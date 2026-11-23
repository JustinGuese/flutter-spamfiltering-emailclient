import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'contracts.dart';

/// Produces privacy-preserving body, URL, and sender domain fingerprints.
class Fingerprinter {
  // 32 pseudo-random 64-bit seeds for MinHash
  static const List<int> _minHashSeeds = [
    0x243f6a8885a308d3, 0x13198a2e03707344, 0xa4093822299f31d0, 0x082efa98ec4e6c89,
    0x452821e638d01377, 0xbe5466cf34e90c6c, 0xc0ac29b7c97c50dd, 0x3f84d5b5b5470917,
    0x9216d5d98979fb1b, 0xd1310ba698dfb5ac, 0x2ffd72dbd01adfb7, 0xb8e1afed6a267e96,
    0xba7c9045f12c7f99, 0x24a19947b3916cf7, 0x0801f2e2858efc16, 0x636920d871574e69,
    0xa458fea3f4933d7e, 0x0d95748f728eb658, 0x718bcd5882154aee, 0x7b54a41dc25a59b5,
    0x9c30d5392af26013, 0xc5d1b023286085f0, 0xca417918b8db38ef, 0x8e79dcb0603a180e,
    0x6c9e0e8bb01e8a3e, 0xd7535d5a3a0329c6, 0xdf0fc52e3995f700, 0x877296ff0f8fe6e8,
    0xd95701ad83f2a893, 0x4f12270ca8c253b2, 0xd9ba618a804cb7b8, 0xba6a0538f7a6f7b1,
  ];

  static const Set<String> _multiPartTlds = {
    'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'net.uk',
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'go.jp',
    'co.nz', 'net.nz', 'org.nz',
    'com.br', 'org.br', 'net.br',
    'co.za', 'org.za',
    'com.sg', 'org.sg',
  };

  /// Computes fingerprints for the given normalized message.
  static Fingerprints fingerprints(Normalized normalized) {
    // 1. Body bands (MinHash 32 / LSH 8x4)
    final bodyBands = _computeBodyBands(normalized);

    // 2. URL hashes (eTLD+1 and host+first path segment)
    final urlHashes = _computeUrlHashes(normalized.extractedUrls);

    // 3. Sender domain hash (skipped for freemail)
    int? senderDomainHash;
    if (normalized.senderDomain != null && !normalized.isSenderFreemail) {
      senderDomainHash = _hash64(normalized.senderDomain!.toLowerCase());
    }

    return Fingerprints(
      bodyBands: bodyBands,
      urlHashes: urlHashes,
      senderDomainHash: senderDomainHash,
    );
  }

  static List<int> _computeBodyBands(Normalized normalized) {
    final words = normalized.cleanedText
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && RegExp(r'[a-zA-Z0-9]').hasMatch(w))
        .toList();

    // S1 requirement: "none for bodies < 40 words"
    if (words.length < 40) {
      return const [];
    }

    // Build word 3-shingles
    final shingles = <String>[];
    for (var i = 0; i <= words.length - 3; i++) {
      shingles.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
    }

    if (shingles.isEmpty) {
      return const [];
    }

    // MinHash across 32 hash functions
    final minHashes = List<int>.filled(32, 0x7FFFFFFFFFFFFFFF);
    for (final shingle in shingles) {
      final shingleBytes = utf8.encode(shingle);
      for (var j = 0; j < 32; j++) {
        final h = _fnv1a64(shingleBytes, _minHashSeeds[j]);
        if (h < minHashes[j]) {
          minHashes[j] = h;
        }
      }
    }

    // 8 LSH bands x 4 rows
    final bands = <int>[];
    for (var b = 0; b < 8; b++) {
      var bandHash = 0xcbf29ce484222325;
      for (var r = 0; r < 4; r++) {
        final v = minHashes[b * 4 + r];
        bandHash ^= v;
        bandHash = (bandHash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
      }
      bands.add(bandHash);
    }

    return bands;
  }

  static List<int> _computeUrlHashes(List<String> urls) {
    final hashes = <int>{};

    for (final raw in urls) {
      final parsed = Uri.tryParse(raw);
      if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
        continue;
      }

      final host = parsed.host.toLowerCase();
      final etldPlus1 = _extractEtldPlusOne(host);
      hashes.add(_hash64(etldPlus1));

      // host + first path segment
      final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
      final hostFirstPath = segments.isNotEmpty ? '$host/${segments.first}' : host;
      hashes.add(_hash64(hostFirstPath));
    }

    return hashes.toList();
  }

  static String _extractEtldPlusOne(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;

    // Check multi-part TLD (e.g. example.co.uk)
    final lastTwo = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
    if (_multiPartTlds.contains(lastTwo) && parts.length >= 3) {
      return '${parts[parts.length - 3]}.$lastTwo';
    }

    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }

  static int _hash64(String input) {
    final digest = sha256.convert(utf8.encode(input)).bytes;
    var result = 0;
    for (var i = 0; i < 8; i++) {
      result = (result << 8) | digest[i];
    }
    // Return positive 63-bit int for clean cross-platform JSON/DB storage
    return result & 0x7FFFFFFFFFFFFFFF;
  }

  static int _fnv1a64(List<int> bytes, int seed) {
    var hash = seed;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash;
  }
}
