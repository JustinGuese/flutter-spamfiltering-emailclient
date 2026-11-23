import 'package:material_ui/material_ui.dart';
import '../ui/shell/nav_shell.dart';
import '../ui/account_setup/account_setup_view.dart';
import '../ui/compose/compose_view.dart';

/// Top-level app routes.
class AppRouter {
  static const home = '/';
  static const accountSetup = '/setup';
  static const compose = '/compose';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const AppNavShell());
      case accountSetup:
        return MaterialPageRoute(builder: (_) => const AccountSetupView());
      case compose:
        return MaterialPageRoute(builder: (_) => const ComposeView());
      default:
        return MaterialPageRoute(builder: (_) => const AppNavShell());
    }
  }
}
