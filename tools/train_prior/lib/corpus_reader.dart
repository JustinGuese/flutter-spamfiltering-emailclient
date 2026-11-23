import 'dart:io';
import 'package:spam_core/spam_core.dart';

/// Reads RFC822 / EML email messages from disk.
class CorpusReader {
  /// Reads a single email file and parses it into a Message.
  static Message readFile(File file) {
    final raw = file.readAsStringSync();
    return parseRawEmail(raw);
  }

  /// Recursively reads all message files in a directory.
  static List<Message> readDirectory(Directory dir) {
    if (!dir.existsSync()) return const [];

    final messages = <Message>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && !entity.path.endsWith('.DS_Store')) {
        try {
          messages.add(readFile(entity));
        } catch (_) {
          // Ignore unparseable or corrupted corpus entries
        }
      }
    }
    return messages;
  }

  /// Parses raw email string into headers and body.
  static Message parseRawEmail(String raw) {
    final headers = <String, List<String>>{};
    final lines = raw.split(RegExp(r'\r?\n'));

    var headerEndIndex = -1;
    String? currentHeaderName;
    final currentHeaderValue = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Empty line marks end of headers
      if (line.trim().isEmpty) {
        headerEndIndex = i;
        if (currentHeaderName != null) {
          headers.putIfAbsent(currentHeaderName.toLowerCase(), () => []).add(currentHeaderValue.toString().trim());
        }
        break;
      }

      // Continuation line (starts with space or tab)
      if ((line.startsWith(' ') || line.startsWith('\t')) && currentHeaderName != null) {
        currentHeaderValue.write(' ${line.trim()}');
        continue;
      }

      // New header line
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        if (currentHeaderName != null) {
          headers.putIfAbsent(currentHeaderName.toLowerCase(), () => []).add(currentHeaderValue.toString().trim());
          currentHeaderValue.clear();
        }
        currentHeaderName = line.substring(0, colonIndex).trim();
        currentHeaderValue.write(line.substring(colonIndex + 1).trim());
      }
    }

    final body = (headerEndIndex != -1 && headerEndIndex < lines.length - 1)
        ? lines.sublist(headerEndIndex + 1).join('\n')
        : '';

    final toHeaders = headers['to'] ?? const [];
    final recipientAddrs = <String>[];
    for (final to in toHeaders) {
      recipientAddrs.addAll(to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }

    return Message(
      headers: headers,
      textBody: body,
      recipientAddrs: recipientAddrs,
    );
  }
}
