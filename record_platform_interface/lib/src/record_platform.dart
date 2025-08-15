import 'record_method_channel_mixin.dart';
import 'record_platform_interface.dart';

class RecordPlatformImpl extends RecordPlatform
    with RecordMethodChannel, RecordEventChannel {
  RecordPlatformImpl();
}
