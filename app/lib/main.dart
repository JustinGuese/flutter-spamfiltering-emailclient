import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:df_notifications/df_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/log.dart';
import 'db/database.dart';
import 'notifications/mail_notification_service.dart';
import 'platform/platform_services.dart';
import 'platform/native_services.dart';
import 'platform/desktop_services.dart';
import 'api/api_client.dart';
import 'filter/cold_start.dart';
import 'filter/token_store_drift.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing fails silently: framework errors and uncaught async errors both
  // end up in the console.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError('flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('uncaught', error, stack);
    return true;
  };

  // 1. Open local database
  final db = await AppDatabase.open();

  // 2. Select platform services (Native vs Desktop split)
  final isDesktop = Platform.isWindows || Platform.isLinux;
  final AppPlatformServices services = isDesktop
      ? DesktopPlatformServices()
      : NativePlatformServices();

  await services.initialize();

  // 3. Cold start training (prior model + contacts)
  final tokenStore = TokenStoreDrift(db);
  final coldStart = ColdStartTrainer(db: db, tokenStore: tokenStore);
  await coldStart.runColdStart();

  // 4. Run application with configured ProviderScope
  final platformOverrides = isDesktop
      ? (services as DesktopPlatformServices).overrides
      : (services as NativePlatformServices).overrides;

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        platformServicesProvider.overrideWithValue(services),
        apiClientOverride,
        dfNotificationConfigProvider.overrideWithValue(
          const DfNotificationConfig(
            windowsAppName: 'DataFortress Mail',
            windowsAppUserModelId: 'DataFortress.Mail',
            windowsGuid: 'f87a8b60-7058-47bc-9df2-501b44ecdcbb',
            defaultChannel: kMailNotificationChannel,
          ),
        ),
        ...platformOverrides,
      ],
      child: const DataFortressMailApp(),
    ),
  );
}
