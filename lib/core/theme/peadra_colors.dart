import 'package:flutter/material.dart';

class PeadraColors {
  final String name;
  final Color bg;
  final Color surface;
  final Color text;
  final Color textSecondary;
  final Color primaryDark;
  final Color primaryMedium;
  final Color primaryLight;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color chartTooltipBg;
  final Color borderColor;
  final Color divider;
  final Color navSelectedBg;
  final Color navSelectedFg;
  final Color transferColor;
  final Color incomeBg;
  final Color expenseBg;
  final Color transferBg;
  final Color incomeIcon;
  final Color expenseIcon;
  final Color transferIcon;
  final Color deleteColor;
  final Color addColor;
  final Color placeholderColor;
  final Color chartIncome;
  final Color chartExpense;
  final Color chartAsset;
  final Color chartAssetBg;
  final Color savingsBg;
  final Color savingsIcon;
  final Color pieHoverText;
  final List<Color> chartPalette;

  const PeadraColors({
    required this.name,
    required this.bg,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.primaryDark,
    required this.primaryMedium,
    required this.primaryLight,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.chartTooltipBg,
    required this.borderColor,
    required this.divider,
    required this.navSelectedBg,
    required this.navSelectedFg,
    required this.transferColor,
    required this.incomeBg,
    required this.expenseBg,
    required this.transferBg,
    required this.incomeIcon,
    required this.expenseIcon,
    required this.transferIcon,
    required this.deleteColor,
    required this.addColor,
    required this.placeholderColor,
    required this.chartIncome,
    required this.chartExpense,
    required this.chartAsset,
    required this.chartAssetBg,
    required this.savingsBg,
    required this.savingsIcon,
    required this.pieHoverText,
    required this.chartPalette,
  });
}

class PeadraTheme {
  PeadraTheme._();

  static final Map<String, PeadraColors> themes = {
    'light': const PeadraColors(
      name: 'light',
      bg: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      text: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      primaryDark: Color(0xFF0F172A),
      primaryMedium: Color(0xFF1E293B),
      primaryLight: Color(0xFF64748B),
      accent: Color(0xFF4F46E5),
      success: Color(0xFF10B981),
      warning: Color(0xFFF59E0B),
      error: Color(0xFFEF4444),
      info: Color(0xFF3B82F6),
      chartTooltipBg: Color(0xFFFFFFFF),
      borderColor: Color(0xFFE2E8F0),
      divider: Color(0xFFF1F5F9),
      navSelectedBg: Color(0xFFE0E7FF),
      navSelectedFg: Color(0xFF4F46E5),
      transferColor: Color(0xFF2563EB),
      incomeBg: Color(0xFFD1FAE5),
      expenseBg: Color(0xFFFEE2E2),
      transferBg: Color(0xFFDBEAFE),
      incomeIcon: Color(0xFF059669),
      expenseIcon: Color(0xFFDC2626),
      transferIcon: Color(0xFF1D4ED8),
      deleteColor: Color(0xFFE11D48),
      addColor: Color(0xFF2563EB),
      placeholderColor: Color(0xFF94A3B8),
      chartIncome: Color(0xFF10B981),
      chartExpense: Color(0xFFEF4444),
      chartAsset: Color(0xFF7C3AED),
      chartAssetBg: Color(0xFFF3E8FF),
      savingsBg: Color(0xFFF3E8FF),
      savingsIcon: Color(0xFF7C3AED),
      pieHoverText: Color(0xFF0F172A),
      chartPalette: [
        Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFF59E0B),
        Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF06B6D4),
        Color(0xFFEC4899),
      ],
    ),
    'dark': const PeadraColors(
      name: 'dark',
      bg: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      text: Color(0xFFF8FAFC),
      textSecondary: Color(0xFF94A3B8),
      primaryDark: Color(0xFF0B0F19),
      primaryMedium: Color(0xFF131C2C),
      primaryLight: Color(0xFF1E293B),
      accent: Color(0xFF5F51F7),
      success: Color(0xFF10B981),
      warning: Color(0xFFF59E0B),
      error: Color(0xFFEF4444),
      info: Color(0xFF3B82F6),
      chartTooltipBg: Color(0xFF1E293B),
      borderColor: Color(0xFF334155),
      divider: Color(0xFF334155),
      navSelectedBg: Color(0xFF334155),
      navSelectedFg: Color(0xFFFFFFFF),
      transferColor: Color(0xFF60A5FA),
      incomeBg: Color(0xFF064E3B),
      expenseBg: Color(0xFF7F1D1D),
      transferBg: Color(0xFF1E3A8A),
      incomeIcon: Color(0xFF10B981),
      expenseIcon: Color(0xFFEF4444),
      transferIcon: Color(0xFF60A5FA),
      deleteColor: Color(0xFFF43F5E),
      addColor: Color(0xFF3B82F6),
      placeholderColor: Color(0xFF64748B),
      chartIncome: Color(0xFF10B981),
      chartExpense: Color(0xFFEF4444),
      chartAsset: Color(0xFF8B5CF6),
      chartAssetBg: Color(0xFF2E1065),
      savingsBg: Color(0xFF2E1065),
      savingsIcon: Color(0xFFA78BFA),
      pieHoverText: Color(0xFFFFFFFF),
      chartPalette: [
        Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFF59E0B),
        Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF06B6D4),
        Color(0xFFEC4899),
      ],
    ),
    'autumn': const PeadraColors(
      name: 'autumn',
      bg: Color(0xFF000022),
      surface: Color(0xFF12123A),
      text: Color(0xFFFBF5F3),
      textSecondary: Color(0xFFC4B5B0),
      primaryDark: Color(0xFF000015),
      primaryMedium: Color(0xFF000022),
      primaryLight: Color(0xFF1A1A5E),
      accent: Color(0xFFE28413),
      success: Color(0xFF10B981),
      warning: Color(0xFFE28413),
      error: Color(0xFFC42847),
      info: Color(0xFF4A6FA5),
      chartTooltipBg: Color(0xFF1A1A5E),
      borderColor: Color(0xFF222255),
      divider: Color(0xFF1A1A4E),
      navSelectedBg: Color(0xFF222255),
      navSelectedFg: Color(0xFFFBF5F3),
      transferColor: Color(0xFFE28413),
      incomeBg: Color(0xFF0A2E1A),
      expenseBg: Color(0xFF3A0A1A),
      transferBg: Color(0xFF0F0F3D),
      incomeIcon: Color(0xFF10B981),
      expenseIcon: Color(0xFFDE3C4B),
      transferIcon: Color(0xFFE28413),
      deleteColor: Color(0xFFC42847),
      addColor: Color(0xFFE28413),
      placeholderColor: Color(0xFF6B6B8A),
      chartIncome: Color(0xFF10B981),
      chartExpense: Color(0xFFDE3C4B),
      chartAsset: Color(0xFFE28413),
      chartAssetBg: Color(0xFF2A1A05),
      savingsBg: Color(0xFF2A1A05),
      savingsIcon: Color(0xFFE28413),
      pieHoverText: Color(0xFFFBF5F3),
      chartPalette: [
        Color(0xFFE28413), Color(0xFFDE3C4B), Color(0xFFC42847),
        Color(0xFFFBF5F3), Color(0xFF10B981), Color(0xFF4A6FA5),
        Color(0xFF8B5CF6),
      ],
    ),
    'summer': const PeadraColors(
      name: 'summer',
      bg: Color(0xFFFCFBE7),
      surface: Color(0xFFF9F9F9),
      text: Color(0xFF1A2A4A),
      textSecondary: Color(0xFF1C3D5E),
      primaryDark: Color(0xFF0A2A4A),
      primaryMedium: Color(0xFF2A6A9A),
      primaryLight: Color(0xFF5AA9E6),
      accent: Color(0xFF5AA9E6),
      success: Color(0xFF10B981),
      warning: Color(0xFFFFCA0A),
      error: Color(0xFFE74C3C),
      info: Color(0xFF5AA9E6),
      chartTooltipBg: Color(0xFFFFFFFF),
      borderColor: Color(0xFFB8D2E1),
      divider: Color(0xFFBECBD1),
      navSelectedBg: Color(0xFFD0E8FF),
      navSelectedFg: Color(0xFF1A3A5A),
      transferColor: Color(0xFF5AA9E6),
      incomeBg: Color(0xFFD1FAE5),
      expenseBg: Color(0xFFFFE0E0),
      transferBg: Color(0xFFD0ECFF),
      incomeIcon: Color(0xFF10B981),
      expenseIcon: Color(0xFFE74C3C),
      transferIcon: Color(0xFF5AA9E6),
      deleteColor: Color(0xFFE74C3C),
      addColor: Color(0xFF5AA9E6),
      placeholderColor: Color(0xFF7192A8),
      chartIncome: Color(0xFF10B981),
      chartExpense: Color(0xFFE74C3C),
      chartAsset: Color(0xFFFFCA0A),
      chartAssetBg: Color(0xFFFFF8E0),
      savingsBg: Color(0xFFFFF8E0),
      savingsIcon: Color(0xFFFFE45E),
      pieHoverText: Color(0xFF1A2A4A),
      chartPalette: [
        Color(0xFF5AA9E6), Color(0xFF7FC8F8), Color(0xFFFFE45E),
        Color(0xFFFFCA0A), Color(0xFF10B981), Color(0xFFE74C3C),
        Color(0xFF8B5CF6),
      ],
    ),
  };

  static PeadraColors getColors(String themeName) {
    return themes[themeName] ?? themes['dark']!;
  }

  static Color hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
