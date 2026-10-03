import 'package:record/record.dart';

import 'live_test.dart';

const _call =
    'Call this phone from another phone. Answer, talk a few seconds, '
    'hang up, and come back to this screen.';

const _needs =
    'A second phone to call this one. No Bluetooth headset: the call would use it.';

// Streams, so we see when audio comes again.
RecordConfig _config(AudioInterruptionMode mode) => RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  audioInterruption: mode,
);

// A phone call interrupts the take.
final interruptionTests = [
  LiveTest(
    id: 'I1',
    title: 'Pause, then resume by hand',
    purpose:
        'The call pauses the take, and it stays paused after the call. '
        'resume() records again.',
    needs: _needs,
    stream: true,
    config: _config(AudioInterruptionMode.pause),
    steps: (run) async {
      await run.noBluetooth();
      await run.start();
      await run.wait(2, 'recording 2 s');

      run.say(_call);
      await run.waitFor(
        'the call pauses the take',
        () => run.state == RecordState.pause,
        timeout: 180,
      );
      await run.askDone('Tap Done once the call has ended.');
      await run.wait(3, 'the take must stay paused');
      run.expectState(RecordState.pause, 'state after the call');

      await run.resume();
      final mark = run.bytes;
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectAudioSince(mark, 3);
      run.expectNoErrors();
    },
  ),
  LiveTest(
    id: 'I2',
    title: 'Pause, then resume by itself',
    purpose:
        'The call pauses the take. It records again by itself after the call.',
    needs: _needs,
    stream: true,
    config: _config(AudioInterruptionMode.pauseResume),
    steps: (run) async {
      await run.noBluetooth();
      await run.start();
      await run.wait(2, 'recording 2 s');

      run.say(_call);
      await run.waitFor(
        'the call pauses the take',
        () => run.state == RecordState.pause,
        timeout: 180,
      );
      await run.waitFor(
        'the take records again after the call',
        () => run.state == RecordState.record,
        timeout: 300,
      );
      final mark = run.bytes;
      run.say('Wait a few seconds.');
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectAudioSince(mark, 3);
      run.expectNoErrors();
    },
  ),
  LiveTest(
    id: 'I3',
    title: 'Never pause',
    purpose:
        'The take never pauses. It captures nothing during the call, '
        'and records again after it.',
    needs: _needs,
    stream: true,
    config: _config(AudioInterruptionMode.none),
    steps: (run) async {
      await run.noBluetooth();
      await run.start();
      await run.wait(2, 'recording 2 s');

      await run.askDone('$_call Then tap Done.');
      final mark = run.bytes;
      run.say('Wait a few seconds.');
      await run.wait(4, 'recording 4 s');
      await run.stop();

      run.expectStates([RecordState.record, RecordState.stop]);
      run.expectAudioSince(mark, 4);
      run.expectNoErrors();
    },
  ),
  LiveTest(
    id: 'I4',
    title: 'A pause by the app stays',
    purpose:
        'The app paused the take before the call. After the call, the '
        'system must not resume it: only the app does.',
    needs: _needs,
    stream: true,
    config: _config(AudioInterruptionMode.pauseResume),
    steps: (run) async {
      await run.noBluetooth();
      await run.start();
      await run.wait(2, 'recording 2 s');
      await run.pause();

      await run.askDone('The take is paused. $_call Then tap Done.');
      await run.wait(5, 'the take must stay paused');
      run.expectState(RecordState.pause, 'state after the call');

      await run.resume();
      final mark = run.bytes;
      await run.wait(3, 'recording 3 s');
      await run.stop();

      run.expectStates([
        RecordState.record,
        RecordState.pause,
        RecordState.record,
        RecordState.stop,
      ]);
      run.expectAudioSince(mark, 3);
      run.expectNoErrors();
    },
  ),
];
