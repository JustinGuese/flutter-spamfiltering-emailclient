import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'package:spam_core/spam_core.dart';
import '../api/api_client.dart';
import 'sync_key.dart';
import 'crdt_counters.dart';
import '../db/database.dart';
import '../filter/token_store_drift.dart';
import '../app/log.dart';

/// End-to-end encrypted filter synchronization using AES-256-GCM and CRDT PN-counters.
class FilterSyncService {
  final Dio dio;
  final SyncKeyManager keyManager;
  final TokenStoreDrift tokenStore;
  final String deviceSlot;

  FilterSyncService({
    required this.dio,
    required this.keyManager,
    required this.tokenStore,
    String? deviceSlot,
  }) : deviceSlot = deviceSlot ?? 'slot_0';

  /// Encrypts and uploads the current device's CRDT token state.
  Future<bool> uploadDeviceState(CrdtTokenState state) async {
    try {
      final key = await keyManager.getOrCreateKey();
      final plaintext = utf8.encode(jsonEncode(state.toJson()));
      final ciphertext = _encryptAesGcm(key, Uint8List.fromList(plaintext));

      final res = await dio.put(
        '/v1/sync/blobs/$deviceSlot',
        data: {'ciphertext': base64Encode(ciphertext)},
      );
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e, st) {
      logError('filter sync upload', e, st);
      return false;
    }
  }

  /// Downloads all device sync slots, decrypts them, and sums counters into local token store.
  Future<void> syncAllSlots([List<String>? allSlots]) async {
    final key = await keyManager.getOrCreateKey();

    try {
      if (allSlots == null || allSlots.isEmpty) {
        final res = await dio.get('/v1/sync/blobs');
        if (res.statusCode == 200 && res.data is List) {
          for (final item in res.data as List) {
            final slot = item['slot'] as String?;
            if (slot == deviceSlot) continue;
            final ciphertextB64 = item['ciphertext'] as String?;
            if (ciphertextB64 != null) {
              _applyBlob(slot ?? '', key, base64Decode(ciphertextB64));
            }
          }
        }
      } else {
        for (final slot in allSlots) {
          if (slot == deviceSlot) continue;
          final res = await dio.get('/v1/sync/blobs/$slot');
          if (res.statusCode == 200 && res.data != null) {
            String? ciphertextB64;
            if (res.data is Map) {
              ciphertextB64 = (res.data as Map)['ciphertext'] as String?;
            }
            if (ciphertextB64 != null) {
              _applyBlob(slot, key, base64Decode(ciphertextB64));
            }
          }
        }
      }
    } catch (e, st) {
      logError('filter sync pull', e, st);
    }
  }

  /// Applies another device's state. Blobs carry that device's full counts,
  /// so only the change since the last blob applied from [slot] is added
  /// (tracked in `sync_applied`); re-pulling the same blob changes nothing.
  void _applyBlob(String slot, Uint8List key, Uint8List ciphertext) {
    try {
      final decrypted = _decryptAesGcm(key, ciphertext);
      final json = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
      applyRemoteState(slot, CrdtTokenState.fromJson(json));
    } catch (e, st) {
      logError('filter sync apply blob', e, st);
    }
  }

  /// Adds the change in [slot]'s counts since its last applied state.
  void applyRemoteState(String slot, CrdtTokenState state) {
    if (slot.isEmpty || slot == deviceSlot) return;
    final db = tokenStore.db.db;
    final remote = <int, (int, int)>{};
    state.spamTokens.forEach((h, c) => remote[h] = (c.value, remote[h]?.$2 ?? 0));
    state.hamTokens.forEach((h, c) => remote[h] = (remote[h]?.$1 ?? 0, c.value));
    final applied = <int, (int, int)>{
      for (final r in db.select('SELECT hash, spam, ham FROM sync_applied WHERE slot = ?', [slot]))
        (r['hash'] as num).toInt(): ((r['spam'] as int?) ?? 0, (r['ham'] as int?) ?? 0),
    };

    db.execute('BEGIN');
    try {
      for (final hash in {...remote.keys, ...applied.keys}) {
        final (rs, rh) = remote[hash] ?? (0, 0);
        final (as_, ah) = applied[hash] ?? (0, 0);
        if (rs != as_) tokenStore.apply(hash, Label.spam, rs - as_);
        if (rh != ah) tokenStore.apply(hash, Label.ham, rh - ah);
        if (rs == as_ && rh == ah) continue;
        db.execute(
          'INSERT OR REPLACE INTO sync_applied (slot, hash, spam, ham) VALUES (?, ?, ?, ?)',
          [slot, hash, rs, rh],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    // Blobs carry token counts but no message totals; derive them again.
    tokenStore.reconcileMessageTotals();
  }

  /// This device's own learning: token counts minus the bundled seed prior
  /// (every device has it) and minus what was applied from other devices
  /// (they upload that themselves). Uploading anything more would echo the
  /// other devices' counts back and inflate them on every round trip.
  CrdtTokenState ownState() {
    final rows = tokenStore.db.db.select('''
      SELECT t.hash,
             t.spam - COALESCE(p.spam, 0) - COALESCE(a.spam, 0) AS s,
             t.ham - COALESCE(p.ham, 0) - COALESCE(a.ham, 0) AS h
      FROM tokens t
      LEFT JOIN prior_tokens p ON p.hash = t.hash
      LEFT JOIN (SELECT hash, SUM(spam) AS spam, SUM(ham) AS ham FROM sync_applied GROUP BY hash) a
        ON a.hash = t.hash
    ''');
    PNCounter counter(int v) => PNCounter(positive: v > 0 ? v : 0, negative: v < 0 ? -v : 0);
    final spam = <int, PNCounter>{};
    final ham = <int, PNCounter>{};
    for (final r in rows) {
      final h = (r['hash'] as num).toInt();
      final s = (r['s'] as num).toInt();
      final hm = (r['h'] as num).toInt();
      if (s != 0) spam[h] = counter(s);
      if (hm != 0) ham[h] = counter(hm);
    }
    return CrdtTokenState(deviceId: deviceSlot, spamTokens: spam, hamTokens: ham);
  }

  static Uint8List _encryptAesGcm(Uint8List key, Uint8List plaintext) {
    final iv = Uint8List(12);
    final random = Random.secure();
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final out = cipher.process(plaintext);

    final result = Uint8List(12 + out.length);
    result.setRange(0, 12, iv);
    result.setRange(12, 12 + out.length, out);
    return result;
  }

  static Uint8List _decryptAesGcm(Uint8List key, Uint8List payload) {
    final iv = payload.sublist(0, 12);
    final ciphertext = payload.sublist(12);

    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return cipher.process(ciphertext);
  }
}

final filterSyncServiceProvider = Provider<FilterSyncService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  final keyManager = ref.watch(syncKeyManagerProvider);
  final tokenStore = ref.watch(tokenStoreProvider);
  return FilterSyncService(
    dio: dio,
    keyManager: keyManager,
    tokenStore: tokenStore,
    deviceSlot: deviceSyncSlot(tokenStore.db),
  );
});

/// This install's sync slot, created once and kept in settings. Every device
/// used to default to `slot_0`, so all devices wrote the same blob and skipped
/// it when pulling: nothing was ever exchanged.
String deviceSyncSlot(AppDatabase db) {
  const key = 'sync_device_slot';
  final existing = db.getSetting(key);
  if (existing != null && existing.isNotEmpty) return existing;
  final rnd = Random.secure();
  final slot = 'dev_${List.generate(8, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  db.setSetting(key, slot);
  return slot;
}
