import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:spam_core/spam_core.dart';
import '../lib/corpus_reader.dart';
import '../lib/trainer.dart';
import '../lib/evaluator.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage information')
    ..addCommand('train')
    ..addCommand('eval')
    ..addCommand('generate-default');

  // Train options
  parser.commands['train']!
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage information')
    ..addOption('spam-dir', help: 'Directory containing spam EML files')
    ..addOption('ham-dir', help: 'Directory containing ham EML files')
    ..addOption('news-dir', help: 'Directory containing newsletter EML files')
    ..addOption('output', abbr: 'o', defaultsTo: 'prior_model.json', help: 'Output JSON model path')
    ..addOption('min-count', defaultsTo: '2', help: 'Minimum token count threshold')
    ..addOption('max-tokens', defaultsTo: '20000', help: 'Maximum number of top informative tokens to retain')
    ..addOption('scale-to', defaultsTo: '200', help: 'Scale token counts and totals so each class equals at most N messages');

  // Eval options
  parser.commands['eval']!
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage information')
    ..addFlag('json', negatable: false, help: 'Print machine-readable JSON output')
    ..addOption('model', abbr: 'm', defaultsTo: 'prior_model.json', help: 'Path to trained model')
    ..addOption('spam-dir', help: 'Test spam directory')
    ..addOption('ham-dir', help: 'Test ham directory');

  // Generate-default options
  parser.commands['generate-default']!
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print usage information')
    ..addOption('output', abbr: 'o', defaultsTo: 'prior_model.json', help: 'Output JSON model path');

  final ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print(e);
    print('Run "train_prior --help" for usage.');
    exit(1);
  }

  if (results['help'] == true || results.command == null) {
    print('Usage: train_prior <train|eval|generate-default> [options]\n');
    print(parser.usage);
    print('\nCommands:');
    for (final cmd in parser.commands.keys) {
      print('\n$cmd:');
      print(parser.commands[cmd]!.usage);
    }
    exit(0);
  }

  if (results.command!['help'] == true) {
    print('Usage: train_prior ${results.command!.name} [options]\n');
    print(parser.commands[results.command!.name]!.usage);
    exit(0);
  }

  switch (results.command!.name) {
    case 'train':
      final cmd = results.command!;
      final spamDir = cmd['spam-dir'] as String?;
      final hamDir = cmd['ham-dir'] as String?;
      final newsDir = cmd['news-dir'] as String?;
      final outputPath = cmd['output'] as String;
      final minCount = int.parse(cmd['min-count'] as String);
      final maxTokens = int.parse(cmd['max-tokens'] as String);
      final scaleTo = int.parse(cmd['scale-to'] as String);

      final trainer = PriorTrainer();

      if (spamDir != null) {
        print('Ingesting spam from $spamDir...');
        final msgs = CorpusReader.readDirectory(Directory(spamDir));
        for (final m in msgs) {
          trainer.ingest(m, Label.spam);
        }
        print('Ingested ${msgs.length} spam messages.');
      }

      if (hamDir != null) {
        print('Ingesting ham from $hamDir...');
        final msgs = CorpusReader.readDirectory(Directory(hamDir));
        for (final m in msgs) {
          trainer.ingest(m, Label.ham);
        }
        print('Ingested ${msgs.length} ham messages.');
      }

      if (newsDir != null) {
        print('Ingesting newsletters from $newsDir...');
        final msgs = CorpusReader.readDirectory(Directory(newsDir));
        for (final m in msgs) {
          trainer.ingest(m, Label.newsletter);
        }
        print('Ingested ${msgs.length} newsletter messages.');
      }

      final outFile = File(outputPath);
      trainer.saveToFile(
        outFile,
        minCount: minCount,
        maxTokens: maxTokens,
        scaleTo: scaleTo,
      );
      print('Saved trained model to $outputPath');
      break;

    case 'generate-default':
      final cmd = results.command!;
      final outputPath = cmd['output'] as String;
      final defaultModel = PriorTrainer.createDefaultModel();
      final outFile = File(outputPath);
      outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(defaultModel));
      print('Generated default clean prior model at $outputPath');
      break;

    case 'eval':
      final cmd = results.command!;
      final modelPath = cmd['model'] as String;
      final spamDir = cmd['spam-dir'] as String?;
      final hamDir = cmd['ham-dir'] as String?;
      final isJson = cmd['json'] as bool? ?? false;

      final store = await CorpusEvaluator.loadModel(File(modelPath));
      final evaluator = CorpusEvaluator(store);

      final samples = <MapEntry<Message, Label>>[];
      if (spamDir != null) {
        for (final m in CorpusReader.readDirectory(Directory(spamDir))) {
          samples.add(MapEntry(m, Label.spam));
        }
      }
      if (hamDir != null) {
        for (final m in CorpusReader.readDirectory(Directory(hamDir))) {
          samples.add(MapEntry(m, Label.ham));
        }
      }

      if (samples.isEmpty) {
        print('No test samples provided.');
        exit(1);
      }

      final metrics = await evaluator.evaluate(samples);
      if (isJson) {
        print(const JsonEncoder.withIndent('  ').convert(metrics.toJson()));
      } else {
        metrics.printSummary();
      }
      break;
  }
}
