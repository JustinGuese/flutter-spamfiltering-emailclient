import 'dart:io';
import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';

Message parseEml(String raw) {
  final headers = <String, List<String>>{};
  final lines = raw.split(RegExp(r'\r?\n'));

  var headerEndIndex = -1;
  String? currentHeaderName;
  final currentHeaderValue = StringBuffer();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (line.trim().isEmpty) {
      headerEndIndex = i;
      if (currentHeaderName != null) {
        headers.putIfAbsent(currentHeaderName.toLowerCase(), () => []).add(currentHeaderValue.toString().trim());
      }
      break;
    }

    if ((line.startsWith(' ') || line.startsWith('\t')) && currentHeaderName != null) {
      currentHeaderValue.write(' ${line.trim()}');
      continue;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex != -1) {
      if (currentHeaderName != null) {
        headers.putIfAbsent(currentHeaderName.toLowerCase(), () => []).add(currentHeaderValue.toString().trim());
        currentHeaderValue.clear();
      }
      currentHeaderName = line.substring(0, colonIndex).trim();
      currentHeaderValue.write(line.substring(colonIndex + 1).trim());
    }
  }

  final body = (headerEndIndex != -1 && headerEndIndex < lines.length - 1)
      ? lines.sublist(headerEndIndex + 1).join('\n')
      : '';

  final toHeaders = headers['to'] ?? const [];
  final recipientAddrs = <String>[];
  for (final to in toHeaders) {
    recipientAddrs.addAll(to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
  }

  final contentType = (headers['content-type'] ?? []).join(' ').toLowerCase();
  final isHtml = contentType.contains('text/html') ||
      body.contains(RegExp(r'<html|<body|<a\s+href', caseSensitive: false));
  final htmlBody = isHtml ? body : null;

  final attachmentNames = <String>[];
  for (final match in RegExp(r'''filename=["']?([^"'\r\n;]+)["']?''', caseSensitive: false).allMatches(raw)) {
    final name = match.group(1)?.trim();
    if (name != null && name.isNotEmpty && !attachmentNames.contains(name)) {
      attachmentNames.add(name);
    }
  }

  return Message(
    headers: headers,
    textBody: body,
    htmlBody: htmlBody,
    recipientAddrs: recipientAddrs,
    attachmentNames: attachmentNames,
  );
}

Directory findFixtureDir(String relativePath) {
  final candidate1 = Directory(relativePath);
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = Directory('packages/spam_core/$relativePath');
  if (candidate2.existsSync()) return candidate2;

  throw StateError('Cannot locate fixture directory: $relativePath');
}

List<Message> loadMessagesFromDir(Directory dir) {
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.eml')).toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files.map((f) => parseEml(f.readAsStringSync())).toList();
}

void main() {
  group('Evaluation Benchmark (S7 Accuracy Suite)', () {
    late List<Message> allSpam;
    late List<Message> allHam;
    late List<Message> allPhish;

    setUpAll(() {
      final spamDir = findFixtureDir('test/fixtures/eval/spam');
      final hamDir = findFixtureDir('test/fixtures/eval/ham');
      final phishDir = findFixtureDir('test/fixtures/eval/phish');

      allSpam = loadMessagesFromDir(spamDir);
      allHam = loadMessagesFromDir(hamDir);
      allPhish = loadMessagesFromDir(phishDir);
    });

    test('verifies dataset counts meet specification requirements', () {
      expect(allSpam.length, greaterThanOrEqualTo(30), reason: 'Expected at least 30 synthetic spam fixtures');
      expect(allHam.length, greaterThanOrEqualTo(30), reason: 'Expected at least 30 synthetic ham fixtures');
      expect(allPhish.length, greaterThanOrEqualTo(10), reason: 'Expected at least 10 synthetic phishing fixtures');
    });

    test('trains on 50% split, evaluates on other 50% with strict accuracy assertions', () async {
      final trainSpam = <Message>[];
      final testSpam = <Message>[];
      for (var i = 0; i < allSpam.length; i++) {
        if (i % 2 == 0) {
          trainSpam.add(allSpam[i]);
        } else {
          testSpam.add(allSpam[i]);
        }
      }

      final trainHam = <Message>[];
      final testHam = <Message>[];
      for (var i = 0; i < allHam.length; i++) {
        if (i % 2 == 0) {
          trainHam.add(allHam[i]);
        } else {
          testHam.add(allHam[i]);
        }
      }

      final store = MemoryTokenStore();

      // Train on first half of spam
      for (final msg in trainSpam) {
        final norm = Normalizer.normalize(msg);
        final tokens = Tokenizer.tokens(norm);
        for (final token in tokens) {
          final hash = Tokenizer.hashToken(token);
          await store.apply(hash, Label.spam, 1);
        }
        store.addMessages(Label.spam, 1);
      }

      // Train on first half of ham
      for (final msg in trainHam) {
        final norm = Normalizer.normalize(msg);
        final tokens = Tokenizer.tokens(norm);
        for (final token in tokens) {
          final hash = Tokenizer.hashToken(token);
          await store.apply(hash, Label.ham, 1);
        }
        store.addMessages(Label.ham, 1);
      }

      // 1. Evaluate Ham Test Set
      var hamAutoMovedCount = 0;
      var hamFlaggedCount = 0;

      for (var i = 0; i < testHam.length; i++) {
        final msg = testHam[i];
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);

        if (verdict.spamScore >= 0.90) {
          hamAutoMovedCount++;
        }
        if (verdict.spamScore >= 0.60) {
          hamFlaggedCount++;
        }
      }

      final hamAutoMoveRate = hamAutoMovedCount / testHam.length;
      final hamFlagRate = hamFlaggedCount / testHam.length;

      // Assertion: ham auto-move rate == 0
      expect(hamAutoMoveRate, equals(0.0),
          reason: 'Ham auto-move rate must be 0 (got $hamAutoMovedCount / ${testHam.length})');

      // Assertion: ham flag rate <= 5%
      expect(hamFlagRate, lessThanOrEqualTo(0.05),
          reason: 'Ham flag rate must be <= 5% (got ${(hamFlagRate * 100).toStringAsFixed(1)}%)');

      // 2. Evaluate Spam Test Set
      var spamCaughtCount = 0;
      for (var i = 0; i < testSpam.length; i++) {
        final msg = testSpam[i];
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);

        if (verdict.spamScore >= 0.60) {
          spamCaughtCount++;
        }
      }

      final spamRecall = spamCaughtCount / testSpam.length;

      // Assertion: spam recall (>= 0.60) >= 0.80
      expect(spamRecall, greaterThanOrEqualTo(0.80),
          reason: 'Spam recall must be >= 80% (got ${(spamRecall * 100).toStringAsFixed(1)}% = $spamCaughtCount / ${testSpam.length})');

      // 3. Evaluate Phishing Set
      for (var i = 0; i < allPhish.length; i++) {
        final msg = allPhish[i];
        final norm = Normalizer.normalize(msg);
        final verdict = await Classifier.score(norm, store);

        expect(
          verdict.isPhishing,
          isTrue,
          reason: 'Phishing fixture #${i + 1} (${msg.firstHeader("subject")}) must be flagged with isPhishing. Evidence: ${verdict.evidence.map((e) => e.id).toList()}',
        );
      }
    });
  });
}
