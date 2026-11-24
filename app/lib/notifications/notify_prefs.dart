import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import 'notify_types.dart';

/// Manages the user's preferred notification mode, backed by the SQLite `settings` table.
/// Key: `notify_mode`, default: [NotifyMode.instant].
class NotifyModeNotifier extends Notifier<NotifyMode> {
  @override
  NotifyMode build() {
    final db = ref.watch(databaseProvider);
    final rows = db.db.select(
      "SELECT value FROM settings WHERE key = 'notify_mode'",
    );
    if (rows.isEmpty) return NotifyMode.instant;
    final val = rows.first['value'] as String?;
    return NotifyMode.values.firstWhere(
      (m) => m.name == val,
      orElse: () => NotifyMode.instant,
    );
  }

  void setMode(NotifyMode mode) {
    state = mode;
    final db = ref.read(databaseProvider);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('notify_mode', ?)
    ''', [mode.name]);
  }
}

final notifyModeProvider =
    NotifierProvider<NotifyModeNotifier, NotifyMode>(NotifyModeNotifier.new);

/// Tracks whether notifications have been denied/blocked in system settings.
/// Backed by the SQLite `settings` table with key `notify_permission_blocked`.
class NotificationBlockedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(databaseProvider);
    final rows = db.db.select(
      "SELECT value FROM settings WHERE key = 'notify_permission_blocked'",
    );
    if (rows.isEmpty) return false;
    return rows.first['value'] == 'true';
  }

  void setBlocked(bool blocked) {
    state = blocked;
    final db = ref.read(databaseProvider);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('notify_permission_blocked', ?)
    ''', [blocked.toString()]);
  }
}

final notificationBlockedProvider =
    NotifierProvider<NotificationBlockedNotifier, bool>(
  NotificationBlockedNotifier.new,
);

final notifyBlockedProvider = notificationBlockedProvider;

/// Tracks whether the notification soft-ask prompt has been offered at least once.
/// Backed by SQLite settings table with key `notify_soft_asked`.
class NotifySoftAskedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(databaseProvider);
    final rows = db.db.select(
      "SELECT value FROM settings WHERE key = 'notify_soft_asked'",
    );
    if (rows.isEmpty) return false;
    return rows.first['value'] == 'true';
  }

  void markOffered() => setOffered(true);

  void setOffered(bool offered) {
    state = offered;
    final db = ref.read(databaseProvider);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('notify_soft_asked', ?)
    ''', [offered.toString()]);
  }
}

final notifySoftAskedProvider =
    NotifierProvider<NotifySoftAskedNotifier, bool>(
  NotifySoftAskedNotifier.new,
);

