class InputDevice {
  /// The ID used to select the device on the platform.
  final String id;

  /// The label text representation.
  final String label;

  /// The number of channels for the device.
  final int? channels;

  /// The sampling for the device.
  final int? samplingRate;

  const InputDevice({
    required this.id,
    required this.label,
    this.channels,
    this.samplingRate,
  });

  factory InputDevice.fromMap(Map map) => InputDevice(
        id: map['id'],
        label: map['label'],
        channels: map['channels'],
        samplingRate: map['samplingRate'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'channels': channels,
        'samplingRate': samplingRate,
      };
}
