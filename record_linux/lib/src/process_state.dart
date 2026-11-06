import 'dart:io';

/// SIGTERM is signal 15, and bit n - 1 of a signal mask stands for signal n.
const _sigtermBit = 0x4000;

/// What /proc says about a process that will not end, in one line.
///
/// Read once, and only to be logged: a capture is killed because its timeout
/// ran out, never because of what this says.
String describeProcess(int pid) {
  try {
    final stat = File('/proc/$pid/stat').readAsStringSync();
    final wchan = File('/proc/$pid/wchan').readAsStringSync();
    final status = File('/proc/$pid/status').readAsStringSync();
    final pending = termPendingFrom(status) ? 'pending' : 'not pending';

    return 'state ${stateFromStat(stat)}, waiting in ${wchanFrom(wchan)}, '
        'SIGTERM $pending, ${termDispositionFrom(status)}';
  } on FileSystemException {
    // The process ended while it was being read.
    return 'state unknown';
  }
}

/// The one-letter state from `/proc/<pid>/stat`, or `?`.
///
/// It is the field behind the program name, and that name can hold spaces and
/// brackets of its own, so it is skipped by its last bracket.
String stateFromStat(String stat) {
  final name = stat.lastIndexOf(')');
  if (name < 0) return '?';

  final state = stat.substring(name + 1).trim().split(' ').first;

  return state.isEmpty ? '?' : state;
}

/// The kernel function from `/proc/<pid>/wchan`, or `-` when it says nothing.
String wchanFrom(String wchan) {
  final waiting = wchan.trim();

  return waiting.isEmpty ? '-' : waiting;
}

/// Whether SIGTERM is waiting for the process or for its main thread.
///
/// `/proc/<pid>/status` carries the shared mask and the main thread's own, so
/// a signal queued privately to another thread is not covered. For a line
/// about a capture that will not end, that is enough.
bool termPendingFrom(String status) {
  final pending = _mask(status, 'SigPnd') | _mask(status, 'ShdPnd');

  return pending & _sigtermBit != 0;
}

/// Whether the program ignores SIGTERM, handles it, or leaves it at default.
String termDispositionFrom(String status) {
  if (_mask(status, 'SigIgn') & _sigtermBit != 0) return 'ignored';
  if (_mask(status, 'SigCgt') & _sigtermBit != 0) return 'handled';

  return 'default';
}

/// The signal mask that [field] holds in `/proc/<pid>/status`, or zero.
int _mask(String status, String field) {
  for (final line in status.split('\n')) {
    if (!line.startsWith('$field:')) continue;

    final fields = line.split(RegExp(r'\s+'));
    if (fields.length < 2) return 0;

    return int.tryParse(fields[1], radix: 16) ?? 0;
  }

  return 0;
}
