import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/ui/mailbox/mailbox_view.dart';
import 'package:sqlite3/sqlite3.dart';

class _FakeEngine implements SyncEngine {
  final calls = <String>[];
  Completer<int>? pending;
  void Function()? onLoaded;

  @override
  Future<int> loadOlder(String folderId) {
    calls.add(folderId);
    return (pending = Completer<int>()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Messages 1..[count] in folder 'f', newest (highest) first in the list.
void _seed(AppDatabase db, int from, int to, {String label = 'inbox'}) {
  for (var i = from; i <= to; i++) {
    final id = 'm$i';
    db.db.execute('''
      INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, sender_domain, recipient_addrs, date, snippet, classification_label)
      VALUES (?, 'a', 'f', ?, ?, 'x@y.com', 'y.com', 'me@y.com', ?, 's', ?)
    ''', [id, i, 'Subject $i', DateTime(2026, 1, 1).add(Duration(hours: i)).toIso8601String(), label]);
  }
}

Future<void> _pump(WidgetTester tester, AppDatabase db, _FakeEngine engine) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db), syncEngineProvider.overrideWithValue(engine)],
    child: const MaterialApp(home: MailboxView()),
  ));
  await tester.pump();
}

void main() {
  late AppDatabase db;
  setUp(() {
    db = AppDatabase(sqlite3.openInMemory());
    db.db.execute("INSERT INTO folders (id, account_id, name, server_path, special_use, unread_count) VALUES ('f', 'a', 'INBOX', 'INBOX', 'inbox', 0)");
  });
  tearDown(() => db.close());

  Finder rows() => find.textContaining('Subject ');

  testWidgets('shows one page, header still counts the whole folder', (tester) async {
    _seed(db, 1, 120);
    await _pump(tester, db, _FakeEngine());
    expect(find.text('Subject 120'), findsOneWidget);
    expect(find.text('Subject 60'), findsNothing, reason: 'beyond the first page of 50');
    expect(find.textContaining('120 messages'), findsOneWidget);
  });

  testWidgets('scrolling to the bottom reveals the next page of stored mail before asking the server', (tester) async {
    _seed(db, 1, 120);
    final engine = _FakeEngine();
    await _pump(tester, db, engine);

    // Row 60 is the 61st newest: only reachable once page two was revealed.
    await tester.scrollUntilVisible(find.text('Subject 60'), 600, scrollable: find.byType(Scrollable).last, maxScrolls: 200);
    expect(find.text('Subject 60'), findsOneWidget);
    expect(engine.calls, isEmpty, reason: 'stored mail is shown first');
  });

  testWidgets('past the last stored message the next page is fetched from the server', (tester) async {
    _seed(db, 31, 60);
    final engine = _FakeEngine();
    await _pump(tester, db, engine);

    await tester.fling(find.byType(Scrollable).last, const Offset(0, -20000), 8000);
    await tester.pump();
    expect(engine.calls, ['f']);
    await tester.pump();
    expect(find.text(UiStrings.loadingOlder), findsOneWidget);

    engine.calls.clear();
    await tester.fling(find.byType(Scrollable).last, const Offset(0, -20000), 8000);
    await tester.pump();
    expect(engine.calls, isEmpty, reason: 'one fetch at a time');

    _seed(db, 1, 30); // older mail, what the engine stored
    engine.pending!.complete(30);
    await tester.pump();
    await tester.pump();
    expect(find.text(UiStrings.loadingOlder), findsNothing);
    await tester.scrollUntilVisible(find.text('Subject 5'), 600, scrollable: find.byType(Scrollable).last, maxScrolls: 200);
    expect(find.text('Subject 5'), findsOneWidget);
  });

  testWidgets('when the server has nothing older the footer goes away and it is not asked again', (tester) async {
    _seed(db, 1, 5);
    final engine = _FakeEngine();
    await _pump(tester, db, engine);

    expect(find.text(UiStrings.loadOlder), findsOneWidget, reason: 'short list cannot scroll, so the footer is the way to ask');
    await tester.tap(find.text(UiStrings.loadOlder));
    await tester.pump();
    engine.pending!.complete(0);
    await tester.pumpAndSettle();

    expect(find.text(UiStrings.loadOlder), findsNothing);
    expect(engine.calls.length, 1);
  });

  testWidgets('a failed fetch offers a retry', (tester) async {
    _seed(db, 1, 5);
    final engine = _FakeEngine();
    await _pump(tester, db, engine);
    await tester.tap(find.text(UiStrings.loadOlder));
    await tester.pump();
    engine.pending!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text(UiStrings.loadOlderFailed), findsOneWidget);

    await tester.tap(find.text(UiStrings.loadOlderFailed));
    await tester.pump();
    expect(engine.calls.length, 2);
    engine.pending!.complete(0);
    await tester.pumpAndSettle();
  });

  testWidgets('filter chips filter and count across the whole folder, not just the loaded page', (tester) async {
    _seed(db, 1, 100);
    _seed(db, 101, 103, label: 'spam');
    await _pump(tester, db, _FakeEngine());
    // The spam rows are the 3 newest, but even if they were deep in the list the chip would count them.
    expect(find.textContaining('103 messages'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ListView).first, matching: find.text(UiStrings.filterSpam)));
    await tester.pump();
    expect(rows(), findsNWidgets(3));
  });
}
