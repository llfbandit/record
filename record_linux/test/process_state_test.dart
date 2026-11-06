import 'package:flutter_test/flutter_test.dart';
import 'package:record_linux/src/process_state.dart';

/// Sample texts as the kernel writes them, so the parsing needs no process.
void main() {
  // A capture frozen by pause: SIGTERM has arrived but cannot be acted on,
  // and the program handles it.
  const stopped =
      'Name:\tparecord\n'
      'State:\tT (stopped)\n'
      'SigPnd:\t0000000000000000\n'
      'ShdPnd:\t0000000000004000\n'
      'SigBlk:\t0000000000000000\n'
      'SigIgn:\t0000000000000000\n'
      'SigCgt:\t0000000000004000\n';

  // A capture that ignores SIGTERM: nothing stays pending, because an
  // ignored signal is thrown away on delivery.
  // The same signal delivered to one thread rather than the whole process.
  const threadPending =
      'Name:\tparecord\n'
      'SigPnd:\t0000000000004000\n'
      'ShdPnd:\t0000000000000000\n'
      'SigIgn:\t0000000000000000\n'
      'SigCgt:\t0000000000000000\n';

  const ignoring =
      'Name:\tparecord\n'
      'State:\tS (sleeping)\n'
      'SigPnd:\t0000000000000000\n'
      'ShdPnd:\t0000000000000000\n'
      'SigIgn:\t0000000000004000\n'
      'SigCgt:\t0000000000000000\n';

  group('stateFromStat', () {
    test('reads the state after the program name', () {
      expect(stateFromStat('4711 (parecord) S 1 4711 4711 0 -1 4194304'), 'S');
    });

    test('survives a program name with spaces and brackets', () {
      expect(stateFromStat('4711 (pa cat (2)) T 1 4711 0'), 'T');
    });

    test('reports an unreadable line as unknown', () {
      expect(stateFromStat('4711 parecord'), '?');
    });
  });

  group('wchanFrom', () {
    test('reads the kernel function', () {
      expect(wchanFrom('do_signal_stop\n'), 'do_signal_stop');
    });

    test('reports an empty file as nothing', () {
      expect(wchanFrom(''), '-');
    });
  });

  group('termPendingFrom', () {
    test('finds SIGTERM waiting for the process', () {
      expect(termPendingFrom(stopped), isTrue);
    });

    test('finds SIGTERM waiting for the main thread', () {
      expect(termPendingFrom(threadPending), isTrue);
    });

    test('reports nothing pending', () {
      expect(termPendingFrom(ignoring), isFalse);
    });

    test('reports nothing pending without the fields', () {
      expect(termPendingFrom('Name:\tparecord\n'), isFalse);
    });
  });

  group('termDispositionFrom', () {
    test('reports a handled SIGTERM', () {
      expect(termDispositionFrom(stopped), 'handled');
    });

    test('reports an ignored SIGTERM', () {
      expect(termDispositionFrom(ignoring), 'ignored');
    });

    test('reports the default when the program says nothing', () {
      expect(termDispositionFrom('Name:\tparecord\n'), 'default');
    });
  });
}
