import 'package:flutter/material.dart';

/// Synthetic Intelligence Shell Design Tokens
/// Faithful implementation of DESIGN.md from stitch_dual_mode_animated_ai_interface.
class SynapseTokens {
  // Surface Hierarchy
  static const Color substrateVoid = Color(0xFF040608); // Absolute Void
  static const Color surfaceLowest = Color(0xFF0B0E13);
  static const Color surfaceLow = Color(0xFF191C21);
  static const Color surface = Color(0xFF101319);
  static const Color surfaceContainer = Color(0xFF1D2025);
  static const Color surfaceHigh = Color(0xFF272A30);
  static const Color surfaceHighest = Color(0xFF32353B);
  static const Color surfaceBright = Color(0xFF36393F);

  // Content / Text
  static const Color onSurface = Color(0xFFE1E2EA);
  static const Color onSurfaceVariant = Color(0xFFB9CACB);
  static const Color outline = Color(0xFF849495);
  static const Color outlineVariant = Color(0xFF3B494B);

  // Alpha Mode (Analytical & Ambient Monitoring)
  static const Color alphaPrimary = Color(0xFFDBFCFF);
  static const Color alphaPrimaryContainer = Color(0xFF00F0FF); // Electric Cyan
  static const Color alphaPrimaryFixedDim = Color(0xFF00DBE9);
  static const Color alphaSecondary = Color(0xFF4D3BFF); // Neon Indigo
  static const Color alphaOnPrimary = Color(0xFF00363A);
  static const Color alphaOnPrimaryContainer = Color(0xFF006970);
  static const Color alphaGlow = Color(0x7300F0FF); // 45% glow
  static const Color alphaBgBase = Color(0xFF080B10);

  // G Mode (Overdrive & Generative Synthesis)
  static const Color gPrimary = Color(0xFFFFDBCE);
  static const Color gPrimaryContainer = Color(0xFFFF5625); // Radiant Orange-Red
  static const Color gPrimaryFixedDim = Color(0xFFFF4500); // Pure Volcanic Orange
  static const Color gSecondary = Color(0xFFFF6E40); // Neon Coral
  static const Color gOnPrimary = Color(0xFF601400);
  static const Color gOnPrimaryContainer = Color(0xFF541100);
  static const Color gGlow = Color(0x73FF4500); // 45% glow
  static const Color gBgBase = Color(0xFF0D0502);

  // Status
  static const Color success = Color(0xFF00FF88);
  static const Color warning = Color(0xFFFFA500);
  static const Color error = Color(0xFFFF5252);

  // Helpers for current mode
  static Color primaryColor(bool isGMode) =>
      isGMode ? gPrimaryContainer : alphaPrimaryContainer;

  static Color primaryFixedDim(bool isGMode) =>
      isGMode ? gPrimaryFixedDim : alphaPrimaryFixedDim;

  static Color secondaryColor(bool isGMode) =>
      isGMode ? gSecondary : alphaSecondary;

  static Color glowColor(bool isGMode) =>
      isGMode ? gGlow : alphaGlow;

  static Color bgBaseColor(bool isGMode) =>
      isGMode ? gBgBase : alphaBgBase;

  // Glass card decoration helper
  static BoxDecoration glassCard({
    required bool isGMode,
    double borderRadius = 16.0,
    bool highlighted = false,
    Color? borderColor,
  }) {
    final accent = primaryColor(isGMode);
    return BoxDecoration(
      color: surfaceLowest.withOpacity(0.75),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? (highlighted ? accent.withOpacity(0.4) : Colors.white.withOpacity(0.08)),
        width: highlighted ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: highlighted ? accent.withOpacity(0.18) : Colors.black.withOpacity(0.4),
          blurRadius: highlighted ? 24.0 : 12.0,
          spreadRadius: highlighted ? 1.0 : 0.0,
        ),
      ],
    );
  }
}
