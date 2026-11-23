import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/community/report_client.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';
import 'package:spamfiltering_emailclient/filter/verdict_controller.dart';

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
}
