import 'dart:math' as math;
import 'contracts.dart';
import 'brands.dart';
import 'freemail_domains.dart';

/// Heuristic checks for phishing signals.
class PhishingChecks {
  static const Set<String> _shorteners = {
    'bit.ly', 'tinyurl.com', 't.co', 'goo.gl', 'is.gd', 'ow.ly',
    'cutt.ly', 'rebrand.ly', 'shorturl.at', 'rb.gy', 'tiny.cc',
  };

  static const Set<String> _dangerousExts = {
    '.exe', '.scr', '.js', '.vbs', '.jar', '.bat', '.cmd', '.ps1',
    '.iso', '.img', '.lnk', '.hta', '.html', '.htm', '.svg',
    '.docm', '.xlsm', '.pptm',
  };

  static final RegExp _hiddenStyleTagPattern = RegExp(
    r'''<([a-zA-Z0-9]+)[^>]*style=["'][^"']*(?:display\s*:\s*none|visibility\s*:\s*hidden|font-size\s*:\s*(?:0(?:px)?|1px))[^"']*["'][^>]*>([\s\S]*?)<\/\1>''',
    caseSensitive: false,
  );

  static final RegExp _zeroWidthPattern = RegExp(r'[\u200B\u200C\u200D\uFEFF]');

  static List<Evidence> evaluate(Normalized normalized) {
    final evidence = <Evidence>[];

    _checkPunycode(normalized, evidence);
    _checkLookalike(normalized, evidence);
    _checkReplyToMismatch(normalized, evidence);
    _checkUrlShorteners(normalized, evidence);
    _checkDangerousAttachments(normalized, evidence);
    _checkImageOnly(normalized, evidence);
    _checkHiddenText(normalized, evidence);

    return evidence;
  }

  static void _checkPunycode(Normalized normalized, List<Evidence> evidence) {
    final senderDomain = normalized.senderDomain?.toLowerCase() ?? '';
    if (senderDomain.contains('xn--')) {
      evidence.add(Evidence(
        id: 'punycode_domain',
        weight: 0.40,
        detail: 'Sender domain contains punycode: $senderDomain',
      ));
      return;
    }

    for (final rawUrl in normalized.extractedUrls) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && uri.host.toLowerCase().contains('xn--')) {
        evidence.add(Evidence(
          id: 'punycode_domain',
          weight: 0.40,
          detail: 'Link destination host contains punycode: ${uri.host}',
        ));
        return;
      }
    }
  }

  static void _checkLookalike(Normalized normalized, List<Evidence> evidence) {
    final candidateHosts = <String>{};
    if (normalized.senderDomain != null) {
      candidateHosts.add(getRegistrableDomain(normalized.senderDomain!));
    }
    for (final rawUrl in normalized.extractedUrls) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && uri.host.isNotEmpty) {
        candidateHosts.add(getRegistrableDomain(uri.host));
      }
    }

    final targetSet = lookalikeTargets.toSet();

    for (final host in candidateHosts) {
      if (host.isEmpty) continue;
      if (allBrandDomains.contains(host)) continue;

      final label = host.split('.').first;
      if (targetSet.contains(label)) continue;
      if (label.length < 4) continue;

      final mapped = _mapLookalike(label);
      final isHomoglyph = mapped != label;

      for (final target in lookalikeTargets) {
        final matchesHomoglyph = isHomoglyph && mapped == target;
        final d = _damerauLevenshtein(label, target);
        final matchesDist1 = target.length >= 6 && d == 1;
        final matchesDist2 = target.length >= 9 && d == 2;

        if (matchesHomoglyph || matchesDist1 || matchesDist2) {
          evidence.add(Evidence(
            id: 'lookalike_domain',
            weight: 0.45,
            detail: 'Domain "$host" is a lookalike of brand domain "$target"',
          ));
          return;
        }
      }
    }
  }

  static void _checkReplyToMismatch(Normalized normalized, List<Evidence> evidence) {
    final replyTo = normalized.original.replyTo;
    if (replyTo == null || replyTo.trim().isEmpty) return;

    final replyEmail = _extractEmail(replyTo);
    if (!replyEmail.contains('@')) return;

    final replyDomain = replyEmail.split('@').last.toLowerCase().trim();
    final replyReg = getRegistrableDomain(replyDomain);

    final fromDomain = normalized.senderDomain?.toLowerCase().trim() ?? '';
    final fromReg = getRegistrableDomain(fromDomain);

    if (replyReg.isNotEmpty && fromReg.isNotEmpty && replyReg != fromReg) {
      final fromHeader = normalized.original.firstHeader('from') ?? '';
      final isFreemail = isFreemailDomain(replyDomain);
      final claimsBrand = _claimsAnyBrand(fromHeader, fromDomain);

      if (isFreemail || claimsBrand) {
        evidence.add(Evidence(
          id: 'reply_to_mismatch',
          weight: 0.35,
          detail: 'Reply-To domain "$replyDomain" differs from From domain "$fromDomain"',
        ));
      }
    }
  }

  static void _checkUrlShorteners(Normalized normalized, List<Evidence> evidence) {
    for (final rawUrl in normalized.extractedUrls) {
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && _shorteners.contains(uri.host.toLowerCase())) {
        evidence.add(Evidence(
          id: 'url_shortener',
          weight: 0.20,
          detail: 'Contains link using URL shortener: ${uri.host}',
        ));
        return;
      }
    }
  }

  static void _checkDangerousAttachments(Normalized normalized, List<Evidence> evidence) {
    for (final name in normalized.original.attachmentNames) {
      final lower = name.trim().toLowerCase();
      var dangerous = false;
      for (final ext in _dangerousExts) {
        if (lower.endsWith(ext)) {
          dangerous = true;
          break;
        }
      }

      if (dangerous) {
        evidence.add(Evidence(
          id: 'dangerous_attachment',
          weight: 0.50,
          detail: 'Contains potentially dangerous attachment: $name',
        ));
        return;
      }
    }
  }

  static void _checkImageOnly(Normalized normalized, List<Evidence> evidence) {
    final html = normalized.original.htmlBody;
    if (html != null && html.contains(RegExp(r'<img\b', caseSensitive: false)) && normalized.wordCount < 15) {
      evidence.add(const Evidence(
        id: 'image_only',
        weight: 0.25,
        detail: 'Image-only message with minimal text content',
      ));
    }
  }

  static void _checkHiddenText(Normalized normalized, List<Evidence> evidence) {
    var hiddenWords = 0;
    final html = normalized.original.htmlBody;
    if (html != null) {
      for (final match in _hiddenStyleTagPattern.allMatches(html)) {
        final innerText = match.group(0)!.replaceAll(RegExp(r'<[^>]*>'), ' ');
        final words = innerText
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(w));
        hiddenWords += words.length;
      }
    }

    final raw = (normalized.original.htmlBody ?? '') + normalized.original.textBody;
    final zeroWidthCount = _zeroWidthPattern.allMatches(raw).length;

    if (hiddenWords >= 40 || zeroWidthCount >= 5) {
      evidence.add(Evidence(
        id: 'hidden_text',
        weight: 0.30,
        detail: hiddenWords >= 40
            ? 'Message contains hidden or invisible text styled elements'
            : 'Message contains excessive zero-width characters',
      ));
    }
  }

  static String _extractEmail(String input) {
    final match = RegExp(r'<([^>]+)>').firstMatch(input);
    if (match != null) return match.group(1)!.trim().toLowerCase();
    return input.trim().toLowerCase();
  }

  static bool _claimsAnyBrand(String fromHeader, String fromDomain) {
    final brand = claimedBrand(fromHeader);
    if (brand != null) return true;
    for (final b in phishedBrands.keys) {
      if (isLegitBrandSender(b, fromDomain)) {
        return true;
      }
    }
    return false;
  }

  static String _mapLookalike(String domain) {
    var s = domain.toLowerCase();
    s = s.replaceAll('0', 'o');
    s = s.replaceAll('1', 'l');
    s = s.replaceAll('3', 'e');
    s = s.replaceAll('5', 's');
    s = s.replaceAll('rn', 'm');
    s = s.replaceAll('vv', 'w');
    return s;
  }

  static int _damerauLevenshtein(String a, String b) {
    final la = a.length;
    final lb = b.length;
    if (la == 0) return lb;
    if (lb == 0) return la;

    final d = List.generate(la + 1, (_) => List.filled(lb + 1, 0));
    for (var i = 0; i <= la; i++) d[i][0] = i;
    for (var j = 0; j <= lb; j++) d[0][j] = j;

    for (var i = 1; i <= la; i++) {
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var minVal = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1);
        minVal = math.min(minVal, d[i - 1][j - 1] + cost);

        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          minVal = math.min(minVal, d[i - 2][j - 2] + 1);
        }
        d[i][j] = minVal;
      }
    }
    return d[la][lb];
  }
}
