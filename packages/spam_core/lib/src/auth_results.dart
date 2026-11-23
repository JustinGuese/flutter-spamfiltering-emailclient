/// Verdict outcomes for email authentication checks (RFC 8601).
enum AuthVerdict {
  pass,
  fail,
  softfail,
  neutral,
  none,
  temperror,
  permerror,
  unknown,
}

/// Parsed email authentication results (SPF, DKIM, DMARC).
class AuthResults {
  final String? authservId;
  final AuthVerdict spf;
  final AuthVerdict dkim;
  final AuthVerdict dmarc;
  final String? rawHeader;

  const AuthResults({
    this.authservId,
    this.spf = AuthVerdict.none,
    this.dkim = AuthVerdict.none,
    this.dmarc = AuthVerdict.none,
    this.rawHeader,
  });

  /// Parses Authentication-Results headers for the designated authservId.
  static AuthResults parse(Map<String, List<String>> headers, [String? targetAuthservId]) {
    final authHeaders = _findAuthHeaders(headers);
    if (authHeaders.isEmpty) {
      return const AuthResults();
    }

    String selected = authHeaders.first;
    String? matchedAuthservId;

    if (targetAuthservId != null && targetAuthservId.isNotEmpty) {
      final targetLower = targetAuthservId.toLowerCase();
      for (final h in authHeaders) {
        final id = _extractAuthservId(h);
        if (id != null && id.toLowerCase() == targetLower) {
          selected = h;
          matchedAuthservId = id;
          break;
        }
      }
    }

    matchedAuthservId ??= _extractAuthservId(selected);

    return AuthResults(
      authservId: matchedAuthservId,
      spf: _extractVerdict(selected, 'spf'),
      dkim: _extractVerdict(selected, 'dkim'),
      dmarc: _extractVerdict(selected, 'dmarc'),
      rawHeader: selected,
    );
  }

  static List<String> _findAuthHeaders(Map<String, List<String>> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authentication-results') {
        return entry.value;
      }
    }
    return const [];
  }

  static String? _extractAuthservId(String header) {
    final parts = header.trim().split(RegExp(r'[;\s]'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.replaceAll('"', '').trim();
    }
    return null;
  }

  static AuthVerdict _extractVerdict(String header, String method) {
    final regex = RegExp('$method\\s*=\\s*([a-zA-Z]+)', caseSensitive: false);
    final match = regex.firstMatch(header);
    if (match == null) return AuthVerdict.none;

    final val = match.group(1)!.toLowerCase();
    switch (val) {
      case 'pass':
        return AuthVerdict.pass;
      case 'fail':
        return AuthVerdict.fail;
      case 'softfail':
        return AuthVerdict.softfail;
      case 'neutral':
        return AuthVerdict.neutral;
      case 'none':
        return AuthVerdict.none;
      case 'temperror':
        return AuthVerdict.temperror;
      case 'permerror':
        return AuthVerdict.permerror;
      default:
        return AuthVerdict.unknown;
    }
  }
}
