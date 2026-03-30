import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/config/app_config.dart';
import '../../core/utils/app_error.dart';
import '../../core/models/advisor_model.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/product.dart';
import '../../core/models/analysis_result.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/product_service.dart';
import '../../core/services/tts_service.dart';

class HomeController extends GetxController with GetTickerProviderStateMixin {
  // ─── 助理状态 ─────────────────────────────────────────────
  final advisorState = AdvisorState.idle.obs;
  final selectedAdvisor = AdvisorCharacter.xiaoTang.obs;

  // ─── 对话 ─────────────────────────────────────────────────
  final messages = <ChatMessage>[].obs;
  final inputText = ''.obs;
  final isThinking = false.obs;

  // ─── 结果面板 ─────────────────────────────────────────────
  final isPanelVisible = false.obs;
  final panelCards = <ResultCard>[].obs;

  // ─── 智能快捷回复 chip ────────────────────────────────────
  final quickReplies = <String>[].obs;

  // ─── 语音播报 ─────────────────────────────────────────────
  /// TTS 开关（用户可关闭）
  final ttsEnabled = true.obs;
  /// 是否正在播放 TTS
  final isSpeaking = false.obs;

  // ─── 用户档案 ─────────────────────────────────────────────
  Rx<UserProfile?> userProfile = Rx(null);

  // ─── 长按AI人物浮层菜单 ───────────────────────────────────
  final avatarMenuVisible = false.obs;

  // ─── 结果面板标题（动态化） ────────────────────────────────
  final panelTitle = '为你找到的方案 ✨'.obs;

  // ─── 对话历史（传给 AI 的上下文） ─────────────────────────
  final _historyForAi = <Map<String, String>>[];

  // ─── 消息队列（防止并发） ────────────────────────────────
  /// 当 isThinking 时暂存用户输入，处理完后自动发送
  final _messageQueue = <String>[];

  // ─── 等待用户对某字段的编辑回复 ─────────────────────────
  String? _pendingEditField;
  String? _pendingEditOriginal;

  // ══════════════════════════════════════════════════════════════
  //  生命周期
  // ══════════════════════════════════════════════════════════════

  @override
  void onInit() {
    super.onInit();
    _loadUserProfile();
    _loadAdvisor();
    _restoreChatHistory();   // 恢复上次对话历史（用于 AI 上下文）
    _sendGreeting();
  }

  @override
  void onClose() {
    // ✅ 资源清理：先停止语音录入
    if (_speechInitialized) {
      _speech.stop();
      AppLogger.d('HomeController', 'SpeechToText 已停止');
    }
    // ✅ 持久化对话历史（退出不丢失）
    StorageService.to.saveChatHistory(List.from(_historyForAi));
    AppLogger.d('HomeController', '对话历史已保存（${_historyForAi.length} 条）');
    TtsService.to.dispose();
    super.onClose();
  }

  // ══════════════════════════════════════════════════════════════
  //  初始化
  // ══════════════════════════════════════════════════════════════

  void _loadUserProfile() {
    userProfile.value = StorageService.to.loadProfile();
  }

  void _loadAdvisor() {
    final saved = StorageService.to.loadAdvisor();
    if (saved != null) {
      try {
        selectedAdvisor.value =
            AdvisorCharacter.values.firstWhere((e) => e.name == saved);
      } catch (_) {}
    }
  }

  /// 恢复上次退出时持久化的对话历史（注入 AI 上下文，让 AI 记得上次的对话）
  void _restoreChatHistory() {
    final saved = StorageService.to.loadChatHistory();
    if (saved.isNotEmpty) {
      _historyForAi.addAll(saved);
      AppLogger.i('HomeController', '对话历史已恢复（${saved.length} 条）');
    }
  }

  /// 发送助理开场白，并触发 TTS 朗读
  void _sendGreeting() {
    Future.delayed(const Duration(milliseconds: 800), () async {
      final name = userProfile.value?.nickname ?? '';
      final p = userProfile.value;
      final hour = DateTime.now().hour;
      final season = AiService.currentSeason;
      final seasonChar = AiService.currentSeasonChar;
      final timeOfDay = AiService.currentTimeOfDay;

      // ── 个性化开场白逻辑 ──────────────────────────────────
      String greeting;
      List<String> initialChips;

      // 判断是否已有档案（返回用户）
      final isReturning = p != null && p.completionRate > 0.3;
      final nameStr = name.isNotEmpty ? '$name' : '你好';

      if (isReturning) {
        // ── 老用户：按时段+季节+档案状态给定制化欢迎 ─────────
        final String timeGreeting;
        if (hour >= 6 && hour < 10) {
          timeGreeting = '早上好，$nameStr ☀️ 今天${season}的早晨，来搭一套出门的穿搭？';
        } else if (hour >= 10 && hour < 12) {
          timeGreeting = '$nameStr，上午好 ✨ $season天气，今天有什么想搭的？';
        } else if (hour >= 12 && hour < 14) {
          timeGreeting = '$nameStr，中午来了 🌸 下午出门还是安心宅着？';
        } else if (hour >= 14 && hour < 18) {
          timeGreeting = '$nameStr，下午好 🌤️ 下午出门想穿什么风格？还是聊聊护肤？';
        } else if (hour >= 18 && hour < 21) {
          timeGreeting = '$nameStr，晚上好 🌙 有约会或晚间出行吗？来搭一套？';
        } else if (hour >= 21 && hour < 24) {
          timeGreeting = '深夜了，$nameStr~ 睡前聊护肤？还是规划明天的穿搭？';
        } else {
          timeGreeting = '嗯，还没睡呢，$nameStr 🌙 规划明天穿搭，还是聊成分？';
        }
        greeting = timeGreeting;

        // 根据档案完整度调整chip
        final hasBodyShape = p.bodyShape != null;
        final hasSkinTone = p.skinTone != null;
        if (!hasBodyShape) {
          initialChips = ['今日穿搭 👗', '帮我填身材 👤', '口红推荐 💄', '护肤方案 🌿'];
        } else if (!hasSkinTone) {
          initialChips = ['今日穿搭 👗', '帮我看肤色 ✨', '口红推荐 💄', '⚙️ 偏好设置'];
        } else {
          // 档案比较完整，给功能chip
          initialChips = [
            hour < 14 ? '今天穿什么 👗' : '晚间穿搭 🌙',
            '$seasonChar季口红色号 💄',
            '护肤方案 🌿',
            '形象诊断 ✨',
          ];
        }
      } else {
        // ── 新用户/档案为空：亲切自我介绍 + 引导最核心功能 ──
        final String timeStart;
        if (hour >= 6 && hour < 12) {
          timeStart = '早上好';
        } else if (hour >= 12 && hour < 18) {
          timeStart = '下午好';
        } else {
          timeStart = '晚上好';
        }
        greeting = '$timeStart，我是 MUSE ✨ 你的 AI 私人风格顾问。\n'
            '告诉我你是什么肤色、什么身材，或者直接问穿搭、护肤、口红——'
            '我帮你找最适合的方案 💫';
        initialChips = ['今日穿搭 👗', '形象诊断 ✨', '成分检测 🔬', '⚙️ 偏好设置'];
      }

      // 用助理自己的greeting格式加上个性化内容
      final advisorGreeting = name.isNotEmpty
          ? '${selectedAdvisor.value.greeting.replaceAll('~', '')}，$name～'
          : selectedAdvisor.value.greeting;
      // 如果是老用户，用个性化greeting；否则用advisor默认欢迎语
      final finalGreeting = isReturning ? greeting : advisorGreeting;

      _addAdvisorMessage(finalGreeting);
      if (ttsEnabled.value) {
        // TTS只念短版（避免TTS太长）
        final ttsText = finalGreeting.length > 40
            ? finalGreeting.substring(0, 40)
            : finalGreeting;
        await _speakReply(ttsText);
      }

      // 推出初始chip
      await Future.delayed(const Duration(milliseconds: 400));
      quickReplies.value = initialChips;

      // ── 智能 Tips：根据档案完整度 / 时段主动推送个性化提示 ──
      await Future.delayed(const Duration(milliseconds: 1200));
      _sendSmartTip();

      // ── 今日场景卡（仅对老用户，SmartTip 后 2.5s 推出）─────
      if (isReturning) {
        await Future.delayed(const Duration(milliseconds: 2500));
        _sendSceneCard();
      }
    });
  }

  /// 根据当前时段 + 档案状态主动推送一条 tips
  void _sendSmartTip() {
    final p = userProfile.value;
    final hour = DateTime.now().hour;

    // ① 档案不完整 → 引导补充最关键缺失项
    if (p != null) {
      final completion = (p.completionRate * 100).toInt();
      if (completion < 60) {
        final missing = <String>[];
        if (p.skinTone == null) missing.add('肤色');
        if (p.bodyShape == null) missing.add('身材');
        if (p.styleType == null) missing.add('风格');
        if (p.budget == null) missing.add('预算');
        if (missing.isNotEmpty) {
          final tip = '💡 档案还差 ${missing.take(2).join('、')} 没填，补全后我的推荐会更精准哦～\n直接跟我说就好，比如"我的肤色是冷白皮"';
          _addAdvisorMessage(tip);
          if (ttsEnabled.value) _speakReply('你的档案还有几个信息没填，补全后推荐会更准，直接跟我说就好。');
          quickReplies.value = ['填写肤色', '填写风格', '填写预算', '先不填'];
          return;
        }
      }
    }

    // ② 早上 6-10 → 早安穿搭提示
    if (hour >= 6 && hour < 10) {
      final tip = '☀️ 早安！今天出门想穿什么风格？告诉我今天的天气或场合，我帮你搭配 ✨';
      _addAdvisorMessage(tip);
      if (ttsEnabled.value) _speakReply('早安！今天出门想穿什么风格？');
      quickReplies.value = ['今天通勤穿搭', '休闲出行搭配', '约会穿什么', '今日天气穿搭'];
      return;
    }

    // ③ 中午 11-13 → 午休美妆护肤
    if (hour >= 11 && hour < 14) {
      final tip = '🌸 午休时间！想聊聊护肤还是口红？我可以根据你的肤质给具体建议～';
      _addAdvisorMessage(tip);
      if (ttsEnabled.value) _speakReply('午休时间，想聊聊护肤还是口红？');
      quickReplies.value = ['推荐口红色号', '护肤品怎么选', '防晒选哪个', '成分检测'];
      return;
    }

    // ④ 下午 14-17 → 购物灵感
    if (hour >= 14 && hour < 18) {
      final tip = '🛍️ 下午好！有什么想买的吗？告诉我想要的单品，我帮你找适合你的款式～';
      _addAdvisorMessage(tip);
      if (ttsEnabled.value) _speakReply('下午好，有什么想买的吗？');
      quickReplies.value = ['找一件上衣', '推荐包包', '适合我的裙子', '${AiService.currentSeasonChar}季穿搭灵感'];
      return;
    }

    // ⑤ 晚上 18-22 → 晚间护肤 / 约会穿搭
    if (hour >= 18 && hour < 23) {
      final tip = '🌙 晚上好！约会或晚间出行有什么需要搭配的吗？或者聊聊今晚的护肤方案？';
      _addAdvisorMessage(tip);
      if (ttsEnabled.value) _speakReply('晚上好，约会或晚间出行有什么需要搭配的吗？');
      quickReplies.value = ['晚间护肤顺序', '约会穿搭', '晚宴礼服选择', '今日形象诊断'];
      return;
    }

    // ⑥ 深夜 / 其他 → 温柔陪伴语
    final tip = '✨ 随时都可以问我穿搭、护肤、成分分析的问题～我在呢！';
    _addAdvisorMessage(tip);
    if (ttsEnabled.value) _speakReply('随时都可以问我穿搭护肤的问题，我在呢。');
    quickReplies.value = ['今日穿搭 👗', '形象诊断 ✨', '成分检测 🔬', '⚙️ 偏好设置'];
  }

  /// 今日场景卡：根据时段+季节+天气/节日 生成一张精美引导卡片
  void _sendSceneCard() {
    final now = DateTime.now();
    final hour = now.hour;
    final season = AiService.currentSeason;
    final seasonChar = AiService.currentSeasonChar;
    final month = now.month;
    final day = now.day;
    final p = userProfile.value;
    final name = p?.nickname ?? '';
    final nameStr = name.isNotEmpty ? ' $name' : '';

    // 节假日检测
    String? holiday;
    if (month == 1 && day <= 3) holiday = '元旦';
    if (month == 2 && day >= 14 && day <= 16) holiday = '情人节';
    if (month == 3 && day == 8) holiday = '女神节';
    if (month == 5 && day >= 1 && day <= 3) holiday = '五一假期';
    if (month == 6 && day == 1) holiday = '六一';
    if (month == 10 && day >= 1 && day <= 7) holiday = '国庆假期';
    if (month == 12 && day == 25) holiday = '圣诞节';
    final isWeekend = now.weekday == 6 || now.weekday == 7;

    // 卡片内容生成
    String cardText;
    List<String> chips;

    if (holiday != null) {
      cardText = '🎉 **$holiday快乐$nameStr！**\n\n'
          '${holiday}穿搭是有讲究的——今天的场合、人群、心情都该被衣橱照顾到。\n'
          '让我帮你规划一套节日感十足的 $season 穿搭 ✨';
      chips = ['$holiday穿搭方案 🎉', '节日彩妆 💄', '节日礼盒推荐 🎁', '随便逛逛 ✨'];
    } else if (isWeekend) {
      if (hour >= 6 && hour < 12) {
        cardText = '☀️ **$season的周末早晨$nameStr**\n\n'
            '今天不用赶时间，可以穿一套让自己觉得"舒服又好看"的休闲穿搭。\n'
            '慵懒 or 清新？告诉我你的心情，我来搭 🌸';
        chips = ['休闲出行穿搭', '下午茶约会搭', '$seasonChar季必买单品 🛍️', '今日护肤方案'];
      } else if (hour >= 12 && hour < 18) {
        cardText = '🌤️ **$season周末下午$nameStr**\n\n'
            '逛街、咖啡、约会……今天你打算去哪里？\n'
            '把场合告诉我，我帮你搭配一套出门的造型 ✨';
        chips = ['咖啡馆穿搭', '逛街一日游搭配', '朋友聚会穿什么', '下午约会造型'];
      } else {
        cardText = '🌙 **$season周末夜晚$nameStr**\n\n'
            '夜晚出行的穿搭讲究"白天减一件、配件加一件"——\n'
            '今晚有什么安排？我帮你搭出夜场感 ✨';
        chips = ['晚间出行穿搭', '餐厅约会造型', '派对穿搭灵感', '聊聊今晚护肤'];
      }
    } else {
      // 工作日按时段
      if (hour >= 6 && hour < 9) {
        cardText = '☀️ **$season通勤早间$nameStr**\n\n'
            '早上出门时间紧，穿搭要"10分钟搞定、上下班都好看"。\n'
            '今天的天气如何？让我帮你搭一套通勤穿搭 👔';
        chips = ['今日通勤穿搭', '办公室适合穿什么', '快速出门穿搭', '今日穿搭灵感'];
      } else if (hour >= 12 && hour < 14) {
        cardText = '🌸 **$season午间$nameStr**\n\n'
            '午休时间到！聊聊护肤还是规划一下下午的造型？\n'
            '或者让我推荐几款当季爆款单品给你 ✨';
        chips = ['午间护肤小课堂', '当季爆款种草 🛍️', '下午外出穿搭', '补妆技巧'];
      } else if (hour >= 17 && hour < 21) {
        cardText = '🌙 **$season下班后$nameStr**\n\n'
            '下班了～今晚有饭局？约会？还是宅家？\n'
            '把你的安排告诉我，我帮你规划一套晚间造型 ✨';
        chips = ['下班约饭穿搭', '约会晚妆推荐', '宅家舒适穿搭', '今晚护肤顺序'];
      } else {
        return; // 其他时段不强推场景卡
      }
    }

    _addAdvisorMessage(cardText, style: BubbleStyle.sceneCard);
    quickReplies.value = chips;
  }

  /// 切换助理角色
  void switchAdvisor(AdvisorCharacter character) {
    // 切换助理时先停止当前播放
    TtsService.to.stop();
    isSpeaking.value = false;

    selectedAdvisor.value = character;
    StorageService.to.saveAdvisor(character.name);
    messages.clear();
    _historyForAi.clear();
    isPanelVisible.value = false;
    quickReplies.clear();
    _sendGreeting();
  }

  // ══════════════════════════════════════════════════════════════
  //  消息发送（含队列防并发）
  // ══════════════════════════════════════════════════════════════

  /// 用户发送文字消息
  /// ✅ Fix 5：isThinking 时入队，不丢弃，处理完自动发送
  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // ── 输入字数限制（防止超长消息撑爆 Token）──────────────────
    final maxLen = AppConfig.maxInputLength;
    final String safeText;
    if (trimmed.length > maxLen) {
      safeText = trimmed.substring(0, maxLen);
      // 告知用户已截断
      Get.snackbar(
        '输入过长',
        '消息已截取前 $maxLen 个字符发送',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } else {
      safeText = trimmed;
    }

    if (isThinking.value) {
      // 正在处理中，先入队等待
      _messageQueue.add(safeText);
      return;
    }

    messages.add(ChatMessage.user(safeText));
    inputText.value = '';
    isPanelVisible.value = false;
    // ✅ Fix 3：发送新消息时清空 chip
    quickReplies.clear();

    // ① 情绪感知优先检测（负面情绪 → 安慰模式，跳过 AI 路由）
    if (_handleMoodMessage(safeText)) return;

    // ② 先检查待编辑字段回复（如刚问了"叫什么名字"）
    if (_handlePendingEdit(safeText)) return;

    // ③ 再检查系统指令（查档案/换助理/改昵称等）
    if (_handleSystemCommand(safeText)) return;

    // ④ 走 AI 分析
    await _processUserInput(text: safeText);

    // ⑤ 处理完后，消费队列里的下一条
    _drainQueue();
  }

  // ── 情绪感知：检测负面情绪关键词，切换安慰模式 ──────────────────
  static final _moodNegative = RegExp(
    r'(好累|好烦|烦死|累死|崩溃|压力大|好丧|好难受|太难了|想哭|不开心|心情差|心情不好|好痛苦|焦虑|难受|委屈|'
    r'丧|郁闷|失眠|失恋|分手|被分|情绪崩|情绪差|心好累|emo|emo了|今天好累)',
    caseSensitive: false,
  );

  bool _handleMoodMessage(String text) {
    if (!_moodNegative.hasMatch(text)) return false;

    // 情绪安慰回复库（随机选一条）
    final replies = [
      '嗯，我感觉到了 🫂 先深呼吸一下——你已经很努力了。\n\n有时候穿一套让自己觉得"好看"的衣服，真的能悄悄撑起心情。要不要让我帮你搭一套治愈感的穿搭？',
      '听起来今天不太容易 💗 累了就停一下，不用什么都扛着。\n\n如果想用一件美美的单品让自己开心一下，告诉我你的心情，我来帮你选 ✨',
      '抱抱你 🌸 情绪来了没关系，允许自己休息一下。\n\n要不要试试"治愈系穿搭"——有时候颜色和剪裁真的能影响心情，我帮你搭？',
      '你说的我都听到了 💙 今天辛苦了。\n\n要不要聊聊让你开心的事？比如一套喜欢的穿搭、一支好看的口红——小确幸也是治愈 ✨',
    ];
    final reply = replies[DateTime.now().millisecondsSinceEpoch % replies.length];

    _addAdvisorMessage(reply, style: BubbleStyle.mood);
    if (ttsEnabled.value) {
      _speakReply('嗯，我感觉到了。先深呼吸一下，你已经很努力了。');
    }
    quickReplies.value = ['帮我搭治愈系穿搭 🌸', '推荐开心色号 💄', '聊聊护肤放松下 🌿', '我没事，继续聊 😊'];
    // 加入历史（情绪关怀也算上下文）
    _historyForAi.add({'role': 'user', 'content': text});
    _historyForAi.add({'role': 'assistant', 'content': reply});
    _drainQueue();
    return true;
  }

  /// 用户发送图片
  Future<void> sendImageMessage(String imagePath, {Uint8List? bytes}) async {
    if (isThinking.value) return;
    // 带字节流加入消息列表，气泡里可显示缩略图
    messages.add(ChatMessage.userImage(imagePath, bytes: bytes));
    await _processUserInput(imagePath: imagePath, imageBytes: bytes);
    _drainQueue();
  }

  /// 消费消息队列
  void _drainQueue() {
    if (_messageQueue.isEmpty) return;
    final next = _messageQueue.removeAt(0);
    // 用 Future.microtask 避免在当前帧内重入
    Future.microtask(() => sendTextMessage(next));
  }

  // ══════════════════════════════════════════════════════════════
  //  核心 AI 处理流程
  // ══════════════════════════════════════════════════════════════

  /// 处理用户输入 → AI分析
  Future<void> _processUserInput({
    String? text,
    String? imagePath,
    Uint8List? imageBytes,
  }) async {
    isThinking.value = true;
    advisorState.value =
        imagePath != null ? AdvisorState.scanning : AdvisorState.thinking;

    try {
      // ① 先查商品库 — 有匹配商品直接用，跳过 AI 生成卡片环节
      List<Product> matchedProducts = [];
      if (text != null) {
        matchedProducts = await ProductService.to.match(
          userMessage: text,
          profile: userProfile.value,
          limit: 3,
        );
      }

      // ② 调用 AI 生成回复文字
      final response = await AiService.to.analyze(
        userMessage: text ?? '请帮我分析这张图片',
        profile: userProfile.value,
        imagePath: imagePath,
        imageBytes: imageBytes,
        history: List.from(_historyForAi),
      );

      // 更新对话历史（用于下次 AI 上下文）
      if (text != null) {
        _historyForAi.add({'role': 'user', 'content': text});
        _historyForAi.add({'role': 'assistant', 'content': response.reply});
        // ── 历史上限裁剪（防内存/Token 溢出）──────────────────
        final maxItems = AppConfig.maxHistoryPairs * 2;
        if (_historyForAi.length > maxItems) {
          _historyForAi.removeRange(0, _historyForAi.length - maxItems);
          AppLogger.d('HomeController', '对话历史已裁剪至 $maxItems 条');
        }
      }

      isThinking.value = false;
      advisorState.value = AdvisorState.speaking;

      // 添加回复
      _addAdvisorMessage(response.reply);

      // ③ 商品库有命中 → 转成 ResultCard 优先展示（真实图片+链接）
      if (matchedProducts.isNotEmpty) {
        panelTitle.value = '为你找到的方案 ✨';
        panelCards.value = matchedProducts.map(_productToCard).toList();
        isPanelVisible.value = true;
      } else if (response.hasCards) {
        // ④ 商品库无命中 → 用 AI 返回的卡片（搜索关键词）
        panelTitle.value = '为你找到的方案 ✨';
        panelCards.value = response.cards;
        isPanelVisible.value = true;
      }

      // ✅ 优先使用 AI 动态生成的 chip，无则降级到规则生成
      if (response.quickReplies.isNotEmpty) {
        quickReplies.value = response.quickReplies;
      } else {
        quickReplies.value = _buildQuickReplies(text ?? '', response.reply);
      }

      // ✅ 对话记忆：从回复中提取用户信息并更新档案
      if (response.profileHints.isNotEmpty) {
        _applyProfileHints(response.profileHints);
      }

      // ⑤ TTS 播报 AI 回复
      if (ttsEnabled.value) {
        await _speakReply(response.reply);
      } else {
        await Future.delayed(AppConstants.animSlow);
        advisorState.value = AdvisorState.idle;
      }
    } catch (e, st) {
      AppLogger.e('HomeController', '_processUserInput 异常', e, st);
      isThinking.value = false;
      advisorState.value = AdvisorState.idle;
      final appErr = ErrorMapper.from(e);
      final errMsg = appErr.type == AppErrorType.noNetwork
          ? '😕 网络好像不通，检查一下网络后重试？'
          : appErr.type == AppErrorType.timeout
              ? '⏱️ 响应超时了，稍后再试试～'
              : '网络好像不太稳，要不要再试一次？';
      _addAdvisorMessage(errMsg);
      // ✅ Fix 4：错误提示也走 TTS
      if (ttsEnabled.value) {
        await _speakReply(errMsg);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  商品卡片转换
  // ══════════════════════════════════════════════════════════════

  /// 把商品库 Product 转成界面展示用的 ResultCard
  ResultCard _productToCard(Product p) {
    CardType type;
    switch (p.category) {
      case ProductCategory.outfit:
      case ProductCategory.accessory:
      case ProductCategory.bag:
      case ProductCategory.shoes:
        type = CardType.outfit;
      case ProductCategory.lipstick:
        type = CardType.lipstick;
      case ProductCategory.skincare:
        type = CardType.skincare;
      default:
        type = CardType.product;
    }
    return ResultCard(
      id: p.id,
      type: type,
      title: p.name,
      subtitle: p.description,
      tags: p.match.styles.take(2).toList() +
          (p.match.occasions.take(1).toList()),
      price: p.price,
      buyUrl: p.buyUrl,
      imageUrl: p.imageUrl,
    );
  }

  void _addAdvisorMessage(
    String text, {
    BubbleStyle style = BubbleStyle.normal,
  }) {
    messages.add(ChatMessage.advisor(text, style: style));
  }

  // ══════════════════════════════════════════════════════════════
  //  快捷入口 & 拍照
  // ══════════════════════════════════════════════════════════════

  /// 快捷入口触发（photo = 拍照，其余走对话）
  void triggerQuickAction(String action) {
    switch (action) {
      case 'photo':
        _showPhotoActionSheet();
        break;
      case 'outfit':
        sendTextMessage('帮我搭配今天的穿搭');
        break;
      case 'lipstick':
        sendTextMessage('推荐几个适合我的口红色号');
        break;
      case 'skin':
        sendTextMessage('帮我分析一下皮肤状态');
        break;
      case 'ingredient':
        sendTextMessage('帮我检测一个产品的成分安全性');
        break;
    }
  }

  /// 拍照按钮弹出选择：形象诊断 or 成分/产品识别
  void _showPhotoActionSheet() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '选择照片用途',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 20),
            _buildPhotoOption(
              emoji: '✨',
              title: '形象诊断',
              subtitle: '上传照片，AI分析你的肤色、脸型、色彩季型',
              color: const Color(0xFFC9956C),
              onTap: () {
                Get.back();
                startPhotoAnalysis();
              },
            ),
            const SizedBox(height: 12),
            _buildPhotoOption(
              emoji: '🔬',
              title: '成分识别',
              subtitle: '拍护肤品成分表，AI帮你分析安全性',
              color: const Color(0xFF6C8AC9),
              onTap: () {
                Get.back();
                _pickPhotoForIngredient();
              },
            ),
          ],
        ),
      ),
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildPhotoOption({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      )),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 14, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  形象诊断 & 成分识别
  // ══════════════════════════════════════════════════════════════

  /// 启动形象诊断流程
  Future<void> startPhotoAnalysis() async {
    Uint8List? imageBytes;
    String? imagePath;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      imagePath = picked.path;
      if (kIsWeb) {
        imageBytes = await picked.readAsBytes();
      }
    } catch (_) {
      const errMsg = '打开相册失败，试试直接说"形象诊断"让我帮你分析～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) await _speakReply(errMsg);
      return;
    }

    const loadingMsg = '收到照片啦～让我仔细看看你的特征，稍等片刻 🔍';
    _addAdvisorMessage(loadingMsg);
    // 分析中不读 loading 提示，避免干扰扫描动画
    advisorState.value = AdvisorState.scanning;
    isThinking.value = true;
    // 把图片气泡加入消息列表（显示缩略图）
    messages.add(ChatMessage.userImage(imagePath ?? '', bytes: imageBytes));

    try {
      final result = await AiService.to.analyzePhoto(
        imagePath: imagePath,
        imageBytes: imageBytes,
        profile: userProfile.value,
      );

      isThinking.value = false;
      advisorState.value = AdvisorState.happy;

      await StorageService.to.saveAnalysisResult(result);

      final doneMsg = '分析完啦！${result.summary}';
      _addAdvisorMessage(doneMsg);
      // ✅ Fix 4：分析完成提示也走 TTS
      if (ttsEnabled.value) await _speakReply(doneMsg);

      await Future.delayed(const Duration(milliseconds: 800));
      advisorState.value = AdvisorState.idle;
      Get.toNamed(AppRoutes.analysisReport, arguments: result);
    } catch (e) {
      isThinking.value = false;
      advisorState.value = AdvisorState.idle;
      const errMsg = '分析出了点小问题，不过我们可以直接在档案里填写信息哦～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) await _speakReply(errMsg);
    }
  }

  /// 成分识别：选图 → AI分析 → 跳转成分报告页
  Future<void> _pickPhotoForIngredient() async {
    Uint8List? imageBytes;
    String? imagePath;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      imagePath = picked.path;
      if (kIsWeb) {
        imageBytes = await picked.readAsBytes();
      }
    } catch (_) {
      const errMsg = '打开相册失败了，你可以直接输入成分名让我帮你查～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) await _speakReply(errMsg);
      return;
    }

    const loadingMsg = '收到成分表啦～马上帮你逐一分析 🔬';
    _addAdvisorMessage(loadingMsg);
    // 把图片气泡加入消息列表（显示缩略图）
    messages.add(ChatMessage.userImage(imagePath ?? '', bytes: imageBytes));
    advisorState.value = AdvisorState.thinking;
    isThinking.value = true;

    try {
      final result = await AiService.to.analyzeIngredients(
        imagePath: imagePath,
        imageBytes: imageBytes,
        profile: userProfile.value,
      );

      isThinking.value = false;
      advisorState.value = AdvisorState.speaking;

      await StorageService.to.saveIngredientResult(result);

      final emoji = result.safetyScore >= 80
          ? '✅'
          : result.safetyScore >= 60
              ? '⚠️'
              : '🚨';
      final doneMsg =
          '$emoji **${result.productName}** 安全评分 ${result.safetyScore}/100（${result.safetyLevel}）\n\n${result.summary}';
      _addAdvisorMessage(doneMsg);
      // ✅ Fix 4：成分分析结果也走 TTS
      if (ttsEnabled.value) await _speakReply(doneMsg);

      await Future.delayed(const Duration(milliseconds: 600));
      advisorState.value = AdvisorState.idle;
      Get.toNamed(AppRoutes.ingredientReport, arguments: result);
    } catch (e) {
      isThinking.value = false;
      advisorState.value = AdvisorState.idle;
      const errMsg = '成分分析遇到问题了，可以直接把成分名发给我帮你查～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) await _speakReply(errMsg);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  系统指令检测
  // ══════════════════════════════════════════════════════════════

  /// 检查用户输入是否是系统指令，如果是则处理并返回 true
  bool _handleSystemCommand(String text) {
    final t = text.trim();

    // ── 档案相关 ──────────────────────────────────────────────
    // 排除"修改/编辑档案"的情况（由 AI 处理）
    if (RegExp(r'(我的档案|查看档案|个人信息|我的信息|档案|个人资料)').hasMatch(t) &&
        !RegExp(r'(修改|编辑|更新|改)').hasMatch(t)) {
      _showProfileSummary();
      return true;
    }
    if (RegExp(r'(改名|修改昵称|换个名字|叫我|我叫)').hasMatch(t)) {
      _promptEditField('nickname', '想改成什么名字呢？', t);
      return true;
    }
    if (RegExp(r'(修改风格|换风格|改风格|风格偏好|我的风格)').hasMatch(t)) {
      _promptPickStyle();
      return true;
    }
    if (RegExp(r'(修改预算|换预算|改预算|预算调整|服装预算)').hasMatch(t)) {
      _promptPickBudget();
      return true;
    }
    if (RegExp(r'(美妆预算|护肤预算|美妆花多少|化妆品预算)').hasMatch(t)) {
      _promptPickBeautyBudget();
      return true;
    }

    // ── 身体数据字段 ──────────────────────────────────────────
    if (RegExp(r'(改身高|修改身高|我的身高|身高是|身高\d)').hasMatch(t)) {
      _promptEditField('height', '你的身高是多少 cm 呢？直接说数字就好，比如"165"', t);
      return true;
    }
    if (RegExp(r'(改体重|修改体重|我的体重|体重是|体重\d)').hasMatch(t)) {
      _promptEditField('weight', '你的体重是多少 kg 呢？直接说数字就好，比如"52"', t);
      return true;
    }
    if (RegExp(r'(改尺码|修改尺码|我的尺码|穿几号|衣服尺码|码数)').hasMatch(t)) {
      _promptPickClothingSize();
      return true;
    }
    if (RegExp(r'(改城市|修改城市|我在哪|我的城市|城市是|所在城市)').hasMatch(t)) {
      _promptEditField('city', '你在哪个城市呢？告诉我城市名，我推荐时会考虑当地天气～', t);
      return true;
    }

    // ── 外貌特征字段 ──────────────────────────────────────────
    if (RegExp(r'(改肤色|修改肤色|我的肤色|肤色是|皮肤颜色)').hasMatch(t)) {
      _promptPickSkinTone();
      return true;
    }
    if (RegExp(r'(改脸型|修改脸型|我的脸型|脸型是|什么脸型)').hasMatch(t)) {
      _promptPickFaceShape();
      return true;
    }
    if (RegExp(r'(改身材|修改身材|我的身材|身材类型|体型)').hasMatch(t)) {
      _promptPickBodyShape();
      return true;
    }
    if (RegExp(r'(改肤质|修改肤质|我的肤质|肤质是|皮肤类型)').hasMatch(t)) {
      _promptPickSkinType();
      return true;
    }

    // ── 换助理 ────────────────────────────────────────────────
    if (RegExp(r'(换个助理|换助理|小糖|林晚|小柚|初夏)').hasMatch(t)) {
      _handleSwitchAdvisor(t);
      return true;
    }

    // ── 设置入口 ──────────────────────────────────────────────
    if (RegExp(r'(设置|偏好|偏好设置|帮我设|我要设|系统设|配置|⚙)').hasMatch(t)) {
      _showSettingsMenu();
      return true;
    }

    // ── 主题 ──────────────────────────────────────────────────
    if (RegExp(r'(深色|黑暗|夜间|暗黑|dark|暗色)').hasMatch(t)) {
      _setTheme('dark');
      return true;
    }
    if (RegExp(r'(浅色|白天|亮色|light|白色模式)').hasMatch(t)) {
      _setTheme('light');
      return true;
    }
    if (RegExp(r'(跟随系统|自动主题|系统主题|system)').hasMatch(t)) {
      _setTheme('system');
      return true;
    }

    // ── 语音开关 ──────────────────────────────────────────────
    if (RegExp(r'(关闭语音|关掉语音|不要语音|静音|语音关|关语音|不读)').hasMatch(t)) {
      _setTts(false);
      return true;
    }
    if (RegExp(r'(开启语音|打开语音|语音开|要语音|开语音|朗读)').hasMatch(t)) {
      _setTts(true);
      return true;
    }

    // ── 历史记录 ──────────────────────────────────────────────
    if (RegExp(r'(查看完整历史|完整历史|所有历史|历史记录页)').hasMatch(t)) {
      final msg = '好的，跳转到完整历史记录 📋';
      _addAdvisorMessage(msg);
      if (ttsEnabled.value) _speakReply(msg);
      Future.delayed(const Duration(milliseconds: 500), () {
        Get.toNamed(AppRoutes.history);
      });
      return true;
    }
    if (RegExp(r'(诊断历史|历史记录|看历史|查历史|我的报告|历史报告)').hasMatch(t)) {
      _goToHistory();
      return true;
    }

    // ── 衣橱 ──────────────────────────────────────────────────
    if (RegExp(r'(管理.*衣橱|衣橱管理|打开衣橱|衣橱页面)').hasMatch(t)) {
      _goToWardrobeFull();
      return true;
    }
    if (RegExp(r'(我的衣橱|看衣橱|衣橱|穿搭记录)').hasMatch(t)) {
      _goToWardrobe();
      return true;
    }

    // ── 清缓存 ────────────────────────────────────────────────
    if (RegExp(r'(清缓存|清空缓存|清空记录|删除历史|清除数据)').hasMatch(t)) {
      _confirmClearCache();
      return true;
    }

    // ── 重置/重新建档 ─────────────────────────────────────────
    if (RegExp(r'(重置账号|重新建档|清空所有|重置所有|重新开始|注销)').hasMatch(t)) {
      _confirmResetAll();
      return true;
    }

    return false;
  }

  // ── 设置菜单：AI 介绍可做的事（显示当前状态） ──────────────
  void _showSettingsMenu() {
    final ttsStatus = ttsEnabled.value ? '开启 🔊' : '关闭 🔇';
    // 当前主题描述（无法直接读取 ThemeMode，从 prefs 读取或默认显示）
    final p = userProfile.value;
    final profileStatus = p != null
        ? '${p.nickname}（${(p.completionRate * 100).toInt()}% 完整）'
        : '未建档';

    final msg = '好的！以下是可以直接跟我说的操作：\n\n'
        '🌙 **外观** — 说"深色模式"或"浅色模式"\n'
        '🔊 **语音朗读**（当前：$ttsStatus）— 说"关闭语音"或"开启语音"\n'
        '💁‍♀️ **换助理** — 说"换成小糖/林晚/小柚/初夏"\n'
        '  当前：${selectedAdvisor.value.name}\n'
        '👤 **我的档案**（当前：$profileStatus）\n'
        '  — 说"查看档案"、"改名字"、"改身高"、"改肤色"\n'
        '📋 **诊断历史** — 说"看诊断历史"\n'
        '👗 **我的衣橱** — 说"打开衣橱"\n'
        '🗑️ **清空缓存** — 说"清空缓存"\n\n'
        '想调整哪个？';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('好的，你可以直接跟我说想调整什么，比如深色模式、关闭语音、换助理等等。');
    advisorState.value = AdvisorState.curious;
    quickReplies.value = ['深色模式 🌙', '换个助理 💁', '看我的档案 👤', '查诊断历史 📋'];
  }

  // ── 主题切换（公开，供浮层菜单直接调用） ────────────────────
  void setTheme(String mode) => _setTheme(mode);

  // ── 主题切换 ──────────────────────────────────────────────────
  void _setTheme(String mode) {
    final themeMode = mode == 'dark'
        ? ThemeMode.dark
        : mode == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
    Get.changeThemeMode(themeMode);

    // 持久化主题设置
    StorageService.to.getPrefs().then((prefs) {
      prefs.setString('muse_theme_mode', mode);
    });

    final label = mode == 'dark' ? '深色模式' : mode == 'light' ? '浅色模式' : '跟随系统';
    final msg = '好的，已切换为$label ✨';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply(msg);
    _setAdvisorHappy();
    quickReplies.value = ['浅色模式 ☀️', '深色模式 🌙', '跟随系统 ⚙️'];
  }

  // ── TTS 开关 ──────────────────────────────────────────────────
  void _setTts(bool enabled) {
    ttsEnabled.value = enabled;
    if (!enabled) {
      TtsService.to.stop();
      isSpeaking.value = false;
      advisorState.value = AdvisorState.idle;
    }
    final msg = enabled ? '好的，我说话你都能听到了 🔊' : '明白，我只显示文字不说话～';
    _addAdvisorMessage(msg);
    if (enabled && ttsEnabled.value) _speakReply(msg);
    _setAdvisorHappy();
  }


  // ── 历史记录：对话内嵌展示（不跳页面） ─────────────────────────
  void _goToHistory() {
    final analysisHistory = StorageService.to.loadAnalysisHistory();
    final ingredientHistory = StorageService.to.loadIngredientHistory();

    if (analysisHistory.isEmpty && ingredientHistory.isEmpty) {
      const msg = '还没有诊断记录哦，要不要先做一个形象诊断？📸\n\n拍张照片，我帮你分析肤色、脸型和色彩季型～';
      _addAdvisorMessage(msg);
      if (ttsEnabled.value) _speakReply(msg);
      quickReplies.value = ['做形象诊断 ✨', '成分检测 🔬', '先聊穿搭'];
      return;
    }

    // 生成内嵌预览卡片
    final cards = <ResultCard>[];
    for (final r in analysisHistory.take(3)) {
      cards.add(ResultCard(
        id: r.createdAt.millisecondsSinceEpoch.toString(),
        type: CardType.product,
        title: '${r.seasonTypeLabel.isNotEmpty ? r.seasonTypeLabel : '形象'}诊断报告',
        subtitle: r.summary.length > 40
            ? '${r.summary.substring(0, 40)}…'
            : r.summary,
        tags: [
          if (r.skinToneLabel.isNotEmpty) r.skinToneLabel,
          if (r.faceShapeLabel.isNotEmpty) r.faceShapeLabel,
        ],
        buyUrl: null,
        imageUrl: null,
      ));
    }
    for (final r in ingredientHistory.take(2)) {
      final emoji = r.safetyScore >= 80
          ? '✅'
          : r.safetyScore >= 60
              ? '⚠️'
              : '🚨';
      cards.add(ResultCard(
        id: r.createdAt.millisecondsSinceEpoch.toString(),
        type: CardType.skincare,
        title: '$emoji ${r.productName}',
        subtitle: '安全评分 ${r.safetyScore}/100 · ${r.safetyLevel}',
        tags: ['成分检测'],
        buyUrl: null,
        imageUrl: null,
      ));
    }

    final total = analysisHistory.length + ingredientHistory.length;
    final msg =
        '📋 你一共有 **$total** 条诊断记录（形象${analysisHistory.length}条 · 成分${ingredientHistory.length}条），最近几条如下：';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) {
      _speakReply('你一共有${total}条诊断记录，最近几条展示在下方。');
    }
    advisorState.value = AdvisorState.speaking;
    if (cards.isNotEmpty) {
      panelTitle.value = '📋 我的诊断记录（共 $total 条）';
      panelCards.value = cards;
      isPanelVisible.value = true;
    }
    quickReplies.value = ['做新的形象诊断', '检测成分安全', '查看完整历史'];
  }

  // ── 衣橱：对话内嵌引导（不跳页面，用于口头触发） ───────────────
  void _goToWardrobe() {
    final msg = '👗 告诉我今天的场合，我直接帮你搭：\n\n'
        '• **"今天上班穿什么"**\n'
        '• **"周末约会搭配"**\n'
        '• **"帮我搭一套休闲的"**\n\n'
        '想管理衣橱（添加/删除单品）就说 **"管理我的衣橱"**。';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) {
      _speakReply('你可以直接跟我说今天的场合，我帮你搭，或者说管理衣橱进行单品管理。');
    }
    advisorState.value = AdvisorState.curious;
    quickReplies.value = ['今天上班穿什么', '周末约会搭配', '帮我搭休闲风', '管理我的衣橱'];
  }

  // ── 衣橱完整管理页（需要表单操作时才跳） ──────────────────────
  void _goToWardrobeFull() {
    final msg = '好的，去衣橱管理页面 👗';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply(msg);
    Future.delayed(const Duration(milliseconds: 500), () {
      Get.toNamed(AppRoutes.wardrobe);
    });
  }



  // ── 确认清缓存 ────────────────────────────────────────────────
  void _confirmClearCache() {
    const msg = '要清空衣橱记录和诊断历史吗？**你的个人档案不会受影响**。\n\n回复"确认清空"来继续，或者直接忽略这条消息。';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('要清空衣橱记录和诊断历史吗？你的个人档案不会受影响，回复确认清空来继续。');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'clear_cache_confirm';
    quickReplies.value = ['确认清空 🗑️', '算了，不清了'];
  }

  // ── 确认重置所有 ──────────────────────────────────────────────
  void _confirmResetAll() {
    const msg = '⚠️ **重置账号**会清除你的全部数据，包括档案、衣橱和所有历史记录，**无法找回**。\n\n确定要重置吗？回复"确认重置"来继续。';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('重置账号会清除你的全部数据，无法找回，确定要重置吗？');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'reset_all_confirm';
    quickReplies.value = ['确认重置', '算了，取消'];
  }

  // 占位方法已移除，直接使用 StorageService.to.getPrefs()

  void _showProfileSummary() {
    final p = userProfile.value;
    if (p == null) {
      const msg = '还没有档案哦，跟我聊几句我就帮你建一个～';
      _addAdvisorMessage(msg);
      if (ttsEnabled.value) _speakReply(msg);
      return;
    }
    final parts = <String>[];
    parts.add('好的，这是你的档案 📋\n');
    parts.add('**昵称：** ${p.nickname}');
    if (p.ageGroup != null) parts.add('**年龄段：** ${p.ageGroup!.label}');
    if (p.height != null || p.weight != null) {
      final hw = [
        if (p.height != null) '${p.height}cm',
        if (p.weight != null) '${p.weight}kg',
      ].join(' / ');
      parts.add('**身形：** $hw');
    }
    if (p.clothingSize != null) parts.add('**衣服尺码：** ${p.clothingSize!.label}');
    if (p.skinTone != null) parts.add('**肤色：** ${p.skinTone!.label}');
    if (p.faceShape != null) parts.add('**脸型：** ${p.faceShape!.label}');
    if (p.bodyShape != null) parts.add('**身材：** ${p.bodyShape!.label}');
    if (p.styleType != null) parts.add('**风格：** ${p.styleType!.label}');
    if (p.skinType != null) parts.add('**肤质：** ${p.skinType!.label}');
    if (p.budget != null) parts.add('**服装预算：** ${p.budget!.label}');
    if (p.beautyBudget != null) parts.add('**美妆预算：** ${p.beautyBudget!.label}');
    if (p.city != null) parts.add('**城市：** ${p.city}');
    if (p.favoriteColors.isNotEmpty) {
      parts.add('**喜欢的颜色：** ${p.favoriteColors.join('、')}');
    }
    if (p.skinConcerns.isNotEmpty) {
      parts.add('**皮肤问题：** ${p.skinConcerns.join('、')}');
    }
    final completion = (p.completionRate * 100).toInt();
    parts.add('\n档案完整度 **$completion%**${completion < 80 ? '，还可以继续补充～' : ' ✨ 很完整！'}');
    final msg = parts.join('\n');
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('这是你的档案，档案完整度${completion}%。');
    advisorState.value = AdvisorState.speaking;

    // 推出针对缺失项的 chip
    final missing = <String>[];
    if (p.skinTone == null) missing.add('填肤色');
    if (p.styleType == null) missing.add('填风格');
    if (p.budget == null) missing.add('填预算');
    if (p.height == null) missing.add('填身高');
    if (p.city == null) missing.add('填城市');
    if (missing.isNotEmpty) {
      quickReplies.value = missing.take(4).toList();
    } else {
      quickReplies.value = ['改名字', '改风格', '改预算', '改肤色'];
    }
  }

  void _promptEditField(String field, String question, String originalText) {
    _addAdvisorMessage(question);
    // ✅ Fix 1（扩展）：追问句也走 TTS
    if (ttsEnabled.value) _speakReply(question);
    advisorState.value = AdvisorState.curious;
    _pendingEditField = field;
    _pendingEditOriginal = originalText;
  }

  bool _handlePendingEdit(String text) {
    if (_pendingEditField == null) return false;
    final field = _pendingEditField!;
    _pendingEditField = null;
    _pendingEditOriginal = null;

    // ── 清缓存确认 ────────────────────────────────────────────
    if (field == 'clear_cache_confirm') {
      if (text.contains('确认') || text.contains('清空') || text.contains('清除') || text.contains('好的') || text.contains('ok')) {
        _doClearCache();
      } else {
        const msg = '好的，那我们继续聊吧～';
        _addAdvisorMessage(msg);
        if (ttsEnabled.value) _speakReply(msg);
      }
      return true;
    }

    // ── 重置所有确认 ──────────────────────────────────────────
    if (field == 'reset_all_confirm') {
      if (text.contains('确认') || text.contains('重置') || text.contains('确定')) {
        _doResetAll();
      } else {
        const msg = '好的，取消了，你的数据都还在～';
        _addAdvisorMessage(msg);
        if (ttsEnabled.value) _speakReply(msg);
      }
      return true;
    }

    final p = userProfile.value;
    if (p == null) return false;

    switch (field) {
      case 'nickname':
        if (text.trim().isNotEmpty) {
          final updated = p.copyWith(nickname: text.trim());
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '好的！以后叫你"${text.trim()}"啦 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        }
        return true;

      case 'height':
        final hMatch = RegExp(r'\d{2,3}').firstMatch(text);
        if (hMatch != null) {
          final h = int.tryParse(hMatch.group(0)!);
          if (h != null && h >= 100 && h <= 230) {
            final updated = p.copyWith(height: h);
            userProfile.value = updated;
            StorageService.to.saveProfile(updated);
            final msg = '好的，身高 ${h}cm 已更新 ✨ 我搭配时会更注意比例～';
            _addAdvisorMessage(msg);
            if (ttsEnabled.value) _speakReply(msg);
            _setAdvisorHappy();
          } else {
            _addAdvisorMessage('身高数值不太对，输入 100-230 之间的数字就好～');
          }
        } else {
          _addAdvisorMessage('直接说数字就好，比如 "165"～');
        }
        return true;

      case 'weight':
        final wMatch = RegExp(r'\d{2,3}').firstMatch(text);
        if (wMatch != null) {
          final w = int.tryParse(wMatch.group(0)!);
          if (w != null && w >= 30 && w <= 200) {
            final updated = p.copyWith(weight: w);
            userProfile.value = updated;
            StorageService.to.saveProfile(updated);
            final msg = '好的，体重 ${w}kg 已更新 ✨';
            _addAdvisorMessage(msg);
            if (ttsEnabled.value) _speakReply(msg);
            _setAdvisorHappy();
          } else {
            _addAdvisorMessage('体重数值看起来不对，输入 30-200 之间的数字就好～');
          }
        } else {
          _addAdvisorMessage('直接说数字就好，比如 "52"～');
        }
        return true;

      case 'city':
        if (text.trim().isNotEmpty) {
          final updated = p.copyWith(city: text.trim());
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '好的，已更新你所在的城市为"${text.trim()}" 🏙️ 天气穿搭建议会更贴合你了～';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        }
        return true;

      case 'skin_tone':
        SkinTone? matched;
        for (final s in SkinTone.values) {
          if (text.contains(s.label) || text.contains(s.name)) {
            matched = s;
            break;
          }
        }
        // 模糊匹配
        if (matched == null) {
          if (text.contains('冷白') || text.contains('白皮')) matched = SkinTone.coolWhite;
          else if (text.contains('暖黄') || text.contains('黄皮')) matched = SkinTone.warmYellow;
          else if (text.contains('中性') || text.contains('自然')) matched = SkinTone.neutral;
          else if (text.contains('小麦') || text.contains('麦色')) matched = SkinTone.wheat;
          else if (text.contains('深色') || text.contains('偏黑')) matched = SkinTone.deep;
        }
        if (matched != null) {
          final updated = p.copyWith(skinTone: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '${matched.label}，已更新！这会让我的色彩推荐更精准 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          _promptPickSkinTone();
        }
        return true;

      case 'face_shape':
        FaceShape? matched;
        for (final s in FaceShape.values) {
          if (text.contains(s.label)) { matched = s; break; }
        }
        if (matched == null) {
          if (text.contains('鹅蛋') || text.contains('椭圆')) matched = FaceShape.oval;
          else if (text.contains('圆')) matched = FaceShape.round;
          else if (text.contains('方')) matched = FaceShape.square;
          else if (text.contains('长')) matched = FaceShape.long;
          else if (text.contains('心') || text.contains('瓜子')) matched = FaceShape.heart;
          else if (text.contains('菱') || text.contains('钻石')) matched = FaceShape.diamond;
        }
        if (matched != null) {
          final updated = p.copyWith(faceShape: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '${matched.label}，已更新！我会给你推荐最显脸小的穿搭 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          _promptPickFaceShape();
        }
        return true;

      case 'body_shape':
        BodyShape? matched;
        for (final s in BodyShape.values) {
          if (text.contains(s.label)) { matched = s; break; }
        }
        if (matched == null) {
          if (text.contains('苹果')) matched = BodyShape.apple;
          else if (text.contains('梨')) matched = BodyShape.pear;
          else if (text.contains('沙漏') || text.contains('标准')) matched = BodyShape.hourglass;
          else if (text.contains('矩形') || text.contains('直筒') || text.contains('H型')) matched = BodyShape.rectangle;
          else if (text.contains('倒三角') || text.contains('肩宽')) matched = BodyShape.invertedTriangle;
        }
        if (matched != null) {
          final updated = p.copyWith(bodyShape: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '${matched.label}体型，已更新！穿搭建议会更针对你的优点～ ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          _promptPickBodyShape();
        }
        return true;

      case 'skin_type':
        SkinType? matched;
        for (final s in SkinType.values) {
          if (text.contains(s.label)) { matched = s; break; }
        }
        if (matched == null) {
          if (text.contains('干')) matched = SkinType.dry;
          else if (text.contains('油')) matched = SkinType.oily;
          else if (text.contains('混合')) matched = SkinType.combination;
          else if (text.contains('敏感')) matched = SkinType.sensitive;
          else if (text.contains('痘') || text.contains('痤疮')) matched = SkinType.acneProne;
          else if (text.contains('中性') || text.contains('正常')) matched = SkinType.normal;
        }
        if (matched != null) {
          final updated = p.copyWith(skinType: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '${matched.label}，已更新！护肤推荐会更适合你 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          _promptPickSkinType();
        }
        return true;

      case 'clothing_size':
        ClothingSize? matched;
        for (final s in ClothingSize.values) {
          if (text.toUpperCase().contains(s.label)) { matched = s; break; }
        }
        if (matched != null) {
          final updated = p.copyWith(clothingSize: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '尺码 ${matched.label} 已更新 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          _promptPickClothingSize();
        }
        return true;

      case 'style':
        StyleType? matched;
        for (final s in StyleType.values) {
          if (text.contains(s.label)) {
            matched = s;
            break;
          }
        }
        if (matched != null) {
          final updated = p.copyWith(styleType: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '${matched.label}风格，很适合你！档案已更新 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          const msg = '没找到这个风格，可以说"甜美"、"知性"、"酷飒"、"复古"、"极简"、"街头"、"优雅"、"运动"～';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          quickReplies.value = ['甜美', '知性', '酷飒', '极简'];
        }
        return true;

      case 'budget':
        BudgetLevel? matched;
        if (text.contains('平价')) {
          matched = BudgetLevel.affordable;
        } else if (text.contains('性价比')) {
          matched = BudgetLevel.midRange;
        } else if (text.contains('轻奢')) {
          matched = BudgetLevel.premium;
        } else if (text.contains('奢侈') || text.contains('奢华')) {
          matched = BudgetLevel.luxury;
        }
        if (matched != null) {
          final updated = p.copyWith(budget: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '预算调整为"${matched.label}"，我推荐时会按这个来 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          const msg = '说"平价"、"性价比"、"轻奢"或"奢侈"就好～';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          quickReplies.value = ['平价（¥0-200）', '性价比（¥200-800）', '轻奢（¥800-3000）', '奢侈（¥3000+）'];
        }
        return true;

      case 'beauty_budget':
        BudgetLevel? matched;
        if (text.contains('平价')) {
          matched = BudgetLevel.affordable;
        } else if (text.contains('性价比')) {
          matched = BudgetLevel.midRange;
        } else if (text.contains('轻奢')) {
          matched = BudgetLevel.premium;
        } else if (text.contains('奢侈') || text.contains('奢华')) {
          matched = BudgetLevel.luxury;
        }
        if (matched != null) {
          final updated = p.copyWith(beautyBudget: matched);
          userProfile.value = updated;
          StorageService.to.saveProfile(updated);
          final msg = '美妆/护肤预算调整为"${matched.label}"，护肤推荐会按这个来 ✨';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          _setAdvisorHappy();
        } else {
          const msg = '说"平价"、"性价比"、"轻奢"或"奢侈"就好～';
          _addAdvisorMessage(msg);
          if (ttsEnabled.value) _speakReply(msg);
          quickReplies.value = ['平价护肤', '性价比护肤', '轻奢护肤', '奢侈护肤'];
        }
        return true;
    }
    return false;
  }

  void _setAdvisorHappy() {
    advisorState.value = AdvisorState.happy;
    Future.delayed(
        AppConstants.animSlow, () => advisorState.value = AdvisorState.idle);
  }

  void _promptPickStyle() {
    const msg = '想换什么风格呢？告诉我：甜美、知性、酷飒、复古、极简、街头、优雅、运动，选一个～';
    _addAdvisorMessage(msg);
    // ✅ Fix 1（扩展）：风格追问也走 TTS
    if (ttsEnabled.value) _speakReply(msg);
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'style';
  }

  void _promptPickBudget() {
    const msg = '单件衣服的预算想调整到多少呢？说"平价"、"性价比"、"轻奢"或"奢侈"就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply(msg);
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'budget';
    quickReplies.value = ['平价（¥0-200）', '性价比（¥200-800）', '轻奢（¥800-3000）', '奢侈（¥3000+）'];
  }

  void _promptPickBeautyBudget() {
    const msg = '美妆/护肤单品的预算想调整到多少呢？说"平价"、"性价比"、"轻奢"或"奢侈"就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply(msg);
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'beauty_budget';
    quickReplies.value = ['平价护肤', '性价比护肤', '轻奢护肤', '奢侈护肤'];
  }

  void _promptPickClothingSize() {
    const msg = '你平时衣服穿几号呢？说 XS/S/M/L/XL/XXL/3XL 就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply(msg);
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'clothing_size';
    quickReplies.value = ['S码', 'M码', 'L码', 'XL码'];
  }

  void _promptPickSkinTone() {
    const msg = '你的肤色是哪种呢？\n\n• **冷白皮** — 偏粉调，晒不黑\n• **暖黄皮** — 偏黄调，自然\n• **中性皮** — 不明显偏色\n• **小麦色** — 自然健康\n• **深肤色** — 偏深\n\n说出对应的名字就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('你的肤色是哪种呢？冷白皮、暖黄皮、中性皮、小麦色还是深肤色？');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'skin_tone';
    quickReplies.value = ['冷白皮 🤍', '暖黄皮 🌾', '中性皮', '小麦色 🌿'];
  }

  void _promptPickFaceShape() {
    const msg = '你是什么脸型呢？\n\n• **鹅蛋脸** — 椭圆形\n• **圆脸** — 脸颊圆润\n• **方脸** — 下颌较方\n• **长脸** — 脸型偏长\n• **心形脸** — 额宽颌尖\n• **菱形脸** — 颧骨突出\n\n说脸型名称就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('你是什么脸型呢？鹅蛋脸、圆脸、方脸、长脸、心形脸还是菱形脸？');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'face_shape';
    quickReplies.value = ['鹅蛋脸', '圆脸', '方脸', '心形脸'];
  }

  void _promptPickBodyShape() {
    const msg = '你的身材类型是哪种呢？\n\n• **苹果型** — 肩宽腰粗\n• **梨形** — 下半身丰满\n• **沙漏型** — 腰细臀丰\n• **矩形** — 比较均匀直筒\n• **倒三角** — 肩宽腿细\n\n说身材类型就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('你的身材类型是哪种？苹果型、梨形、沙漏型、矩形还是倒三角？');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'body_shape';
    quickReplies.value = ['沙漏型 ⌛', '梨形 🍐', '苹果型 🍎', '矩形'];
  }

  void _promptPickSkinType() {
    const msg = '你的肤质是哪种呢？\n\n• **干性** — 容易干燥\n• **油性** — T区出油多\n• **混合性** — T区油两颊干\n• **敏感肌** — 容易过敏泛红\n• **痘痘肌** — 容易长痘\n• **中性** — 较稳定正常\n\n说肤质类型就好～';
    _addAdvisorMessage(msg);
    if (ttsEnabled.value) _speakReply('你的肤质是哪种？干性、油性、混合性、敏感肌、痘痘肌还是中性？');
    advisorState.value = AdvisorState.curious;
    _pendingEditField = 'skin_type';
    quickReplies.value = ['干性肌', '油性肌', '混合性', '敏感肌'];
  }

  void _handleSwitchAdvisor(String text) {
    AdvisorCharacter? target;
    if (text.contains('小糖')) target = AdvisorCharacter.xiaoTang;
    else if (text.contains('林晚')) target = AdvisorCharacter.linWan;
    else if (text.contains('小柚')) target = AdvisorCharacter.xiaoYou;
    else if (text.contains('初夏')) target = AdvisorCharacter.chuXia;

    if (target != null && target != selectedAdvisor.value) {
      switchAdvisor(target);
    } else if (target == null) {
      const msg = '想换哪个助理呢？有小糖、林晚、小柚、初夏可以选～';
      _addAdvisorMessage(msg);
      if (ttsEnabled.value) _speakReply(msg);
    }
    // 若 target == selectedAdvisor.value，静默忽略（已经是这个助理了）
  }

  // ══════════════════════════════════════════════════════════════
  //  面板 & 昵称
  // ══════════════════════════════════════════════════════════════

  /// 关闭结果面板，同步清空快捷 chip
  /// ✅ Fix 3：closePanel 一并清空 chip
  void closePanel() {
    isPanelVisible.value = false;
    quickReplies.clear();
  }

  /// 打开长按人物浮层菜单
  void showAvatarMenu() {
    // 正在思考/录音时不打开菜单
    if (isThinking.value || isListening.value) return;
    avatarMenuVisible.value = true;
  }

  /// 向对话添加一条系统提示（不走 AI，不走 TTS，用于即时反馈）
  void addSystemMessage(String text) {
    _addAdvisorMessage(text);
    _setAdvisorHappy();
  }

  /// 获取用户昵称（用于UI展示）
  String get displayName => userProfile.value?.nickname ?? '你';

  // ══════════════════════════════════════════════════════════════
  //  🔊 语音播报（TTS）
  // ══════════════════════════════════════════════════════════════

  /// 切换 TTS 开关
  void toggleTts() {
    ttsEnabled.value = !ttsEnabled.value;
    if (!ttsEnabled.value) {
      TtsService.to.stop();
      isSpeaking.value = false;
      advisorState.value = AdvisorState.idle;
    }
  }

  /// 公开朗读任意文字（气泡长按用）
  Future<void> speakText(String text) async {
    if (isSpeaking.value) {
      await TtsService.to.stop();
    }
    await _speakReply(text);
  }

  /// 停止当前播放
  Future<void> stopTts() async {
    await TtsService.to.stop();
    isSpeaking.value = false;
    advisorState.value = AdvisorState.idle;
  }

  /// 播报文本（内部统一入口）
  /// 去掉 Markdown 符号，限制300字，避免请求过慢
  Future<void> _speakReply(String text) async {
    final clean = text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'\1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'\1')
        .replaceAll(RegExp(r'#+\s*'), '')
        .replaceAll(RegExp(r'\n{2,}'), '，')
        .replaceAll('\n', '，')
        .trim();

    // 超过300字截断，避免 TTS 接口超时
    final truncated = clean.length > 300 ? '${clean.substring(0, 300)}……' : clean;

    await TtsService.to.speak(
      text: truncated,
      character: selectedAdvisor.value,
      onStart: () {
        isSpeaking.value = true;
        advisorState.value = AdvisorState.speaking;
      },
      onDone: () {
        isSpeaking.value = false;
        advisorState.value = AdvisorState.idle;
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  🎙️ 语音输入（STT）
  // ══════════════════════════════════════════════════════════════

  final _speech = stt.SpeechToText();
  bool _speechInitialized = false;

  /// 语音录音状态
  final isListening = false.obs;

  Future<void> _initSpeech() async {
    if (_speechInitialized) return;
    _speechInitialized = await _speech.initialize(
      onError: (e) {
        isListening.value = false;
        advisorState.value = AdvisorState.idle;
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          isListening.value = false;
          advisorState.value = AdvisorState.idle;
        }
      },
    );
  }

  /// 开始语音输入（长按触发）
  /// ✅ Fix 2：录音开始时自动停止 TTS，防止两个声音打架
  Future<void> startVoiceInput() async {
    // 先停止 TTS，再录音
    if (isSpeaking.value) {
      await stopTts();
    }

    await _initSpeech();
    if (!_speechInitialized) {
      Get.snackbar(
        '语音不可用',
        '设备不支持语音输入',
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
      );
      return;
    }
    isListening.value = true;
    advisorState.value = AdvisorState.listening;

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          isListening.value = false;
          advisorState.value = AdvisorState.idle;
          sendTextMessage(result.recognizedWords);
        }
      },
      localeId: 'zh_CN',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  /// 停止语音输入（松手触发）
  Future<void> stopVoiceInput() async {
    await _speech.stop();
    isListening.value = false;
    advisorState.value = AdvisorState.idle;
  }

  // ══════════════════════════════════════════════════════════════
  //  智能快捷回复生成（规则备用，优先用 AI 动态生成）
  // ══════════════════════════════════════════════════════════════

  /// 备用规则生成 chip（当 AI 未返回 quick_replies 时使用）
  List<String> _buildQuickReplies(String userMsg, String aiReply) {
    final u = userMsg.toLowerCase();
    final a = aiReply.toLowerCase();
    final season = AiService.currentSeason;
    final seasonChar = AiService.currentSeasonChar;
    final timeOfDay = AiService.currentTimeOfDay;
    final p = userProfile.value;

    // ── 候选 chip 池（按意图分类） ────────────────────────────────
    List<String> candidates = [];

    // ① 设置相关
    if (u.contains('设置') || u.contains('配置') || u.contains('⚙') ||
        a.contains('设置') || a.contains('偏好')) {
      return ['深色模式 🌙', '关闭语音 🔇', '换个助理 💁', '清空缓存 🗑️'];
    }

    // ② 场合穿搭追问
    if (u.contains('约会') || u.contains('相亲') || u.contains('见家长')) {
      candidates = ['更有女人味一点', '平价版有吗', '配什么鞋', '妆容怎么搭', '换个颜色试试'];
    } else if (u.contains('面试') || u.contains('应聘')) {
      candidates = ['更保守的版本', '适合什么颜色', '鞋子怎么选', '配包推荐'];
    } else if (u.contains('婚礼') || u.contains('婚宴')) {
      candidates = ['不能穿白色对吗', '更显气质的款', '鞋子怎么搭', '配件推荐'];
    } else if (u.contains('上班') || u.contains('通勤') || u.contains('办公')) {
      candidates = ['更精干一点', '平价平替', '配什么内搭', '适合$season的通勤单品'];
    } else if (u.contains('旅行') || u.contains('出游') || u.contains('度假')) {
      candidates = ['方便走路的鞋', '适合拍照的颜色', '轻便又好看的包', '再搭一套'];
    }

    // ③ 天气穿搭
    else if (u.contains('天气') || u.contains('冷') || u.contains('热') ||
             u.contains('下雨') || u.contains('气温') || u.contains('几度')) {
      final timeChips = timeOfDay == '早晨' || timeOfDay == '上午'
          ? ['通勤怎么穿', '需要带外套吗']
          : timeOfDay == '晚上' || timeOfDay == '傍晚'
              ? ['晚间出门怎么搭', '约会穿什么']
              : ['下午出门怎么穿', '适合这天气的配色'];
      candidates = [...timeChips, '内搭推荐', '鞋子怎么选', '$seasonChar季必备单品'];
    }

    // ④ 情绪穿搭
    else if (u.contains('难过') || u.contains('不开心') || u.contains('烦') ||
             u.contains('emo') || u.contains('想改变')) {
      candidates = ['给我更活泼的颜色', '安全感穿搭', '有什么速效好看的', '护肤也帮我看看'];
    } else if (u.contains('开心') || u.contains('今天很美') || u.contains('状态好')) {
      candidates = ['再给我一套', '妆容搭配建议', '配件怎么加', '今日护肤方案'];
    }

    // ⑤ 口红/彩妆
    else if (u.contains('口红') || u.contains('唇') || u.contains('色号') ||
             a.contains('口红') || a.contains('色号') || a.contains('唇')) {
      // 根据有无肤色档案给不同追问
      final hasSkinTone = p?.skinTone != null;
      candidates = hasSkinTone
          ? ['国货平替有哪些', '哑光还是水润', '日常上班用哪个', '约会首选色号', '显白的选哪个']
          : ['先帮我判断肤色', '日常款推荐', '显白的颜色', '有没有国货'];
    }

    // ⑥ 护肤/成分
    else if (u.contains('护肤') || u.contains('皮肤') || u.contains('精华') ||
             u.contains('面霜') || u.contains('防晒') ||
             a.contains('护肤') || a.contains('成分')) {
      final hasSkinType = p?.skinType != null;
      candidates = hasSkinType
          ? ['平价平替有哪些', '使用顺序是什么', '这成分我能用吗', '再推个防晒', '抗老方案']
          : ['先判断我的肤质', '推荐平价护肤', '防晒怎么选', '成分检测'];
    }

    // ⑦ 成分检测
    else if (u.contains('成分') || u.contains('安全') || u.contains('过敏') ||
             a.contains('成分') || a.contains('安全')) {
      candidates = ['这成分敏感肌能用吗', '有没有替代产品', '怎么看成分表', '帮我再查一个'];
    }

    // ⑧ 普通穿搭（细分时段）
    else if (u.contains('穿') || u.contains('搭') || u.contains('outfit') ||
             a.contains('穿搭') || a.contains('搭配')) {
      // 时段细分
      final List<String> timeSpecific;
      if (timeOfDay == '早晨' || timeOfDay == '上午') {
        timeSpecific = ['通勤版本', '今天天气适合吗'];
      } else if (timeOfDay == '傍晚' || timeOfDay == '晚上') {
        timeSpecific = ['约会版本', '晚间出行更正式一点'];
      } else {
        timeSpecific = ['下午出门版本', '更休闲一点'];
      }
      // 档案缺失字段也提示
      final List<String> profileChips = [];
      if (p?.bodyShape == null) profileChips.add('根据我的身材推荐');
      if (p?.styleType == null) profileChips.add('帮我确定风格');

      candidates = [
        ...timeSpecific,
        '鞋子怎么搭',
        '有平价版吗',
        '再来一套',
        ...profileChips,
      ];
    }

    // ⑨ 档案相关
    else if (a.contains('档案') || a.contains('完整度') || a.contains('补充')) {
      final missing = <String>[];
      if (p?.skinTone == null) missing.add('填肤色');
      if (p?.bodyShape == null) missing.add('填身材');
      if (p?.styleType == null) missing.add('填风格');
      if (p?.city == null) missing.add('填城市');
      candidates = missing.take(3).toList() + ['去档案页编辑'];
    }

    // ⑩ 默认兜底（带时段感知）
    else {
      final timeDefault = timeOfDay == '早晨' || timeOfDay == '上午'
          ? '今天通勤穿什么 👗'
          : timeOfDay == '傍晚' || timeOfDay == '晚上'
              ? '晚间出行穿搭 🌙'
              : '$seasonChar季穿搭灵感 ✨';
      candidates = [timeDefault, '推荐口红色号 💄', '护肤方案 🌿', '⚙️ 偏好设置'];
      return candidates; // 默认直接返回，无需去重
    }

    // ── 去重 + 取前4 ────────────────────────────────────────────
    final seen = <String>{};
    final result = <String>[];
    for (final chip in candidates) {
      final key = chip.replaceAll(RegExp(r'[\s🌙🔇💁🗑️✨💄🌿⚙️👗👤📋]'), '');
      if (seen.add(key) && result.length < 4) {
        result.add(chip);
      }
    }
    // 若不足4个，补season兜底
    if (result.length < 4) {
      final fallbacks = ['$season穿搭', '再来一套', '有平价版吗', '告诉我更多'];
      for (final f in fallbacks) {
        if (result.length >= 4) break;
        if (!result.any((r) => r.contains(f.substring(0, 2)))) result.add(f);
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════
  //  清缓存 & 重置所有
  // ══════════════════════════════════════════════════════════════

  Future<void> _doClearCache() async {
    try {
      await StorageService.to.clearAnalysisHistory();
      await StorageService.to.clearIngredientHistory();
      final prefs = await StorageService.to.getPrefs();
      await prefs.remove('muse_wardrobe_items');
      const msg = '✅ 缓存已清空！衣橱记录和诊断历史都清除了，你的档案还在～';
      _addAdvisorMessage(msg);
      if (ttsEnabled.value) _speakReply(msg);
      _setAdvisorHappy();
    } catch (e) {
      const errMsg = '清空时遇到了点问题，稍后再试吧～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) _speakReply(errMsg);
    }
  }

  Future<void> _doResetAll() async {
    try {
      await StorageService.to.clearProfile();
      await StorageService.to.clearAnalysisHistory();
      await StorageService.to.clearIngredientHistory();
      final prefs = await StorageService.to.getPrefs();
      await prefs.remove('muse_wardrobe_items');
      Get.offAllNamed(AppRoutes.onboarding);
    } catch (e) {
      const errMsg = '重置遇到了问题，稍后再试～';
      _addAdvisorMessage(errMsg);
      if (ttsEnabled.value) _speakReply(errMsg);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  对话记忆：自动从用户输入提取并更新档案
  // ══════════════════════════════════════════════════════════════

  /// 将 AI 解析的档案提示应用到用户档案（静默更新，不打断对话）
  /// 把 AI 从对话中提取到的用户信息自动写入档案（静默更新，不打扰对话）
  void _applyProfileHints(Map<String, String> hints) {
    final p = userProfile.value;
    if (p == null || hints.isEmpty) return;

    // ── 枚举类型字段 ──
    SkinTone? skinTone;
    SkinType? skinType;
    BodyShape? bodyShape;
    StyleType? styleType;
    AgeGroup? ageGroup;
    ClothingSize? clothingSize;
    SeasonType? seasonType;

    if (hints.containsKey('skinTone')) {
      try {
        skinTone = SkinTone.values.firstWhere(
          (e) => e.name == hints['skinTone'],
          orElse: () => p.skinTone ?? SkinTone.neutral,
        );
      } catch (_) {}
    }
    if (hints.containsKey('skinType')) {
      try {
        skinType = SkinType.values.firstWhere(
          (e) => e.name == hints['skinType'],
          orElse: () => p.skinType ?? SkinType.normal,
        );
      } catch (_) {}
    }
    if (hints.containsKey('bodyShape')) {
      try {
        bodyShape = BodyShape.values.firstWhere(
          (e) => e.name == hints['bodyShape'],
          orElse: () => p.bodyShape ?? BodyShape.rectangle,
        );
      } catch (_) {}
    }
    if (hints.containsKey('styleType')) {
      try {
        styleType = StyleType.values.firstWhere(
          (e) => e.name == hints['styleType'],
          orElse: () => p.styleType ?? StyleType.minimal,
        );
      } catch (_) {}
    }
    if (hints.containsKey('ageGroup')) {
      try {
        ageGroup = AgeGroup.values.firstWhere(
          (e) => e.name == hints['ageGroup'],
          orElse: () => p.ageGroup ?? AgeGroup.youngAdult,
        );
      } catch (_) {}
    }
    if (hints.containsKey('clothingSize')) {
      try {
        clothingSize = ClothingSize.values.firstWhere(
          (e) => e.name.toLowerCase() == hints['clothingSize']?.toLowerCase(),
          orElse: () => p.clothingSize ?? ClothingSize.m,
        );
      } catch (_) {}
    }
    if (hints.containsKey('seasonType')) {
      try {
        seasonType = SeasonType.values.firstWhere(
          (e) => e.name == hints['seasonType'],
          orElse: () => p.seasonType ?? SeasonType.spring,
        );
      } catch (_) {}
    }

    // ── 数值类型字段 ──
    int? height;
    int? weight;
    String? city;

    if (hints.containsKey('height')) {
      height = int.tryParse(hints['height'] ?? '');
      if (height != null && (height < 130 || height > 220)) height = null;
    }
    if (hints.containsKey('weight')) {
      weight = int.tryParse(hints['weight'] ?? '');
      if (weight != null && (weight < 30 || weight > 160)) weight = null;
    }
    if (hints.containsKey('city')) {
      final c = hints['city']?.trim() ?? '';
      if (c.length >= 2) city = c;
    }

    // ── 合并只有新值才更新的字段（不覆盖已有信息）──
    final updated = p.copyWith(
      skinTone: skinTone ?? p.skinTone,
      skinType: skinType ?? p.skinType,
      bodyShape: bodyShape ?? p.bodyShape,
      styleType: styleType ?? p.styleType,
      ageGroup: ageGroup ?? p.ageGroup,
      clothingSize: clothingSize ?? p.clothingSize,
      seasonType: seasonType ?? p.seasonType,
      height: (height != null && p.height == null) ? height : p.height,
      weight: (weight != null && p.weight == null) ? weight : p.weight,
      city: (city != null && (p.city == null || p.city!.isEmpty)) ? city : p.city,
    );

    // 有任何字段有变化才写回存储
    final changed =
        updated.skinTone != p.skinTone ||
        updated.skinType != p.skinType ||
        updated.bodyShape != p.bodyShape ||
        updated.styleType != p.styleType ||
        updated.ageGroup != p.ageGroup ||
        updated.clothingSize != p.clothingSize ||
        updated.seasonType != p.seasonType ||
        updated.height != p.height ||
        updated.weight != p.weight ||
        updated.city != p.city;

    if (changed) {
      userProfile.value = updated;
      StorageService.to.saveProfile(updated);
    }
  }
}
