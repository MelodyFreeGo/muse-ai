class AppConstants {
  // ─── 应用信息 ─────────────────────────────────────────────
  static const appName = 'MUSE';
  static const appTagline = 'Your AI Personal Advisor';
  static const appVersion = '1.0.0';

  // ─── Storage Keys ────────────────────────────────────────
  // ⚠️ 新代码请使用 AppConfig.kXxx，此处仅保留旧 Key 兼容性
  static const kIsFirstLaunch = 'is_first_launch';
  static const kIsOnboardingDone = 'is_onboarding_done';
  static const kSelectedAdvisor = 'selected_advisor';
  static const kThemeMode = 'theme_mode';
  static const kUserProfile = 'user_profile';

  // ─── 动画时长 ─────────────────────────────────────────────
  static const animFast = Duration(milliseconds: 200);
  static const animNormal = Duration(milliseconds: 350);
  static const animSlow = Duration(milliseconds: 600);
  static const animAdvisorTyping = Duration(milliseconds: 50); // 打字速度

  // ─── 布局 ─────────────────────────────────────────────────
  static const avatarHeightRatio = 0.55; // 人物占屏幕高度比例
  static const bottomPanelMinHeight = 120.0;
  static const bottomPanelMaxHeight = 0.65; // 结果面板最大高度比例
}

