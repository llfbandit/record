
class Device {
  int? id;
  String? name;
  String? channel;
  String? type;
  bool isDefault;

  Device({this.id, this.name, this.channel, this.type, this.isDefault = false});
  
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'channel': channel,
    'type': type,
    'isDefault': isDefault
  };
}