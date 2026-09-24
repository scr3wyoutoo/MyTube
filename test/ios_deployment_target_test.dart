import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setzt iOS 15 in Projekt, CocoaPods und Framework-Metadaten', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final frameworkInfo = File(
      'ios/Flutter/AppFrameworkInfo.plist',
    ).readAsStringSync();

    expect(
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = 15\.0;').allMatches(project).length,
      3,
    );
    expect(project, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')));
    expect(podfile, contains("platform :ios, '15.0'"));
    expect(
      frameworkInfo,
      matches(RegExp(r'<key>MinimumOSVersion</key>\s*<string>15\.0</string>')),
    );
  });
}
