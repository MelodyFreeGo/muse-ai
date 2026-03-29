import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/app_error.dart';
import '../models/user_profile.dart';
import '../models/analysis_result.dart';
import '../models/ingredient_result.dart';

/// 本地持久化服务（单例 GetxService 风格，通过 StorageService.to 访问）
class StorageService {
  static StorageService? _instance;
  static StorageService get to => _instance ??= StorageService._();
  StorageService._();

  static const _keyProfile = 'muse_user_profile';
  static const _keyAdvisor = 'muse_selected_advisor';
  static const _keyOnboardingDone = 'muse_onboarding_done';
  static const _keyAnalysisHistory = 'muse_analysis_history';
  static const _keyIngredientHistory = 'muse_ingredient_history';
  static const _keyChatHistory = AppConfig.kChatHistory;

  late SharedPreferences _prefs;

  /// 必须在 main() 中 await 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 暴露 prefs 供外部直接读写（如主题模式、衣橱缓存清除等）
  Future<SharedPreferences> getPrefs() async => _prefs;

  // ─── Onboarding 状态 ──────────────────────────────────────

  bool get isOnboardingDone => _prefs.getBool(_keyOnboardingDone) ?? false;

  Future<void> setOnboardingDone() =>
      _prefs.setBool(_keyOnboardingDone, true);

  // ─── 用户档案 ─────────────────────────────────────────────

  UserProfile? loadProfile() {
    final json = _prefs.getString(_keyProfile);
    if (json == null) return null;
    try {
      return _profileFromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final json = jsonEncode(_profileToJson(profile));
    await _prefs.setString(_keyProfile, json);
  }

  Future<void> clearProfile() async {
    await _prefs.remove(_keyProfile);
    await _prefs.remove(_keyOnboardingDone);
  }

  // ─── 上次选择的助理角色 ───────────────────────────────────

  String? loadAdvisor() => _prefs.getString(_keyAdvisor);

  Future<void> saveAdvisor(String advisorName) =>
      _prefs.setString(_keyAdvisor, advisorName);

  // ─── 形象诊断历史 ──────────────────────────────────────────

  /// 加载所有历史诊断报告（最新在前，最多20条）
  List<AnalysisResult> loadAnalysisHistory() {
    final raw = _prefs.getString(_keyAnalysisHistory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AnalysisResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存一条新的诊断结果（自动插到最前面，最多保留20条）
  Future<void> saveAnalysisResult(AnalysisResult result) async {
    final history = loadAnalysisHistory();
    history.insert(0, result);
    final trimmed = history.take(20).toList();
    await _prefs.setString(
      _keyAnalysisHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearAnalysisHistory() =>
      _prefs.remove(_keyAnalysisHistory);

  // ─── 成分检测历史 ──────────────────────────────────────────

  /// 加载成分检测历史（最新在前，最多30条）
  List<IngredientResult> loadIngredientHistory() {
    final raw = _prefs.getString(_keyIngredientHistory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => IngredientResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存一条新的成分检测结果
  Future<void> saveIngredientResult(IngredientResult result) async {
    final history = loadIngredientHistory();
    history.insert(0, result);
    final trimmed = history.take(30).toList();
    await _prefs.setString(
      _keyIngredientHistory,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearIngredientHistory() =>
      _prefs.remove(_keyIngredientHistory);

  // ─── 对话历史（AI 上下文持久化）─────────────────────────────

  /// 加载持久化的对话历史（用于 AI 上下文注入）
  ///
  /// 格式：[{"role":"user","content":"..."}, {"role":"assistant","content":"..."}]
  List<Map<String, String>> loadChatHistory() {
    final raw = _prefs.getString(_keyChatHistory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (e) {
      AppLogger.w('StorageService', '加载对话历史失败，已清空', e);
      _prefs.remove(_keyChatHistory);
      return [];
    }
  }

  /// 保存对话历史（自动截断至最近 N 轮，防止无限增长）
  Future<void> saveChatHistory(List<Map<String, String>> history) async {
    final maxPairs = AppConfig.persistedHistoryPairs;
    final maxItems = maxPairs * 2; // 每轮 = user + assistant 各1条
    final trimmed = history.length > maxItems
        ? history.sublist(history.length - maxItems)
        : history;
    await _prefs.setString(
      _keyChatHistory,
      jsonEncode(trimmed),
    );
  }

  /// 清除对话历史
  Future<void> clearChatHistory() => _prefs.remove(_keyChatHistory);



  Map<String, dynamic> _profileToJson(UserProfile p) => {
        'id': p.id,
        'nickname': p.nickname,
        'skinTone': p.skinTone?.name,
        'faceShape': p.faceShape?.name,
        'bodyShape': p.bodyShape?.name,
        'styleType': p.styleType?.name,
        'seasonType': p.seasonType?.name,
        // 身体数据
        'height': p.height,
        'weight': p.weight,
        'clothingSize': p.clothingSize?.name,
        'ageGroup': p.ageGroup?.name,
        // 偏好
        'favoriteColors': p.favoriteColors,
        'avoidColors': p.avoidColors,
        'occasions': p.occasions.map((e) => e.name).toList(),
        'budget': p.budget?.name,
        'beautyBudget': p.beautyBudget?.name,
        // 护肤
        'skinType': p.skinType?.name,
        'skinConcerns': p.skinConcerns,
        'allergens': p.allergens,
        // 其他
        'city': p.city,
        'favoriteCategories': p.favoriteCategories,
        'facePhotoPath': p.facePhotoPath,
        'fullBodyPhotoPath': p.fullBodyPhotoPath,
        'createdAt': p.createdAt.toIso8601String(),
        'updatedAt': p.updatedAt.toIso8601String(),
        'isOnboardingComplete': p.isOnboardingComplete,
      };

  UserProfile _profileFromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        nickname: j['nickname'] as String,
        skinTone: _enumFromName(SkinTone.values, j['skinTone']),
        faceShape: _enumFromName(FaceShape.values, j['faceShape']),
        bodyShape: _enumFromName(BodyShape.values, j['bodyShape']),
        styleType: _enumFromName(StyleType.values, j['styleType']),
        seasonType: _enumFromName(SeasonType.values, j['seasonType']),
        height: j['height'] as int?,
        weight: j['weight'] as int?,
        clothingSize: _enumFromName(ClothingSize.values, j['clothingSize']),
        ageGroup: _enumFromName(AgeGroup.values, j['ageGroup']),
        favoriteColors: List<String>.from(j['favoriteColors'] ?? []),
        avoidColors: List<String>.from(j['avoidColors'] ?? []),
        occasions: (j['occasions'] as List<dynamic>? ?? [])
            .map((e) => _enumFromName(OccasionType.values, e as String))
            .whereType<OccasionType>()
            .toList(),
        budget: _enumFromName(BudgetLevel.values, j['budget']),
        beautyBudget: _enumFromName(BudgetLevel.values, j['beautyBudget']),
        skinType: _enumFromName(SkinType.values, j['skinType']),
        skinConcerns: List<String>.from(j['skinConcerns'] ?? []),
        allergens: List<String>.from(j['allergens'] ?? []),
        city: j['city'] as String?,
        favoriteCategories: List<String>.from(j['favoriteCategories'] ?? []),
        facePhotoPath: j['facePhotoPath'] as String?,
        fullBodyPhotoPath: j['fullBodyPhotoPath'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        isOnboardingComplete: j['isOnboardingComplete'] as bool? ?? false,
      );

  T? _enumFromName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    try {
      return values.firstWhere((e) => e.name == name);
    } catch (_) {
      return null;
    }
  }
}
