import 'package:flutter_riverpod/flutter_riverpod.dart';

/// C4 AppPlatformServices abstract contract.
/// Two implementations are selected at startup:
/// - native: iOS, Android, macOS (df_firebase_auth, df_revenuecat)
/// - desktop: Windows, Linux (df_firebase_rest, df_billing, no-op sinks)
abstract class AppPlatformServices {
  Future<void> initialize();
  bool get isDesktop;
  String get platformName;
}

/// Provider holding the active platform services implementation.
final platformServicesProvider = Provider<AppPlatformServices>((ref) {
  throw UnimplementedError('platformServicesProvider must be initialized at startup');
});

class ListDensityNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle() => state = !state;
  void set(bool val) => state = val;
}

/// Reactive provider for list density: true = comfortable (72dp), false = compact (52dp).
final listDensityComfortableProvider = NotifierProvider<ListDensityNotifier, bool>(ListDensityNotifier.new);

class SelectedFolderIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? val) => state = val;
}

/// Selected mailbox folder ID provider.
final selectedFolderIdProvider = NotifierProvider<SelectedFolderIdNotifier, String?>(SelectedFolderIdNotifier.new);

class SelectedMessageIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? val) => state = val;
}

/// Selected message ID provider for master-detail.
final selectedMessageIdProvider = NotifierProvider<SelectedMessageIdNotifier, String?>(SelectedMessageIdNotifier.new);
