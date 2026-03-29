/// 成分检测结果模型
class IngredientResult {
  final String productName;        // 识别到的产品名称
  final String safetyLevel;        // 整体安全等级：安全/温和/注意/风险
  final int safetyScore;           // 安全评分 0-100
  final List<IngredientItem> safeIngredients;   // 安全成分列表
  final List<IngredientItem> cautionIngredients; // 需注意成分
  final List<IngredientItem> riskIngredients;   // 风险/致敏成分

  final List<String> suitableSkinTypes;  // 适合的肤质
  final List<String> avoidSkinTypes;     // 不适合的肤质
  final String summary;                  // 综合评价
  final String recommendation;           // 使用建议（1-2句话）

  final DateTime createdAt;
  final String? photoPath;

  const IngredientResult({
    required this.productName,
    required this.safetyLevel,
    required this.safetyScore,
    required this.safeIngredients,
    required this.cautionIngredients,
    required this.riskIngredients,
    required this.suitableSkinTypes,
    required this.avoidSkinTypes,
    required this.summary,
    required this.recommendation,
    required this.createdAt,
    this.photoPath,
  });

  factory IngredientResult.fromJson(Map<String, dynamic> json,
      {String? photoPath}) {
    return IngredientResult(
      productName: json['product_name'] as String? ?? '护肤品',
      safetyLevel: json['safety_level'] as String? ?? '温和',
      safetyScore: (json['safety_score'] as num?)?.toInt() ?? 75,
      safeIngredients: _parseItems(json['safe_ingredients']),
      cautionIngredients: _parseItems(json['caution_ingredients']),
      riskIngredients: _parseItems(json['risk_ingredients']),
      suitableSkinTypes:
          List<String>.from(json['suitable_skin_types'] as List? ?? []),
      avoidSkinTypes:
          List<String>.from(json['avoid_skin_types'] as List? ?? []),
      summary: json['summary'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      photoPath: json['photo_path'] as String?,
    );
  }

  static List<IngredientItem> _parseItems(dynamic list) {
    if (list == null) return [];
    return (list as List)
        .map((e) => IngredientItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mock 演示数据
  factory IngredientResult.mock() => IngredientResult(
        productName: '某品牌水乳套装',
        safetyLevel: '温和',
        safetyScore: 82,
        safeIngredients: [
          IngredientItem(
            name: '透明质酸钠',
            function: '保湿锁水',
            risk: RiskLevel.safe,
            note: '强效保湿，温和无刺激',
          ),
          IngredientItem(
            name: '烟酰胺',
            function: '提亮美白',
            risk: RiskLevel.safe,
            note: '高浓度（>5%）部分人会泛红',
          ),
          IngredientItem(
            name: '甘油',
            function: '保湿润肤',
            risk: RiskLevel.safe,
            note: '基础保湿成分，安全温和',
          ),
        ],
        cautionIngredients: [
          IngredientItem(
            name: '香精',
            function: '改善气味',
            risk: RiskLevel.caution,
            note: '敏感肌需注意，可能引起刺激',
          ),
          IngredientItem(
            name: '乙醇',
            function: '助渗透/清爽感',
            risk: RiskLevel.caution,
            note: '干性/敏感肌建议避开酒精成分',
          ),
        ],
        riskIngredients: [],
        suitableSkinTypes: ['油性肌', '混合性肌', '中性肌'],
        avoidSkinTypes: ['干性肌', '敏感肌'],
        summary: '整体成分较为温和，有效保湿提亮。含有香精和少量酒精，干皮和敏感肌需谨慎。',
        recommendation: '油皮混油皮适合使用，建议先局部测试。干皮敏感肌可以考虑换无香无醇的替代款。',
        createdAt: DateTime.now(),
      );

  /// 序列化为 JSON（用于本地存储）
  Map<String, dynamic> toJson() => {
        'product_name': productName,
        'safety_level': safetyLevel,
        'safety_score': safetyScore,
        'safe_ingredients': safeIngredients.map((e) => e.toJson()).toList(),
        'caution_ingredients':
            cautionIngredients.map((e) => e.toJson()).toList(),
        'risk_ingredients': riskIngredients.map((e) => e.toJson()).toList(),
        'suitable_skin_types': suitableSkinTypes,
        'avoid_skin_types': avoidSkinTypes,
        'summary': summary,
        'recommendation': recommendation,
        'created_at': createdAt.toIso8601String(),
        'photo_path': photoPath,
      };
}

/// 单个成分条目
class IngredientItem {
  final String name;       // 成分名称
  final String function;   // 功能描述
  final RiskLevel risk;    // 安全等级
  final String note;       // 补充说明

  const IngredientItem({
    required this.name,
    required this.function,
    required this.risk,
    required this.note,
  });

  factory IngredientItem.fromJson(Map<String, dynamic> json) =>
      IngredientItem(
        name: json['name'] as String? ?? '',
        function: json['function'] as String? ?? '',
        risk: _riskFromString(json['risk'] as String? ?? 'safe'),
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'function': function,
        'risk': risk.name,
        'note': note,
      };

  static RiskLevel _riskFromString(String s) {
    switch (s) {
      case 'caution':
        return RiskLevel.caution;
      case 'risk':
        return RiskLevel.risk;
      default:
        return RiskLevel.safe;
    }
  }
}

enum RiskLevel {
  safe,    // 安全
  caution, // 注意
  risk,    // 风险
}
