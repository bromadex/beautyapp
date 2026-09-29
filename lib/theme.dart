import 'package:flutter/material.dart';

/// BeauTap design system — Direction B "Rich, modern".
/// Forest green with soft gold on a light canvas, Manrope throughout,
/// JetBrains Mono for reference codes. Text colours pass 4.5:1.
class AppColors {
  /// Set by the app from the user's Appearance choice (System / Light / Dark).
  /// Screens rebuild when it changes.
  static bool isDark = false;

  static Color _c(int light, int dark) => Color(isDark ? dark : light);

  // Brand
  static Color get primary => _c(0xFF0F3B31, 0xFF7CC7AB);     // Forest; mint on dark so it reads as text
  static Color get onPrimary => _c(0xFFFFFFFF, 0xFF0B2C25);   // Text on primary buttons
  static Color get forest => _c(0xFF0F3B31, 0xFF14392F);      // Hero panels with white text, both modes
  static Color get primaryDark => _c(0xFF0B2C25, 0xFF0B241E); // Forest pressed / inset on forest
  static const Color pine = Color(0xFF2A5A4E);                // Tiles and avatars on dark headers
  static Color get primarySoft => _c(0xFFE4EDE8, 0xFF1B2F28); // Mint
  static const Color gold = Color(0xFFC8A15A);                // Payment on dark, Featured, FAB, active tab bar
  static Color get goldText => _c(0xFF7A5C22, 0xFFE0C07F);    // Gold-toned text
  static const Color goldLight = Color(0xFFE7D3A6);           // Text and badges on Forest
  static Color get cream => _c(0xFFF4ECDB, 0xFF2A2519);       // Plan banner, loyalty card, tag chips
  static Color get secondary => gold;
  static Color get accent => goldText;

  // Feedback
  static Color get success => _c(0xFF2E6B35, 0xFF7BC47F);
  static Color get successSoft => _c(0xFFE3F0E3, 0xFF1A2D1C);
  static Color get warning => _c(0xFFC98A00, 0xFFE0A82E);
  static Color get warningText => _c(0xFF7A4F00, 0xFFF0C674);
  static Color get warningSoft => _c(0xFFFBEFD3, 0xFF32280F);
  static Color get error => _c(0xFFB3261E, 0xFFF2685E);
  static Color get errorText => _c(0xFFA8261C, 0xFFF28B82);
  static Color get errorSoft => _c(0xFFF8E1DE, 0xFF3A1D1A);
  static Color get info => _c(0xFF2A5A4E, 0xFF7CC7AB);

  // Surfaces
  static Color get surfaceLight => _c(0xFFF5F6F3, 0xFF0F1613); // Canvas
  static Color get surfaceMuted => _c(0xFFECEEEB, 0xFF1E2925);
  static Color get card => _c(0xFFFFFFFF, 0xFF18221E);         // Cards, sheets, fields
  static const Color surfaceDark = Color(0xFF14201C);
  static Color get cardLight => card;
  static const Color cardDark = Color(0xFF1D2A25);

  static Color get border => _c(0xFFE1E5E1, 0xFF2A3631);       // Line
  static Color get borderStrong => _c(0xFFB9C2BD, 0xFF405049); // Field line

  static Color get textPrimary => _c(0xFF14201C, 0xFFE7EEEA);  // Ink
  static Color get textSecondary => _c(0xFF55625D, 0xFFA8B4AE);// Slate
  static Color get textTertiary => _c(0xFF6B7671, 0xFF8C9993);

  static const Color available = Color(0xFF3FB26B);
  static Color get busy => warning;
  static const Color offline = Color(0xFF9AA59F);

  static LinearGradient get primaryGradient => LinearGradient(colors: [forest, forest]);
  static LinearGradient get heroGradient => LinearGradient(colors: [forest, forest]);
}

class AppRadius {
  static const double xs = 6;   // Pills, badges
  static const double sm = 10;  // Fields, chips, 48px buttons
  static const double md = 12;  // Cards, 52px buttons
  static const double lg = 12;
  static const double xl = 20;  // Sheet top
  static const double xxl = 28;

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
    BoxShadow(color: Color(0x1414201C), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Reference codes and transaction IDs.
TextStyle get monoStyle => TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: AppColors.textSecondary);

class AppTheme {
  static const String fontFamily = 'Manrope';

  /// The theme for the current mode (see AppColors.isDark).
  static ThemeData get light => current;

  static ThemeData get current {
    final dark = AppColors.isDark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
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
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.surfaceMuted,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    );

    final text = TextTheme(
      displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -0.72, height: 1.1, color: AppColors.textPrimary),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2, color: AppColors.textPrimary),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.24, height: 1.25, color: AppColors.textPrimary),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.3, color: AppColors.textPrimary),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.45, color: AppColors.textPrimary),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.45, color: AppColors.textPrimary),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4, color: AppColors.textSecondary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
      labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.48, color: AppColors.textSecondary),
    );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: AppColors.border),
        ),
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: AppColors.textSecondary,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, color: AppColors.textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: field(AppColors.borderStrong),
        enabledBorder: field(AppColors.borderStrong),
        focusedBorder: field(AppColors.primary, 2),
        errorBorder: field(AppColors.error),
        focusedErrorBorder: field(AppColors.error, 2),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
        floatingLabelStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 15),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.card,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          side: BorderSide(color: AppColors.primary, width: 1.5),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textPrimary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.card,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smAll,
          side: BorderSide(color: AppColors.borderStrong),
        ),
        side: BorderSide(color: AppColors.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        secondaryLabelStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
            )),
      ),

      dividerTheme: DividerThemeData(color: AppColors.border, thickness: 1, space: 0),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.surfaceLight),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.gold,
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.border,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.mdAll)),
          side: WidgetStatePropertyAll(BorderSide(color: AppColors.borderStrong)),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primarySoft : AppColors.card),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceMuted),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : AppColors.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: AppColors.borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.card),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.cream,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(backgroundColor: AppColors.error),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: AppRadius.smAll),
        textStyle: TextStyle(fontFamily: fontFamily, color: AppColors.surfaceLight, fontSize: 12),
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
