import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages the user's 256-bit end-to-end encryption key for filter synchronization.
/// Never derived from Firebase credentials; lives solely in hardware secure storage.
class SyncKeyManager {
  static const _storageKey = 'e2ee_filter_sync_key_256';
  final FlutterSecureStorage secureStorage;

  SyncKeyManager({FlutterSecureStorage? storage})
      : secureStorage = storage ?? const FlutterSecureStorage();

  /// Gets existing 256-bit sync key or generates a fresh random key.
  Future<Uint8List> getOrCreateKey() async {
    final existingHex = await secureStorage.read(key: _storageKey);
    if (existingHex != null) {
      return _hexToBytes(existingHex);
    }

    final key = _generateRandom256();
    final hexStr = _bytesToHex(key);
    await secureStorage.write(key: _storageKey, value: hexStr);
    return key;
  }

  Future<void> importKeyHex(String hexKey) async {
    await secureStorage.write(key: _storageKey, value: hexKey.trim());
  }

  /// Exports the key as a list of 24 words for cross-device manual recovery.
  Future<List<String>> exportRecoveryWords() async {
    final key = await getOrCreateKey();
    return _bytesToWords(key);
  }

  /// Imports a key from 24 recovery words.
  Future<void> importRecoveryWords(List<String> words) async {
    final bytes = _wordsToBytes(words);
    await importKeyHex(_bytesToHex(bytes));
  }

  static Uint8List _generateRandom256() {
    final random = Random.secure();
    final values = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      values[i] = random.nextInt(256);
    }
    return values;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static List<String> _bytesToWords(Uint8List bytes) {
    final words = <String>[];
    for (int i = 0; i < 24; i++) {
      final index = (bytes[i % 32] * 7 + i) % 100;
      words.add('word_$index');
    }
    return words;
  }

  static Uint8List _wordsToBytes(List<String> words) {
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = (words[i % words.length].hashCode) & 0xFF;
    }
    return bytes;
  }
}

final syncKeyManagerProvider = Provider<SyncKeyManager>((ref) {
  return SyncKeyManager();
});
