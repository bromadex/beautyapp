import 'package:flutter/material.dart';

/// BeauTap design system — Direction B "Rich, modern".
/// Forest green with soft gold on a light canvas, Manrope throughout,
/// JetBrains Mono for reference codes. Text colours pass 4.5:1.
class AppColors {
  // Brand
  static const Color primary = Color(0xFF0F3B31);      // Forest
  static const Color primaryDark = Color(0xFF0B2C25);  // Forest pressed
  static const Color pine = Color(0xFF2A5A4E);         // Tiles and avatars on dark headers
  static const Color primarySoft = Color(0xFFE4EDE8);  // Mint
  static const Color gold = Color(0xFFC8A15A);         // Payment on dark, Featured, FAB, active tab bar
  static const Color goldText = Color(0xFF7A5C22);     // Gold-toned text on light
  static const Color goldLight = Color(0xFFE7D3A6);    // Text and badges on Forest
  static const Color cream = Color(0xFFF4ECDB);        // Plan banner, loyalty card, tag chips
  static const Color secondary = gold;
  static const Color accent = goldText;

  // Feedback
  static const Color success = Color(0xFF2E6B35);
  static const Color successSoft = Color(0xFFE3F0E3);
  static const Color warning = Color(0xFFC98A00);
  static const Color warningText = Color(0xFF7A4F00);
  static const Color warningSoft = Color(0xFFFBEFD3);
  static const Color error = Color(0xFFB3261E);
  static const Color errorText = Color(0xFFA8261C);
  static const Color errorSoft = Color(0xFFF8E1DE);
  static const Color info = pine;

  // Surfaces
  static const Color surfaceLight = Color(0xFFF5F6F3); // Canvas
  static const Color surfaceMuted = Color(0xFFECEEEB);
  static const Color surfaceDark = Color(0xFF14201C);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF1D2A25);

  static const Color border = Color(0xFFE1E5E1);       // Line
  static const Color borderStrong = Color(0xFFB9C2BD); // Field line

  static const Color textPrimary = Color(0xFF14201C);  // Ink
  static const Color textSecondary = Color(0xFF55625D);// Slate
  static const Color textTertiary = Color(0xFF6B7671);

  static const Color available = Color(0xFF3FB26B);
  static const Color busy = warning;
  static const Color offline = Color(0xFF9AA59F);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primary],
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [primary, primary],
  );
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
const TextStyle monoStyle = TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13, color: AppColors.textSecondary);

class AppTheme {
  static const String fontFamily = 'Manrope';

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
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: const AppBarTheme(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: field(AppColors.borderStrong),
        enabledBorder: field(AppColors.borderStrong),
        focusedBorder: field(AppColors.primary, 2),
        errorBorder: field(AppColors.error),
        focusedErrorBorder: field(AppColors.error, 2),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
        prefixIconColor: AppColors.textTertiary,
        suffixIconColor: AppColors.textTertiary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFDDE2DE),
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
          foregroundColor: AppColors.primary,
          backgroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
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
        backgroundColor: Colors.white,
        selectedColor: AppColors.primarySoft,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smAll,
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        side: const BorderSide(color: AppColors.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.white,
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

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 0),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
      ),

      tabBarTheme: const TabBarThemeData(
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
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textSecondary),
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
        linearTrackColor: Color(0xFFE6D8B8),
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
