import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/storage_service.dart';
import '../../core/constants/app_routes.dart';

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════

class ProfileController extends GetxController {
  final nickname = ''.obs;
  final skinTone = Rx<SkinTone?>(null);
  final faceShape = Rx<FaceShape?>(null);
  final bodyShape = Rx<BodyShape?>(null);
  final styleType = Rx<StyleType?>(null);
  final seasonType = Rx<SeasonType?>(null);
  final ageGroup = Rx<AgeGroup?>(null);
  final clothingSize = Rx<ClothingSize?>(null);
  final height = Rx<int?>(null);
  final weight = Rx<int?>(null);
  final skinType = Rx<SkinType?>(null);
  final budget = Rx<BudgetLevel?>(null);
  final beautyBudget = Rx<BudgetLevel?>(null);
  final skinConcerns = <String>[].obs;
  final allergens = <String>[].obs;
  final occasions = <OccasionType>[].obs;
  final favoriteColors = <String>[].obs;
  final avoidColors = <String>[].obs;
  final city = ''.obs;

  final isSaving = false.obs;

  static const allSkinConcerns = [
    '痘痘', '毛孔粗大', '黑头', '暗沉', '干燥', '出油', '细纹',
    '色斑', '敏感泛红', '黑眼圈', '浮肿',
  ];
  static const allAllergens = [
    '酒精', '香精', '水杨酸', '果酸', '视黄醇', '烟酰胺',
    '防腐剂', '硅油', '矿油', '大豆提取物', '坚果提取物',
  ];

  // 常见颜色选项（用于偏好/避免）
  static const colorOptions = [
    ('黑色', '⬛'), ('白色', '⬜'), ('灰色', '🩶'), ('米白', '🤍'),
    ('粉色', '🩷'), ('红色', '❤️'), ('橙色', '🧡'), ('黄色', '💛'),
    ('绿色', '💚'), ('蓝色', '💙'), ('紫色', '💜'), ('棕色', '🤎'),
    ('驼色', '🫘'), ('墨绿', '🌿'), ('宝蓝', '🫐'), ('荧光', '🟡'),
  ];

  @override
  void onInit() {
    super.onInit();
    _loadProfile();
  }

  void _loadProfile() {
    final profile = StorageService.to.loadProfile();
    if (profile == null) return;
    nickname.value = profile.nickname;
    skinTone.value = profile.skinTone;
    faceShape.value = profile.faceShape;
    bodyShape.value = profile.bodyShape;
    styleType.value = profile.styleType;
    seasonType.value = profile.seasonType;
    ageGroup.value = profile.ageGroup;
    clothingSize.value = profile.clothingSize;
    height.value = profile.height;
    weight.value = profile.weight;
    skinType.value = profile.skinType;
    budget.value = profile.budget;
    beautyBudget.value = profile.beautyBudget;
    skinConcerns.value = List.from(profile.skinConcerns);
    allergens.value = List.from(profile.allergens);
    occasions.value = List.from(profile.occasions);
    favoriteColors.value = List.from(profile.favoriteColors);
    avoidColors.value = List.from(profile.avoidColors);
    city.value = profile.city ?? '';
  }

  void toggleSkinConcern(String c) => skinConcerns.contains(c) ? skinConcerns.remove(c) : skinConcerns.add(c);
  void toggleAllergen(String a) => allergens.contains(a) ? allergens.remove(a) : allergens.add(a);
  void toggleOccasion(OccasionType o) => occasions.contains(o) ? occasions.remove(o) : occasions.add(o);
  void toggleFavoriteColor(String c) => favoriteColors.contains(c) ? favoriteColors.remove(c) : favoriteColors.add(c);
  void toggleAvoidColor(String c) => avoidColors.contains(c) ? avoidColors.remove(c) : avoidColors.add(c);

  double get completionRate {
    int total = 11;
    int filled = 0;
    if (nickname.value.isNotEmpty) filled++;
    if (skinTone.value != null) filled++;
    if (faceShape.value != null) filled++;
    if (bodyShape.value != null) filled++;
    if (styleType.value != null) filled++;
    if (skinType.value != null) filled++;
    if (budget.value != null) filled++;
    if (ageGroup.value != null) filled++;
    if (clothingSize.value != null) filled++;
    if (occasions.isNotEmpty) filled++;
    if (favoriteColors.isNotEmpty) filled++;
    return filled / total;
  }

  Future<void> save() async {
    if (isSaving.value) return;
    isSaving.value = true;
    final existing = StorageService.to.loadProfile();
    final now = DateTime.now();
    final profile = UserProfile(
      id: existing?.id ?? now.millisecondsSinceEpoch.toString(),
      nickname: nickname.value.trim().isEmpty ? (existing?.nickname ?? 'MUSE用户') : nickname.value.trim(),
      skinTone: skinTone.value,
      faceShape: faceShape.value,
      bodyShape: bodyShape.value,
      styleType: styleType.value,
      seasonType: seasonType.value,
      ageGroup: ageGroup.value,
      clothingSize: clothingSize.value,
      height: height.value,
      weight: weight.value,
      skinType: skinType.value,
      budget: budget.value,
      beautyBudget: beautyBudget.value,
      skinConcerns: List.from(skinConcerns),
      allergens: List.from(allergens),
      occasions: List.from(occasions),
      favoriteColors: List.from(favoriteColors),
      avoidColors: List.from(avoidColors),
      city: city.value.trim().isEmpty ? null : city.value.trim(),
      favoriteCategories: existing?.favoriteCategories ?? [],
      facePhotoPath: existing?.facePhotoPath,
      fullBodyPhotoPath: existing?.fullBodyPhotoPath,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      isOnboardingComplete: true,
    );
    await StorageService.to.saveProfile(profile);
    isSaving.value = false;
    Get.back();
    Get.snackbar(
      '已保存',
      'MUSE 会根据你的新档案给出更精准的建议 ✨',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.primary.withOpacity(0.9),
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 14,
      duration: const Duration(seconds: 2),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ProfileController());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ctrl, isDark),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),
                _ProfileCompletion(ctrl: ctrl),
                const SizedBox(height: 16),
                _HistoryEntryCard(isDark: isDark),
                const SizedBox(height: 28),

                // ── 基本信息 ──
                _SectionTitle(title: '基本信息', icon: '👤'),
                const SizedBox(height: 12),
                _NicknameField(ctrl: ctrl, isDark: isDark),
                const SizedBox(height: 8),
                _CityField(ctrl: ctrl, isDark: isDark),
                const SizedBox(height: 12),
                _EnumChips<AgeGroup>(
                  label: '年龄段',
                  values: AgeGroup.values,
                  selected: ctrl.ageGroup,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.ageGroup.value = ctrl.ageGroup.value == e ? null : e,
                ),
                const SizedBox(height: 28),

                // ── 外貌特征 ──
                _SectionTitle(title: '外貌特征', icon: '🪞'),
                const SizedBox(height: 4),
                _SubTitle(text: '越完整，AI穿搭和美妆建议越精准'),
                const SizedBox(height: 12),
                _EnumChips<SkinTone>(
                  label: '肤色',
                  values: SkinTone.values,
                  selected: ctrl.skinTone,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.skinTone.value = ctrl.skinTone.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _EnumChips<FaceShape>(
                  label: '脸型',
                  values: FaceShape.values,
                  selected: ctrl.faceShape,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.faceShape.value = ctrl.faceShape.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _EnumChips<BodyShape>(
                  label: '身材类型',
                  values: BodyShape.values,
                  selected: ctrl.bodyShape,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.bodyShape.value = ctrl.bodyShape.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _EnumChips<SeasonType>(
                  label: '色彩季型',
                  values: SeasonType.values,
                  selected: ctrl.seasonType,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.seasonType.value = ctrl.seasonType.value == e ? null : e,
                ),
                const SizedBox(height: 28),

                // ── 身体数据 ──
                _SectionTitle(title: '身体数据', icon: '📐'),
                const SizedBox(height: 4),
                _SubTitle(text: '用于推荐合适版型和尺码'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _NumberField(
                      label: '身高 (cm)',
                      hint: '例如 165',
                      value: ctrl.height,
                      isDark: isDark,
                      min: 140, max: 220,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _NumberField(
                      label: '体重 (kg)',
                      hint: '例如 50',
                      value: ctrl.weight,
                      isDark: isDark,
                      min: 30, max: 150,
                    )),
                  ],
                ),
                const SizedBox(height: 12),
                _EnumChips<ClothingSize>(
                  label: '常穿尺码',
                  values: ClothingSize.values,
                  selected: ctrl.clothingSize,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.clothingSize.value = ctrl.clothingSize.value == e ? null : e,
                ),
                const SizedBox(height: 28),

                // ── 风格 & 场景 ──
                _SectionTitle(title: '风格与场景', icon: '✨'),
                const SizedBox(height: 12),
                _EnumChips<StyleType>(
                  label: '穿搭风格',
                  values: StyleType.values,
                  selected: ctrl.styleType,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.styleType.value = ctrl.styleType.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _MultiEnumChips<OccasionType>(
                  label: '常见穿搭场景（可多选）',
                  values: OccasionType.values,
                  selected: ctrl.occasions,
                  labelOf: (e) => e.label,
                  onToggle: ctrl.toggleOccasion,
                ),
                const SizedBox(height: 28),

                // ── 颜色偏好 ──
                _SectionTitle(title: '颜色偏好', icon: '🎨'),
                const SizedBox(height: 4),
                _SubTitle(text: '告诉 MUSE 你喜欢和排斥的颜色'),
                const SizedBox(height: 12),
                _ColorChips(
                  label: '喜欢的颜色（可多选）',
                  options: ProfileController.colorOptions,
                  selected: ctrl.favoriteColors,
                  onToggle: ctrl.toggleFavoriteColor,
                  activeColor: AppColors.primary,
                ),
                const SizedBox(height: 12),
                _ColorChips(
                  label: '不太接受的颜色（可多选）',
                  options: ProfileController.colorOptions,
                  selected: ctrl.avoidColors,
                  onToggle: ctrl.toggleAvoidColor,
                  activeColor: const Color(0xFFE57373),
                ),
                const SizedBox(height: 28),

                // ── 预算 ──
                _SectionTitle(title: '消费预算', icon: '💰'),
                const SizedBox(height: 12),
                _EnumChips<BudgetLevel>(
                  label: '服装/配饰（单件）',
                  values: BudgetLevel.values,
                  selected: ctrl.budget,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.budget.value = ctrl.budget.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _EnumChips<BudgetLevel>(
                  label: '护肤/美妆（单品）',
                  values: BudgetLevel.values,
                  selected: ctrl.beautyBudget,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.beautyBudget.value = ctrl.beautyBudget.value == e ? null : e,
                ),
                const SizedBox(height: 28),

                // ── 护肤信息 ──
                _SectionTitle(title: '护肤信息', icon: '🌿'),
                const SizedBox(height: 12),
                _EnumChips<SkinType>(
                  label: '肤质',
                  values: SkinType.values,
                  selected: ctrl.skinType,
                  labelOf: (e) => e.label,
                  onTap: (e) => ctrl.skinType.value = ctrl.skinType.value == e ? null : e,
                ),
                const SizedBox(height: 12),
                _MultiChips(
                  label: '皮肤问题（可多选）',
                  options: ProfileController.allSkinConcerns,
                  selected: ctrl.skinConcerns,
                  onToggle: ctrl.toggleSkinConcern,
                ),
                const SizedBox(height: 12),
                _MultiChips(
                  label: '过敏/排斥成分（可多选）',
                  options: ProfileController.allAllergens,
                  selected: ctrl.allergens,
                  onToggle: ctrl.toggleAllergen,
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
      bottomSheet: _SaveButton(ctrl: ctrl),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, ProfileController ctrl, bool isDark) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : AppColors.textPrimary, size: 20),
        onPressed: () => Get.back(),
      ),
      title: Text(
        '我的档案',
        style: TextStyle(
          color: isDark ? Colors.white : AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        Obx(() => TextButton(
              onPressed: ctrl.isSaving.value ? null : ctrl.save,
              child: Text(
                ctrl.isSaving.value ? '保存中...' : '保存',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            )),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  子组件
// ══════════════════════════════════════════════════════════════

class _ProfileCompletion extends StatelessWidget {
  final ProfileController ctrl;
  const _ProfileCompletion({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = ctrl.completionRate;
      String hint;
      if (p < 0.3) {
        hint = '填写更多信息，AI建议会准确很多 💡';
      } else if (p < 0.6) {
        hint = '不错！再填几项，解锁更精准的个性化建议 🎯';
      } else if (p < 1.0) {
        hint = '快完成啦！档案越完整，MUSE 越了解你 ✨';
      } else {
        hint = '档案已完整！MUSE 会给你最精准的专属建议 🎉';
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.12),
              AppColors.roseGold.withOpacity(0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('档案完成度',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                Text('${(p * 100).toInt()}%',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p,
                backgroundColor: AppColors.primary.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(hint,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
    });
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _SubTitle extends StatelessWidget {
  final String text;
  const _SubTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

class _NicknameField extends StatelessWidget {
  final ProfileController ctrl;
  final bool isDark;
  const _NicknameField({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: ctrl.nickname.value,
      onChanged: (v) => ctrl.nickname.value = v,
      decoration: _fieldDecoration('昵称', Icons.person_outline_rounded, isDark),
    );
  }
}

class _CityField extends StatelessWidget {
  final ProfileController ctrl;
  final bool isDark;
  const _CityField({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: ctrl.city.value,
      onChanged: (v) => ctrl.city.value = v,
      decoration: _fieldDecoration('所在城市（用于季节/气候建议）', Icons.location_on_outlined, isDark),
    );
  }
}

InputDecoration _fieldDecoration(String label, IconData icon, bool isDark) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

/// 数字输入框（身高/体重）
class _NumberField extends StatelessWidget {
  final String label;
  final String hint;
  final Rx<int?> value;
  final bool isDark;
  final int min;
  final int max;
  const _NumberField({
    required this.label,
    required this.hint,
    required this.value,
    required this.isDark,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() => TextFormField(
          key: ValueKey('${label}_${value.value}'),
          initialValue: value.value?.toString() ?? '',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= min && n <= max) {
              value.value = n;
            } else if (v.isEmpty) {
              value.value = null;
            }
          },
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ));
  }
}

/// 单选 Chip（枚举）
class _EnumChips<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final Rx<T?> selected;
  final String Function(T) labelOf;
  final void Function(T) onTap;

  const _EnumChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values.map((v) {
                final isSelected = selected.value == v;
                return GestureDetector(
                  onTap: () => onTap(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      labelOf(v),
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white : AppColors.primary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }
}

/// 多选 Chip（枚举）
class _MultiEnumChips<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final RxList<T> selected;
  final String Function(T) labelOf;
  final void Function(T) onToggle;

  const _MultiEnumChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values.map((v) {
                final isSel = selected.contains(v);
                return GestureDetector(
                  onTap: () => onToggle(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.primary : AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? AppColors.primary : AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Text(
                      labelOf(v),
                      style: TextStyle(
                        fontSize: 13,
                        color: isSel ? Colors.white : AppColors.primary,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }
}

/// 多选 Chip（字符串）
class _MultiChips extends StatelessWidget {
  final String label;
  final List<String> options;
  final RxList<String> selected;
  final void Function(String) onToggle;

  const _MultiChips({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((opt) {
                final isSel = selected.contains(opt);
                return GestureDetector(
                  onTap: () => onToggle(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.roseGold : AppColors.roseGold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? AppColors.roseGold : AppColors.roseGold.withOpacity(0.25),
                      ),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSel ? Colors.white : AppColors.roseGold,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }
}

/// 颜色偏好 Chip（带 emoji）
class _ColorChips extends StatelessWidget {
  final String label;
  final List<(String, String)> options; // (name, emoji)
  final RxList<String> selected;
  final void Function(String) onToggle;
  final Color activeColor;

  const _ColorChips({
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((item) {
                final (name, emoji) = item;
                final isSel = selected.contains(name);
                return GestureDetector(
                  onTap: () => onToggle(name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSel ? activeColor : activeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? activeColor : activeColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSel ? Colors.white : activeColor,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }
}

/// 历史诊断记录入口卡片
class _HistoryEntryCard extends StatelessWidget {
  final bool isDark;
  const _HistoryEntryCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    // 统计数量
    final analysisCount =
        StorageService.to.loadAnalysisHistory().length;
    final ingredientCount =
        StorageService.to.loadIngredientHistory().length;

    return GestureDetector(
      onTap: () => Get.toNamed(AppRoutes.history),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.08),
              AppColors.roseGold.withOpacity(0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.history_outlined,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的诊断记录',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    analysisCount + ingredientCount > 0
                        ? '形象诊断 $analysisCount 条 · 成分检测 $ingredientCount 条'
                        : '暂无记录，去诊断一下吧',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
    );
  }
}

/// 底部保存按钮
class _SaveButton extends StatelessWidget {
  final ProfileController ctrl;
  const _SaveButton({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Obx(() => SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: ctrl.isSaving.value ? null : ctrl.save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: ctrl.isSaving.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('保存档案',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          )),
    );
  }
}
