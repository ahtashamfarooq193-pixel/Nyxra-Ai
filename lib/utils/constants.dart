import 'package:flutter/material.dart';

class AppConstants {
  static const int dailyFreeImages = 3;
  // Colors
  static const Color primaryColor = Color(0xFF00D4FF);
  static const Color secondaryColor = Color(0xFF9D4EDD);
  static const Color backgroundColor = Color(0xFF0A0E27);
  static const Color surfaceColor = Color(0xFF1A1F3A);
  static const Color userMessageColor = Color(0xFF00D4FF);
  static const Color aiMessageColor = Color(0xFF1E2746);
  static const Color textColor = Color(0xFFFFFFFF);
  static const Color subtextColor = Color(0xFFB0B0B0);

  // Semantic tokens (consolidates the raw Colors.white.withOpacity(...) literals
  // scattered across screens/widgets into a small, consistent set)
  static const Color borderColor = Color(0x14FFFFFF); // Colors.white @ 8% - hairline borders/dividers
  static const Color surfaceOverlay = Color(0x0AFFFFFF); // Colors.white @ 4% - subtle fills
  static const Color mutedTextColor = Colors.white60; // secondary/subtitle text
  static const Color faintTextColor = Colors.white38; // timestamps, hints, footer text
  static const Color successColor = Color(0xFF4ADE80);
  static const Color errorColor = Colors.redAccent;
  static const Color accentGold = Color(0xFFFFD700);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, secondaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 400);
  static const Duration longAnimation = Duration(milliseconds: 600);

  // Free daily token allowance (resets at local midnight)
  static const int dailyFreeTokens = 5000;

  // Spacing
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;

  // Border Radius
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 16.0;
  static const double radiusLarge = 24.0;
}
