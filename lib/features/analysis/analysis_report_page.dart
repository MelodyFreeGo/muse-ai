import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/analysis_result.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_colors.dart';

class AnalysisReportPage extends StatefulWidget {
  const AnalysisReportPage({super.key});

  @override
  State<AnalysisReportPage> createState() => _AnalysisReportPageState();
}

class _AnalysisReportPageState extends State<AnalysisReportPage>
    with TickerProviderStateMixin {
  late AnalysisResult _result;
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // 截图 key（用于生成分享图）
  final _repaintKey = GlobalKey();
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _result = Get.arguments as AnalysisResult;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // 根据季型给出背景渐变
  List<Color> get _seasonGradient {
    final s = _result.seasonTypeLabel;
    if (s.contains('春')) return [const Color(0xFFFBE8D0), const Color(0xFFF5C4C4)];
    if (s.contains('夏')) return [const Color(0xFFD4E8F5), const Color(0xFFCED4F0)];
    if (s.contains('秋')) return [const Color(0xFFF5E0C4), const Color(0xFFE8C4A0)];
    if (s.contains('冬')) return [const Color(0xFFD8D4F0), const Color(0xFFC4D0E8)];
    return [const Color(0xFFE8D5C8), const Color(0xFFFAF8F5)];
  }

  Color get _seasonAccent {
    final s = _result.seasonTypeLabel;
    if (s.contains('春')) return const Color(0xFFE8957A);
    if (s.contains('夏')) return const Color(0xFF7A9CE8);
    if (s.contains('秋')) return const Color(0xFFD4885A);
    if (s.contains('冬')) return const Color(0xFF7A7ACE);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Get.back(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.35),
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
                        Icon(Icons.share_outlined, size: 14, color: Colors.white),
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
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: RepaintBoundary(
              key: _repaintKey,
              child: Column(
                children: [
                  // ── 顶部英雄区域 ──────────────────────────────
                  _buildHeroSection(),
                  const SizedBox(height: 8),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 基础诊断四格 ──────────────────────────
                        _buildDiagnosisGrid(),
                        const SizedBox(height: 24),

                        // ── 色彩季型色卡 ──────────────────────────
                        _buildColorPalette(),
                        const SizedBox(height: 24),

                        // ── 不建议的颜色 ──────────────────────────
                        if (_result.avoidColors.isNotEmpty) ...[
                          _buildAvoidColors(),
                          const SizedBox(height: 24),
                        ],

                        // ── 风格关键词 ────────────────────────────
                        if (_result.styleKeywords.isNotEmpty) ...[
                          _buildStyleKeywords(),
                          const SizedBox(height: 24),
                        ],

                        // ── 专属建议三块 ──────────────────────────
                        _buildAdviceCard(
                          icon: '👗',
                          title: '穿搭建议',
                          content: _result.outfitAdvice,
                          color: const Color(0xFFC9956C),
                        ),
                        const SizedBox(height: 12),
                        _buildAdviceCard(
                          icon: '💄',
                          title: '妆容建议',
                          content: _result.makeupAdvice,
                          color: const Color(0xFFD4706C),
                        ),
                        const SizedBox(height: 12),
                        _buildAdviceCard(
                          icon: '🧴',
                          title: '护肤建议',
                          content: _result.skincareAdvice,
                          color: const Color(0xFF6BAF8C),
                        ),
                        if (_result.hairAdvice.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildAdviceCard(
                            icon: '✂️',
                            title: '发型建议',
                            content: _result.hairAdvice,
                            color: const Color(0xFF8C6BAF),
                          ),
                        ],
                        const SizedBox(height: 32),


                        // ── 底部 CTA ──────────────────────────────
                        _buildBottomCTA(),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 顶部英雄区：季型背景 + 头像 + 综合评语 ─────────────────────
  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _seasonGradient,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Text(
                    '✨ 专属形象诊断',
                    style: TextStyle(
                      fontSize: 13,
                      color: _seasonAccent,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _seasonAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      _result.seasonTypeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: _seasonAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // AI 综合评语卡片
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.7), width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🌸',
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _result.summary,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              height: 1.65,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 基础诊断四格：肤色/脸型/身材/季型 ──────────────────────────
  Widget _buildDiagnosisGrid() {
    final items = [
      _DiagItem(icon: '🎨', label: '肤色', value: _result.skinToneLabel),
      _DiagItem(icon: '💎', label: '脸型', value: _result.faceShapeLabel),
      _DiagItem(icon: '👤', label: '身材', value: _result.bodyShapeLabel),
      _DiagItem(icon: '🌸', label: '季型', value: _result.seasonTypeLabel),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('基础诊断'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: items.map((item) => _buildDiagCard(item)).toList(),
        ),
      ],
    );
  }

  Widget _buildDiagCard(_DiagItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 色彩季型色卡 ─────────────────────────────────────────────────
  Widget _buildColorPalette() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('你的专属色盘'),
        const SizedBox(height: 4),
        Text(
          '这些颜色最适合你的肤色和季型',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.1,
          children: _result.recommendedColors.map(_buildColorSwatch).toList(),
        ),
      ],
    );
  }

  Widget _buildColorSwatch(SeasonColor c) {
    final color = Color(c.colorValue);
    // 判断颜色深浅决定文字颜色
    final luminance = color.computeLuminance();
    final textColor =
        luminance > 0.5 ? Colors.black87 : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            c.hex.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: textColor.withOpacity(0.7),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            c.name,
            style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── 不建议颜色 ───────────────────────────────────────────────────
  Widget _buildAvoidColors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('尽量避开这些色'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _result.avoidColors
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                          color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close,
                            size: 12,
                            color: AppColors.error.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text(c,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.error.withOpacity(0.8),
                              fontWeight: FontWeight.w500,
                            )),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ── 风格关键词 ───────────────────────────────────────────────────
  Widget _buildStyleKeywords() {
    final colors = [
      _seasonAccent,
      AppColors.primary.withOpacity(0.8),
      AppColors.gold,
      AppColors.success,
      AppColors.nude,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('你的风格标签'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _result.styleKeywords.asMap().entries.map((e) {
            final color = colors[e.key % colors.length];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(
                '# ${e.value}',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 建议卡片 ──────────────────────────────────────────────────────
  Widget _buildAdviceCard({
    required String icon,
    required String title,
    required String content,
    required Color color,
  }) {
    if (content.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 13,
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

  // ── 底部 CTA ──────────────────────────────────────────────────────
  Widget _buildBottomCTA() {
    return Column(
      children: [
        // 去更新档案
        GestureDetector(
          onTap: _syncToProfile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  '根据诊断更新我的档案',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 分享到小红书
        GestureDetector(
          onTap: _shareReport,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: AppColors.primaryLight),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('📕', style: TextStyle(fontSize: 16)),
                SizedBox(width: 8),
                Text(
                  '分享到小红书',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 档案联动：把诊断结果写回 UserProfile ─────────────────────────
  Future<void> _syncToProfile() async {
    HapticFeedback.mediumImpact();
    final storage = StorageService.to;
    final existing = storage.loadProfile();

    if (existing == null) {
      Get.snackbar('提示', '还没有建档哦，先完成档案设置吧～',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // 将文字标签映射到枚举（兼容 AI 返回的各种写法）
    SkinTone? parsedSkinTone = _parseSkinTone(_result.skinToneLabel);
    FaceShape? parsedFaceShape = _parseFaceShape(_result.faceShapeLabel);
    BodyShape? parsedBodyShape = _parseBodyShape(_result.bodyShapeLabel);
    SeasonType? parsedSeasonType = _parseSeasonType(_result.seasonTypeLabel);

    final updated = existing.copyWith(
      skinTone: parsedSkinTone ?? existing.skinTone,
      faceShape: parsedFaceShape ?? existing.faceShape,
      bodyShape: parsedBodyShape ?? existing.bodyShape,
      seasonType: parsedSeasonType ?? existing.seasonType,
    );

    await storage.saveProfile(updated);

    // 更新 HomeController 中的缓存（如果在路由栈里）
    try {
      // ignore: invalid_use_of_protected_member
    } catch (_) {}

    Get.snackbar(
      '✅ 档案已更新',
      [
        if (parsedSkinTone != null) '肤色：${_result.skinToneLabel}',
        if (parsedFaceShape != null) '脸型：${_result.faceShapeLabel}',
        if (parsedSeasonType != null) '季型：${_result.seasonTypeLabel}',
      ].join(' · '),
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: const Color(0xFF4CAF7D),
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }

  // ── 枚举解析辅助（模糊匹配） ──────────────────────────────────────
  SkinTone? _parseSkinTone(String label) {
    final l = label;
    if (l.contains('冷白') || l.contains('瓷白')) return SkinTone.coolWhite;
    if (l.contains('暖黄') || l.contains('黄调')) return SkinTone.warmYellow;
    if (l.contains('小麦') || l.contains('健康')) return SkinTone.wheat;
    if (l.contains('深') || l.contains('黑')) return SkinTone.deep;
    if (l.contains('中性') || l.contains('自然')) return SkinTone.neutral;
    return null;
  }

  FaceShape? _parseFaceShape(String label) {
    final l = label;
    if (l.contains('鹅蛋') || l.contains('椭圆') || l.contains('oval'))
      return FaceShape.oval;
    if (l.contains('圆')) return FaceShape.round;
    if (l.contains('方')) return FaceShape.square;
    if (l.contains('长')) return FaceShape.long;
    if (l.contains('心') || l.contains('倒三角')) return FaceShape.heart;
    if (l.contains('菱') || l.contains('钻石')) return FaceShape.diamond;
    return null;
  }

  BodyShape? _parseBodyShape(String label) {
    final l = label;
    if (l.contains('梨')) return BodyShape.pear;
    if (l.contains('苹果')) return BodyShape.apple;
    if (l.contains('沙漏') || l.contains('X型')) return BodyShape.hourglass;
    if (l.contains('倒三角') || l.contains('V型'))
      return BodyShape.invertedTriangle;
    if (l.contains('直筒') || l.contains('矩形') || l.contains('均匀'))
      return BodyShape.rectangle;
    return null;
  }

  SeasonType? _parseSeasonType(String label) {
    final l = label;
    if (l.contains('春')) return SeasonType.spring;
    if (l.contains('夏')) return SeasonType.summer;
    if (l.contains('秋')) return SeasonType.autumn;
    if (l.contains('冬')) return SeasonType.winter;
    return null;
  }

  // ── 分享报告（截图长图 + 文字fallback） ──────────────────────────
  Future<void> _shareReport() async {
    setState(() => _isSharing = true);
    HapticFeedback.mediumImpact();
    try {
      // ── Step 1: 截图 ──────────────────────────────────────
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      Uint8List? pngBytes;
      if (boundary != null) {
        // 高 DPI（pixelRatio=3 生成 @3x 分辨率，适合小红书分享）
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData?.buffer.asUint8List();
      }

      final shareText = '✨ 我的专属形象诊断 | MUSE AI私人风格顾问\n\n'
          '🌸 色彩季型：${_result.seasonTypeLabel}\n'
          '🎨 肤色：${_result.skinToneLabel}  '
          '💎 脸型：${_result.faceShapeLabel}\n'
          '${_result.summary}';

      if (pngBytes != null && !kIsWeb) {
        // ── Native：保存到临时目录，再用 Share.shareXFiles 分享图片 ──
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/muse_diagnosis_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(pngBytes);

        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: shareText,
          subject: 'MUSE 我的专属形象诊断',
        );
      } else if (pngBytes != null && kIsWeb) {
        // ── Web：直接分享 bytes（部分浏览器支持） ──
        await Share.shareXFiles(
          [XFile.fromData(pngBytes,
              name: 'muse_diagnosis.png', mimeType: 'image/png')],
          subject: 'MUSE 我的专属形象诊断',
        );
      } else {
        // ── fallback：纯文字分享 ──
        await Share.share(shareText, subject: 'MUSE 我的专属形象诊断');
      }
    } catch (e) {
      // 截图失败则降级分享文字
      try {
        await Share.share(
          '✨ 我的专属形象诊断\n\n'
          '季型：${_result.seasonTypeLabel}  肤色：${_result.skinToneLabel}\n'
          '${_result.summary}\n\n来自 MUSE AI私人风格顾问',
          subject: 'MUSE 我的专属形象诊断',
        );
      } catch (_) {
        Get.snackbar('分享失败', '稍后再试～',
            snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ── 通用标题 ─────────────────────────────────────────────────────
  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: _seasonAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// 诊断项数据类
class _DiagItem {
  final String icon;
  final String label;
  final String value;
  const _DiagItem({required this.icon, required this.label, required this.value});
}
