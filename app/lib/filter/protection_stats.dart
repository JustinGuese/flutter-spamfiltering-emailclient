import 'dart:convert';
import 'package:spam_core/spam_core.dart';
import '../db/database.dart';

/// Who caught a spam message, replayed from what is stored for it.
enum CaughtBy {
  /// The on-device filter (or you, by marking it) would have caught it anyway.
  filter,

  /// Only the community blocklist pushed it over the spam threshold.
  community,
}

class CaughtMessage {
  final String id;
  final String subject;
  final String sender;
  final DateTime? date;
  final double score;
  final CaughtBy by;

  /// True when the blocklist matched, even if the local filter would also have caught it.
  final bool communityMatched;

  /// You marked it yourself.
  final bool byYou;

  const CaughtMessage({
    required this.id,
    required this.subject,
    required this.sender,
    required this.date,
    required this.score,
    required this.by,
    required this.communityMatched,
    required this.byYou,
  });
}

/// What the "Your protection" screen shows. Every figure is counted from the local
/// database; nothing is estimated.
class ProtectionStats {
  /// Spam messages known to this device: what an unfiltered inbox would have shown.
  final int total;

  /// Of those, caught by the on-device filter (including ones you marked yourself).
  final int filterCaught;

  /// Of those, caught only because the community blocklist tipped the score.
  final int communityOnly;

  /// Messages you marked by hand; these taught the filter.
  final int corrections;

  /// Distinct words (stored as hashes) the filter has counts for.
  final int learnedTokens;
  final int spamLeaning;
  final int hamLeaning;

  /// Fingerprints currently on the local community blocklist.
  final int blocklistEntries;

  /// Newest first, capped.
  final List<CaughtMessage> recent;

  const ProtectionStats({
    required this.total,
    required this.filterCaught,
    required this.communityOnly,
    required this.corrections,
    required this.learnedTokens,
    required this.spamLeaning,
    required this.hamLeaning,
    required this.blocklistEntries,
    required this.recent,
  });

  /// Spam that would reach the inbox at each stage of the story.
  int get reachInboxNoFilter => total;
  int get reachInboxFilter => total - filterCaught;
  int get reachInboxCommunity => total - filterCaught - communityOnly;

  bool get isEmpty => total == 0 && learnedTokens == 0;
}

ProtectionStats computeProtection(AppDatabase db, {int recentLimit = 200}) {
  final rows = db.db.select('''
    SELECT c.message_id, c.spam_score, c.evidence_json, c.user_overridden,
           m.subject, m.sender, m.date
    FROM classifications c LEFT JOIN messages m ON m.id = c.message_id
    WHERE c.label = 'spam'
    ORDER BY m.date DESC
  ''');

  var filterCaught = 0;
  var communityOnly = 0;
  var corrections = 0;
  final recent = <CaughtMessage>[];

  for (final r in rows) {
    final byYou = (r['user_overridden'] as int) == 1;
    final score = (r['spam_score'] as num).toDouble();
    final matched = !byYou && _hasCommunityEvidence(r['evidence_json'] as String);
    // Your own verdicts and anything the filter would score as spam alone count as
    // the filter's work; the rest was tipped over the line by the blocklist.
    final by = matched && Classifier.scoreWithoutCommunity(score) < Classifier.spamUnsureThreshold
        ? CaughtBy.community
        : CaughtBy.filter;
    if (byYou) corrections++;
    if (by == CaughtBy.filter) {
      filterCaught++;
    } else {
      communityOnly++;
    }
    if (recent.length < recentLimit) {
      recent.add(CaughtMessage(
        id: r['message_id'] as String,
        subject: (r['subject'] as String?) ?? '',
        sender: (r['sender'] as String?) ?? '',
        date: DateTime.tryParse((r['date'] as String?) ?? ''),
        score: score,
        by: by,
        communityMatched: matched,
        byYou: byYou,
      ));
    }
  }

  int count(String sql) => (db.db.select(sql).first.values.first as int?) ?? 0;
  return ProtectionStats(
    total: rows.length,
    filterCaught: filterCaught,
    communityOnly: communityOnly,
    corrections: corrections,
    // The bundled seed prior is not something this device learned.
    learnedTokens: count('SELECT COUNT(*) FROM tokens WHERE hash NOT IN (SELECT hash FROM prior_tokens)'),
    spamLeaning: count('SELECT COUNT(*) FROM tokens WHERE spam > ham AND spam > newsletter AND spam > inbox'),
    hamLeaning: count('SELECT COUNT(*) FROM tokens WHERE ham + inbox > spam'),
    blocklistEntries: count('SELECT COUNT(*) FROM blocklist_entries'),
    recent: recent,
  );
}

bool _hasCommunityEvidence(String evidenceJson) {
  try {
    final list = jsonDecode(evidenceJson) as List<dynamic>;
    return list.any((e) => e is Map && e['id'] == 'community');
  } catch (_) {
    return false;
  }
}
