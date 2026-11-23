import '../app/strings.dart';

enum ComposeMode { reply, replyAll, forward }

/// Everything a prefilled compose window needs. Plain data, no Flutter.
class ComposeDraft {
  final String? accountId;
  final List<String> to;
  final List<String> cc;
  final String subject;
  final String body;

  /// `Message-ID` of the mail being answered, for the In-Reply-To / References
  /// headers. Null for forwards (a forward starts a new thread).
  final String? inReplyTo;

  const ComposeDraft({
    this.accountId,
    this.to = const [],
    this.cc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
  });
}

/// "Re: x" for replies, "Fwd: x" for forwards; never stacks "Re: Re:".
String prefixedSubject(String subject, ComposeMode mode) {
  final prefix = mode == ComposeMode.forward ? 'Fwd' : 'Re';
  final s = subject.trim();
  final existing = RegExp('^$prefix:\\s*', caseSensitive: false);
  // "Fw:" is what some clients write for a forward.
  final alt = mode == ComposeMode.forward ? RegExp(r'^fw:\s*', caseSensitive: false) : null;
  if (existing.hasMatch(s) || (alt?.hasMatch(s) ?? false)) return s;
  return '$prefix: $s';
}

/// Builds the draft for Reply / Reply All / Forward of a stored message.
///
/// [sender], [to] and [cc] are bare addresses as stored in `messages`.
/// [accountEmail] is the mailbox the message arrived in; it is never put back
/// in the recipient lists. [dateText] is the already-formatted original date.
ComposeDraft buildDraft({
  required ComposeMode mode,
  required String accountId,
  required String accountEmail,
  required String sender,
  required List<String> to,
  required List<String> cc,
  required String subject,
  required String dateText,
  required String textBody,
  String? messageId,
}) {
  final own = accountEmail.trim().toLowerCase();
  final seen = <String>{own};
  List<String> unique(Iterable<String> addrs) {
    final out = <String>[];
    for (final a in addrs.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      if (seen.add(a.toLowerCase())) out.add(a);
    }
    return out;
  }

  final subjectLine = prefixedSubject(subject, mode);

  if (mode == ComposeMode.forward) {
    final body = '\n\n${AppStrings.forwardDivider}\n'
        '${AppStrings.headerFrom}: $sender\n'
        '${AppStrings.headerDate}: $dateText\n'
        '${AppStrings.headerSubject}: $subject\n'
        '${AppStrings.headerTo}: ${to.join(', ')}\n'
        '${cc.isEmpty ? '' : '${AppStrings.headerCc}: ${cc.join(', ')}\n'}'
        '\n$textBody';
    return ComposeDraft(accountId: accountId, subject: subjectLine, body: body);
  }

  // Answering a message you sent yourself (Sent folder) goes to its recipients.
  final fromMe = sender.trim().toLowerCase() == own;
  final replyTo = unique(fromMe ? to : [sender]);
  final replyCc = mode == ComposeMode.replyAll ? unique([if (!fromMe) ...to, ...cc]) : <String>[];

  final attribution =
      AppStrings.replyAttribution.replaceAll('{date}', dateText).replaceAll('{sender}', sender);
  final quoted = textBody.split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n');

  return ComposeDraft(
    accountId: accountId,
    to: replyTo,
    cc: replyCc,
    subject: subjectLine,
    body: '\n\n$attribution\n$quoted',
    inReplyTo: messageId,
  );
}
