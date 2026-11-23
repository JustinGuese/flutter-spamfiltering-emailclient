/// Authentication seam for mail protocols (IMAP/SMTP).
/// Supports simple password credentials and OAuth2 bearer tokens.
sealed class MailAuth {
  const MailAuth();

  String get authType;
}

class PasswordMailAuth extends MailAuth {
  final String password;
  const PasswordMailAuth(this.password);

  @override
  String get authType => 'password';
}

class OAuth2MailAuth extends MailAuth {
  final String accessToken;
  final String? refreshToken;
  const OAuth2MailAuth(this.accessToken, {this.refreshToken});

  @override
  String get authType => 'oauth2';
}
