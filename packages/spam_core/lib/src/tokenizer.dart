import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'contracts.dart';

/// Tokenizer generating body words, OSB bigrams, and prefixed header tokens.
class Tokenizer {
  static const int osbWindow = 4;

  static final RegExp _wordFilterPattern = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _hasLetterPattern = RegExp(r'\p{L}', unicode: true);

  static final RegExp _cjkRunPattern = RegExp(
    r'[\u3040-\u309F\u30A0-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F\u0E00-\u0E7F]+',
  );

  static final RegExp _singleCharSepPattern = RegExp(
    r'(?:^|(?<=[^\p{L}\p{N}]))([\p{L}\p{N}](?:[.\-_][\p{L}\p{N}]){2,})(?:$|(?=[^\p{L}\p{N}]))',
    unicode: true,
  );

  static const Map<String, String> _leetspeakMap = {
    '0': 'o',
    '1': 'i',
    '3': 'e',
    '4': 'a',
    '5': 's',
    '7': 't',
    '@': 'a',
    '\$': 's',
  };

  /// Extracts all tokens from a normalized message.
  static List<String> tokens(Normalized normalized) {
    final result = <String>{};

    // 1. Body words
    final words = normalized.tokenText
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && _wordFilterPattern.hasMatch(w))
        .map((w) => w.toLowerCase())
        .toList();

    for (final w in words) {
      if (w.length <= 30) {
        result.add(w);
      }
      final deob = _deobfuscate(w);
      if (deob != null) {
        result.add('deob:$deob');
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

    // 3. CJK/Thai/Hangul/Kana character bigrams
    _extractCjkBigrams(normalized.tokenText, result);

    // 4. Prefixed header tokens
    final original = normalized.original;

    // Subject
    final subject = original.firstHeader('subject') ?? '';
    final subjWords = subject
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && _wordFilterPattern.hasMatch(w));
    for (final sw in subjWords) {
      if (sw.length <= 30) {
        result.add('subj:$sw');
      }
      final deob = _deobfuscate(sw);
      if (deob != null) {
        result.add('deob:$deob');
      }
    }
    if (subject.isNotEmpty) {
      _extractCjkBigrams(subject, result);
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

  static String? _deobfuscate(String word) {
    if (!_hasLetterPattern.hasMatch(word)) {
      return null;
    }

    var deob = word;
    var changed = false;

    // 1. Remove dots/hyphens/underscores between single characters (e.g. "c.a.s.i.n.o" -> "casino")
    if (_singleCharSepPattern.hasMatch(deob)) {
      deob = deob.replaceAllMapped(_singleCharSepPattern, (match) {
        changed = true;
        return match.group(1)!.replaceAll(RegExp(r'[.\-_]'), '');
      });
    }

    // 2. Leet substitutions: 0->o, 1->i, 3->e, 4->a, 5->s, 7->t, @->a, $->s
    // Skip if word is a standard email address
    final isEmail = word.contains('@') &&
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(word);

    if (!isEmail) {
      final sb = StringBuffer();
      for (var i = 0; i < deob.length; i++) {
        final ch = deob[i];
        final repl = _leetspeakMap[ch];
        if (repl != null) {
          sb.write(repl);
          changed = true;
        } else {
          sb.write(ch);
        }
      }
      deob = sb.toString();
    }

    if (!changed || deob == word) {
      return null;
    }

    // Normalized word must be valid (length >= 2, contains letters)
    if (deob.length >= 2 && deob.length <= 30 && _hasLetterPattern.hasMatch(deob)) {
      return deob;
    }
    return null;
  }

  static void _extractCjkBigrams(String text, Set<String> result) {
    for (final match in _cjkRunPattern.allMatches(text)) {
      final run = match.group(0)!;
      final runes = run.runes.toList();
      for (var i = 0; i < runes.length - 1; i++) {
        result.add(String.fromCharCodes([runes[i], runes[i + 1]]));
      }
    }
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
