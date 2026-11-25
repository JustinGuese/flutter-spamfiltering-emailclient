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

  static const fullscreenEnter = 'Full screen';
  static const fullscreenExit = 'Exit full screen (Esc)';

  static const emptyBody ='(This message has no text content.)';
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

  // Attachments
  static const attachmentsTitle = 'Attachments';
  static const attachmentsLoading = 'Loading attachments…';
  static const attachmentsFailed = 'Could not load the attachments: {error}';
  static const attachmentRetry = 'Retry';
  static const attachmentSave = 'Save as…';
  static const attachmentSaved = 'Saved to {path}';
  static const attachmentDownloadFailed = 'Could not download "{name}": {error}';
  static const attachmentNoApp = 'No app on this device can open "{name}". Use Save as… instead.';
  static const attachmentRunnableTitle = 'This file can run code';
  static const attachmentRunnableBody =
      '"{name}" is a program or script. Opening it could run it on your device. Save it instead, and only run it if you trust the sender.';
  static const attachmentCancel = 'Cancel';
  static const attachTooBig = 'Attachments are limited to {mb} MB in total. "{name}" was not added.';
  static const attachPickFailed = 'Could not open the file picker.';
  static const attachUnreadable = 'Could not read "{name}".';
  static const attachRemove = 'Remove {name}';
  static const forwardAttachmentsFailed = 'Could not load the attachments to forward: {error}';
  static const sendNeedsRecipient = 'Add at least one recipient.';
  static const sendFailed = 'Could not send: {error}';
  static const sending = 'Sending…';

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
  static const setupContinueGoogle = 'Continue with Google';
  static const setupContinueMicrosoft = 'Continue with Microsoft';
  static const setupOrDivider = 'or configure with password';
  static const setupGoogleNotConfigured =
      'Google sign-in is not configured in this build';
  static const setupMicrosoftNotConfigured =
      'Microsoft sign-in is not configured in this build';
  static const accountReconnect = 'Reconnect';
  static const accountReconnecting = 'Reconnecting…';
  static const accountReconnectSuccess = 'Account reconnected successfully';
  static const accountNeedsReauth = 'Needs re-authentication';

  static const settingsAccounts = 'Accounts';
  static const settingsNotifications = 'Notifications';
  static const settingsPrivacy = 'Privacy';
  static const settingsPro = 'Pro';
  static const settingsAppearance = 'Appearance';
  static const settingsLegal = 'Legal';

  // Notifications
  static const notifyModeTitle = 'New mail notifications';
  static const notifyModeOff = 'Off';
  static const notifyModeInstant = 'On every new message';
  static const notifyModeEvery5min = 'Bundled every 5 minutes';
  static const notifyModeHourly = 'Hourly summary';
  static const notifyBlockedSubtitle =
      'Notifications are blocked in system settings';
  static const notifySendTest = 'Send test notification';
  static const notifyTestTitle = 'Test notification';
  static const notifyTestBody =
      'This is a test notification from DataFortress Mail.';
  static const notifyPrimingTitle = 'Know when mail arrives';
  static const notifyPrimingBody =
      'Get a notification for new mail in your inbox. It shows the sender and subject only, never the message text. Mail the filter flags as spam stays quiet. You can change this anytime in Settings.';
  static const notifyPrimingAccept = 'Turn on notifications';
  static const notifyPrimingDecline = 'Not now';

  static const checkoutUnavailable =
      'The upgrade screen could not be opened. This build may not include subscriptions.';
  static const checkoutDesktopUnavailable =
      "Subscriptions can't be started from the desktop app yet. Use the iOS, Android or macOS app.";

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

  static const protectionTitle = 'Your protection';
  static const protectionClose = 'Close';
  static const protectionTabStory = 'Protection';
  static const protectionTabCaught = 'Caught';
  static const protectionTabLearned = 'Learned';

  static const stageNoFilter = 'No filter';
  static const stageFilter = 'Our app';
  static const stageCommunity = 'App + community';
  static const stagePro = 'Pro';
  static const storyReachInbox = 'spam reaching your inbox';
  static const storyNoFilterBody =
      'Without a filter, every one of these would be sitting in your inbox.';
  static String storyFilterBody(int n) =>
      'The on-device filter stops $n of them. Nothing leaves your device to do it.';
  static String storyCommunityBody(int n) => n == 0
      ? 'The community blocklist is on. None of your spam needed it so far; it covers what your filter has not seen yet.'
      : 'Anonymous community fingerprints stop $n more that the filter alone would have let through.';
  static const storyProBody =
      'Pro does not catch more on this device. It makes every other device you own start as trained as this one.';
  static const storyLegendFilter = 'caught by your filter';
  static const storyLegendCommunity = 'caught by the community';
  static const storyLegendInbox = 'reaches your inbox';
  static String storySquareScale(int k) => 'Each square is about $k messages.';
  static const storyReplay = 'Replay';
  static const storyBasis =
      'Counted from the spam on this device. The "community" step re-scores each message without the blocklist signal.';
  static const storySampleTitle = 'Sample data';
  static const storySampleBody =
      'Nothing has been caught on this device yet, so this shows an example. It switches to your own numbers as mail is filtered.';

  static const proPanelTitle = 'A new device, with and without Pro';
  static const proPanelFree = 'Free';
  static const proPanelProLabel = 'Pro';
  static const proPanelFreeBody = 'starts from zero and learns again';
  static const proPanelProBody = 'starts already trained, from your other devices';
  static const proPanelWords = 'words learned';
  static const proPanelFootnote =
      'Free already includes the full filter and community protection. Pro adds encrypted sync only.';
  static const proPanelActive = 'Pro is active: your filter follows you to every device.';
  static const proCtaTitle = 'Train once, protected everywhere';
  static const proCtaBody = 'Pro keeps what this filter has learned in sync across your phone and computers.';

  static const caughtEmpty = 'No spam caught yet.';
  static const caughtByFilter = 'Filter';
  static const caughtByCommunity = 'Community';
  static const caughtByYou = 'You';
  static const caughtNoSubject = '(no subject)';
  static String caughtShowing(int shown, int total) =>
      shown >= total ? messageCount(total) : 'Latest $shown of $total';

  static const learnedHeadline = 'words learned';
  static const learnedBody =
      'Each message you mark teaches the filter which words go with spam and which with real mail.';
  static const learnedSpamWords = 'lean spam';
  static const learnedHamWords = 'lean real mail';
  static const learnedCorrections = 'messages you marked by hand';
  static const learnedBlocklist = 'community fingerprints on this device';
  static const learnedPrivacy =
      'The filter stores a hash for each word, not the word and not the message. Nothing here can be read back into your mail.';

  static const loadOlder = 'Load older mail';
  static const loadingOlder = 'Loading older mail…';
  static const loadOlderFailed = "Couldn't load older mail. Tap to retry.";

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

  // Notifications
  static String notifySummaryTitle(int count) =>
      '$count new messages';
  static String notifyBundledBody(List<String> senders) =>
      senders.join(', ');

  // Accounts
  static const accountNoAccounts = 'No accounts configured.';
  static const accountAdd = 'Add account';
  static const accountAddAccount = 'Add Account';
}
