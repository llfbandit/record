class InputDevice {
  /// The ID used to select the device on the platform.
  final String id;

  /// The label text representation.
  final String label;

  /// The sample rates supported by this device.
  ///
  /// `null` means the device did not report specific rates (all standard
  /// rates are assumed to be supported).
  ///
  /// Currently populated on Android only. iOS and macOS do not expose
  /// per-device sample rate capabilities through a public API.
  final List<int>? sampleRates;

  const InputDevice({
    required this.id,
    required this.label,
    this.sampleRates,
  });

  factory InputDevice.fromMap(Map map) => InputDevice(
        id: map['id'],
        label: map['label'],
        sampleRates: (map['sampleRates'] as List?)?.cast<int>(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        if (sampleRates != null) 'sampleRates': sampleRates,
      };

  @override
  String toString() {
    return '''
      id: $id
      label: $label
      sampleRates: $sampleRates
      ''';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is InputDevice && other.id == id && other.label == label;
  }

  @override
  int get hashCode => id.hashCode ^ label.hashCode;
}
