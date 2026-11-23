import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import 'report_client.dart';

class BlocklistSyncService {
  final AppDatabase db;
  final CommunityReportClient client;
  Timer? _periodicTimer;

  BlocklistSyncService({
    required this.db,
    required this.client,
  });

  void startPeriodicSync() {
    _periodicTimer?.cancel();
    // Periodic sync every 6 hours
    _periodicTimer = Timer.periodic(const Duration(hours: 6), (_) {
      sync();
    });
    // Trigger initial sync
    sync();
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> sync() async {
    final verRow = db.db.select(
      "SELECT value FROM settings WHERE key = 'blocklist_version'",
    );
    final currentVer = int.tryParse(verRow.firstOrNull?['value'] as String? ?? '0') ?? 0;

    if (currentVer == 0) {
      final snapshot = await client.fetchSnapshot();
      if (snapshot != null) {
        _applySnapshot(snapshot);
      }
    } else {
      final delta = await client.fetchDelta(currentVer);
      if (delta != null) {
        _applyDelta(delta);
      }
    }
  }

  void _applySnapshot(Map<String, dynamic> snapshot) {
    final version = snapshot['version'] as int? ?? 1;
    final entries = snapshot['fingerprints'] as List<dynamic>? ?? [];

    db.db.execute('BEGIN TRANSACTION');
    db.db.execute('DELETE FROM blocklist_entries');

    for (final e in entries) {
      if (e is Map<String, dynamic>) {
        final id = e['id'].toString();
        final type = e['type'] as String? ?? 'url_hash';
        final hashValue = (e['hash'] as num).toInt();
        db.db.execute('''
          INSERT OR REPLACE INTO blocklist_entries (id, type, hash_value, added_at)
          VALUES (?, ?, ?, ?)
        ''', [id, type, hashValue, DateTime.now().toIso8601String()]);
      } else if (e is num) {
        final hashValue = e.toInt();
        db.db.execute('''
          INSERT OR REPLACE INTO blocklist_entries (id, type, hash_value, added_at)
          VALUES (?, ?, ?, ?)
        ''', ['fp_$hashValue', 'url_hash', hashValue, DateTime.now().toIso8601String()]);
      }
    }

    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('blocklist_version', ?)
    ''', [version.toString()]);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('blocklist_last_sync', ?)
    ''', [DateTime.now().toIso8601String()]);

    db.db.execute('COMMIT');
  }

  void _applyDelta(Map<String, dynamic> delta) {
    final nextVersion = delta['version'] as int? ?? 1;
    final added = delta['added'] as List<dynamic>? ?? [];
    final removed = delta['removed'] as List<dynamic>? ?? [];

    db.db.execute('BEGIN TRANSACTION');
    for (final rem in removed) {
      if (rem is Map<String, dynamic>) {
        db.db.execute('DELETE FROM blocklist_entries WHERE id = ?', [rem['id'].toString()]);
      } else {
        db.db.execute('DELETE FROM blocklist_entries WHERE id = ? OR hash_value = ?', [rem.toString(), rem]);
      }
    }
    for (final add in added) {
      if (add is Map<String, dynamic>) {
        db.db.execute('''
          INSERT OR REPLACE INTO blocklist_entries (id, type, hash_value, added_at)
          VALUES (?, ?, ?, ?)
        ''', [
          add['id'].toString(),
          add['type'] as String? ?? 'url_hash',
          (add['hash'] as num).toInt(),
          DateTime.now().toIso8601String(),
        ]);
      } else if (add is num) {
        final hashValue = add.toInt();
        db.db.execute('''
          INSERT OR REPLACE INTO blocklist_entries (id, type, hash_value, added_at)
          VALUES (?, ?, ?, ?)
        ''', ['fp_$hashValue', 'url_hash', hashValue, DateTime.now().toIso8601String()]);
      }
    }
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('blocklist_version', ?)
    ''', [nextVersion.toString()]);
    db.db.execute('''
      INSERT OR REPLACE INTO settings (key, value)
      VALUES ('blocklist_last_sync', ?)
    ''', [DateTime.now().toIso8601String()]);
    db.db.execute('COMMIT');
  }
}

final blocklistSyncProvider = Provider<BlocklistSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return BlocklistSyncService(db: db, client: CommunityReportClient());
});
