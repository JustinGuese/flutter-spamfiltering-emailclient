import 'dart:convert';
import 'package:enough_mail/enough_mail.dart';
import 'attachments.dart';
import 'mail_auth.dart';
import 'account_repository.dart';
import 'imap_service.dart';
import '../app/log.dart';
import '../db/database.dart';

/// Escaped, line-break-preserving HTML twin of a plain-text body. Quoted text
/// from received mail ends up in here, so it must never be passed through raw.
String textToHtml(String text) =>
    '<div style="white-space:pre-wrap">${const HtmlEscape(HtmlEscapeMode.element).convert(text)}</div>';

/// The MIME message for a send. Plain text + HTML twin; with attachments it is
/// `multipart/mixed` holding that pair and one part per file.
MimeMessage buildOutgoingMessage({
  required MailAddress from,
  required List<String> to,
  List<String> cc = const [],
  List<String> bcc = const [],
  required String subject,
  required String bodyText,
  String? bodyHtml,
  String? inReplyTo,
  List<LoadedAttachment> attachments = const [],
}) {
  final htmlText = bodyHtml ?? textToHtml(bodyText);
  final MessageBuilder builder;
  if (attachments.isEmpty) {
    builder = MessageBuilder.prepareMultipartAlternativeMessage(plainText: bodyText, htmlText: htmlText);
  } else {
    builder = MessageBuilder.prepareMultipartMixedMessage()
      ..addMultipartAlternative(plainText: bodyText, htmlText: htmlText);
    for (final a in attachments) {
      builder.addBinary(a.bytes, MediaType.fromText(a.mimeType), filename: a.fileName);
    }
  }
  builder
    ..from = [from]
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
  return builder.buildMimeMessage();
}

class SmtpService {
  final SmtpClient client;
  final AppDatabase? db;

  SmtpService({SmtpClient? client, this.db})
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
    List<LoadedAttachment> attachments = const [],
    ImapService? imapForSentAppend,
    String? sentFolderPath,
  }) async {
    final mimeMessage = buildOutgoingMessage(
      from: MailAddress(account.displayName, account.email),
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: bodyText,
      bodyHtml: bodyHtml,
      inReplyTo: inReplyTo,
      attachments: attachments,
    );
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

    try {
      await client.sendMessage(mimeMessage);
    } finally {
      try {
        await client.disconnect();
      } catch (e) {
        logError('smtp disconnect', e); // the send's own error is the one to report
      }
    }

    // Upsert To/Cc recipients into contacts with trust_level = 1
    if (db != null) {
      final recipients = [...to, ...cc];
      for (final raw in recipients) {
        final email = _extractAddress(raw).toLowerCase();
        if (email.isNotEmpty && email.contains('@')) {
          db!.db.execute('''
            INSERT OR IGNORE INTO contacts (id, email, trust_level)
            VALUES (?, ?, 1)
          ''', [email, email]);
        }
      }
    }

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

  static String _extractAddress(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'<([^>]+)>').firstMatch(trimmed);
    if (match != null) return match.group(1)!.trim();
    return trimmed;
  }
}
