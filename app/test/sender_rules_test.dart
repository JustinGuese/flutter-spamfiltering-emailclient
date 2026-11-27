import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/filter_service.dart';
import 'package:spamfiltering_emailclient/filter/sender_rules.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:spamfiltering_emailclient/mail/smtp_service.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail/src/private/util/client_base.dart';

class _FakeSmtpClient extends Fake implements SmtpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #connectToServer) {
      return Future<ConnectionInfo>.value(const ConnectionInfo('host', 465, isSecure: true));
    }
    if (invocation.memberName == #authenticate || invocation.memberName == #sendMessage) {
      return Future<SmtpResponse>.value(SmtpResponse(['250 OK']));
    }
    return Future<void>.value();
  }
}

void main() {
  late AppDatabase db;
  late SenderRules rules;

  setUp(() async {
    db = await AppDatabase.open(inMemory: true);
    rules = SenderRules(db);
  });

  tearDown(() {
    db.close();
  });

  group('SenderRules', () {
    test('set, lookup and remove address rule', () {
      expect(rules.lookup('spammer@evil.com'), isNull);

      rules.set('spammer@evil.com', 'address', SenderRuleAction.block);
      expect(rules.lookup('spammer@evil.com'), equals(SenderRuleAction.block));
      expect(rules.lookup('Spammer <SPAMMER@evil.com>'), equals(SenderRuleAction.block));

      rules.remove('spammer@evil.com');
      expect(rules.lookup('spammer@evil.com'), isNull);
    });

    test('domain rule matches exact domain and subdomains', () {
      rules.set('company.com', 'domain', SenderRuleAction.allow);

      expect(rules.lookup('user@company.com'), equals(SenderRuleAction.allow));
      expect(rules.lookup('User <news@marketing.company.com>'), equals(SenderRuleAction.allow));
      expect(rules.lookup('user@othercompany.com'), isNull);
    });

    test('address rule takes precedence over domain rule', () {
      rules.set('example.com', 'domain', SenderRuleAction.allow);
      rules.set('badapple@example.com', 'address', SenderRuleAction.block);

      expect(rules.lookup('good@example.com'), equals(SenderRuleAction.allow));
      expect(rules.lookup('badapple@example.com'), equals(SenderRuleAction.block));
    });

    test('all returns rules in descending order of creation', () {
      rules.set('a@b.com', 'address', SenderRuleAction.allow);
      rules.set('b.com', 'domain', SenderRuleAction.block);

      final all = rules.all();
      expect(all.length, equals(2));
      expect(all.map((r) => r.pattern), containsAll(['a@b.com', 'b.com']));
    });

    test('isContact checks trust_level >= 1', () {
      expect(rules.isContact('friend@example.com'), isFalse);

      db.db.execute('''
        INSERT INTO contacts (id, email, name, trust_level)
        VALUES ('c1', 'friend@example.com', 'Friend', 1)
      ''');
      db.db.execute('''
        INSERT INTO contacts (id, email, name, trust_level)
        VALUES ('c2', 'untrusted@example.com', 'Untrusted', 0)
      ''');

      expect(rules.isContact('friend@example.com'), isTrue);
      expect(rules.isContact('Friend <FRIEND@example.com>'), isTrue);
      expect(rules.isContact('untrusted@example.com'), isFalse);
    });

    test('FilterService.classifyMessage uses senderRules for signals', () async {
      final store = TokenStoreDrift(db);
      final filter = FilterService(db: db, tokenStore: store, senderRules: rules);

      rules.set('blocked@evil.com', 'address', SenderRuleAction.block);

      final msg = const Message(
        headers: {'from': ['Blocked Sender <blocked@evil.com>']},
        textBody: 'Hello world',
      );

      final verdict = await filter.classifyMessage(messageId: 'm-test', message: msg);
      expect(verdict.spamScore, equals(1.0));
      expect(verdict.evidence.any((e) => e.id == 'sender_blocked'), isTrue);
    });

    test('SmtpService inserts To/Cc recipients into contacts after successful send', () async {
      final smtp = SmtpService(client: _FakeSmtpClient(), db: db);
      final account = AccountRecord(
        id: 'acc1',
        email: 'me@example.com',
        displayName: 'Me',
        imapHost: 'imap.example.com',
        imapPort: 993,
        smtpHost: 'smtp.example.com',
        smtpPort: 465,
        authType: 'password',
        createdAt: DateTime.now(),
      );

      await smtp.sendMail(
        account: account,
        auth: const PasswordMailAuth('pw'),
        to: ['alice@work.com'],
        cc: ['bob@work.com'],
        subject: 'Hi',
        bodyText: 'Hello team',
      );

      expect(rules.isContact('alice@work.com'), isTrue);
      expect(rules.isContact('bob@work.com'), isTrue);
      expect(rules.isContact('charlie@work.com'), isFalse);
    });
  });
}
