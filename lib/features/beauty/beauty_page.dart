import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/models/chat_message.dart';
import '../../core/constants/app_routes.dart';

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

enum BeautyTab { lipstick, skincare, ingredient }

class BeautyController extends GetxController {
  final activeTab = BeautyTab.lipstick.obs;
  final isLoading = false.obs;
  final cards = <ResultCard>[].obs;
  final replyText = ''.obs;
  final inputText = ''.obs;

  final _ai = AiService.to;

  // 快捷问法
  static const lipstickQueries = ['推荐显白口红', '适合我肤色的色号', '日常通勤口红', '约会约会红唇'];
  static const skincareQueries = ['我的肤质适合什么护肤品', '推荐补水保湿方案', '抗老精华推荐', '痘痘肌护肤路线'];
  static const ingredientQueries = ['分析这款产品成分', '哪些成分敏感肌要避开', '视黄醇怎么用', '烟酰胺和VC能一起用吗'];

  Future<void> ask(String question) async {
    if (isLoading.value) return;
    isLoading.value = true;
    cards.clear();
    replyText.value = '';

    final profile = StorageService.to.loadProfile();
    final result = await _ai.analyze(
      userMessage: question,
      profile: profile,
    );

    replyText.value = result.reply;
    cards.value = result.cards;
    isLoading.value = false;
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class BeautyPage extends StatelessWidget {
  const BeautyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(BeautyController());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            _buildTabs(ctrl, isDark),
            Expanded(child: _buildBody(ctrl, isDark)),
            _buildInput(ctrl, isDark),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Get.back(),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Text('美妆顾问',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary)),
          const Spacer(),
          Text('💄', style: const TextStyle(fontSize: 22)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Tab栏 ───────────────────────────────────────────────────
  Widget _buildTabs(BeautyController ctrl, bool isDark) {
    const tabs = [
      (BeautyTab.lipstick, '💄 口红彩妆'),
      (BeautyTab.skincare, '🌿 护肤方案'),
      (BeautyTab.ingredient, '🔬 成分分析'),
    ];
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Obx(() => Row(
            children: tabs.map((t) {
              final isActive = ctrl.activeTab.value == t.$1;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    ctrl.activeTab.value = t.$1;
                    ctrl.cards.clear();
                    ctrl.replyText.value = '';
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.roseGold : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? Colors.white
                            : (isDark
                                ? Colors.white60
                                : AppColors.textSecondary),
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          )),
    );
  }

  // ── 主体 ────────────────────────────────────────────────────
  Widget _buildBody(BeautyController ctrl, bool isDark) {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return _buildLoading();
      }
      if (ctrl.cards.isNotEmpty || ctrl.replyText.value.isNotEmpty) {
        return _buildResults(ctrl, isDark);
      }
      return _buildQuickEntries(ctrl, isDark);
    });
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppColors.roseGold),
            ),
          ),
          const SizedBox(height: 16),
          Text('MUSE 正在分析...', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ).animate().fadeIn(),
    );
  }

  Widget _buildQuickEntries(BeautyController ctrl, bool isDark) {
    final queries = ctrl.activeTab.value == BeautyTab.lipstick
        ? BeautyController.lipstickQueries
        : ctrl.activeTab.value == BeautyTab.skincare
            ? BeautyController.skincareQueries
            : BeautyController.ingredientQueries;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('快速咨询',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...queries.asMap().entries.map((entry) {
            final i = entry.key;
            final q = entry.value;
            return GestureDetector(
              onTap: () => ctrl.ask(q),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.roseGold.withOpacity(0.2)),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16, color: AppColors.roseGold),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(q,
                            style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary))),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ).animate().fadeIn(delay: (i * 80).ms).slideX(begin: 0.05, end: 0),
            );
          }),

          const SizedBox(height: 24),
          // 拍照入口（预留）
          _PhotoEntryCard(isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildResults(BeautyController ctrl, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ctrl.replyText.value.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.roseGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.roseGold.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💄', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ctrl.replyText.value,
                        style: TextStyle(
                            fontSize: 14, height: 1.6,
                            color: isDark ? Colors.white : AppColors.textPrimary)),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 16),
          ],
          ...ctrl.cards.asMap().entries.map((entry) {
            final i = entry.key;
            final card = entry.value;
            return _BeautyCard(card: card, isDark: isDark, index: i);
          }),
          const SizedBox(height: 12),
          // 重新提问
          GestureDetector(
            onTap: () {
              ctrl.cards.clear();
              ctrl.replyText.value = '';
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Text('重新提问',
                  style: TextStyle(
                      color: AppColors.roseGold,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 输入框 ──────────────────────────────────────────────────
  Widget _buildInput(BeautyController ctrl, bool isDark) {
    final textCtrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textCtrl,
              onChanged: (v) => ctrl.inputText.value = v,
              decoration: InputDecoration(
                hintText: '问问MUSE吧...',
                hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                // 语音按钮预留（接口占位）
                prefixIcon: GestureDetector(
                  onTap: () {
                    // TODO: 接入 speech_to_text
                    Get.snackbar('语音功能', '语音互动即将上线 🎙️',
                        snackPosition: SnackPosition.BOTTOM,
                        margin: const EdgeInsets.all(16));
                  },
                  child: Icon(Icons.mic_none_rounded,
                      color: AppColors.textSecondary, size: 20),
                ),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  ctrl.ask(v.trim());
                  textCtrl.clear();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Obx(() => GestureDetector(
                onTap: () {
                  final q = ctrl.inputText.value.trim();
                  if (q.isEmpty || ctrl.isLoading.value) return;
                  ctrl.ask(q);
                  textCtrl.clear();
                  ctrl.inputText.value = '';
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: ctrl.inputText.value.trim().isNotEmpty
                        ? AppColors.roseGold
                        : AppColors.roseGold.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
                ),
              )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _BeautyCard extends StatelessWidget {
  final ResultCard card;
  final bool isDark;
  final int index;
  const _BeautyCard(
      {required this.card, required this.isDark, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(card.title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary)),
              ),
              if (card.price != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.roseGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(card.price!,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.roseGold,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          if (card.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(card.subtitle!,
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5)),
          ],
          if (card.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: card.tags
                  .map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.roseGold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(tag,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.roseGold)),
                      ))
                  .toList(),
            ),
          ],
          // 联盟跳转按钮（预留）
          if (card.buyUrl != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: 联盟跳转 - 接入淘宝/京东联盟
                  // url_launcher: https://s.taobao.com/search?q=${card.buyUrl}
                  Get.snackbar('购买跳转', '联盟购买功能即将上线 🛒',
                      snackPosition: SnackPosition.BOTTOM,
                      margin: const EdgeInsets.all(16));
                },
                icon: Icon(Icons.shopping_bag_outlined,
                    size: 14, color: AppColors.roseGold),
                label: Text('查看购买',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.roseGold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.roseGold.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.05, end: 0);
  }
}

/// 拍照识妆入口卡片 → 跳转口红试色页
class _PhotoEntryCard extends StatelessWidget {
  final bool isDark;
  const _PhotoEntryCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.toNamed(AppRoutes.lipstick),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.roseGold.withOpacity(0.15),
              AppColors.primary.withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.roseGold.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.roseGold.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.camera_alt_outlined,
                  color: AppColors.roseGold, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('口红试色 💄',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('19色色板 · AI扫脸推荐最衬肤色色号',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.roseGold, size: 20),
          ],
        ),
      ).animate().fadeIn(delay: 320.ms).slideY(begin: 0.05, end: 0),
    );
  }
}
