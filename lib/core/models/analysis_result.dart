/// AI 形象诊断结果模型
///
/// 用于从照片分析中返回结构化的个人形象诊断结果
class AnalysisResult {
  // ─── 基础诊断 ─────────────────────────────────────────────
  final String skinToneLabel;      // 肤色描述，如"冷白皮"
  final String faceShapeLabel;     // 脸型，如"鹅蛋脸"
  final String bodyShapeLabel;     // 身材类型，如"梨形身材"
  final String seasonTypeLabel;    // 色彩季型，如"夏季型"

  // ─── 色彩系统 ─────────────────────────────────────────────
  final List<SeasonColor> recommendedColors; // 推荐色卡
  final List<String> avoidColors;            // 不建议的颜色

  // ─── 专属建议 ─────────────────────────────────────────────
  final String outfitAdvice;   // 穿搭建议（1-2句话）
  final String makeupAdvice;   // 妆容建议（1-2句话）
  final String skincareAdvice; // 护肤建议（1-2句话）
  final String hairAdvice;     // 发型建议（针对脸型）
  final List<String> styleKeywords; // 风格关键词，如["简约","高级感","冷淡风"]

  // ─── AI 综合评语 ─────────────────────────────────────────
  final String summary;        // AI整体点评，2-3句话，亲切温柔

  // ─── 元数据 ──────────────────────────────────────────────
  final DateTime createdAt;
  final String? photoPath;     // 分析用的照片路径

  const AnalysisResult({
    required this.skinToneLabel,
    required this.faceShapeLabel,
    required this.bodyShapeLabel,
    required this.seasonTypeLabel,
    required this.recommendedColors,
    required this.avoidColors,
    required this.outfitAdvice,
    required this.makeupAdvice,
    required this.skincareAdvice,
    this.hairAdvice = '',
    required this.styleKeywords,
    required this.summary,
    required this.createdAt,
    this.photoPath,
  });

  /// 序列化为 JSON（用于本地存储）
  Map<String, dynamic> toJson() => {
        'skin_tone': skinToneLabel,
        'face_shape': faceShapeLabel,
        'body_shape': bodyShapeLabel,
        'season_type': seasonTypeLabel,
        'recommended_colors':
            recommendedColors.map((c) => c.toJson()).toList(),
        'avoid_colors': avoidColors,
        'outfit_advice': outfitAdvice,
        'makeup_advice': makeupAdvice,
        'skincare_advice': skincareAdvice,
        'hair_advice': hairAdvice,
        'style_keywords': styleKeywords,
        'summary': summary,
        'created_at': createdAt.toIso8601String(),
        'photo_path': photoPath,
      };

  factory AnalysisResult.fromJson(Map<String, dynamic> json, {String? photoPath}) {
    // ── avoid_colors 兼容两种格式：字符串数组 or 对象数组 ──
    final rawAvoid = json['avoid_colors'] as List? ?? [];
    final avoidColors = rawAvoid.map((e) {
      if (e is String) return e;
      if (e is Map) return (e['name'] as String?) ?? e.toString();
      return e.toString();
    }).toList();

    return AnalysisResult(
      skinToneLabel: json['skin_tone'] as String? ?? '自然皮',
      faceShapeLabel: json['face_shape'] as String? ?? '鹅蛋脸',
      bodyShapeLabel: json['body_shape'] as String? ?? '均匀身材',
      seasonTypeLabel: json['season_type'] as String? ?? '四季通用',
      recommendedColors: ((json['recommended_colors'] as List?) ?? [])
          .map((e) => SeasonColor.fromJson(e as Map<String, dynamic>))
          .toList(),
      avoidColors: avoidColors,
      outfitAdvice: json['outfit_advice'] as String? ?? '',
      makeupAdvice: json['makeup_advice'] as String? ?? '',
      skincareAdvice: json['skincare_advice'] as String? ?? '',
      hairAdvice: json['hair_advice'] as String? ?? '',
      styleKeywords: List<String>.from(json['style_keywords'] as List? ?? []),
      summary: json['summary'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      photoPath: photoPath ?? json['photo_path'] as String?,
    );
  }

  /// Mock 演示数据（用于测试）
  factory AnalysisResult.mock() => AnalysisResult(
        skinToneLabel: '冷白皮',
        faceShapeLabel: '鹅蛋脸',
        bodyShapeLabel: '梨形身材',
        seasonTypeLabel: '夏季型',
        recommendedColors: [
          SeasonColor(name: '粉雾玫瑰', hex: '#E8A4B8'),
          SeasonColor(name: '薰衣草紫', hex: '#C9A8D4'),
          SeasonColor(name: '冰蓝灰', hex: '#B0C8D4'),
          SeasonColor(name: '奶油白', hex: '#FAF6F0'),
          SeasonColor(name: '浅薄荷', hex: '#B8D8C8'),
          SeasonColor(name: '玫瑰豆沙', hex: '#C4847A'),
        ],
        avoidColors: ['橙色（偏暖调，会让冷白皮显黄）', '土黄色（融色，整体暗沉）', '砖红色（暖调太重，撞色）'],
        outfitAdvice: '高腰设计拉长下半身比例，A字裙和阔腿裤是你的好朋友，上深下浅的穿法视觉上最显高挑。V领/一字领开阔肩线，正适合你的优雅感。',
        makeupAdvice: '冷调玫瑰色系最衬你肤色，推荐粉紫眼影配玫瑰豆沙唇色，腮红选择玫粉调，避免暖橘调彩妆。',
        skincareAdvice: '冷白皮肌肤通常偏薄、容易泛红，重点做好补水保湿和防晒，避免含酒精刺激性成分。推荐含神经酰胺/积雪草修护精华。',
        hairAdvice: '鹅蛋脸适合大多数发型，微烫的慵懒卷最能体现你的温柔感，或者高马尾+碎发展示清爽个性感。',
        styleKeywords: ['冷淡风', '高级感', '法式优雅', '简约知性'],
        summary: '你是妥妥的冷白皮鹅蛋脸，天生就适合走高级冷淡路线！夏季型的色彩系统让你穿浅粉浅紫都超仙，避开暖橘调就完全不会出错～春季这波穿浅玫瑰色的连衣裙绝对是今年最美那个。',
        createdAt: DateTime.now(),
      );
}

/// 推荐色卡中的单个颜色
class SeasonColor {
  final String name;  // 颜色名称，如"粉雾玫瑰"
  final String hex;   // 十六进制颜色值，如"#E8A4B8"

  const SeasonColor({required this.name, required this.hex});

  factory SeasonColor.fromJson(Map<String, dynamic> json) => SeasonColor(
        name: json['name'] as String? ?? '',
        hex: json['hex'] as String? ?? '#CCCCCC',
      );

  Map<String, dynamic> toJson() => {'name': name, 'hex': hex};

  /// 将 hex 字符串转为 Flutter Color 整型值
  int get colorValue {
    final clean = hex.replaceAll('#', '');
    return int.parse('FF$clean', radix: 16);
  }
}
