import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../utils/app_error.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../models/analysis_result.dart';
import '../models/ingredient_result.dart';
import '../models/product.dart';
import 'weather_service.dart';
import 'product_service.dart';
import 'storage_service.dart';

extension _IntLet on int {
  T let<T>(T Function(int) f) => f(this);
}

/// AI 服务 v2
///
/// 架构：三层智能路由
///   Layer 1 — Intent:     本地关键词 + 场景识别（含天气/情绪/场合）
///   Layer 2 — Memory:     对话中自动提取档案信息（肤色/身材/风格等）
///   Layer 3 — LLM Chat:   DeepSeek 精调 Prompt，档案全量注入，强制个性化
///
/// 新增能力：
///   - 场景意图：今天穿什么/约会/上班/出门 → 自动关联场合和天气建议
///   - 情绪感知：心情不好/无聊/减压 → 给出治愈系回复 + 穿搭情绪价值
///   - 档案追问：关键字段缺失时主动追问，而非给泛泛建议
///   - 动态 chip：AI 生成快捷回复，而非写死规则
///   - 对话记忆：从聊天中解析并缓存用户信息更新意图
class AiService {
  AiService._();
  static final AiService to = AiService._();

  // ── 对外暴露实时季节工具（供其他 Controller 使用）──────────────
  static String get currentSeason => _getRealSeason();
  static String get currentSeasonChar => _getRealSeasonChar();
  static String get currentTimeOfDay => _getTimeOfDay();

  // ══════════════════════════════════════════════════════════════
  //  ⚙️  配置区（全部迁移至 AppConfig，此处仅做别名引用）
  // ══════════════════════════════════════════════════════════════

  static const _deepSeekKey   = AppConfig.deepSeekKey;
  static const _deepSeekBase  = AppConfig.deepSeekBase;
  static const _deepSeekModel = AppConfig.deepSeekModel;

  static const _visionKey   = AppConfig.dashscopeKey;
  static const _visionBase  = AppConfig.visionBase;
  static const _visionModel = AppConfig.visionModel;

  // ══════════════════════════════════════════════════════════════

  static const _timeout = AppConfig.llmTimeout;

  // ─── 意图枚举 ─────────────────────────────────────────────────

  static const _intentOutfit      = 'outfit';       // 穿搭建议
  static const _intentLipstick    = 'lipstick';     // 口红/彩妆
  static const _intentSkin        = 'skin';         // 护肤建议
  static const _intentIngredient  = 'ingredient';   // 成分检测
  static const _intentPhoto       = 'photo';        // 拍照分析
  static const _intentWeather     = 'weather';      // 天气穿搭
  static const _intentOccasion    = 'occasion';     // 场合穿搭（约会/通勤/派对）
  static const _intentMood        = 'mood';         // 情绪/心情相关
  static const _intentProfile     = 'profile_ask';  // 用户主动询问或更新档案
  static const _intentChat        = 'chat';         // 闲聊/其他

  // ─── 公开 API ─────────────────────────────────────────────────

  /// 分析用户输入，返回 [AiResponse]
  Future<AiResponse> analyze({
    required String userMessage,
    required UserProfile? profile,
    String? imagePath,
    Uint8List? imageBytes,
    List<Map<String, String>> history = const [],
  }) async {
    final intent = _detectIntent(userMessage);

    // 检测是否是"编辑/补充档案"类请求（而非查询）
    final isProfileEditRequest = _match(
      userMessage.toLowerCase(),
      ['继续补充', '编辑档案', '修改档案', '更新档案', '修改信息', '完善档案',
       '修改一下档案', '编辑一下档案', '更新一下档案', '改一下档案', '改档案',
       '我要改档案', '我要编辑档案', '我要修改档案', '我要更新档案',
       '改风格', '改身材', '改肤质', '改预算', '改年龄', '改城市']
    );
    AppLogger.d('AiService', '用户消息: "$userMessage", isProfileEditRequest: $isProfileEditRequest');

    // ── 实时天气（先拉后注入 Prompt，让 AI 能真正说出今天天气）──
    WeatherData? weather;
    final cityName = profile?.city?.isNotEmpty == true ? profile!.city : null;
    if (cityName != null) {
      weather = await WeatherService.to.fetchWeather(cityName);
    }

    // ── 商品库优先匹配（只对有商品卡片的意图生效）──────────────
    List<Product> matchedProducts = [];
    List<Product> fallbackProducts = []; // 降级相近商品
    final isProductIntent = (intent == _intentOutfit ||
        intent == _intentWeather || intent == _intentOccasion ||
        intent == _intentMood || intent == _intentLipstick ||
        intent == _intentSkin || intent == _intentIngredient);

    if (isProductIntent) {
      // 精确匹配
      matchedProducts = await ProductService.to.match(
        userMessage: userMessage,
        profile: profile,
        limit: 4,
      );
      // 无精确匹配 → 降级：找同品类商品（忽略关键词门槛）
      if (matchedProducts.isEmpty) {
        fallbackProducts = await ProductService.to.matchByCategory(
          intent: intent,
          profile: profile,
          limit: 3,
        );
      }
    }

    final messages = _buildMessages(
      intent: intent,
      userMessage: userMessage,
      profile: profile,
      history: history,
      weather: weather,
      isProfileEditRequest: isProfileEditRequest,
      matchedProducts: matchedProducts,
      fallbackProducts: fallbackProducts,
    );

    final raw = await _callLLM(messages);
    if (raw == null) {
      return AiResponse.error('网络好像不太好，稍后再试试～');
    }
    // 结构化错误前缀（来自 _callLLM 的 AppException）
    if (raw.startsWith('__error__:')) {
      return AiResponse.error(raw.substring('__error__:'.length));
    }

    // 如果有商品库精确匹配，直接用库中商品构造卡片，不依赖 AI 自由生成
    if (matchedProducts.isNotEmpty) {
      final profileHints = _extractProfileHints(userMessage, raw);
      // 先从 AI 回复提取文字摘要
      final aiText = _extractReplyText(raw);
      final cards = matchedProducts.map((p) => ResultCard(
        id: '${p.id}_${DateTime.now().millisecondsSinceEpoch}',
        type: _cardTypeFromProduct(p),
        title: p.name,
        subtitle: p.description,
        tags: _tagsFromProduct(p),
        price: p.price,
        buyUrl: p.buyUrl,
        imageUrl: p.imageUrl,
        isOwnProduct: true, // 标记为自有商品
      )).toList();
      return AiResponse(
        reply: aiText,
        cards: cards,
        quickReplies: const [],
      ).copyWithHints(profileHints);
    }

    // 有降级商品（品类相关但关键词不完全匹配）→ AI 解释 + 附上相近商品
    if (fallbackProducts.isNotEmpty) {
      final profileHints = _extractProfileHints(userMessage, raw);
      final aiText = _extractReplyText(raw);
      final cards = fallbackProducts.map((p) => ResultCard(
        id: '${p.id}_fb_${DateTime.now().millisecondsSinceEpoch}',
        type: _cardTypeFromProduct(p),
        title: p.name,
        subtitle: p.description,
        tags: _tagsFromProduct(p),
        price: p.price,
        buyUrl: p.buyUrl,
        imageUrl: p.imageUrl,
        isOwnProduct: true,
      )).toList();
      return AiResponse(
        reply: aiText,
        cards: cards,
        quickReplies: const [],
      ).copyWithHints(profileHints);
    }

    final response = _parseResponse(raw, intent);

    // 尝试从对话中提取档案信息（返回给上层，由 HomeController 决定是否更新）
    final profileHints = _extractProfileHints(userMessage, raw);

    return response.copyWithHints(profileHints);
  }

  /// 从 AI 回复中提取纯文字摘要（去掉 JSON 块）
  String _extractReplyText(String raw) {
    // 先尝试从 JSON 提取 reply 字段
    final extracted = _extractJson(raw);
    if (extracted != null) {
      try {
        final json = jsonDecode(extracted) as Map<String, dynamic>;
        final reply = json['reply'] as String?;
        if (reply != null && reply.isNotEmpty) return reply;
      } catch (_) {}
    }
    // 无 JSON → 去掉代码块标记，返回纯文字（截断到200字）
    final clean = raw
        .replaceAll(RegExp(r'```json[\s\S]*?```'), '')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .trim();
    return clean.length > 200 ? '${clean.substring(0, 200)}...' : clean;
  }

  /// Product → CardType 映射
  CardType _cardTypeFromProduct(Product p) {
    switch (p.category) {
      case ProductCategory.outfit:
        return CardType.outfit;
      case ProductCategory.lipstick:
        return CardType.lipstick;
      case ProductCategory.skincare:
      case ProductCategory.beauty:
        return CardType.skincare;
      default:
        return CardType.outfit;
    }
  }

  /// Product → 展示标签
  List<String> _tagsFromProduct(Product p) {
    final tags = <String>[];
    if (p.match.seasons.isNotEmpty) tags.add('${p.match.seasons.first}季');
    if (p.match.occasions.isNotEmpty) tags.add(p.match.occasions.first);
    if (p.match.colors.isNotEmpty) tags.add(p.match.colors.first);
    tags.add('自营推荐');
    return tags.take(3).toList();
  }

  // ─── 意图识别 ──────────────────────────────────────────────────

  String _detectIntent(String text) {
    final t = text.toLowerCase();

    // ① 成分检测（最高优先——避免被护肤拦截）
    if (_match(t, ['成分', '配方', '成分表', '能不能用', '适不适合', '有没有酒精',
                   '含不含', '成分安不安全', '防腐剂', '香精', '角鲨烷',
                   'ingredient', '刺激成分', '禁忌成分', '孕妇能用吗',
                   '这个产品安全吗', '查一下成分', '帮我看成分'])) {
      return _intentIngredient;
    }

    // ② 天气穿搭
    if (_match(t, ['天气', '下雨', '下雪', '高温', '低温', '阴天', '晴天',
                   '气温', '几度', '温差', '潮湿', '换季',
                   '好热', '好冷', '凉快', '暖和', '闷热', '湿冷', '冻死',
                   '热死', '刮风', '台风', '大风', '今天多少度', '穿多少',
                   '穿厚', '穿薄', '加件外套', '要带伞吗', '今天冷不冷',
                   '要穿羽绒服吗', '能穿裙子吗', '穿什么面料'])) {
      return _intentWeather;
    }

    // ③ 场合穿搭（扩展节日/特定人物/特殊场景）
    if (_match(t, ['约会', '相亲', '见家长', '见男友', '见女友', '见对象',
                   '派对', '聚会', '婚礼', '面试', '演讲', '发言',
                   '毕业典礼', '年会', '颁奖', '出游', '旅行', '度假',
                   '健身', '运动', '瑜伽', '跑步', '徒步', '露营',
                   '上班', '通勤', '复工', '节后上班', '开学',
                   '今天穿什么', '明天穿什么', '后天穿什么', '穿去哪',
                   '五一', '十一', '国庆', '元旦', '春节', '情人节',
                   '七夕', '圣诞', '跨年', '平安夜',
                   '送礼', '送男友', '送女友', '送闺蜜', '送妈妈',
                   '生日', '纪念日', '毕业', '拍大头贴', '拍写真',
                   '同学聚会', '家庭聚餐', '闺蜜聚会', '商务宴请',
                   '参加婚宴', '伴娘', '出席活动', '走红毯'])) {
      return _intentOccasion;
    }

    // ④ 情绪/心情（口语化词扩充）
    if (_match(t, ['心情不好', '难过', '不开心', '郁闷', '想美美的',
                   '要出风头', '减压', '治愈', '没状态', '无聊', '烦',
                   '想改变', '换个心情', '开心一下', '今天很累', '心情差',
                   '沮丧', '焦虑', '想出风头', '让我美美的', '提振精神',
                   '给我力量', '振作起来', '治愈系', '心塞', 'emo',
                   '想被夸', '想被看见', '今天状态好', '今天很美'])) {
      return _intentMood;
    }

    // ⑤ 彩妆/口红（扩展：具体产品/妆容场景）
    if (_match(t, ['口红', '唇膏', '唇彩', '唇釉', '唇泥', '唇蜜',
                   '眼影', '眼线', '眼妆', '粉底', '粉底液', '气垫',
                   '腮红', '高光', '修容', '散粉', '定妆',
                   'lipstick', 'makeup', '彩妆',
                   '色号', '试色', '显白', '显黑', '适合我的色号',
                   '美瞳', '睫毛膏', '睫毛', '眉毛', '眉笔',
                   '什么色号好看', '口红推荐', '彩妆推荐',
                   '日常妆', '约会妆', '职场妆', '气色', '涂什么口红'])) {
      return _intentLipstick;
    }

    // ⑥ 皮肤/护肤（扩展：产品品类/功效词）
    if (_match(t, ['皮肤', '肤质', '护肤', '精华', '面霜', '乳液', '爽肤水',
                   '防晒', '防晒霜', '防晒乳', '防晒喷雾',
                   '痘', '痤疮', '毛孔', '黑头', '白头',
                   '补水', '保湿', '抗老', '抗衰', '暗沉', '敏感肌',
                   'skincare', '护肤品', '面膜', '精华液', '水乳',
                   '洁面', '卸妆', '屏障', '美白', '淡斑', '紧致', '去皱',
                   '遮瑕', '隔离', '妆前乳', '油皮', '干皮', '混皮',
                   '刷酸', '烟酰胺', '玻尿酸', '胶原蛋白', '视黄醇',
                   '早c晚a', '精华推荐', '护肤推荐', '皮肤不好'])) {
      return _intentSkin;
    }

    // ⑦ 普通穿搭（扩展：颜色/材质/价格/身材诉求）
    if (_match(t, ['穿', '搭', '衣', '裤', '裙', '外套', '上衣', '穿搭', '搭配',
                   'outfit', 'wear', '单品', '怎么穿', '怎么搭',
                   '显瘦', '显高', '遮肉', '显腿', '拉腿',
                   '棉', '麻', '丝', '雪纺', '针织', '牛仔', '皮革',
                   '黑色穿搭', '白色穿搭', '米色', '莫兰迪',
                   '平价', '百元', '千元', '轻奢', '大牌平替',
                   '梨形', '苹果型', '沙漏', '长腿', '高个',
                   '法式', '韩系', '日系', '美式', '复古', 'ins风',
                   '简约', '通勤风', '学院风', '街头'])) {
      return _intentOutfit;
    }

    // ⑧ 图片
    if (_match(t, ['拍', '照片', '图片', '这个', '这件', '帮我看', '分析图',
                   '看看这套', '这个颜色', '这件衣服'])) {
      return _intentPhoto;
    }

    // ⑨ 档案查询/更新（优先于chat，避免被闲聊吞掉）
    if (_match(t, ['我的档案', '查看档案', '档案信息', '我的信息', '个人信息',
                   '档案完整', '档案填', '帮我查档案', '档案里', '我有哪些信息',
                   '你知道我哪些', '你了解我多少', '我的资料',
                   '继续补充档案', '我要继续补充档案', '怎么补充档案', '补充档案',
                   '编辑档案', '修改档案', '更新档案', '修改信息', '完善档案'])) {
      return _intentProfile;
    }

    return _intentChat;
  }

  bool _match(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  // ─── Prompt 构建 ──────────────────────────────────────────────

  List<Map<String, String>> _buildMessages({
    required String intent,
    required String userMessage,
    required UserProfile? profile,
    required List<Map<String, String>> history,
    WeatherData? weather,
    List<Product> matchedProducts = const [],
    List<Product> fallbackProducts = const [],
    bool isProfileEditRequest = false,
  }) {
    // ── 从 history 中提取对话内已透露的用户信息，避免 AI 重复追问 ──
    final conversationHints = _extractHintsFromHistory(history);

    final systemPrompt = _buildSystemPrompt(
      intent, profile, userMessage,
      weather: weather,
      matchedProducts: matchedProducts,
      fallbackProducts: fallbackProducts,
      conversationHints: conversationHints,
      history: history,
      isProfileEditRequest: isProfileEditRequest,
    );
    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // 带入历史（最近10条，保持更好的上下文）
    final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
    msgs.addAll(recent);
    msgs.add({'role': 'user', 'content': userMessage});
    return msgs;
  }

  /// 从历史对话中提取用户已告知的偏好/特征信息（用于防止重复追问）
  Map<String, String> _extractHintsFromHistory(List<Map<String, String>> history) {
    final hints = <String, String>{};
    // 只扫 user 角色的消息
    for (final msg in history) {
      if (msg['role'] == 'user') {
        final extracted = _extractProfileHints(msg['content'] ?? '', '');
        hints.addAll(extracted);
      }
    }
    return hints;
  }

  // ─── 实时时间/季节工具 ───────────────────────────────────────────

  /// 获取当前真实季节标签
  static String _getRealSeason() {
    final month = DateTime.now().month;
    if (month >= 3 && month <= 5) return '春季';
    if (month >= 6 && month <= 8) return '夏季';
    if (month >= 9 && month <= 11) return '秋季';
    return '冬季';
  }

  /// 获取当前真实季节单字（用于搜索关键词）
  static String _getRealSeasonChar() {
    final month = DateTime.now().month;
    if (month >= 3 && month <= 5) return '春';
    if (month >= 6 && month <= 8) return '夏';
    if (month >= 9 && month <= 11) return '秋';
    return '冬';
  }

  /// 获取当前时段标签（早晨/上午/中午/下午/傍晚/晚上/深夜）
  static String _getTimeOfDay() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 9)  return '早晨';
    if (h >= 9 && h < 12) return '上午';
    if (h >= 12 && h < 14) return '中午';
    if (h >= 14 && h < 18) return '下午';
    if (h >= 18 && h < 20) return '傍晚';
    if (h >= 20 && h < 23) return '晚上';
    return '深夜';
  }

  /// 获取当前节假日/节日感知（返回 null 表示普通日子）
  static String? _detectHoliday() {
    final now = DateTime.now();
    final m = now.month;
    final d = now.day;
    final weekday = now.weekday; // 1=周一, 7=周日

    // ── 固定日期节日 ──
    if (m == 2 && d == 14) return '情人节';
    if (m == 3 && d == 8) return '三八妇女节';
    if (m == 5 && d == 1) return '五一劳动节';
    if (m == 5 && d >= 1 && d <= 5) return '五一假期';
    if (m == 6 && d == 1) return '六一儿童节';
    if (m == 7 && d == 7) return '七夕情人节';
    if (m == 10 && d == 1) return '国庆节';
    if (m == 10 && d >= 1 && d <= 7) return '国庆假期';
    if (m == 12 && d == 24) return '平安夜';
    if (m == 12 && d == 25) return '圣诞节';
    if (m == 12 && d == 31) return '跨年夜';
    if (m == 1 && d == 1) return '元旦';

    // ── 周末 ──
    if (weekday == 6) return '周六';
    if (weekday == 7) return '周日';

    return null; // 普通工作日
  }

  /// 获取当前实际温度范围参考（按月份，中国大陆参考）
  static String _getTemperatureHint(String? city) {
    final month = DateTime.now().month;
    // 北方判断：省名 OR 直辖市 OR 具体北方城市名
    final isNorth = city != null &&
        (city.contains('黑龙江') || city.contains('吉林') || city.contains('辽宁') ||
         city.contains('内蒙') || city.contains('北京') || city.contains('天津') ||
         city.contains('河北') || city.contains('山西') || city.contains('山东') ||
         city.contains('河南') || city.contains('陕西') || city.contains('甘肃') ||
         city.contains('新疆') || city.contains('宁夏') || city.contains('青海') ||
         // 直接城市名（不含省级关键词的北方城市）
         city.contains('沈阳') || city.contains('大连') || city.contains('长春') ||
         city.contains('哈尔滨') || city.contains('朝阳') || city.contains('北票') ||
         city.contains('锦州') || city.contains('鞍山') || city.contains('抚顺') ||
         city.contains('本溪') || city.contains('丹东') || city.contains('辽阳') ||
         city.contains('营口') || city.contains('呼和浩特') || city.contains('包头') ||
         city.contains('西安') || city.contains('太原') || city.contains('石家庄') ||
         city.contains('济南') || city.contains('郑州') || city.contains('兰州') ||
         city.contains('银川') || city.contains('西宁') || city.contains('乌鲁木齐'));
    if (isNorth) {
      const temps = {
        1: '北方严寒，约-15~-5°C，需要羽绒服/厚棉服',
        2: '北方末冬，约-10~3°C，厚羽绒/棉服',
        3: '北方早春，约3~15°C，日差大，叠穿为主',
        4: '北方春季，约10~22°C，薄外套/针织',
        5: '北方春末，约15~28°C，单薄长袖/轻薄外套',
        6: '北方初夏，约20~32°C，短袖/轻薄面料',
        7: '北方盛夏，约25~36°C，清凉透气为主',
        8: '北方夏末，约22~33°C，防晒为主',
        9: '北方初秋，约12~25°C，日差大，外套必备',
        10: '北方深秋，约5~18°C，叠穿+外套',
        11: '北方入冬，约-3~10°C，保暖优先',
        12: '北方严寒，约-12~-2°C，羽绒服必备',
      };
      return temps[month] ?? '北方，参考当月气温穿搭';
    } else {
      // 南方/江南/华南等通用
      const temps = {
        1: '冬季，约5~15°C，大衣/毛呢外套',
        2: '冬末早春，约8~18°C，薄外套+打底',
        3: '春季，约12~22°C，薄外套/针织衫',
        4: '春季，约16~26°C，轻薄外套或长袖',
        5: '春末，约20~30°C，短袖+防晒薄外套',
        6: '初夏，约25~33°C，清凉透气短袖',
        7: '盛夏，约28~38°C，最热时段，轻薄防晒',
        8: '夏末，约27~36°C，轻薄透气为主',
        9: '初秋，约22~32°C，早晚稍凉，可叠穿',
        10: '秋季，约15~26°C，薄外套+长袖',
        11: '深秋，约10~20°C，外套必备',
        12: '冬季，约6~16°C，厚外套/轻羽绒',
      };
      return temps[month] ?? '参考当月气温穿搭';
    }
  }

  String _buildSystemPrompt(
    String intent,
    UserProfile? profile,
    String userMessage, {
    WeatherData? weather,
    List<Product> matchedProducts = const [],
    List<Product> fallbackProducts = const [],
    Map<String, String> conversationHints = const {},
    List<Map<String, String>> history = const [],
    bool isProfileEditRequest = false,
  }) {
    final profileDesc = profile != null
        ? _describeProfile(profile)
        : '（用户尚未建立档案，请温柔地引导用户完善档案，提问要具体）';

    // 档案缺失检测：对推荐类意图，分析哪些关键字段缺失并触发追问
    final missingHint = _buildMissingHint(intent, profile);

    // ── 实时时间与季节（精确到时分+时段，让AI知道早晨还是晚上）──
    final now = DateTime.now();
    final realSeason = _getRealSeason();
    final timeOfDay = _getTimeOfDay();
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[now.weekday - 1];
    final hourStr = now.hour.toString().padLeft(2, '0');
    final minStr = now.minute.toString().padLeft(2, '0');
    final realDate = '${now.year}年${now.month}月${now.day}日（星期$weekday，$realSeason，$timeOfDay $hourStr:$minStr）';
    final city = profile?.city?.isNotEmpty == true ? profile!.city! : '未知城市';

    // ── 节假日感知 ──────────────────────────────────────────────
    final holiday = _detectHoliday();
    final String holidayHint;
    if (holiday != null) {
      final String occasionTip;
      switch (holiday) {
        case '情人节':
        case '七夕情人节':
        case '纪念日':
          occasionTip = '今天是$holiday，用户可能有约会/情侣场景穿搭需求，主动关联约会穿搭建议。';
          break;
        case '五一假期':
        case '国庆假期':
        case '元旦':
          occasionTip = '今天是$holiday，用户可能有出游/聚会需求，主动关联旅行或节日聚会穿搭。';
          break;
        case '三八妇女节':
          occasionTip = '今天是$holiday，可以给用户一点节日祝福，并联系到穿出女神感的穿搭建议。';
          break;
        case '圣诞节':
        case '平安夜':
        case '跨年夜':
          occasionTip = '今天是$holiday，有节日仪式感穿搭需求，可以推荐派对/跨年适合的穿搭。';
          break;
        case '周六':
        case '周日':
          occasionTip = '今天是周末，用户可能有休闲出游或约会需求，穿搭建议侧重休闲/出游/约会方向。';
          break;
        default:
          occasionTip = '今天是$holiday，可以根据节日特点主动关联场合穿搭建议。';
      }
      holidayHint = '\n【今日节假日/特殊日】$holiday\n- $occasionTip';
    } else {
      holidayHint = '';
    }

    // ── 实时天气（有真实数据则注入，否则降级到月份参考）──
    final String weatherBlock;
    if (weather != null) {
      weatherBlock = '''
【当前实时天气】✅ 已获取真实数据，必须以此为准
- 城市：$city
- 天气：${weather.toPromptString()}
- 穿搭温度建议：${weather.dressHint}
- ⚠️ 用户问天气穿搭时，直接告诉她"$city现在${weather.weatherDesc}，${weather.temperature.round()}°C"，不要说"我没有实时天气数据"''';
    } else {
      final tempHint = _getTemperatureHint(profile?.city);
      weatherBlock = '''
【当前气候参考】⚠️ 未能获取实时天气，使用月份气候估算
- 城市：$city
- 本月气温参考：$tempHint
- 提示：如需实时天气穿搭建议，可告诉用户"你可以告诉我今天多少度，我帮你搭"''';
    }

    // ── 商品库注入块 ────────────────────────────────────────────────
    final String productBlock;
    if (matchedProducts.isNotEmpty) {
      final productList = matchedProducts.map((p) =>
        '- 【${p.name}】¥${p.price.replaceAll('¥', '')} | ${p.description}').join('\n');
      productBlock = '''
【⚡ 自营商品库精确匹配】已为用户找到以下商品，请直接使用！
$productList

‼️ 关键指令：
1. 必须以上述商品为主推，结合用户档案说明"为什么适合她"
2. 禁止让用户"去淘宝/京东/拼多多搜索"，禁止给外部搜索关键词
3. 你的回复 reply 字段只需要一句温暖、个性化的推荐理由（50字以内）
4. 不需要输出 cards 字段，系统会自动展示商品卡片
5. 输出格式：{"reply": "推荐理由"}''';
    } else if (fallbackProducts.isNotEmpty) {
      final productList = fallbackProducts.map((p) =>
        '- 【${p.name}】¥${p.price.replaceAll('¥', '')} | ${p.description}').join('\n');
      productBlock = '''
【💡 自营商品库相近推荐】没有完全匹配的商品，以下是相近款式，请优先推荐！
$productList

‼️ 关键指令：
1. 主动告诉用户"虽然没有你说的具体款式，但这款很适合你，因为..."
2. 禁止让用户"去淘宝/京东/拼多多搜索"，禁止给外部搜索关键词
3. 你的回复 reply 字段说明为什么这个相近款也适合她（60字以内）
4. 不需要输出 cards 字段，系统会自动展示商品卡片
5. 输出格式：{"reply": "推荐理由，说明为什么相近款也适合"}''';
    } else {
      productBlock = '''
【商品库】本次未找到精确匹配商品，请根据用户需求给出专业建议。
- 可以描述穿搭/美妆方向，给出具体单品特征
- 如需商品卡片，请在 JSON 的 cards 数组中生成（带 buy_keyword 搜索词）''';
    }

    // ── 对话内已获取的用户信息（防止 AI 重复追问）───────────────
    String conversationMemoryBlock = '';
    if (conversationHints.isNotEmpty) {
      final knownItems = <String>[];
      if (conversationHints.containsKey('skinTone')) knownItems.add('肤色');
      if (conversationHints.containsKey('skinType')) knownItems.add('肤质');
      if (conversationHints.containsKey('bodyShape')) knownItems.add('身材');
      if (conversationHints.containsKey('styleType')) knownItems.add('风格');
      if (conversationHints.containsKey('height')) knownItems.add('身高${conversationHints['height']}cm');
      if (conversationHints.containsKey('weight')) knownItems.add('体重${conversationHints['weight']}kg');
      if (conversationHints.containsKey('city')) knownItems.add('城市${conversationHints['city']}');
      if (conversationHints.containsKey('ageGroup')) knownItems.add('年龄段');
      if (conversationHints.containsKey('clothingSize')) knownItems.add('尺码${conversationHints['clothingSize']}');
      if (knownItems.isNotEmpty) {
        conversationMemoryBlock = '''
【本次对话已知信息】用户在这次聊天中已告知：${knownItems.join('、')}
- ⚠️ 不要再追问上面已知的字段！直接用这些信息给建议。''';
      }
    }

    // ── 用户消息长度→回复长度自适应 ──────────────────────────
    final userMsgLen = userMessage.length;
    final String replyLenRule;
    if (userMsgLen <= 10) {
      // 极短问题（「推荐口红」「鞋子呢」）→ 超精简回复
      replyLenRule = '用户问题很短，回复也要短！reply控制在25字以内，直接给结论，不铺垫。';
    } else if (userMsgLen <= 25) {
      // 短问题 → 简洁回复
      replyLenRule = 'reply控制在40字以内，开门见山说结论。';
    } else {
      // 详细描述 → 正常长度
      replyLenRule = 'reply可以展开说，40-60字，结合用户描述的具体情况回应。';
    }

    // ── 检测是否为追问（鞋子/包包/配件追问），提取history中最近的outfit上下文 ──
    final isFollowUp = _match(userMessage.toLowerCase(), [
      '鞋子', '包包', '包呢', '配件', '再搭', '内搭', '外套呢', '腰带', '首饰',
      '帽子', '丝巾', '袜子', '耳环', '项链', '再来一套', '有平价版', '换个颜色',
    ]);
    String followUpHint = '';
    if (isFollowUp && history.isNotEmpty) {
      // 找最近一条assistant消息中的穿搭方案关键词
      for (int i = history.length - 1; i >= 0; i--) {
        if (history[i]['role'] == 'assistant') {
          final prevReply = history[i]['content'] ?? '';
          if (prevReply.length > 20) {
            // 截取核心部分注入提示
            final snippet = prevReply.length > 80
                ? prevReply.substring(0, 80)
                : prevReply;
            followUpHint = '\n【追问感知】用户在追问上一套方案的配搭，上一条建议摘要："$snippet..."。请基于这套方案接着搭，不要重新来过。';
            break;
          }
        }
      }
    }

    final base = '''
你是 MUSE，一个真正懂时尚、有审美、有温度的 AI 私人风格顾问。
性格特点：像最懂你的闺蜜——直接、有趣、有观点，不说废话，不说正确的废话。

【当前时间与季节】⚠️ 严格以此为准，禁止自行推测季节
- 今天：$realDate
- 时段：$timeOfDay
- 季节：$realSeason（只推$realSeason单品，不推反季）
$holidayHint

$weatherBlock

$productBlock

【你的说话风格 - 非常重要】
✅ 好的表达方式（要这样说）：
  - 穿搭："你是梨形身材，穿这条高腰A字裙，腰马上细一圈"
  - 颜色："你肤色偏暖黄，选偏橘调的豆沙色，整个人气色好3倍"
  - 天气："现在${timeOfDay}，你要出门的话，外面$realSeason换季，这件薄针织开衫带走不亏"
  - 护肤："你混合偏油，T区控油两颊补水才是正确打开方式，别傻乎乎全脸一个产品"
  - 成分："这个水杨酸浓度2%，你油痘肌刚好，但别和A醇叠用，两个一起上脸会刺激"
  - 直接说结论，别铺垫

❌ 坚决不要说的废话：
  - "根据你的情况/个人档案/皮肤特点来看"
  - "我建议你考虑..."
  - "这是一个很好的选择"

⚠️ 禁止幻觉记忆：严禁编造用户说过的话！
  - 不可以说"你上次说想买xxx"、"你之前提到过xxx"（除非对话历史里真的有）
  - 不可以说"我记得你说过xxx"（除非真的说过）
  - 记忆缺失时直接说"我忘了，你重新说一遍"，不要编造
  - 被用户质疑"我没说过"时，立即承认错误，不要狡辩

✅ 闲聊处理原则：
  - 唱歌/讲故事等非核心请求：拒绝后立即引导回主业，例"我不会唱歌，但我可以帮你挑一款约会用的香水"
  - 幽默点可以，但不要离题太远
  - "希望对你有帮助"
  - 任何套话开头

【回复长度规则 - 必须遵守】
$replyLenRule$followUpHint

【核心规则】
1. reply 字段直接说干货，开门见山，一句到位（超了裁）
2. 结合档案细节（身材/肤色/风格）而不是泛泛而谈
3. $realSeason单品才推，反季直接不说
4. 发现档案有空缺字段，最多问一个追问，不要一次问多个
5. 有自营商品时，重点说"为什么这款适合她"，不推外部平台

【用户档案】
$profileDesc

$conversationMemoryBlock

$missingHint
''';

    switch (intent) {
      case _intentOutfit:
        return base + _outfitPrompt(profile, userMessage);

      case _intentWeather:
        return base + _weatherPrompt(profile, userMessage, weather);

      case _intentOccasion:
        return base + _occasionPrompt(profile, userMessage, weather);

      case _intentMood:
        return base + _moodPrompt(profile, userMessage);

      case _intentLipstick:
        return base + _lipstickPrompt(profile);

      case _intentSkin:
        return base + _skinPrompt(profile);

      case _intentIngredient:
        return base + _ingredientPrompt(profile);

      case _intentProfile:
        return base + _profileSummaryPrompt(profile, isProfileEditRequest);

      default: {
        // ── 动态闲聊：根据时段/节日生成不同的「话题钩子」────
        final season = _getRealSeason();
        final seasonChar = _getRealSeasonChar();
        final timeOfDay = _getTimeOfDay();
        final holiday = _detectHoliday();

        // 当下最自然的时尚话题（每次聊天用不同的切入点）
        final topicSeeds = [
          '$season必入单品',
          '$seasonChar季哪个颜色最显白',
          '$timeOfDay出门的穿搭状态',
          '最近流行的${_getPlatformTrend()}',
          '换季衣橱整理',
        ];
        final topicSeed = topicSeeds[DateTime.now().minute % topicSeeds.length];

        final holidayTip = holiday != null
            ? '\n- 今天是$holiday，可以顺带聊聊节日穿搭/护肤心情。'
            : '';

        return base + '''
【当前任务：对话】
自然、亲切地回应用户，像真正懂时尚的好朋友聊天，不是客服。

话题引导原则：
1. 先自然回应用户说的话（不能无视她说的内容）
2. 如果用户说了任何关于自己外貌/偏好/生活的信息，立刻在回复里用到，体现你在听
3. 回复末尾自然切入一个时尚/美妆话题钩子（不要生硬转移，要顺着对话逻辑）
4. 话题钩子参考方向："$topicSeed"$holidayTip

❌ 不要这样做：
- 纯应付式回复（"好的呀～"、"嗯嗯"然后没有下文）
- 连问多个问题轰炸用户
- 每次都问一样的话题

直接输出文字回复，不需要 JSON 格式。
30字以内，有话题钩子结尾。
''';
      }
    }
  }

  // ─── 各意图 Prompt ─────────────────────────────────────────────

  String _outfitPrompt(UserProfile? p, [String userMsg = '']) {
    final season = _getRealSeason();
    final seasonChar = _getRealSeasonChar();
    final timeOfDay = _getTimeOfDay();

    // ── 风格容错：纠正用户的打字错误或近似表述 ────────────────────
    String correctedMsg = userMsg.toLowerCase();
    
    // 运动服 → 运动风 / 甜美服 → 甜美风 / 极简服 → 极简风
    correctedMsg = correctedMsg
        .replaceAll(RegExp(r'运动\s*服'), '运动风')
        .replaceAll(RegExp(r'甜美\s*服'), '甜美风')
        .replaceAll(RegExp(r'极简\s*服'), '极简风')
        .replaceAll(RegExp(r'性感\s*服'), '性感风')
        .replaceAll(RegExp(r'优雅\s*服'), '优雅风')
        .replaceAll(RegExp(r'文艺\s*服'), '文艺风')
        .replaceAll(RegExp(r'街头\s*服'), '街头风')
        .replaceAll(RegExp(r'通勤\s*服'), '通勤风');

    // ── 用户诉求细分（显瘦/显高/颜色/版型/材质） ───────────────
    final tl = correctedMsg;
    String subGoal = '';
    String subInstruction = '';

    if (_match(tl, ['显瘦', '遮肉', '遮肚子', '遮大腿', '腿显细', '腰显细', '修身'])) {
      subGoal = '【显瘦诉求】';
      subInstruction = '''
关键穿搭原则（显瘦）：
- 梨形：高腰A字裙/阔腿裤修臀胯，深色下装
- 苹果/腰粗：V领/裹身裙拉长腰线，避免腰部横向细节
- 直筒：腰封/束腰外套制造曲线
- 通用：深色系优于浅色，纵向线条/竖条纹视觉拉长
- 禁忌：水平宽腰带/短款上衣+短裙（会截断比例）''';
    } else if (_match(tl, ['显高', '拉腿', '腿长', '显腿长', '视觉高', '拉高'])) {
      subGoal = '【显高诉求】';
      subInstruction = '''
关键穿搭原则（显高）：
- 连衣裙/上下同色系：视觉无截断，拉长全身比例
- 高腰线单品：高腰裤/裙让腿看起来更长
- 尖头鞋/中跟鞋：延伸腿部线条（比厚底夸张靴更有效）
- 九分裤：露出脚踝，视觉"借高"
- 禁忌：颜色撞断腰线的搭法（如黑色裤子配白色上衣+白色腰带）''';
    } else if (_match(tl, ['什么颜色', '颜色搭配', '配色', '色系', '显白', '肤色搭', '气色'])) {
      subGoal = '【颜色/显白诉求】';
      final skinToneHint = p?.skinTone != null
          ? '用户肤色：${p!.skinTone!.label}'
          : '肤色未知，可以推荐冷/暖两个方向';
      subInstruction = '''
关键配色原则（$skinToneHint）：
- 冷白皮：马卡龙粉/薄荷绿/天蓝/冷灰最显白；橘黄/土棕慎用
- 暖黄皮：米白/杏色/橄榄绿/砖红提气色；冷蓝/冷粉会显黄
- 小麦色：白色/饱和亮色对比感好；避免浅卡其/奶茶色（融色）
- 冷肤/中性：粉调白/浅紫/玫瑰色都很友好
- 通用显白：off-white（米白）比纯白更显白，减少反光''';
    } else if (_match(tl, ['版型', '廓形', '宽松', '收腰', 'oversize', '修身版'])) {
      subGoal = '【版型诉求】';
      final bodyShapeStr = p?.bodyShape?.label ?? '通用';
      subInstruction = '''
关键版型原则（用户身材：$bodyShapeStr）：
- 梨形：上紧下宽/A字裙 — 上衣稍修身，裤/裙有量感遮臀胯
- 苹果：上宽下修 — 宽松上衣叠修身直筒裤，转移视线
- 沙漏：收腰廓形最能展示曲线，wrap/裹身裙/系带连衣裙
- 直筒：制造曲线 — 腰封/束腰外套/有细节的系带设计
- ⚠️ 必须结合上方用户实际身材「$bodyShapeStr」给最匹配的版型，而非泛泛说4种''';
    } else if (_match(tl, ['棉', '麻', '丝', '雪纺', '针织', '牛仔', '皮革', '面料', '材质'])) {
      subGoal = '【面料/材质诉求】';
      subInstruction = '''
$season面料首选：${_getSeasonOutfitHint(season)}
- 春夏透气首选：棉/麻/雪纺/轻薄丝绸
- 秋冬保暖首选：针织/法兰绒/羊毛/厚棉
- 提升质感：真丝/缎面/精纺羊毛（价格高但上镜好）''';
    }

    // quick_replies 根据诉求子意图动态调整
    final List<String> dynamicQuickReplies;
    if (subGoal == '【显瘦诉求】') {
      dynamicQuickReplies = ['鞋子怎么搭', '下装有什么推荐', '上衣显瘦款', '有颜色建议吗'];
    } else if (subGoal == '【显高诉求】') {
      dynamicQuickReplies = ['推荐哪种鞋', '裤子怎么选', '颜色搭配建议', '再来一套'];
    } else if (subGoal == '【颜色/显白诉求】') {
      dynamicQuickReplies = ['这颜色配什么下装', '口红颜色呢', '有平价版吗', '换个风格试试'];
    } else if (subGoal == '【版型诉求】') {
      dynamicQuickReplies = ['有没有具体品牌推荐', '裤装版型呢', '外套什么版型好', '平价版有吗'];
    } else if (subGoal == '【面料/材质诉求】') {
      dynamicQuickReplies = ['有没有平价面料推荐', '这面料怎么保养', '再推一个款', '搭什么鞋'];
    } else {
      dynamicQuickReplies = ['鞋子怎么搭', '有平价版吗', '换个颜色试试', '再来一套'];
    }

    // 时段场合提示
    final String timeHint;
    switch (timeOfDay) {
      case '早晨':
      case '上午':
        timeHint = '通勤/出门，便利性+职业感';
        break;
      case '中午':
        timeHint = '午后外出/活动，舒适实用';
        break;
      case '下午':
        timeHint = '下午出门/傍晚聚会，兼顾日/夜两用';
        break;
      case '傍晚':
      case '晚上':
        timeHint = '晚间约会/聚餐，有女人味和仪式感';
        break;
      default:
        timeHint = '规划明天穿搭，可以给2套备选';
    }

    // 多样性种子词（分钟数取模）
    final diversitySeeds = [
      '简单高级感', '颜色出挑', '层次感叠穿', '版型显身材', '面料质感优先',
      '百搭易出门', '有点不一样', '清爽干净', '有个性的穿法', '小众有品味',
    ];
    final seed = diversitySeeds[DateTime.now().minute % diversitySeeds.length];

    return '''
【任务：穿搭建议】当前$season，只推$seasonChar季单品。$subGoal
- 时段：$timeOfDay（$timeHint）
- 身高：${p?.height != null ? '${p!.height}cm' : '未填'}
- 体重：${p?.weight != null ? '${p!.weight}kg' : '未填'}
- 身材：${p?.bodyShape?.label ?? '未填，推通用显瘦版型'}
- 尺码：${p?.clothingSize?.label ?? '未填'}
- 年龄段：${p?.ageGroup?.label ?? '未填'}
- 肤色：${p?.skinTone?.label ?? '未填'}（影响穿搭配色，冷白皮推冷调色；暖黄皮推暖调/大地色；小麦色推对比饱和色）
- 风格：${p?.styleType?.label ?? '未填，可以问她'}（⚠️ 智能推断：用户说"运动服/甜美服/极简服/性感服/优雅服/文艺服/街头服/通勤服"等带"服"字的表述，应理解为"XX风"而非单品类型！例："运动服"→理解为运动风格穿搭，而非直接推荐运动服单品）
- 喜欢颜色：${p?.favoriteColors.isNotEmpty == true ? p!.favoriteColors.join('、') : '未填，推适合她肤色的色系'}
- 不要颜色：${p?.avoidColors.isNotEmpty == true ? p!.avoidColors.join('、') : '无限制'}
- 场景：${p?.occasions.isNotEmpty == true ? p!.occasions.map((e) => e.label).join('、') : '日常'}
- 预算：${p?.budget?.label ?? '未填，平价轻奢各给一个'}
$subInstruction

本次推荐侧重（自由融合，让回复有特点）："$seed"

必须JSON输出（只输出JSON，不要任何前缀说明）：
{
  "reply": "直接告诉她穿什么、为什么（提到身材/颜色优势），$season+$timeOfDay带进去，25-50字",
  "quick_replies": ${jsonEncode(dynamicQuickReplies)},
  "cards": [
    {
      "title": "具体穿搭名（体现$season特色，如：$seasonChar季碎花裙日系穿搭）",
      "subtitle": "为什么适合她的身材+颜色，$season穿出去的感觉",
      "tags": ["$seasonChar季", "场合", "颜色特点"],
      "price_range": "¥xxx-xxx",
      "buy_keyword": "$seasonChar季 具体单品关键词"
    }
  ]
}
''';
  }

  /// 各季节穿搭单品参考（给 AI 更明确的方向）
  static String _getSeasonOutfitHint(String season) {
    switch (season) {
      case '春季': return '薄外套、针织开衫、风衣、连衣裙、叠穿技巧（避开羽绒/厚棉服/毛呢大衣）';
      case '夏季': return '短袖T恤、吊带、雪纺、防晒衬衫、短裙、阔腿短裤（避开羽绒/毛衣/厚外套）';
      case '秋季': return '薄毛衣、卫衣、皮夹克、风衣、牛仔外套、针织连衣裙（避开厚羽绒/单薄吊带）';
      case '冬季': return '羽绒服、毛呢大衣、厚毛衣、加绒打底、棉服（避开单薄连衣裙/短袖）';
      default: return '当季适合的单品';
    }
  }

  String _weatherPrompt(UserProfile? p, String userMsg, [WeatherData? weather]) {
    final season = _getRealSeason();

    // 有实时天气时用真实数据；否则降级到月份参考
    final String weatherInfo;
    final String dressStrategy;
    if (weather != null) {
      weatherInfo = '✅ 实时天气：${weather.toPromptString()}';
      dressStrategy = weather.dressHint;
    } else {
      weatherInfo = '📊 月份参考：${_getTemperatureHint(p?.city)}';
      dressStrategy = '根据月份估算温度，给出叠穿和层次建议';
    }

    // 根据天气类型动态调整 quick_replies
    final List<String> weatherQuickReplies;
    if (weather != null) {
      final desc = weather.weatherDesc;
      final temp = weather.temperature;
      if (desc.contains('雨') || desc.contains('雪')) {
        weatherQuickReplies = ['雨天鞋子怎么选', '防水面料推荐', '雨天妆容建议', '下午天晴了换什么'];
      } else if (temp > 30) {
        weatherQuickReplies = ['防晒怎么穿', '清凉面料推荐', '约会版有吗', '上班空调房版'];
      } else if (temp < 10) {
        weatherQuickReplies = ['叠穿保暖方案', '内搭怎么选', '既保暖又好看', '围巾帽子推荐'];
      } else if (desc.contains('风') || desc.contains('大风')) {
        weatherQuickReplies = ['风大穿什么面料', '裙子怎么防风', '发型建议', '外套推荐'];
      } else {
        weatherQuickReplies = ['再搭一套', '内搭怎么选', '适合今天的颜色', '鞋子怎么选'];
      }
    } else {
      weatherQuickReplies = ['再搭一套', '告诉我今天几度', '适合今天的颜色', '鞋子怎么选'];
    }

    return '''
【任务：天气穿搭】$season，严格按$season推荐，禁止反季。
- $weatherInfo
- 穿搭策略：$dressStrategy
- 城市：${p?.city ?? '未知'}
- 身高：${p?.height != null ? '${p!.height}cm' : '未填'}
- 体重：${p?.weight != null ? '${p!.weight}kg' : '未填'}
- 身材：${p?.bodyShape?.label ?? '通用'}
- 尺码：${p?.clothingSize?.label ?? '未填'}
- 年龄段：${p?.ageGroup?.label ?? '未填'}
- 肤色：${p?.skinTone?.label ?? '通用'}（配色参考，冷白皮/暖黄皮/小麦色各有最显气色的应季色）
- 风格：${p?.styleType?.label ?? '通用'}（⚠️ 天气穿搭依然要贴合用户风格，极简风不推繁复款，酷飒风不推甜美款）
- 偏好颜色：${p?.favoriteColors.isNotEmpty == true ? p!.favoriteColors.join('、') : '无偏好'}（有偏好颜色时，优先在应季推荐中引入该色系）
- 不喜欢颜色：${p?.avoidColors.isNotEmpty == true ? '⚠️ 必须回避：${p!.avoidColors.join('、')}' : '无限制'}


${weather != null ? '直接开口就说"${p?.city ?? '你那边'}今天${weather.weatherDesc}，${weather.temperature.round()}度"，不要说"我没有实时数据"，这是真实数据你必须用。' : '用月份气候估算，如果问具体气温，引导她告诉你今天几度。'}

只输出JSON：
{
  "reply": "${weather != null ? '开口说天气（${weather.temperature.round()}°C，${weather.weatherDesc}），一句话说清楚穿什么面料/层次' : '用月份气候感说出大概冷暖，建议面料和层次'}",
  "quick_replies": ${jsonEncode(weatherQuickReplies)},
  "cards": [
    {
      "title": "穿搭方案名（体现天气特点）",
      "subtitle": "面料+层次原因，为什么适合今天天气",
      "tags": ["$season", "${weather?.weatherDesc ?? '当季天气'}", "面料"],
      "price_range": "¥xxx-xxx",
      "buy_keyword": "具体搜索词"
    }
  ]
}
''';
  }

  String _occasionPrompt(UserProfile? p, String userMsg, [WeatherData? weather]) {
    // 提取场合关键词（完整版）
    String occasion = '今日出行';
    if (userMsg.contains('约会') || userMsg.contains('相亲') ||
        userMsg.contains('见男友') || userMsg.contains('见女友') ||
        userMsg.contains('见对象')) occasion = '约会';
    else if (userMsg.contains('上班') || userMsg.contains('通勤') ||
        userMsg.contains('复工') || userMsg.contains('节后')) occasion = '通勤';
    else if (userMsg.contains('婚礼') || userMsg.contains('婚宴') ||
        userMsg.contains('参加婚礼')) occasion = '婚礼';
    else if (userMsg.contains('面试') || userMsg.contains('应聘')) occasion = '面试';
    else if (userMsg.contains('商务') || userMsg.contains('宴请') ||
        userMsg.contains('商务宴')) occasion = '商务宴请';
    else if (userMsg.contains('派对') || userMsg.contains('聚会') ||
        userMsg.contains('同学聚会') || userMsg.contains('闺蜜聚会') ||
        userMsg.contains('家庭聚餐')) occasion = '聚会';
    else if (userMsg.contains('旅行') || userMsg.contains('出游') ||
        userMsg.contains('度假') || userMsg.contains('踏青')) occasion = '旅行';
    else if (userMsg.contains('运动') || userMsg.contains('健身') ||
        userMsg.contains('瑜伽') || userMsg.contains('跑步')) occasion = '运动健身';
    else if (userMsg.contains('见家长')) occasion = '见家长';
    else if (userMsg.contains('生日') || userMsg.contains('纪念日')) occasion = '生日纪念';
    else if (userMsg.contains('拍照') || userMsg.contains('拍大头贴') ||
        userMsg.contains('拍写真')) occasion = '拍照写真';
    else if (userMsg.contains('五一') || userMsg.contains('十一') ||
        userMsg.contains('国庆') || userMsg.contains('假期')) occasion = '节假日出游';
    else if (userMsg.contains('毕业')) occasion = '毕业典礼';
    else if (userMsg.contains('年会') || userMsg.contains('颁奖')) occasion = '年会典礼';
    else if (userMsg.contains('露营') || userMsg.contains('徒步') ||
        userMsg.contains('户外')) occasion = '户外活动';

    final season = _getRealSeason();
    final seasonChar = _getRealSeasonChar();
    final timeOfDay = _getTimeOfDay();
    final String weatherNote;
    if (weather != null) {
      weatherNote = '- ✅ 今日天气：${weather.toPromptString()}，穿搭温度策略：${weather.dressHint}';
    } else {
      weatherNote = '- 气候参考：${_getTemperatureHint(p?.city)}';
    }

    // quick_replies 按场合动态调整
    final List<String> occasionQuickReplies;
    switch (occasion) {
      case '约会':
        occasionQuickReplies = ['鞋包怎么搭', '妆容怎么配', '更甜美一点', '更高级冷淡风'];
        break;
      case '通勤':
        occasionQuickReplies = ['有没有平价版', '鞋子推荐', '更休闲一点', '冬天版本呢'];
        break;
      case '婚礼':
        occasionQuickReplies = ['妆容怎么搭', '平价版有吗', '更正式一点', '白天婚礼版本'];
        break;
      case '面试':
        occasionQuickReplies = ['鞋子推荐', '妆容建议', '更显成熟稳重', '互联网公司可以活泼点吗'];
        break;
      case '商务宴请':
        occasionQuickReplies = ['配饰怎么选', '妆容建议', '更高端一点', '鞋包推荐'];
        break;
      case '旅行':
      case '节假日出游':
        occasionQuickReplies = ['好收纳的面料', '适合拍照的颜色', '鞋子怎么选', '备一套换的'];
        break;
      case '运动健身':
        occasionQuickReplies = ['鞋子推荐', '运动内衣怎么选', '瑜伽版本呢', '好看又功能性的品牌'];
        break;
      case '见家长':
        occasionQuickReplies = ['妆容建议', '显得成熟一点', '颜色建议', '鞋包怎么搭'];
        break;
      case '拍照写真':
        occasionQuickReplies = ['什么颜色最上镜', '多套备换怎么搭', '妆容建议', '道具/配件推荐'];
        break;
      case '年会典礼':
        occasionQuickReplies = ['更闪一点', '鞋子推荐', '妆容建议', '平价版有吗'];
        break;
      case '生日纪念':
        occasionQuickReplies = ['更有仪式感', '妆容建议', '配饰怎么选', '男友约会版'];
        break;
      case '毕业典礼':
        occasionQuickReplies = ['拍照好看的颜色', '鞋子推荐', '更正式一点', '亲友版本'];
        break;
      case '户外活动':
        occasionQuickReplies = ['防晒怎么穿', '鞋子推荐', '背包推荐', '好拍照版本'];
        break;
      default:
        occasionQuickReplies = ['再正式一点', '更休闲一点', '鞋包怎么搭', '平价版有吗'];
    }

    return '''
【任务：$occasion场合穿搭】$season，严格只推$seasonChar季单品。
- 时段：$timeOfDay
$weatherNote
- 身高：${p?.height != null ? '${p!.height}cm' : '未填'}
- 体重：${p?.weight != null ? '${p!.weight}kg' : '未填'}
- 身材：${p?.bodyShape?.label ?? '通用'}
- 尺码：${p?.clothingSize?.label ?? '未填'}
- 年龄段：${p?.ageGroup?.label ?? '未填'}
- 肤色：${p?.skinTone?.label ?? '通用'}（影响$occasion配色，冷白皮推冷调；暖黄皮推暖调大地色）
- 风格偏好：${p?.styleType?.label ?? '通用'}（⚠️ 在满足$occasion场合要求前提下，尽量贴合用户风格偏好！如用户是极简风，约会也不推过度设计感；如用户是甜美风，通勤也可以有小心机）
- 偏好颜色：${p?.favoriteColors.isNotEmpty == true ? '优先把 ${p!.favoriteColors.join('、')} 融入$occasion穿搭配色（在场合允许范围内）' : '无偏好，按场合配色规律推'}
- 不喜欢颜色：${p?.avoidColors.isNotEmpty == true ? '⚠️ 必须回避：${p!.avoidColors.join('、')}' : '无限制'}
- 预算：${p?.budget?.label ?? '给不同价位各一套'}


【$occasion的关键】
${_getOccasionRequirements(occasion)}

只输出JSON（不要前缀说明）：
{
  "reply": "直接说$occasion穿什么最出效果，一句话结论（提到身材/场合亮点），30-50字",
  "quick_replies": ${jsonEncode(occasionQuickReplies)},
  "cards": [
    {
      "title": "穿搭名（$season+$occasion特点，如：$seasonChar季$occasion气质穿搭）",
      "subtitle": "$occasion场合为什么穿这套有效果，给人什么印象",
      "tags": ["$occasion", "$seasonChar季", "风格效果"],
      "price_range": "¥xxx-xxx",
      "buy_keyword": "$seasonChar季 $occasion 具体单品关键词"
    }
  ]
}
''';
  }

  /// 获取当下流行趋势关键词（按季节/月份轮换，营造时尚感）
  static String _getPlatformTrend() {
    final month = DateTime.now().month;
    final trends = {
      1: '过年穿搭',
      2: '早春穿搭',
      3: '春日碎花裙',
      4: '五一出游穿搭',
      5: '清爽薄款外套',
      6: '防晒穿搭',
      7: '夏日碎花连衣裙',
      8: '初秋叠穿',
      9: '秋天针织开衫',
      10: '国庆出游穿搭',
      11: '秋冬大衣',
      12: '跨年派对穿搭',
    };
    return trends[month] ?? '当季流行单品';
  }

  String _getOccasionRequirements(String occasion) {
    switch (occasion) {
      case '约会': return '要有女人味，突出优雅或甜美，让她自信。避免太正式或太随意。颜色推荐柔和或鲜明的亮点色，突出气质。';
      case '通勤': return '专业得体但不失时尚，方便活动，质感要好。适合长时间穿着。颜色稳重不失个性，版型合身。';
      case '婚礼': return '喜庆但不抢主角，避免白色和黑色，有仪式感但不浮夸。推荐淡雅有光泽感的面料和颜色。';
      case '面试': return '专业利落，展现能力和自信，颜色稳重（藏蓝/深灰/米白），版型合身不松垮。';
      case '派对聚会':
      case '聚会': return '可以更大胆有趣，展示个性，闪光元素/亮色/特别剪裁都可以。让她在人群里被注意到。';
      case '旅行': return '舒适方便为主，好搭配易收纳，兼顾拍照好看。可以有亮色或图案，轻盈面料优先。';
      case '运动健身': return '功能性优先，排汗透气，同时兼顾运动时的好看。可以有运动感的撞色或设计感。';
      case '见家长': return '得体清爽，展现知性温柔，保守但不无聊，颜色清新或素雅（粉色/白色/浅蓝）。让长辈觉得"这孩子懂事"。';
      case '生日纪念': return '有仪式感，突出主角光环，可以有一个亮点（颜色/剪裁/细节）让人印象深刻。';
      case '拍照写真': return '上镜好看是第一位，线条感强、颜色饱和或清新、避免过多花纹导致发花。适合多拍几套备用。\n【上镜肤色配色原则】冷白皮→马卡龙粉/天蓝/薄荷绿最上镜（摄影补光更显白）；暖黄皮→米白/杏色/橙红/大地色上镜最提气色（避开冷蓝/冷紫会显黄）；小麦色→白色/亮橘/鲜红对比感强最好看；通用→纯色比花纹更上镜，饱和度中等（不要太浅也不要太鲜）';
      case '节假日出游': return '舒适轻便，方便走路/拍照，同时要有度假感，可以有明亮色彩或度假元素。';
      case '毕业典礼': return '青春朝气、有纪念感，颜色清新不老气，可以有一个亮点单品，整体干净利落。';
      case '年会典礼': return '有光泽感和仪式感，可以更大胆，闪光/丝绒/饱和色都很合适，展示个人魅力。';
      case '商务宴请': return '高级感优先，显示品味和地位，面料质感好（真丝/毛呢/精纺），颜色深沉或优雅（黑/藏蓝/深酒红）。避免过于休闲或花哨。';
      case '户外活动': return '实用与美观兼顾，防风防晒，颜色可以活泼一点，功能性面料优先，整体有运动户外感。';
      default: return '根据当天心情和目的地，给出舒适实用且好看的穿搭方案，突出她的优势。';
    }
  }

  String _moodPrompt(UserProfile? p, String userMsg) {
    final season = _getRealSeason();
    final seasonChar = _getRealSeasonChar();
    final timeOfDay = _getTimeOfDay();

    // 根据消息判断情绪倾向，给AI更精准的共情方向
    final tl = userMsg.toLowerCase();
    String moodType = '一般';
    String moodHint = '用温暖的话语给她力量';
    if (tl.contains('难过') || tl.contains('哭') || tl.contains('委屈') || tl.contains('伤心')) {
      moodType = '低落';
      moodHint = '先说一两句温暖的共情（不要说"我理解你的感受"这种套话），再用穿搭帮她找回自信';
    } else if (tl.contains('烦') || tl.contains('焦虑') || tl.contains('压力') || tl.contains('累')) {
      moodType = '烦躁压力';
      moodHint = '先说一两句轻松的话缓解她的压力，再给一套能让她"出门被夸立刻好心情"的穿搭';
    } else if (tl.contains('无聊') || tl.contains('没劲') || tl.contains('emo')) {
      moodType = 'emo/无聊';
      moodHint = '来点幽默感，说她可以用穿搭制造"惊喜感"，给自己一个仪式感的理由出门';
    } else if (tl.contains('开心') || tl.contains('今天很美') || tl.contains('状态好')) {
      moodType = '开心';
      moodHint = '顺着她的好心情，推一套配得上她今天好状态的穿搭，帮她"锁住"这份自信';
    } else if (tl.contains('想改变') || tl.contains('换个心情') || tl.contains('想变美')) {
      moodType = '想改变';
      moodHint = '说改变从穿搭开始，给一套有点不一样的穿法，让她感觉"今天的我不一样"。同时可以搭配发型/妆容小建议（如换个发型/口红颜色），穿搭+妆发双管齐下才是真正的蜕变';
    }

    // 情绪状态对应动态 quick_replies
    final List<String> moodQuickReplies;
    if (moodType == '低落') {
      moodQuickReplies = ['给我安全感的颜色', '不想费脑子的穿法', '护肤推一下', '帮我搭配明天'];
    } else if (moodType == '烦躁压力') {
      moodQuickReplies = ['出门被夸的那种', '放松系护肤品', '换个颜色试试', '配件能不能点亮'];
    } else if (moodType == 'emo/无聊') {
      moodQuickReplies = ['有点不一样的穿法', '来个新色号', '发型改变建议', '再推活泼版'];
    } else if (moodType == '开心') {
      moodQuickReplies = ['配得上好心情的口红', '帮我今天拍照好看', '出去约会版', '更闪一点'];
    } else if (moodType == '想改变') {
      moodQuickReplies = ['发型改变建议', '口红换个色系', '全套新造型', '平价快速蜕变方案'];
    } else {
      moodQuickReplies = ['给我更活泼的颜色', '想要安全感的穿法', '帮我搭配明天', '治愈系护肤也推一下'];
    }

    // 多样性种子词（防止AI每次回复同质化）
    final seeds = ['今天', '出门', '穿上', '这套', '马上'];
    final seed = seeds[DateTime.now().second % seeds.length];

    return '''
【任务：情绪治愈穿搭】用户情绪状态：$moodType
⚠️ $season，只推$seasonChar季单品，禁止反季。时段：$timeOfDay。

情绪处理原则：$moodHint

- 身高：${p?.height != null ? '${p!.height}cm' : '未填'}
- 体重：${p?.weight != null ? '${p!.weight}kg' : '未填'}
- 年龄段：${p?.ageGroup?.label ?? '未填'}
- 尺码：${p?.clothingSize?.label ?? '未填'}
- 身材：${p?.bodyShape?.label ?? '通用'}
- 肤色：${p?.skinTone?.label ?? '通用'}（颜色治愈加持：冷白皮推粉/薄荷；暖黄皮推杏/橙橘；配合情绪配色原则）
- 风格偏好：${p?.styleType?.label ?? '通用'}（情绪穿搭也要贴合风格，不能因为治愈就给甜美风用户推酷飒配色）
- 偏好颜色：${p?.favoriteColors.isNotEmpty == true ? p!.favoriteColors.join('、') : '无偏好'}（优先把偏好颜色融入情绪治愈穿搭，穿自己喜欢的颜色本身就是治愈）
- 不喜欢颜色：${p?.avoidColors.isNotEmpty == true ? '⚠️ 情绪低落时更要回避厌恶色：${p!.avoidColors.join('、')}（反感的颜色会加重负面情绪）' : '无限制'}
- 常去场景：${p?.occasions.isNotEmpty == true ? p!.occasions.map((e) => e.label).join('、') : '日常出行'}（情绪穿搭要能实际穿出去）

颜色心理：黄/橙→提振元气，粉/玫瑰→温柔疗愈，深色→安全感，明亮色→自信感
$season可选单品：${_getSeasonOutfitHint(season)}

种子词（用在reply中体现多样感，可选用）："$seed"

只输出JSON：
{
  "reply": "先1句共情（直接、真实，别套话），再1句告诉她穿这套能带来什么改变。$season+$timeOfDay带进去。30-60字",
  "quick_replies": ${jsonEncode(moodQuickReplies)},
  "cards": [
    {
      "title": "穿搭名（带情绪词+$seasonChar季，如：治愈$seasonChar季米白针织日）",
      "subtitle": "穿上这套能带来的感受变化，具体说",
      "tags": ["$seasonChar季", "$moodType治愈", "颜色心理"],
      "price_range": "¥xxx-xxx",
      "buy_keyword": "$seasonChar季 情绪 穿搭关键词"
    }
  ]
}
''';
  }

  /// 档案摘要 Prompt（用户主动查询自己的档案信息）
  String _profileSummaryPrompt(UserProfile? p, [bool isEditRequest = false]) {
    if (isEditRequest) {
      // 编辑档案请求，主动问"你想改哪个"
      return '''
【任务：引导编辑档案】用户想修改/补充档案信息。

不要直接让她去页面，先用 JSON 询问"你想改哪个？"
{
  "reply": "好的，你想改哪部分？告诉我你想修改的内容，我帮你看看怎么调整 💎",
  "quick_replies": ["风格不对，想改风格", "身材信息变了", "肤质有变化", "年龄/城市", "预算范围"]
}
''';
    }

    if (p == null) {
      return '''
【任务：档案查询】用户还没有建立档案。
直接输出文字，温柔地告诉她目前还没有档案信息，邀请她现在就填写几个关键字段。
先问最重要的一个：肤色。
格式：直接输出文字，不要 JSON。
''';
    }

    final rate = (p.completionRate * 100).toInt();
    return '''
【任务：档案摘要】把用户的档案用闺蜜的口吻总结一遍，像在给她"读履历"一样，有趣、有温度。

重要：
1. 不要用表格，不要用"您"，用"你"
2. 按"外貌特征 → 风格偏好 → 身材 → 护肤情况 → 预算"的顺序说
3. 缺失的字段别明说"未填写"，改成"你还没告诉我XXX，下次记得说！"
4. 档案完整度：$rate%，结尾说一句完整度评价（高于80%夸她，低于60%鼓励她补充）
5. 结尾给2-3个基于档案的快速行动建议（如"你的肤色推荐你去看看秋日口红色号"）



直接输出文字，不要 JSON。
''';
  }

  String _lipstickPrompt(UserProfile? p) {
    // 多样性种子
    final seeds = ['日常通勤首选', '约会显气色', '夸张出挑色', '国货宝藏', '大牌经典款'];
    final seed = seeds[DateTime.now().second % seeds.length];
    final season = _getRealSeason();
    final seasonChar = _getRealSeasonChar();

    // 口红色系随季节调整
    final String seasonLipHint;
    switch (season) {
      case '春季':
        seasonLipHint = '春季推荐：裸粉/珊瑚橘/玫瑰粉→清新感；避免过深的暗棕/暗红';
        break;
      case '夏季':
        seasonLipHint = '夏季推荐：西瓜红/正红/橘调活力色→清爽感；水润/镜面质地更应季';
        break;
      case '秋季':
        seasonLipHint = '秋季推荐：豆沙/砖红/焦糖棕/深玫瑰→秋日氛围感；哑光或丝绒质地';
        break;
      case '冬季':
        seasonLipHint = '冬季推荐：深红/酒红/暗莓/枣红→冬日高级感；持妆哑光优先，不掉色';
        break;
      default:
        seasonLipHint = '当季推荐适合肤色的色号';
    }

    return '''
【任务：口红/彩妆推荐】根据用户肤色和季型，推荐最适合的口红色号。必须说清楚"为什么适合她的具体肤色"。
- 当前季节：$season（⚠️ 必须优先推应季色号：$seasonLipHint）
- 肤色：${p?.skinTone?.label ?? '未知，先问肤色再推荐，不要泛推'}
- 色彩季型：${p?.seasonType?.label ?? '未知'}
- 脸型：${p?.faceShape?.label ?? '未知'}（脸型影响妆容效果：圆脸→避免腮红横刷/推拉长纵向感的裸唇+深色唇线；长脸→避免太细唇线/推横向拉宽感圆润唇形；方脸→推圆润柔和色号软化轮廓；尖脸→推饱满正红/正粉增气色减尖锐感）
- 年龄段：${p?.ageGroup?.label ?? '未填'}（18岁→清透感；25岁→日常显气色；35岁↑→遮瑕持久轻熟妆）
- 肤质：${p?.skinType?.label ?? '未知'}（干唇推滋润质地/哑光不友好；油皮推持妆哑光）
- 皮肤问题：${p?.skinConcerns.isNotEmpty == true ? p!.skinConcerns.join('、') : '无'}（有痘痘推遮瑕遮盖唇部小细纹；敏感肌推无香精口红）
- 偏好颜色：${p?.favoriteColors.isNotEmpty == true ? p!.favoriteColors.join('、') : '无偏好'}（偏好颜色影响口红选色方向，如喜欢粉色→优先玫瑰/裸粉系）
- 不喜欢颜色：${p?.avoidColors.isNotEmpty == true ? '⚠️ 回避这些色调的口红：${p!.avoidColors.join('、')}' : '无限制'}
- 彩妆预算：${p?.beautyBudget?.label ?? p?.budget?.label ?? '未知，给不同价位各推一个'}

【肤色精准适配】
- 冷白皮：正红/玫红/蓝调口红最显白；避开土橘、暖棕
- 暖黄皮：橘红/砖红/暖棕最提气色；避开偏蓝紫调
- 小麦色：裸棕/深豆沙/砖红稳稳好看；避免太浅透的裸粉
- 中性肤：豆沙/玫瑰/正红几乎通吃

本次推荐侧重（融入建议，让回复有新鲜感）："$seed"

只输出JSON：
{
  "reply": "开口就告诉她她肤色适合什么色系，为什么（越具体越好，如'你暖黄皮，橘调豆沙色一涂气色好3倍'），30-40字",
  "quick_replies": ["国货平替有哪些", "哑光还是水润好", "日常上班用哪个", "约会首选色号"],
  "cards": [
    {
      "title": "品牌+色号名（如：YSL#416 裸金玫瑰）",
      "subtitle": "为什么适合她的肤色，涂上的效果，适合什么场合",
      "tags": ["适合肤色", "色系调性", "质地/场合"],
      "price": "¥xxx",
      "buy_keyword": "品牌名+色号关键词"
    }
  ]
}
''';
  }

  String _skinPrompt(UserProfile? p) {
    // 多样性种子（护肤侧重点）
    final seeds = ['成分党视角', '快速见效', '敏感友好', '平价好用', '成分协同搭配'];
    final seed = seeds[(DateTime.now().minute + DateTime.now().second) % seeds.length];
    final timeOfDay = _getTimeOfDay();
    final season = _getRealSeason();
    final city = p?.city ?? '';

    // 时段感知：早晨/晚上护肤步骤差异
    final String timeRoutineHint;
    if (timeOfDay == '早晨' || timeOfDay == '上午') {
      timeRoutineHint = '⏰ 早间护肤：清洁→精华→乳液/面霜→【必须】防晒（SPF30+）；早晨推清爽/轻薄质地，不推厚重修复产品';
    } else if (timeOfDay == '晚上' || timeOfDay == '深夜') {
      timeRoutineHint = '🌙 晚间护肤：卸妆→清洁→精华（功效优先，如A醇/烟酰胺/果酸）→面霜→可加面膜；晚上是修复黄金期，功效精华全在这里上';
    } else {
      timeRoutineHint = '给出早C晚A完整方案，早间防晒必须有，晚间功效精华优先';
    }

    // 季节感知：不同季节皮肤状态和护肤重点
    final String seasonSkinHint;
    switch (season) {
      case '春季':
        seasonSkinHint = '春季换季皮肤易敏感/泛红，屏障修护+防晒为主；控油水分平衡；推轻薄质地';
        break;
      case '夏季':
        seasonSkinHint = '夏季出油多/毛孔大/防晒是重中之重；油皮用无油配方；轻薄乳液/凝胶质地，必晒后修护';
        break;
      case '秋季':
        seasonSkinHint = '秋季干燥换季，补水力度加强，可以开始用更滋润的面霜和精华；维A醇入门好时机（夏天结束紫外线弱）';
        break;
      case '冬季':
        seasonSkinHint = '冬季皮肤屏障最弱，干皮加强神经酰胺/角鲨烷封锁；洗脸水温不要过热；面霜必须换厚款；唇部护理也加进来';
        break;
      default:
        seasonSkinHint = '结合当季气候调整护肤步骤';
    }

    // 城市特殊护肤提示（高原/海边/南北差异）
    final String citySpecialHint;
    final isHighAltitude = city.contains('昆明') || city.contains('贵阳') || city.contains('成都') ||
        city.contains('拉萨') || city.contains('西藏') || city.contains('青海') ||
        city.contains('丽江') || city.contains('大理') || city.contains('西宁') ||
        city.contains('高原');
    final isCoastal = city.contains('三亚') || city.contains('厦门') || city.contains('青岛') ||
        city.contains('海口') || city.contains('北海') || city.contains('舟山') ||
        city.contains('海南') || city.contains('珠海') || city.contains('湛江');
    final isSouth = city.contains('广州') || city.contains('深圳') || city.contains('广东') ||
        city.contains('福建') || city.contains('广西') || city.contains('重庆') ||
        city.contains('湖南') || city.contains('上海') || city.contains('杭州');
    if (isHighAltitude) {
      citySpecialHint = '⚠️ 高原城市特别提示：紫外线超强（海拔每升高1000m，UV增强约10%），防晒必须SPF50+PA++++，且每2小时补涂；空气干燥，保湿力度加倍；推矿物防晒/物理防晒减少刺激';
    } else if (isCoastal) {
      citySpecialHint = '⚠️ 海边/沿海城市特别提示：盐雾+湿气+强紫外线三重挑战；防晒SPF50+防水型；高湿度下油皮更易出油，推清爽无油配方；海风大容易干燥缺水，补水不能省';
    } else if (isSouth) {
      citySpecialHint = '南方湿热：控油/轻质地优先；防晒全年必须；高湿度下厚质地面霜容易闷痘，推凝露/凝胶质地';
    } else {
      citySpecialHint = ''; // 北方已在主 prompt 中处理
    }

    // quick_replies 按肤质动态调整
    final skinType = p?.skinType?.label ?? '';
    final List<String> skinQuickReplies;
    if (skinType.contains('油') || skinType.contains('痘')) {
      skinQuickReplies = ['控油精华推荐', '刷酸怎么用', '不会长痘的防晒', '毛孔怎么缩小'];
    } else if (skinType.contains('干')) {
      skinQuickReplies = ['补水最强的精华', '面霜怎么选', '角鲨烷和玻尿酸区别', '冬天加强保湿方案'];
    } else if (skinType.contains('混')) {
      skinQuickReplies = ['T区控油怎么做', '分区护理方案', '精华推荐', '换季敏感怎么办'];
    } else if (skinType.contains('敏')) {
      skinQuickReplies = ['屏障修护精华', '成分越少越好的推荐', '换季泛红怎么办', '哪些成分要避开'];
    } else {
      skinQuickReplies = ['平价替代有哪些', '用的顺序是什么', '这个成分我能用吗', '再推个防晒'];
    }

    return '''
【任务：护肤方案】针对用户肤质和皮肤问题，给个性化护肤方案，必须规避过敏成分。
- 当前时段：$timeOfDay（$timeRoutineHint）
- 当前季节：$season（⚠️ 季节护肤重点：$seasonSkinHint）
- 肤质：${p?.skinType?.label ?? '未知，先问肤质（干/油/混合/敏感）'}
- 皮肤问题：${p?.skinConcerns.isNotEmpty == true ? p!.skinConcerns.join('、') : '未填，可以问主要困扰是什么'}
- 过敏/排斥成分：${p?.allergens.isNotEmpty == true ? '⚠️ 必须严格排除：${p!.allergens.join('、')}' : '无已知过敏'}
- 年龄段：${p?.ageGroup?.label ?? '未填'}（18岁→基础保湿防晒；25岁→抗氧化+早C晚A；35岁↑→多肽/胶原/抗老精华优先）
- 肤色：${p?.skinTone?.label ?? '未知'}（暖黄皮可重点关注烟酰胺提亮；冷白皮屏障修护优先；小麦色可加VC/熊果苷）
- 城市：${p?.city ?? '未填'}（北方干燥→神经酰胺/角鲨烷加强封锁；南方湿热→轻质地/控油为主）${citySpecialHint.isNotEmpty ? '\n- ⚠️ 城市特殊提示：$citySpecialHint' : ''}
- 护肤预算：${p?.beautyBudget?.label ?? p?.budget?.label ?? '未知，给不同价位各推一个'}

【肤质核心策略】
- 敏感肌：修护屏障优先，成分越简洁越好，避开酒精/香精/高浓度酸
- 油痘肌：水油平衡，可用水杨酸/烟酰胺，轻薄质地
- 干性肌：补水+封锁，玻尿酸/神经酰胺/角鲨烷
- 混合肌：T区控油，两颊保湿，分区护理
- 抗老：维A醇/视黄醇/多肽（敏感肌低浓度入门）

本次推荐侧重（融入建议，让回复有新鲜感）："$seed"

只输出JSON：
{
  "reply": "开口就说她的核心肤质问题+解决方向（如'你混合偏油，T区控油、两颊补水才是正确打开方式'），30-50字",
  "quick_replies": ${jsonEncode(skinQuickReplies)},
  "cards": [
    {
      "title": "具体产品名称（品牌+产品线）",
      "subtitle": "针对她肤质问题的效果，是否含过敏成分（如有则明确说）",
      "tags": ["适合肤质", "核心功效", "价位/品牌调性"],
      "price": "¥xxx",
      "buy_keyword": "产品精准搜索词"
    }
  ]
}
''';
  }

  String _ingredientPrompt(UserProfile? p) {
    final hasAllergens = p?.allergens.isNotEmpty == true;
    final allergenStr = hasAllergens ? p!.allergens.join('、') : '无已知过敏';
    final skinTypeStr = p?.skinType?.label ?? '未知';
    final skinConcernsStr = p?.skinConcerns.isNotEmpty == true
        ? p!.skinConcerns.join('、')
        : '未知';

    return '''
【当前任务：成分安全分析】专业成分党视角，帮用户判断产品成分是否安全可用。

用户档案：
- 肤质：$skinTypeStr
- 皮肤困扰：$skinConcernsStr
- 年龄段：${p?.ageGroup?.label ?? '未知'}（18岁以下慎推高浓A醇/水杨酸；孕期⚠️需规避A酸/视黄醇/水杨酸/咖啡因高浓）
- 肤色：${p?.skinTone?.label ?? '未知'}（暖黄皮关注提亮成分适配性；冷白皮关注刺激性成分）
- ${hasAllergens ? '⚠️ 已知过敏/排斥成分：$allergenStr（必须严格排查！有冲突必须明说）' : '无已知过敏记录'}

【⚠️ 孕期成分特别警报】
如果用户消息中提到「孕期」「备孕」「怀孕」「哺乳期」，或档案中有相关信息：
必须首先评估以下高风险成分（孕期/哺乳期需严格规避）：
- 🔴 强制规避：A酸/全反式维A酸/视黄醇（高浓）/水杨酸（高浓）/苯甲醇/甲醛释放剂
- 🔴 谨慎对待：高浓度咖啡因/精油类/某些精华素
- 🟡 孕期可用：烟酰胺/玻尿酸/神经酰胺/维C（温和型）/SPF防晒（物理防晒更安全）

【分析框架 - 按以下顺序输出】
1. 过敏风险（最高优先级）：是否含有用户过敏成分？有则STOP直接说
2. 肤质适配：对$skinTypeStr是否友好？原因是什么？
3. 主要功效：核心成分能解决什么问题（补水/抗老/控油/修护等）
4. 成分协同/冲突：有没有互相增效或互相"打架"的成分组合？
5. 安全等级评定：🟢安全可用 / 🟡谨慎使用 / 🔴建议避开

输出规则：
- 如果有过敏风险，reply开头必须说"⚠️ 注意！"
- 技术词用括号解释（如：烟酰胺（维生素B3，控油+提亮））
- 不要用"大概""可能"这类模糊词，明确说"适合/不适合"

只输出JSON：
{
  "reply": "总结评价（开门见山说结论，有风险先说风险，30-50字）",
  "quick_replies": ["${hasAllergens ? '这成分和我过敏原冲突吗' : '适合敏感肌吗'}", "有没有替代成分", "使用顺序对吗", "帮我查另一个产品"],
  "cards": [
    {
      "title": "成分名（中英文都写，如：烟酰胺 Niacinamide）",
      "subtitle": "功效+适合肤质+风险评级（🟢/🟡/🔴）",
      "tags": ["功效", "适合肤质/冲突", "浓度参考"]
    }
  ]
}
''';
  }

  /// 检测关键字段缺失，生成精准追问提示（只追问最关键的1个，带具体范例）
  String _buildMissingHint(String intent, UserProfile? p) {
    if (p == null) return '';

    // ── 穿搭/天气/场合/情绪：身材 > 风格 ──────────────────────
    if (intent == _intentOutfit || intent == _intentOccasion ||
        intent == _intentWeather || intent == _intentMood) {
      if (p.bodyShape == null) {
        return '''
【追问指令 - 关键档案缺失】⚠️ 只追问一个，不要问多个！
用户的「身材类型」未知，你无法精准避开劣势。
请在回复末尾自然地追问（不要生硬），例如：
  - "你是梨形还是苹果型？我好给你专门绕开腿粗的穿法"
  - "你觉得自己哪里想遮一遮？上半身还是下半身？"
  - "直接说腰/腿/肩哪个是你想显的，我来搭"
⚠️ 若用户消息里已经隐含身材信息（如"我腿粗/肚子肉"），直接用，不要再问！
''';
      }
      if (p.styleType == null) {
        return '''
【追问指令 - 关键档案缺失】⚠️ 只追问一个，不要问多个！
用户的「风格偏好」未知，给的方案可能不合胃口。
请在回复末尾自然地追问，例如：
  - "你平时更偏法式简约还是韩系休闲，我调整方向"
  - "你喜欢有设计感的款式，还是那种百搭安全款？"
⚠️ 若用户已表达了风格倾向（如"我喜欢简单的"），直接用，不要再问！
''';
      }
    }

    // ── 口红彩妆：肤色 ─────────────────────────────────────────
    else if (intent == _intentLipstick) {
      if (p.skinTone == null) {
        return '''
【追问指令 - 关键档案缺失】⚠️ 只追问一个！
用户肤色未知，无法判断哪个色号显白还是显黄。
请在回复末尾自然地追问，例如：
  - "你是冷白皮还是暖黄皮？（冷白=白里透粉，暖黄=黄里透暖）"
  - "你手腕内侧的血管是蓝紫色还是绿色？蓝紫是冷调，绿色是暖调"
⚠️ 若用户已说过肤色信息，直接用！
''';
      }
    }

    // ── 护肤：肤质 > 皮肤困扰 ──────────────────────────────────
    else if (intent == _intentSkin) {
      if (p.skinType == null) {
        return '''
【追问指令 - 关键档案缺失】⚠️ 只追问一个！
用户肤质未知，给护肤建议会不够准。
请在回复末尾自然地追问，例如：
  - "你洗完脸不涂任何东西，20分钟后T区是不是开始出油？"
  - "你皮肤容易干还是油？还是两颊干T区油那种混合皮？"
⚠️ 若用户已说过肤质（如"我是干皮"），直接用，不要再问！
''';
      }
      if (p.skinConcerns.isEmpty) {
        return '''
【追问指令 - 档案缺失】⚠️ 只问一个！
用户主要皮肤困扰未知，无法锁定最有效的护肤成分。
请自然地追问：
  - "你现在最困扰的是痘痘、暗沉，还是干燥或细纹？"
  - "最近皮肤最烦的是什么——出油、泛红、还是显老？"
''';
      }
    }

    // ── 成分分析：肤质 ──────────────────────────────────────────
    else if (intent == _intentIngredient) {
      if (p.skinType == null) {
        return '''
【追问指令 - 关键档案缺失】⚠️ 只追问一个！
用户肤质未知，成分适配性分析会不准确（同一成分对干皮/油皮/敏感肌完全不同）。
请在回复末尾自然地追问，例如：
  - "你是干皮、油皮，还是敏感肌？（肤质不同，这个成分是否适合你差别很大）"
  - "你皮肤有没有容易泛红/刺痛的情况？先确认肤质我才好帮你判断"
⚠️ 若用户已说过肤质，直接用，不要再问！
''';
      }
    }

    return ''; // 没有关键缺失字段，无需追问
  }

  // ─── 档案信息提取（从对话中学习用户信息）─────────────────────

  /// 从用户输入和 AI 回复中提取可能的档案更新信息
  /// 支持自动提取：肤色/肤质/身材/风格/身高/体重/城市/年龄/尺码/季型
  Map<String, String> _extractProfileHints(String userMsg, String aiReply) {
    final hints = <String, String>{};
    final t = userMsg;
    final tl = t.toLowerCase();

    // ── 肤色 ─────────────────────────────────────────────────
    if (tl.contains('冷白') || tl.contains('白皮') || tl.contains('冷调白')) {
      hints['skinTone'] = 'coolWhite';
    } else if (tl.contains('暖黄') || tl.contains('黄皮') || tl.contains('暖调')) {
      hints['skinTone'] = 'warmYellow';
    } else if (tl.contains('小麦') || tl.contains('健康色') || tl.contains('麦色')) {
      hints['skinTone'] = 'wheat';
    } else if (tl.contains('深肤') || tl.contains('黑皮') || tl.contains('偏黑')) {
      hints['skinTone'] = 'deep';
    } else if (tl.contains('中性肤') || tl.contains('自然肤')) {
      hints['skinTone'] = 'neutral';
    }

    // ── 肤质 ─────────────────────────────────────────────────
    if (tl.contains('干皮') || tl.contains('皮肤干') || tl.contains('缺水') ||
        tl.contains('干燥')) {
      hints['skinType'] = 'dry';
    } else if (tl.contains('油皮') || tl.contains('出油') || tl.contains('油性')) {
      hints['skinType'] = 'oily';
    } else if (tl.contains('混油') || tl.contains('混合肌') || tl.contains('混合皮')) {
      hints['skinType'] = 'combination';
    } else if (tl.contains('敏感肌') || tl.contains('皮肤敏感') || tl.contains('敏感皮')) {
      hints['skinType'] = 'sensitive';
    } else if (tl.contains('痘痘') || tl.contains('长痘') || tl.contains('痤疮')) {
      hints['skinType'] = 'acneProne';
    }

    // ── 身材 ─────────────────────────────────────────────────
    if (tl.contains('梨形') || tl.contains('下半身胖') || tl.contains('大腿粗') ||
        tl.contains('臀胯宽')) {
      hints['bodyShape'] = 'pear';
    } else if (tl.contains('苹果') || tl.contains('腰粗') || tl.contains('小肚子') ||
        tl.contains('水桶腰')) {
      hints['bodyShape'] = 'apple';
    } else if (tl.contains('沙漏') || tl.contains('腰细') || tl.contains('腰细臀宽')) {
      hints['bodyShape'] = 'hourglass';
    } else if (tl.contains('直筒') || tl.contains('平胸') || tl.contains('纸片身材')) {
      hints['bodyShape'] = 'rectangle';
    } else if (tl.contains('倒三角') || tl.contains('肩宽')) {
      hints['bodyShape'] = 'invertedTriangle';
    }

    // ── 穿搭风格 ──────────────────────────────────────────────
    if (tl.contains('甜美') || tl.contains('可爱风') || tl.contains('少女感')) {
      hints['styleType'] = 'sweet';
    } else if (tl.contains('知性') || tl.contains('文艺风') || tl.contains('ins风')) {
      hints['styleType'] = 'intellectual';
    } else if (tl.contains('酷飒') || tl.contains('帅气') || tl.contains('酷的') ||
        tl.contains('中性风')) {
      hints['styleType'] = 'cool';
    } else if (tl.contains('优雅') || tl.contains('气质') || tl.contains('淑女')) {
      hints['styleType'] = 'elegant';
    } else if (tl.contains('通勤') && tl.contains('风')) {
      hints['styleType'] = 'office';
    } else if (tl.contains('运动风') || tl.contains('运动休闲')) {
      hints['styleType'] = 'sport';
    } else if (tl.contains('法式') || tl.contains('复古风')) {
      hints['styleType'] = 'french';
    } else if (tl.contains('韩系') || tl.contains('韩风')) {
      hints['styleType'] = 'korean';
    } else if (tl.contains('日系') || tl.contains('森女')) {
      hints['styleType'] = 'japanese';
    }

    // ── 身高（正则提取数字，如 "我身高165" "165cm"） ─────────
    final heightMatch = RegExp(r'身高[是为]?\s*(\d{3})').firstMatch(t);
    if (heightMatch != null) {
      final h = int.tryParse(heightMatch.group(1) ?? '');
      if (h != null && h >= 140 && h <= 200) hints['height'] = h.toString();
    }
    final cmMatch = RegExp(r'(\d{3})\s*cm').firstMatch(tl);
    if (cmMatch != null && !hints.containsKey('height')) {
      final h = int.tryParse(cmMatch.group(1) ?? '');
      if (h != null && h >= 140 && h <= 200) hints['height'] = h.toString();
    }

    // ── 体重（如 "我体重50kg" "50公斤"） ─────────────────────
    final weightMatch = RegExp(r'体重[是为]?\s*(\d{2,3})').firstMatch(t);
    if (weightMatch != null) {
      final w = int.tryParse(weightMatch.group(1) ?? '');
      if (w != null && w >= 30 && w <= 150) hints['weight'] = w.toString();
    }
    final kgMatch = RegExp(r'(\d{2,3})\s*(kg|公斤|斤)').firstMatch(tl);
    if (kgMatch != null && !hints.containsKey('weight')) {
      var w = int.tryParse(kgMatch.group(1) ?? '');
      if (w != null) {
        if (kgMatch.group(2) == '斤') w = (w / 2).round(); // 斤→kg
        if (w >= 30 && w <= 150) hints['weight'] = w.toString();
      }
    }

    // ── 城市（直接说城市名，如"我在北京" "北京的" ） ─────────
    final cityMatch = RegExp(r'(我在|住在|我是|我来自)\s*([^\s，,。！？]{2,5}[市区省])').firstMatch(t);
    if (cityMatch != null) {
      hints['city'] = cityMatch.group(2) ?? '';
    }
    // 直接说"北京" "上海" "广州"等一二线城市名
    final topCities = ['北京', '上海', '广州', '深圳', '成都', '杭州', '武汉', '南京',
      '西安', '重庆', '苏州', '天津', '郑州', '长沙', '沈阳', '大连', '哈尔滨'];
    for (final city in topCities) {
      if (t.contains(city) && !hints.containsKey('city')) {
        hints['city'] = city;
        break;
      }
    }

    // ── 年龄/年龄段（如"我22岁" "我是90后"） ─────────────────
    final ageMatch = RegExp(r'我?[今今年]?\s*(\d{2})\s*(岁|周岁)').firstMatch(t);
    if (ageMatch != null) {
      final age = int.tryParse(ageMatch.group(1) ?? '');
      if (age != null && age >= 14 && age <= 65) {
        // 映射到 AgeGroup 枚举：teen/youngAdult/adult/mature/midAge/senior
        if (age < 18) hints['ageGroup'] = 'teen';
        else if (age < 25) hints['ageGroup'] = 'youngAdult';
        else if (age < 31) hints['ageGroup'] = 'adult';
        else if (age < 41) hints['ageGroup'] = 'mature';
        else if (age < 51) hints['ageGroup'] = 'midAge';
        else hints['ageGroup'] = 'senior';
      }
    }
    if (tl.contains('00后')) hints['ageGroup'] = 'youngAdult';
    else if (tl.contains('95后')) hints['ageGroup'] = 'youngAdult';
    else if (tl.contains('90后')) hints['ageGroup'] = 'adult';
    else if (tl.contains('85后')) hints['ageGroup'] = 'mature';
    else if (tl.contains('80后')) hints['ageGroup'] = 'mature';

    // ── 尺码（如"我穿M" "XL码" ） ────────────────────────────
    final sizeMatch = RegExp(r'(穿|码)\s*(XS|S|M|L|XL|XXL|xs|s|m|l|xl|xxl)').firstMatch(t);
    if (sizeMatch != null) {
      hints['clothingSize'] = sizeMatch.group(2)?.toUpperCase() ?? '';
    }

    // ── 色彩季型 ──────────────────────────────────────────────
    if (tl.contains('春季型') || (tl.contains('春型') && !tl.contains('春季'))) {
      hints['seasonType'] = 'spring';
    } else if (tl.contains('夏季型') || tl.contains('夏型色')) {
      hints['seasonType'] = 'summer';
    } else if (tl.contains('秋季型') || tl.contains('秋型色')) {
      hints['seasonType'] = 'autumn';
    } else if (tl.contains('冬季型') || tl.contains('冬型色')) {
      hints['seasonType'] = 'winter';
    }

    return hints;
  }

  String _describeProfile(UserProfile p) {
    final parts = <String>[];
    parts.add('昵称：${p.nickname}');
    if (p.ageGroup != null) parts.add('年龄段：${p.ageGroup!.label}');
    if (p.skinTone != null) parts.add('肤色：${p.skinTone!.label}');
    if (p.faceShape != null) parts.add('脸型：${p.faceShape!.label}');
    if (p.bodyShape != null) parts.add('身材：${p.bodyShape!.label}');
    if (p.height != null) parts.add('身高：${p.height}cm');
    if (p.weight != null) parts.add('体重：${p.weight}kg');
    if (p.clothingSize != null) parts.add('常穿尺码：${p.clothingSize!.label}');
    if (p.styleType != null) parts.add('穿搭风格偏好：${p.styleType!.label}');
    if (p.seasonType != null) parts.add('色彩季型：${p.seasonType!.label}');
    if (p.occasions.isNotEmpty) {
      parts.add('常见穿搭场景：${p.occasions.map((e) => e.label).join('、')}');
    }
    if (p.favoriteColors.isNotEmpty) {
      parts.add('喜欢的颜色：${p.favoriteColors.join('、')}');
    }
    if (p.avoidColors.isNotEmpty) {
      parts.add('不喜欢/不适合的颜色：${p.avoidColors.join('、')}');
    }
    if (p.budget != null) parts.add('服装预算（单件）：${p.budget!.label}');
    if (p.beautyBudget != null) parts.add('美妆护肤预算（单品）：${p.beautyBudget!.label}');
    if (p.skinType != null) parts.add('肤质：${p.skinType!.label}');
    if (p.skinConcerns.isNotEmpty) {
      parts.add('皮肤问题：${p.skinConcerns.join('、')}');
    }
    if (p.allergens.isNotEmpty) {
      parts.add('过敏/排斥成分：${p.allergens.join('、')}（推荐护肤品时必须严格规避）');
    }
    if (p.city != null && p.city!.isNotEmpty) parts.add('所在城市：${p.city}');

    // 档案完整度提示
    final rate = (p.completionRate * 100).toInt();
    if (rate < 60) {
      parts.add('（档案完整度 $rate%，推荐时请注意缺失字段，适当追问）');
    }

    return parts.join('\n');
  }

  // ─── 调用 LLM ────────────────────────────────────────────────

  Future<String?> _callLLM(List<Map<String, String>> messages) async {
    final apiKey = _deepSeekKey;
    if (AppConfig.useMock) {
      AppLogger.d('AiService', 'Key 未配置，走 Mock 响应');
      final profile = StorageService.to.loadProfile();
      return _mockResponse(messages.last['content'] ?? '', profile);
    }

    try {
      return await RetryHelper.run<String?>(
        tag: 'AiService._callLLM',
        maxRetries: AppConfig.maxRetries,
        action: () async {
          final resp = await http
              .post(
                Uri.parse('$_deepSeekBase/chat/completions'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({
                  'model': _deepSeekModel,
                  'messages': messages,
                  'temperature': 0.75,
                  'max_tokens': 1000,
                }),
              )
              .timeout(_timeout);

          if (resp.statusCode == 200) {
            final data = jsonDecode(utf8.decode(resp.bodyBytes));
            return data['choices'][0]['message']['content'] as String?;
          }

          // 抛出结构化异常，让 RetryHelper 判断是否重试
          throw ErrorMapper.from(
            'HTTP ${resp.statusCode}',
            statusCode: resp.statusCode,
          );
        },
      );
    } on AppException catch (e) {
      AppLogger.e('AiService', '_callLLM 最终失败: ${e.message}', e);
      // 将友好提示透传给上层（由上层决定如何展示）
      return '__error__:${e.message}';
    } catch (e, st) {
      final appErr = ErrorMapper.from(e);
      AppLogger.e('AiService', '_callLLM 未知异常', appErr, st);
      return '__error__:${appErr.message}';
    }
  }

  // ─── 解析 LLM 输出 ─────────────────────────────────────────

  /// 🛡️ 第四道防线：对 AI 回复中的外部平台引流文字做净化
  /// 当商品库有匹配时这段代码不会触达（已在上层拦截），
  /// 但商品库完全空时 AI 自由回复也不应该带"去淘宝搜"这类话。
  String _sanitizeReply(String reply, {bool hasOwnProducts = false}) {
    if (hasOwnProducts) return reply; // 有自营商品时不需要过滤（AI已被严格约束）

    // 平台引流黑名单词组
    final blockedPhrases = [
      RegExp(r'去(淘宝|京东|拼多多|抖音|小红书|天猫|当当|苏宁).{0,8}(搜|搜索|找|购买|购买|下单|买)'),
      RegExp(r'(淘宝|京东|拼多多|抖音商城).{0,6}(搜索|搜)["「]'),
      RegExp(r'搜索关键词[：:]\s*["「]?[\w\u4e00-\u9fa5]+["」]?'),
      RegExp(r'在(淘宝|京东|天猫|拼多多|小红书)上?搜'),
      RegExp(r'直接(去|在)(淘宝|京东|天猫)'),
    ];

    String cleaned = reply;
    for (final pattern in blockedPhrases) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    // 清理因替换留下的多余标点/空白
    cleaned = cleaned
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'[，,]\s*[，,]'), '，')
        .trim();
    return cleaned.isEmpty ? reply : cleaned; // 万一全被删了，退回原始
  }

  AiResponse _parseResponse(String raw, String intent) {
    // chat/photo：先尝试提取 quick_replies，然后返回纯文字
    if (intent == _intentChat || intent == _intentPhoto) {
      final extracted = _extractJson(raw);
      if (extracted != null) {
        try {
          final json = jsonDecode(extracted) as Map<String, dynamic>;
          final aiQuickReplies = List<String>.from(
            (json['quick_replies'] as List<dynamic>? ?? [])
          );
          final reply = (json['reply'] as String?)?.isNotEmpty == true
              ? json['reply'] as String
              : raw.trim();
          return AiResponse(
            reply: _sanitizeReply(reply),
            cards: const [],
            quickReplies: aiQuickReplies,
          );
        } catch (_) {}
      }
      return AiResponse.text(_sanitizeReply(raw.trim()));
    }

    final extracted = _extractJson(raw);
    if (extracted != null) {
      try {
        final json = jsonDecode(extracted) as Map<String, dynamic>;
        final reply = json['reply'] as String? ?? '';
        final rawCards = json['cards'] as List<dynamic>? ?? [];
        // ✅ 提取 AI 动态生成的 quick_replies
        final aiQuickReplies = List<String>.from(
          (json['quick_replies'] as List<dynamic>? ?? [])
        );

        // 🛡️ AI 生成的卡片：buy_keyword 是外部搜索词，isOwnProduct=false
        // 但 title 里若包含平台名称（"淘宝搜xxx"），做一下清理
        final cards = rawCards.asMap().entries.map((entry) {
          final m = entry.value as Map<String, dynamic>;
          final rawTitle = m['title'] as String? ?? '';
          final cleanTitle = _cleanProductTitle(rawTitle);
          return ResultCard(
            id: '${DateTime.now().microsecondsSinceEpoch}_${entry.key}',
            type: _cardTypeFromIntent(intent),
            title: cleanTitle,
            subtitle: m['subtitle'] as String?,
            tags: List<String>.from(m['tags'] ?? []),
            price: (m['price'] ?? m['price_range']) as String?,
            buyUrl: m['buy_keyword'] as String?,
            isOwnProduct: false, // 明确标记为非自营
          );
        }).toList();

        if (cards.isNotEmpty) {
          return AiResponse(
            reply: _sanitizeReply(reply.isNotEmpty ? reply : raw.trim()),
            cards: cards,
            quickReplies: aiQuickReplies,
          );
        }

        // 有 reply 但无卡片的情况（AI 在追问用户）
        if (reply.isNotEmpty) {
          return AiResponse(
            reply: _sanitizeReply(reply),
            cards: const [],
            quickReplies: aiQuickReplies,
          );
        }
      } catch (_) {}
    }

    // Fallback：从文字中提取关键词生成卡片
    if (intent != _intentChat) {
      final fallbackCards = _buildFallbackCards(raw, intent);
      if (fallbackCards.isNotEmpty) {
        final shortReply = raw.trim().length > 120
            ? '${raw.trim().substring(0, 120)}...'
            : raw.trim();
        return AiResponse(
          reply: _sanitizeReply(shortReply),
          cards: fallbackCards,
        );
      }
    }

    return AiResponse.text(_sanitizeReply(raw.trim()));
  }

  /// 清理 AI 生成的商品标题里可能带的平台词
  String _cleanProductTitle(String title) {
    return title
        .replaceAll(RegExp(r'(淘宝|京东|拼多多|天猫|抖音|小红书).{0,4}(搜|购买|链接)?'), '')
        .replaceAll(RegExp(r'^\s*[：:\s]+'), '')
        .trim();
  }

  String? _extractJson(String raw) {
    var s = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return s.substring(start, end + 1);
  }

  List<ResultCard> _buildFallbackCards(String text, String intent) {
    final cardType = _cardTypeFromIntent(intent);
    final items = <({String title, String keyword})>[];

    // 优先提取「搜 "xxx"」格式
    final searchPattern = RegExp(
      r'搜(?:索|一下)?\s*["""「]([^"""」\n]{2,40})["""」]',
    );
    for (final m in searchPattern.allMatches(text)) {
      final kw = m.group(1)?.trim() ?? '';
      if (kw.isNotEmpty && !items.any((e) => e.keyword == kw)) {
        final displayTitle = kw.replaceAll(RegExp(r'(套装|搭配|款|系列)$'), '').trim();
        items.add((title: displayTitle.isEmpty ? kw : displayTitle, keyword: kw));
      }
    }

    // 提取加粗内容
    final boldPattern = RegExp(r'\*\*([^*]{2,30})\*\*');
    for (final m in boldPattern.allMatches(text)) {
      final t = m.group(1)?.trim() ?? '';
      if (t.isNotEmpty && !items.any((e) => e.title == t)) {
        final lineStart = text.lastIndexOf('\n', m.start) + 1;
        final lineEnd = text.indexOf('\n', m.end).let((i) => i == -1 ? text.length : i);
        final line = text.substring(lineStart, lineEnd);
        final kwMatch = RegExp(r'["""「]([^"""」\n]{3,40})["""」]').firstMatch(line);
        final kw = kwMatch?.group(1)?.trim() ?? t;
        items.add((title: t, keyword: kw));
      }
    }

    // 提取引号内容
    final quotePattern = RegExp(r'「([^」]{2,20})」|["""]([^"""]{2,20})["""]');
    for (final m in quotePattern.allMatches(text)) {
      final t = (m.group(1) ?? m.group(2))?.trim() ?? '';
      if (t.isNotEmpty && !items.any((e) => e.title == t || e.keyword == t)) {
        items.add((title: t, keyword: t));
      }
    }

    if (items.isEmpty) return [];

    return items.take(4).toList().asMap().entries.map((e) {
      final keyword = e.value.keyword.replaceAll(RegExp(r'[+\+＋]'), ' ').trim();
      return ResultCard(
        id: '${DateTime.now().microsecondsSinceEpoch}_fb_${e.key}',
        type: cardType,
        title: e.value.title,
        subtitle: _guessSubtitle(intent),
        tags: _guessTags(intent),
        price: null,
        buyUrl: keyword,
      );
    }).toList();
  }

  String _guessSubtitle(String intent) {
    if (intent == _intentOutfit || intent == _intentOccasion || intent == _intentWeather) {
      return '点击选择平台搜索这套穿搭';
    }
    if (intent == _intentLipstick) return '点击选择平台查看色号';
    if (intent == _intentSkin) return '点击选择平台了解产品';
    return '点击选择购物平台搜索';
  }

  List<String> _guessTags(String intent) {
    if (intent == _intentOutfit || intent == _intentOccasion) return ['穿搭', 'AI推荐'];
    if (intent == _intentWeather) return ['天气穿搭', 'AI推荐'];
    if (intent == _intentMood) return ['心情穿搭', 'AI推荐'];
    if (intent == _intentLipstick) return ['口红', 'AI推荐'];
    if (intent == _intentSkin) return ['护肤', 'AI推荐'];
    return ['AI推荐'];
  }

  CardType _cardTypeFromIntent(String intent) {
    switch (intent) {
      case _intentOutfit:
      case _intentOccasion:
      case _intentWeather:
      case _intentMood:
        return CardType.outfit;
      case _intentLipstick:
        return CardType.lipstick;
      case _intentSkin:
      case _intentIngredient:  // 成分检测结果也归类为护肤产品卡片
        return CardType.skincare;
      default:
        return CardType.product;
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  📸 形象诊断
  // ══════════════════════════════════════════════════════════════

  Future<AnalysisResult> analyzePhoto({
    String? imagePath,
    Uint8List? imageBytes,
    UserProfile? profile,
  }) async {
    final hasVision = _visionKey.isNotEmpty;
    if (!hasVision) {
      await Future.delayed(const Duration(seconds: 2));
      return AnalysisResult.mock();
    }

    String base64Image;
    try {
      if (imageBytes != null) {
        base64Image = base64Encode(imageBytes);
      } else if (imagePath != null && !kIsWeb) {
        final bytes = await File(imagePath).readAsBytes();
        base64Image = base64Encode(bytes);
      } else {
        return AnalysisResult.mock();
      }
    } catch (_) {
      return AnalysisResult.mock();
    }

    final profileDesc = profile != null ? _describeProfile(profile) : '（暂无档案）';
    final season = _getRealSeason();
    final prompt = '''
你是专业的色彩形象顾问，请仔细分析照片人物的外貌特征，给出权威形象诊断报告。

【用户档案参考】
$profileDesc

【色彩季型判断框架 - 必须按此标准判断】
- 春季型：暖色调+高明度，肤色明亮偏黄/桃，头发棕黄/金棕，眼睛棕色温柔。适合：暖黄/珊瑚/草绿/驼色。
- 夏季型：冷色调+低饱和，肤色粉调偏灰白，头发灰棕/亚麻，眼睛灰褐/蓝灰。适合：粉紫/薰衣草/冰蓝/玫灰。
- 秋季型：暖色调+低明度，肤色象牙/金棕，头发深棕/红棕，眼睛深棕/琥珀。适合：芥末黄/砖红/橄榄绿/咖色。
- 冬季型：冷色调+高对比，肤色白皙或深，发色深黑，眼睛深邃有神。适合：纯黑/纯白/正红/宝蓝/酒红。

【分析维度】必须以JSON格式输出（只输出JSON，不要其他文字）：
{
  "skin_tone": "肤色类型（冷白皮/暖黄皮/中性皮/小麦色/健康色/深肤色）+ 一句为什么",
  "face_shape": "脸型（鹅蛋脸/圆脸/方脸/长脸/心形脸/菱形脸）+ 特征说明",
  "body_shape": "身材类型（梨形/苹果/沙漏/直筒/倒三角/均匀）+ 如无法判断请写'照片角度有限，建议自测'",
  "season_type": "色彩季型（春/夏/秋/冬季型）+ 判断依据（提到肤色+发色+眼色中至少2个依据）",
  "recommended_colors": [
    {"name": "颜色中文名", "hex": "#十六进制色值", "reason": "为什么适合（10字以内）"}
  ],
  "avoid_colors": [
    {"name": "颜色名", "reason": "为什么不适合（10字以内）"}
  ],
  "outfit_advice": "针对脸型+身材的穿搭核心原则（2-3句，具体说'什么脸型适合什么领型'，不要泛泛说'选择适合的款式'）",
  "makeup_advice": "针对肤色+季型的妆容方向（提到腮红色系、口红色调，说具体颜色而不是'自然色'）",
  "skincare_advice": "针对肤色特点的护肤重点（如'暖黄皮重点提亮，推荐含烟酰胺/vc的精华'）",
  "style_keywords": ["最适合风格关键词1", "关键词2", "关键词3", "关键词4"],
  "hair_advice": "发型建议（针对脸型，如'圆脸适合高颅顶/侧分，避免刘海遮额头加宽脸'）",
  "summary": "2-3句整体点评，亲切温柔，像闺蜜一样。先说她的颜值优势，再说$season最适合她的穿搭方向"
}

要求：
- recommended_colors 提供6个颜色，必须带hex色值和reason
- avoid_colors 提供2-3个，说清楚为什么
- 所有建议要具体，不能用模糊词（"适合的款式"→"V领/一字领/深V都适合"）
- summary 要让用户看了心情好，带一个今天$season的穿搭行动建议
''';

    try {
      final resp = await http.post(
        Uri.parse('$_visionBase/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_visionKey',
        },
        body: jsonEncode({
          'model': _visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
              ],
            }
          ],
          'max_tokens': 1000,
        }),
      ).timeout(_timeout);

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String? ?? '';
        final jsonStr = _extractJson(content);
        if (jsonStr != null) {
          final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
          return AnalysisResult.fromJson(parsed, photoPath: imagePath);
        }
        AppLogger.w('AiService', 'analyzePhoto: 响应中未找到有效 JSON');
      } else {
        AppLogger.e('AiService', 'analyzePhoto HTTP ${resp.statusCode}');
      }
    } catch (e, st) {
      AppLogger.e('AiService', 'analyzePhoto 异常', ErrorMapper.from(e), st);
    }
    return AnalysisResult.mock();
  }

  // ══════════════════════════════════════════════════════════════
  //  🔬 成分检测
  // ══════════════════════════════════════════════════════════════

  Future<IngredientResult> analyzeIngredients({
    String? imagePath,
    Uint8List? imageBytes,
    UserProfile? profile,
  }) async {
    final hasVision = _visionKey.isNotEmpty;
    if (!hasVision) {
      await Future.delayed(const Duration(seconds: 2));
      return IngredientResult.mock();
    }

    String base64Image;
    try {
      if (imageBytes != null) {
        base64Image = base64Encode(imageBytes);
      } else if (imagePath != null && !kIsWeb) {
        final bytes = await File(imagePath).readAsBytes();
        base64Image = base64Encode(bytes);
      } else {
        return IngredientResult.mock();
      }
    } catch (_) {
      return IngredientResult.mock();
    }

    final allergenNote = (profile?.allergens.isNotEmpty == true)
        ? '用户已知过敏成分：${profile!.allergens.join('、')}'
        : '';
    final skinTypeNote = profile?.skinType != null
        ? '用户肤质：${profile!.skinType!.label}'
        : '';

    final prompt = '''
你是一位专业的护肤品成分分析师，请仔细识别照片中的产品成分表，对每个成分进行安全性分析。

【用户信息参考】
$skinTypeNote
$allergenNote

请以 JSON 格式输出分析结果（只输出 JSON，不要其他文字）：
{
  "product_name": "识别到的产品名称，如无则写\\"护肤品\\"",
  "safety_level": "整体安全等级：安全/温和/注意/风险",
  "safety_score": 0到100的整数（100=最安全）,
  "safe_ingredients": [
    {"name": "成分名", "function": "功能", "risk": "safe", "note": "简短说明"}
  ],
  "caution_ingredients": [
    {"name": "成分名", "function": "功能", "risk": "caution", "note": "注意原因"}
  ],
  "risk_ingredients": [
    {"name": "成分名", "function": "功能", "risk": "risk", "note": "风险说明"}
  ],
  "suitable_skin_types": ["适合肤质1", "肤质2"],
  "avoid_skin_types": ["不适合肤质1", "肤质2"],
  "summary": "综合评价，2-3句话，实用客观",
  "recommendation": "使用建议，1-2句话，针对用户肤质个性化"
}
''';

    try {
      final resp = await http.post(
        Uri.parse('$_visionBase/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_visionKey',
        },
        body: jsonEncode({
          'model': _visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
              ],
            }
          ],
          'max_tokens': 1200,
        }),
      ).timeout(_timeout);

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String? ?? '';
        final jsonStr = _extractJson(content);
        if (jsonStr != null) {
          final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
          return IngredientResult.fromJson(parsed, photoPath: imagePath);
        }
        AppLogger.w('AiService', 'analyzeIngredients: 响应中未找到有效 JSON');
      } else {
        AppLogger.e('AiService', 'analyzeIngredients HTTP ${resp.statusCode}');
      }
    } catch (e, st) {
      AppLogger.e('AiService', 'analyzeIngredients 异常', ErrorMapper.from(e), st);
    }
    return IngredientResult.mock();
  }

  // ══════════════════════════════════════════════════════════════
  //  💄 口红试色
  // ══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> analyzeLipColor({
    String? imagePath,
    Uint8List? imageBytes,
    UserProfile? profile,
  }) async {
    final hasVision = _visionKey.isNotEmpty;
    if (!hasVision) {
      await Future.delayed(const Duration(seconds: 1));
      return _mockLipColorResult(profile);
    }

    String base64Image;
    try {
      if (imageBytes != null) {
        base64Image = base64Encode(imageBytes);
      } else if (imagePath != null && !kIsWeb) {
        final bytes = await File(imagePath).readAsBytes();
        base64Image = base64Encode(bytes);
      } else {
        return _mockLipColorResult(profile);
      }
    } catch (_) {
      return _mockLipColorResult(profile);
    }

    final skinToneHint = profile?.skinTone != null
        ? '用户肤色：${profile!.skinTone!.label}'
        : '';
    final seasonHint = profile?.seasonType != null
        ? '色彩季型：${profile!.seasonType!.label}'
        : '';

    final prompt = '''
你是专业彩妆顾问，请分析照片中人物的肤色特征，推荐最适合的口红色系。

【用户档案参考】
$skinToneHint
$seasonHint

请以 JSON 格式输出（只输出 JSON，不加其他文字）：
{
  "skin_tone_analysis": "简短描述检测到的肤色特征（1句话）",
  "analysis": "根据肤色推荐口红色系的分析（2-3句话，亲切实用）",
  "suggested_shades": ["推荐色调1", "推荐色调2", "推荐色调3"],
  "avoid_shades": ["不建议色调1", "色调2"],
  "tip": "一句话选色小技巧"
}

suggested_shades 从以下选：正红/玫瑰红/草莓红/酒红/番茄红/豆沙/裸色/脏橘/裸粉/深豆沙/亮粉/玫瑰粉/浅粉/珊瑚橘/暖橘/深橘/雾霾紫/梅子
只推荐最适合当前肤色的2-4个色调。
''';

    try {
      final resp = await http.post(
        Uri.parse('$_visionBase/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_visionKey',
        },
        body: jsonEncode({
          'model': _visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                },
              ],
            }
          ],
          'max_tokens': 600,
        }),
      ).timeout(_timeout);

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String? ?? '';
        final jsonStr = _extractJson(content);
        if (jsonStr != null) {
          final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
          return {
            'analysis': '${parsed['skin_tone_analysis'] ?? ''}\n\n${parsed['analysis'] ?? ''}\n\n💡 ${parsed['tip'] ?? ''}',
            'suggested_shades': List<String>.from(parsed['suggested_shades'] as List? ?? []),
            'avoid_shades': List<String>.from(parsed['avoid_shades'] as List? ?? []),
          };
        }
        AppLogger.w('AiService', 'analyzeLipColor: 响应中未找到有效 JSON');
      } else {
        AppLogger.e('AiService', 'analyzeLipColor HTTP ${resp.statusCode}');
      }
    } catch (e, st) {
      AppLogger.e('AiService', 'analyzeLipColor 异常', ErrorMapper.from(e), st);
    }
    return _mockLipColorResult(profile);
  }

  Map<String, dynamic> _mockLipColorResult(UserProfile? profile) {
    String analysis;
    List<String> shades;
    final season = profile?.seasonType?.label ?? '';
    final skin = profile?.skinTone?.label ?? '';

    if (season.contains('春') || skin.contains('暖')) {
      analysis = '你是暖调肤色，珊瑚橘和番茄红超级衬你！\n\n暖色系口红能让气色更饱满，日常可以从珊瑚橘入手，约会场合换番茄红轻松驾驭。\n\n💡 哑光质地让暖橘调更高级，建议避开偏蓝的玫瑰色。';
      shades = ['珊瑚橘', '番茄红', '暖橘', '豆沙'];
    } else if (season.contains('夏') || skin.contains('冷')) {
      analysis = '你是冷调肤色，玫瑰红和豆沙粉绝了！\n\n冷调肤色驾驭玫瑰色系游刃有余，日常豆沙粉高级感满满，约会可以冲经典玫瑰红。\n\n💡 冷白皮避开偏橘调，会显脸黄。';
      shades = ['玫瑰红', '豆沙', '玫瑰粉', '裸粉'];
    } else if (season.contains('秋')) {
      analysis = '你是秋季型深暖色调，深豆沙和脏橘是你的专属色！\n\n秋季型适合有深度的暖色系，脏橘棕和深豆沙都能展现独特的成熟质感。\n\n💡 丝绒或哑光质地比珠光更显高级。';
      shades = ['深豆沙', '脏橘', '酒红', '番茄红'];
    } else {
      analysis = '你的肤色比较万能，经典正红和豆沙系都非常适合！\n\n推荐从豆沙粉日常开始，提升气色感，特别场合可以试试经典正红，绝对不会出错。\n\n💡 选口红先看质地，哑光显高级，珠光显气色。';
      shades = ['经典正红', '豆沙', '玫瑰红', '裸色'];
    }
    return {'analysis': analysis, 'suggested_shades': shades, 'avoid_shades': <String>[]};
  }

  // ─── Mock 数据 ─────────────────────────────────────────────────

  /// 根据当前季节返回对应的 Mock 穿搭卡片（避免硬编码反季单品）
  static List<Map<String, dynamic>> _getMockOutfits(String season, String seasonChar) {
    switch (season) {
      case '春季':
        return [
          {
            "title": "薄款风衣 + 白色T恤 + 直筒牛仔裤",
            "subtitle": "春日经典三件套，风衣随温差灵活穿脱，直筒牛仔裤显腿型",
            "tags": ["春季", "日常", "显高"],
            "price_range": "¥299-499",
            "buy_keyword": "薄款风衣女春季显瘦"
          },
          {
            "title": "碎花连衣裙 + 薄款开衫",
            "subtitle": "春天最有少女感的穿法，开衫早晚防凉，花裙让整体更有生机",
            "tags": ["春季", "清新", "甜美"],
            "price_range": "¥199-399",
            "buy_keyword": "碎花连衣裙春季女气质"
          },
          {
            "title": "高腰阔腿裤 + 针织短上衣",
            "subtitle": "春季拉腿型神器，高腰设计制造比例感，针织材质轻薄透气",
            "tags": ["春季", "拉腿型", "时髦"],
            "price_range": "¥258-458",
            "buy_keyword": "高腰阔腿裤女春季针织上衣"
          }
        ];
      case '夏季':
        return [
          {
            "title": "雪纺吊带裙 + 防晒薄外套",
            "subtitle": "夏天必备组合，吊带裙清凉透气，外套防晒兼顾进出空调房",
            "tags": ["夏季", "清凉", "防晒"],
            "price_range": "¥199-399",
            "buy_keyword": "雪纺吊带裙女夏清凉显瘦"
          },
          {
            "title": "纯棉短袖T恤 + 高腰短裙",
            "subtitle": "简约日常搭，短裙拉高腰线显腿长，棉质T恤吸汗透气",
            "tags": ["夏季", "日常", "显腿长"],
            "price_range": "¥128-268",
            "buy_keyword": "高腰短裙夏季显瘦T恤套装"
          },
          {
            "title": "阔腿短裤 + 冰感衬衫",
            "subtitle": "夏日通勤首选，冰感面料凉快不显汗，阔腿裤显瘦遮腿",
            "tags": ["夏季", "通勤", "冰感"],
            "price_range": "¥229-429",
            "buy_keyword": "冰感衬衫阔腿短裤夏季套装"
          }
        ];
      case '秋季':
        return [
          {
            "title": "针织毛衣 + 直筒牛仔裤 + 短靴",
            "subtitle": "秋天最百搭的组合，毛衣保暖显温柔，牛仔裤修腿型",
            "tags": ["秋季", "日常", "温柔"],
            "price_range": "¥259-459",
            "buy_keyword": "针织毛衣女秋季显瘦"
          },
          {
            "title": "皮革夹克 + 连衣裙叠穿",
            "subtitle": "酷飒风的绝佳搭法，皮夹克提升气场，裙子保留女人味",
            "tags": ["秋季", "酷飒", "混搭"],
            "price_range": "¥399-699",
            "buy_keyword": "皮革夹克女秋季叠穿连衣裙"
          },
          {
            "title": "中长款风衣 + 打底针织 + 小脚裤",
            "subtitle": "秋天最有高级感的穿法，风衣显高显气质，整体利落不臃肿",
            "tags": ["秋季", "高级感", "显高"],
            "price_range": "¥499-899",
            "buy_keyword": "中长款风衣女秋冬修身"
          }
        ];
      case '冬季':
      default:
        return [
          {
            "title": "羽绒服 + 高领毛衣打底 + 直筒裤",
            "subtitle": "冬天保暖不失型，短款羽绒服拉腿比例，高领毛衣贴合颈部保暖",
            "tags": ["冬季", "保暖", "显高"],
            "price_range": "¥499-999",
            "buy_keyword": "短款羽绒服女冬季显高"
          },
          {
            "title": "毛呢大衣 + 针织毛衣裙",
            "subtitle": "冬日高级感首选，毛呢大衣笔挺有型，毛衣裙腿部保暖",
            "tags": ["冬季", "高级", "优雅"],
            "price_range": "¥599-1299",
            "buy_keyword": "毛呢大衣女冬季气质修身"
          },
          {
            "title": "加绒卫衣 + 阔腿运动裤",
            "subtitle": "冬天休闲舒适搭，加绒保暖，阔腿显腿型不显胖",
            "tags": ["冬季", "休闲", "舒适"],
            "price_range": "¥199-399",
            "buy_keyword": "加绒卫衣套装女冬季"
          }
        ];
    }
  }

  Future<String?> _mockResponse(String userMessage, UserProfile? profile) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final intent = _detectIntent(userMessage);
    // 动态季节信息（Mock 也要知道当前是什么季节）
    final season = _getRealSeason();
    final seasonChar = _getRealSeasonChar();
    final mockOutfits = _getMockOutfits(season, seasonChar);

    switch (intent) {
      case _intentOutfit:
        return jsonEncode({
          "reply": "根据你的身材和风格，这几套$season穿搭超适合你～",
          "quick_replies": ["换个更日常的", "适合今天天气吗", "推荐下衣", "鞋子怎么搭"],
          "cards": mockOutfits,
        });

      case _intentWeather:
        return jsonEncode({
          "reply": "根据$season天气帮你搭！关键是层次感和面料选对～",
          "quick_replies": ["更保暖的版本", "防晒怎么选", "推荐外套", "颜色怎么配"],
          "cards": mockOutfits.take(2).toList(),
        });

      case _intentOccasion:
        return jsonEncode({
          "reply": "特别场合要穿得让自己最自信！给你几套方案～",
          "quick_replies": ["更正式一点", "更休闲一点", "鞋子配什么", "包包选什么"],
          "cards": [
            {
              "title": "气质连衣裙",
              "subtitle": "显女人味的经典选择，A字版型遮住小肚子，裙摆有流动感",
              "tags": ["优雅", "得体", "显身材"],
              "price_range": "¥299-599",
              "buy_keyword": "气质连衣裙收腰显瘦"
            },
            {
              "title": "高腰阔腿裤 + 丝绒衬衫",
              "subtitle": "不爱裙子的最佳方案，帅气中有女人味",
              "tags": ["帅气", "有女人味", "通勤约会两用"],
              "price_range": "¥350-550",
              "buy_keyword": "丝绒衬衫阔腿裤套装女"
            }
          ]
        });

      case _intentMood:
        final moodSeason = _getRealSeason();
        final moodSeasonChar = _getRealSeasonChar();
        final moodOutfits = _getMockOutfits(moodSeason, moodSeasonChar);
        return jsonEncode({
          "reply": "换套好看的穿搭，今天必须元气满满！",
          "quick_replies": ["要更明亮的颜色", "给我安全感的穿法", "今天约会穿什么", "换个发型搭配"],
          "cards": moodOutfits.take(2).map((o) => {
            "title": "${o['title']}（心情治愈款）",
            "subtitle": "${o['subtitle']}，换上新衣心情立刻好",
            "tags": ["$moodSeason", "治愈色", "元气"],
            "price_range": o['price_range'],
            "buy_keyword": o['buy_keyword'],
          }).toList(),
        });

      case _intentLipstick:
        return jsonEncode({
          "reply": "来帮你试色！这几个色号超适合你的肤色 💄",
          "quick_replies": ["有没有国货平替", "哑光还是水润好", "日常款推荐", "约会用哪个色"],
          "cards": [
            {
              "title": "YSL 方管 1966 正红",
              "subtitle": "蓝调正红，冷白皮绝配，让嘴唇变成全场焦点",
              "tags": ["显白", "正红", "适合冷皮"],
              "price": "¥340",
              "buy_keyword": "YSL方管1966正红色唇膏"
            },
            {
              "title": "Armani 权利红 405",
              "subtitle": "玫瑰豆沙调，日常通勤万能色，几乎不挑肤色",
              "tags": ["豆沙玫瑰", "日常百搭", "提亮肤色"],
              "price": "¥380",
              "buy_keyword": "阿玛尼405红管唇膏"
            },
            {
              "title": "花知晓小鸡蛋 M05（平价推荐）",
              "subtitle": "69元的豆沙粉棕，学生党必入，效果不输大牌",
              "tags": ["平价国货", "豆沙", "学生友好"],
              "price": "¥69",
              "buy_keyword": "花知晓口红M05豆沙色"
            }
          ]
        });

      case _intentSkin:
        return jsonEncode({
          "reply": "根据你的肤质，帮你规划一套基础护肤方案～",
          "quick_replies": ["有没有更平价的", "顺序怎么用", "防晒推荐", "油皮怎么护肤"],
          "cards": [
            {
              "title": "玉泽屏障修护精华水",
              "subtitle": "敏感肌首选，无酒精无香精，修护受损屏障效果显著",
              "tags": ["修护屏障", "敏感肌友好", "无刺激"],
              "price": "¥189",
              "buy_keyword": "玉泽屏障修护精华水"
            },
            {
              "title": "珀莱雅双抗精华 2.0",
              "subtitle": "烟酰胺+虾青素双重抗氧化，提亮暗沉效果明显",
              "tags": ["提亮肤色", "抗氧化", "性价比高"],
              "price": "¥239",
              "buy_keyword": "珀莱雅双抗精华2.0"
            }
          ]
        });

      case _intentProfile:
        // Mock 档案逻辑：编辑请求时问"你想改哪个"，否则展示档案
        final isEditRequest = _match(
          userMessage.toLowerCase(),
          ['继续补充', '编辑档案', '修改档案', '更新档案', '修改信息', '完善档案']
        );
        if (isEditRequest) {
          return jsonEncode({
            "reply": "好的，你想改哪部分？告诉我你想修改的内容，我帮你看看怎么调整 💎",
            "quick_replies": ["风格不对，想改风格", "身材信息变了", "肤质有变化", "年龄/城市", "预算范围"]
          });
        } else {
          return jsonEncode({
            "reply": "你的档案信息：风格${profile?.styleType?.label ?? '未填'}，身材${profile?.bodyShape?.label ?? '未填'}，肤质${profile?.skinTone?.label ?? '未填'}。点击底部「我的」可以编辑完整档案～",
            "quick_replies": ["修改档案", "编辑档案", "继续补充", "查看我的完整度"]
          });
        }

      default:
        final replies = [
          '嗯嗯，我听到了～你可以告诉我更多细节，我帮你更精准地分析！',
          '好的！你想从穿搭、美妆还是护肤哪个方向开始？',
          '我在这里！有什么想问的尽管说～',
          '你说的这个很有意思～能告诉我你现在的具体情况吗？',
        ];
        return replies[DateTime.now().second % replies.length];
    }
  }
}

// ─── 响应模型 ─────────────────────────────────────────────────

class AiResponse {
  final String reply;
  final List<ResultCard> cards;
  final bool isError;
  /// AI 动态生成的快捷回复（比硬编码更精准）
  final List<String> quickReplies;
  /// 从对话中提取的档案更新提示（key→enumName）
  final Map<String, String> profileHints;

  const AiResponse({
    required this.reply,
    this.cards = const [],
    this.isError = false,
    this.quickReplies = const [],
    this.profileHints = const {},
  });

  factory AiResponse.text(String reply) =>
      AiResponse(reply: reply, cards: const []);

  factory AiResponse.error(String message) =>
      AiResponse(reply: message, cards: const [], isError: true);

  bool get hasCards => cards.isNotEmpty;

  AiResponse copyWithHints(Map<String, String> hints) => AiResponse(
    reply: reply,
    cards: cards,
    isError: isError,
    quickReplies: quickReplies,
    profileHints: hints,
  );
}

