import 'contracts.dart';
import 'freemail_domains.dart';

/// Normalizes email messages for classification and fingerprinting.
class Normalizer {
  static final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');
  static final RegExp _urlPattern = RegExp(
    r'https?://[a-zA-Z0-9.\-_~:/?#\[\]@!$&()*+,;=%]+',
    caseSensitive: false,
  );
  static final RegExp _hrefPattern = RegExp(
    r'''href\s*=\s*["'](https?://[^"']+)["']''',
    caseSensitive: false,
  );
  static final RegExp _greetingPattern = RegExp(
    r'^\s*(?:hi|hello|dear|hey|good\s+(?:morning|afternoon|evening)|greetings|to:?)\b[^\n]*[,\.!:]?',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _emailExtractPattern = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  /// Normalizes a message: strips recipient name/address + greeting,
  /// folds case/whitespace, and extracts URLs and sender domain.
  static Normalized normalize(Message message) {
    // 1. Determine raw text
    String rawText = message.textBody;
    if (rawText.trim().isEmpty && message.htmlBody != null) {
      rawText = _stripHtml(message.htmlBody!);
    }

    // 2. Extract recipient details to strip
    final recipientTokens = _collectRecipientTokens(message);

    // 3. Strip greetings from the beginning of lines/body
    String cleaned = rawText.replaceAll(_greetingPattern, '');

    // 4. Strip recipient tokens
    for (final token in recipientTokens) {
      if (token.length >= 3) {
        final escaped = RegExp.escape(token);
        cleaned = cleaned.replaceAll(RegExp(escaped, caseSensitive: false), ' ');
      }
    }

    // 5. Lowercase and fold whitespace
    cleaned = _foldWhitespace(cleaned.toLowerCase());

    // 6. Extract URLs (both from text and HTML)
    final urls = <String>{};
    for (final match in _urlPattern.allMatches(rawText)) {
      final u = match.group(0);
      if (u != null) urls.add(_cleanUrl(u));
    }
    if (message.htmlBody != null) {
      for (final match in _hrefPattern.allMatches(message.htmlBody!)) {
        final u = match.group(1);
        if (u != null) urls.add(_cleanUrl(u));
      }
    }

    // 7. Extract sender domain
    final senderDomain = _extractSenderDomain(message);
    final isFreemail = isFreemailDomain(senderDomain);

    // 8. Word count
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && RegExp(r'[a-zA-Z0-9]').hasMatch(w))
        .toList();

    return Normalized(
      original: message,
      cleanedText: cleaned,
      cleanedHtml: message.htmlBody,
      extractedUrls: urls.toList(),
      senderDomain: senderDomain,
      isSenderFreemail: isFreemail,
      wordCount: words.length,
    );
  }

  static Set<String> _collectRecipientTokens(Message message) {
    final tokens = <String>{};
    final rawAddrs = <String>[...message.recipientAddrs];

    for (final header in ['to', 'cc', 'delivered-to', 'x-original-to']) {
      rawAddrs.addAll(message.getHeader(header));
    }

    for (final raw in rawAddrs) {
      for (final match in _emailExtractPattern.allMatches(raw)) {
        final fullEmail = match.group(0)!;
        tokens.add(fullEmail);
        final parts = fullEmail.split('@');
        if (parts.isNotEmpty) {
          tokens.add(parts[0]);
          final subParts = parts[0].split(RegExp(r'[._\-]'));
          for (final sp in subParts) {
            if (sp.length >= 3) tokens.add(sp);
          }
        }
      }

      // Display name in "Name <email>"
      final nameMatch = RegExp(r'^"?([^"<]+)"?\s*<').firstMatch(raw.trim());
      if (nameMatch != null) {
        final name = nameMatch.group(1)!.trim();
        if (name.length >= 3) {
          tokens.add(name);
          for (final word in name.split(RegExp(r'\s+'))) {
            if (word.length >= 3) tokens.add(word);
          }
        }
      }
    }
    return tokens;
  }

  static String _stripHtml(String html) {
    String text = html
        .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(_htmlTagPattern, ' ');

    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");

    return text;
  }

  static String _foldWhitespace(String input) {
    return input.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _cleanUrl(String raw) {
    var u = raw.trim();
    final hashIndex = u.indexOf('#');
    if (hashIndex != -1) u = u.substring(0, hashIndex);
    final qIndex = u.indexOf('?');
    if (qIndex != -1) u = u.substring(0, qIndex);
    return u;
  }

  static String? _extractSenderDomain(Message message) {
    final fromHeader = message.firstHeader('from') ?? message.firstHeader('return-path');
    if (fromHeader == null) return null;

    final match = _emailExtractPattern.firstMatch(fromHeader);
    if (match != null) {
      final email = match.group(0)!;
      final parts = email.split('@');
      if (parts.length == 2) {
        return parts[1].toLowerCase().trim();
      }
    }
    return null;
  }
}
