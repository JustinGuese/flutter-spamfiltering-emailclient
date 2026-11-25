import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import 'mail_auth.dart';
import 'account_repository.dart';

class ImapFolderInfo {
  final String name;
  final String serverPath;
  final String? specialUse; // inbox, sent, drafts, trash, junk, archive
  final int? uidValidity;
  final int? nextUid;
  final int messagesCount;

  /// False for pure containers such as Gmail's "[Gmail]" (`\Noselect`), which
  /// the server refuses to SELECT.
  final bool selectable;

  const ImapFolderInfo({
    required this.name,
    required this.serverPath,
    this.specialUse,
    this.uidValidity,
    this.nextUid,
    this.messagesCount = 0,
    this.selectable = true,
  });
}

class ImapService {
  final ImapClient client;

  ImapService({ImapClient? client})
      : client = client ?? ImapClient(isLogEnabled: false);

  /// Connects and logs in. Both steps are time-limited: pointing this at a
  /// server that is not an IMAP server (e.g. an SMTP host) never answers with
  /// an IMAP greeting, and without a limit the sync would hang forever.
  Future<void> connectAndAuthenticate(
    AccountRecord account,
    MailAuth auth, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final where = '${account.imapHost}:${account.imapPort}';
    try {
      await client
          .connectToServer(
            account.imapHost,
            account.imapPort,
            isSecure: account.imapPort == 993,
          )
          .timeout(timeout);

      if (auth is PasswordMailAuth) {
        await client.login(account.email, auth.password).timeout(timeout);
      } else if (auth is OAuth2MailAuth) {
        await client.authenticateWithOAuth2(account.email, auth.accessToken).timeout(timeout);
      }
    } on TimeoutException {
      try {
        await client.disconnect();
      } catch (_) {}
      throw TimeoutException(
        'No IMAP response from $where within ${timeout.inSeconds}s. '
        'Check the IMAP server and port (imap.… on 993, not the SMTP server).',
      );
    }
  }

  Future<List<ImapFolderInfo>> listSpecialUseFolders() async {
    // Recursive: Sent, Drafts, Trash and Spam live under "[Gmail]/" (and
    // "INBOX." on some servers); a top-level-only LIST never returns them.
    final mailboxes = await client.listMailboxes(recursive: true);
    final result = <ImapFolderInfo>[];
    for (final box in mailboxes) {
      String? specialUse;
      final flags = box.flags.map((f) => f.name.toLowerCase()).toList();
      if (flags.contains(r'\inbox') || box.name.toLowerCase() == 'inbox') {
        specialUse = 'inbox';
      } else if (flags.contains(r'\sent') || box.name.toLowerCase().contains('sent')) {
        specialUse = 'sent';
      } else if (flags.contains(r'\drafts') || box.name.toLowerCase().contains('draft')) {
        specialUse = 'drafts';
      } else if (flags.contains(r'\trash') || box.name.toLowerCase().contains('trash')) {
        specialUse = 'trash';
      } else if (flags.contains(r'\junk') || box.name.toLowerCase().contains('junk') || box.name.toLowerCase().contains('spam')) {
        specialUse = 'junk';
      } else if (flags.contains(r'\archive') || box.name.toLowerCase().contains('archive')) {
        specialUse = 'archive';
      } else if (flags.contains(r'\all') || flags.contains(r'\flagged') || flags.contains(r'\important')) {
        // Gmail's virtual "All Mail" / "Starred" / "Important" views: huge
        // aliases of mail that already lives elsewhere, so never auto-synced.
        specialUse = 'virtual';
      }

      result.add(ImapFolderInfo(
        name: box.name,
        serverPath: box.path,
        specialUse: specialUse,
        messagesCount: box.messagesExists,
        selectable: !box.isNotSelectable,
      ));
    }
    return result;
  }

  Mailbox? _selected;

  Future<Mailbox> selectMailbox(String path) async {
    return _selected = await client.selectMailboxByPath(path);
  }

  /// The newest [count] messages of the selected mailbox (a first sync).
  /// Fetched by sequence number from the top, so it is the latest mail, not
  /// the oldest.
  Future<List<MimeMessage>> fetchRecent({int count = 100}) async {
    if (_selected?.messagesExists == 0) return const [];
    final res = await client.fetchRecentMessages(
      messageCount: count,
      criteria: _criteria,
    );
    return res.messages;
  }

  /// Messages with a UID greater than [lastUid]. `N:*` always includes the
  /// newest message even when its UID is below N, so that is filtered out.
  Future<List<MimeMessage>> fetchNewerThan(int lastUid) async {
    final res = await client.uidFetchMessagesByCriteria(
      '${lastUid + 1}:* $_criteria',
    );
    return res.messages.where((m) => (m.uid ?? 0) > lastUid).toList();
  }

  /// The newest [count] messages with a UID below [beforeUid]: the next page
  /// of older mail when the user scrolls past what is stored. Empty once the
  /// start of the mailbox is reached.
  Future<List<MimeMessage>> fetchOlderThan(int beforeUid, {int count = 50}) async {
    if (beforeUid <= 1) return const [];
    final uids = (await searchUids('UID 1:${beforeUid - 1}')).where((u) => u < beforeUid).toList()
      ..sort((a, b) => b.compareTo(a));
    return fetchByUids(uids.take(count).toList());
  }

  /// UIDs in the selected mailbox matching an IMAP `SEARCH` [criteria] string
  /// (e.g. `TEXT "invoice" UNSEEN`). The server does the matching.
  Future<List<int>> searchUids(String criteria) async {
    final res = await client.uidSearchMessages(searchCriteria: criteria);
    return res.matchingSequence?.toList() ?? const [];
  }

  /// The full messages with these UIDs from the selected mailbox.
  Future<List<MimeMessage>> fetchByUids(List<int> uids) async {
    if (uids.isEmpty) return const [];
    final res = await client.uidFetchMessages(
      MessageSequence.fromIds(uids, isUid: true),
      _criteria,
    );
    return res.messages;
  }

  static const _criteria = '(UID FLAGS BODY.PEEK[])';

  Future<void> setFlags(int uid, List<String> flags, {bool add = true}) async {
    // `uid` is a real IMAP UID, so every command here must be the UID variant.
    final seq = MessageSequence.fromId(uid, isUid: true);
    await client.uidStore(
      seq,
      flags,
      action: add ? StoreAction.add : StoreAction.remove,
    );
  }

  Future<void> moveMessage(int uid, String targetPath) async {
    final seq = MessageSequence.fromId(uid, isUid: true);
    await client.uidCopy(seq, targetMailboxPath: targetPath);
    await client.uidStore(seq, [r'\Deleted'], action: StoreAction.add);
    await client.expunge();
  }

  Future<void> disconnect() async {
    if (client.isLoggedIn) {
      await client.logout();
    }
  }
}
