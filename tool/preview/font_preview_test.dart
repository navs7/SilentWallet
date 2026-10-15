// Renders before / after images of the app's typography. Not part of the normal
// test run; use:  flutter test tool/preview/font_preview_test.dart
// Images are written to build/preview/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/home.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import '../../test/test_support.dart';

Future<void> _loadFonts() async {
  await loadAppFonts();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader('Roboto');
  for (final n in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final f = File('${dir.path}/$n');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
  // the icon font, so icons draw as icons (not empty squares)
  final icons = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) {
    final il = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await il.load();
  }
}

FakeRepo _sampleRepo() {
  final r = FakeRepo();
  r.accounts = [Account(id: 'a1', name: 'Cash', type: 'Cash', isDefault: true), Account(id: 'a2', name: 'HDFC Savings', type: 'Bank')];
  r.categories = [
    Category(id: 'food', name: 'Food & Dining', icon: 'restaurant', color: 0xFFE57373, kind: TxType.expense),
    Category(id: 'fuel', name: 'Fuel', icon: 'fuel', color: 0xFF7986CB, kind: TxType.expense),
    Category(id: 'groc', name: 'Groceries', icon: 'cart', color: 0xFF81C784, kind: TxType.expense),
    Category(id: 'other', name: 'Other', icon: 'other', color: 0xFF90A4AE, kind: TxType.expense),
    Category(id: 'sal', name: 'Salary', icon: 'salary', color: 0xFF4DB6AC, kind: TxType.income),
  ];
  final n = DateTime.now();
  DateTime d(int day, int h) => DateTime(n.year, n.month, day, h);
  Tx t(String id, DateTime date, int paise, String note, String cat, {TxType type = TxType.expense}) =>
      Tx(id: id, type: type, amount: paise, accountId: 'a1', categoryId: cat, note: note, date: date);
  r.txs = [
    t('1', d(10, 18), 27000, 'Icecream', 'food'),
    t('2', d(8, 13), 15900, 'Coffee', 'food'),
    t('3', d(6, 9), 51900, 'Misc', 'other'),
    t('4', d(4, 20), 26000, 'Coffee', 'food'),
    t('5', d(3, 12), 17200, 'Snacks', 'food'),
    t('6', d(3, 9), 27000, 'Coffee', 'food'),
    t('7', d(2, 8), 248400, 'Car petrol', 'fuel'),
    t('8', d(1, 10), 4500000, 'Salary', 'sal', type: TxType.income),
    t('9', d(1, 18), 183050, 'Weekly shop', 'groc'),
  ];
  r.hasData = true;
  return r;
}

Future<void> _save(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final f = File('build/preview/$name.png');
    await f.create(recursive: true);
    await f.writeAsBytes(bytes.buffer.asUint8List());
  });
}

Widget _phone(String label, ThemeData theme, {required bool inter}) => SizedBox(
      width: 393,
      height: 760,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: theme.colorScheme.brightness == Brightness.dark ? Colors.white70 : Colors.black87, fontFamily: 'Inter')),
        ),
        Expanded(
          child: ClipRect(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: compactText,
              home: const HomeScreen(),
            ),
          ),
        ),
      ]),
    );

ThemeData _oldLook(Brightness b) {
  final t = buildTheme(b);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: t.appBarTheme.copyWith(titleTextStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 18, fontWeight: FontWeight.w500)),
    navigationBarTheme: t.navigationBarTheme.copyWith(labelTextStyle: WidgetStateProperty.all(const TextStyle(fontFamily: 'Roboto', fontSize: 11))),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    // no keyboard-focus rings in the pictures
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  });

  Future<void> compare(WidgetTester t, Brightness b, String name, {String? tab}) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final settings = await Settings.load();
    final repo = _sampleRepo();
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(840 * 2, 800 * 2);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<Settings>.value(value: settings),
        ChangeNotifierProvider<Repo>.value(value: repo),
        ChangeNotifierProvider<LockController>.value(value: LockController(settings)),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: b == Brightness.dark ? const Color(0xFF222222) : const Color(0xFFEFEFEF),
            padding: const EdgeInsets.all(6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _phone('Before: Roboto', _oldLook(b), inter: false),
              const SizedBox(width: 12),
              _phone('After: Inter', buildTheme(b), inter: true),
            ]),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    if (tab != null) {
      for (final f in find.text(tab).evaluate().toList()) {
        await t.tap(find.byWidget(f.widget).first, warnIfMissed: false);
      }
      for (final e in find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)).evaluate().toList()) {
        await t.tap(find.byWidget(e.widget), warnIfMissed: false);
      }
      await t.pumpAndSettle();
    }
    await _save(t, key, name);
  }

  testWidgets('transactions, light', (t) => compare(t, Brightness.light, 'transactions_light'));
  testWidgets('transactions, dark', (t) => compare(t, Brightness.dark, 'transactions_dark'));
  testWidgets('reports, light', (t) => compare(t, Brightness.light, 'reports_light', tab: 'Reports'));

  testWidgets('weights specimen', (t) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(760 * 2, 520 * 2);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    Widget row(String family, FontWeight w, String name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 120, child: Text(name, style: const TextStyle(fontSize: 12, color: Colors.black54, fontFamily: 'Inter'))),
            Text('₹12,345.67  Food & Dining',
                style: TextStyle(fontFamily: family, fontWeight: w, fontSize: 22, color: Colors.black87, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in ['Roboto', 'Inter']) ...[
              Text('$f (the app now uses Inter)'.replaceAll(' (the app now uses Inter)', f == 'Inter' ? '  <- new' : '  <- before'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black, fontFamily: 'Inter')),
              row(f, FontWeight.w400, 'Regular 400'),
              row(f, FontWeight.w500, 'Medium 500'),
              row(f, FontWeight.w600, 'SemiBold 600'),
              row(f, FontWeight.w700, 'Bold 700'),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await _save(t, key, 'weights');
  });
}
