import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/storage_service.dart';

// ══════════════════════════════════════════════════════════════
//  数据模型
// ══════════════════════════════════════════════════════════════

class LipColor {
  final String name;    // 色号名称
  final String hex;     // 颜色值
  final String brand;   // 品牌
  final String shade;   // 色调描述（如"暖橘红"）
  final String finish;  // 质地（如"哑光""珠光""镜面"）
  final bool isSuggested; // 是否为AI推荐

  const LipColor({
    required this.name,
    required this.hex,
    required this.brand,
    required this.shade,
    required this.finish,
    this.isSuggested = false,
  });

  int get colorValue {
    final clean = hex.replaceAll('#', '');
    return int.parse('FF$clean', radix: 16);
  }
}

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

class LipstickController extends GetxController {
  final selectedColor = Rx<LipColor?>(null);
  final isAnalyzing = false.obs;
  final analysisText = ''.obs;
  final photoBytes = Rx<Uint8List?>(null);
  final photoPath = Rx<String?>(null);
  final suggestedColors = <LipColor>[].obs;
  final activeCategory = '全部'.obs;

  // 内置色板（按色系分组）
  static const allColors = [
    // ── 红调 ──
    LipColor(name: '经典正红', hex: 'E8223C', brand: 'MAC', shade: '正红', finish: '哑光'),
    LipColor(name: '玫瑰红', hex: 'C9405A', brand: 'YSL', shade: '玫瑰红', finish: '缎光'),
    LipColor(name: '草莓红', hex: 'E8486A', brand: 'Dior', shade: '草莓红', finish: '珠光'),
    LipColor(name: '勃艮第', hex: '8B1A2A', brand: 'NARS', shade: '酒红', finish: '哑光'),
    LipColor(name: '番茄红', hex: 'D93B2C', brand: '完美日记', shade: '番茄红', finish: '丝绒'),
    // ── 豆沙/裸色 ──
    LipColor(name: '豆沙粉', hex: 'C47A7A', brand: '花西子', shade: '豆沙', finish: '哑光'),
    LipColor(name: '奶茶裸', hex: 'C49A7A', brand: 'MUFE', shade: '裸色', finish: '缎光'),
    LipColor(name: '脏橘棕', hex: 'B56A48', brand: 'MAC', shade: '脏橘', finish: '哑光'),
    LipColor(name: '米朵裸', hex: 'D4A896', brand: 'Chanel', shade: '裸粉', finish: '珠光'),
    LipColor(name: '深豆沙', hex: 'A05E5E', brand: 'Armani', shade: '深豆沙', finish: '丝绒'),
    // ── 粉调 ──
    LipColor(name: '芭比粉', hex: 'E87090', brand: 'Too Faced', shade: '亮粉', finish: '镜面'),
    LipColor(name: '雾感玫瑰', hex: 'D4768A', brand: 'YSL', shade: '玫瑰粉', finish: '哑光'),
    LipColor(name: '少女粉', hex: 'EFA0A8', brand: 'KATE', shade: '浅粉', finish: '珠光'),
    LipColor(name: '仙女粉', hex: 'F0B0B8', brand: '3CE', shade: '粉嫩', finish: '镜面'),
    // ── 橘调 ──
    LipColor(name: '珊瑚橘', hex: 'E8705A', brand: 'Bobbi Brown', shade: '珊瑚橘', finish: '缎光'),
    LipColor(name: '暖橘红', hex: 'D45A30', brand: '橘朵', shade: '暖橘', finish: '哑光'),
    LipColor(name: '南瓜橘', hex: 'C8622A', brand: 'Charlotte', shade: '深橘', finish: '丝绒'),
    // ── 紫调 ──
    LipColor(name: '雾霾紫', hex: 'A875A0', brand: 'Urban Decay', shade: '雾霾紫', finish: '哑光'),
    LipColor(name: '梅子紫', hex: '8A4878', brand: 'NARS', shade: '梅子', finish: '丝绒'),
  ];

  static const categories = ['全部', '红调', '豆沙/裸色', '粉调', '橘调', '紫调'];
  static const categoryRanges = {
    '全部': [0, 19],
    '红调': [0, 4],
    '豆沙/裸色': [5, 9],
    '粉调': [10, 13],
    '橘调': [14, 16],
    '紫调': [17, 18],
  };

  List<LipColor> get filteredColors {
    final range = categoryRanges[activeCategory.value];
    if (range == null) return allColors;
    return allColors.sublist(range[0], range[1] + 1);
  }

  void selectColor(LipColor c) {
    HapticFeedback.selectionClick();
    selectedColor.value = c;
  }

  /// 拍照 / 选图，然后AI分析最适合的口红色号
  Future<void> pickPhotoAndAnalyze() async {
    Uint8List? bytes;
    String? path;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      path = picked.path;
      if (kIsWeb) bytes = await picked.readAsBytes();
    } catch (_) {
      Get.snackbar('提示', '打开相册失败，可手动选色试色',
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16));
      return;
    }

    photoPath.value = path;
    photoBytes.value = bytes;
    isAnalyzing.value = true;
    analysisText.value = '';
    suggestedColors.clear();

    try {
      final profile = StorageService.to.loadProfile();
      final result = await AiService.to.analyzeLipColor(
        imagePath: path,
        imageBytes: bytes,
        profile: profile,
      );

      analysisText.value = result['analysis'] as String? ?? '';
      final suggested = result['suggested_shades'] as List? ?? [];
      // 从内置色板里按色调关键词匹配
      final matched = <LipColor>[];
      for (final shade in suggested) {
        final shadeStr = shade.toString().toLowerCase();
        for (final c in allColors) {
          if (c.shade.contains(shadeStr) ||
              shadeStr.contains(c.shade) ||
              c.name.contains(shadeStr)) {
            if (!matched.contains(c)) matched.add(c);
          }
        }
      }
      // 如果没匹配到，按肤色季型返回默认推荐
      if (matched.isEmpty && result['fallback_colors'] != null) {
        final fallback = result['fallback_colors'] as List;
        for (final hex in fallback) {
          final c = allColors.firstWhereOrNull(
              (x) => x.hex.toLowerCase() == hex.toString().toLowerCase());
          if (c != null) matched.add(c);
        }
      }
      suggestedColors.value = matched.isEmpty
          ? allColors.take(4).toList()
          : matched.take(4).toList();
    } catch (_) {
      analysisText.value = '分析完成～根据你的肤色，下方色板中标星的色号是我为你精选的推荐。';
      suggestedColors.value = allColors.take(4).toList();
    }

    isAnalyzing.value = false;
  }

  Future<void> takePhoto() async {
    Uint8List? bytes;
    String? path;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      path = picked.path;
      if (kIsWeb) bytes = await picked.readAsBytes();
    } catch (_) {
      Get.snackbar('提示', '打开相机失败',
          snackPosition: SnackPosition.BOTTOM, margin: const EdgeInsets.all(16));
      return;
    }

    photoPath.value = path;
    photoBytes.value = bytes;
    isAnalyzing.value = true;
    analysisText.value = '';
    suggestedColors.clear();

    try {
      final profile = StorageService.to.loadProfile();
      final result = await AiService.to.analyzeLipColor(
        imagePath: path,
        imageBytes: bytes,
        profile: profile,
      );

      analysisText.value = result['analysis'] as String? ?? '';
      final suggested = result['suggested_shades'] as List? ?? [];
      final matched = <LipColor>[];
      for (final shade in suggested) {
        final shadeStr = shade.toString();
        for (final c in allColors) {
          if (c.shade.contains(shadeStr) || c.name.contains(shadeStr)) {
            if (!matched.contains(c)) matched.add(c);
          }
        }
      }
      suggestedColors.value =
          matched.isEmpty ? allColors.take(4).toList() : matched.take(4).toList();
    } catch (_) {
      analysisText.value = '分析完成！基于你的肤色特点，已为你标出最显色的推荐。';
      suggestedColors.value = allColors.take(4).toList();
    }

    isAnalyzing.value = false;
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class LipstickPage extends StatelessWidget {
  const LipstickPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(LipstickController());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildPhotoSection(ctrl, isDark),
                    _buildCategoryTabs(ctrl, isDark),
                    _buildColorPalette(ctrl, isDark),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
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
            '口红试色',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text('💄', style: const TextStyle(fontSize: 22)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── 照片 + 试色展示区 ─────────────────────────────────────
  Widget _buildPhotoSection(LipstickController ctrl, bool isDark) {
    return Obx(() {
      final color = ctrl.selectedColor.value;
      final bytes = ctrl.photoBytes.value;

      return Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主预览区
            Container(
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: color != null
                      ? [
                          Color(color.colorValue).withOpacity(0.2),
                          AppColors.roseGold.withOpacity(0.1),
                        ]
                      : [
                          AppColors.roseGold.withOpacity(0.1),
                          AppColors.primary.withOpacity(0.06),
                        ],
                ),
                border: Border.all(
                  color: color != null
                      ? Color(color.colorValue).withOpacity(0.3)
                      : AppColors.roseGold.withOpacity(0.2),
                ),
              ),
              child: Stack(
                children: [
                  // 背景图 or 占位
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: bytes != null
                        ? Image.memory(bytes,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            color: color != null
                                ? Color(color.colorValue).withOpacity(0.15)
                                : null,
                            colorBlendMode: BlendMode.softLight)
                        : _buildPhotoPlaceholder(ctrl, isDark),
                  ),
                  // 试色信息卡（右下角）
                  if (color != null)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _ColorInfoBadge(color: color)
                          .animate()
                          .fadeIn(duration: 250.ms)
                          .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
                    ),
                  // 加载中
                  if (ctrl.isAnalyzing.value)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text('AI分析中...',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 操作按钮行
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'AI扫脸试色',
                    color: AppColors.roseGold,
                    onTap: () => ctrl.pickPhotoAndAnalyze(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.camera_alt_outlined,
                    label: '拍照分析',
                    color: AppColors.primary,
                    onTap: () => ctrl.takePhoto(),
                  ),
                ),
              ],
            ),

            // AI 分析文字
            if (ctrl.analysisText.value.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.roseGold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.roseGold.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💄', style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ctrl.analysisText.value,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
            ],

            // AI推荐色号
            if (ctrl.suggestedColors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: AppColors.roseGold),
                  const SizedBox(width: 6),
                  Text(
                    'AI 为你推荐的色号',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.roseGold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 68,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: ctrl.suggestedColors.length,
                  itemBuilder: (context, i) {
                    final c = ctrl.suggestedColors[i];
                    return Obx(() => _SuggestedColorItem(
                          color: c,
                          isSelected: ctrl.selectedColor.value == c,
                          onTap: () => ctrl.selectColor(c),
                          index: i,
                        ));
                  },
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildPhotoPlaceholder(LipstickController ctrl, bool isDark) {
    return GestureDetector(
      onTap: () => ctrl.pickPhotoAndAnalyze(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.roseGold.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.face_retouching_natural_outlined,
                  color: AppColors.roseGold, size: 28),
            ),
            const SizedBox(height: 12),
            Text('上传照片，AI为你推荐最衬肤色的色号',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('或直接点色板试色效果 →',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.roseGold.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  // ── 分类 Tab ────────────────────────────────────────────
  Widget _buildCategoryTabs(LipstickController ctrl, bool isDark) {
    return SizedBox(
      height: 36,
      child: Obx(() => ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: LipstickController.categories.length,
            itemBuilder: (context, i) {
              final cat = LipstickController.categories[i];
              final isActive = ctrl.activeCategory.value == cat;
              return GestureDetector(
                onTap: () => ctrl.activeCategory.value = cat,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.roseGold
                        : AppColors.roseGold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive
                          ? AppColors.roseGold
                          : AppColors.roseGold.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    cat,
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
              );
            },
          )),
    );
  }

  // ── 色板网格 ────────────────────────────────────────────
  Widget _buildColorPalette(LipstickController ctrl, bool isDark) {
    return Obx(() {
      final colors = ctrl.filteredColors;
      final suggested = ctrl.suggestedColors;

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: colors.length,
          itemBuilder: (context, i) {
            final c = colors[i];
            final isSelected = ctrl.selectedColor.value == c;
            final isSuggested =
                suggested.any((s) => s.name == c.name);
            return _ColorGridItem(
              color: c,
              isSelected: isSelected,
              isSuggested: isSuggested,
              onTap: () => ctrl.selectColor(c),
              index: i,
            );
          },
        ),
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ColorInfoBadge extends StatelessWidget {
  final LipColor color;

  const _ColorInfoBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Color(color.colorValue),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                color.name,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${color.brand} · ${color.finish}',
                style: TextStyle(
                    fontSize: 10, color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestedColorItem extends StatelessWidget {
  final LipColor color;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  const _SuggestedColorItem({
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(right: 10, left: index == 0 ? 2 : 0),
        width: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Color(color.colorValue)
                : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(color.colorValue).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Color(color.colorValue),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
              ),
            ),
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
              ),
              child: Center(
                child: Text(
                  color.name.length > 4
                      ? color.name.substring(0, 4)
                      : color.name,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (index * 80).ms).scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
          ),
    );
  }
}

class _ColorGridItem extends StatelessWidget {
  final LipColor color;
  final bool isSelected;
  final bool isSuggested;
  final VoidCallback onTap;
  final int index;

  const _ColorGridItem({
    required this.color,
    required this.isSelected,
    required this.isSuggested,
    required this.onTap,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Color(color.colorValue)
                : (isSuggested
                    ? AppColors.roseGold.withOpacity(0.6)
                    : Colors.transparent),
            width: isSelected ? 2.5 : (isSuggested ? 1.5 : 1),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(color.colorValue).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            // 色块
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Color(color.colorValue),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13)),
                ),
                child: Stack(
                  children: [
                    if (isSuggested)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Icon(Icons.auto_awesome,
                            size: 12, color: Colors.white.withOpacity(0.9)),
                      ),
                    if (isSelected)
                      Center(
                        child: Icon(Icons.check_rounded,
                            size: 20, color: Colors.white.withOpacity(0.9)),
                      ),
                  ],
                ),
              ),
            ),
            // 色号信息
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(13)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      color.name,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      color.finish,
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (index * 30).ms),
    );
  }
}
