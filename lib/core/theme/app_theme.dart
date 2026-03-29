import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // ─── 亮色主题 ────────────────────────────────────────────
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.nude,
        surface: AppColors.surfaceLight,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2),
        displayMedium: GoogleFonts.plusJakartaSans(
            fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3),
        displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3),
        headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
        titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
        titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary, height: 1.5),
        bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.6),
        bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.6),
        bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5),
        labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4),
        labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.4),
        labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textHint,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundLight,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      extensions: [AppThemeExtension.light],
    );
  }

  // ─── 深色主题 ────────────────────────────────────────────
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryLight,
        onPrimary: AppColors.textPrimary,
        secondary: AppColors.nude,
        surface: AppColors.surfaceDark,
        onSurface: AppColors.textPrimaryDark,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimaryDark, height: 1.2),
        displayMedium: GoogleFonts.plusJakartaSans(
            fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark, height: 1.3),
        displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark, height: 1.3),
        headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark, height: 1.4),
        titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark, height: 1.4),
        titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimaryDark, height: 1.5),
        bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.textPrimaryDark, height: 1.6),
        bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondaryDark, height: 1.6),
        bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondaryDark, height: 1.5),
        labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimaryDark, height: 1.4),
        labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondaryDark, height: 1.4),
        labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondaryDark, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textSecondaryDark,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundDark,
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.textSecondaryDark,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      extensions: [AppThemeExtension.dark],
    );
  }
}

/// 自定义主题扩展（放一些Material不覆盖的自定义属性）
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color cardBorder;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Gradient avatarBackground;

  const AppThemeExtension({
    required this.cardBorder,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.avatarBackground,
  });

  static const light = AppThemeExtension(
    cardBorder: Color(0xFFEDE5DC),
    shimmerBase: Color(0xFFEDE5DC),
    shimmerHighlight: Color(0xFFFAF8F5),
    avatarBackground: RadialGradient(
      colors: [Color(0xFFE8D5C8), Color(0xFFFAF8F5)],
    ),
  );

  static const dark = AppThemeExtension(
    cardBorder: Color(0xFF3A2E28),
    shimmerBase: Color(0xFF2A2018),
    shimmerHighlight: Color(0xFF3A2E28),
    avatarBackground: RadialGradient(
      colors: [Color(0xFF3A2518), Color(0xFF1A1614)],
    ),
  );

  @override
  AppThemeExtension copyWith({
    Color? cardBorder,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Gradient? avatarBackground,
  }) =>
      AppThemeExtension(
        cardBorder: cardBorder ?? this.cardBorder,
        shimmerBase: shimmerBase ?? this.shimmerBase,
        shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
        avatarBackground: avatarBackground ?? this.avatarBackground,
      );

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
      avatarBackground: avatarBackground,
    );
  }
}
