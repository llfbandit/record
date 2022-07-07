import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:record_windows/record_windows.dart';

Future<void> main() async {
  final record = RecordWindows();

  // final d = await record.listInputDevices();

  await record.start(
    path: p.join(File(Platform.resolvedExecutable).parent.path, 'rec.m4a'),
  );
  await Future.delayed(const Duration(seconds: 3));

  await record.pause();
  await Future.delayed(const Duration(seconds: 1));

  await record.resume();
  await Future.delayed(const Duration(seconds: 1));

  await record.stop();
}
