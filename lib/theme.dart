import 'package:flutter/material.dart';

/// Compact Material 3 theme used across the app.
ThemeData buildTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF2E7D6B),
      brightness: b,
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        toolbarHeight: 46,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minVerticalPadding: 2,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 58,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
      inputDecorationTheme: const InputDecorationTheme(isDense: true),
      dividerTheme: const DividerThemeData(space: 12),
    );

/// Slightly smaller text overall (on top of the user's system font size).
Widget compactText(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * 0.92)),
    child: child!,
  );
}
