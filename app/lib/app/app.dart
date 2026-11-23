import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import '../theme/app_brand.dart';
import '../funnel/launch_gate.dart';
import '../ui/shell/nav_shell.dart';
import 'bootstrap.dart';
import 'router.dart';
import 'strings.dart';

class DataFortressMailApp extends StatelessWidget {
  const DataFortressMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = AppBrand.brand;

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: DfTheme.light(brand),
      darkTheme: DfTheme.dark(brand),
      themeMode: ThemeMode.system,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const AppBootstrap(
        child: AppLaunchGate(
          child: AppNavShell(),
        ),
      ),
    );
  }
}
