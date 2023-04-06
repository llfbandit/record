#import "RecordPlugin.h"
#if __has_include(<record/record-Swift.h>)
#import <record/record-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "record-Swift.h"
#endif

@implementation RecordPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftRecordPlugin registerWithRegistrar:registrar];
}
@end
