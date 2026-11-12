import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Fixed brand and status colours (same in light and dark mode).
class LekkaColors {
  static const primary = Color(0xFF064E3B);
  static const primaryDark = Color(0xFF022C22); // gradient start
  static const gradientEnd = Color(0xFF07362A);
  static const primaryMid = Color(0xFF065F46);
  static const highlightOnDark = Color(0xFFFCD34D); // late interest on the summary card

  // Due soon
  static const dueSoonText = Color(0xFFB45309);
  static const dueSoonBg = Color(0xFFFFFBEB);
  static const dueSoonBorder = Color(0xFFFDE68A);

  // Overdue
  static const overdueText = Color(0xFFBE123C);
  static const overdueBg = Color(0xFFFFF1F2);
  static const overdueBorder = Color(0xFFFECDD3);
  static const overdueAvatarBg = Color(0xFFFFE4E6);
  static const overdueAvatarText = Color(0xFF9F1239);

  static const summaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, gradientEnd],
  );
}

/// Colours that change between light and dark mode.
/// Read with `LekkaPalette.of(context)`.
@immutable
class LekkaPalette extends ThemeExtension<LekkaPalette> {
  const LekkaPalette({
    required this.background,
    required this.card,
    required this.text,
    required this.muted,
    required this.line,
    required this.chip,
    required this.accent,
    required this.navActive,
    required this.tint,
    required this.tintBorder,
  });

  final Color background;
  final Color card;
  final Color text;
  final Color muted;
  final Color line;
  final Color chip;
  final Color accent; // positive text, links
  final Color navActive; // active bottom bar item
  final Color tint; // badges, avatars
  final Color tintBorder;

  static const light = LekkaPalette(
    background: Color(0xFFF7F9FA),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    line: Color(0xFFE2E8F0),
    chip: Color(0xFFF1F5F9),
    accent: Color(0xFF047857),
    navActive: LekkaColors.primary,
    tint: Color(0xFFECFDF5),
    tintBorder: Color(0xFFD1FAE5),
  );

  // Dark values come from the build prompt. Accent and tint are lifted so
  // green text stays readable on the dark card.
  static const dark = LekkaPalette(
    background: Color(0xFF0B1210),
    card: Color(0xFF14201C),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFF94A3B8),
    line: Color(0xFF25332E),
    chip: Color(0xFF1C2A25),
    accent: Color(0xFF34D399),
    navActive: Color(0xFF34D399),
    tint: Color(0xFF12332A),
    tintBorder: Color(0xFF1F4D3F),
  );

  static LekkaPalette of(BuildContext context) =>
      Theme.of(context).extension<LekkaPalette>()!;

  @override
  LekkaPalette copyWith() => this;

  @override
  LekkaPalette lerp(ThemeExtension<LekkaPalette>? other, double t) {
    if (other is! LekkaPalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// Fonts: Plus Jakarta Sans for headlines and amounts, Inter for body text.
/// Telugu and Hindi letters fall back to Noto Sans Telugu / Noto Sans Devanagari
/// at the same weight, so they render with proper shapes.
class LekkaFonts {
  static List<String> _fallback(String languageCode, FontWeight weight) {
    switch (languageCode) {
      case 'te':
        return [GoogleFonts.notoSansTelugu(fontWeight: weight).fontFamily!];
      case 'hi':
        return [GoogleFonts.notoSansDevanagari(fontWeight: weight).fontFamily!];
      default:
        // English screens can still show a Telugu/Hindi name or the language
        // picker, so keep both scripts available.
        return [
          GoogleFonts.notoSansTelugu(fontWeight: weight).fontFamily!,
          GoogleFonts.notoSansDevanagari(fontWeight: weight).fontFamily!,
        ];
    }
  }

  static TextStyle heading(String lang, double size, FontWeight weight, Color color) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color)
          .copyWith(fontFamilyFallback: _fallback(lang, weight));

  static TextStyle body(String lang, double size, FontWeight weight, Color color) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color)
          .copyWith(fontFamilyFallback: _fallback(lang, weight));
}

/// Builds the Material 3 theme for one brightness and one language.
ThemeData buildLekkaTheme(Brightness brightness, String languageCode) {
  final p = brightness == Brightness.light ? LekkaPalette.light : LekkaPalette.dark;
  final lang = languageCode;

  final textTheme = TextTheme(
    // Big amount on the summary card: 30 px, weight 800.
    displaySmall: LekkaFonts.heading(lang, 30, FontWeight.w800, p.text),
    headlineSmall: LekkaFonts.heading(lang, 22, FontWeight.w700, p.text),
    titleLarge: LekkaFonts.heading(lang, 18, FontWeight.w700, p.text),
    titleMedium: LekkaFonts.heading(lang, 16, FontWeight.w700, p.text),
    titleSmall: LekkaFonts.body(lang, 14, FontWeight.w600, p.text),
    bodyLarge: LekkaFonts.body(lang, 15, FontWeight.w400, p.text),
    bodyMedium: LekkaFonts.body(lang, 14, FontWeight.w400, p.text),
    bodySmall: LekkaFonts.body(lang, 12, FontWeight.w400, p.muted),
    labelLarge: LekkaFonts.body(lang, 14, FontWeight.w600, p.text),
    labelMedium: LekkaFonts.body(lang, 12, FontWeight.w600, p.text),
    labelSmall: LekkaFonts.body(lang, 11, FontWeight.w500, p.muted),
  );

  final scheme = ColorScheme.fromSeed(
    seedColor: LekkaColors.primary,
    brightness: brightness,
  ).copyWith(
    primary: LekkaColors.primary,
    onPrimary: Colors.white,
    secondary: p.accent,
    surface: p.card,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.line,
    surfaceContainerHighest: p.chip,
    error: LekkaColors.overdueText,
  );

  final roundedField = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: p.line),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    textTheme: textTheme,
    extensions: [p],
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: LekkaColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: p.line),
        foregroundColor: p.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(44, 44),
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      border: roundedField,
      enabledBorder: roundedField,
      focusedBorder: roundedField.copyWith(
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
      errorBorder: roundedField.copyWith(
        borderSide: const BorderSide(color: LekkaColors.overdueText),
      ),
      focusedErrorBorder: roundedField.copyWith(
        borderSide: const BorderSide(color: LekkaColors.overdueText, width: 1.5),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: p.muted),
      errorStyle: textTheme.bodySmall?.copyWith(color: LekkaColors.overdueText),
      errorMaxLines: 3, // long Telugu/Hindi messages wrap instead of being cut
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.chip,
      selectedColor: LekkaColors.primary,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelLarge,
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
      checkmarkColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.tint,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.navActive : p.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          color: selected ? p.navActive : p.muted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.muted,
      textColor: p.text,
      selectedColor: p.text,
      minVerticalPadding: 12,
    ),
  );
}
