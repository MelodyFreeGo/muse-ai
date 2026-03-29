/// 商品模型
///
/// 商家后台录入后存储，AI 对话时查询匹配
class Product {
  final String id;
  final String name;          // 商品名称
  final String description;   // 商品详细介绍
  final String imageUrl;      // 商品图片（CDN地址或网络图）
  final String price;         // 展示价格，如 "¥299"
  final String buyUrl;        // 购买跳转链接（可以是淘宝/品牌官网/小程序链接）
  final ProductCategory category; // 商品分类
  final List<String> keywords;    // 关键词（用于意图匹配）
  final ProductMatchProfile match; // 适合人群标签
  final int weight;           // 推广权重 1-100，越高越优先

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.buyUrl,
    required this.category,
    required this.keywords,
    required this.match,
    this.weight = 10,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        imageUrl: j['image_url'] as String? ?? '',
        price: j['price'] as String? ?? '',
        buyUrl: j['buy_url'] as String? ?? '',
        category: ProductCategory.fromString(j['category'] as String? ?? ''),
        keywords: List<String>.from(j['keywords'] ?? []),
        match: ProductMatchProfile.fromJson(
            j['match'] as Map<String, dynamic>? ?? {}),
        weight: j['weight'] as int? ?? 10,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'price': price,
        'buy_url': buyUrl,
        'category': category.value,
        'keywords': keywords,
        'match': match.toJson(),
        'weight': weight,
      };
}

// ─── 商品分类 ───────────────────────────────────────────────────

enum ProductCategory {
  outfit('outfit', '服装'),
  lipstick('lipstick', '口红/彩妆'),
  skincare('skincare', '护肤'),
  beauty('beauty', '美妆'),
  accessory('accessory', '配饰'),
  bag('bag', '包包'),
  shoes('shoes', '鞋子'),
  other('other', '其他');

  const ProductCategory(this.value, this.label);
  final String value;
  final String label;

  static ProductCategory fromString(String s) =>
      ProductCategory.values.firstWhere(
        (e) => e.value == s,
        orElse: () => ProductCategory.other,
      );
}

// ─── 适合人群匹配条件 ───────────────────────────────────────────

class ProductMatchProfile {
  final List<String> styles;      // 适合风格，如 ['简约', '职场', 'ins风']
  final List<String> bodyShapes;  // 适合身材，如 ['梨形', '均匀']
  final List<String> skinTones;   // 适合肤色，如 ['冷白', '自然']
  final List<String> skinTypes;   // 适合肤质，如 ['油性', '敏感肌', '干性']
  final List<String> skinIssues;  // 适合肤况，如 ['痘痘', '暗沉', '泛红']
  final List<String> occasions;   // 适合场合，如 ['通勤', '约会']
  final List<String> colors;      // 颜色关键词，如 ['黑色', '深色']
  final int? budgetMin;           // 最低预算
  final int? budgetMax;           // 最高预算（可选）
  final List<String> seasons;     // 适合季节，如 ['春', '秋']
  final List<String> ageRanges;   // 适合年龄段，如 ['25+', '30+']

  const ProductMatchProfile({
    this.styles = const [],
    this.bodyShapes = const [],
    this.skinTones = const [],
    this.skinTypes = const [],
    this.skinIssues = const [],
    this.occasions = const [],
    this.colors = const [],
    this.budgetMin,
    this.budgetMax,
    this.seasons = const [],
    this.ageRanges = const [],
  });

  factory ProductMatchProfile.fromJson(Map<String, dynamic> j) =>
      ProductMatchProfile(
        styles: List<String>.from(j['styles'] ?? []),
        bodyShapes: List<String>.from(j['body_shapes'] ?? []),
        skinTones: List<String>.from(j['skin_tones'] ?? []),
        skinTypes: List<String>.from(j['skin_types'] ?? []),
        skinIssues: List<String>.from(j['skin_issues'] ?? []),
        occasions: List<String>.from(j['occasions'] ?? []),
        colors: List<String>.from(j['colors'] ?? []),
        budgetMin: j['budget_min'] as int?,
        budgetMax: j['budget_max'] as int?,
        seasons: List<String>.from(j['seasons'] ?? []),
        ageRanges: List<String>.from(j['age_ranges'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        'styles': styles,
        'body_shapes': bodyShapes,
        'skin_tones': skinTones,
        'skin_types': skinTypes,
        'skin_issues': skinIssues,
        'occasions': occasions,
        'colors': colors,
        if (budgetMin != null) 'budget_min': budgetMin,
        if (budgetMax != null) 'budget_max': budgetMax,
        'seasons': seasons,
        'age_ranges': ageRanges,
      };
}
