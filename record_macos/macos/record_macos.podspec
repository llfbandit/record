#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint record_macos.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'record_macos'
  s.version          = '0.2.0'
  s.summary          = 'macOS implementation for record package.'
  s.description      = <<-DESC
  macOS implementation for record package.
                       DESC
  s.homepage         = 'https://github.com/llfbandit/record/tree/master/record_macos'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
