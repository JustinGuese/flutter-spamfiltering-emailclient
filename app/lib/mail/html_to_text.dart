/// Turns an HTML mail body into readable plain text for the reader and for the
/// list preview. Mail that has only an HTML part (most notifications and
/// newsletters) has no text part to show, so this is its only readable form.
/// Nothing is fetched and nothing is executed: tags are simply dropped.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'<(head|style|script|title)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|table|h[1-6]|ul|ol|blockquote|section|article)\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</(li|td|th)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = _decodeEntities(s)
      .replaceAll(RegExp('[​‌‍⁠﻿­͏]'), '')
      .replaceAll(' ', ' ')
      .replaceAll('\r', '');
  final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim());
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

const _named = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'copy': '©', 'reg': '®', 'trade': '™', 'hellip': '…', 'ndash': '–',
  'mdash': '—', 'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”',
  'bull': '•', 'middot': '·', 'euro': '€', 'pound': '£', 'laquo': '«', 'raquo': '»',
  'zwnj': '', 'zwj': '',
};

String _decodeEntities(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final code = e[1] == 'x' || e[1] == 'X' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code == null || code <= 0 || code > 0x10FFFF ? '' : String.fromCharCode(code);
      }
      return _named[e.toLowerCase()] ?? m.group(0)!;
    });
