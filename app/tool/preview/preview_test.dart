// Visual preview harness: renders real app screens with seeded demo mail to PNGs.
// Run:  PREVIEW_OUT=/some/dir flutter test tool/preview/preview_test.dart
// Not part of the product test suite (lives in tool/, not test/).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:df_theme/df_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:spamfiltering_emailclient/db/database.dart';
import 'package:spamfiltering_emailclient/platform/platform_services.dart';
import 'package:spamfiltering_emailclient/theme/app_brand.dart';
import 'package:spamfiltering_emailclient/ui/account_setup/account_setup_view.dart';
import 'package:spamfiltering_emailclient/ui/compose/compose_view.dart';
import 'package:spamfiltering_emailclient/funnel/launch_gate.dart';
import 'package:spamfiltering_emailclient/ui/premium/upsell_sheet.dart';
import 'package:spamfiltering_emailclient/ui/settings/settings_view.dart';
import 'package:spamfiltering_emailclient/ui/shell/nav_shell.dart';

final String outDir = Platform.environment['PREVIEW_OUT'] ?? '/tmp/preview';

Future<void> _loadFonts() async {
  for (final f in {
    'Fraunces': 'assets/fonts/Fraunces.ttf',
    'Public Sans': 'assets/fonts/PublicSans.ttf',
    'JetBrains Mono': 'assets/fonts/JetBrainsMono.ttf',
  }.entries) {
    final loader = FontLoader(f.key)..addFont(rootBundle.load(f.value));
    await loader.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final l = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await l.load();
    }
  }
}


Future<AppDatabase> seedDb() async {
  final app = await AppDatabase.open(inMemory: true);
  final db = app.db;
  db.execute("INSERT INTO accounts VALUES ('a1','justin@example.com','Justin','imap.example.com',993,'smtp.example.com',587,'password','2026-11-01T00:00:00Z')");
  final folders = [
    ['f-inbox', 'Inbox', 'inbox', 3],
    ['f-news', 'Newsletters', null, 1],
    ['f-sent', 'Sent', 'sent', 0],
    ['f-drafts', 'Drafts', 'drafts', 2],
    ['f-junk', 'Junk', 'junk', 2],
    ['f-arch', 'Archive', 'archive', 0],
    ['f-trash', 'Trash', 'trash', 0],
  ];
  for (final f in folders) {
    db.execute('INSERT INTO folders (id,account_id,name,server_path,special_use,unread_count) VALUES (?,?,?,?,?,?)',
        [f[0], 'a1', f[1], f[1], f[2], f[3]]);
  }
  final msgs = <Map<String, Object?>>[
    {'id': 'm1', 'f': 'f-inbox', 's': 'Mara Lindqvist <mara@lindqvist.studio>', 'd': 'lindqvist.studio', 'sub': 'Re: Brand typography proposal — final round', 'sn': 'I have attached the revised specimen sheets. The serif pairs beautifully with the mono you suggested, but I would like your call on the…', 't': '2026-11-23T14:12:00Z', 'r': 0, 'att': 1, 'l': 'inbox', 'sc': 0.02, 'body': 'Hi Justin,\n\nI have attached the revised specimen sheets. The serif pairs beautifully with the mono you suggested, but I would like your call on the heading weight before we lock the system.\n\nThree things I changed since Tuesday:\n\n1. Display weight dropped from 700 to 600, which reads calmer at 40px.\n2. Numerals are now tabular everywhere a figure sits in a column.\n3. The accent is used once per screen, never twice.\n\nCan we talk Thursday morning?\n\nWarmly,\nMara'},
    {'id': 'm2', 'f': 'f-inbox', 's': 'Dev Patel <dev@northfield.dev>', 'd': 'northfield.dev', 'sub': 'PR #482: tokenizer fixes need your review', 'sn': 'Normalizer now strips the greeting line before tokenising, so personalised spam hashes identically. Tests are green; one open question about…', 't': '2026-11-23T11:48:00Z', 'r': 0, 'att': 0, 'l': 'inbox', 'sc': 0.04, 'body': 'Normalizer now strips the greeting line before tokenising, so personalised spam hashes identically across recipients.\n\nTests are green. One open question about freemail domains: do we skip the sender-domain hash for them, or only for the body fingerprint?\n\n— Dev'},
    {'id': 'm3', 'f': 'f-inbox', 's': 'Anouk de Vries <anouk@devries.example>', 'd': 'devries.example', 'sub': 'Dinner Saturday? Bringing the good wine', 'sn': 'Eight o’clock at ours. Thijs is making the lamb and promises not to talk about his bicycle again.', 't': '2026-11-22T19:30:00Z', 'r': 1, 'att': 0, 'l': 'inbox', 'sc': 0.01, 'body': 'Eight o’clock at ours. Thijs is making the lamb and promises not to talk about his bicycle again.\n\nA'},
    {'id': 'm4', 'f': 'f-news', 's': 'The Weekly Ledger <hello@ledgerweekly.example>', 'd': 'ledgerweekly.example', 'sub': 'Seven essays on slow software', 'sn': 'This week: why your inbox should be a place, not a feed; a defence of the plain-text email; and what typographers know about interfaces…', 't': '2026-11-22T07:00:00Z', 'r': 0, 'att': 0, 'l': 'newsletter', 'sc': 0.05, 'body': 'This week: why your inbox should be a place, not a feed; a defence of the plain-text email; and what typographers know about interfaces that software engineers keep forgetting.\n\nRead online · Unsubscribe'},
    {'id': 'm5', 'f': 'f-inbox', 's': 'Atlas Air <no-reply@atlas-air.example>', 'd': 'atlas-air.example', 'sub': 'Your boarding pass: LIS to HEL, Mon 24 Nov', 'sn': 'Check-in is open. Gate opens 55 minutes before departure. Your seat is 14A.', 't': '2026-11-21T09:05:00Z', 'r': 1, 'att': 1, 'l': 'inbox', 'sc': 0.06, 'body': 'Check-in is open. Gate opens 55 minutes before departure. Your seat is 14A.'},
    {'id': 'm6', 'f': 'f-junk', 's': 'Prize Desk <winner@claim-now-today.example>', 'd': 'claim-now-today.example', 'sub': 'CONGRATULATIONS!!! You have been selected', 'sn': 'Dear lucky winner, you have been randomly selected to receive a luxury cash reward. Click below within 24 hours or the offer expires…', 't': '2026-11-21T03:41:00Z', 'r': 0, 'att': 0, 'l': 'spam', 'sc': 0.97, 'body': 'Dear lucky winner,\n\nYou have been randomly selected to receive a LUXURY CASH REWARD of \$5,000,000. Click the link below within 24 hours or the offer expires.\n\nhttp://claim-now-today.example/redeem?id=88231'},
    {'id': 'm7', 'f': 'f-junk', 's': 'Account Security <support@secure-paypa1-verify.example>', 'd': 'secure-paypa1-verify.example', 'sub': 'Action required: confirm your account within 24h', 'sn': 'We detected unusual activity. To avoid suspension verify your identity now using the secure link below…', 't': '2026-11-20T22:10:00Z', 'r': 0, 'att': 0, 'l': 'spam', 'sc': 0.93, 'body': 'We detected unusual activity on your account. To avoid suspension, verify your identity now.'},
    {'id': 'm8', 'f': 'f-inbox', 's': 'Tomás Rivera <tomas@rivera-consulting.example>', 'd': 'rivera-consulting.example', 'sub': 'Invoice 2026-114 — second reminder', 'sn': 'Following up on the invoice sent two weeks ago. Payment details are in the attached PDF. Please confirm receipt.', 't': '2026-11-19T10:00:00Z', 'r': 1, 'att': 1, 'l': 'inbox', 'sc': 0.71, 'body': 'Following up on the invoice sent two weeks ago. Payment details are in the attached PDF. Please confirm receipt.'},
  ];
  for (final m in msgs) {
    db.execute(
        'INSERT INTO messages (id,account_id,folder_id,uid,subject,sender,sender_domain,recipient_addrs,date,snippet,is_read,is_flagged,has_attachments,classification_label,spam_score) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [m['id'], 'a1', m['f'], 1, m['sub'], m['s'], m['d'], 'justin@example.com', m['t'], m['sn'], m['r'], m['id'] == 'm2' ? 1 : 0, m['att'], m['l'], m['sc']]);
    db.execute('INSERT INTO bodies (message_id,text_body,remote_images_blocked) VALUES (?,?,1)', [m['id'], m['body']]);
  }
  final ev6 = jsonEncode([
    {'id': 'bayes', 'weight': 0.62, 'detail': '38 spammy tokens (“selected”, “reward”, “luxury”)'},
    {'id': 'auth', 'weight': 0.21, 'detail': 'DMARC fail · SPF softfail'},
    {'id': 'community', 'weight': 0.31, 'detail': '5 independent reports on the community list'},
    {'id': 'heuristic', 'weight': 0.12, 'detail': 'Link text domain ≠ link target domain'},
  ]);
  final ev7 = jsonEncode([
    {'id': 'bayes', 'weight': 0.48, 'detail': '“verify”, “suspension”, “unusual activity”'},
    {'id': 'heuristic', 'weight': 0.34, 'detail': 'Lookalike domain: paypa1 ≈ paypal'},
    {'id': 'auth', 'weight': 0.2, 'detail': 'DKIM fail'},
  ]);
  final ev8 = jsonEncode([
    {'id': 'bayes', 'weight': 0.33, 'detail': '“invoice”, “payment”, “reminder”'},
    {'id': 'heuristic', 'weight': 0.12, 'detail': 'Sender never contacted before'},
    {'id': 'ham', 'weight': -0.18, 'detail': 'Domain appears in your Sent folder'},
  ]);
  for (final e in [['m6', 'spam', 0.97, ev6], ['m7', 'spam', 0.93, ev7], ['m8', 'inbox', 0.71, ev8]]) {
    db.execute('INSERT INTO classifications VALUES (?,?,?,?,?,0)', [e[0], e[1], e[2], e[3], '2026-11-23T08:00:00Z']);
  }
  db.execute('WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2140) INSERT INTO tokens (hash,spam,ham) SELECT i, i % 3, i % 5 FROM n');
  db.execute("WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 1204) INSERT INTO blocklist_entries (id,type,hash_value,added_at) SELECT 'b'||i, 'body', i, '2026-11-20T00:00:00Z' FROM n");
  return app;
}

Future<void> shot(WidgetTester tester, String name, Widget home,
    {Size size = const Size(1440, 900), double dpr = 1.5, ThemeMode mode = ThemeMode.light, AppDatabase? db, void Function(ProviderContainer c)? setup, Future<void> Function(WidgetTester t)? act}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final database = db ?? await seedDb();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DfTheme.light(AppBrand.brand),
        darkTheme: DfTheme.dark(AppBrand.brand),
        themeMode: mode,
        home: home,
      ),
    ),
  ));
  if (setup != null) {
    setup(ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)));
  }
  await tester.pump(const Duration(milliseconds: 900));
  if (act != null) await act(tester);
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 900));
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: dpr);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bd!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('desktop light, inbox message selected', (t) async {
    await shot(t, 'desktop_light', const AppNavShell(), setup: (c) {
      c.read(selectedMessageIdProvider.notifier).set('m1');
    });
  });
  testWidgets('desktop dark, spam selected', (t) async {
    await shot(t, 'desktop_dark_spam', const AppNavShell(), mode: ThemeMode.dark, setup: (c) {
      c.read(selectedMessageIdProvider.notifier).set('m6');
    });
  });
  testWidgets('mobile list', (t) async {
    await shot(t, 'mobile_list', const AppNavShell(), size: const Size(390, 844), dpr: 2);
  });
  testWidgets('mobile reader', (t) async {
    await shot(t, 'mobile_reader', const AppNavShell(), size: const Size(390, 844), dpr: 2, setup: (c) {
      c.read(selectedMessageIdProvider.notifier).set('m8');
    });
  });
  testWidgets('onboarding mobile', (t) async {
    await shot(t, 'onboarding_mobile', Builder(builder: (ctx) => AppLaunchGate.buildOnboarding(ctx, () {})), size: const Size(390, 844), dpr: 2);
  });
  testWidgets('onboarding desktop', (t) async {
    await shot(t, 'onboarding_desktop', Builder(builder: (ctx) => AppLaunchGate.buildOnboarding(ctx, () {})));
  });
  testWidgets('onboarding desktop p2', (t) async {
    await shot(t, 'onboarding_desktop_p2', Builder(builder: (ctx) => AppLaunchGate.buildOnboarding(ctx, () {})), act: (t) async {
      await t.tap(find.text('Next'));
      await t.pump(const Duration(milliseconds: 600));
    });
  });
  testWidgets('onboarding mobile p3 dark', (t) async {
    await shot(t, 'onboarding_mobile_p3_dark', Builder(builder: (ctx) => AppLaunchGate.buildOnboarding(ctx, () {})), size: const Size(390, 844), dpr: 2, mode: ThemeMode.dark, act: (t) async {
      for (var i = 0; i < 2; i++) {
        await t.fling(find.byType(PageView), const Offset(-500, 0), 2000);
        await t.pump(const Duration(milliseconds: 1500));
      }
    });
  });
  testWidgets('upsell sheet', (t) async {
    await shot(t, 'upsell', Scaffold(body: Center(child: SizedBox(width: 480, child: AppUpsellSheet(onDismiss: () {}, onSubscribed: () {})))), size: const Size(700, 800));
  });
  testWidgets('settings tiles', (t) async {
    await shot(t, 'settings_tiles',
        const SettingsView(),
        size: const Size(720, 900));
  });
  testWidgets('compose desktop', (t) async {
    await shot(t, 'compose_desktop', const ComposeView(), size: const Size(1100, 800));
  });
  testWidgets('account setup desktop', (t) async {
    await shot(t, 'account_setup_desktop', const AccountSetupView(), size: const Size(1280, 800));
  });
  testWidgets('account setup mobile', (t) async {
    await shot(t, 'account_setup_mobile', const AccountSetupView(), size: const Size(390, 844), dpr: 2);
  });
}
