import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/pactl_devices.dart';
import 'package:record_linux/src/route_monitor.dart';

/// Fakes pactl output, so this runs on any host.
void main() {
  const pid = 4242;

  List<String> sourceOutputs({required int source, int owner = pid}) => [
    'Source Output #7',
    '\tSource: 99',
    '\tProperties:',
    '\t\tapplication.process.id = "1"',
    'Source Output #8',
    '\tSource: $source',
    '\tProperties:',
    '\t\tapplication.process.id = "$owner"',
  ];

  List<String> shortSources(List<int> indexes) => [
    for (final index in indexes) '$index\tsource_$index\tPipeWire\ts16le',
  ];

  group('parsers', () {
    test('reads a subscribe event', () {
      expect(parsePactlEvent("Event 'remove' on source #54"), (
        type: 'remove',
        facility: 'source',
        index: 54,
      ));
      expect(
        parsePactlEvent("Event 'change' on source-output #3")?.facility,
        'source-output',
      );
      expect(parsePactlEvent('garbage'), isNull);
    });

    test('finds the source of the stream a process owns', () {
      expect(parseStreamSource(sourceOutputs(source: 54), pid), 54);
      expect(parseStreamSource(sourceOutputs(source: 54), 1), 99);
      expect(parseStreamSource(sourceOutputs(source: 54), 5), isNull);
    });

    test('ignores an unlinked stream', () {
      expect(parseStreamSource(sourceOutputs(source: 4294967295), pid), isNull);
    });

    test('reads short source names without monitors', () {
      expect(
        parseShortSourceNames(const [
          '1\talsa_output.pci.analog-stereo.monitor\tPipeWire\ts16le',
          '2\talsa_input.pci.analog-stereo\tPipeWire\ts16le',
        ]),
        {'alsa_input.pci.analog-stereo'},
      );
    });
  });

  group('RouteMonitor', () {
    late List<String> outputs;
    late List<int> sources;
    late int lost;
    late RouteMonitor monitor;

    setUp(() {
      outputs = sourceOutputs(source: 54);
      sources = [54, 60];
      lost = 0;
      monitor = RouteMonitor(
        run: (args) async =>
            args.contains('short') ? shortSources(sources) : outputs,
      )..watch(capturePid: pid, onRouteLost: () => lost++);
    });

    test('reports the removal of the source in use', () async {
      await monitor.handleEvent("Event 'new' on source-output #8");
      await monitor.handleEvent("Event 'remove' on source #60");
      expect(lost, 0);

      await monitor.handleEvent("Event 'remove' on source #54");
      expect(lost, 1);
    });

    test('reports a rescue move seen before the removal', () async {
      await monitor.handleEvent("Event 'new' on source-output #8");

      // PulseAudio moves the stream, then reports the removal.
      outputs = sourceOutputs(source: 60);
      sources = [60];
      await monitor.handleEvent("Event 'change' on source-output #8");

      expect(lost, 1);
    });

    test('follows a move while the old source remains', () async {
      await monitor.handleEvent("Event 'new' on source-output #8");

      outputs = sourceOutputs(source: 60);
      await monitor.handleEvent("Event 'change' on source-output #8");
      await monitor.handleEvent("Event 'remove' on source #54");
      expect(lost, 0);

      await monitor.handleEvent("Event 'remove' on source #60");
      expect(lost, 1);
    });

    test('reports once, then stays quiet until watched again', () async {
      await monitor.handleEvent("Event 'new' on source-output #8");
      await monitor.handleEvent("Event 'remove' on source #54");
      await monitor.handleEvent("Event 'remove' on source #54");

      expect(lost, 1);
    });
  });
}
