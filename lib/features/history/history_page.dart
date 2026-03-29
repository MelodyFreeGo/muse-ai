import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/storage_service.dart';
import '../../core/models/analysis_result.dart';
import '../../core/models/ingredient_result.dart';
import '../../core/constants/app_routes.dart';

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

enum HistoryTab { analysis, ingredient }

class HistoryController extends GetxController {
  final activeTab = HistoryTab.analysis.obs;
  final analysisHistory = <AnalysisResult>[].obs;
  final ingredientHistory = <IngredientResult>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    analysisHistory.value = StorageService.to.loadAnalysisHistory();
    ingredientHistory.value = StorageService.to.loadIngredientHistory();
  }

  void refresh() => _load();

  Future<void> deleteAnalysis(int index) async {
    final list = List<AnalysisResult>.from(analysisHistory);
    list.removeAt(index);
    analysisHistory.value = list;
    // 回写存储
    final storage = StorageService.to;
    // 清空后逐条重写（最多20条，用现有API重写）
    await _rewriteAnalysisHistory(list);
  }

  Future<void> deleteIngredient(int index) async {
    final list = List<IngredientResult>.from(ingredientHistory);
    list.removeAt(index);
    ingredientHistory.value = list;
    await _rewriteIngredientHistory(list);
  }

  Future<void> _rewriteAnalysisHistory(List<AnalysisResult> list) async {
    await StorageService.to.clearAnalysisHistory();
    // 倒序插入（保留最新在前的顺序）
    for (final item in list.reversed) {
      await StorageService.to.saveAnalysisResult(item);
    }
    // 修正顺序 — 重新加载
    analysisHistory.value = StorageService.to.loadAnalysisHistory();
  }

  Future<void> _rewriteIngredientHistory(List<IngredientResult> list) async {
    await StorageService.to.clearIngredientHistory();
    for (final item in list.reversed) {
      await StorageService.to.saveIngredientResult(item);
    }
    ingredientHistory.value = StorageService.to.loadIngredientHistory();
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(HistoryController());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            _buildTabs(ctrl, isDark),
            Expanded(child: _buildBody(ctrl, isDark)),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Get.back(),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Text(
            '我的诊断记录',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text('📋', style: const TextStyle(fontSize: 22)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Tab栏 ────────────────────────────────────────────────
  Widget _buildTabs(HistoryController ctrl, bool isDark) {
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
            children: [
              _Tab(
                label: '🪞 形象诊断',
                isActive: ctrl.activeTab.value == HistoryTab.analysis,
                onTap: () => ctrl.activeTab.value = HistoryTab.analysis,
                isDark: isDark,
              ),
              _Tab(
                label: '🔬 成分检测',
                isActive: ctrl.activeTab.value == HistoryTab.ingredient,
                onTap: () => ctrl.activeTab.value = HistoryTab.ingredient,
                isDark: isDark,
              ),
            ],
          )),
    );
  }

  // ── 主体 ─────────────────────────────────────────────────
  Widget _buildBody(HistoryController ctrl, bool isDark) {
    return Obx(() {
      if (ctrl.activeTab.value == HistoryTab.analysis) {
        if (ctrl.analysisHistory.isEmpty) {
          return _buildEmpty('还没有形象诊断记录\n去首页拍照做个专属诊断吧 🪞', isDark);
        }
        return _buildAnalysisList(ctrl, isDark);
      } else {
        if (ctrl.ingredientHistory.isEmpty) {
          return _buildEmpty('还没有成分检测记录\n去首页拍成分表照片试试吧 🔬', isDark);
        }
        return _buildIngredientList(ctrl, isDark);
      }
    });
  }

  Widget _buildEmpty(String msg, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 56, color: AppColors.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.7,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // ── 形象诊断列表 ────────────────────────────────────────
  Widget _buildAnalysisList(HistoryController ctrl, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: ctrl.analysisHistory.length,
      itemBuilder: (context, i) {
        final item = ctrl.analysisHistory[i];
        return Dismissible(
          key: ValueKey('analysis_$i${item.createdAt}'),
          direction: DismissDirection.endToStart,
          background: _swipeDeleteBg(),
          onDismissed: (_) => ctrl.deleteAnalysis(i),
          child: _AnalysisHistoryCard(
            result: item,
            index: i,
            isDark: isDark,
            onTap: () => Get.toNamed(AppRoutes.analysisReport, arguments: item),
          ),
        );
      },
    );
  }

  // ── 成分检测列表 ────────────────────────────────────────
  Widget _buildIngredientList(HistoryController ctrl, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: ctrl.ingredientHistory.length,
      itemBuilder: (context, i) {
        final item = ctrl.ingredientHistory[i];
        return Dismissible(
          key: ValueKey('ingredient_$i${item.createdAt}'),
          direction: DismissDirection.endToStart,
          background: _swipeDeleteBg(),
          onDismissed: (_) => ctrl.deleteIngredient(i),
          child: _IngredientHistoryCard(
            result: item,
            index: i,
            isDark: isDark,
            onTap: () =>
                Get.toNamed(AppRoutes.ingredientReport, arguments: item),
          ),
        );
      },
    );
  }

  Widget _swipeDeleteBg() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5252).withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.delete_outline_rounded,
          color: Color(0xFFFF5252), size: 22),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _Tab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;

  const _Tab({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.white60 : AppColors.textSecondary),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 形象诊断历史卡片
class _AnalysisHistoryCard extends StatelessWidget {
  final AnalysisResult result;
  final int index;
  final bool isDark;
  final VoidCallback onTap;

  const _AnalysisHistoryCard({
    required this.result,
    required this.index,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 根据季型选颜色
    final seasonColors = {
      '春': [const Color(0xFFFFE4B5), const Color(0xFFFFC87C)],
      '夏': [const Color(0xFFE8D4F0), const Color(0xFFC9A8D4)],
      '秋': [const Color(0xFFFFDEB4), const Color(0xFFD4956A)],
      '冬': [const Color(0xFFCDE8F5), const Color(0xFF7BB8D4)],
    };
    List<Color> gradientColors = [AppColors.primary.withOpacity(0.2), AppColors.roseGold.withOpacity(0.15)];
    for (final entry in seasonColors.entries) {
      if (result.seasonTypeLabel.contains(entry.key)) {
        gradientColors = entry.value;
        break;
      }
    }

    final dateStr = _formatDate(result.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
        child: Row(
          children: [
            // 左侧季型色条
            Container(
              width: 72,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🪞', style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    result.seasonTypeLabel.length > 3
                        ? result.seasonTypeLabel.substring(0, 3)
                        : result.seasonTypeLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // 右侧信息
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${result.skinToneLabel} · ${result.faceShapeLabel}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.styleKeywords.take(3).join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 推荐色点
                    Row(
                      children: [
                        ...result.recommendedColors.take(5).map((c) {
                          return Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Color(c.colorValue),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                          );
                        }),
                        const Spacer(),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (index * 60).ms).slideX(begin: 0.04, end: 0),
    );
  }
}

/// 成分检测历史卡片
class _IngredientHistoryCard extends StatelessWidget {
  final IngredientResult result;
  final int index;
  final bool isDark;
  final VoidCallback onTap;

  const _IngredientHistoryCard({
    required this.result,
    required this.index,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 评分颜色
    final scoreColor = result.safetyScore >= 80
        ? const Color(0xFF4CAF7D)
        : result.safetyScore >= 60
            ? const Color(0xFFFF9C00)
            : const Color(0xFFFF5252);

    final scoreEmoji = result.safetyScore >= 80
        ? '✅'
        : result.safetyScore >= 60
            ? '⚠️'
            : '🚨';

    final dateStr = _formatDate(result.createdAt);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
        child: Row(
          children: [
            // 左侧评分色条
            Container(
              width: 72,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scoreColor.withOpacity(0.7),
                    scoreColor.withOpacity(0.3),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(scoreEmoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(
                    '${result.safetyScore}',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '分',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            // 右侧信息
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            result.productName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.safetyLevel,
                      style: TextStyle(
                        fontSize: 11,
                        color: scoreColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _IngredientBadge(
                          count: result.safeIngredients.length,
                          color: const Color(0xFF4CAF7D),
                          label: '安全',
                        ),
                        const SizedBox(width: 6),
                        if (result.cautionIngredients.isNotEmpty)
                          _IngredientBadge(
                            count: result.cautionIngredients.length,
                            color: const Color(0xFFFF9C00),
                            label: '注意',
                          ),
                        if (result.riskIngredients.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _IngredientBadge(
                            count: result.riskIngredients.length,
                            color: const Color(0xFFFF5252),
                            label: '风险',
                          ),
                        ],
                        const Spacer(),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (index * 60).ms).slideX(begin: 0.04, end: 0),
    );
  }
}

class _IngredientBadge extends StatelessWidget {
  final int count;
  final Color color;
  final String label;

  const _IngredientBadge(
      {required this.count, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '今天 $h:$m';
  } else if (diff.inDays == 1) {
    return '昨天';
  } else if (diff.inDays < 7) {
    return '${diff.inDays}天前';
  } else {
    return '${dt.month}月${dt.day}日';
  }
}
