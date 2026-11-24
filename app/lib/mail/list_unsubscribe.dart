/// RFC 8058 and RFC 2369 List-Unsubscribe header parser.
///
/// Pure Dart, no I/O.
library;

/// Parsed unsubscribe targets from email headers.
class UnsubscribeTargets {
  /// HTTPS URL for RFC 8058 One-Click unsubscribe.
  /// Only populated when [oneClickUrl] is https AND List-Unsubscribe-Post
  /// header matches 'List-Unsubscribe=One-Click' (case-insensitive).
  final Uri? oneClickUrl;

  /// Validated mailto target for RFC 2369 mailto unsubscribe.
  final MailtoTarget? mailto;

  const UnsubscribeTargets({this.oneClickUrl, this.mailto});

  /// Whether at least one valid unsubscribe target is available.
  bool get hasTarget => oneClickUrl != null || mailto != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnsubscribeTargets &&
          runtimeType == other.runtimeType &&
          oneClickUrl == other.oneClickUrl &&
          mailto == other.mailto;

  @override
  int get hashCode => Object.hash(oneClickUrl, mailto);

  @override
  String toString() =>
      'UnsubscribeTargets(oneClickUrl: $oneClickUrl, mailto: $mailto)';
}

/// A validated mailto target for unsubscribing via email.
class MailtoTarget {
  final String to;
  final String subject;
  final String body;

  const MailtoTarget({
    required this.to,
    required this.subject,
    required this.body,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MailtoTarget &&
          runtimeType == other.runtimeType &&
          to == other.to &&
          subject == other.subject &&
          body == other.body;

  @override
  int get hashCode => Object.hash(to, subject, body);

  @override
  String toString() =>
      'MailtoTarget(to: $to, subject: $subject, body: $body)';
}

/// Parses the List-Unsubscribe and List-Unsubscribe-Post headers.
///
/// Rules:
/// - Parser returns [oneClickUrl] only when scheme is https AND
///   [listUnsubscribePost] contains 'List-Unsubscribe=One-Click' (case-insensitive).
/// - Plain http URLs are ignored.
/// - Handles multiple '<...>' entries and folded whitespace across lines.
/// - mailto with cc/bcc/CRLF/header injection/multiple recipients -> mailto is null.
/// - Extracts subject/body from mailto URI if present (decodes percent-encoding,
///   caps lengths at 200 chars), defaulting subject and body to 'unsubscribe'.
UnsubscribeTargets parseListUnsubscribe(
  String? listUnsubscribe,
  String? listUnsubscribePost,
) {
  if (listUnsubscribe == null || listUnsubscribe.trim().isEmpty) {
    return const UnsubscribeTargets();
  }

  // Extract entries enclosed in <...>
  final entries = <String>[];
  final matches = RegExp(r'<([^>]+)>', dotAll: true).allMatches(listUnsubscribe);
  if (matches.isNotEmpty) {
    for (final m in matches) {
      final content = m.group(1)?.trim();
      if (content != null && content.isNotEmpty) {
        entries.add(content);
      }
    }
  } else if (!listUnsubscribe.contains('<')) {
    // Fallback for header values without angle brackets
    for (final part in listUnsubscribe.split(',')) {
      final content = part.trim();
      if (content.isNotEmpty) {
        entries.add(content);
      }
    }
  }

  Uri? oneClickUrl;
  MailtoTarget? mailto;

  final isOneClickPost = _isOneClick(listUnsubscribePost);

  for (final raw in entries) {
    if (raw.toLowerCase().startsWith('mailto:')) {
      mailto ??= _parseMailto(raw);
    } else if (isOneClickPost && oneClickUrl == null) {
      // Strip any internal whitespace/folding in URL
      final clean = raw.replaceAll(RegExp(r'\s+'), '');
      final uri = Uri.tryParse(clean);
      if (uri != null &&
          uri.hasScheme &&
          uri.scheme.toLowerCase() == 'https' &&
          uri.host.isNotEmpty) {
        oneClickUrl = uri;
      }
    }
  }

  return UnsubscribeTargets(oneClickUrl: oneClickUrl, mailto: mailto);
}

/// Validates whether the List-Unsubscribe-Post header equals or contains
/// 'List-Unsubscribe=One-Click' (case-insensitive).
bool _isOneClick(String? post) {
  if (post == null) return false;
  final cleaned = post
      .replaceAll(RegExp(r'^list-unsubscribe-post:\s*', caseSensitive: false), '')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .trim()
      .toLowerCase();

  return cleaned == 'list-unsubscribe=one-click' ||
      cleaned.split(';').map((s) => s.trim()).contains('list-unsubscribe=one-click');
}

/// Parses and strictly validates a mailto URI string.
///
/// Returns null if:
/// - CRLF or %0d / %0a is present anywhere (header injection prevention)
/// - Any cc, bcc, or unauthorized header params are present
/// - Multiple recipients exist in path or parameters
/// - Email recipient format is invalid
MailtoTarget? _parseMailto(String raw) {
  // Reject CRLF, null bytes, or %0d / %0a anywhere (header injection protection)
  if (raw.contains('\r') ||
      raw.contains('\n') ||
      raw.contains('\x00') ||
      raw.toLowerCase().contains('%0d') ||
      raw.toLowerCase().contains('%0a') ||
      raw.toLowerCase().contains('%00')) {
    return null;
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.toLowerCase() != 'mailto') {
    return null;
  }

  // Reject if any query parameter other than subject and body is present (e.g. cc, bcc, to)
  // or if duplicate keys are present.
  String? rawSubject;
  String? rawBody;
  for (final entry in uri.queryParametersAll.entries) {
    final key = entry.key.toLowerCase();
    if (key != 'subject' && key != 'body') {
      return null;
    }
    if (entry.value.length > 1) {
      return null;
    }
    if (key == 'subject') {
      rawSubject = entry.value.first;
    } else if (key == 'body') {
      rawBody = entry.value.first;
    }
  }

  var to = Uri.decodeComponent(uri.path).trim();
  if (to.startsWith('<') && to.endsWith('>')) {
    to = to.substring(1, to.length - 1).trim();
  }

  // Exactly one recipient: no commas, no semicolons, no whitespace, no angle brackets
  if (to.isEmpty ||
      to.contains(',') ||
      to.contains(';') ||
      to.contains(' ') ||
      to.contains('<') ||
      to.contains('>') ||
      to.contains('\r') ||
      to.contains('\n')) {
    return null;
  }

  // Validate email address structure: user@domain.tld
  final atIndex = to.indexOf('@');
  if (atIndex <= 0 || atIndex != to.lastIndexOf('@') || atIndex == to.length - 1) {
    return null;
  }
  final domain = to.substring(atIndex + 1);
  if (!domain.contains('.') || domain.startsWith('.') || domain.endsWith('.')) {
    return null;
  }

  // Subject and body with length cap (200 characters) and defaults
  String subject = 'unsubscribe';
  String body = 'unsubscribe';

  if (rawSubject != null && rawSubject.trim().isNotEmpty) {
    final s = rawSubject.trim();
    if (s.contains('\r') || s.contains('\n')) return null;
    subject = s.length > 200 ? s.substring(0, 200) : s;
  }

  if (rawBody != null && rawBody.trim().isNotEmpty) {
    final b = rawBody.trim();
    if (b.contains('\r') || b.contains('\n')) return null;
    body = b.length > 200 ? b.substring(0, 200) : b;
  }

  return MailtoTarget(to: to, subject: subject, body: body);
}
