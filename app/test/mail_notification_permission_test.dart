import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:df_notifications/df_notifications.dart';
import 'package:spamfiltering_emailclient/app/ui_strings.dart';
import 'package:spamfiltering_emailclient/notifications/mail_notification_permission.dart';

class _FakeReminderService extends DfReminderService {
  _FakeReminderService() : super.base();

  bool requested = false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    requested = true;
    return true;
  }

  @override
  Future<void> schedule(DfReminder reminder) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelMany(Iterable<int> ids) async {}

  @override
  String? consumePendingPayload() => null;
}

void main() {
  testWidgets('ensureMailNotificationPermission shows mail copy and no reminder copy', (tester) async {
    final fakeService = _FakeReminderService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dfReminderServiceProvider.overrideWithValue(fakeService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return ElevatedButton(
                  onPressed: () => ensureMailNotificationPermission(context, ref),
                  child: const Text('Ask'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    // Verify mail copy is displayed
    expect(find.text(UiStrings.notifyPrimingTitle), findsOneWidget);
    expect(find.text(UiStrings.notifyPrimingBody), findsOneWidget);
    expect(find.text(UiStrings.notifyPrimingAccept), findsOneWidget);
    expect(find.text(UiStrings.notifyPrimingDecline), findsOneWidget);

    // Verify no generic reminder copy is present
    expect(find.textContaining('Stay on track'), findsNothing);
    expect(find.textContaining('remind'), findsNothing);
    expect(find.textContaining('Remind'), findsNothing);

    // Tap accept to verify integration
    await tester.tap(find.text(UiStrings.notifyPrimingAccept));
    await tester.pumpAndSettle();

    expect(fakeService.requested, isTrue);
  });
}
