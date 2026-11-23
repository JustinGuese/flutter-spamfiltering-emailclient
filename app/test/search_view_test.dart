import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/ui/search/search_view.dart';
import 'package:sqlite3/sqlite3.dart';

class _FakeEngine implements SyncEngine {
  final calls = <String>[];
  Completer<({int imported, int failed, String? error})>? pending;

  @override
  Future<({int imported, int failed, String? error})> searchRemote(String input) {
    calls.add(input);
    return (pending = Completer()).future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _msg(AppDatabase db, String id, String subject) {
  db.db.execute('''
    INSERT INTO messages (id, account_id, folder_id, uid, subject, sender, sender_domain, recipient_addrs, date, snippet)
    VALUES (?, 'a', 'f', 1, ?, 'x@y.com', 'y.com', 'me@y.com', '2026-11-01T10:00:00', 's')
  ''', [id, subject]);
  db.db.execute("INSERT INTO bodies (message_id, text_body) VALUES (?, 'body')", [id]);
}

void main() {
  testWidgets('shows local hits at once, then asks the server and shows what it added', (tester) async {
    final db = AppDatabase(sqlite3.openInMemory());
    _msg(db, 'local', 'Invoice from the shop');
    final engine = _FakeEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), syncEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(home: Scaffold(body: SearchView())),
    ));

    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pump();
    expect(find.text('Invoice from the shop'), findsOneWidget, reason: 'local results need no server');
    expect(engine.calls, isEmpty, reason: 'the server is asked only after typing pauses');

    await tester.pump(const Duration(milliseconds: 800));
    expect(engine.calls, ['invoice']);
    expect(find.text(AppStrings.searchServerSearching), findsOneWidget);

    _msg(db, 'remote', 'Old invoice 2019'); // what the engine imports
    engine.pending!.complete((imported: 1, failed: 0, error: null));
    await tester.pump();
    expect(find.text(AppStrings.searchServerAdded(1)), findsOneWidget);
    expect(find.text('Old invoice 2019'), findsOneWidget);
    db.close();
  });

  testWidgets('a failed server search says so and keeps the local results', (tester) async {
    final db = AppDatabase(sqlite3.openInMemory());
    _msg(db, 'local', 'Invoice');
    final engine = _FakeEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), syncEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(home: Scaffold(body: SearchView())),
    ));
    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pump(const Duration(milliseconds: 800));
    engine.pending!.complete((imported: 0, failed: 1, error: 'No saved password'));
    await tester.pump();
    expect(find.text(AppStrings.searchServerFailed('No saved password')), findsOneWidget, reason: 'says why');
    expect(find.text('Invoice'), findsOneWidget);

    await tester.tap(find.text(AppStrings.searchServerRetry));
    await tester.pump();
    expect(engine.calls, ['invoice', 'invoice']);
    db.close();
  });

  testWidgets('queries only this device can answer never go to the server', (tester) async {
    final db = AppDatabase(sqlite3.openInMemory());
    final engine = _FakeEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), syncEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(home: Scaffold(body: SearchView())),
    ));
    await tester.enterText(find.byType(TextField), 'is:spam cheap');
    await tester.pump(const Duration(milliseconds: 800));
    expect(engine.calls, isEmpty);
    db.close();
  });
}
