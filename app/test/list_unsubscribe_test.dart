import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/list_unsubscribe.dart';
import 'package:spamfiltering_emailclient/mail/unsubscribe_service.dart';

void main() {
  group('parseListUnsubscribe - One-Click (RFC 8058)', () {
    test('requires https and List-Unsubscribe=One-Click (case-insensitive)', () {
      final res = parseListUnsubscribe(
        '<https://example.com/unsub?id=123>',
        'List-Unsubscribe=One-Click',
      );
      expect(res.oneClickUrl, Uri.parse('https://example.com/unsub?id=123'));
      expect(res.mailto, isNull);
    });

    test('case-insensitivity of Post header', () {
      final res = parseListUnsubscribe(
        '<https://example.com/unsub>',
        'list-unsubscribe=one-click',
      );
      expect(res.oneClickUrl, Uri.parse('https://example.com/unsub'));

      final res2 = parseListUnsubscribe(
        '<https://example.com/unsub>',
        'LIST-UNSUBSCRIBE=ONE-CLICK',
      );
      expect(res2.oneClickUrl, Uri.parse('https://example.com/unsub'));

      final res3 = parseListUnsubscribe(
        '<https://example.com/unsub>',
        'List-Unsubscribe-Post: List-Unsubscribe=One-Click',
      );
      expect(res3.oneClickUrl, Uri.parse('https://example.com/unsub'));
    });

    test('ignores http-only URLs', () {
      final res = parseListUnsubscribe(
        '<http://example.com/unsub>',
        'List-Unsubscribe=One-Click',
      );
      expect(res.oneClickUrl, isNull);
    });

    test('ignores one-click URL if Post header is absent or invalid', () {
      final resNone = parseListUnsubscribe(
        '<https://example.com/unsub>',
        null,
      );
      expect(resNone.oneClickUrl, isNull);

      final resInvalid = parseListUnsubscribe(
        '<https://example.com/unsub>',
        'List-Unsubscribe=Two-Click',
      );
      expect(resInvalid.oneClickUrl, isNull);
    });
  });

  group('parseListUnsubscribe - mailto (RFC 2369)', () {
    test('extracts basic mailto with default subject and body', () {
      final res = parseListUnsubscribe(
        '<mailto:unsub@example.com>',
        null,
      );
      expect(res.mailto, isNotNull);
      expect(res.mailto!.to, 'unsub@example.com');
      expect(res.mailto!.subject, 'unsubscribe');
      expect(res.mailto!.body, 'unsubscribe');
    });

    test('extracts subject and body decoding percent-encoding', () {
      final res = parseListUnsubscribe(
        '<mailto:unsub@example.com?subject=Unsubscribe%20Please&body=Stop%20sending%20email>',
        null,
      );
      expect(res.mailto, isNotNull);
      expect(res.mailto!.to, 'unsub@example.com');
      expect(res.mailto!.subject, 'Unsubscribe Please');
      expect(res.mailto!.body, 'Stop sending email');
    });

    test('caps subject and body at 200 chars', () {
      final longStr = 'a' * 300;
      final res = parseListUnsubscribe(
        '<mailto:unsub@example.com?subject=$longStr&body=$longStr>',
        null,
      );
      expect(res.mailto, isNotNull);
      expect(res.mailto!.subject.length, 200);
      expect(res.mailto!.body.length, 200);
      expect(res.mailto!.subject, 'a' * 200);
      expect(res.mailto!.body, 'a' * 200);
    });

    test('rejects mailto with cc or bcc (returns null)', () {
      final withCc = parseListUnsubscribe(
        '<mailto:unsub@example.com?cc=victim@example.com>',
        null,
      );
      expect(withCc.mailto, isNull);

      final withBcc = parseListUnsubscribe(
        '<mailto:unsub@example.com?bcc=victim@example.com>',
        null,
      );
      expect(withBcc.mailto, isNull);

      final withMixedCaseBcc = parseListUnsubscribe(
        '<mailto:unsub@example.com?BCC=victim@example.com>',
        null,
      );
      expect(withMixedCaseBcc.mailto, isNull);
    });

    test('rejects mailto with header injection via CRLF or %0d%0a', () {
      final crlfRaw = '<mailto:unsub@example.com?subject=test\r\nBcc:victim@evil.com>';
      expect(parseListUnsubscribe(crlfRaw, null).mailto, isNull);

      final percentEncodedCr = '<mailto:unsub@example.com?subject=test%0dBcc:victim@evil.com>';
      expect(parseListUnsubscribe(percentEncodedCr, null).mailto, isNull);

      final percentEncodedLf = '<mailto:unsub@example.com?subject=test%0aBcc:victim@evil.com>';
      expect(parseListUnsubscribe(percentEncodedLf, null).mailto, isNull);

      final percentEncodedCrlf = '<mailto:unsub@example.com?subject=test%0D%0ABcc:victim@evil.com>';
      expect(parseListUnsubscribe(percentEncodedCrlf, null).mailto, isNull);
    });

    test('rejects multiple recipients', () {
      final commaInPath = parseListUnsubscribe(
        '<mailto:user1@example.com,user2@example.com>',
        null,
      );
      expect(commaInPath.mailto, isNull);

      final semiInPath = parseListUnsubscribe(
        '<mailto:user1@example.com;user2@example.com>',
        null,
      );
      expect(semiInPath.mailto, isNull);

      final toInQuery = parseListUnsubscribe(
        '<mailto:user1@example.com?to=user2@example.com>',
        null,
      );
      expect(toInQuery.mailto, isNull);
    });

    test('rejects invalid recipient format', () {
      expect(parseListUnsubscribe('<mailto:notanemail>', null).mailto, isNull);
      expect(parseListUnsubscribe('<mailto:user@localhost>', null).mailto, isNull);
      expect(parseListUnsubscribe('<mailto:>', null).mailto, isNull);
    });
  });

  group('parseListUnsubscribe - multiple entries & whitespace folding', () {
    test('handles multiple entries in header (both mailto and one-click)', () {
      final header = '<mailto:unsub@example.com?subject=unsubscribe>, <https://example.com/unsub>';
      final res = parseListUnsubscribe(header, 'List-Unsubscribe=One-Click');

      expect(res.oneClickUrl, Uri.parse('https://example.com/unsub'));
      expect(res.mailto, isNotNull);
      expect(res.mailto!.to, 'unsub@example.com');
      expect(res.mailto!.subject, 'unsubscribe');
      expect(res.hasTarget, isTrue);
    });

    test('handles folded whitespace across lines', () {
      final foldedHeader = '''
<mailto:unsub@example.com>,
  <https://example.com/unsub?track=1>
''';
      final res = parseListUnsubscribe(foldedHeader, 'List-Unsubscribe=One-Click');

      expect(res.oneClickUrl, Uri.parse('https://example.com/unsub?track=1'));
      expect(res.mailto, isNotNull);
      expect(res.mailto!.to, 'unsub@example.com');
    });

    test('handles whitespace inside URL entry', () {
      final header = '<https://example.com/\r\n  unsub_path>';
      final res = parseListUnsubscribe(header, 'List-Unsubscribe=One-Click');
      expect(res.oneClickUrl, Uri.parse('https://example.com/unsub_path'));
    });

    test('skips http URL to find valid https URL when multiple URLs present', () {
      final header = '<http://example.com/insecure>, <https://example.com/secure>';
      final res = parseListUnsubscribe(header, 'List-Unsubscribe=One-Click');
      expect(res.oneClickUrl, Uri.parse('https://example.com/secure'));
    });

    test('returns empty targets for null or empty header', () {
      final resNull = parseListUnsubscribe(null, null);
      expect(resNull.oneClickUrl, isNull);
      expect(resNull.mailto, isNull);
      expect(resNull.hasTarget, isFalse);

      final resEmpty = parseListUnsubscribe('   ', 'List-Unsubscribe=One-Click');
      expect(resEmpty.oneClickUrl, isNull);
      expect(resEmpty.mailto, isNull);
      expect(resEmpty.hasTarget, isFalse);
    });
  });

  group('UnsubscribeService contracts', () {
    test('enums and UnsubscribeOutcome behave as expected', () {
      const outcome = UnsubscribeOutcome(
        UnsubscribeStatus.sent,
        method: 'one_click',
      );
      expect(outcome.status, UnsubscribeStatus.sent);
      expect(outcome.method, 'one_click');
      expect(
        outcome,
        const UnsubscribeOutcome(UnsubscribeStatus.sent, method: 'one_click'),
      );
      expect(outcome.toString(), contains('sent'));

      expect(UnsubscribeTrigger.values, contains(UnsubscribeTrigger.verdict));
      expect(UnsubscribeTrigger.values, contains(UnsubscribeTrigger.manual));
      expect(
        UnsubscribeStatus.values,
        containsAll([
          UnsubscribeStatus.sent,
          UnsubscribeStatus.failed,
          UnsubscribeStatus.skippedDisabled,
          UnsubscribeStatus.skippedNoTarget,
          UnsubscribeStatus.skippedUnauthenticated,
          UnsubscribeStatus.skippedDuplicate,
          UnsubscribeStatus.skippedRateLimited,
          UnsubscribeStatus.skippedSelfDomain,
          UnsubscribeStatus.skippedUnsafeUrl,
        ]),
      );
    });
  });

  group('Database schema & migration', () {
    test('fresh DB contains list_unsubscribe columns and unsubscribe_log table', () {
      final db = AppDatabase(sqlite3.openInMemory());
      addTearDown(db.close);

      final cols = db.db.select('PRAGMA table_info(messages)').map((r) => r['name'] as String).toSet();
      expect(cols, contains('list_unsubscribe'));
      expect(cols, contains('list_unsubscribe_post'));
      expect(cols, contains('sender_auth_pass'));

      // Check unsubscribe_log table
      final logCols = db.db.select('PRAGMA table_info(unsubscribe_log)').map((r) => r['name'] as String).toSet();
      expect(logCols, containsAll([
        'id',
        'account_id',
        'sender_domain',
        'message_id',
        'method',
        'status',
        'created_at',
      ]));

      // Check index exists
      final indexNames = db.db.select("SELECT name FROM sqlite_master WHERE type = 'index'").map((r) => r['name'] as String).toSet();
      expect(indexNames, contains('idx_unsubscribe_log_account_sender'));

      // Check auto_unsubscribe setting default
      expect(db.isAutoUnsubscribeEnabled, isTrue);

      db.setSetting('auto_unsubscribe', 'false');
      expect(db.isAutoUnsubscribeEnabled, isFalse);

      db.setSetting('auto_unsubscribe', 'true');
      expect(db.isAutoUnsubscribeEnabled, isTrue);
    });

    test('migrates existing DB lacking new columns and table', () {
      final rawDb = sqlite3.openInMemory();
      // Create pre-migration messages table without list_unsubscribe columns
      rawDb.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          folder_id TEXT NOT NULL,
          uid INTEGER NOT NULL,
          message_id TEXT,
          subject TEXT NOT NULL,
          sender TEXT NOT NULL,
          sender_domain TEXT,
          recipient_addrs TEXT NOT NULL,
          cc_addrs TEXT NOT NULL DEFAULT '',
          date TEXT NOT NULL,
          snippet TEXT NOT NULL,
          is_read INTEGER NOT NULL DEFAULT 0,
          is_flagged INTEGER NOT NULL DEFAULT 0,
          has_attachments INTEGER NOT NULL DEFAULT 0,
          classification_label TEXT NOT NULL DEFAULT 'inbox',
          spam_score REAL NOT NULL DEFAULT 0.0
        );
      ''');

      // Now open AppDatabase on top of this raw DB (triggers _createTables + _migrate)
      final db = AppDatabase(rawDb);
      addTearDown(db.close);

      final cols = db.db.select('PRAGMA table_info(messages)').map((r) => r['name'] as String).toSet();
      expect(cols, contains('list_unsubscribe'));
      expect(cols, contains('list_unsubscribe_post'));
      expect(cols, contains('sender_auth_pass'));

      final logCols = db.db.select('PRAGMA table_info(unsubscribe_log)').map((r) => r['name'] as String).toSet();
      expect(logCols, contains('sender_domain'));
    });
  });
}
