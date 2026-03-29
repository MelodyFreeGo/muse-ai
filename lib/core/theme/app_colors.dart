import 'package:flutter/material.dart';

/// MUSE 品牌色彩系统
class AppColors {
  // ─── 主品牌色 ───────────────────────────────────────────
  /// 玫瑰金主色
  static const primary = Color(0xFFC9956C);

  /// 玫瑰金别名（用于美妆/服饰模块强调色）
  static const roseGold = Color(0xFFC9956C);

  /// 深玫瑰金
  static const primaryDark = Color(0xFFB07D55);

  /// 浅玫瑰金
  static const primaryLight = Color(0xFFE8C4A8);

  // ─── 背景色 ──────────────────────────────────────────────
  /// 主背景：米白（亮色模式）
  static const backgroundLight = Color(0xFFFAF8F5);

  /// 卡片背景：象牙白
  static const surfaceLight = Color(0xFFF5F1EC);

  /// 主背景：深夜模式
  static const backgroundDark = Color(0xFF1A1614);

  /// 卡片背景：深色
  static const surfaceDark = Color(0xFF252018);

  // ─── 文字色 ──────────────────────────────────────────────
  /// 主文字（深灰，不用纯黑）
  static const textPrimary = Color(0xFF2D2420);

  /// 次要文字
  static const textSecondary = Color(0xFF8A7A72);

  /// 提示文字
  static const textHint = Color(0xFFBBAEA6);

  /// 深色模式主文字
  static const textPrimaryDark = Color(0xFFF5EDE8);

  /// 深色模式次要文字
  static const textSecondaryDark = Color(0xFFAA9A92);

  // ─── 点缀色 ──────────────────────────────────────────────
  /// 淡金色（高亮/徽章）
  static const gold = Color(0xFFD4AF6A);

  /// 裸粉（辅助色）
  static const nude = Color(0xFFE8C4B8);

  /// 成功绿
  static const success = Color(0xFF6BAF8C);

  /// 警告橙
  static const warning = Color(0xFFE8956C);

  /// 错误红
  static const error = Color(0xFFD4706C);

  // ─── 渐变 ────────────────────────────────────────────────
  /// 主渐变（玫瑰金→裸粉）
  static const Gradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC9956C), Color(0xFFE8C4B8)],
  );

  /// 深色背景渐变
  static const Gradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1614), Color(0xFF2A1F1A)],
  );

  /// 人物背景渐变（温柔光晕）
  static const Gradient avatarBg = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0xFFE8D5C8), Color(0xFFFAF8F5)],
  );

  // ─── 玻璃态 ──────────────────────────────────────────────
  static Color glassLight = Colors.white.withOpacity(0.6);
  static Color glassDark = Colors.black.withOpacity(0.3);
  static Color glassBorder = Colors.white.withOpacity(0.25);
}
