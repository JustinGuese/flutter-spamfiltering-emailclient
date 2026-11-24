import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/oauth/oauth_types.dart';
import 'package:spamfiltering_emailclient/notifications/notify_types.dart';
import 'package:spamfiltering_emailclient/ui/settings/notifications_tile.dart';

void main() {
  group('OAuth Types', () {
    test('OAuthProvider enum values', () {
      expect(OAuthProvider.values, contains(OAuthProvider.google));
      expect(OAuthProvider.values, contains(OAuthProvider.microsoft));
    });

    test('OAuthTokens construction and fields', () {
      final now = DateTime.now();
      final tokens = OAuthTokens(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
        expiresAt: now,
        idToken: 'id_789',
      );
      expect(tokens.accessToken, 'access_123');
      expect(tokens.refreshToken, 'refresh_456');
      expect(tokens.expiresAt, now);
      expect(tokens.idToken, 'id_789');
    });

    test('OAuthIdentity construction and fields', () {
      const identity = OAuthIdentity(
        email: 'user@example.com',
        displayName: 'Test User',
      );
      expect(identity.email, 'user@example.com');
      expect(identity.displayName, 'Test User');
    });

    test('ReauthRequiredException toString contains details', () {
      const ex = ReauthRequiredException(
        accountId: 'acc_1',
        email: 'user@example.com',
        provider: OAuthProvider.google,
      );
      expect(ex.accountId, 'acc_1');
      expect(ex.email, 'user@example.com');
      expect(ex.provider, OAuthProvider.google);
      expect(ex.toString(), contains('acc_1'));
      expect(ex.toString(), contains('user@example.com'));
      expect(ex.toString(), contains('OAuthProvider.google'));
    });
  });

  group('MailAuth backwards compatibility', () {
    test('PasswordMailAuth unchanged', () {
      const auth = PasswordMailAuth('secret');
      expect(auth.authType, 'password');
      expect(auth.password, 'secret');
    });

    test('OAuth2MailAuth defaults and compatibility', () {
      const legacy = OAuth2MailAuth('access_legacy', refreshToken: 'refresh_legacy');
      expect(legacy.accessToken, 'access_legacy');
      expect(legacy.refreshToken, 'refresh_legacy');
      expect(legacy.expiresAt, isNull);
      expect(legacy.provider, OAuthProvider.google);
      expect(legacy.authType, 'oauth_google');

      final now = DateTime.now();
      final full = OAuth2MailAuth(
        'access_ms',
        refreshToken: 'refresh_ms',
        expiresAt: now,
        provider: OAuthProvider.microsoft,
      );
      expect(full.accessToken, 'access_ms');
      expect(full.refreshToken, 'refresh_ms');
      expect(full.expiresAt, now);
      expect(full.provider, OAuthProvider.microsoft);
      expect(full.authType, 'oauth_microsoft');
    });
  });

  group('Notify Types', () {
    test('NotifyMode enum values', () {
      expect(NotifyMode.values, [
        NotifyMode.off,
        NotifyMode.instant,
        NotifyMode.every5min,
        NotifyMode.hourly,
      ]);
    });

    test('NewMail construction and fields', () {
      final received = DateTime.now();
      final mail = NewMail(
        messageId: 'msg-123',
        accountId: 'acc-456',
        sender: 'sender@example.com',
        subject: 'Hello World',
        receivedAt: received,
      );
      expect(mail.messageId, 'msg-123');
      expect(mail.accountId, 'acc-456');
      expect(mail.sender, 'sender@example.com');
      expect(mail.subject, 'Hello World');
      expect(mail.receivedAt, received);
    });
  });

  group('NotificationsTile stub', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: NotificationsTile(),
        ),
      );
      expect(find.byType(NotificationsTile), findsOneWidget);
    });
  });
}
