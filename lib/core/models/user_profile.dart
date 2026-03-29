/// 用户个人档案
class UserProfile {
  final String id;
  final String nickname;

  // ─── 外貌特征 ────────────────────────────────────────────
  final SkinTone? skinTone;
  final FaceShape? faceShape;
  final BodyShape? bodyShape;
  final StyleType? styleType;
  final SeasonType? seasonType; // 色彩季型

  // ─── 身体数据 ────────────────────────────────────────────
  final int? height;       // 身高 cm
  final int? weight;       // 体重 kg
  final ClothingSize? clothingSize; // 衣服尺码
  final AgeGroup? ageGroup; // 年龄段

  // ─── 偏好 ────────────────────────────────────────────────
  final List<String> favoriteColors;   // 喜欢的颜色
  final List<String> avoidColors;      // 不喜欢的颜色
  final List<OccasionType> occasions;  // 常见穿搭场景
  final BudgetLevel? budget;           // 服装预算
  final BudgetLevel? beautyBudget;     // 护肤/美妆预算（独立）
  final String? city;
  final List<String> favoriteCategories;

  // ─── 护肤信息 ────────────────────────────────────────────
  final SkinType? skinType;
  final List<String> skinConcerns; // 皮肤问题
  final List<String> allergens; // 过敏成分

  // ─── 档案照片 ────────────────────────────────────────────
  final String? facePhotoPath;
  final String? fullBodyPhotoPath;

  // ─── 元数据 ──────────────────────────────────────────────
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnboardingComplete;

  const UserProfile({
    required this.id,
    required this.nickname,
    this.skinTone,
    this.faceShape,
    this.bodyShape,
    this.styleType,
    this.seasonType,
    this.height,
    this.weight,
    this.clothingSize,
    this.ageGroup,
    this.favoriteColors = const [],
    this.avoidColors = const [],
    this.occasions = const [],
    this.budget,
    this.beautyBudget,
    this.skinType,
    this.skinConcerns = const [],
    this.allergens = const [],
    this.city,
    this.favoriteCategories = const [],
    this.facePhotoPath,
    this.fullBodyPhotoPath,
    required this.createdAt,
    required this.updatedAt,
    this.isOnboardingComplete = false,
  });

  UserProfile copyWith({
    String? nickname,
    SkinTone? skinTone,
    FaceShape? faceShape,
    BodyShape? bodyShape,
    StyleType? styleType,
    SeasonType? seasonType,
    int? height,
    int? weight,
    ClothingSize? clothingSize,
    AgeGroup? ageGroup,
    List<String>? favoriteColors,
    List<String>? avoidColors,
    List<OccasionType>? occasions,
    BudgetLevel? budget,
    BudgetLevel? beautyBudget,
    SkinType? skinType,
    List<String>? skinConcerns,
    List<String>? allergens,
    String? city,
    List<String>? favoriteCategories,
    String? facePhotoPath,
    String? fullBodyPhotoPath,
    bool? isOnboardingComplete,
  }) =>
      UserProfile(
        id: id,
        nickname: nickname ?? this.nickname,
        skinTone: skinTone ?? this.skinTone,
        faceShape: faceShape ?? this.faceShape,
        bodyShape: bodyShape ?? this.bodyShape,
        styleType: styleType ?? this.styleType,
        seasonType: seasonType ?? this.seasonType,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        clothingSize: clothingSize ?? this.clothingSize,
        ageGroup: ageGroup ?? this.ageGroup,
        favoriteColors: favoriteColors ?? this.favoriteColors,
        avoidColors: avoidColors ?? this.avoidColors,
        occasions: occasions ?? this.occasions,
        budget: budget ?? this.budget,
        beautyBudget: beautyBudget ?? this.beautyBudget,
        skinType: skinType ?? this.skinType,
        skinConcerns: skinConcerns ?? this.skinConcerns,
        allergens: allergens ?? this.allergens,
        city: city ?? this.city,
        favoriteCategories: favoriteCategories ?? this.favoriteCategories,
        facePhotoPath: facePhotoPath ?? this.facePhotoPath,
        fullBodyPhotoPath: fullBodyPhotoPath ?? this.fullBodyPhotoPath,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        isOnboardingComplete:
            isOnboardingComplete ?? this.isOnboardingComplete,
      );

  /// 生成标签列表（用于展示）
  List<String> get tags {
    final list = <String>[];
    if (skinTone != null) list.add(skinTone!.label);
    if (faceShape != null) list.add(faceShape!.label);
    if (bodyShape != null) list.add(bodyShape!.label);
    if (styleType != null) list.add(styleType!.label);
    if (skinType != null) list.add(skinType!.label);
    if (ageGroup != null) list.add(ageGroup!.label);
    if (clothingSize != null) list.add(clothingSize!.label);
    return list;
  }

  /// 档案完整度（0.0~1.0），用于 Profile 页进度条
  double get completionRate {
    int total = 11; // 总维度数
    int filled = 0;
    if (nickname.isNotEmpty) filled++;
    if (skinTone != null) filled++;
    if (faceShape != null) filled++;
    if (bodyShape != null) filled++;
    if (styleType != null) filled++;
    if (skinType != null) filled++;
    if (budget != null) filled++;
    if (ageGroup != null) filled++;
    if (clothingSize != null) filled++;
    if (occasions.isNotEmpty) filled++;
    if (favoriteColors.isNotEmpty) filled++;
    return filled / total;
  }
}

// ─── 枚举定义 ─────────────────────────────────────────────

enum SkinTone {
  coolWhite('冷白皮'),
  warmYellow('暖黄皮'),
  neutral('中性皮'),
  wheat('小麦色'),
  deep('深肤色');

  final String label;
  const SkinTone(this.label);
}

enum FaceShape {
  oval('鹅蛋脸'),
  round('圆脸'),
  square('方脸'),
  long('长脸'),
  heart('心形脸'),
  diamond('菱形脸');

  final String label;
  const FaceShape(this.label);
}

enum BodyShape {
  apple('苹果型'),
  pear('梨形'),
  hourglass('沙漏型'),
  rectangle('矩形'),
  invertedTriangle('倒三角');

  final String label;
  const BodyShape(this.label);
}

enum StyleType {
  sweet('甜美'),
  intellectual('知性'),
  cool('酷飒'),
  vintage('复古'),
  minimal('极简'),
  street('街头'),
  elegant('优雅'),
  sporty('运动');

  final String label;
  const StyleType(this.label);
}

enum SeasonType {
  spring('春型'),
  summer('夏型'),
  autumn('秋型'),
  winter('冬型');

  final String label;
  const SeasonType(this.label);
}

enum SkinType {
  dry('干性'),
  oily('油性'),
  combination('混合性'),
  sensitive('敏感肌'),
  acneProne('痘痘肌'),
  normal('中性');

  final String label;
  const SkinType(this.label);
}

enum BudgetLevel {
  affordable('平价 ¥0-200'),
  midRange('性价比 ¥200-800'),
  premium('轻奢 ¥800-3000'),
  luxury('奢侈 ¥3000+');

  final String label;
  const BudgetLevel(this.label);
}

/// 衣服尺码
enum ClothingSize {
  xs('XS'),
  s('S'),
  m('M'),
  l('L'),
  xl('XL'),
  xxl('XXL'),
  xxxl('3XL');

  final String label;
  const ClothingSize(this.label);
}

/// 年龄段
enum AgeGroup {
  teen('18岁以下'),
  youngAdult('18-24岁'),
  adult('25-30岁'),
  mature('31-40岁'),
  midAge('41-50岁'),
  senior('50岁以上');

  final String label;
  const AgeGroup(this.label);
}

/// 穿搭场景
enum OccasionType {
  daily('日常休闲'),
  commute('通勤上班'),
  date('约会出行'),
  party('派对聚会'),
  sport('运动健身'),
  travel('旅行度假'),
  formal('正式场合');

  final String label;
  const OccasionType(this.label);
}
