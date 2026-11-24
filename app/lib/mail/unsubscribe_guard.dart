import 'dart:io';

/// Abstraction for DNS lookup to enable test injection.
typedef DnsLookup = Future<List<InternetAddress>> Function(String host);

/// Result of evaluating a URI for SSRF / safety.
enum GuardResult {
  safe,
  unsafeScheme,
  hasUserInfo,
  unsafePort,
  blockedHost,
  privateIp,
  dnsFailed,
}

/// Guard to validate URLs before making HTTP requests (RFC 8058 One-Click).
///
/// SSRF / URL safety:
/// - HTTPS only.
/// - No userinfo.
/// - Default port 443 only (or no port specified, meaning 443).
/// - Host not localhost, .local, .internal, or IP literals in:
///   - Loopback (127.0.0.0/8, ::1)
///   - Private (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
///   - Link-local (169.254.0.0/16, fe80::/10)
///   - CGNAT (100.64.0.0/10)
///   - ULA (fc00::/7)
/// - Hostname is resolved via DNS resolver and every resolved address must be public.
class UnsubscribeGuard {
  final DnsLookup dnsLookup;

  const UnsubscribeGuard({DnsLookup? dnsLookup})
      : dnsLookup = dnsLookup ?? InternetAddress.lookup;

  /// Validates [uri] against SSRF and safety rules.
  /// Returns `true` if safe, `false` otherwise.
  Future<bool> isSafe(Uri uri) async {
    final result = await check(uri);
    return result == GuardResult.safe;
  }

  /// Checks [uri] and returns specific [GuardResult].
  Future<GuardResult> check(Uri uri) async {
    // 1. HTTPS only
    if (uri.scheme.toLowerCase() != 'https') {
      return GuardResult.unsafeScheme;
    }

    // 2. No userinfo
    if (uri.userInfo.isNotEmpty) {
      return GuardResult.hasUserInfo;
    }

    // 3. Port: default 443 only (or no port specified, which implies 443 for https)
    if (uri.hasPort && uri.port != 443) {
      return GuardResult.unsafePort;
    }

    final host = uri.host.trim();
    if (host.isEmpty) {
      return GuardResult.blockedHost;
    }

    // 4. Host checks: localhost, .local, .internal
    final lowerHost = host.toLowerCase();
    if (lowerHost == 'localhost' ||
        lowerHost.endsWith('.localhost') ||
        lowerHost.endsWith('.local') ||
        lowerHost.endsWith('.internal')) {
      return GuardResult.blockedHost;
    }

    // Check if host itself is an IP literal
    final directIp = InternetAddress.tryParse(host);
    if (directIp != null) {
      if (isPrivateOrRestricted(directIp)) {
        return GuardResult.privateIp;
      }
      return GuardResult.safe;
    }

    // 5. Hostname resolved via DNS resolver and EVERY resolved IP must be public
    List<InternetAddress> addresses;
    try {
      addresses = await dnsLookup(host);
    } catch (_) {
      return GuardResult.dnsFailed;
    }

    if (addresses.isEmpty) {
      return GuardResult.dnsFailed;
    }

    for (final addr in addresses) {
      if (isPrivateOrRestricted(addr)) {
        return GuardResult.privateIp;
      }
    }

    return GuardResult.safe;
  }

  /// Evaluates whether [addr] belongs to a private, loopback, link-local,
  /// CGNAT, ULA, or otherwise restricted IP range.
  static bool isPrivateOrRestricted(InternetAddress addr) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) {
      return true;
    }

    final bytes = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4) {
      return _isRestrictedIpv4(bytes);
    } else if (addr.type == InternetAddressType.IPv6) {
      return _isRestrictedIpv6(bytes);
    }
    return true;
  }

  static bool _isRestrictedIpv4(List<int> bytes) {
    if (bytes.length != 4) return true;
    final b0 = bytes[0];
    final b1 = bytes[1];

    // 0.0.0.0/8 (Current network)
    if (b0 == 0) return true;

    // 10.0.0.0/8 (Private)
    if (b0 == 10) return true;

    // 100.64.0.0/10 (CGNAT / Shared Address Space: 100.64.0.0 - 100.127.255.255)
    // 64 is 01000000, 127 is 01111111 (b1 & 0xC0 == 0x40)
    if (b0 == 100 && (b1 & 0xC0) == 64) return true;

    // 127.0.0.0/8 (Loopback)
    if (b0 == 127) return true;

    // 169.254.0.0/16 (Link-local)
    if (b0 == 169 && b1 == 254) return true;

    // 172.16.0.0/12 (Private: 172.16.0.0 - 172.31.255.255)
    // 16 is 00010000, 31 is 00011111 (b1 & 0xF0 == 0x10)
    if (b0 == 172 && (b1 & 0xF0) == 16) return true;

    // 192.0.0.0/24 (IETF Protocol Assignments)
    if (b0 == 192 && b1 == 0 && bytes[2] == 0) return true;

    // 192.0.2.0/24 (TEST-NET-1)
    if (b0 == 192 && b1 == 0 && bytes[2] == 2) return true;

    // 192.168.0.0/16 (Private)
    if (b0 == 192 && b1 == 168) return true;

    // 198.18.0.0/15 (Benchmarking: 198.18.0.0 - 198.19.255.255)
    if (b0 == 198 && (b1 & 0xFE) == 18) return true;

    // 198.51.100.0/24 (TEST-NET-2)
    if (b0 == 198 && b1 == 51 && bytes[2] == 100) return true;

    // 203.0.113.0/24 (TEST-NET-3)
    if (b0 == 203 && b1 == 0 && bytes[2] == 113) return true;

    // 224.0.0.0/4 (Multicast: 224-239)
    if (b0 >= 224 && b0 <= 239) return true;

    // 240.0.0.0/4 (Reserved / Future Use) + 255.255.255.255 (Broadcast)
    if (b0 >= 240) return true;

    return false;
  }

  static bool _isRestrictedIpv6(List<int> bytes) {
    if (bytes.length != 16) return true;

    // ::1 (Loopback)
    bool isAllZeroExceptLast = true;
    for (int i = 0; i < 15; i++) {
      if (bytes[i] != 0) {
        isAllZeroExceptLast = false;
        break;
      }
    }
    if (isAllZeroExceptLast && bytes[15] == 1) return true;

    // :: (Unspecified)
    if (isAllZeroExceptLast && bytes[15] == 0) return true;

    // IPv4-mapped IPv6 ::ffff:0:0/96
    bool isV4Mapped = true;
    for (int i = 0; i < 10; i++) {
      if (bytes[i] != 0) isV4Mapped = false;
    }
    if (bytes[10] != 0xff || bytes[11] != 0xff) isV4Mapped = false;
    if (isV4Mapped) {
      return _isRestrictedIpv4(bytes.sublist(12, 16));
    }

    // fe80::/10 (Link-local: first byte 0xfe, high 2 bits of second byte 10 -> 0x80..0xbf)
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;

    // fc00::/7 (Unique Local Address / ULA: first 7 bits are 1111110 -> 0xfc or 0xfd)
    if ((bytes[0] & 0xfe) == 0xfc) return true;

    // ff00::/8 (Multicast)
    if (bytes[0] == 0xff) return true;

    return false;
  }
}
