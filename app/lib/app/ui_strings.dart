/// Copy for the redesigned surfaces (kept apart from the older AppStrings so the
/// two can evolve independently; everything user-facing still lives in strings).
abstract final class UiStrings {
  static const sidebarMailboxes = 'Mailboxes';
  static const sidebarFilter = 'Your filter';
  static const compose = 'Compose';
  static const statCaught = 'caught as spam';
  static const statLearned = 'words learned';
  static const statCommunity = 'community signals';

  static const filterAll = 'All';
  static const filterInbox = 'Inbox';
  static const filterNewsletters = 'Newsletters';
  static const filterSpam = 'Spam';

  static const pillSpam = 'Spam';
  static const pillNewsletter = 'Newsletter';
  static const pillPossible = 'Possible spam';

  static const to = 'To';
  static const toMe = 'to me';

  static const ledgerSpam = 'Likely spam';
  static const ledgerPossible = 'Possible spam — your call';
  static const ledgerNewsletter = 'Looks like a newsletter';
  static const ledgerClean = 'Looks fine';
  static const ledgerScoreCaption = 'spam score';
  static const ledgerWhy = 'Why this verdict';
  static const ledgerHideWhy = 'Hide details';
  static const ledgerFooter = 'Every signal above is computed on this device from this message.';

  static const signalBayes = 'Word statistics';
  static const signalAuth = 'Sender authentication';
  static const signalCommunity = 'Community reports';
  static const signalHeuristic = 'Link & lookalike checks';
  static const signalHam = 'Your history';
  static const signalAi = 'On-device model';

  static const emptyBody = '(This message has no text content.)';
  static const emptyReaderTitle = 'Nothing selected.';
  static const emptyReaderBody = 'Pick a message, or let the keyboard drive.';
  static const keyNext = 'next / previous';
  static const keySpam = 'mark as spam';
  static const keyNewsletter = 'mark as newsletter';
  static const keyInbox = 'back to inbox';

  static const fieldFrom = 'From';
  static const fieldTo = 'To';
  static const fieldCc = 'Cc';
  static const fieldBcc = 'Bcc';
  static const fieldSubject = 'Subject';
  static const send = 'Send';
  static const attachSoon = 'Attachments are not available yet';

  static const setupHeadline = 'Connect your mail.';
  static const setupSub = 'Any IMAP account. Your messages are read here, on this device, and nowhere else.';
  static const setupPromise1 = 'Credentials stay in your system keychain';
  static const setupPromise2 = 'Mail is cached locally, never mirrored to us';
  static const setupPromise3 = 'No account with us is needed';
  static const setupLedgerTitle = 'Server ledger';
  static const setupUseAuto = 'Use auto-discover';
  static const removeAccountTitle = 'Remove this account?';
  static const removeAccountBody =
      'Its saved password and the mail cached on this device are deleted. Nothing is deleted on the mail server, and what your filter has learned is kept.';
  static const removeAccountConfirm = 'Remove';
  static const removeAccountCancel = 'Cancel';
  static const setupImapLooksSmtp = 'The IMAP server looks like an SMTP server: are the two server fields swapped?';
  static const setupConnecting = 'Connecting…';
  static const setupStoreFailed =
      'Could not save the password to the system keychain, so the account was not added. Make sure a keychain (e.g. gnome-keyring) is running and unlocked.';

  static const artSubject = 'CONGRATULATIONS!!! You have been selected';
  static const artSender = 'Prize Desk';
  static const artVerdictInbox = 'Inbox';
  static const artVerdictNewsletter = 'Newsletter';
  static const artVerdictSpam = 'Spam';
  static const artStamp = 'SPAM';
  static const artLearned = 'Learned · similar mail moves too';
  static const artHashCaption = 'No names. No addresses. Just fingerprints.';
  static const artKindBody = 'body';
  static const artKindUrl = 'link';
  static const artKindDomain = 'sender';

  static const settingsAccounts = 'Accounts';
  static const settingsPrivacy = 'Privacy';
  static const settingsPro = 'Pro';
  static const settingsAppearance = 'Appearance';

  static const upsellEyebrow = 'Pro';
  static const upsellHeadline = 'Your filter, on every device.';
  static const upsellSub =
      'Everything you teach the spam filter follows you to every phone and computer you use.';
  static const upsellFreeNote =
      'Mail, spam filtering and community protection stay free. Pro only adds sync.';
  static const upsellPoint1 =
      'Train once, protected everywhere. Each message you mark as spam or newsletter teaches your other devices too.';
  static const upsellPoint2 =
      'A new phone or laptop starts out already knowing your mail, instead of learning from zero.';
  static const upsellPoint3 =
      'Encrypted before it leaves this device. We only ever store ciphertext.';
  static const upsellPoint4 =
      'The key is yours: 24 recovery words. Lose them and we cannot restore your filter.';
  static const proSectionWhy =
      'Free already includes the full spam filter. Pro keeps what it has learned in sync across all your devices:';
  static const proSectionBullet1 = 'Train once, every device benefits';
  static const proSectionBullet2 = 'New devices start with your trained filter';
  static const proSectionBullet3 = 'End-to-end encrypted, we only store ciphertext';
  static const proSectionActive = 'Your Pro entitlement keeps your trained filter in sync across your devices.';
  static const upsellAnnual = 'Annual';
  static const upsellRenewal = 'Renews every year until you cancel in your store settings.';
  static const upsellLater = 'Maybe later';

  static const emptyListTitle = 'All quiet.';
  static const emptyListBody = 'Nothing in this view.';

  static String messageCount(int n) => n == 1 ? '1 message' : '$n messages';
  static String unreadCount(int n) => '$n unread';

  static String signalLabel(String id) => switch (id) {
        'bayes' => signalBayes,
        'auth' => signalAuth,
        'community' => signalCommunity,
        'heuristic' => signalHeuristic,
        'ham' => signalHam,
        'ai' => signalAi,
        _ => id,
      };
}
