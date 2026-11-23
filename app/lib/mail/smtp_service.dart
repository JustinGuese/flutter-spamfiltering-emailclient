import 'dart:convert';
import 'package:enough_mail/enough_mail.dart';
import 'mail_auth.dart';
import 'account_repository.dart';
import 'imap_service.dart';
import '../app/log.dart';

/// Escaped, line-break-preserving HTML twin of a plain-text body. Quoted text
/// from received mail ends up in here, so it must never be passed through raw.
String textToHtml(String text) =>
    '<div style="white-space:pre-wrap">${const HtmlEscape(HtmlEscapeMode.element).convert(text)}</div>';

class SmtpService {
  final SmtpClient client;

  SmtpService({SmtpClient? client})
      : client = client ?? SmtpClient('datafortress.client', isLogEnabled: false);

  Future<void> sendMail({
    required AccountRecord account,
    required MailAuth auth,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String bodyText,
    String? bodyHtml,
    String? inReplyTo,
    ImapService? imapForSentAppend,
    String? sentFolderPath,
  }) async {
    await client.connectToServer(
      account.smtpHost,
      account.smtpPort,
      isSecure: account.smtpPort == 465,
    );

    if (auth is PasswordMailAuth) {
      await client.authenticate(account.email, auth.password, AuthMechanism.plain);
    } else if (auth is OAuth2MailAuth) {
      await client.authenticate(
        account.email,
        auth.accessToken,
        AuthMechanism.xoauth2,
      );
    }

    final builder = MessageBuilder.prepareMultipartAlternativeMessage(
      plainText: bodyText,
      htmlText: bodyHtml ?? textToHtml(bodyText),
    )
      ..from = [MailAddress(account.displayName, account.email)]
      ..to = to.map((e) => MailAddress('', e.trim())).toList()
      ..cc = cc.map((e) => MailAddress('', e.trim())).toList()
      ..bcc = bcc.map((e) => MailAddress('', e.trim())).toList()
      ..subject = subject;
    if (inReplyTo != null && inReplyTo.isNotEmpty) {
      // Lets the recipient's client thread the reply under the original.
      builder
        ..setHeader('In-Reply-To', inReplyTo)
        ..setHeader('References', inReplyTo);
    }

    final mimeMessage = builder.buildMimeMessage();
    await client.sendMessage(mimeMessage);
    await client.disconnect();

    // APPEND to Sent mailbox if server does not automatically append
    if (imapForSentAppend != null && sentFolderPath != null) {
      try {
        await imapForSentAppend.client.appendMessage(
          mimeMessage,
          targetMailboxPath: sentFolderPath,
          flags: [r'\Seen'],
        );
      } catch (e, st) {
        logError('smtp sent append', e, st);
        // Fallback: ignore append failures if server auto-saves
      }
    }
  }
}
