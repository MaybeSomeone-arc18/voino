import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared look: warm paper, one ink, one gold accent. Headings use Instrument Serif, everything
/// else Inter (both SIL Open Font License, served by the google_fonts package at runtime).
/// Scale (px / line height): display 34/40, headline 28/34, section 16/22 semibold, body 16/25,
/// secondary 14/20, caption 12/16. Nothing below 12.
class AppColors {
  static const paper = Color(0xFFF4EEE1);
  static const ink = Color(0xFF2B2A28);
  static const gold = Color(0xFFC4903F);
  static final muted = ink.withValues(alpha: 0.68); // about 5:1 on paper
}

ThemeData buildAppTheme() {
  const ink = AppColors.ink;
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.gold).copyWith(
    primary: ink,
    onPrimary: Colors.white,
    secondary: AppColors.gold,
    surface: AppColors.paper,
    onSurface: ink,
  );
  final base = ThemeData(colorScheme: scheme, scaffoldBackgroundColor: const Color(0xFFF4F2EC), useMaterial3: true);
  final inter = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);
  TextStyle serif(double size, double height) =>
      GoogleFonts.instrumentSerif(fontSize: size, height: height / size, color: ink, fontWeight: FontWeight.w400);
  return base.copyWith(
    textTheme: inter.copyWith(
      displaySmall: serif(34, 40),
      headlineMedium: serif(28, 34),
      headlineSmall: serif(24, 30),
      titleMedium: inter.titleMedium?.copyWith(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600),
      bodyLarge: inter.bodyLarge?.copyWith(fontSize: 16, height: 25 / 16),
      bodyMedium: inter.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14),
      bodySmall: inter.bodySmall?.copyWith(fontSize: 12, height: 16 / 12, color: AppColors.muted),
      labelLarge: inter.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: inter.labelMedium?.copyWith(fontSize: 13),
      labelSmall: inter.labelSmall?.copyWith(fontSize: 12, color: AppColors.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentTextStyle: GoogleFonts.inter(fontSize: 14, height: 20 / 14, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}
