// TimePass design tokens — "Quiet Interface" (Monogram-style).
//
// The chrome stays out of the way: white surfaces, one accent (near-black),
// soft gray tiles with large radii and no borders, semibold sentence-case
// section headers, gray secondary text. All color and delight comes from the
// CONTENT — data, semantic colors (AQI bands, cricket balls, alerts) and
// soft-3D imagery — never from the UI chrome. (Design evidence and the
// Monogram teardown live in DESIGN_RESEARCH.md; rules in DESIGN.md.)
//
// Type is the system stack (Roboto + Noto Indic fallbacks): native feel,
// guaranteed hi/te legibility, zero asset weight. Indic rules still apply:
// fixed line-heights, weight ceiling w700, hierarchy via size/color.

import 'package:flutter/material.dart';

// ── color tokens ────────────────────────────────────────────────────────────

/// Semantic colors, themed light/dark via [ThemeExtension].
@immutable
class TpTokens extends ThemeExtension<TpTokens> {
  const TpTokens({
    required this.bg,
    required this.card,
    required this.tile,
    required this.bubble,
    required this.ink,
    required this.inkMuted,
    required this.action,
    required this.onAction,
    required this.link,
    required this.signalGreen,
    required this.signalRed,
    required this.warnAmber,
    required this.shadow,
  });

  /// Page background.
  final Color bg;

  /// Floating answer card (soft shadow, no border).
  final Color card;

  /// Inset gray tile: ingredient-style cells, ball dots, notices.
  final Color tile;

  /// The user's query bubble.
  final Color bubble;

  final Color ink;
  final Color inkMuted;

  /// The single chrome accent: buttons, mic, checkboxes. Black by day,
  /// white by night — never a hue.
  final Color action;
  final Color onAction;

  /// Sources and taps that leave the app.
  final Color link;

  /// Content semantics only — never chrome.
  final Color signalGreen;
  final Color signalRed;
  final Color warnAmber;

  final Color shadow;

  static const light = TpTokens(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    tile: Color(0xFFF4F4F2),
    bubble: Color(0xFFF1F1EF),
    ink: Color(0xFF17171A),
    inkMuted: Color(0xFF88888E),
    action: Color(0xFF141416),
    onAction: Color(0xFFFFFFFF),
    link: Color(0xFF3B6FD4),
    signalGreen: Color(0xFF2E9E44),
    signalRed: Color(0xFFE0453A),
    warnAmber: Color(0xFFE8A13D),
    shadow: Color(0x14000000),
  );

  static const dark = TpTokens(
    bg: Color(0xFF0F0F10),
    card: Color(0xFF1B1B1D),
    tile: Color(0xFF29292C),
    bubble: Color(0xFF29292C),
    ink: Color(0xFFF4F4F5),
    inkMuted: Color(0xFF9A9AA1),
    action: Color(0xFFF4F4F5),
    onAction: Color(0xFF141416),
    link: Color(0xFF8FB0F2),
    signalGreen: Color(0xFF57C46E),
    signalRed: Color(0xFFF0655B),
    warnAmber: Color(0xFFF0B45E),
    shadow: Color(0x33000000),
  );

  @override
  TpTokens copyWith() => this;

  @override
  TpTokens lerp(TpTokens? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension TpContext on BuildContext {
  /// Falls back by brightness so catalog components render correctly even
  /// inside a host theme without the extension (e.g. renderer tests).
  TpTokens get tp =>
      Theme.of(this).extension<TpTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? TpTokens.dark
          : TpTokens.light);
}

// ── motion tokens ───────────────────────────────────────────────────────────
// Feedback, not decoration (NN/g): 100–500ms, entrances longer than exits.

abstract final class TpMotion {
  static const enter = Duration(milliseconds: 280);
  static const exit = Duration(milliseconds: 180);
  static const fast = Duration(milliseconds: 150);
  static const stagger = Duration(milliseconds: 50);
  static const pulse = Duration(milliseconds: 1400);
  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeIn;
}

// ── type tokens ─────────────────────────────────────────────────────────────
// System stack everywhere. Fixed line-heights hold across scripts
// (auto line-height varies per script); hierarchy via size + color.

/// Display style for large data (scores, temperatures, AQI) and headers.
TextStyle display(
  double size, {
  FontWeight weight = FontWeight.w600,
  double height = 1.25,
  Color? color,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      color: color,
      letterSpacing: size >= 24 ? -0.5 : -0.2,
    );

/// Section header: semibold, sentence case ("What you need").
TextStyle sectionHeader(BuildContext context) =>
    display(16, weight: FontWeight.w600, height: 1.3, color: context.tp.ink);

/// Small gray caption under tiles and data.
TextStyle caption(BuildContext context) => TextStyle(
      fontSize: 12.5,
      height: 1.35,
      color: context.tp.inkMuted,
    );

// ── theme ───────────────────────────────────────────────────────────────────

ThemeData tpTheme(Brightness brightness) {
  final t = brightness == Brightness.light ? TpTokens.light : TpTokens.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: t.ink,
    brightness: brightness,
  ).copyWith(
    primary: t.action,
    surface: t.bg,
    error: t.signalRed,
  );

  const bodyHeight = 1.5;
  final textTheme = ThemeData(brightness: brightness).textTheme.copyWith(
        displayMedium: display(40, weight: FontWeight.w700, height: 1.1, color: t.ink),
        displaySmall: display(32, weight: FontWeight.w700, height: 1.15, color: t.ink),
        headlineSmall: display(24, weight: FontWeight.w700, height: 1.2, color: t.ink),
        titleMedium: display(16.5, height: 1.3, color: t.ink),
        titleSmall: display(14, height: 1.3, color: t.ink),
        bodyLarge: TextStyle(fontSize: 16, height: bodyHeight, color: t.ink),
        bodyMedium: TextStyle(fontSize: 14.5, height: bodyHeight, color: t.ink),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: t.inkMuted),
        labelSmall: TextStyle(
            fontSize: 11.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: t.inkMuted),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    textTheme: textTheme,
    extensions: [t],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 0, // shadow is applied by TpCard for full control
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.card,
      side: BorderSide.none,
      elevation: 0,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w500, color: t.ink),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    dividerTheme: DividerThemeData(color: t.tile, thickness: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.action : null,
      ),
      checkColor: WidgetStatePropertyAll(t.onAction),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: t.inkMuted.withValues(alpha: 0.5), width: 1.5),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.ink,
      linearTrackColor: t.tile,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.action,
        foregroundColor: t.onAction,
        shape: const StadiumBorder(),
      ),
    ),
  );
}
