import 'brands.dart';
import 'contracts.dart';
import 'freemail_domains.dart';
import 'phishing.dart';

/// Heuristic checks for phishing, spoofing, and suspicious message patterns.
class Heuristics {
  static final RegExp _emailPattern = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static final RegExp _urlLikePattern = RegExp(
    r'(?:https?://)?(?:www\.)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})',
    caseSensitive: false,
  );

  static final RegExp _anchorTagPattern = RegExp(
    r'''<a\s+[^>]*href=["'](https?://[^"']+)["'][^>]*>([\s\S]*?)</a>''',
    caseSensitive: false,
  );

  /// Evaluates heuristics on a normalized message.
  static List<Evidence> evaluate(Normalized normalized) {
    final evidence = <Evidence>[];

    // 1. Disposable sender domain
    if (normalized.senderDomain != null && isDisposableDomain(normalized.senderDomain)) {
      evidence.add(Evidence(
        id: 'disposable_domain',
        weight: 0.35,
        detail: 'Sender domain ${normalized.senderDomain} is a known disposable provider',
      ));
    }

    // 2. Display name spoofing
    final fromHeader = normalized.original.firstHeader('from');
    if (fromHeader != null) {
      _checkDisplayNameSpoofing(fromHeader, normalized.senderDomain, evidence);
    }

    // 3. Link text vs href destination mismatch
    if (normalized.original.htmlBody != null) {
      _checkLinkMismatches(normalized.original.htmlBody!, evidence);
    }

    // 4. Phishing and evasion heuristics
    evidence.addAll(PhishingChecks.evaluate(normalized));

    return evidence;
  }

  static void _checkDisplayNameSpoofing(
    String fromHeader,
    String? senderDomain,
    List<Evidence> evidence,
  ) {
    final nameMatch = RegExp(r'^"?([^"<]+)"?\s*<').firstMatch(fromHeader.trim());
    if (nameMatch == null) return;

    final displayName = nameMatch.group(1)!.trim().toLowerCase();

    // Check if display name contains an email address that doesn't match sender domain
    final emailInName = _emailPattern.firstMatch(displayName);
    if (emailInName != null) {
      final embeddedEmail = emailInName.group(0)!;
      final embeddedDomain = embeddedEmail.split('@').last.toLowerCase();
      if (senderDomain != null && embeddedDomain != senderDomain) {
        evidence.add(Evidence(
          id: 'display_name_spoof_email',
          weight: 0.40,
          detail: 'Display name contains email $embeddedEmail conflicting with sender domain $senderDomain',
        ));
        return;
      }
    }

    // Check if display name claims a sensitive brand but domain doesn't match
    for (final entry in phishedBrands.entries) {
      final brand = entry.key;
      if (displayName.contains(brand)) {
        final senderReg = senderDomain != null ? getRegistrableDomain(senderDomain) : '';
        if (senderDomain == null || !entry.value.contains(senderReg)) {
          evidence.add(Evidence(
            id: 'display_name_brand_spoof',
            weight: 0.35,
            detail: 'Display name claims brand "$brand" but sender domain is $senderDomain',
          ));
          break;
        }
      }
    }
  }

  static void _checkLinkMismatches(String html, List<Evidence> evidence) {
    for (final match in _anchorTagPattern.allMatches(html)) {
      final href = match.group(1)!;
      final text = match.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      final textUrlMatch = _urlLikePattern.firstMatch(text);
      if (textUrlMatch == null) continue;

      final textHost = textUrlMatch.group(1)!.toLowerCase();
      final hrefUri = Uri.tryParse(href);
      if (hrefUri == null || hrefUri.host.isEmpty) continue;

      final hrefHost = hrefUri.host.toLowerCase();

      // Check if text host looks like brand A but href host is brand B
      if (textHost != hrefHost && !hrefHost.endsWith('.$textHost')) {
        evidence.add(Evidence(
          id: 'link_mismatch',
          weight: 0.45,
          detail: 'Link anchor text domain "$textHost" differs from destination host "$hrefHost"',
        ));
        break; // One link mismatch is sufficient evidence
      }
    }
  }
}
