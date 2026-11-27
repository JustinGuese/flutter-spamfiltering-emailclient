import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spam_core/spam_core.dart';
import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/filter/token_store_drift.dart';
import 'package:spamfiltering_emailclient/premium/crdt_counters.dart';
import 'package:spamfiltering_emailclient/premium/filter_sync.dart';
import 'package:spamfiltering_emailclient/premium/sync_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppDatabase, TokenStoreDrift, FilterSyncService)> setup() async {
    final db = await AppDatabase.open(inMemory: true);
    final store = TokenStoreDrift(db);
    final sync = FilterSyncService(
      dio: Dio(),
      keyManager: SyncKeyManager(),
      tokenStore: store,
      deviceSlot: deviceSyncSlot(db),
    );
    return (db, store, sync);
  }

  CrdtTokenState remote(int spam) => CrdtTokenState(
        deviceId: 'dev_other',
        spamTokens: {42: PNCounter(positive: spam, negative: 0)},
      );

  test('re-pulling the same remote blob does not add its counts again', () async {
    final (_, store, sync) = await setup();
    sync.applyRemoteState('dev_other', remote(5));
    sync.applyRemoteState('dev_other', remote(5));
    expect(store.counts(42).spam, 5);

    // The remote device learned 2 more: only the difference is added.
    sync.applyRemoteState('dev_other', remote(7));
    expect(store.counts(42).spam, 7);
  });

  test('own state excludes counts applied from other devices', () async {
    final (_, store, sync) = await setup();
    store.apply(42, Label.spam, 3); // learned here
    sync.applyRemoteState('dev_other', remote(5));
    expect(store.counts(42).spam, 8);
    expect(sync.ownState().spamTokens[42]!.value, 3);
  });

  test('each install gets its own stable sync slot', () async {
    final a = await AppDatabase.open(inMemory: true);
    final b = await AppDatabase.open(inMemory: true);
    expect(deviceSyncSlot(a), deviceSyncSlot(a));
    expect(deviceSyncSlot(a), isNot(deviceSyncSlot(b)));
    expect(deviceSyncSlot(a), isNot('slot_0'));
  });
}
