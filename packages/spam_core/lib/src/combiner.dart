import 'dart:async';
import 'dart:math' as math;
import 'contracts.dart';
import 'auth_results.dart';
import 'bayes.dart';
import 'heuristics.dart';
import 'tokenizer.dart';

/// Top-level classifier implementing Stage-A (Spam Bayes) and Stage-B (Newsletter).
class Classifier {
  static const double spamHighThreshold = 0.90;
  static const double spamUnsureThreshold = 0.60;

  /// Logit boost the community blocklist adds to a message's spam score.
  static const double communityLogitBoost = 3.5;

  /// The score this message would have had without the community blocklist
  /// signal. Lets the app show what the blocklist added, from stored scores only.
  static double scoreWithoutCommunity(double spamScore) {
    final p = spamScore.clamp(1e-12, 1.0 - 1e-12);
    final logit = math.log(p / (1.0 - p)) - communityLogitBoost;
    return 1.0 / (1.0 + math.exp(-logit));
  }

  /// Scores a normalized message and returns a comprehensive Verdict.
  static Future<Verdict> score(
    Normalized normalized,
    TokenStore store, [
    Signals? signals,
    String? authservId,
  ]) async {
    final evidence = <Evidence>[];

    // 1. Extract tokens
    final tokens = Tokenizer.tokens(normalized);
    final tokenHashes = tokens.map(Tokenizer.hashToken).toList();

    // 2. Stage-A Robinson-Fisher Bayes
    final totals = await store.messageTotals();
    final bayesResult = await BayesClassifier.scoreTokens(
      tokenHashes,
      store,
      totalSpamMessages: totals.spam,
      totalHamMessages: totals.ham,
    );
    evidence.add(Evidence(
      id: 'bayes',
      weight: bayesResult.score,
      detail: 'Robinson-Fisher chi-squared Bayes score: ${bayesResult.score.toStringAsFixed(3)} '
          '(${bayesResult.tokenCount} tokens evaluated, unsure=${bayesResult.isUnsure})',
    ));

    // 3. AuthResults (SPF, DKIM, DMARC)
    final auth = AuthResults.parse(normalized.original.headers, authservId);
    _evaluateAuthResults(auth, evidence);

    // 4. Heuristics (display-name spoofing, link mismatch, disposable domain)
    final heuristicEvidence = Heuristics.evaluate(normalized);
    evidence.addAll(heuristicEvidence);

    // 5. Community blocklist signal
    if (signals?.communityBlocklistMatch == true) {
      evidence.add(const Evidence(
        id: 'community_blocklist',
        weight: 0.60,
        detail: 'Matched active community spam fingerprint blocklist',
      ));
    }

    // 6. Advanced transformer model signal (Premium)
    if (signals?.advancedModelScore != null) {
      final score = signals!.advancedModelScore!;
      evidence.add(Evidence(
        id: 'advanced_model',
        weight: score,
        detail: 'On-device neural transformer score: ${score.toStringAsFixed(3)}',
      ));
    }

    // 7. Known contact signal
    if (signals?.knownContact == true) {
      evidence.add(const Evidence(
        id: 'known_contact',
        weight: -0.25,
        detail: 'Sender is in your trusted contacts',
      ));
    }

    // 8. Combine Stage-A signals into overall spamScore
    var spamScore = _combineSpamSignals(bayesResult.score, evidence);

    // Capping for known contacts (never auto-move to Junk unless phishing is present)
    final hasPhishing = evidence.any((e) => phishingEvidenceIds.contains(e.id));
    if (signals?.knownContact == true && !hasPhishing) {
      spamScore = math.min(spamScore, 0.89);
    }

    // Sender rules take final effect
    if (signals?.senderRule == SenderRuleAction.block) {
      spamScore = 1.0;
      evidence.add(const Evidence(
        id: 'sender_blocked',
        weight: 1.0,
        detail: 'Sender or domain blocked by your rule',
      ));
    } else if (signals?.senderRule == SenderRuleAction.allow) {
      spamScore = math.min(spamScore, 0.05);
      evidence.add(const Evidence(
        id: 'sender_allowed',
        weight: -1.0,
        detail: 'Sender or domain allowed by your rule',
      ));
    }

    // 9. Determine label: Stage-A vs Stage-B
    Label label;
    if (spamScore >= spamUnsureThreshold) {
      label = Label.spam;
      if (spamScore < spamHighThreshold) {
        evidence.add(Evidence(
          id: 'spam_unsure_band',
          weight: spamScore,
          detail: 'Score falls in unsure band [0.60, 0.90); marked for possible spam review',
        ));
      }
    } else {
      // Stage-B: Newsletter vs Inbox
      final newsletterVerdict = await _evaluateStageB(normalized, tokenHashes, store, evidence);
      label = newsletterVerdict ? Label.newsletter : Label.inbox;
    }

    return Verdict(
      label: label,
      spamScore: spamScore,
      evidence: evidence,
    );
  }

  static void _evaluateAuthResults(AuthResults auth, List<Evidence> evidence) {
    if (auth.dmarc == AuthVerdict.fail) {
      evidence.add(const Evidence(
        id: 'auth_dmarc_fail',
        weight: 0.35,
        detail: 'DMARC authentication failed',
      ));
    } else if (auth.dmarc == AuthVerdict.pass) {
      evidence.add(const Evidence(
        id: 'auth_dmarc_pass',
        weight: -0.15,
        detail: 'DMARC authentication passed',
      ));
    }

    if (auth.spf == AuthVerdict.fail || auth.spf == AuthVerdict.softfail) {
      evidence.add(Evidence(
        id: 'auth_spf_fail',
        weight: auth.spf == AuthVerdict.fail ? 0.20 : 0.10,
        detail: 'SPF verification ${auth.spf.name}',
      ));
    }

    if (auth.dkim == AuthVerdict.fail) {
      evidence.add(const Evidence(
        id: 'auth_dkim_fail',
        weight: 0.20,
        detail: 'DKIM signature verification failed',
      ));
    }
  }

  static double _combineSpamSignals(double bayesScore, List<Evidence> evidence) {
    // Base logit from Bayes
    final clampedBayes = bayesScore.clamp(0.01, 0.99);
    var logit = math.log(clampedBayes / (1.0 - clampedBayes));

    for (final ev in evidence) {
      switch (ev.id) {
        case 'auth_dmarc_fail':
          logit += 1.8;
          break;
        case 'auth_dmarc_pass':
          logit -= 1.0;
          break;
        case 'auth_spf_fail':
          logit += 1.0;
          break;
        case 'auth_dkim_fail':
          logit += 1.0;
          break;
        case 'community_blocklist':
          logit += communityLogitBoost;
          break;
        case 'known_contact':
          logit -= 2.5;
          break;
        case 'advanced_model':
          logit += (ev.weight - 0.5) * 2.5;
          break;
        case 'disposable_domain':
          logit += 1.5;
          break;
        case 'punycode_domain':
          logit += 2.0;
          break;
        case 'lookalike_domain':
          logit += 3.0;
          break;
        case 'reply_to_mismatch':
          logit += 1.5;
          break;
        case 'url_shortener':
          logit += 0.7;
          break;
        case 'dangerous_attachment':
          logit += 3.0;
          break;
        case 'image_only':
          logit += 1.0;
          break;
        case 'hidden_text':
          logit += 1.5;
          break;
        case 'display_name_spoof_email':
        case 'display_name_brand_spoof':
          logit += 2.0;
          break;
        case 'link_mismatch':
          logit += 2.5;
          break;
      }
    }

    final combined = 1.0 / (1.0 + math.exp(-logit));
    return combined.clamp(0.0, 1.0);
  }

  static Future<bool> _evaluateStageB(
    Normalized normalized,
    List<int> tokenHashes,
    TokenStore store,
    List<Evidence> evidence,
  ) async {
    var newsletterScore = 0.0;
    final message = normalized.original;

    // Header priors
    final listUnsub = message.firstHeader('list-unsubscribe');
    if (listUnsub != null) {
      newsletterScore += 0.45;
      evidence.add(Evidence(
        id: 'stage_b_list_unsubscribe',
        weight: 0.45,
        detail: 'List-Unsubscribe header present: $listUnsub',
      ));
    }

    final listId = message.firstHeader('list-id');
    if (listId != null) {
      newsletterScore += 0.35;
      evidence.add(Evidence(
        id: 'stage_b_list_id',
        weight: 0.35,
        detail: 'List-Id header present: $listId',
      ));
    }

    final precedence = message.firstHeader('precedence')?.toLowerCase();
    if (precedence == 'bulk' || precedence == 'list') {
      newsletterScore += 0.30;
      evidence.add(Evidence(
        id: 'stage_b_precedence',
        weight: 0.30,
        detail: 'Precedence: $precedence header indicates mailing list',
      ));
    }

    // Token store newsletter vs inbox counts
    var newsTokens = 0;
    var inboxTokens = 0;
    for (final h in tokenHashes) {
      final counts = await store.counts(h);
      if (counts.newsletter > counts.inbox) newsTokens++;
      if (counts.inbox > counts.newsletter) inboxTokens++;
    }

    if (newsTokens + inboxTokens > 0) {
      final tokenBias = (newsTokens - inboxTokens) / (newsTokens + inboxTokens);
      newsletterScore += tokenBias * 0.25;
      evidence.add(Evidence(
        id: 'stage_b_tokens',
        weight: tokenBias,
        detail: 'Newsletter token ratio: $newsTokens news vs $inboxTokens inbox',
      ));
    }

    final isNewsletter = newsletterScore >= 0.45;
    evidence.add(Evidence(
      id: isNewsletter ? 'stage_b_newsletter' : 'stage_b_inbox',
      weight: newsletterScore,
      detail: isNewsletter ? 'Classified as newsletter' : 'Classified as inbox personal/transactional',
    ));

    return isNewsletter;
  }
}
