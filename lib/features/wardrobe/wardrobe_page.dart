import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/models/chat_message.dart';

// ══════════════════════════════════════════════════════════════
//  衣橱条目模型
// ══════════════════════════════════════════════════════════════

enum ClothingCategory {
  top('上装', '👕'),
  bottom('下装', '👖'),
  dress('连衣裙', '👗'),
  outer('外套', '🧥'),
  shoes('鞋子', '👟'),
  bag('包包', '👜'),
  accessory('配饰', '💍');

  final String label;
  final String emoji;
  const ClothingCategory(this.label, this.emoji);
}

class ClothingItem {
  final String id;
  final String name;
  final ClothingCategory category;
  final String? color;
  final String? notes;
  final String? imagePath;      // native 平台：本地文件路径
  final Uint8List? imageBytes;  // Web 平台：base64 持久化
  final DateTime addedAt;

  ClothingItem({
    required this.id,
    required this.name,
    required this.category,
    this.color,
    this.notes,
    this.imagePath,
    this.imageBytes,
    required this.addedAt,
  });

  bool get hasImage => imagePath != null || imageBytes != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'color': color,
        'notes': notes,
        'imagePath': imagePath,
        // Web 端：把 bytes 用 base64 存到 prefs
        'imageBytes': imageBytes != null ? base64Encode(imageBytes!) : null,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ClothingItem.fromJson(Map<String, dynamic> j) {
    Uint8List? bytes;
    if (j['imageBytes'] != null) {
      try {
        bytes = base64Decode(j['imageBytes'] as String);
      } catch (_) {}
    }
    return ClothingItem(
      id: j['id'] as String,
      name: j['name'] as String,
      category: ClothingCategory.values
          .firstWhere((e) => e.name == j['category'],
              orElse: () => ClothingCategory.top),
      color: j['color'] as String?,
      notes: j['notes'] as String?,
      imagePath: j['imagePath'] as String?,
      imageBytes: bytes,
      addedAt: DateTime.parse(j['addedAt'] as String),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

enum WardrobeTab { wardrobe, outfit, today }

class WardrobeController extends GetxController {
  static const _keyItems = 'muse_wardrobe_items';

  final activeTab = WardrobeTab.wardrobe.obs;
  final items = <ClothingItem>[].obs;
  final filterCategory = Rx<ClothingCategory?>(null);

  // 穿搭建议
  final isLoading = false.obs;
  final aiReply = ''.obs;
  final aiCards = <ResultCard>[].obs;
  final inputText = ''.obs;

  // 今日穿搭
  final todayLoading = false.obs;
  final todayOutfitItems = <_OutfitPiece>[].obs; // AI推荐的单品列表（从衣橱挑出）
  final todayAdvice = ''.obs;      // AI搭配点评
  final todayScenario = '日常'.obs; // 当前场景
  final todayGenerated = false.obs;

  final _ai = AiService.to;

  static const outfitQueries = [
    '帮我搭配今天的穿搭', '约会穿什么好看', '通勤上班装扮', '周末休闲穿搭'
  ];

  static const scenarios = [
    ('日常', '☀️'), ('通勤', '💼'), ('约会', '💕'),
    ('派对', '🎉'), ('运动', '🏃'), ('出行', '✈️'),
  ];

  @override
  void onInit() {
    super.onInit();
    _loadItems();
  }

  // ─── 持久化 ────────────────────────────────────────────────

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyItems);
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List;
      items.value = list
          .map((e) => ClothingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyItems, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  void addItem(ClothingItem item) {
    items.insert(0, item);
    _saveItems();
  }

  void removeItem(String id) {
    items.removeWhere((e) => e.id == id);
    _saveItems();
  }

  List<ClothingItem> get filteredItems {
    if (filterCategory.value == null) return items;
    return items.where((e) => e.category == filterCategory.value).toList();
  }

  // ─── 穿搭建议 ────────────────────────────────────────────────

  Future<void> askOutfit(String question) async {
    if (isLoading.value) return;
    isLoading.value = true;
    aiCards.clear();
    aiReply.value = '';

    final wardrobeSummary = _buildWardrobeSummary();
    final fullQuestion = wardrobeSummary.isEmpty
        ? question
        : '$question\n\n【我的衣橱现有】\n$wardrobeSummary';

    final profile = StorageService.to.loadProfile();
    final result = await _ai.analyze(userMessage: fullQuestion, profile: profile);

    aiReply.value = result.reply;
    aiCards.value = result.cards;
    isLoading.value = false;
  }

  // ─── 今日穿搭：从衣橱挑单品 ─────────────────────────────────

  Future<void> generateTodayOutfit() async {
    if (todayLoading.value) return;
    todayLoading.value = true;
    todayOutfitItems.clear();
    todayAdvice.value = '';

    final profile = StorageService.to.loadProfile();
    final wardrobeSummary = _buildWardrobeSummaryDetailed();

    final scenario = todayScenario.value;
    final question = wardrobeSummary.isEmpty
        ? '帮我为今天的「$scenario」场合搭配一套完整穿搭，给出具体单品推荐和搭配理由'
        : '根据我衣橱里的单品，帮我为「$scenario」场合搭配今日穿搭，从衣橱里挑选合适的单品组合，给出完整搭配方案和理由。\n\n【我的衣橱】\n$wardrobeSummary';

    final result = await _ai.analyze(userMessage: question, profile: profile);

    todayAdvice.value = result.reply;

    // 从衣橱匹配 AI 回复中提到的单品
    if (items.isNotEmpty) {
      final mentioned = _matchMentionedItems(result.reply);
      if (mentioned.isNotEmpty) {
        todayOutfitItems.value = mentioned;
      } else {
        // fallback：按场景挑一套典型单品
        todayOutfitItems.value = _pickDefaultOutfit(scenario);
      }
    }

    todayGenerated.value = true;
    todayLoading.value = false;
  }

  /// 从 AI 回复中找衣橱里被提到的单品
  List<_OutfitPiece> _matchMentionedItems(String reply) {
    final result = <_OutfitPiece>[];
    final used = <String>{};

    for (final item in items) {
      if (used.contains(item.id)) continue;
      // 名称或颜色被提到
      if (reply.contains(item.name) ||
          (item.color != null && reply.contains(item.color!))) {
        result.add(_OutfitPiece(item: item, reason: '来自你的衣橱'));
        used.add(item.id);
        if (result.length >= 4) break;
      }
    }
    return result;
  }

  /// 按场景类型默认挑一套（上装+下装/连衣裙+外套）
  List<_OutfitPiece> _pickDefaultOutfit(String scenario) {
    final result = <_OutfitPiece>[];
    final byCategory = <ClothingCategory, List<ClothingItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(item.category, () => []).add(item);
    }

    // 优先连衣裙
    final dresses = byCategory[ClothingCategory.dress] ?? [];
    if (dresses.isNotEmpty) {
      result.add(_OutfitPiece(item: dresses.first, reason: '主体单品'));
    } else {
      // 没连衣裙：上衣 + 下装
      final tops = byCategory[ClothingCategory.top] ?? [];
      final bottoms = byCategory[ClothingCategory.bottom] ?? [];
      if (tops.isNotEmpty) result.add(_OutfitPiece(item: tops.first, reason: '上装'));
      if (bottoms.isNotEmpty) result.add(_OutfitPiece(item: bottoms.first, reason: '下装'));
    }

    // 外套（寒冷天气/派对）
    if (['出行', '派对'].contains(scenario)) {
      final outers = byCategory[ClothingCategory.outer] ?? [];
      if (outers.isNotEmpty) result.add(_OutfitPiece(item: outers.first, reason: '外搭'));
    }

    // 鞋子
    final shoes = byCategory[ClothingCategory.shoes] ?? [];
    if (shoes.isNotEmpty) result.add(_OutfitPiece(item: shoes.first, reason: '鞋子'));

    return result;
  }

  String _buildWardrobeSummary() {
    if (items.isEmpty) return '';
    final map = <String, List<String>>{};
    for (final item in items) {
      map.putIfAbsent(item.category.label, () => []).add(item.name);
    }
    return map.entries
        .map((e) => '${e.key}：${e.value.take(5).join('、')}')
        .join('\n');
  }

  String _buildWardrobeSummaryDetailed() {
    if (items.isEmpty) return '';
    final map = <String, List<String>>{};
    for (final item in items) {
      final desc = item.color != null ? '${item.name}(${item.color})' : item.name;
      map.putIfAbsent(item.category.label, () => []).add(desc);
    }
    return map.entries
        .map((e) => '${e.key}：${e.value.join('、')}')
        .join('\n');
  }
}

// 今日穿搭单品数据
class _OutfitPiece {
  final ClothingItem item;
  final String reason;
  const _OutfitPiece({required this.item, required this.reason});
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class WardrobePage extends StatelessWidget {
  const WardrobePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(WardrobeController());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ctrl, isDark),
            _buildTabs(ctrl, isDark),
            Expanded(child: _buildBody(ctrl, isDark)),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context, WardrobeController ctrl, bool isDark) {
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
          Text('我的衣橱',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary)),
          const Spacer(),
          Obx(() => ctrl.activeTab.value == WardrobeTab.wardrobe
              ? GestureDetector(
                  onTap: () => _showAddItemSheet(context, ctrl, isDark),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        const Text('添加',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink()),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Tabs ────────────────────────────────────────────────────
  Widget _buildTabs(WardrobeController ctrl, bool isDark) {
    const tabs = [
      (WardrobeTab.wardrobe, '👗 衣橱'),
      (WardrobeTab.outfit, '✨ 穿搭建议'),
      (WardrobeTab.today, '📅 今日穿搭'),
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
                  onTap: () => ctrl.activeTab.value = t.$1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? Colors.white
                            : (isDark ? Colors.white60 : AppColors.textSecondary),
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
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
  Widget _buildBody(WardrobeController ctrl, bool isDark) {
    return Obx(() {
      switch (ctrl.activeTab.value) {
        case WardrobeTab.wardrobe:
          return _buildWardrobeTab(ctrl, isDark);
        case WardrobeTab.outfit:
          return _buildOutfitTab(ctrl, isDark);
        case WardrobeTab.today:
          return _buildTodayTab(ctrl, isDark);
      }
    });
  }

  // ── 衣橱 Tab ────────────────────────────────────────────────
  Widget _buildWardrobeTab(WardrobeController ctrl, bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 12),
        // 分类筛选
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _CategoryChip(
                label: '全部',
                isSelected: ctrl.filterCategory.value == null,
                onTap: () => ctrl.filterCategory.value = null,
                isDark: isDark,
              ),
              ...ClothingCategory.values.map((cat) => _CategoryChip(
                    label: '${cat.emoji} ${cat.label}',
                    isSelected: ctrl.filterCategory.value == cat,
                    onTap: () => ctrl.filterCategory.value =
                        ctrl.filterCategory.value == cat ? null : cat,
                    isDark: isDark,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Obx(() {
            final filtered = ctrl.filteredItems;
            if (filtered.isEmpty) {
              return _buildEmptyWardrobe(isDark);
            }
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, i) => _ClothingCard(
                item: filtered[i],
                isDark: isDark,
                onDelete: () => ctrl.removeItem(filtered[i].id),
                index: i,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildEmptyWardrobe(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('👗', style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text('衣橱还是空的',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('添加你的衣物，AI帮你搭配 ✨',
              style:
                  TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // ── 穿搭建议 Tab ─────────────────────────────────────────────
  Widget _buildOutfitTab(WardrobeController ctrl, bool isDark) {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            if (ctrl.isLoading.value) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44, height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('MUSE 正在搭配...', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ).animate().fadeIn(),
              );
            }
            if (ctrl.aiCards.isNotEmpty || ctrl.aiReply.value.isNotEmpty) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ctrl.aiReply.value.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('✨', style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(ctrl.aiReply.value,
                                  style: TextStyle(
                                      fontSize: 14, height: 1.6,
                                      color: isDark ? Colors.white : AppColors.textPrimary)),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),
                      const SizedBox(height: 16),
                    ],
                    ...ctrl.aiCards.asMap().entries.map((e) =>
                        _OutfitResultCard(card: e.value, isDark: isDark, index: e.key)),
                    GestureDetector(
                      onTap: () {
                        ctrl.aiCards.clear();
                        ctrl.aiReply.value = '';
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        child: Text('重新搭配',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              );
            }
            // 快捷入口
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text('快速搭配',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  ...WardrobeController.outfitQueries.asMap().entries.map((e) {
                    return GestureDetector(
                      onTap: () => ctrl.askOutfit(e.value),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
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
                            Icon(Icons.style_outlined,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(e.value,
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.textPrimary))),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: AppColors.textSecondary),
                          ],
                        ),
                      ).animate().fadeIn(delay: (e.key * 80).ms).slideX(begin: 0.05, end: 0),
                    );
                  }),
                ],
              ),
            );
          }),
        ),
        // 输入框
        _OutfitInput(ctrl: ctrl, isDark: isDark),
      ],
    );
  }

  // ── 今日穿搭 Tab ─────────────────────────────────────────────
  Widget _buildTodayTab(WardrobeController ctrl, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Obx(() {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),

            // ── 场景选择 ──────────────────────────────────────
            Text('今天去哪',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textPrimary)),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: WardrobeController.scenarios.map((s) {
                  final isSelected = ctrl.todayScenario.value == s.$1;
                  return GestureDetector(
                    onTap: () {
                      ctrl.todayScenario.value = s.$1;
                      ctrl.todayGenerated.value = false; // 重置
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.black.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.$2,
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          Text(s.$1,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : AppColors.textSecondary),
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── 衣橱状态提示 ─────────────────────────────────
            if (ctrl.items.isEmpty) ...[
              _buildEmptyWardrobeHint(isDark),
              const SizedBox(height: 16),
            ],

            // ── AI 一键帮搭按钮 ───────────────────────────────
            GestureDetector(
              onTap: ctrl.todayLoading.value ? null : ctrl.generateTodayOutfit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: ctrl.todayLoading.value
                      ? null
                      : LinearGradient(
                          colors: [AppColors.primary, AppColors.roseGold],
                        ),
                  color: ctrl.todayLoading.value
                      ? AppColors.primary.withOpacity(0.3)
                      : null,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: ctrl.todayLoading.value
                      ? null
                      : [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ctrl.todayLoading.value)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    else
                      const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      ctrl.todayLoading.value
                          ? 'MUSE 正在为你搭配...'
                          : 'AI 帮我搭今日穿搭',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 300.ms),

            // ── AI 生成结果区 ─────────────────────────────────
            if (ctrl.todayGenerated.value && !ctrl.todayLoading.value) ...[
              const SizedBox(height: 24),

              // AI 搭配点评
              if (ctrl.todayAdvice.value.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ctrl.todayAdvice.value,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.65,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 16),
              ],

              // 衣橱单品搭配卡片
              if (ctrl.todayOutfitItems.isNotEmpty) ...[
                Text('今日搭配单品',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary)),
                const SizedBox(height: 12),
                ...ctrl.todayOutfitItems.asMap().entries.map((e) =>
                    _OutfitPieceCard(
                        piece: e.value, isDark: isDark, index: e.key)),
              ] else ...[
                _buildNoMatchHint(isDark),
              ],

              const SizedBox(height: 16),

              // 重新生成
              GestureDetector(
                onTap: () {
                  ctrl.todayGenerated.value = false;
                  ctrl.generateTodayOutfit();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text('换一套',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── 穿搭灵感入口（未生成时也显示） ────────────────
            if (!ctrl.todayGenerated.value) ...[
              _TodayCard(
                icon: '💼',
                title: '通勤穿搭',
                subtitle: '职场显瘦又有气场的衣橱搭法',
                isDark: isDark,
                onTap: () {
                  ctrl.todayScenario.value = '通勤';
                  ctrl.generateTodayOutfit();
                },
              ),
              const SizedBox(height: 10),
              _TodayCard(
                icon: '💕',
                title: '约会穿搭',
                subtitle: '甜美有心机，让他多看你几眼',
                isDark: isDark,
                onTap: () {
                  ctrl.todayScenario.value = '约会';
                  ctrl.generateTodayOutfit();
                },
              ),
              const SizedBox(height: 10),
              _TodayCard(
                icon: '✈️',
                title: '出行穿搭',
                subtitle: '舒适好看，拍照出片',
                isDark: isDark,
                onTap: () {
                  ctrl.todayScenario.value = '出行';
                  ctrl.generateTodayOutfit();
                },
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildEmptyWardrobeHint(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '衣橱是空的，先去「👗 衣橱」Tab 添加几件衣物，搭配会更精准',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.gold,
                  height: 1.5),
            ),
          ),
          GestureDetector(
            onTap: () => Get.find<WardrobeController>().activeTab.value =
                WardrobeTab.wardrobe,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('去添加',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatchHint(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '衣橱里暂时没找到完全对应的单品，上面的搭配建议仍然有效，可以按这个方向选购 ✨',
        style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5),
      ),
    );
  }

  // ── 添加衣物弹窗 ─────────────────────────────────────────────
  void _showAddItemSheet(
      BuildContext context, WardrobeController ctrl, bool isDark) {
    final nameCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final selectedCat = ClothingCategory.top.obs;
    final pickedImagePath = Rx<String?>(null);
    final pickedImageBytes = Rx<Uint8List?>(null);

    Future<void> pickImage(ImageSource source) async {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
        if (picked == null) return;
        pickedImagePath.value = picked.path;
        if (kIsWeb) {
          pickedImageBytes.value = await picked.readAsBytes();
        }
      } catch (_) {
        Get.snackbar('提示', '打开相册失败',
            snackPosition: SnackPosition.BOTTOM,
            margin: const EdgeInsets.all(16));
      }
    }

    Get.bottomSheet(
      StatefulBuilder(builder: (ctx, setState) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('添加衣物',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color:
                                isDark ? Colors.white : AppColors.textPrimary)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Icon(Icons.close,
                          color: AppColors.textSecondary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── 图片选择区 ────────────────────────────────
                Obx(() {
                  final hasImage = pickedImagePath.value != null;
                  return GestureDetector(
                    onTap: () {
                      // 弹出来源选择
                      Get.bottomSheet(
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.camera_alt_outlined),
                                title: const Text('拍照'),
                                onTap: () {
                                  Get.back();
                                  pickImage(ImageSource.camera);
                                },
                              ),
                              ListTile(
                                leading:
                                    const Icon(Icons.photo_library_outlined),
                                title: const Text('从相册选择'),
                                onTap: () {
                                  Get.back();
                                  pickImage(ImageSource.gallery);
                                },
                              ),
                              if (hasImage)
                                ListTile(
                                  leading: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  title: const Text('删除图片',
                                      style: TextStyle(color: Colors.red)),
                                  onTap: () {
                                    Get.back();
                                    pickedImagePath.value = null;
                                    pickedImageBytes.value = null;
                                  },
                                ),
                            ],
                          ),
                        ),
                        backgroundColor: Colors.transparent,
                      );
                    },
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: hasImage
                              ? AppColors.primary.withOpacity(0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: hasImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: kIsWeb && pickedImageBytes.value != null
                                  ? Image.memory(pickedImageBytes.value!,
                                      fit: BoxFit.cover,
                                      width: double.infinity)
                                  : Image.file(File(pickedImagePath.value!),
                                      fit: BoxFit.cover,
                                      width: double.infinity),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 32,
                                    color: AppColors.textSecondary
                                        .withOpacity(0.6)),
                                const SizedBox(height: 8),
                                Text('添加衣物照片（可选）',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                    ),
                  );
                }),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '名称（如：白色oversize衬衫）',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: colorCtrl,
                  decoration: InputDecoration(
                    labelText: '颜色（可选）',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text('分类',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Obx(() => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ClothingCategory.values.map((cat) {
                        final isSel = selectedCat.value == cat;
                        return GestureDetector(
                          onTap: () => selectedCat.value = cat,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppColors.primary
                                  : AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text('${cat.emoji} ${cat.label}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: isSel
                                        ? Colors.white
                                        : AppColors.primary)),
                          ),
                        );
                      }).toList(),
                    )),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        Get.snackbar('提示', '请输入衣物名称',
                            snackPosition: SnackPosition.BOTTOM,
                            margin: const EdgeInsets.all(16));
                        return;
                      }
                      ctrl.addItem(ClothingItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        category: selectedCat.value,
                        color: colorCtrl.text.trim().isEmpty
                            ? null
                            : colorCtrl.text.trim(),
                        imagePath: kIsWeb ? null : pickedImagePath.value,
                        imageBytes: kIsWeb ? pickedImageBytes.value : null,
                        addedAt: DateTime.now(),
                      ));
                      Get.back();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('添加到衣橱',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
      isScrollControlled: true,
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;
  const _CategoryChip(
      {required this.label,
      required this.isSelected,
      required this.onTap,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : AppColors.textSecondary),
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _ClothingCard extends StatelessWidget {
  final ClothingItem item;
  final bool isDark;
  final VoidCallback onDelete;
  final int index;
  const _ClothingCard(
      {required this.item,
      required this.isDark,
      required this.onDelete,
      required this.index});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(
          children: [
            // 图片区（有图显示图，无图显示 emoji）
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                child: item.hasImage
                    ? _buildItemImage(item)
                    : _emojiPlaceholder(),
              ),
            ),
            // 文字区
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                children: [
                  Text(item.name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : AppColors.textPrimary)),
                  if (item.color != null) ...[
                    const SizedBox(height: 2),
                    Text(item.color!,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (index * 60).ms).scale(
          begin: const Offset(0.95, 0.95)),
    );
  }

  Widget _buildItemImage(ClothingItem item) {
    // Web: bytes优先
    if (item.imageBytes != null) {
      return Image.memory(item.imageBytes!,
          fit: BoxFit.cover, width: double.infinity);
    }
    // Native: 文件路径
    if (item.imagePath != null) {
      return Image.file(
        File(item.imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _emojiPlaceholder(),
      );
    }
    return _emojiPlaceholder();
  }

  Widget _emojiPlaceholder() {
    return Container(
      color: AppColors.primary.withOpacity(0.06),
      child: Center(
        child:
            Text(item.category.emoji, style: const TextStyle(fontSize: 32)),
      ),
    );
  }
}

class _OutfitResultCard extends StatelessWidget {
  final ResultCard card;
  final bool isDark;
  final int index;
  const _OutfitResultCard(
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
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary)),
          if (card.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(card.subtitle!,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
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
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(tag,
                            style: TextStyle(
                                fontSize: 11, color: AppColors.primary)),
                      ))
                  .toList(),
            ),
          ],
          if (card.price != null) ...[
            const SizedBox(height: 8),
            Text(card.price!,
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.roseGold,
                    fontWeight: FontWeight.w600)),
          ],
          // 联盟跳转（预留）
          if (card.buyUrl != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: 联盟跳转
                  Get.snackbar('购买跳转', '联盟购买功能即将上线 🛒',
                      snackPosition: SnackPosition.BOTTOM,
                      margin: const EdgeInsets.all(16));
                },
                icon: Icon(Icons.shopping_bag_outlined,
                    size: 14, color: AppColors.primary),
                label: Text('去购买',
                    style: TextStyle(fontSize: 13, color: AppColors.primary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
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

class _TodayCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;
  const _TodayCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
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
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

// 今日穿搭单品卡片
class _OutfitPieceCard extends StatelessWidget {
  final _OutfitPiece piece;
  final bool isDark;
  final int index;
  const _OutfitPieceCard(
      {required this.piece, required this.isDark, required this.index});

  @override
  Widget build(BuildContext context) {
    final item = piece.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.07) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
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
          // 图片/emoji
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: item.hasImage
                  ? _buildImg(item)
                  : Container(
                      color: AppColors.primary.withOpacity(0.06),
                      child: Center(
                        child: Text(item.category.emoji,
                            style: const TextStyle(fontSize: 28)),
                      ),
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
                    Expanded(
                      child: Text(item.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(item.category.label,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.primary)),
                    ),
                  ],
                ),
                if (item.color != null) ...[
                  const SizedBox(height: 2),
                  Text(item.color!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 4),
                Text(piece.reason,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary.withOpacity(0.7))),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 20),
        ],
      ),
    ).animate().fadeIn(delay: (index * 80).ms).slideX(begin: 0.03, end: 0);
  }

  Widget _buildImg(ClothingItem item) {
    if (item.imageBytes != null) {
      return Image.memory(item.imageBytes!,
          fit: BoxFit.cover, width: 60, height: 60);
    }
    if (item.imagePath != null) {
      return Image.file(File(item.imagePath!),
          fit: BoxFit.cover,
          width: 60,
          height: 60,
          errorBuilder: (_, __, ___) => Container(
                color: AppColors.primary.withOpacity(0.06),
                child: Center(
                    child: Text(item.category.emoji,
                        style: const TextStyle(fontSize: 28))),
              ));
    }
    return const SizedBox.shrink();
  }
}

class _OutfitInput extends StatelessWidget {
  final WardrobeController ctrl;
  final bool isDark;
  const _OutfitInput({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
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
                hintText: '描述场合或心情...',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
                // 语音按钮预留
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
                  ctrl.askOutfit(v.trim());
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
                  ctrl.askOutfit(q);
                  textCtrl.clear();
                  ctrl.inputText.value = '';
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: ctrl.inputText.value.trim().isNotEmpty
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
                ),
              )),
        ],
      ),
    );
  }
}
