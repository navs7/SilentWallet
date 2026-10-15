import 'package:flutter/material.dart';

/// The app's typeface: Inter, bundled in assets/fonts (works fully offline).
const kFontFamily = 'Inter';

/// Digits of equal width, so amounts and totals line up in tidy columns.
const kTabularFigures = [FontFeature.tabularFigures()];

/// A cleaner, modern type scale: Inter with calm weights (regular body,
/// medium labels, semibold titles) and tight tracking on large text.
TextTheme _typography(TextTheme t) {
  TextStyle? s(TextStyle? x, FontWeight w, double letterSpacing) =>
      x?.copyWith(fontWeight: w, letterSpacing: letterSpacing);
  return t.copyWith(
    headlineLarge: s(t.headlineLarge, FontWeight.w600, -0.6),
    headlineMedium: s(t.headlineMedium, FontWeight.w600, -0.5),
    headlineSmall: s(t.headlineSmall, FontWeight.w600, -0.4),
    titleLarge: s(t.titleLarge, FontWeight.w600, -0.3),
    titleMedium: s(t.titleMedium, FontWeight.w600, -0.15),
    titleSmall: s(t.titleSmall, FontWeight.w600, -0.05),
    bodyLarge: s(t.bodyLarge, FontWeight.w400, -0.1),
    bodyMedium: s(t.bodyMedium, FontWeight.w400, -0.05),
    bodySmall: s(t.bodySmall, FontWeight.w400, 0),
    labelLarge: s(t.labelLarge, FontWeight.w500, -0.05),
    labelMedium: s(t.labelMedium, FontWeight.w500, 0),
    labelSmall: s(t.labelSmall, FontWeight.w500, 0.1),
  );
}

/// Compact Material 3 theme used across the app.
ThemeData buildTheme(Brightness b) {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF2E7D6B),
    brightness: b,
    fontFamily: kFontFamily,
    visualDensity: VisualDensity.compact,
    appBarTheme: const AppBarTheme(
      toolbarHeight: 46,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
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
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(isDense: true),
    dividerTheme: const DividerThemeData(space: 12),
  );
  return base.copyWith(textTheme: _typography(base.textTheme));
}

/// Slightly smaller text overall (on top of the user's system font size).
Widget compactText(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: TextScaler.linear(mq.textScaler.scale(1) * 0.92),
    ),
    child: child!,
  );
}
