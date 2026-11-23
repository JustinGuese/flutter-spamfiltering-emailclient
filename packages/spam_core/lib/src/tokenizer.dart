import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'contracts.dart';

/// Tokenizer generating body words, OSB bigrams, and prefixed header tokens.
class Tokenizer {
  static const int osbWindow = 4;

  /// Extracts all tokens from a normalized message.
  static List<String> tokens(Normalized normalized) {
    final result = <String>{};

    // 1. Body words
    final words = normalized.cleanedText
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && RegExp(r'[a-zA-Z0-9]').hasMatch(w))
        .map((w) => w.toLowerCase())
        .toList();

    for (final w in words) {
      if (w.length <= 30) {
        result.add(w);
      }
    }

    // 2. OSB bigrams (rspamd / CRM114 style)
    for (var i = 0; i < words.length; i++) {
      for (var d = 1; d <= osbWindow && (i + d) < words.length; d++) {
        final prefix = '_' * (d - 1);
        final bigram = '${words[i]}+$prefix${words[i + d]}';
        result.add(bigram);
      }
    }

    // 3. Prefixed header tokens
    final original = normalized.original;

    // Subject
    final subject = original.firstHeader('subject') ?? '';
    final subjWords = subject
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && RegExp(r'[a-zA-Z0-9]').hasMatch(w));
    for (final sw in subjWords) {
      if (sw.length <= 30) {
        result.add('subj:$sw');
      }
    }

    // Sender domain
    if (normalized.senderDomain != null) {
      result.add('from-dom:${normalized.senderDomain}');
    }

    // URL domains
    for (final rawUrl in normalized.extractedUrls) {
      final u = Uri.tryParse(rawUrl);
      if (u != null && u.host.isNotEmpty) {
        result.add('url-dom:${u.host.toLowerCase()}');
      }
    }

    // Content-Type
    final ct = original.firstHeader('content-type');
    if (ct != null) {
      final mime = ct.split(';').first.trim().toLowerCase();
      if (mime.isNotEmpty) {
        result.add('ct:$mime');
      }
    }

    // X-Mailer / User-Agent
    final mailer = original.firstHeader('x-mailer') ?? original.firstHeader('user-agent');
    if (mailer != null) {
      final cleanedMailer = mailer.split(RegExp(r'[/\s]')).first.trim().toLowerCase();
      if (cleanedMailer.isNotEmpty && cleanedMailer.length <= 20) {
        result.add('x-mailer:$cleanedMailer');
      }
    }

    // List headers
    final listUnsub = original.firstHeader('list-unsubscribe');
    result.add(listUnsub != null ? 'list-unsub:present' : 'list-unsub:absent');

    final listId = original.firstHeader('list-id');
    if (listId != null) {
      result.add('list-id:present');
    }

    final precedence = original.firstHeader('precedence');
    if (precedence != null) {
      result.add('precedence:${precedence.trim().toLowerCase()}');
    }

    return result.toList();
  }

  /// Hashes a token string to a positive 63-bit integer.
  static int hashToken(String token) {
    final bytes = sha256.convert(utf8.encode(token)).bytes;
    var result = 0;
    for (var i = 0; i < 8; i++) {
      result = (result << 8) | bytes[i];
    }
    return result & 0x7FFFFFFFFFFFFFFF;
  }
}
