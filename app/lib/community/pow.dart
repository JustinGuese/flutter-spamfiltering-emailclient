import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Hashcash-style Proof-of-Work solver for anonymous report rate-limiting.
class ProofOfWork {
  /// Solves a PoW puzzle with [difficulty] leading zero bits for given [payload].
  static String solve(String challenge, {int difficulty = 8}) {
    int nonce = 0;
    while (true) {
      final input = '$challenge:$nonce';
      final digest = sha256.convert(utf8.encode(input)).bytes;
      if (_hasLeadingZeroBits(digest, difficulty)) {
        return '$challenge:$nonce';
      }
      nonce++;
    }
  }

  static bool _hasLeadingZeroBits(List<int> bytes, int bits) {
    int fullBytes = bits ~/ 8;
    int remainingBits = bits % 8;

    for (int i = 0; i < fullBytes; i++) {
      if (bytes[i] != 0) return false;
    }

    if (remainingBits > 0) {
      int mask = (0xFF << (8 - remainingBits)) & 0xFF;
      if ((bytes[fullBytes] & mask) != 0) return false;
    }

    return true;
  }
}
