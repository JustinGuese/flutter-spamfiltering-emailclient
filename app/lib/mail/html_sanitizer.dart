/// Result of HTML sanitization with remote image detection.
class SanitizedContent {
  final String html;
  final bool hasRemoteImages;
  final List<String> remoteImageUrls;

  const SanitizedContent({
    required this.html,
    required this.hasRemoteImages,
    this.remoteImageUrls = const [],
  });
}

/// Sanitizer stripping <script>, <style>, <form>, <object>, <iframe>,
/// inline on* handlers, javascript: links, and remote image URLs.
class HtmlSanitizer {
  static final _dangerousTags = RegExp(
    r'<\s*(script|style|form|iframe|object|embed|applet)[^>]*>[\s\S]*?<\s*\/\s*\1\s*>',
    caseSensitive: false,
  );

  static final _dangerousSelfClosing = RegExp(
    r'<\s*(script|style|form|iframe|object|embed|applet)[^>]*\/?>',
    caseSensitive: false,
  );

  static final _eventHandlers = RegExp(
    r'\s+on[a-zA-Z]+\s*=\s*(["\x27][^"\x27]*["\x27]|[^\s>]+)',
    caseSensitive: false,
  );

  static final _jsHrefs = RegExp(
    r'''href\s*=\s*["']?\s*javascript:[^"'>\s]+''',
    caseSensitive: false,
  );

  static final _imgSrcRegex = RegExp(
    r'''<img\s+[^>]*src\s*=\s*["'](https?:\/\/[^"']+)["'][^>]*>''',
    caseSensitive: false,
  );

  static SanitizedContent sanitize(
    String rawHtml, {
    bool blockRemoteImages = true,
  }) {
    var cleaned = rawHtml
        .replaceAll(_dangerousTags, '')
        .replaceAll(_dangerousSelfClosing, '')
        .replaceAll(_eventHandlers, '')
        .replaceAll(_jsHrefs, 'href="#"');

    final remoteUrls = <String>[];
    if (blockRemoteImages) {
      cleaned = cleaned.replaceAllMapped(_imgSrcRegex, (match) {
        final url = match.group(1);
        if (url != null) {
          remoteUrls.add(url);
        }
        return '<img src="data:image/svg+xml;utf8,<svg xmlns=\'http://www.w3.org/2000/svg\' width=\'24\' height=\'24\'><rect width=\'24\' height=\'24\' fill=\'%23e4ded4\'/></svg>" alt="[Image blocked]" />';
      });
    }

    return SanitizedContent(
      html: cleaned,
      hasRemoteImages: remoteUrls.isNotEmpty,
      remoteImageUrls: remoteUrls,
    );
  }
}
