import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/advisor_model.dart';
import '../../core/services/storage_service.dart';
import '../../core/constants/app_routes.dart';

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

class SettingsController extends GetxController {
  // 主题
  final themeMode = ThemeMode.system.obs;

  // 助理
  final selectedAdvisor = AdvisorCharacter.xiaoTang.obs;

  // 通知开关（本地偏好，未接推送时仅UI展示）
  final notifyDailyOutfit = true.obs;  // 每日穿搭提醒
  final notifyWeeklyReport = false.obs; // 每周肤况报告

  // 声音开关
  final ttsEnabled = true.obs;

  static const _keyThemeMode = 'muse_theme_mode';
  static const _keyNotifyDaily = 'muse_notify_daily';
  static const _keyNotifyWeekly = 'muse_notify_weekly';
  static const _keyTts = 'muse_tts_enabled';

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyThemeMode) ?? 'system';
    themeMode.value = _modeFromString(mode);
    Get.changeThemeMode(themeMode.value);

    final saved = StorageService.to.loadAdvisor();
    if (saved != null) {
      try {
        selectedAdvisor.value = AdvisorCharacter.values
            .firstWhere((e) => e.name == saved);
      } catch (_) {}
    }

    notifyDailyOutfit.value = prefs.getBool(_keyNotifyDaily) ?? true;
    notifyWeeklyReport.value = prefs.getBool(_keyNotifyWeekly) ?? false;
    ttsEnabled.value = prefs.getBool(_keyTts) ?? true;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, _modeToString(mode));
  }

  Future<void> setAdvisor(AdvisorCharacter advisor) async {
    selectedAdvisor.value = advisor;
    await StorageService.to.saveAdvisor(advisor.name);
    // 同步更新 HomeController（如果在栈里）
    try {
      final hc = Get.find<dynamic>(tag: 'home');
      // ignore: avoid_dynamic_calls
      hc.selectedAdvisor.value = advisor;
    } catch (_) {}
    Get.snackbar(
      '已切换助理',
      '${advisor.name} 已就位 ✨',
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> toggleNotifyDaily(bool val) async {
    notifyDailyOutfit.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyDaily, val);
  }

  Future<void> toggleNotifyWeekly(bool val) async {
    notifyWeeklyReport.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifyWeekly, val);
  }

  Future<void> toggleTts(bool val) async {
    ttsEnabled.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTts, val);
  }

  // 清空缓存（衣橱 + 诊断历史 + 成分历史，保留用户档案）
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('muse_wardrobe_items');
    await StorageService.to.clearAnalysisHistory();
    await StorageService.to.clearIngredientHistory();
  }

  // 重置所有（清档案 + 回Onboarding）
  Future<void> resetAll() async {
    await StorageService.to.clearProfile();
    await clearCache();
    Get.offAllNamed(AppRoutes.onboarding);
  }

  ThemeMode _modeFromString(String s) {
    if (s == 'light') return ThemeMode.light;
    if (s == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  String _modeToString(ThemeMode m) {
    if (m == ThemeMode.light) return 'light';
    if (m == ThemeMode.dark) return 'dark';
    return 'system';
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(SettingsController());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF8F6F4),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  const SizedBox(height: 4),

                  // ── 外观主题 ──────────────────────────────────
                  _SectionTitle(title: '外观', isDark: isDark),
                  _ThemeSelector(ctrl: ctrl, isDark: isDark),
                  const SizedBox(height: 20),

                  // ── 我的助理 ──────────────────────────────────
                  _SectionTitle(title: '我的AI助理', isDark: isDark),
                  _AdvisorSelector(ctrl: ctrl, isDark: isDark),
                  const SizedBox(height: 20),

                  // ── 语音 ──────────────────────────────────────
                  _SectionTitle(title: '语音', isDark: isDark),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      Obx(() => _ToggleRow(
                            icon: Icons.volume_up_rounded,
                            iconColor: AppColors.primary,
                            title: 'AI语音播报',
                            subtitle: '助理回复后自动朗读',
                            value: ctrl.ttsEnabled.value,
                            onChanged: ctrl.toggleTts,
                            isDark: isDark,
                          )),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 通知 ──────────────────────────────────────
                  _SectionTitle(title: '通知', isDark: isDark),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      Obx(() => _ToggleRow(
                            icon: Icons.wb_sunny_rounded,
                            iconColor: AppColors.gold,
                            title: '每日穿搭提醒',
                            subtitle: '每天早8点推送今日穿搭灵感',
                            value: ctrl.notifyDailyOutfit.value,
                            onChanged: ctrl.toggleNotifyDaily,
                            isDark: isDark,
                          )),
                      _Divider(isDark: isDark),
                      Obx(() => _ToggleRow(
                            icon: Icons.bar_chart_rounded,
                            iconColor: AppColors.success,
                            title: '每周肤况报告',
                            subtitle: '每周日汇总护肤建议',
                            value: ctrl.notifyWeeklyReport.value,
                            onChanged: ctrl.toggleNotifyWeekly,
                            isDark: isDark,
                          )),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 数据 ──────────────────────────────────────
                  _SectionTitle(title: '数据与隐私', isDark: isDark),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _TapRow(
                        icon: Icons.delete_sweep_rounded,
                        iconColor: AppColors.roseGold,
                        title: '清空缓存',
                        subtitle: '删除衣橱记录和诊断历史，不影响档案',
                        isDark: isDark,
                        onTap: () => _showClearCacheDialog(context, ctrl, isDark),
                      ),
                      _Divider(isDark: isDark),
                      _TapRow(
                        icon: Icons.person_outline_rounded,
                        iconColor: const Color(0xFF7B68EE),
                        title: '我的档案',
                        subtitle: '查看和编辑个人风格档案',
                        isDark: isDark,
                        onTap: () => Get.toNamed(AppRoutes.profile),
                      ),
                      _Divider(isDark: isDark),
                      _TapRow(
                        icon: Icons.history_rounded,
                        iconColor: AppColors.primary,
                        title: '诊断历史',
                        subtitle: '形象诊断和成分检测记录',
                        isDark: isDark,
                        onTap: () => Get.toNamed(AppRoutes.history),
                      ),
                      _Divider(isDark: isDark),
                      _TapRow(
                        icon: Icons.shield_outlined,
                        iconColor: AppColors.textSecondary,
                        title: '隐私政策',
                        subtitle: '了解我们如何保护你的数据',
                        isDark: isDark,
                        onTap: () => _showPrivacyDialog(context, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 关于 ──────────────────────────────────────
                  _SectionTitle(title: '关于', isDark: isDark),
                  _SettingsCard(
                    isDark: isDark,
                    children: [
                      _TapRow(
                        icon: Icons.auto_awesome_rounded,
                        iconColor: AppColors.roseGold,
                        title: 'MUSE AI 私人顾问',
                        subtitle: '版本 1.0.0',
                        isDark: isDark,
                        showArrow: false,
                        onTap: () {},
                      ),
                      _Divider(isDark: isDark),
                      _TapRow(
                        icon: Icons.star_outline_rounded,
                        iconColor: AppColors.gold,
                        title: '给个好评 ⭐',
                        subtitle: '喜欢MUSE就去AppStore评分吧',
                        isDark: isDark,
                        onTap: () {
                          Get.snackbar('谢谢你 🥹', '你的支持是MUSE进步的动力！',
                              snackPosition: SnackPosition.BOTTOM,
                              margin: const EdgeInsets.all(16));
                        },
                      ),
                      _Divider(isDark: isDark),
                      _TapRow(
                        icon: Icons.refresh_rounded,
                        iconColor: AppColors.error,
                        title: '重置账号',
                        subtitle: '清除所有数据，重新开始建档',
                        isDark: isDark,
                        onTap: () => _showResetDialog(context, ctrl, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ── 版权 ──────────────────────────────────────
                  Center(
                    child: Text(
                      '🌸 MUSE — 你的AI私人风格顾问\nMade with ❤️',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary.withOpacity(0.6),
                          height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Get.back(),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Text('设置',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // 清空缓存确认弹窗
  void _showClearCacheDialog(
      BuildContext context, SettingsController ctrl, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('清空缓存',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text(
          '将清除衣橱记录、诊断历史、成分检测历史。\n\n你的个人档案（肤色/风格/尺码等）不会受影响。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await ctrl.clearCache();
              HapticFeedback.mediumImpact();
              Get.snackbar('✅ 缓存已清空', '衣橱和历史记录已清除',
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(16),
                  backgroundColor: AppColors.success,
                  colorText: Colors.white);
            },
            child: const Text('确认清空',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // 重置账号确认弹窗
  void _showResetDialog(
      BuildContext context, SettingsController ctrl, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('重置账号',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.error)),
        content: const Text(
          '⚠️ 这将清除全部数据，包括你的个人档案、衣橱记录和所有历史报告。\n\n此操作不可撤销。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await ctrl.resetAll();
            },
            child: const Text('确认重置',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, bool isDark) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('隐私政策',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const SingleChildScrollView(
          child: Text(
            'MUSE 承诺保护你的隐私：\n\n'
            '• 所有个人数据（档案、衣橱、历史报告）仅存储在你的设备本地，不上传服务器\n\n'
            '• AI对话内容通过加密传输发送给AI服务提供商，不被用于训练\n\n'
            '• 我们不收集、不出售任何个人身份信息\n\n'
            '• 你可以随时在设置中清除所有本地数据',
            style: TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('我明白了',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  主题选择器
// ══════════════════════════════════════════════════════════════

class _ThemeSelector extends StatelessWidget {
  final SettingsController ctrl;
  final bool isDark;
  const _ThemeSelector({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const modes = [
      (ThemeMode.light, '☀️', '浅色'),
      (ThemeMode.dark, '🌙', '深色'),
      (ThemeMode.system, '⚙️', '跟随系统'),
    ];

    return Obx(() => Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.07) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: modes.map((m) {
              final isSelected = ctrl.themeMode.value == m.$1;
              return Expanded(
                child: GestureDetector(
                  onTap: () => ctrl.setThemeMode(m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(m.$2,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 4),
                        Text(
                          m.$3,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? Colors.white60
                                    : AppColors.textSecondary),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ));
  }
}

// ══════════════════════════════════════════════════════════════
//  助理选择器
// ══════════════════════════════════════════════════════════════

class _AdvisorSelector extends StatelessWidget {
  final SettingsController ctrl;
  final bool isDark;
  const _AdvisorSelector({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
          children: AdvisorCharacter.values.asMap().entries.map((e) {
            final advisor = e.value;
            final isSelected = ctrl.selectedAdvisor.value == advisor;
            return GestureDetector(
              onTap: () => ctrl.setAdvisor(advisor),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: EdgeInsets.only(bottom: e.key < 3 ? 10 : 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? advisor.primaryColor.withOpacity(0.12)
                      : (isDark
                          ? Colors.white.withOpacity(0.07)
                          : Colors.white),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? advisor.primaryColor.withOpacity(0.5)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ],
                ),
                child: Row(
                  children: [
                    // 助理头像（颜色渐变圆）
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            advisor.primaryColor,
                            advisor.secondaryColor,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: advisor.primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          advisor.name.substring(0, 1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // 信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(advisor.name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textPrimary)),
                              const SizedBox(width: 8),
                              if (isSelected)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        advisor.primaryColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: Text('当前助理',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: advisor.primaryColor,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(advisor.personality,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  height: 1.4)),
                          const SizedBox(height: 4),
                          Text('"${advisor.greeting}"',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: advisor.primaryColor.withOpacity(0.8),
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded,
                          color: advisor.primaryColor, size: 22)
                    else
                      Icon(Icons.radio_button_unchecked_rounded,
                          color: AppColors.textSecondary.withOpacity(0.4),
                          size: 22),
                  ],
                ),
              ).animate().fadeIn(delay: (e.key * 60).ms),
            );
          }).toList(),
        ));
  }
}

// ══════════════════════════════════════════════════════════════
//  通用组件
// ══════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _SettingsCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.07) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
      ),
      child: Column(children: children),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;
  final bool showArrow;

  const _TapRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (showArrow)
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textSecondary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 66),
      color: isDark
          ? Colors.white.withOpacity(0.07)
          : Colors.black.withOpacity(0.06),
    );
  }
}
