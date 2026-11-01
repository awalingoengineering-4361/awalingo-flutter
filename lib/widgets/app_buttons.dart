import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared button styles so action buttons look the same everywhere. Based on
/// the Curator-in-waiting modal (curate_guard_modal.dart), which matches the
/// web: pill shape, 14px vertical padding, Metropolis semibold 14,
/// foreground-on-background primary and a bordered secondary.
class AppButtonStyles {
  AppButtonStyles._();

  static const _padding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  static const _textStyle = TextStyle(
    fontFamily: 'Metropolis',
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  /// Main action: dark pill in light mode, light pill in dark mode.
  static ButtonStyle primary(AppColorScheme c) => _filled(
        c,
        background: c.foreground,
        foreground: c.background,
      );

  /// Destructive action, e.g. ending a quiz or test early.
  static ButtonStyle destructive(AppColorScheme c) => _filled(
        c,
        background: const Color(0xFFE11D48),
        foreground: Colors.white,
      );

  /// Secondary action next to a primary one: outlined pill.
  static ButtonStyle secondary(AppColorScheme c) => OutlinedButton.styleFrom(
        foregroundColor: c.foreground,
        disabledForegroundColor: c.mutedForeground,
        side: BorderSide(color: c.border),
        shape: const StadiumBorder(),
        padding: _padding,
        textStyle: _textStyle,
      );

  static ButtonStyle _filled(
    AppColorScheme c, {
    required Color background,
    required Color foreground,
  }) =>
      ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: c.secondary,
        disabledForegroundColor: c.mutedForeground,
        shape: const StadiumBorder(),
        padding: _padding,
        elevation: 0,
        textStyle: _textStyle,
      );
}
