import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spam_core/spam_core.dart';
import '../community/matcher.dart';
import '../db/database.dart';
import 'sender_rules.dart';
import 'token_store_drift.dart';

/// Service classifying incoming mail and retrieving stored verdicts.
class FilterService {
  final AppDatabase db;
  final TokenStoreDrift tokenStore;
  final SenderRules senderRules;

  FilterService({
    required this.db,
    required this.tokenStore,
    SenderRules? senderRules,
  }) : senderRules = senderRules ?? SenderRules(db);

  Future<Verdict> classifyMessage({
    required String messageId,
    required Message message,
    bool isCommunityMatch = false,
  }) async {
    final normalized = Normalizer.normalize(message);
    final fingerprints = Fingerprinter.fingerprints(normalized);
    final matcher = CommunityMatcher(db);
    final matchedCommunity = isCommunityMatch || matcher.matches(fingerprints);

    final fromHeader = message.firstHeader('from') ?? '';
    final senderAddr = SenderRules.extractEmail(fromHeader);

    final signals = Signals(
      communityBlocklistMatch: matchedCommunity,
      knownContact: senderRules.isContact(senderAddr),
      senderRule: senderRules.lookup(senderAddr),
    );

    final rawVerdict = await Classifier.score(
      normalized,
      tokenStore,
      signals,
    );

    // Map evidence id community_blocklist to community
    final mappedEvidence = rawVerdict.evidence.map((e) {
      if (e.id == 'community_blocklist') {
        return Evidence(id: 'community', weight: e.weight, detail: e.detail);
      }
      return e;
    }).toList();

    final verdict = Verdict(
      label: rawVerdict.label,
      spamScore: rawVerdict.spamScore,
      evidence: mappedEvidence,
    );

    // Persist classification in database
    db.db.execute('''
      UPDATE messages
      SET classification_label = ?, spam_score = ?
      WHERE id = ?
    ''', [verdict.label.name, verdict.spamScore, messageId]);

    final evidenceList = verdict.evidence
        .map((e) => e.toJson())
        .toList();

    db.db.execute('''
      INSERT OR REPLACE INTO classifications
      (message_id, label, spam_score, evidence_json, classified_at, user_overridden)
      VALUES (?, ?, ?, ?, ?, 0)
    ''', [
      messageId,
      verdict.label.name,
      verdict.spamScore,
      jsonEncode(evidenceList),
      DateTime.now().toIso8601String(),
    ]);

    return verdict;
  }

  Verdict? getStoredVerdict(String messageId) {
    final row = db.db.select('''
      SELECT label, spam_score, evidence_json
      FROM classifications
      WHERE message_id = ?
    ''', [messageId]).firstOrNull;

    if (row == null) return null;

    final label = Label.values.byName(row['label'] as String);
    final spamScore = (row['spam_score'] as num).toDouble();
    final evidenceRaw = jsonDecode(row['evidence_json'] as String) as List<dynamic>;

    final evidence = evidenceRaw.map((e) {
      final map = e as Map<String, dynamic>;
      return Evidence(
        id: map['id'] as String,
        weight: (map['weight'] as num).toDouble(),
        detail: map['detail'] as String,
      );
    }).toList();

    return Verdict(
      label: label,
      spamScore: spamScore,
      evidence: evidence,
    );
  }
}

final filterServiceProvider = Provider<FilterService>((ref) {
  final db = ref.watch(databaseProvider);
  final store = ref.watch(tokenStoreProvider);
  final rules = ref.watch(senderRulesProvider);
  return FilterService(db: db, tokenStore: store, senderRules: rules);
});
