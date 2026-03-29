import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/ingredient_result.dart';
import '../../core/theme/app_colors.dart';

class IngredientReportPage extends StatefulWidget {
  const IngredientReportPage({super.key});

  @override
  State<IngredientReportPage> createState() => _IngredientReportPageState();
}

class _IngredientReportPageState extends State<IngredientReportPage>
    with TickerProviderStateMixin {
  late IngredientResult _result;
  late AnimationController _fadeCtrl;
  late AnimationController _scoreCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scoreAnim;

  bool _isSharing = false;
  final _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _result = Get.arguments as IngredientResult;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scoreCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scoreAnim =
        CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic);

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 200), _scoreCtrl.forward);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  // 根据评分决定主色调
  Color get _scoreColor {
    final s = _result.safetyScore;
    if (s >= 80) return const Color(0xFF4CAF7D);
    if (s >= 60) return const Color(0xFFE8A54B);
    return const Color(0xFFE05C5C);
  }

  String get _scoreLabel {
    final s = _result.safetyScore;
    if (s >= 90) return '非常安全';
    if (s >= 80) return '比较安全';
    if (s >= 70) return '整体温和';
    if (s >= 60) return '注意部分成分';
    return '建议谨慎使用';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Get.back(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _shareReport,
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _scoreColor,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: _scoreColor.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: _isSharing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_outlined,
                            size: 14, color: Colors.white),
                        SizedBox(width: 5),
                        Text('分享',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RepaintBoundary(
          key: _repaintKey,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // ── 顶部评分区 ──────────────────────────────────────
                _buildScoreSection(),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 综合评价 ──────────────────────────────────
                      _buildSummaryCard(),
                      const SizedBox(height: 20),

                      // ── 成分列表 ──────────────────────────────────
                      if (_result.safeIngredients.isNotEmpty) ...[
                        _buildIngredientSection(
                          title: '✅ 安全成分',
                          subtitle: '对皮肤有益，放心使用',
                          items: _result.safeIngredients,
                          color: const Color(0xFF4CAF7D),
                          bgColor: const Color(0xFFF0FBF5),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_result.cautionIngredients.isNotEmpty) ...[
                        _buildIngredientSection(
                          title: '⚠️ 注意成分',
                          subtitle: '部分人群需留意',
                          items: _result.cautionIngredients,
                          color: const Color(0xFFE8A54B),
                          bgColor: const Color(0xFFFDF7EC),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_result.riskIngredients.isNotEmpty) ...[
                        _buildIngredientSection(
                          title: '🚨 风险成分',
                          subtitle: '建议敏感肌避开',
                          items: _result.riskIngredients,
                          color: const Color(0xFFE05C5C),
                          bgColor: const Color(0xFFFDF2F2),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── 适合/不适合肤质 ──────────────────────────
                      _buildSkinTypeSection(),
                      const SizedBox(height: 16),

                      // ── 使用建议 ──────────────────────────────────
                      _buildRecommendationCard(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 顶部评分区 ──────────────────────────────────────────────────
  Widget _buildScoreSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _scoreColor.withOpacity(0.12),
            _scoreColor.withOpacity(0.04),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '🔬 成分安全分析',
                    style: TextStyle(
                      fontSize: 13,
                      color: _scoreColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _scoreColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      _result.safetyLevel,
                      style: TextStyle(
                        fontSize: 12,
                        color: _scoreColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 环形评分仪
              Row(
                children: [
                  // 圆环
                  AnimatedBuilder(
                    animation: _scoreAnim,
                    builder: (_, __) => SizedBox(
                      width: 110,
                      height: 110,
                      child: CustomPaint(
                        painter: _ScoreRingPainter(
                          progress:
                              _scoreAnim.value * _result.safetyScore / 100,
                          color: _scoreColor,
                          bgColor: _scoreColor.withOpacity(0.12),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(_scoreAnim.value * _result.safetyScore).round()}',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: _scoreColor,
                                  height: 1,
                                ),
                              ),
                              Text(
                                '/100',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _scoreColor.withOpacity(0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  // 产品名 + 评级
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _result.productName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _scoreLabel,
                          style: TextStyle(
                            fontSize: 14,
                            color: _scoreColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 三个计数统计
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildCountChip(
                              '${_result.safeIngredients.length}个安全',
                              const Color(0xFF4CAF7D),
                            ),
                            if (_result.cautionIngredients.isNotEmpty)
                              _buildCountChip(
                                '${_result.cautionIngredients.length}个注意',
                                const Color(0xFFE8A54B),
                              ),
                            if (_result.riskIngredients.isNotEmpty)
                              _buildCountChip(
                                '${_result.riskIngredients.length}个风险',
                                const Color(0xFFE05C5C),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── 综合评价卡 ──────────────────────────────────────────────────
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💬', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _result.summary,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
                height: 1.65,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 成分列表分组 ────────────────────────────────────────────────
  Widget _buildIngredientSection({
    required String title,
    required String subtitle,
    required List<IngredientItem> items,
    required Color color,
    required Color bgColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Column(
            children: items
                .asMap()
                .entries
                .map((e) => _buildIngredientItem(
                      e.value,
                      color,
                      isLast: e.key == items.length - 1,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientItem(
      IngredientItem item, Color color,
      {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            item.function,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.note,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: color.withOpacity(0.1),
            indent: 32,
            endIndent: 14,
          ),
      ],
    );
  }

  // ── 肤质适合性 ────────────────────────────────────────────────
  Widget _buildSkinTypeSection() {
    if (_result.suitableSkinTypes.isEmpty &&
        _result.avoidSkinTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '适合人群',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (_result.suitableSkinTypes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _result.suitableSkinTypes
                  .map((s) => _buildSkinChip(s, const Color(0xFF4CAF7D), true))
                  .toList(),
            ),
          ],
          if (_result.avoidSkinTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '建议避开',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _result.avoidSkinTypes
                  .map((s) =>
                      _buildSkinChip(s, const Color(0xFFE05C5C), false))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkinChip(String label, Color color, bool isSuitable) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSuitable ? Icons.check : Icons.close,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 使用建议 ──────────────────────────────────────────────────
  Widget _buildRecommendationCard() {
    if (_result.recommendation.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _scoreColor.withOpacity(0.08),
            _scoreColor.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _scoreColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _scoreColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('💡', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '使用建议',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _scoreColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _result.recommendation,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 分享 ──────────────────────────────────────────────────────
  Future<void> _shareReport() async {
    setState(() => _isSharing = true);
    HapticFeedback.mediumImpact();
    try {
      // 截图
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      Uint8List? pngBytes;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData?.buffer.asUint8List();
      }

      final scoreColor = _result.safetyScore >= 80
          ? '✅'
          : _result.safetyScore >= 60
              ? '⚠️'
              : '🚨';
      final shareText =
          '$scoreColor 我用 MUSE 检测了「${_result.productName}」\n'
          '安全评分：${_result.safetyScore}/100 · ${_result.safetyLevel}\n'
          '${_result.recommendation}\n来自 MUSE AI私人风格顾问';

      if (pngBytes != null && !kIsWeb) {
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/muse_ingredient_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(pngBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: shareText,
          subject: 'MUSE 成分安全检测报告',
        );
      } else if (pngBytes != null && kIsWeb) {
        await Share.shareXFiles(
          [XFile.fromData(pngBytes,
              name: 'muse_ingredient.png', mimeType: 'image/png')],
        );
      } else {
        await Share.share(shareText, subject: 'MUSE 成分安全检测报告');
      }
    } catch (e) {
      Get.snackbar('分享失败', '稍后再试～', snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }
}

// ── 环形评分画笔 ──────────────────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color color;
  final Color bgColor;

  _ScoreRingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 14) / 2;
    const strokeWidth = 7.0;

    // 背景圆环
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // 进度圆弧
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.color != color;
}
