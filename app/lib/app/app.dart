import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_app_shell/df_app_shell.dart';
import 'package:df_theme/df_theme.dart';
import '../theme/app_brand.dart';
import '../funnel/launch_gate.dart';
import '../ui/shell/nav_shell.dart';
import 'bootstrap.dart';
import 'router.dart';
import 'strings.dart';

class DataFortressMailApp extends ConsumerWidget {
  const DataFortressMailApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = AppBrand.brand;
    // Settings -> Appearance writes this; without watching it the choice would do nothing.
    final themeMode = ref.watch(dfThemeModeProvider);

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: DfTheme.light(brand),
      darkTheme: DfTheme.dark(brand),
      themeMode: themeMode,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const AppBootstrap(
        child: AppLaunchGate(
          child: AppNavShell(),
        ),
      ),
    );
  }
}
