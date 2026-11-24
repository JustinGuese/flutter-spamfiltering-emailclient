// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/community/report_client.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';
import 'package:spamfiltering_emailclient/filter/verdict_controller.dart';
import 'package:spamfiltering_emailclient/mail/unsubscribe_service.dart';

/// Never touches the network: a spam verdict reports to the community backend,
/// which now defaults to the live server.
class _FakeReports extends CommunityReportClient {
  var reports = 0;

  @override
  Future<bool> reportSpam(Fingerprints fingerprints) async {
    reports++;
    return false; // "not delivered": skips the last_report_at write so commits stay countable
  }

  @override
  Future<bool> voteHam(List<int> hashes) async => true;
}

class _FakeUnsubscribeService implements UnsubscribeService {
  final List<({String messageId, UnsubscribeTrigger trigger})> calls = [];

  @override
  Future<UnsubscribeOutcome> unsubscribeForMessage(
    String messageId, {
    required UnsubscribeTrigger trigger,
  }) async {
    calls.add((messageId: messageId, trigger: trigger));
    return const UnsubscribeOutcome(UnsubscribeStatus.sent, method: 'one_click');
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(inMemory: true);
    db.db.execute("INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, sender_domain, recipient_addrs, date, snippet, classification_label) VALUES ('m', 'a', 'f', 1, 'Win a prize', 's@x.com', 'x.com', '', '2026-11-02T10:00:00', '', 'inbox')");
    final body = List.generate(300, (i) => 'word$i prize$i').join(' ');
    db.db.execute("INSERT INTO bodies (message_id, text_body, remote_images_blocked) VALUES ('m', ?, 1)", [body]);
  });
  tearDown(() => db.close());

  test('a verdict is written in a single transaction, not one disk write per token', () async {
    // Each token count used to commit on its own: ~600 fsyncs, 10+ s on a real disk.
    var commits = 0;
    final sub = db.db.commits.listen((_) => commits++);
    var changed = 0;
    final reports = _FakeReports();
    final controller = VerdictController(db: db, tokenStore: TokenStoreDrift(db), reportClient: reports, onChanged: () => changed++);

    await controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(db.db.select('SELECT COUNT(*) c FROM tokens').first['c'] as int, greaterThan(300), reason: 'tokens were learned');
    expect(commits, 1);
    expect(reports.reports, 1, reason: 'spam verdicts are shared anonymously by default');
    expect(changed, greaterThan(0), reason: 'the list and reader must rebuild when the verdict lands');
    expect(db.db.select("SELECT classification_label l FROM messages WHERE id = 'm'").first['l'], 'spam');
  });

  test('undo restores the label and learns back in one transaction too', () async {
    final controller = VerdictController(db: db, tokenStore: TokenStoreDrift(db), reportClient: _FakeReports());
    await controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
    var commits = 0;
    final sub = db.db.commits.listen((_) => commits++);

    controller.undo();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(commits, 1);
    expect(db.db.select("SELECT classification_label l FROM messages WHERE id = 'm'").first['l'], 'inbox');
  });

  test('1. Spam click schedules unsubscribe after delay', () {
    fakeAsync((async) {
      final unsubService = _FakeUnsubscribeService();
      final controller = VerdictController(
        db: db,
        tokenStore: TokenStoreDrift(db),
        reportClient: _FakeReports(),
        unsubscribeService: unsubService,
      );

      controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
      async.flushMicrotasks();

      expect(controller.pendingUnsubscribeTimer, isNotNull);
      expect(controller.pendingUnsubscribeMessageId, 'm');
      expect(unsubService.calls, isEmpty);

      // Fast-forward past undo window (8s) but before 10s
      async.elapse(const Duration(seconds: 9));
      expect(unsubService.calls, isEmpty);

      // Fast-forward past 10s
      async.elapse(const Duration(seconds: 1));
      expect(unsubService.calls.length, 1);
      expect(unsubService.calls.first.messageId, 'm');
      expect(unsubService.calls.first.trigger, UnsubscribeTrigger.verdict);
      expect(controller.pendingUnsubscribeTimer, isNull);
    });
  });

  test('2. Undo cancels scheduled unsubscribe', () {
    fakeAsync((async) {
      final unsubService = _FakeUnsubscribeService();
      final controller = VerdictController(
        db: db,
        tokenStore: TokenStoreDrift(db),
        reportClient: _FakeReports(),
        unsubscribeService: unsubService,
      );

      controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
      async.flushMicrotasks();

      expect(controller.pendingUnsubscribeTimer, isNotNull);

      // User triggers undo within the 8s window
      async.elapse(const Duration(seconds: 5));
      controller.undo();
      async.flushMicrotasks();

      expect(controller.pendingUnsubscribeTimer, isNull);

      // Advance time past 10s total
      async.elapse(const Duration(seconds: 10));
      expect(unsubService.calls, isEmpty);
    });
  });

  test('3. Non-spam verdict cancels pending unsubscribe', () {
    fakeAsync((async) {
      final unsubService = _FakeUnsubscribeService();
      final controller = VerdictController(
        db: db,
        tokenStore: TokenStoreDrift(db),
        reportClient: _FakeReports(),
        unsubscribeService: unsubService,
      );

      controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
      async.flushMicrotasks();

      expect(controller.pendingUnsubscribeTimer, isNotNull);

      // Mark as ham or inbox before 10s
      async.elapse(const Duration(seconds: 3));
      controller.applyVerdict(messageId: 'm', newLabel: Label.ham);
      async.flushMicrotasks();

      expect(controller.pendingUnsubscribeTimer, isNull);

      // Advance past 10s
      async.elapse(const Duration(seconds: 10));
      expect(unsubService.calls, isEmpty);
    });
  });

  test('4. Undo of a ham verdict (which might revert to spam) does not schedule unsubscribe', () {
    fakeAsync((async) {
      // Setup message with initial classification 'spam'
      db.db.execute("UPDATE messages SET classification_label = 'spam' WHERE id = 'm'");

      final unsubService = _FakeUnsubscribeService();
      final controller = VerdictController(
        db: db,
        tokenStore: TokenStoreDrift(db),
        reportClient: _FakeReports(),
        unsubscribeService: unsubService,
      );

      // User marks message as ham (previous label was spam)
      controller.applyVerdict(messageId: 'm', newLabel: Label.ham);
      async.flushMicrotasks();
      expect(controller.pendingUnsubscribeTimer, isNull);

      // User undos the ham verdict -> reverts to spam
      controller.undo();
      async.flushMicrotasks();

      // Ensure that reverting to spam via undo does NOT schedule auto-unsubscribe
      expect(controller.pendingUnsubscribeTimer, isNull);
      expect(controller.pendingUnsubscribeMessageId, isNull);

      async.elapse(const Duration(seconds: 15));
      expect(unsubService.calls, isEmpty);
    });
  });

  test('5. Spam-clicking several messages in a row unsubscribes from each, not just the last', () {
    fakeAsync((async) {
      db.db.execute("INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, sender_domain, recipient_addrs, date, snippet, classification_label) VALUES ('m2', 'a', 'f', 2, 'Other', 's@y.com', 'y.com', '', '2026-11-02T10:00:00', '', 'inbox')");
      db.db.execute("INSERT INTO bodies (message_id, text_body, remote_images_blocked) VALUES ('m2', 'other body', 1)");
      final unsubService = _FakeUnsubscribeService();
      final controller = VerdictController(
        db: db,
        tokenStore: TokenStoreDrift(db),
        reportClient: _FakeReports(),
        unsubscribeService: unsubService,
      );

      controller.applyVerdict(messageId: 'm', newLabel: Label.spam);
      async.flushMicrotasks();
      controller.applyVerdict(messageId: 'm2', newLabel: Label.spam);
      async.flushMicrotasks();
      expect(controller.hasPendingUnsubscribe('m'), isTrue);
      expect(controller.hasPendingUnsubscribe('m2'), isTrue);

      async.elapse(const Duration(seconds: 11));
      expect(unsubService.calls.map((c) => c.messageId).toSet(), {'m', 'm2'});
    });
  });
}
