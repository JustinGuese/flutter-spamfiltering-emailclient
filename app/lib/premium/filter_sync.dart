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
              _applyBlob(key, base64Decode(ciphertextB64));
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
              _applyBlob(key, base64Decode(ciphertextB64));
            }
          }
        }
      }
    } catch (e, st) {
      logError('filter sync pull', e, st);
    }
  }

  void _applyBlob(Uint8List key, Uint8List ciphertext) {
    try {
      final decrypted = _decryptAesGcm(key, ciphertext);
      final json = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
      final state = CrdtTokenState.fromJson(json);

      for (final entry in state.spamTokens.entries) {
        tokenStore.apply(entry.key, Label.spam, entry.value.value);
      }
      for (final entry in state.hamTokens.entries) {
        tokenStore.apply(entry.key, Label.ham, entry.value.value);
      }
    } catch (e, st) {
      logError('filter sync apply blob', e, st);
    }
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
  return FilterSyncService(dio: dio, keyManager: keyManager, tokenStore: tokenStore);
});
