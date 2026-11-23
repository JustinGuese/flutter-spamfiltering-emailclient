import 'package:spam_core/spam_core.dart';
import '../db/database.dart';

/// Local matching of message fingerprints against the synced blocklist entries.
class CommunityMatcher {
  final AppDatabase db;

  CommunityMatcher(this.db);

  /// Checks whether any fingerprint (URL hash, body band, or sender domain hash) matches.
  bool matches(Fingerprints fingerprints) {
    return matchingHashes(fingerprints).isNotEmpty;
  }

  /// Returns the list of matching 64-bit hash values from local blocklist.
  List<int> matchingHashes(Fingerprints fingerprints) {
    final result = <int>[];

    // 1. Check URL hashes
    for (final urlHash in fingerprints.urlHashes) {
      final rows = db.db.select(
        'SELECT hash_value FROM blocklist_entries WHERE type = ? AND hash_value = ? LIMIT 1',
        ['url_hash', urlHash],
      );
      if (rows.isNotEmpty) {
        result.add(urlHash);
      }
    }

    // 2. Check body bands (at least 2 matching bands out of 8 constitute a match)
    final matchedBands = <int>[];
    for (final band in fingerprints.bodyBands) {
      final rows = db.db.select(
        'SELECT hash_value FROM blocklist_entries WHERE type = ? AND hash_value = ? LIMIT 1',
        ['body_band', band],
      );
      if (rows.isNotEmpty) {
        matchedBands.add(band);
      }
    }
    if (matchedBands.length >= 2) {
      result.addAll(matchedBands);
    }

    // 3. Check sender domain hash if present
    if (fingerprints.senderDomainHash != null) {
      final rows = db.db.select(
        'SELECT hash_value FROM blocklist_entries WHERE type = ? AND hash_value = ? LIMIT 1',
        ['sender_domain', fingerprints.senderDomainHash],
      );
      if (rows.isNotEmpty) {
        result.add(fingerprints.senderDomainHash!);
      }
    }

    return result;
  }
}
