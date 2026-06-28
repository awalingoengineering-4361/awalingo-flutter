import 'package:flutter/material.dart';

// ── Static brand colours (never change between themes) ────────────────────────
class AppColors {
  static const Color success = Color(0xFF10B981);
  static const Color error   = Color(0xFFEF4444);
  static const Color gold    = Color(0xFFEAAB0B);

  // Onboarding / auth screens stay in light mode
  static const Color background       = Color(0xFFF4F4F4);
  static const Color foreground       = Color(0xFF111111);
  static const Color mutedForeground  = Color(0xFF737373);
  static const Color border           = Color(0xFFE5E5E5);
  static const Color card             = Color(0xFFFFFFFF);
  static const Color primary          = Color(0xFF111111);
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color secondary        = Color(0xFFF5F5F5);
  static const Color foreground80     = Color(0xCC111111);
  static const Color dotInactive      = Color(0x33111111);
}

// ── Context-aware colour scheme (switches with theme) ─────────────────────────
class AppColorScheme {
  final Color background;
  final Color card;
  final Color foreground;
  final Color foreground80;
  final Color mutedForeground;
  final Color border;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color dotInactive;

  const AppColorScheme._({
    required this.background,
    required this.card,
    required this.foreground,
    required this.foreground80,
    required this.mutedForeground,
    required this.border,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.dotInactive,
  });

  static const AppColorScheme light = AppColorScheme._(
    background:       Color(0xFFF4F4F4),
    card:             Color(0xFFFFFFFF),
    foreground:       Color(0xFF111111),
    foreground80:     Color(0xCC111111),
    mutedForeground:  Color(0xFF737373),
    border:           Color(0xFFE5E5E5),
    primary:          Color(0xFF111111),
    primaryForeground: Color(0xFFFFFFFF),
    secondary:        Color(0xFFF5F5F5),
    dotInactive:      Color(0x33111111),
  );

  static const AppColorScheme dark = AppColorScheme._(
    background:       Color(0xFF0A0A0A),
    card:             Color(0xFF171717),
    foreground:       Color(0xFFFAFAFA),
    foreground80:     Color(0xCCFAFAFA),
    mutedForeground:  Color(0xFFA3A3A3),
    border:           Color(0xFF333333),
    primary:          Color(0xFFFAFAFA),
    primaryForeground: Color(0xFF0A0A0A),
    secondary:        Color(0xFF262626),
    dotInactive:      Color(0x33FAFAFA),
  );

  static AppColorScheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

// ── ThemeData ─────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColorScheme.light.background,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF111111),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFFF5F5F5),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF111111),
        outline: Color(0xFFE5E5E5),
      ),
      fontFamily: 'Metropolis',
      dividerColor: AppColorScheme.light.border,
      inputDecorationTheme: _inputTheme(AppColorScheme.light),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColorScheme.dark.background,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFAFAFA),
        onPrimary: Color(0xFF0A0A0A),
        secondary: Color(0xFF262626),
        surface: Color(0xFF171717),
        onSurface: Color(0xFFFAFAFA),
        outline: Color(0xFF333333),
      ),
      fontFamily: 'Metropolis',
      dividerColor: AppColorScheme.dark.border,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF171717),
      ),
      inputDecorationTheme: _inputTheme(AppColorScheme.dark),
    );
  }

  static InputDecorationTheme _inputTheme(AppColorScheme c) {
    return InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      hintStyle: TextStyle(color: c.mutedForeground, fontSize: 14),
      labelStyle: TextStyle(color: c.primary, fontSize: 13, fontWeight: FontWeight.w500),
    );
  }
}
