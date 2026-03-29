import 'dart:convert';
import 'package:flutter/services.dart';
import '../utils/app_error.dart';
import '../models/product.dart';
import '../models/user_profile.dart';

/// 商品匹配服务
///
/// 负责：
/// 1. 加载商品库（本地 JSON，未来换云端 API）
/// 2. 根据用户输入关键词 + 用户档案 → 多维度加权评分
/// 3. 按分数排序，返回最优 N 个商品
class ProductService {
  ProductService._();
  static final ProductService to = ProductService._();

  List<Product> _products = [];
  bool _loaded = false;

  // ─── 初始化 ───────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/products.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['products'] as List<dynamic>;
      _products = list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
      AppLogger.i('ProductService', '商品库加载完成，共 ${_products.length} 件');
    } catch (e, st) {
      AppLogger.e('ProductService', '商品库加载失败，将使用空列表', e, st);
      _products = [];
    }
  }

  // ─── 主查询接口 ───────────────────────────────────────────────

  /// 根据用户输入 + 用户档案，匹配最多 [limit] 个商品
  /// 返回空列表说明没有匹配商品，走 AI 自由回复
  Future<List<Product>> match({
    required String userMessage,
    required UserProfile? profile,
    int limit = 4,
  }) async {
    await init();
    if (_products.isEmpty) return [];

    final scored = <({Product product, double score})>[];

    for (final p in _products) {
      final score = _score(p, userMessage, profile);
      if (score > 0) {
        scored.add((product: p, score: score));
      }
    }

    if (scored.isEmpty) return [];

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.product).toList();
  }

  /// 降级匹配：按意图品类 + 用户档案推荐相近商品（忽略关键词门槛）
  /// 用于精确匹配无结果时，仍优先推荐自有商品库
  Future<List<Product>> matchByCategory({
    required String intent,
    required UserProfile? profile,
    int limit = 3,
  }) async {
    await init();
    if (_products.isEmpty) return [];

    // 意图 → 商品品类过滤
    final Set<ProductCategory> targetCats;
    switch (intent) {
      case 'lipstick':
        targetCats = {ProductCategory.lipstick, ProductCategory.beauty};
        break;
      case 'skin':
      case 'ingredient':
        targetCats = {ProductCategory.skincare, ProductCategory.beauty};
        break;
      case 'outfit':
      case 'weather':
      case 'occasion':
      case 'mood':
        targetCats = {
          ProductCategory.outfit, ProductCategory.accessory,
          ProductCategory.bag, ProductCategory.shoes
        };
        break;
      default:
        return [];
    }

    final candidates = _products
        .where((p) => targetCats.contains(p.category))
        .toList();

    if (candidates.isEmpty) return [];

    // 在品类内按档案打分（无关键词门槛）
    final scored = candidates.map((p) {
      double s = p.weight * 0.2; // 基础权重分

      // 当季加成
      final currentSeason = _getCurrentSeason();
      if (p.match.seasons.contains(currentSeason)) s += 10;

      if (profile != null) {
        // 风格匹配
        if (profile.styleType != null) {
          final userStyle = profile.styleType!.label;
          if (p.match.styles.any((st) =>
              userStyle.contains(st) || st.contains(userStyle))) s += 10;
        }
        // 肤色匹配（美妆类）
        if (profile.skinTone != null &&
            (p.category == ProductCategory.lipstick ||
                p.category == ProductCategory.beauty)) {
          final userSkin = profile.skinTone!.label;
          if (p.match.skinTones.any((st) =>
              userSkin.contains(st) || st.contains(userSkin))) s += 8;
        }
        // 肤质匹配（护肤类）
        if (profile.skinType != null &&
            (p.category == ProductCategory.skincare ||
                p.category == ProductCategory.beauty)) {
          final userSkinType = _skinTypeLabel(profile.skinType!);
          if (p.match.skinTypes.any((t) =>
              userSkinType.contains(t) || t.contains(userSkinType))) s += 10;
        }
        // 预算
        final userBudget = _parseBudgetMax(profile.budget?.label);
        if (userBudget != null) {
          final productPrice = _parsePrice(p.price);
          if (productPrice != null && productPrice > userBudget * 1.2) {
            s -= 30;
          }
        }
      }
      return (product: p, score: s);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored
        .where((e) => e.score > 0)
        .take(limit)
        .map((e) => e.product)
        .toList();
  }

  // ─── 多维度评分算法 ────────────────────────────────────────────

  /// 口语→关键词同义词扩展表（让自然语言更容易命中商品库）
  static const Map<String, List<String>> _synonyms = {
    // 服装通用
    '连衣裙': ['裙', '裙子', '连裙', '一件式'],
    '裤子': ['裤', '下装', '长裤'],
    '外套': ['大衣', '夹克', '风衣', '外搭', '上外'],
    '上衣': ['衬衫', '毛衣', 'T恤', '卫衣', '打底'],
    '衬衫': ['衬衣', '白衬衫', '棉衬'],
    '风衣': ['trench', '英伦外套', '长款外套'],
    '毛衣': ['针织', '针织衫', '针织毛衣', '针织上衣', '暖意'],
    '牛仔裤': ['牛仔', 'jeans', '直筒裤', '单宁'],
    '阔腿裤': ['阔腿', '宽腿裤', '宽裤'],
    // 颜色扩展
    '黑色': ['黑', '纯黑', '哑光黑', '炭黑'],
    '白色': ['白', '纯白', '奶白', '米白', '象牙白', '浅色'],
    '卡其': ['卡其色', '驼色', '米驼', '大地色'],
    '蓝色': ['蓝', '牛仔蓝', '深蓝', '浅蓝', '宝蓝'],
    // 彩妆护肤
    '口红': ['唇膏', '唇釉', '唇彩', '唇泥', '唇', 'lipstick'],
    '护肤': ['护肤品', '精华', '面霜', '爽肤水', '水乳'],
    '眼影': ['眼妆', '彩妆盘', '眼眸'],
    // 场合/使用场景
    '约会': ['相亲', '见男友', '见女友', '浪漫', '恋爱'],
    '通勤': ['上班', '职场', '工作', '公司'],
    '日常': ['平时', '逛街', '出门', '休闲'],
    '旅行': ['旅游', '出游', '度假', '踏青'],
    // 身材诉求
    '显瘦': ['遮肉', '藏肉', '减龄', '显高', '拉腿'],
    '显腿长': ['拉腿型', '显腿直', '腿部显瘦'],
  };

  /// 将用户消息扩展为包含同义词的增强查询词集合
  Set<String> _expandQuery(String msg) {
    final result = <String>{msg.toLowerCase()};
    for (final entry in _synonyms.entries) {
      // 如果用户消息中包含同义词，则将主词也加入搜索集合
      for (final syn in entry.value) {
        if (msg.contains(syn)) {
          result.add(entry.key.toLowerCase());
          result.add(syn.toLowerCase());
        }
      }
      // 如果用户消息包含主词，也把同义词加进去
      if (msg.contains(entry.key)) {
        for (final syn in entry.value) {
          result.add(syn.toLowerCase());
        }
      }
    }
    return result;
  }

  double _score(Product p, String userMsg, UserProfile? profile) {
    double score = 0;
    final msg = userMsg.toLowerCase();
    // ① 扩展查询词集合（含同义词）
    final expandedQuery = _expandQuery(msg);

    // ① 关键词命中（核心门槛）— 完全不命中直接排除
    int kwHits = 0;
    for (final kw in p.keywords) {
      final kwLower = kw.toLowerCase();
      // 直接匹配 or 同义词扩展匹配
      if (expandedQuery.any((q) => q.contains(kwLower) || kwLower.contains(q.split(' ').first))) {
        kwHits++;
      }
    }
    if (kwHits == 0) return 0;
    score += kwHits * 15; // 每个命中 +15分

    // ② 商品权重（推广优先级）— 权重1-100，最多 +20分
    score += p.weight * 0.2;

    // ③ 当季加成 — 当季商品 +10分
    final currentSeason = _getCurrentSeason();
    if (p.match.seasons.contains(currentSeason)) {
      score += 10;
    } else if (p.match.seasons.isNotEmpty &&
        !p.match.seasons.contains(currentSeason)) {
      score -= 5; // 反季轻微降权
    }

    // ④ 场合精准匹配 — 用户提到场合且商品支持 +12分
    const occasionKeywords = {
      '约会': '约会',
      '相亲': '约会',
      '通勤': '通勤',
      '上班': '通勤',
      '面试': '通勤',
      '职场': '通勤',
      '日常': '日常',
      '逛街': '逛街',
      '旅行': '旅行',
      '出游': '旅行',
      '聚会': '聚会',
      '派对': '聚会',
      '节日': '节日',
      '重要': '重要场合',
      '学校': '学校',
    };
    for (final entry in occasionKeywords.entries) {
      if (msg.contains(entry.key) &&
          p.match.occasions.contains(entry.value)) {
        score += 12;
        break;
      }
    }

    if (profile == null) return score;

    // ⑤ 风格匹配 — +10分
    if (profile.styleType != null) {
      final userStyle = profile.styleType!.label;
      if (p.match.styles.any(
          (s) => userStyle.contains(s) || s.contains(userStyle))) {
        score += 10;
      }
    }

    // ⑥ 身材匹配（服装类）— +8分
    if (profile.bodyShape != null &&
        p.category == ProductCategory.outfit) {
      final userBody = profile.bodyShape!.label;
      if (p.match.bodyShapes.any(
          (b) => userBody.contains(b) || b.contains(userBody))) {
        score += 8;
      }
    }

    // ⑦ 肤色匹配（美妆/口红类）— +8分
    if (profile.skinTone != null &&
        (p.category == ProductCategory.lipstick ||
            p.category == ProductCategory.beauty)) {
      final userSkin = profile.skinTone!.label;
      if (p.match.skinTones.any(
          (s) => userSkin.contains(s) || s.contains(userSkin))) {
        score += 8;
      }
    }

    // ⑧ 肤质匹配（护肤/美妆类）— +10分
    if (profile.skinType != null &&
        (p.category == ProductCategory.skincare ||
            p.category == ProductCategory.beauty ||
            p.category == ProductCategory.lipstick)) {
      final userSkinType = _skinTypeLabel(profile.skinType!);
      if (p.match.skinTypes.any((t) =>
          userSkinType.contains(t) || t.contains(userSkinType))) {
        score += 10;
      }
    }

    // ⑨ 肤况（skinIssues）匹配 — 每命中一个 +8分（上限 +24）
    if (profile.skinConcerns.isNotEmpty && p.match.skinIssues.isNotEmpty) {
      int issueHits = 0;
      for (final problem in profile.skinConcerns) {
        if (p.match.skinIssues.any(
            (i) => problem.contains(i) || i.contains(problem))) {
          issueHits++;
        }
      }
      // 也检查用户消息里提到的肤况
      for (final issue in p.match.skinIssues) {
        if (msg.contains(issue)) issueHits++;
      }
      score += (issueHits * 8).clamp(0, 24).toDouble();
    }

    // ⑩ 预算匹配 — 超出预算 -50分，在预算内 +5分
    final userBudget = _parseBudgetMax(profile.budget?.label);
    if (userBudget != null) {
      final productPrice = _parsePrice(p.price);
      if (productPrice != null) {
        if (productPrice > userBudget * 1.2) {
          score -= 50;
        } else if (productPrice <= userBudget) {
          score += 5;
        }
      }
    }

    // ⑪ 颜色偏好匹配 — +6分
    if (profile.favoriteColors.isNotEmpty) {
      for (final favColor in profile.favoriteColors) {
        if (p.match.colors
                .any((c) => c.contains(favColor) || favColor.contains(c)) ||
            msg.contains(favColor)) {
          score += 6;
          break;
        }
      }
    }

    // ⑫ 用户消息中明确提到颜色且与商品关键词匹配 — +10分
    for (final kw in p.keywords) {
      if (_isColorWord(kw) && msg.contains(kw)) {
        score += 10;
      }
    }

    // ⑬ 排斥颜色检查 — -30分
    if (profile.avoidColors.isNotEmpty) {
      for (final avoidColor in profile.avoidColors) {
        if (p.keywords.any((k) => k.contains(avoidColor))) {
          score -= 30;
          break;
        }
      }
    }

    return score;
  }

  // ─── 辅助方法 ──────────────────────────────────────────────────

  /// 获取当前季节
  String _getCurrentSeason() {
    final month = DateTime.now().month;
    if (month >= 3 && month <= 5) return '春';
    if (month >= 6 && month <= 8) return '夏';
    if (month >= 9 && month <= 11) return '秋';
    return '冬';
  }

  /// SkinType 枚举 → 中文标签
  String _skinTypeLabel(SkinType st) {
    switch (st) {
      case SkinType.oily:
        return '油性';
      case SkinType.dry:
        return '干性';
      case SkinType.combination:
        return '混合性';
      case SkinType.sensitive:
        return '敏感肌';
      case SkinType.acneProne:
        return '痘痘肌';
      case SkinType.normal:
        return '正常';
    }
  }

  /// 解析价格字符串，返回数字，如 "¥299" → 299
  double? _parsePrice(String price) {
    final clean = price.replaceAll(RegExp(r'[¥￥,，\s]'), '');
    final parts = clean.split(RegExp(r'[-~—]'));
    return double.tryParse(parts.first);
  }

  /// 解析预算上限，如 "200-500元" → 500，"500以内" → 500
  int? _parseBudgetMax(String? budgetLabel) {
    if (budgetLabel == null) return null;
    final nums = RegExp(r'\d+')
        .allMatches(budgetLabel)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (nums.isEmpty) return null;
    return nums.last;
  }

  bool _isColorWord(String kw) {
    const colors = [
      '黑', '白', '红', '蓝', '绿', '黄', '粉', '紫',
      '棕', '卡其', '米', '灰', '橙', '裸', '豆沙'
    ];
    return colors.any((c) => kw.contains(c));
  }
}
