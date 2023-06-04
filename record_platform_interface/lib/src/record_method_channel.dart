import 'dart:async';

import 'package:flutter/services.dart';

import '../record_platform_interface.dart';

class RecordMethodChannel extends RecordPlatform {
  // Channel handlers
  final _methodChannel = const MethodChannel('com.llfbandit.record/messages');

  @override
  Future<void> create(String recorderId) {
    return _methodChannel.invokeMethod<void>(
      'create',
      {'recorderId': recorderId},
    );
  }

  @override
  Future<bool> hasPermission(String recorderId) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'hasPermission',
      {'recorderId': recorderId},
    );
    return result ?? false;
  }

  @override
  Future<bool> isPaused(String recorderId) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'isPaused',
      {'recorderId': recorderId},
    );

    return result ?? false;
  }

  @override
  Future<bool> isRecording(String recorderId) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'isRecording',
      {'recorderId': recorderId},
    );
    return result ?? false;
  }

  @override
  Future<void> pause(String recorderId) {
    return _methodChannel.invokeMethod(
      'pause',
      {'recorderId': recorderId},
    );
  }

  @override
  Future<void> resume(String recorderId) {
    return _methodChannel.invokeMethod(
      'resume',
      {'recorderId': recorderId},
    );
  }

  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) {
    return _methodChannel.invokeMethod('start', {
      'recorderId': recorderId,
      'path': path,
      ...config.toMap(),
    });
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    final eventRecordChannel = EventChannel(
      'com.llfbandit.record/eventsRecord/$recorderId',
    );

    await _methodChannel.invokeMethod('startStream', {
      'recorderId': recorderId,
      ...config.toMap(),
    });

    return eventRecordChannel
        .receiveBroadcastStream()
        .map<Uint8List>((data) => data);
  }

  @override
  Future<String?> stop(String recorderId) async {
    final outputPath = await _methodChannel.invokeMethod(
      'stop',
      {'recorderId': recorderId},
    );

    return outputPath;
  }

  @override
  Future<void> cancel(String recorderId) async {
    _methodChannel.invokeMethod(
      'cancel',
      {'recorderId': recorderId},
    );
  }

  @override
  Future<void> dispose(String recorderId) async {
    await _methodChannel.invokeMethod(
      'dispose',
      {'recorderId': recorderId},
    );
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async {
    final result = await _methodChannel.invokeMethod(
      'getAmplitude',
      {'recorderId': recorderId},
    );

    return Amplitude(
      current: result?['current'] ?? 0.0,
      max: result?['max'] ?? 0.0,
    );
  }

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async {
    final isSupported = await _methodChannel.invokeMethod<bool>(
      'isEncoderSupported',
      {'encoder': encoder.name, 'recorderId': recorderId},
    );

    return isSupported ?? false;
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async {
    final devices = await _methodChannel.invokeMethod<List<dynamic>>(
      'listInputDevices',
      {'recorderId': recorderId},
    );

    return devices
            ?.map((d) => InputDevice.fromMap(d as Map))
            .toList(growable: false) ??
        [];
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    final eventChannel = EventChannel(
      'com.llfbandit.record/events/$recorderId',
    );

    return eventChannel.receiveBroadcastStream().map<RecordState>(
          (state) => RecordState.values.firstWhere((e) => e.index == state),
        );
  }
}
