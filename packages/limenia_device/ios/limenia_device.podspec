#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'limenia_device'
  s.version          = '0.1.1'
  s.summary          = 'Device tokens for the device connector of Limenia.'
  s.description      = <<-DESC
DeviceCheck tokens for the device connector of Limenia (Play Integrity on Android).
                       DESC
  s.homepage         = 'https://github.com/DL3KB/limenia-flutter/tree/main/packages/limenia_device'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Limenia' => 'https://github.com/DL3KB' }
  s.source           = { :path => '.' }
  s.source_files = 'limenia_device/Sources/limenia_device/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'DeviceCheck'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # DeviceCheck is no required reason API and the plugin collects no data itself: the privacy manifest is empty.
  s.resource_bundles = {'limenia_device_privacy' => ['limenia_device/Sources/limenia_device/PrivacyInfo.xcprivacy']}
end
