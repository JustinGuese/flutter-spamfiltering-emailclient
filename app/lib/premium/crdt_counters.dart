import 'dart:math' as math;

/// Single token counter tracked via CRDT Positive-Negative (PN) counter.
class PNCounter {
  final int positive;
  final int negative;

  const PNCounter({this.positive = 0, this.negative = 0});

  int get value => positive - negative;

  PNCounter increment(int delta) =>
      PNCounter(positive: positive + delta, negative: negative);

  PNCounter decrement(int delta) =>
      PNCounter(positive: positive, negative: negative + delta);

  /// Standard state-based CRDT PN-Counter merge (maximum of each component).
  PNCounter merge(PNCounter other) {
    return PNCounter(
      positive: math.max(positive, other.positive),
      negative: math.max(negative, other.negative),
    );
  }

  Map<String, int> toJson() => {'p': positive, 'n': negative};

  factory PNCounter.fromJson(Map<String, dynamic> json) => PNCounter(
    positive: (json['p'] as num?)?.toInt() ?? 0,
    negative: (json['n'] as num?)?.toInt() ?? 0,
  );
}

/// Device-specific map of token training counters for CRDT replication.
class CrdtTokenState {
  final String deviceId;
  final Map<int, PNCounter> spamTokens;
  final Map<int, PNCounter> hamTokens;

  CrdtTokenState({
    required this.deviceId,
    Map<int, PNCounter>? spamTokens,
    Map<int, PNCounter>? hamTokens,
  })  : spamTokens = spamTokens ?? {},
        hamTokens = hamTokens ?? {};

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'spam': spamTokens.map((k, v) => MapEntry(k.toString(), v.toJson())),
    'ham': hamTokens.map((k, v) => MapEntry(k.toString(), v.toJson())),
  };

  factory CrdtTokenState.fromJson(Map<String, dynamic> json) {
    final spamRaw = json['spam'] as Map<String, dynamic>? ?? {};
    final hamRaw = json['ham'] as Map<String, dynamic>? ?? {};

    return CrdtTokenState(
      deviceId: json['device_id'] as String? ?? 'dev',
      spamTokens: spamRaw.map(
        (k, v) => MapEntry(int.parse(k), PNCounter.fromJson(v as Map<String, dynamic>)),
      ),
      hamTokens: hamRaw.map(
        (k, v) => MapEntry(int.parse(k), PNCounter.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}
