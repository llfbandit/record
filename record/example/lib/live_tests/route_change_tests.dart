import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'live_test.dart';

// The input picked on the screen goes away, or a new one comes, during a take.
final routeChangeTests = [
  LiveTest(
    id: 'R1',
    title: 'Pause, then resume on the default input',
    purpose:
        'Losing the input pauses the take. resume() goes on from the '
        'default input, and onConfigChanged reports the move.',
    needs:
        'The picked input connected, and another input (e.g. the built-in mic).',
    input: PickedInput.recorded,
    config: const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.pause,
    ),
    steps: (run) async {
      await run.connected();
      await run.start();
      await run.wait(3, 'recording 3 s');
      final mark = run.configs.length;

      await run.removeInput();
      await run.waitFor(
        'the take pauses',
        () => run.state == RecordState.pause,
        timeout: 5,
      );
      run.say('Leave "${run.device!.label}" disconnected.');
      await run.wait(2);
      await run.resume();
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectMoves(mark, 1);
      run.expectNoErrors();
      await run.expectAudio();
    },
  ),
  LiveTest(
    id: 'R2',
    title: 'Follow the default input, without a pause',
    purpose:
        'Losing the input moves the take to the default input at once. '
        'The stream goes on, and onConfigChanged reports the move.',
    needs:
        'The picked input connected, and another input (e.g. the built-in mic).',
    input: PickedInput.recorded,
    stream: true,
    config: const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.follow,
    ),
    steps: (run) async {
      await run.connected();
      await run.start();
      await run.wait(3, 'recording 3 s');
      final mark = run.configs.length;

      await run.removeInput();
      await run.waitFor(
        'the take moves to the default input',
        () => run.movesSince(mark).isNotEmpty,
        timeout: 5,
      );
      final bytesAtMove = run.bytes;
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([RecordState.record, RecordState.stop]);
      run.expectMoves(mark, 1);
      run.expectNoErrors();
      run.expectAudioSince(bytesAtMove, 3);
      // A browser can take 1 to 2 s to report the lost input (Firefox).
      await run.expectAudio(tolerance: kIsWeb ? 3 : 1.5);
    },
  ),
  LiveTest(
    id: 'R3',
    title: 'Stop, and keep the file',
    purpose:
        'Losing the input ends the take by itself. The file keeps what was '
        'recorded.',
    needs: 'The picked input connected.',
    input: PickedInput.recorded,
    config: const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.stop,
    ),
    steps: (run) async {
      await run.connected();
      await run.start();
      await run.wait(3, 'recording 3 s');
      final mark = run.configs.length;

      await run.removeInput();
      await run.waitFor(
        'the take stops',
        () => run.state == RecordState.stop,
        timeout: 5,
      );
      // The app does not know yet. It stops as usual.
      await run.stop(stillRecording: false);

      run.expectStates([RecordState.record, RecordState.stop]);
      run.expectMoves(mark, 0);
      run.expectNoErrors();
      await run.expectAudio();
    },
  ),
  LiveTest(
    id: 'R4',
    title: 'A new input does not move the take',
    purpose:
        'Connecting an input during a take on the default input changes '
        'nothing: no pause, no report, no audio lost.',
    needs: 'The picked input disconnected at start.',
    input: PickedInput.watched,
    config: const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.pause,
    ),
    steps: (run) async {
      await run.disconnected();
      await run.start();
      await run.wait(2, 'recording 2 s');
      final mark = run.configs.length;

      run.say('Connect "${run.device!.label}" now.');
      await run.waitFor(
        '"${run.device!.label}" connected',
        run.listed,
        timeout: 120,
      );
      await run.wait(4, 'recording 4 s');
      await run.stop();

      run.expectStates([RecordState.record, RecordState.stop]);
      run.expectNoReports(mark);
      run.expectNoErrors();
      await run.expectAudio();
    },
  ),
  LiveTest(
    id: 'R5',
    title: 'Resume on the picked input when it comes back',
    purpose:
        'Losing the input pauses the take. When it is back before resume(), '
        'the take goes on from it, with no move reported.',
    needs: 'The picked input connected.',
    input: PickedInput.recorded,
    config: const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.pause,
    ),
    steps: (run) async {
      await run.connected();
      await run.start();
      await run.wait(3, 'recording 3 s');
      final mark = run.configs.length;

      await run.removeInput();
      await run.waitFor(
        'the take pauses',
        () => run.state == RecordState.pause,
        timeout: 5,
      );
      run.say('Connect "${run.device!.label}" again.');
      await run.waitFor(
        '"${run.device!.label}" connected',
        run.listed,
        timeout: 120,
      );
      await run.wait(2, 'letting the input settle');
      await run.resume();
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectMoves(mark, 0);
      run.expectNoErrors();
      await run.expectAudio();
    },
  ),
  LiveTest(
    id: 'R6',
    title: 'A new input during a pause does not move the take',
    purpose:
        'The app pauses a take on the default input. An input connected '
        'meanwhile changes nothing: resume() goes on, with no report.',
    needs: 'The picked input disconnected at start.',
    input: PickedInput.watched,
    config: const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      audioRouteChange: AudioRouteChangeMode.pause,
    ),
    steps: (run) async {
      await run.disconnected();
      await run.start();
      await run.wait(3, 'recording 3 s');
      await run.pause();
      final mark = run.configs.length;

      run.say('The take is paused. Connect "${run.device!.label}" now.');
      await run.waitFor(
        '"${run.device!.label}" connected',
        run.listed,
        timeout: 120,
      );
      await run.wait(2, 'letting the input settle');
      await run.resume();
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectNoReports(mark);
      run.expectNoErrors();
      await run.expectAudio();
    },
  ),
];
