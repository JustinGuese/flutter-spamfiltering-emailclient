import 'dart:io';
import 'dart:typed_data';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/mail/account_repository.dart';
import 'package:spamfiltering_emailclient/mail/attachments.dart';
import 'package:spamfiltering_emailclient/mail/reply_builder.dart';
import 'package:spamfiltering_emailclient/mail/sync_engine.dart';
import 'package:spamfiltering_emailclient/ui/compose/compose_view.dart';
import 'package:spamfiltering_emailclient/ui/reader/attachment_strip.dart';
import 'package:sqlite3/sqlite3.dart';

class _Storage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Engine implements SyncEngine {
  final downloads = <int>[];
  final List<AttachmentMeta> files;
  Object? downloadError;
  _Engine(this.files);

  @override
  Future<List<AttachmentMeta>> attachmentsOf(String messageId) async => files;

  @override
  Future<File> downloadAttachment(int attachmentId) async {
    downloads.add(attachmentId);
    if (downloadError != null) throw downloadError!;
    return File('${Directory.systemTemp.path}/does-not-matter.txt');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _app(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  group('AttachmentStrip', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(sqlite3.openInMemory()));
    tearDown(() => db.close());

    testWidgets('lists the files with sizes and downloads one when tapped', (tester) async {
      final engine = _Engine([
        const AttachmentMeta(id: 1, fetchId: '2', fileName: 'Report.pdf', mimeType: 'application/pdf', size: 2 * 1024 * 1024),
        const AttachmentMeta(id: 2, fetchId: '3', fileName: 'photo.jpg', mimeType: 'image/jpeg', size: 900),
      ]);
      final opened = <String>[];
      await tester.pumpWidget(_app(
        AttachmentStrip(
          messageId: 'm',
          opener: (path) async {
            opened.add(path);
            return OpenResult(type: ResultType.noAppToOpen, message: 'none');
          },
        ),
        [databaseProvider.overrideWithValue(db), syncEngineProvider.overrideWithValue(engine)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Report.pdf'), findsOneWidget);
      expect(find.text('2.0 MB'), findsOneWidget);
      expect(find.text('900 B'), findsOneWidget);
      expect(find.textContaining('ATTACHMENTS · 2'), findsOneWidget);

      await tester.tap(find.text('Report.pdf'));
      await tester.pumpAndSettle();
      expect(engine.downloads, [1]);
      expect(opened, hasLength(1));
      expect(find.textContaining('No app on this device can open "Report.pdf"'), findsOneWidget);
    });

    testWidgets('a program is not opened: it warns, and Cancel downloads nothing', (tester) async {
      final engine = _Engine([const AttachmentMeta(id: 7, fetchId: '2', fileName: 'invoice.exe', mimeType: 'application/octet-stream', size: 10)]);
      await tester.pumpWidget(_app(const AttachmentStrip(messageId: 'm'), [
        databaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(engine),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('invoice.exe'));
      await tester.pumpAndSettle();
      expect(find.text(UiStrings.attachmentRunnableTitle), findsOneWidget);

      await tester.tap(find.text(UiStrings.attachmentCancel));
      await tester.pumpAndSettle();
      expect(engine.downloads, isEmpty);
    });

    testWidgets('a download that fails says why', (tester) async {
      final engine = _Engine([const AttachmentMeta(id: 1, fetchId: '2', fileName: 'a.pdf', mimeType: 'application/pdf')])
        ..downloadError = StateError('This message is no longer on the mail server.');
      await tester.pumpWidget(_app(const AttachmentStrip(messageId: 'm'), [
        databaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(engine),
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a.pdf'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer on the mail server'), findsOneWidget);
    });
  });

  group('ComposeView', () {
    late AppDatabase db;
    setUp(() {
      db = AppDatabase(sqlite3.openInMemory());
      db.db.execute(
        "INSERT INTO accounts (id, email, display_name, imap_host, imap_port, smtp_host, smtp_port, auth_type, created_at) "
        "VALUES ('a1', 'me@example.com', 'me', 'i', 993, 's', 587, 'password', '2026-01-01T00:00:00Z')",
      );
    });
    tearDown(() => db.close());

    Widget compose(ComposeDraft draft) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            accountRepositoryProvider.overrideWithValue(AccountRepository(db: db, storage: _Storage())),
          ],
          child: MaterialApp(home: ComposeView(draft: draft)),
        );

    testWidgets('a forward opens with the original files attached, and they can be removed', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(compose(ComposeDraft(
        accountId: 'a1',
        subject: 'Fwd: x',
        attachments: [
          OutgoingAttachment(fileName: 'plan.pdf', mimeType: 'application/pdf', size: 3 * 1024, load: () async => Uint8List(3)),
          OutgoingAttachment(fileName: 'pic.png', mimeType: 'image/png', size: 0, load: () async => Uint8List(0)),
        ],
      )));
      await tester.pump();

      expect(find.textContaining('plan.pdf · 3 KB'), findsOneWidget);
      expect(find.text('pic.png'), findsOneWidget);
      expect(find.byTooltip(AppStrings.composeAttach), findsOneWidget);

      await tester.tap(find.byTooltip(UiStrings.attachRemove.replaceAll('{name}', 'plan.pdf')));
      await tester.pump();
      expect(find.textContaining('plan.pdf'), findsNothing);
      expect(find.text('pic.png'), findsOneWidget);
    });

    testWidgets('sending without a recipient says so instead of doing nothing', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(compose(const ComposeDraft(accountId: 'a1')));
      await tester.pump();
      await tester.tap(find.text(UiStrings.send));
      await tester.pump();
      expect(find.text(UiStrings.sendNeedsRecipient), findsOneWidget);
    });
  });
}
