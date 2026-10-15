import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/more_screen.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/screen_guard.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

const _channel = MethodChannel('com.offlineexpensemgr.silentwallet/window');

/// Records calls the app makes to the native side.
List<MethodCall> _mockNative(WidgetTester? t) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings.allowScreenshots', () {
    test('is off by default (private)', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      expect(s.allowScreenshots, isFalse);
    });

    test('is saved and read back', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      await s.setAllowScreenshots(true);
      expect(s.allowScreenshots, isTrue);
      expect((await Settings.load()).allowScreenshots, isTrue);
      await s.setAllowScreenshots(false);
      expect((await Settings.load()).allowScreenshots, isFalse);
    });

    test('notifies listeners when changed', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      var n = 0;
      s.addListener(() => n++);
      await s.setAllowScreenshots(true);
      expect(n, 1);
    });
  });

  group('ScreenGuard', () {
    test('sends the secure flag to the native side', () async {
      final calls = _mockNative(null);
      await ScreenGuard.setSecure(true);
      await ScreenGuard.setSecure(false);
      expect(calls.map((c) => c.method), ['setSecure', 'setSecure']);
      expect(calls.map((c) => c.arguments), [true, false]);
    });

    test('does not crash when there is no native side', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      await ScreenGuard.setSecure(true); // MissingPluginException is swallowed
    });
  });

  group('More tab switch', () {
    Future<(Settings, List<MethodCall>)> pumpMore(WidgetTester t, {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final settings = await Settings.load();
      final calls = _mockNative(t);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(393, 851);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<Settings>.value(value: settings),
          ChangeNotifierProvider<Repo>.value(value: FakeRepo()),
          ChangeNotifierProvider<LockController>.value(value: LockController(settings)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: compactText,
          home: const Scaffold(body: MoreScreen()),
        ),
      ));
      await t.pumpAndSettle();
      return (settings, calls);
    }

    Finder tile() => find.widgetWithText(SwitchListTile, 'Allow screenshots');

    testWidgets('is shown, off by default, and explains itself', (t) async {
      await pumpMore(t);
      expect(tile(), findsOneWidget);
      expect(t.widget<SwitchListTile>(tile()).value, isFalse);
      expect(find.textContaining('screenshots and screen recording are blocked'), findsOneWidget);
    });

    testWidgets('turning it on allows screenshots (clears the secure flag)', (t) async {
      final (settings, calls) = await pumpMore(t);
      await t.tap(tile());
      await t.pumpAndSettle();
      expect(settings.allowScreenshots, isTrue);
      expect(t.widget<SwitchListTile>(tile()).value, isTrue);
      expect(calls.single.method, 'setSecure');
      expect(calls.single.arguments, false); // secure = false
    });

    testWidgets('turning it off blocks screenshots again', (t) async {
      final (settings, calls) = await pumpMore(t, prefs: {'allow_screenshots': true});
      expect(t.widget<SwitchListTile>(tile()).value, isTrue);
      await t.tap(tile());
      await t.pumpAndSettle();
      expect(settings.allowScreenshots, isFalse);
      expect(calls.single.arguments, true); // secure = true
    });
  });
}
