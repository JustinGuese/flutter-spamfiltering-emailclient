import '../mail/imap_service.dart';
import '../app/log.dart';

/// Manages standard and custom IMAP keyword flags for spam and newsletters.
class ImapFlagsManager {
  static const flagJunk = r'$Junk';
  static const flagNotJunk = r'$NotJunk';
  static const flagNewsletter = r'$Newsletter';

  /// Sets IMAP keywords for spam classification.
  static Future<void> markSpam(ImapService imap, int uid) async {
    try {
      await imap.setFlags(uid, [flagJunk], add: true);
      await imap.setFlags(uid, [flagNotJunk], add: false);
    } catch (e, st) {
      logError('imap markSpam', e, st);
    }
  }

  /// Sets IMAP keywords for inbox/ham classification.
  static Future<void> markHam(ImapService imap, int uid) async {
    try {
      await imap.setFlags(uid, [flagNotJunk], add: true);
      await imap.setFlags(uid, [flagJunk], add: false);
    } catch (e, st) {
      logError('imap markHam', e, st);
    }
  }

  /// Sets IMAP keywords for newsletter if supported by the server, otherwise fallback to local.
  static Future<void> markNewsletter(
    ImapService imap,
    int uid, {
    bool serverSupportsPermanentFlags = false,
  }) async {
    if (serverSupportsPermanentFlags) {
      try {
        await imap.setFlags(uid, [flagNewsletter], add: true);
        await imap.setFlags(uid, [flagJunk], add: false);
      } catch (e, st) {
        logError('imap markNewsletter', e, st);
      }
    }
  }
}
