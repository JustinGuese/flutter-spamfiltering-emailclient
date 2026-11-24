/// Centralized user-facing strings for DataFortress Mail.
/// No inline literals are allowed in UI widgets.
class AppStrings {
  // Brand & Navigation
  static const appName = 'DataFortress Mail';
  static const navMail = 'Mail';
  static const navSearch = 'Search';
  static const navSettings = 'Settings';

  // Search
  static const searchHint = 'Search mail';
  static const searchClear = 'Clear';
  static const searchIncludeSpam = 'Include spam';
  static const searchPromptTitle = 'Find anything.';
  static const searchPromptBody =
      'Searches subjects, senders and message text on this device, then asks your mail server for older mail.';
  static const searchTryTitle = 'Narrow it down';
  static const searchExamples = [
    'from:amazon',
    'subject:invoice',
    'is:unread',
    'has:attachment',
    'after:2026-01-01',
    '"exact phrase"',
  ];
  static const searchNoResultsTitle = 'Nothing found.';
  static const searchNoResultsBody = 'Try fewer words, or include spam.';
  static const searchServerSearching = 'Searching your mail server…';
  static const searchServerNone = 'Nothing more on the server';
  static String searchServerFailed(String? reason) => reason == null || reason.isEmpty
      ? 'Server search failed. Showing mail on this device.'
      : 'Server search failed: $reason';
  static const searchServerRetry = 'Retry';
  static String searchServerAdded(int n) => 'Added $n from the server';
  static String searchResultCount(int n, int limit) =>
      n >= limit ? 'Best $n matches' : (n == 1 ? '1 match' : '$n matches');

  // Mailboxes
  static const folderInbox = 'Inbox';
  static const folderSent = 'Sent';
  static const folderDrafts = 'Drafts';
  static const folderArchive = 'Archive';
  static const folderJunk = 'Junk';
  static const folderTrash = 'Trash';
  static const folderAllMail = 'All Mail';
  static const emptyMailbox = 'No messages in this folder';

  // Classification & Verdicts
  static const verdictInbox = 'Inbox';
  static const verdictNewsletter = 'Newsletter';
  static const verdictSpam = 'Spam';
  static const verdictUnsure = 'Possible Spam';
  static const verdictLearned = 'Learned';
  static const undoAction = 'Undo';
  static const markAsSpam = 'Mark as Spam';
  static const markAsNewsletter = 'Mark as Newsletter';
  static const markAsInbox = 'Move to Inbox';
  static const verdictMovedFormat = 'Learned · %d other from this sender';
  static const verdictLearnedOnly = 'Learned from this message';

  // Evidence Sheet
  static const evidenceTitle = 'Signal Ledger';
  static const evidenceSubtitle = 'Why this was classified';
  static const evidenceBayes = 'Bayesian token analysis';
  static const evidenceDmarc = 'DMARC authentication';
  static const evidenceSpf = 'SPF validation';
  static const evidenceDkim = 'DKIM signature';
  static const evidenceCommunity = 'Community blocklist match';
  static const evidenceLinkMismatch = 'Mismatched hyperlink target';
  static const evidenceAiScore = 'On-device neural score';
  static const evidenceContribution = 'Weight';

  // Reader & Sanitizer
  static const remoteImagesBlocked = 'Remote images blocked';
  static const loadImagesOnce = 'Load once';
  static const alwaysAllowImages = 'Always for this sender';
  static const headerFrom = 'From';
  static const headerTo = 'To';
  static const headerCc = 'Cc';
  static const headerBcc = 'Bcc';
  static const headerDate = 'Date';
  static const headerSubject = 'Subject';
  static const actionReply = 'Reply';
  static const actionReplyAll = 'Reply All';
  static const actionForward = 'Forward';
  // Text written into the body of a reply / forward ({placeholders} are filled by the draft builder).
  static const replyAttribution = 'On {date}, {sender} wrote:';
  static const forwardDivider = '---------- Forwarded message ----------';
  static const actionDelete = 'Delete';
  static const actionArchive = 'Archive';
  static const noMessageSelected = 'Select a message to read';

  // Compose
  static const composeTitle = 'New Message';
  static const composeToHint = 'Recipients';
  static const composeCcHint = 'Cc';
  static const composeBccHint = 'Bcc';
  static const composeShowCc = 'Add Cc';
  static const composeShowBcc = 'Add Bcc';
  static const composeSubjectHint = 'Subject';
  static const composeBodyHint = 'Write your message...';
  static const composeSend = 'Send';
  static const composeDiscard = 'Discard';
  static const composeDraftSaved = 'Saved to Drafts';
  static const composeAttach = 'Attach file';

  // Account Setup
  static const setupTitle = 'Add Mail Account';
  static const setupEmail = 'Email address';
  static const setupPassword = 'Password or App Password';
  static const setupDisplayName = 'Your Name';
  static const setupImapHost = 'IMAP Server';
  static const setupImapPort = 'Port';
  static const setupSmtpHost = 'SMTP Server';
  static const setupSmtpPort = 'Port';
  static const setupConnect = 'Connect Account';
  static const setupAutoDetecting = 'Auto-detecting server settings...';
  static const setupManualConfig = 'Manual configuration';
  static const setupAppPasswordNote =
      'Yahoo and iCloud require an app-specific password.';
  static const setupSuccess = 'Account connected successfully';
  static const setupFailed = 'Failed to connect. Check credentials.';

  // Settings
  static const settingsTitle = 'Settings';
  static const settingsAccounts = 'Mail Accounts';
  static const settingsSpamFilter = 'Spam Filter & Privacy';
  static const settingsAppearance = 'Appearance';
  static const settingsDensity = 'List Density';
  static const densityComfortable = 'Comfortable (72dp)';
  static const densityCompact = 'Compact (52dp)';
  static const settingsTheme = 'Theme';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const themeSystem = 'System';
  static const settingsSharing = 'Anonymous Community Shield';
  static const settingsSharingSub =
      'Share anonymous 64-bit cryptographic fingerprints of spam to protect the community.';
  static const settingsBlocklistVer = 'Blocklist version';
  static const settingsLastReport = 'Last report sent';
  static const settingsPremium = 'DataFortress Pro';
  static const settingsLegal = 'Legal & Privacy Policy';
  static const settingsVersion = 'Version 1.0.0';

  // Community Sharing Notice
  static const sharingNoticeTitle = 'Anonymous Community Protection';
  static const sharingNoticeBody =
      'When you mark an email as spam, anonymous 64-bit cryptographic fingerprints (no text, no personal IDs, no IP address) are shared to protect other users.';
  static const sharingNoticeTurnOff = 'Turn off sharing';
  static const sharingNoticeDismiss = 'Got it';
  static const sharingNoticeLearnMore = 'Learn more';
  static const sharingNoticeLearnMoreTitle = 'Community Protection Details';
  static const sharingNoticeLearnMoreBody =
      'Only 64-bit cryptographic hashes of URLs, body word sequences (MinHash), and domain signatures are submitted. Your email address, message text, IP address, and personal identifiers are never stored or transmitted.';

  // Onboarding
  static const onbPage1Title = 'The Ledger Desk';
  static const onbPage1Body =
      'A dense, quiet email client engineered for focus and absolute local privacy.';
  static const onbPage2Title = 'Learns On-Device';
  static const onbPage2Body =
      'The Bayesian engine inspects signals on your hardware. Your tokens stay on your disk.';
  static const onbPage3Title = 'Collective Shield';
  static const onbPage3Body =
      'Block spam campaigns anonymously with zero tracking IDs, zero account linkage, and zero IP logs.';

  // Premium / Funnel & Filter Sync
  static const proTitle = 'DataFortress Pro';
  static const proSubtitle = 'Encrypted multi-device filter sync.';
  static const proUpgrade = 'Upgrade to Pro';
  static const proRestore = 'Restore Purchases';
  static const proActive = 'Pro Active';
  static const proSyncFeature = 'End-to-End Encrypted Filter Sync';
  static const proNeuralFeature = 'On-Device Advanced Neural Scorer';
  static const proMonthly = '\$4.99 / month';
  static const proAnnual = '\$39.99 / year';

  static const settingsFilterSync = 'End-to-End Filter Sync';
  static const settingsFilterSyncSub =
      'Encrypted cross-device synchronization of filter training counters.';
  static const syncRecoveryCode = 'Show Recovery Words';
  static const syncAddDevice = 'Add Device / Import Recovery Words';
  static const syncEnterWordsHint = 'Enter 24 recovery words separated by spaces';
  static const syncImportSuccess = 'Recovery key imported successfully';
  static const syncImportFailed = 'Failed to import recovery words';
  static const syncClose = 'Close';
  static const syncImport = 'Import';
  static const syncCancel = 'Cancel';
  static const syncEnabled = 'Sync Enabled';
  static const syncWordsCopied = 'Recovery words copied';
}
