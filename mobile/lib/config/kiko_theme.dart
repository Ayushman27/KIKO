/// KIKO Design System
/// Centralised colors, typography, and theme tokens.
library;

import 'package:flutter/material.dart';

class KikoColors {
  // Brand
  static const cyan = Color(0xFF00F0FF);
  static const cyanDim = Color(0xFF38BDF8);
  static const purple = Color(0xFF8A2BE2);
  static const purpleDark = Color(0xFF4B0082);

  // Backgrounds
  static const bg0 = Color(0xFF080C14); // page background
  static const bg1 = Color(0xFF0F172A); // cards, panels
  static const bg2 = Color(0xFF1E293B); // elevated surfaces
  static const bg3 = Color(0xFF334155); // borders, dividers

  // Text
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);

  // Status
  static const success = Color(0xFF00FF88);
  static const warning = Color(0xFFFFA500);
  static const error = Color(0xFFFF4444);
  static const info = Color(0xFF60A5FA);

  // G Mode
  static const gPurple = Color(0xFF8A2BE2);
  static const gPurpleGlow = Color(0xFFB24BF0);

  // Alpha Mode
  static const alphaCyan = Color(0xFF00F0FF);
}

class KikoTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: KikoColors.bg0,
        colorScheme: const ColorScheme.dark(
          primary: KikoColors.cyan,
          secondary: KikoColors.purple,
          surface: KikoColors.bg1,
          error: KikoColors.error,
          onPrimary: KikoColors.bg0,
          onSecondary: Colors.white,
          onSurface: KikoColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: KikoColors.bg1,
          foregroundColor: KikoColors.textPrimary,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: KikoColors.cyan,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        cardTheme: const CardThemeData(
          color: KikoColors.bg1,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(
          color: KikoColors.bg3,
          thickness: 1,
          space: 1,
        ),
        iconTheme: const IconThemeData(color: KikoColors.textSecondary),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              color: KikoColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(
              color: KikoColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: KikoColors.textPrimary, fontSize: 14),
          bodyMedium: TextStyle(color: KikoColors.textSecondary, fontSize: 13),
          bodySmall: TextStyle(color: KikoColors.textMuted, fontSize: 11),
          labelLarge: TextStyle(
              color: KikoColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: KikoColors.bg2,
          hintStyle: const TextStyle(color: KikoColors.textMuted, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KikoColors.bg3),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KikoColors.bg3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KikoColors.cyan, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: KikoColors.cyan,
            foregroundColor: KikoColors.bg0,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w700, letterSpacing: 0.5, fontSize: 13),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: KikoColors.bg2,
          labelStyle: TextStyle(color: KikoColors.textSecondary, fontSize: 12),
          side: BorderSide(color: KikoColors.bg3),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(KikoColors.bg3),
          thickness: WidgetStateProperty.all(4),
        ),
      );
}

/// Reusable decoration builders
class KikoDecor {
  static BoxDecoration card({Color? borderColor, bool glow = false}) =>
      BoxDecoration(
        color: KikoColors.bg1,
        border: Border.all(
            color: borderColor ?? KikoColors.bg3, width: glow ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: glow
            ? [
                BoxShadow(
                    color: (borderColor ?? KikoColors.cyan).withOpacity(0.15),
                    blurRadius: 12,
                    spreadRadius: 0)
              ]
            : null,
      );

  static BoxDecoration pill(Color color) => BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(20),
      );

  static BoxDecoration statusBadge(Color color) => BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(6),
      );
}

/// Status color helper
Color statusColor(String status) {
  switch (status.toUpperCase()) {
    case 'RUNNING':
    case 'ACTIVE':
      return KikoColors.cyan;
    case 'COMPLETED':
    case 'SUCCESS':
    case 'APPROVED':
      return KikoColors.success;
    case 'PENDING':
    case 'QUEUED':
    case 'WAITING_APPROVAL':
    case 'PENDING_REVIEW':
      return KikoColors.warning;
    case 'PAUSED':
      return Colors.blueGrey;
    case 'FAILED':
    case 'ERROR':
    case 'REJECTED':
    case 'CANCELLED':
      return KikoColors.error;
    default:
      return KikoColors.textMuted;
  }
}
