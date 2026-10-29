import 'package:flutter/cupertino.dart' show NoDefaultCupertinoThemeData;
import 'package:flutter/material.dart';

import 'glass.dart';

/// BeauTap design system: iOS 26.
/// Apple's system colours and text sizes, Inter (closest free match to San
/// Francisco), BeauTap forest green as the tint and gold as the accent.
/// Liquid glass only where iOS uses it: bars, the tab bar, floating buttons.
class AppColors {
  /// Set by the app from the user's Appearance choice (System / Light / Dark).
  /// Screens rebuild when it changes.
  static bool isDark = false;

  static Color _c(int light, int dark) => Color(isDark ? dark : light);

  // Brand (the tint, like an iOS app's accent colour)
  static Color get primary => _c(0xFF0F3B31, 0xFF6FD1A9);     // Forest tint; mint on dark
  static Color get onPrimary => _c(0xFFFFFFFF, 0xFF00261C);   // Text on filled buttons
  static Color get forest => _c(0xFF0F3B31, 0xFF14392F);      // Brand panels with white text
  static Color get primaryDark => _c(0xFF0B2C25, 0xFF0B241E);
  static const Color pine = Color(0xFF2A5A4E);
  static Color get primarySoft => _c(0x1F0F3B31, 0x336FD1A9); // Tinted fill
  static const Color gold = Color(0xFFC8A15A);
  static Color get goldText => _c(0xFF7A5C22, 0xFFE0C07F);
  static const Color goldLight = Color(0xFFE7D3A6);
  static Color get cream => _c(0xFFF4ECDB, 0xFF2C2618);
  static Color get secondary => gold;
  static Color get accent => goldText;

  // Feedback: iOS system green, orange, red
  static Color get success => _c(0xFF248A3D, 0xFF30D158);
  static Color get successSoft => _c(0x1F34C759, 0x2E30D158);
  static Color get warning => _c(0xFFC93400, 0xFFFF9F0A);
  static Color get warningText => _c(0xFF9A4A00, 0xFFFFB340);
  static Color get warningSoft => _c(0x1FFF9500, 0x2EFF9F0A);
  static Color get error => _c(0xFFD70015, 0xFFFF453A);
  static Color get errorText => _c(0xFFC4000F, 0xFFFF6961);
  static Color get errorSoft => _c(0x1AFF3B30, 0x2EFF453A);
  static Color get info => _c(0xFF0F3B31, 0xFF6FD1A9);

  // Surfaces: systemGroupedBackground / secondarySystemGroupedBackground
  static Color get surfaceLight => _c(0xFFF2F2F7, 0xFF000000); // Page background
  static Color get surfaceMuted => _c(0x1F767680, 0x3D767680); // Fill (tertiarySystemFill)
  static Color get card => _c(0xFFFFFFFF, 0xFF1C1C1E);         // Grouped cells and cards
  static Color get cardElevated => _c(0xFFFFFFFF, 0xFF2C2C2E); // Sheets, menus
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static Color get cardLight => card;
  static const Color cardDark = Color(0xFF2C2C2E);

  static Color get border => _c(0x1F3C3C43, 0x33545458);       // Hairline separator
  static Color get borderStrong => _c(0x4A3C3C43, 0xA6545458); // Opaque separator

  // Labels
  static Color get textPrimary => _c(0xFF000000, 0xFFFFFFFF);
  static Color get textSecondary => _c(0xFF6C6C70, 0xFFAEAEB2); // secondaryLabel, readable
  static Color get textTertiary => _c(0xFF8E8E93, 0xFF8D8D93);

  static const Color available = Color(0xFF34C759);
  static Color get busy => warning;
  static const Color offline = Color(0xFF8E8E93);

  static LinearGradient get primaryGradient => const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF22604F), Color(0xFF0F3B31)]);
  static LinearGradient get heroGradient => const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF22604F), Color(0xFF0F3B31), Color(0xFF08241D)], stops: [0, 0.55, 1]);
}

class AppRadius {
  static const double xs = 8;   // Badges
  static const double sm = 12;  // Fields, small buttons
  static const double md = 16;  // Buttons, small cards
  static const double lg = 22;  // Grouped sections and cards (iOS 26 is rounder)
  static const double xl = 28;  // Big panels
  static const double xxl = 36; // Sheets

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get xxlAll => BorderRadius.circular(xxl);
  static BorderRadius get pill => BorderRadius.circular(999);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets screenPadding = EdgeInsets.all(lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

class AppShadows {
  static const List<BoxShadow> soft = [];
  static const List<BoxShadow> lifted = [
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

/// Reference codes and transaction IDs.
TextStyle get monoStyle => TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: AppColors.textSecondary);

class AppTheme {
  static const String fontFamily = 'Inter';
  static const String displayFamily = 'InterDisplay';

  /// The theme for the current mode (see AppColors.isDark).
  static ThemeData get light => current;

  static ThemeData get current {
    final dark = AppColors.isDark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F3B31),
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primary,
      secondary: AppColors.secondary,
      error: AppColors.error,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.card,
      surfaceContainerLow: AppColors.card,
      surfaceContainer: AppColors.cardElevated,
      surfaceContainerHigh: AppColors.cardElevated,
      surfaceContainerHighest: dark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    );

    // Apple's text styles (Large Title 34, Title 28/22/20, Headline 17,
    // Body 17, Subheadline 15, Footnote 13, Caption 12), slightly tightened
    // so Inter reads like San Francisco.
    TextStyle t(double size, FontWeight w, {double? ls, double? h, Color? c, bool display = false}) => TextStyle(
          fontFamily: display ? displayFamily : fontFamily,
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls ?? (size >= 20 ? -0.5 : -0.2),
          height: h,
          color: c ?? AppColors.textPrimary,
        );
    final text = TextTheme(
      displayLarge: t(40, FontWeight.w700, display: true, ls: -0.8),
      displayMedium: t(36, FontWeight.w700, display: true, ls: -0.7),
      displaySmall: t(34, FontWeight.w700, display: true, ls: -0.6, h: 1.12),
      headlineLarge: t(28, FontWeight.w700, display: true, h: 1.18),
      headlineMedium: t(22, FontWeight.w700, display: true, h: 1.22),
      headlineSmall: t(20, FontWeight.w600, display: true, h: 1.25),
      titleLarge: t(17, FontWeight.w600),
      titleMedium: t(17, FontWeight.w600),
      titleSmall: t(15, FontWeight.w600),
      bodyLarge: t(17, FontWeight.w400, h: 1.35),
      bodyMedium: t(15, FontWeight.w400, h: 1.35),
      bodySmall: t(13, FontWeight.w400, h: 1.35, ls: -0.1, c: AppColors.textSecondary),
      labelLarge: t(15, FontWeight.w600),
      labelMedium: t(13, FontWeight.w500, ls: -0.1, c: AppColors.textSecondary),
      labelSmall: t(12, FontWeight.w600, ls: 0, c: AppColors.textSecondary),
    );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: c == Colors.transparent ? BorderSide.none : BorderSide(color: c, width: w),
        );

    const capsule = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      // Behave like an iPhone everywhere: bouncing scroll, iOS switches,
      // spinners and sliders, centred titles, swipe-back, iOS text selection.
      platform: TargetPlatform.iOS,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.cardElevated,
      splashFactory: NoSplash.splashFactory,
      highlightColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
      visualDensity: VisualDensity.standard,
      cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
        primaryColor: AppColors.primary,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: GlassPageTransitions(),
        TargetPlatform.iOS: GlassPageTransitions(),
        TargetPlatform.macOS: GlassPageTransitions(),
        TargetPlatform.windows: GlassPageTransitions(),
        TargetPlatform.linux: GlassPageTransitions(),
        TargetPlatform.fuchsia: GlassPageTransitions(),
      }),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(Icons.chevron_left_rounded, size: 32),
      ),

      // iOS navigation bar: centred 17pt title, hairline when content scrolls under.
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.6,
        shadowColor: AppColors.borderStrong,
        centerTitle: true,
        backgroundColor: AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 52,
        titleSpacing: 16,
        titleTextStyle: t(17, FontWeight.w600, ls: -0.3),
        iconTheme: IconThemeData(color: AppColors.primary, size: 24),
        actionsIconTheme: IconThemeData(color: AppColors.primary, size: 24),
      ),

      // Grouped cells: no borders, rounded, on the grey page.
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
        iconColor: AppColors.primary,
        titleTextStyle: t(17, FontWeight.w400),
        subtitleTextStyle: t(15, FontWeight.w400, c: AppColors.textSecondary),
      ),

      // iOS fields: soft grey fill, no outline until focused.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: field(Colors.transparent),
        enabledBorder: field(Colors.transparent),
        focusedBorder: field(AppColors.primary, 1.6),
        errorBorder: field(AppColors.error),
        focusedErrorBorder: field(AppColors.error, 1.6),
        labelStyle: t(16, FontWeight.w400, c: AppColors.textSecondary),
        floatingLabelStyle: t(14, FontWeight.w600, c: AppColors.primary),
        hintStyle: t(16, FontWeight.w400, c: AppColors.textTertiary),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
      ),

      // iOS 26 buttons: capsules. Filled = prominent, outlined = tinted grey.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
          shape: capsule,
          textStyle: t(17, FontWeight.w600, ls: -0.3),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
          shape: capsule,
          elevation: 0,
          textStyle: t(17, FontWeight.w600, ls: -0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.surfaceMuted,
          minimumSize: const Size(64, 46),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          shape: capsule,
          side: BorderSide.none,
          textStyle: t(16, FontWeight.w600, ls: -0.3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: capsule,
          textStyle: t(17, FontWeight.w400, ls: -0.3),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.primary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.onPrimary,
        shape: const StadiumBorder(side: BorderSide.none),
        side: BorderSide.none,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        // Selected chips are filled with the tint, so their label flips to onPrimary.
        labelStyle: WidgetStateTextStyle.resolveWith((s) => s.contains(WidgetState.selected)
            ? t(15, FontWeight.w600, c: AppColors.onPrimary)
            : t(15, FontWeight.w500, c: AppColors.textPrimary)),
        secondaryLabelStyle: t(15, FontWeight.w600, c: AppColors.onPrimary),
      ),

      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 0.5, space: 0),

      // iOS sheets: big rounded top, grabber.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Glass.modal,
        modalBackgroundColor: Glass.modal,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
        showDragHandle: true,
        dragHandleColor: AppColors.textTertiary.withValues(alpha: 0.5),
        dragHandleSize: const Size(38, 5),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: Glass.modal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        textStyle: t(17, FontWeight.w400),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Glass.modal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Glass.modal,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      ),

      // iOS 26 alerts: very round, centred.
      dialogTheme: DialogThemeData(
        backgroundColor: Glass.modal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        titleTextStyle: t(17, FontWeight.w600, ls: -0.3),
        contentTextStyle: t(15, FontWeight.w400, h: 1.4, c: AppColors.textSecondary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
        contentTextStyle: t(15, FontWeight.w500, c: Colors.white),
        shape: const StadiumBorder(),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        shape: const StadiumBorder(),
        elevation: 4,
        highlightElevation: 6,
        extendedTextStyle: t(17, FontWeight.w600, ls: -0.3),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicator: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(999),
            boxShadow: dark ? null : const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))]),
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: t(14, FontWeight.w600),
        unselectedLabelStyle: t(14, FontWeight.w500),
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),

      // Looks like iOS's segmented control: grey track, white selected pill.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? (dark ? const Color(0xFF636366) : Colors.white) : AppColors.surfaceMuted),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.textPrimary : AppColors.textSecondary),
          iconColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.textPrimary : AppColors.textSecondary),
          textStyle: WidgetStatePropertyAll(t(14, FontWeight.w600)),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? AppColors.success
            : (dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA))),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: AppColors.borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: Colors.white,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: Color(0xFFFF3B30)),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: dark ? const Color(0xFF3A3A3C) : const Color(0xFF1C1C1E), borderRadius: AppRadius.smAll),
        textStyle: t(13, FontWeight.w500, c: Colors.white),
      ),
    );
  }
}

class StatusColors {
  static Color background(String status) {
    switch (status) {
      case 'confirmed': case 'en_route': case 'arrived': case 'in_progress': return AppColors.primarySoft;
      case 'completed': return AppColors.successSoft;
      case 'cancelled': case 'no_show': return AppColors.errorSoft;
      case 'pending': case 'awaiting_deposit': return AppColors.warningSoft;
      default: return AppColors.surfaceMuted;
    }
  }

  static Color foreground(String status) {
    switch (status) {
      case 'confirmed': case 'en_route': case 'arrived': case 'in_progress': return AppColors.primary;
      case 'completed': return AppColors.success;
      case 'cancelled': case 'no_show': return AppColors.errorText;
      case 'pending': case 'awaiting_deposit': return AppColors.warningText;
      default: return AppColors.textSecondary;
    }
  }

  /// Left strip on booking cards.
  static Color strip(String status) {
    switch (status) {
      case 'completed': return AppColors.success;
      case 'cancelled': case 'no_show': return AppColors.error;
      case 'pending': case 'awaiting_deposit': return AppColors.warning;
      default: return AppColors.primary;
    }
  }

  static String label(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'confirmed': return 'Confirmed';
      case 'en_route': return 'On the way';
      case 'arrived': return 'Arrived';
      case 'in_progress': return 'In progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'no_show': return 'No-show';
      default: return status;
    }
  }
}
