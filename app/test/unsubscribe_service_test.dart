import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/list_unsubscribe.dart';
import 'package:spamfiltering_emailclient/mail/mail_auth.dart';
import 'package:df_safe_url/df_safe_url.dart';
import 'package:spamfiltering_emailclient/mail/unsubscribe_service.dart';

class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      data[key];

  @override
  Future<void> write({required String key, required String? value, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    if (value != null) {
      data[key] = value;
    } else {
      data.remove(key);
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockMailSender implements UnsubscribeMailSender {
  final List<MailtoTarget> sentMails = [];
  bool shouldThrow = false;

  @override
  Future<void> sendUnsubscribeMail({
    required AccountRecord account,
    required MailtoTarget mailto,
  }) async {
    if (shouldThrow) {
      throw Exception('SMTP failure');
    }
    sentMails.add(mailto);
  }
}

class MockHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int statusCode = 200;
  dynamic responseData = 'OK';
  Map<String, List<String>> responseHeaders = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final headers = <String, List<String>>{
      ...responseHeaders,
      'content-type': ['text/plain'],
    };
    return ResponseBody.fromString(
      responseData.toString(),
      statusCode,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late AccountRepository accountRepo;
  late MockMailSender mockMailSender;
  late MockHttpAdapter mockHttpAdapter;
  late Dio dio;
  late DfSafeUrlGuard publicGuard;
  DateTime fakeNow = DateTime.utc(2026, 11, 24, 12, 0, 0);

  setUp(() async {
    db = AppDatabase(sqlite3.openInMemory());
    accountRepo = AccountRepository(db: db, storage: _FakeStorage());
    mockMailSender = MockMailSender();
    mockHttpAdapter = MockHttpAdapter();

    dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
    ));
    dio.httpClientAdapter = mockHttpAdapter;

    publicGuard = DfSafeUrlGuard(
      dnsLookup: (host) async => [InternetAddress('93.184.216.34')],
    );

    // Seed account
    final account = AccountRecord(
      id: 'acc1',
      email: 'user@mydomain.com',
      displayName: 'User',
      imapHost: 'imap.mydomain.com',
      imapPort: 993,
      smtpHost: 'smtp.mydomain.com',
      smtpPort: 465,
      authType: 'password',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await accountRepo.saveAccount(account, const PasswordMailAuth('secret'));
  });

  tearDown(() {
    db.close();
  });

  void insertMessage({
    required String id,
    String accountId = 'acc1',
    String sender = 'newsletter@example.com',
    String? senderDomain = 'example.com',
    String? listUnsubscribe = '<https://example.com/unsub>',
    String? listUnsubscribePost = 'List-Unsubscribe=One-Click',
    int senderAuthPass = 1,
  }) {
    db.db.execute('''
      INSERT INTO messages (
        id, account_id, folder_id, uid, subject, sender, sender_domain,
        recipient_addrs, date, snippet, list_unsubscribe, list_unsubscribe_post, sender_auth_pass
      ) VALUES (?, ?, 'f1', 1, 'Subject', ?, ?, 'user@mydomain.com', '2026-11-24', 'Snippet', ?, ?, ?)
    ''', [
      id,
      accountId,
      sender,
      senderDomain,
      listUnsubscribe,
      listUnsubscribePost,
      senderAuthPass,
    ]);
  }

  UnsubscribeServiceImpl createService({
    DfSafeUrlGuard? guard,
    DateTime Function()? clock,
  }) {
    return UnsubscribeServiceImpl(
      db: db,
      accountRepo: accountRepo,
      guard: guard ?? publicGuard,
      dio: dio,
      mailSender: mockMailSender,
      clock: clock ?? () => fakeNow,
    );
  }

  group('UnsubscribeService - Request Hygiene & One-Click', () {
    test('one-click sends exactly one POST with exact body and no auth/cookie headers', () async {
      insertMessage(
        id: 'msg1',
        listUnsubscribe: '<https://example.com/unsub>',
        listUnsubscribePost: 'List-Unsubscribe=One-Click',
        senderAuthPass: 1,
      );

      final service = createService();
      final outcome = await service.unsubscribeForMessage(
        'msg1',
        trigger: UnsubscribeTrigger.verdict,
      );

      expect(outcome.status, UnsubscribeStatus.sent);
      expect(outcome.method, 'one_click');

      // Check request
      expect(mockHttpAdapter.requests.length, 1);
      final req = mockHttpAdapter.requests.first;
      expect(req.method, 'POST');
      expect(req.uri, Uri.parse('https://example.com/unsub'));
      expect(req.data, 'List-Unsubscribe=One-Click');
      expect(req.contentType, 'application/x-www-form-urlencoded');
      expect(req.followRedirects, isFalse);

      // Verify no auth or cookie headers
      expect(req.headers['authorization'], isNull);
      expect(req.headers['cookie'], isNull);
      expect(req.headers['Cookie'], isNull);
      expect(req.headers['x-device-id'], isNull);

      // Check DB log
      final logs = db.db.select('SELECT * FROM unsubscribe_log');
      expect(logs.length, 1);
      expect(logs.first['status'], 'sent');
      expect(logs.first['method'], 'one_click');
      expect(logs.first['account_id'], 'acc1');
      expect(logs.first['sender_domain'], 'example.com');
    });

    test('does not follow redirect (3xx logged as failed)', () async {
      mockHttpAdapter.statusCode = 302;
      mockHttpAdapter.responseHeaders = {'location': ['https://example.com/other']};

      insertMessage(
        id: 'msg_redirect',
        listUnsubscribe: '<https://example.com/unsub>',
        listUnsubscribePost: 'List-Unsubscribe=One-Click',
      );

      final service = createService();
      final outcome = await service.unsubscribeForMessage(
        'msg_redirect',
        trigger: UnsubscribeTrigger.verdict,
      );

      expect(outcome.status, UnsubscribeStatus.failed);
      expect(outcome.method, 'one_click');

      final logs = db.db.select('SELECT * FROM unsubscribe_log');
      expect(logs.length, 1);
      expect(logs.first['status'], 'failed');
      expect(logs.first['method'], 'one_click');
    });
  });

  group('UnsubscribeService - Authentication guard', () {
    test('unauthenticated sender skipped on verdict but allowed on manual', () async {
      insertMessage(
        id: 'msg_unauth',
        senderAuthPass: 0,
      );

      final service = createService();

      // Trigger = verdict -> skippedUnauthenticated
      final outcomeVerdict = await service.unsubscribeForMessage(
        'msg_unauth',
        trigger: UnsubscribeTrigger.verdict,
      );
      expect(outcomeVerdict.status, UnsubscribeStatus.skippedUnauthenticated);
      expect(mockHttpAdapter.requests.isEmpty, isTrue);

      // Verify logged as skippedUnauthenticated
      final logs1 = db.db.select('SELECT * FROM unsubscribe_log WHERE status = ?', [
        UnsubscribeStatus.skippedUnauthenticated.name,
      ]);
      expect(logs1.length, 1);

      // Trigger = manual -> allowed, executes one-click
      final outcomeManual = await service.unsubscribeForMessage(
        'msg_unauth',
        trigger: UnsubscribeTrigger.manual,
      );
      expect(outcomeManual.status, UnsubscribeStatus.sent);
      expect(mockHttpAdapter.requests.length, 1);
    });
  });

  group('UnsubscribeService - Idempotency & Rate Limit', () {
    test('second call for same sender is skippedDuplicate within 30 days', () async {
      insertMessage(
        id: 'msg_idem1',
        senderDomain: 'repeat-sender.com',
      );
      insertMessage(
        id: 'msg_idem2',
        senderDomain: 'repeat-sender.com',
      );

      final service = createService();

      final first = await service.unsubscribeForMessage(
        'msg_idem1',
        trigger: UnsubscribeTrigger.verdict,
      );
      expect(first.status, UnsubscribeStatus.sent);

      final second = await service.unsubscribeForMessage(
        'msg_idem2',
        trigger: UnsubscribeTrigger.verdict,
      );
      expect(second.status, UnsubscribeStatus.skippedDuplicate);

      // Still only 1 HTTP request made
      expect(mockHttpAdapter.requests.length, 1);
    });

    test('failure retried after 24h, but not within 24h; capped at 3 attempts', () async {
      insertMessage(
        id: 'msg_fail',
        senderDomain: 'failing-sender.com',
      );

      mockHttpAdapter.statusCode = 500;
      final service = createService();

      // Attempt 1: fails
      final r1 = await service.unsubscribeForMessage('msg_fail', trigger: UnsubscribeTrigger.manual);
      expect(r1.status, UnsubscribeStatus.failed);

      // Attempt 2 immediately (within 24h): skippedDuplicate
      final r2 = await service.unsubscribeForMessage('msg_fail', trigger: UnsubscribeTrigger.manual);
      expect(r2.status, UnsubscribeStatus.skippedDuplicate);

      // Advance time by 25h
      fakeNow = fakeNow.add(const Duration(hours: 25));

      // Attempt 3: fails again
      final r3 = await service.unsubscribeForMessage('msg_fail', trigger: UnsubscribeTrigger.manual);
      expect(r3.status, UnsubscribeStatus.failed);

      // Advance time by 25h
      fakeNow = fakeNow.add(const Duration(hours: 25));

      // Attempt 4: fails (3rd failure attempt)
      final r4 = await service.unsubscribeForMessage('msg_fail', trigger: UnsubscribeTrigger.manual);
      expect(r4.status, UnsubscribeStatus.failed);

      // Advance time by 25h
      fakeNow = fakeNow.add(const Duration(hours: 25));

      // Attempt 5: max 3 attempts reached -> skippedDuplicate
      final r5 = await service.unsubscribeForMessage('msg_fail', trigger: UnsubscribeTrigger.manual);
      expect(r5.status, UnsubscribeStatus.skippedDuplicate);
    });

    test('21st attempt in 24h across all accounts is rate limited', () async {
      final service = createService();

      for (int i = 1; i <= 20; i++) {
        insertMessage(
          id: 'msg_rate_$i',
          senderDomain: 'sender$i.com',
          sender: 'news@sender$i.com',
        );
        final res = await service.unsubscribeForMessage(
          'msg_rate_$i',
          trigger: UnsubscribeTrigger.manual,
        );
        expect(res.status, UnsubscribeStatus.sent, reason: 'attempt $i should pass');
      }

      expect(mockHttpAdapter.requests.length, 20);

      // 21st attempt
      insertMessage(
        id: 'msg_rate_21',
        senderDomain: 'sender21.com',
        sender: 'news@sender21.com',
      );
      final res21 = await service.unsubscribeForMessage(
        'msg_rate_21',
        trigger: UnsubscribeTrigger.manual,
      );
      expect(res21.status, UnsubscribeStatus.skippedRateLimited);
      expect(mockHttpAdapter.requests.length, 20); // No 21st request made
    });
  });

  group('UnsubscribeService - Self-Domain and Disabled Setting', () {
    test('skips when sender domain equals receiving account domain', () async {
      insertMessage(
        id: 'msg_self',
        senderDomain: 'mydomain.com',
        sender: 'alerts@mydomain.com',
      );

      final service = createService();
      final res = await service.unsubscribeForMessage(
        'msg_self',
        trigger: UnsubscribeTrigger.verdict,
      );
      expect(res.status, UnsubscribeStatus.skippedSelfDomain);
      expect(mockHttpAdapter.requests.isEmpty, isTrue);

      final logs = db.db.select('SELECT * FROM unsubscribe_log WHERE sender_domain = ?', ['mydomain.com']);
      expect(logs.length, 1);
      expect(logs.first['status'], UnsubscribeStatus.skippedSelfDomain.name);
    });

    test('skips and does NOT write log when auto_unsubscribe setting is false on verdict', () async {
      db.setSetting('auto_unsubscribe', 'false');
      insertMessage(
        id: 'msg_disabled',
        senderDomain: 'external.com',
      );

      final service = createService();
      final resVerdict = await service.unsubscribeForMessage(
        'msg_disabled',
        trigger: UnsubscribeTrigger.verdict,
      );
      expect(resVerdict.status, UnsubscribeStatus.skippedDisabled);
      expect(mockHttpAdapter.requests.isEmpty, isTrue);

      // Must NOT write log
      final logs = db.db.select('SELECT * FROM unsubscribe_log');
      expect(logs.isEmpty, isTrue);

      // But manual still works
      final resManual = await service.unsubscribeForMessage(
        'msg_disabled',
        trigger: UnsubscribeTrigger.manual,
      );
      expect(resManual.status, UnsubscribeStatus.sent);
      expect(mockHttpAdapter.requests.length, 1);
    });
  });

  group('UnsubscribeService - Mailto fallback and safety', () {
    test('executes mailto when one-click is absent', () async {
      insertMessage(
        id: 'msg_mailto',
        listUnsubscribe: '<mailto:unsub@newsletter.org?subject=Stop>',
        listUnsubscribePost: null,
      );

      final service = createService();
      final outcome = await service.unsubscribeForMessage(
        'msg_mailto',
        trigger: UnsubscribeTrigger.verdict,
      );

      expect(outcome.status, UnsubscribeStatus.sent);
      expect(outcome.method, 'mailto');
      expect(mockMailSender.sentMails.length, 1);
      expect(mockMailSender.sentMails.first.to, 'unsub@newsletter.org');
      expect(mockMailSender.sentMails.first.subject, 'Stop');
    });

    test('fails mailto when recipient is account own address', () async {
      insertMessage(
        id: 'msg_mailto_own',
        listUnsubscribe: '<mailto:user@mydomain.com>',
        listUnsubscribePost: null,
      );

      final service = createService();
      final outcome = await service.unsubscribeForMessage(
        'msg_mailto_own',
        trigger: UnsubscribeTrigger.verdict,
      );

      expect(outcome.status, UnsubscribeStatus.failed);
      expect(outcome.method, 'mailto');
      expect(mockMailSender.sentMails.isEmpty, isTrue);
    });
  });

  group('UnsubscribeService - SSRF Unsafe URL', () {
    test('skips unsafe URL if guard fails', () async {
      final privateGuard = DfSafeUrlGuard(
        dnsLookup: (host) async => [InternetAddress('127.0.0.1')],
      );
      insertMessage(
        id: 'msg_unsafe',
        listUnsubscribe: '<https://attacker.internal/unsub>',
        listUnsubscribePost: 'List-Unsubscribe=One-Click',
      );

      final service = createService(guard: privateGuard);
      final outcome = await service.unsubscribeForMessage(
        'msg_unsafe',
        trigger: UnsubscribeTrigger.verdict,
      );

      expect(outcome.status, UnsubscribeStatus.skippedUnsafeUrl);
      expect(outcome.method, 'one_click');
      expect(mockHttpAdapter.requests.isEmpty, isTrue);

      final logs = db.db.select('SELECT * FROM unsubscribe_log');
      expect(logs.length, 1);
      expect(logs.first['status'], UnsubscribeStatus.skippedUnsafeUrl.name);
    });
  });
}
