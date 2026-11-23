import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/ui/filter/verdict_bar.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/verdict_controller.dart';

class _FakeVerdicts implements VerdictController {
  @override
  Future<int> applyVerdict({required String messageId, required Label newLabel, void Function(String, Label, int)? onStamp}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('VerdictBar exposes Semantics labels for all three classes', (tester) async {
    final semantics = tester.ensureSemantics();
    final db = await AppDatabase.open(inMemory: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: VerdictBar(
              messageId: 'test_msg_1',
              currentLabel: Label.inbox,
            ),
          ),
        ),
      ),
    );

    // Verify Semantics labels for all three classes
    expect(find.bySemanticsLabel(RegExp(AppStrings.markAsInbox)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(AppStrings.markAsNewsletter)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(AppStrings.markAsSpam)), findsOneWidget);

    semantics.dispose();
    db.close();
  });

  testWidgets('the "Learned" snackbar (which has an Undo action) dismisses itself quickly', (tester) async {
    final db = await AppDatabase.open(inMemory: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          verdictControllerProvider.overrideWithValue(_FakeVerdicts()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: VerdictBar(messageId: 'm', currentLabel: Label.inbox)),
        ),
      ),
    );

    await tester.tap(find.text(AppStrings.verdictSpam));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(AppStrings.verdictLearned), findsOneWidget);

    // A SnackBar with an action persists forever unless persist is false.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.verdictLearned), findsNothing);
    db.close();
  });
}
