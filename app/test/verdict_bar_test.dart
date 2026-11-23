import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/ui/filter/verdict_bar.dart';
import 'package:spamfiltering_emailclient/app/strings.dart';
import 'package:spamfiltering_emailclient/db/database.dart';

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
}
