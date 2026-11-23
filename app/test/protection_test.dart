import 'dart:convert';
import 'dart:math' as math;
import 'package:df_funnel/df_funnel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/protection_stats.dart';
import 'package:spamfiltering_emailclient/ui/protection/protection_view.dart';

/// Score a message would get with the community signal (+3.5 logit) on top of [local].
double _withCommunity(double local) => 1 / (1 + math.exp(-(math.log(local / (1 - local)) + 3.5)));

void _spam(AppDatabase db, String id, double score, {bool community = false, bool byYou = false, String date = '2026-11-02T10:00:00'}) {
  db.db.execute(
    "INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, recipient_addrs, date, snippet) VALUES (?, 'a', 'f', 1, ?, 's@x.com', '', ?, '')",
    [id, 'Subject $id', date],
  );
  db.db.execute(
    'INSERT INTO classifications (message_id, label, spam_score, evidence_json, classified_at, user_overridden) VALUES (?, ?, ?, ?, ?, ?)',
    [id, 'spam', score, jsonEncode(community ? [{'id': 'community', 'weight': 0.6, 'detail': ''}] : []), '2026-11-02', byYou ? 1 : 0],
  );
}

void main() {
  late AppDatabase db;
  setUp(() async => db = await AppDatabase.open(inMemory: true));
  tearDown(() => db.close());

  test('splits spam into filter-caught and community-only by re-scoring without the blocklist', () {
    _spam(db, 'strong', 0.99); // no community signal at all
    _spam(db, 'both', 0.999, community: true); // filter alone would still have caught it
    _spam(db, 'tipped', _withCommunity(0.20), community: true); // only the blocklist got it over 0.60
    _spam(db, 'yours', 0.95, byYou: true);

    final s = computeProtection(db);

    expect(s.total, 4);
    expect(s.filterCaught, 3);
    expect(s.communityOnly, 1);
    expect(s.corrections, 1);
    expect(s.reachInboxNoFilter, 4);
    expect(s.reachInboxFilter, 1);
    expect(s.reachInboxCommunity, 0);
    expect(s.recent.firstWhere((m) => m.id == 'tipped').by, CaughtBy.community);
    expect(s.recent.firstWhere((m) => m.id == 'both').communityMatched, isTrue);
  });

  test('only spam counts, newest first, and the list is capped', () {
    _spam(db, 'old', 0.99, date: '2026-01-01T00:00:00');
    _spam(db, 'new', 0.99, date: '2026-11-01T00:00:00');
    db.db.execute("INSERT INTO classifications VALUES ('h', 'inbox', 0.01, '[]', '2026', 0)");

    final s = computeProtection(db, recentLimit: 1);

    expect(s.total, 2);
    expect(s.recent.map((m) => m.id), ['new']);
  });

  test('an empty database yields an empty (sample-worthy) result', () {
    expect(computeProtection(db).isEmpty, isTrue);
  });

  Future<void> pump(WidgetTester tester, {bool pro = false, ProtectionTab tab = ProtectionTab.story}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dfEffectivePremiumProvider.overrideWithValue(pro),
      ],
      child: MaterialApp(home: ProtectionView(initialTab: tab)),
    ));
    await tester.pump();
  }

  testWidgets('with no data it shows a labelled sample and walks through the stages', (tester) async {
    await pump(tester);
    expect(find.text('${UiStrings.storySampleTitle}. '), findsNothing); // part of a rich span
    expect(find.textContaining(UiStrings.storySampleBody, findRichText: true), findsOneWidget);

    await tester.tap(find.text(UiStrings.stageNoFilter));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('47'), findsOneWidget);

    await tester.tap(find.text(UiStrings.stageCommunity));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.text(UiStrings.stagePro));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(UiStrings.proPanelTitle), findsOneWidget);
    expect(find.text('812'), findsOneWidget, reason: 'Pro hands the learned words to a new device');
    await tester.pumpWidget(const SizedBox()); // stop autoplay timers
  });

  testWidgets('free users get the upgrade card; Pro users do not', (tester) async {
    await pump(tester);
    expect(find.text(AppStrings.proUpgrade), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await pump(tester, pro: true);
    expect(find.text(AppStrings.proUpgrade), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Learned tab reports real counts and says only hashes are stored', (tester) async {
    db.db.execute('INSERT INTO tokens (hash, spam, ham) VALUES (1, 5, 0), (2, 0, 4), (3, 0, 9)');
    _spam(db, 'm', 0.99);
    await pump(tester, tab: ProtectionTab.learned);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('3'), findsOneWidget);
    expect(find.text(UiStrings.learnedPrivacy), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
