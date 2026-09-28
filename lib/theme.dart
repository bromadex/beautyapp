import 'package:flutter/material.dart';

/// BeauTap design system — warm, calm and friendly.
/// Mulberry brand colour, blush tints, warm off-white surfaces,
/// Plus Jakarta Sans throughout.
class AppColors {
  static const Color primary = Color(0xFF8E3B63);     // Mulberry
  static const Color primaryDark = Color(0xFF6D2A4B);
  static const Color primarySoft = Color(0xFFF7E9EF);  // Blush tint
  static const Color secondary = Color(0xFFD99A3D);    // Honey gold
  static const Color accent = Color(0xFFC2577F);       // Rose

  static const Color success = Color(0xFF2F9E6E);
  static const Color warning = Color(0xFFD98A1C);
  static const Color error = Color(0xFFD64560);
  static const Color info = Color(0xFF3C7DD9);

  static const Color surfaceLight = Color(0xFFFAF6F3); // Warm off-white
  static const Color surfaceMuted = Color(0xFFF3EDE9);
  static const Color surfaceDark = Color(0xFF1C1619);

  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF2A2226);

  static const Color border = Color(0xFFEDE4DF);
  static const Color borderStrong = Color(0xFFE0D5CF);

  static const Color textPrimary = Color(0xFF241B20);
  static const Color textSecondary = Color(0xFF6B5F66);
  static const Color textTertiary = Color(0xFF9D9197);

  static const Color available = success;
  static const Color busy = warning;
  static const Color offline = Color(0xFFB9AEB3);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF9C4570), Color(0xFF7E3257)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF8E3B63), Color(0xFF5E2442)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 32;

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

  static const EdgeInsets screenPadding = EdgeInsets.all(xl);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

class AppShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x0F3A1F2C), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> lifted = [
    BoxShadow(color: Color(0x1A3A1F2C), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

class AppTheme {
  static const String fontFamily = 'Jakarta';

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      error: AppColors.error,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.surfaceMuted,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    );

    const text = TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15, color: AppColors.textPrimary),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.2, color: AppColors.textPrimary),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.25, color: AppColors.textPrimary),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.3, color: AppColors.textPrimary),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1, color: AppColors.textPrimary),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: AppColors.textPrimary),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45, color: AppColors.textSecondary),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.4, color: AppColors.textTertiary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: AppColors.textTertiary),
    );

    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
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
          side: const BorderSide(color: AppColors.border),
        ),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        iconColor: AppColors.textSecondary,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 13, color: AppColors.textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: field(AppColors.borderStrong),
        enabledBorder: field(AppColors.borderStrong),
        focusedBorder: field(AppColors.primary, 1.6),
        errorBorder: field(AppColors.error),
        focusedErrorBorder: field(AppColors.error, 1.6),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          elevation: 0,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          side: const BorderSide(color: AppColors.borderStrong),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
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
        backgroundColor: Colors.white,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.pill,
          side: const BorderSide(color: AppColors.border),
        ),
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.primarySoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.textTertiary,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? AppColors.primary : AppColors.textTertiary,
            )),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 0),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: AppColors.primary,
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.mdAll)),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderStrong)),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primarySoft : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceMuted),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : AppColors.borderStrong),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.primarySoft,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.error),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: AppRadius.smAll),
        textStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class StatusColors {
  static Color background(String status) {
    switch (status) {
      case 'confirmed': return AppColors.info.withValues(alpha: 0.1);
      case 'en_route': return AppColors.warning.withValues(alpha: 0.1);
      case 'arrived': case 'in_progress': return AppColors.accent.withValues(alpha: 0.1);
      case 'completed': return AppColors.success.withValues(alpha: 0.1);
      case 'cancelled': return AppColors.error.withValues(alpha: 0.1);
      case 'pending': return AppColors.warning.withValues(alpha: 0.1);
      default: return Colors.grey.withValues(alpha: 0.1);
    }
  }

  static Color foreground(String status) {
    switch (status) {
      case 'confirmed': return AppColors.info;
      case 'en_route': return AppColors.warning;
      case 'arrived': case 'in_progress': return AppColors.accent;
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      case 'pending': return AppColors.warning;
      default: return Colors.grey;
    }
  }

  static String label(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'confirmed': return 'Confirmed';
      case 'en_route': return 'En Route';
      case 'arrived': return 'Arrived';
      case 'in_progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return status;
    }
  }
}
