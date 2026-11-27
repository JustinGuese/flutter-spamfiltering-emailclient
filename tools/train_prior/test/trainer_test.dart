import 'package:test/test.dart';
import 'package:spam_core/spam_core.dart';
import '../lib/trainer.dart';

void main() {
  group('PriorTrainer', () {
    test('tracks ingested message counts for all classes', () {
      final trainer = PriorTrainer();

      trainer.ingest(
        const Message(headers: {'subject': ['Spam 1']}, textBody: 'buy viagra now'),
        Label.spam,
      );
      trainer.ingest(
        const Message(headers: {'subject': ['Spam 2']}, textBody: 'win lottery prize'),
        Label.spam,
      );
      trainer.ingest(
        const Message(headers: {'subject': ['Ham 1']}, textBody: 'team project meeting'),
        Label.ham,
      );
      trainer.ingest(
        const Message(headers: {'subject': ['Newsletter 1']}, textBody: 'weekly updates digest'),
        Label.newsletter,
      );
      trainer.ingest(
        const Message(headers: {'subject': ['Inbox 1']}, textBody: 'personal dinner invoice'),
        Label.inbox,
      );

      expect(trainer.totalSpam, equals(2));
      expect(trainer.totalHam, equals(1));
      expect(trainer.totalNewsletter, equals(1));
      expect(trainer.totalInbox, equals(1));

      final model = trainer.exportModel(minCount: 1, scaleTo: 0);
      expect(model['total_spam'], equals(2));
      expect(model['total_ham'], equals(1));
      expect(model['totals']['spam'], equals(2));
      expect(model['totals']['ham'], equals(1));
      expect(model['totals']['newsletter'], equals(1));
      expect(model['totals']['inbox'], equals(1));
    });

    test('--max-tokens retains tokens with highest salience and drops uninformative ones', () {
      final trainer = PriorTrainer();

      // Ingest 100 spam messages with "topspamtoken"
      for (var i = 0; i < 100; i++) {
        trainer.ingest(
          const Message(headers: {}, textBody: 'topspamtoken'),
          Label.spam,
        );
      }

      // Ingest 100 ham messages with "tophamtoken"
      for (var i = 0; i < 100; i++) {
        trainer.ingest(
          const Message(headers: {}, textBody: 'tophamtoken'),
          Label.ham,
        );
      }

      // Ingest 100 spam and 100 ham messages both containing "neutralword"
      for (var i = 0; i < 100; i++) {
        trainer.ingest(
          const Message(headers: {}, textBody: 'neutralword'),
          Label.spam,
        );
        trainer.ingest(
          const Message(headers: {}, textBody: 'neutralword'),
          Label.ham,
        );
      }

      final spamHighHash = Tokenizer.hashToken('topspamtoken');
      final hamHighHash = Tokenizer.hashToken('tophamtoken');
      final neutralHash = Tokenizer.hashToken('neutralword');

      final modelAll = trainer.exportModel(minCount: 1, maxTokens: 0, scaleTo: 0);
      final tokensMap = modelAll['tokens'] as Map<String, dynamic>;

      expect(tokensMap.containsKey(spamHighHash.toString()), isTrue);
      expect(tokensMap.containsKey(hamHighHash.toString()), isTrue);
      expect(tokensMap.containsKey(neutralHash.toString()), isTrue);

      // Restrict max-tokens to 2: should retain the two highly discriminative tokens and drop neutral ones
      final modelTop2 = trainer.exportModel(minCount: 1, maxTokens: 2, scaleTo: 0);
      final topTokens = (modelTop2['tokens'] as Map<String, dynamic>).keys.toSet();

      expect(topTokens.length, equals(2));
      expect(topTokens.contains(spamHighHash.toString()), isTrue);
      expect(topTokens.contains(hamHighHash.toString()), isTrue);
      expect(topTokens.contains(neutralHash.toString()), isFalse);
    });

    test('--scale-to scales counts and totals so each class is at most N, dropping tokens that become 0', () {
      final trainer = PriorTrainer();

      // Ingest 1000 spam messages
      for (var i = 0; i < 1000; i++) {
        final body = (i < 200) ? 'commonspam rareword' : 'commonspam otherword$i';
        trainer.ingest(
          Message(headers: {'subject': ['Spam']}, textBody: body),
          Label.spam,
        );
      }

      // Ingest 500 ham messages
      for (var i = 0; i < 500; i++) {
        final body = (i < 100) ? 'commonham rareword' : 'commonham otherham$i';
        trainer.ingest(
          Message(headers: {'subject': ['Ham']}, textBody: body),
          Label.ham,
        );
      }

      expect(trainer.totalSpam, equals(1000));
      expect(trainer.totalHam, equals(500));

      // Scale to 200
      final scaled = trainer.exportModel(minCount: 1, maxTokens: 0, scaleTo: 200);

      expect(scaled['total_spam'], equals(200));
      expect(scaled['total_ham'], equals(200));
      expect(scaled['totals']['spam'], equals(200));
      expect(scaled['totals']['ham'], equals(200));
      expect(scaled['raw_totals']['spam'], equals(1000));
      expect(scaled['raw_totals']['ham'], equals(500));

      final tokensMap = scaled['tokens'] as Map<String, dynamic>;

      // commonspam was 1000 in spam -> scaled to (1000 * (200/1000)).round() = 200
      final commonSpamHash = Tokenizer.hashToken('commonspam');
      expect(tokensMap[commonSpamHash.toString()]['spam'], equals(200));

      // commonham was 500 in ham -> scaled to (500 * (200/500)).round() = 200
      final commonHamHash = Tokenizer.hashToken('commonham');
      expect(tokensMap[commonHamHash.toString()]['ham'], equals(200));

      // Each single-occurrence otherword$i was 1 in spam:
      // (1 * 0.2).round() = 0 -> dropped!
      final sampleOtherHash = Tokenizer.hashToken('otherword500');
      expect(tokensMap.containsKey(sampleOtherHash.toString()), isFalse);
    });

    test('createDefaultModel produces valid model with top-level totals', () {
      final defaultModel = PriorTrainer.createDefaultModel();
      expect(defaultModel['total_spam'], isPositive);
      expect(defaultModel['total_ham'], isPositive);
      expect(defaultModel['tokens'], isNotEmpty);
      expect(defaultModel['version'], equals(1));
    });
  });
}
