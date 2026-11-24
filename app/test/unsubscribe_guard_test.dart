import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/mail/unsubscribe_guard.dart';

void main() {
  group('UnsubscribeGuard - Scheme, Userinfo, Port', () {
    const guard = UnsubscribeGuard();

    test('rejects non-https scheme (http, ftp, etc.)', () async {
      expect(
        await guard.check(Uri.parse('http://example.com/unsub')),
        GuardResult.unsafeScheme,
      );
      expect(await guard.isSafe(Uri.parse('http://example.com/unsub')), isFalse);

      expect(
        await guard.check(Uri.parse('ftp://example.com/unsub')),
        GuardResult.unsafeScheme,
      );
    });

    test('rejects URLs with userinfo', () async {
      expect(
        await guard.check(Uri.parse('https://user:pass@example.com/unsub')),
        GuardResult.hasUserInfo,
      );
      expect(
        await guard.isSafe(Uri.parse('https://admin@example.com/unsub')),
        isFalse,
      );
    });

    test('rejects non-443 ports', () async {
      expect(
        await guard.check(Uri.parse('https://example.com:8080/unsub')),
        GuardResult.unsafePort,
      );
      expect(
        await guard.check(Uri.parse('https://example.com:80/unsub')),
        GuardResult.unsafePort,
      );
      expect(
        await guard.check(Uri.parse('https://example.com:8443/unsub')),
        GuardResult.unsafePort,
      );
    });

    test('accepts default port 443 or omitted port', () async {
      final mockGuard = UnsubscribeGuard(
        dnsLookup: (host) async => [InternetAddress('93.184.216.34')],
      );
      expect(
        await mockGuard.check(Uri.parse('https://example.com/unsub')),
        GuardResult.safe,
      );
      expect(
        await mockGuard.check(Uri.parse('https://example.com:443/unsub')),
        GuardResult.safe,
      );
    });
  });

  group('UnsubscribeGuard - Hostnames and IP Literals', () {
    final mockGuard = UnsubscribeGuard(
      dnsLookup: (host) async => [InternetAddress('93.184.216.34')],
    );

    test('rejects localhost, .local, and .internal hostnames', () async {
      expect(
        await mockGuard.check(Uri.parse('https://localhost/unsub')),
        GuardResult.blockedHost,
      );
      expect(
        await mockGuard.check(Uri.parse('https://foo.localhost/unsub')),
        GuardResult.blockedHost,
      );
      expect(
        await mockGuard.check(Uri.parse('https://service.local/unsub')),
        GuardResult.blockedHost,
      );
      expect(
        await mockGuard.check(Uri.parse('https://api.internal/unsub')),
        GuardResult.blockedHost,
      );
    });

    test('rejects IP literals in loopback (127.0.0.0/8, ::1)', () async {
      expect(
        await mockGuard.check(Uri.parse('https://127.0.0.1/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://127.1.2.3/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://[::1]/unsub')),
        GuardResult.privateIp,
      );
    });

    test('rejects IP literals in private ranges (RFC 1918)', () async {
      // 10.0.0.0/8
      expect(
        await mockGuard.check(Uri.parse('https://10.0.0.1/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://10.255.255.254/unsub')),
        GuardResult.privateIp,
      );

      // 172.16.0.0/12
      expect(
        await mockGuard.check(Uri.parse('https://172.16.0.1/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://172.31.255.254/unsub')),
        GuardResult.privateIp,
      );

      // 192.168.0.0/16
      expect(
        await mockGuard.check(Uri.parse('https://192.168.1.1/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://192.168.254.254/unsub')),
        GuardResult.privateIp,
      );
    });

    test('rejects link-local (169.254.0.0/16, fe80::/10)', () async {
      expect(
        await mockGuard.check(Uri.parse('https://169.254.169.254/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://[fe80::1]/unsub')),
        GuardResult.privateIp,
      );
    });

    test('rejects CGNAT (100.64.0.0/10) and ULA (fc00::/7)', () async {
      expect(
        await mockGuard.check(Uri.parse('https://100.64.0.1/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://100.127.255.254/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://[fc00::1]/unsub')),
        GuardResult.privateIp,
      );
      expect(
        await mockGuard.check(Uri.parse('https://[fd12:3456:789a::1]/unsub')),
        GuardResult.privateIp,
      );
    });

    test('accepts public IP literal', () async {
      expect(
        await mockGuard.check(Uri.parse('https://93.184.216.34/unsub')),
        GuardResult.safe,
      );
    });
  });

  group('UnsubscribeGuard - DNS Resolution', () {
    test('rejects when DNS resolves to private IP', () async {
      final guard = UnsubscribeGuard(
        dnsLookup: (host) async => [InternetAddress('10.0.0.5')],
      );
      expect(
        await guard.check(Uri.parse('https://evil-unsub.com/unsub')),
        GuardResult.privateIp,
      );
      expect(await guard.isSafe(Uri.parse('https://evil-unsub.com/unsub')), isFalse);
    });

    test('rejects when any of multiple resolved IPs is private/restricted', () async {
      final guard = UnsubscribeGuard(
        dnsLookup: (host) async => [
          InternetAddress('93.184.216.34'),
          InternetAddress('127.0.0.1'),
        ],
      );
      expect(
        await guard.check(Uri.parse('https://mixed-unsub.com/unsub')),
        GuardResult.privateIp,
      );
      expect(await guard.isSafe(Uri.parse('https://mixed-unsub.com/unsub')), isFalse);
    });

    test('rejects when DNS resolution fails or returns empty', () async {
      final failingGuard = UnsubscribeGuard(
        dnsLookup: (host) async => throw const SocketException('NXDOMAIN'),
      );
      expect(
        await failingGuard.check(Uri.parse('https://nonexistent-domain.xyz/unsub')),
        GuardResult.dnsFailed,
      );

      final emptyGuard = UnsubscribeGuard(
        dnsLookup: (host) async => [],
      );
      expect(
        await emptyGuard.check(Uri.parse('https://empty-domain.xyz/unsub')),
        GuardResult.dnsFailed,
      );
    });

    test('passes when all resolved IPs are public', () async {
      final guard = UnsubscribeGuard(
        dnsLookup: (host) async => [
          InternetAddress('93.184.216.34'),
          InternetAddress('2606:2800:220:1:248:1893:25c8:1946'),
        ],
      );
      expect(
        await guard.check(Uri.parse('https://valid-sender.com/unsub')),
        GuardResult.safe,
      );
      expect(await guard.isSafe(Uri.parse('https://valid-sender.com/unsub')), isTrue);
    });
  });
}
