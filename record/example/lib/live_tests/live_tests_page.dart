import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'interruption_tests.dart';
import 'live_test.dart';
import 'route_change_tests.dart';

// Guided tests on a real device, for route changes and interruptions.
class LiveTestsPage extends StatefulWidget {
  const LiveTestsPage({super.key});

  @override
  State<LiveTestsPage> createState() => _LiveTestsPageState();
}

class _LiveTestsPageState extends State<LiveTestsPage> {
  final _recorder = AudioRecorder();
  List<InputDevice> _devices = [];
  InputDevice? _device;
  final _results = <String, Outcome>{};

  // Only Android and iOS report interruptions.
  static final _hasInterruptions =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    // Some platforms list inputs only after the permission.
    await _recorder.hasPermission();
    final all = await _recorder.listInputDevices();
    // A built-in mic cannot be disconnected.
    final devices = all.where((d) => d.type != InputDeviceType.builtIn);
    setState(() {
      _devices = devices.toList();
      // Keep the pick while it is disconnected: the tests need that.
      if (_device != null && !devices.contains(_device)) {
        _devices = [..._devices, _device!];
      }
    });
  }

  Future<void> _run(LiveTest test) async {
    final run = LiveRun(test, _device);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => LiveRunPage(run: run)));
    setState(() => _results[test.id] = run.outcome);
    _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _hasInterruptions ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live tests'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Route change'),
              if (_hasInterruptions) const Tab(text: 'Interruption'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _TestList(
              header: _devicePicker(),
              tests: routeChangeTests,
              device: _device,
              results: _results,
              onRun: _run,
            ),
            if (_hasInterruptions)
              _TestList(
                header: const _Tip(
                  'You need a second phone to call this one. '
                  'Keep this app on screen until the call comes.',
                ),
                tests: interruptionTests,
                device: _device,
                results: _results,
                onRun: _run,
              ),
          ],
        ),
      ),
    );
  }

  Widget _devicePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Tip(
          'Pick an input you can disconnect: Bluetooth buds, a USB mic or a '
          'wired headset. Another input must stay, like the built-in mic.',
        ),
        if (kIsWeb)
          const _Tip(
            'Keep this page focused: a browser may only see an input come or '
            'go while it has the focus.',
          ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          const _Tip(
            'iOS cannot start audio input in the background. Keep this app '
            'on screen: connect the buds from their case, not from Settings.',
          ),
        Row(
          children: [
            const Text('Input'),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButton<InputDevice>(
                value: _device,
                isExpanded: true,
                hint: Text(
                  _devices.isEmpty
                      ? 'Connect an input, then refresh'
                      : 'Pick the input to disconnect',
                ),
                items: _devices
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(d.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (d) => setState(() => _device = d),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loadDevices,
            ),
          ],
        ),
      ],
    );
  }
}

class _TestList extends StatelessWidget {
  const _TestList({
    required this.header,
    required this.tests,
    required this.device,
    required this.results,
    required this.onRun,
  });

  final Widget header;
  final List<LiveTest> tests;
  final InputDevice? device;
  final Map<String, Outcome> results;
  final void Function(LiveTest) onRun;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 8),
        for (final test in tests)
          _TestCard(
            test: test,
            device: device,
            result: results[test.id],
            onRun: test.input == PickedInput.unused || device != null
                ? () => onRun(test)
                : null,
          ),
      ],
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.test,
    required this.device,
    required this.result,
    required this.onRun,
  });

  final LiveTest test;
  final InputDevice? device;
  final Outcome? result;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${test.id} · ${test.title}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (result != null) _OutcomeChip(result!),
              ],
            ),
            Text(test.purpose),
            Text(
              test.recap(device),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            Text('You need: ${test.needs}', style: theme.textTheme.bodySmall),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onRun,
                child: Text(onRun == null ? 'Pick an input first' : 'Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One run: what to do now, what happens, then the result.
class LiveRunPage extends StatefulWidget {
  const LiveRunPage({super.key, required this.run});

  final LiveRun run;

  @override
  State<LiveRunPage> createState() => _LiveRunPageState();
}

class _LiveRunPageState extends State<LiveRunPage> {
  LiveRun get run => widget.run;

  @override
  void initState() {
    super.initState();
    run.run();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final running = run.outcome == Outcome.running;
        return PopScope(
          // Back cancels a running test first.
          canPop: !running,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) run.cancel();
          },
          child: Scaffold(
            appBar: AppBar(title: Text('${run.test.id} · ${run.test.title}')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  run.test.recap(run.device),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                if (running) _live(context) else _result(context),
                const SizedBox(height: 16),
                Text('Log', style: Theme.of(context).textTheme.titleSmall),
                for (final line in run.log.reversed)
                  Text(
                    line,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _live(BuildContext context) {
    final theme = Theme.of(context);
    final left = run.waitEnds == null ? null : run.waitEnds! - run.elapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              run.instruction ?? '',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        if (run.waitingFor != null)
          Row(
            spacing: 12,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              Expanded(
                child: Text(
                  'Waiting: ${run.waitingFor}'
                  '${left == null ? '' : ' (${left.inSeconds} s left)'}',
                ),
              ),
            ],
          ),
        Text(
          'State: ${run.state?.name ?? '-'} · '
          'recorded: ${run.recordSeconds.toStringAsFixed(1)} s'
          '${run.test.stream ? ' · stream: ${run.streamSeconds(run.bytes).toStringAsFixed(1)} s' : ''}',
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 12,
          children: [
            OutlinedButton(onPressed: run.cancel, child: const Text('Cancel')),
            if (run.asksDone)
              FilledButton(onPressed: run.userDone, child: const Text('Done')),
          ],
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (run.outcome) {
      Outcome.passed => ('PASSED', Colors.green),
      Outcome.failed => ('FAILED', theme.colorScheme.error),
      _ => ('CANCELLED', Colors.grey),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Card(
          color: color.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.headlineSmall?.copyWith(color: color),
                ),
                if (run.failure != null) Text(run.failure!),
              ],
            ),
          ),
        ),
        for (final c in run.checks)
          ListTile(
            dense: true,
            leading: Icon(
              c.ok ? Icons.check_circle : Icons.cancel,
              color: c.ok ? Colors.green : theme.colorScheme.error,
            ),
            title: Text(c.name),
            subtitle: Text(
              '${c.actual}${c.expected == null ? '' : '   expected ${c.expected}'}',
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 12,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy report'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: run.report));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Report copied')));
              },
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip(this.outcome);

  final Outcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      Outcome.passed => ('passed', Colors.green),
      Outcome.failed => ('failed', Theme.of(context).colorScheme.error),
      _ => ('cancelled', Colors.grey),
    };
    return Text(label, style: TextStyle(color: color));
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
