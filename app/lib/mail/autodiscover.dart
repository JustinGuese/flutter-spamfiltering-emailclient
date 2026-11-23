/// Status entry for ledger-style autodiscovery progress.
class AutodiscoverLine {
  final String text;
  final bool isDone;
  final bool isSuccess;

  const AutodiscoverLine({
    required this.text,
    this.isDone = false,
    this.isSuccess = false,
  });
}

/// Autodiscover configuration result.
class DiscoveredConfig {
  final String imapHost;
  final int imapPort;
  final bool imapTls;
  final String smtpHost;
  final int smtpPort;
  final bool smtpTls;

  const DiscoveredConfig({
    required this.imapHost,
    required this.imapPort,
    required this.imapTls,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpTls,
  });
}

/// Helper to discover IMAP and SMTP configurations from email domain.
class MailAutodiscover {
  static const Map<String, DiscoveredConfig> _knownProviders = {
    'gmail.com': DiscoveredConfig(
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapTls: true,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
      smtpTls: true,
    ),
    'yahoo.com': DiscoveredConfig(
      imapHost: 'imap.mail.yahoo.com',
      imapPort: 993,
      imapTls: true,
      smtpHost: 'smtp.mail.yahoo.com',
      smtpPort: 465,
      smtpTls: true,
    ),
    'icloud.com': DiscoveredConfig(
      imapHost: 'imap.mail.me.com',
      imapPort: 993,
      imapTls: true,
      smtpHost: 'smtp.mail.me.com',
      smtpPort: 587,
      smtpTls: true,
    ),
    'outlook.com': DiscoveredConfig(
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      imapTls: true,
      smtpHost: 'smtp.office365.com',
      smtpPort: 587,
      smtpTls: true,
    ),
  };

  static DiscoveredConfig? resolveKnown(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return null;
    return _knownProviders[parts[1].toLowerCase().trim()];
  }

  static DiscoveredConfig defaultForDomain(String domain) {
    return DiscoveredConfig(
      imapHost: 'imap.$domain',
      imapPort: 993,
      imapTls: true,
      smtpHost: 'smtp.$domain',
      smtpPort: 587,
      smtpTls: true,
    );
  }
}
