import 'dart:convert';
import 'dart:io';
import 'package:enough_mail/enough_mail.dart';
import 'package:spam_core/spam_core.dart';

/// Reads RFC822 / EML email messages from disk.
///
/// Messages are MIME-decoded with enough_mail, the parser the app's sync uses,
/// so the prior is trained on the same text the app classifies (decoded
/// text/plain, else the HTML part) instead of raw base64 and multipart markup.
class CorpusReader {
  /// Reads a single email file and parses it into a Message.
  static Message readFile(File file) {
    final bytes = file.readAsBytesSync();
    // Corpus mail is often Latin-1; never drop a message over its encoding.
    final raw = utf8.decode(bytes, allowMalformed: true);
    return parseRawEmail(raw);
  }

  /// Recursively reads all message files in a directory.
  static List<Message> readDirectory(Directory dir) {
    if (!dir.existsSync()) return const [];

    final messages = <Message>[];
    for (final entity in dir.listSync(recursive: true, followLinks: true)) {
      if (entity is File && !entity.path.endsWith('.DS_Store') && !entity.path.endsWith('/cmds')) {
        try {
          messages.add(readFile(entity));
        } catch (_) {
          // Ignore unparseable or corrupted corpus entries
        }
      }
    }
    return messages;
  }

  /// Parses a raw RFC 822 message the way the app's sync builds its input.
  static Message parseRawEmail(String raw) {
    final mime = MimeMessage.parseFromText(raw);

    final headers = <String, List<String>>{};
    for (final h in mime.headers ?? const <Header>[]) {
      final value = h.value;
      if (value != null) headers.putIfAbsent(h.name, () => []).add(value);
    }
    final subject = mime.decodeSubject();
    if (subject != null) headers['Subject'] = [subject];

    final html = mime.decodeTextHtmlPart();
    final text = (mime.decodeTextPlainPart() ?? '').trim();

    final attachmentNames = <String>[];
    for (final info in mime.findContentInfo(disposition: ContentDisposition.attachment)) {
      final name = info.fileName;
      if (name != null && name.isNotEmpty) attachmentNames.add(name);
    }

    final recipientAddrs = (mime.to ?? const <MailAddress>[]).map((a) => a.email).toList();

    return Message(
      headers: headers,
      textBody: text,
      htmlBody: html,
      recipientAddrs: recipientAddrs,
      attachmentNames: attachmentNames,
    );
  }
}
