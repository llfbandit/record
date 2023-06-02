class InputDevice {
  /// The ID used to select the device on the platform.
  final String id;

  /// The label text representation.
  final String label;

  /// The number of channels for the device.
  final int? channels;

  /// The sample rate for the device.
  final int? sampleRate;

  const InputDevice({
    required this.id,
    required this.label,
    this.channels,
    this.sampleRate,
  });

  factory InputDevice.fromMap(Map map) => InputDevice(
        id: map['id'],
        label: map['label'],
        channels: map['channels'],
        sampleRate: map['sampleRate'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'channels': channels,
        'sampleRate': sampleRate,
      };

  @override
  String toString() {
    return '''
      id: $id
      label: $label
      channels: $channels
      sampleRate: $sampleRate
      ''';
  }
}
