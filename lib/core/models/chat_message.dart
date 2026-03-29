import 'dart:typed_data';

/// 气泡样式类型（决定视觉风格）
enum BubbleStyle {
  normal,     // 普通对话气泡
  tip,        // 温馨小提示（淡蓝底+灯泡图标）
  sceneCard,  // 今日场景卡（精美渐变大卡片）
  mood,       // 情绪安慰消息（暖粉底+爱心图标）
  insight,    // 档案/数据洞察（金黄底+⚡图标）
}

/// 对话消息模型
class ChatMessage {
  final String id;
  final MessageSender sender;
  final MessageType type;
  final String? text;
  final String? imagePath;
  /// Web 端图片字节流（避免 File 路径问题）
  final Uint8List? imageBytes;
  final List<ResultCard>? cards;
  final DateTime createdAt;
  final bool isAnimating; // 是否正在打字动画
  /// 气泡视觉风格，默认 normal
  final BubbleStyle bubbleStyle;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.type,
    this.text,
    this.imagePath,
    this.imageBytes,
    this.cards,
    required this.createdAt,
    this.isAnimating = false,
    this.bubbleStyle = BubbleStyle.normal,
  });

  factory ChatMessage.advisor(
    String text, {
    bool isAnimating = true,
    BubbleStyle style = BubbleStyle.normal,
  }) =>
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sender: MessageSender.advisor,
        type: MessageType.text,
        text: text,
        createdAt: DateTime.now(),
        isAnimating: isAnimating,
        bubbleStyle: style,
      );

  factory ChatMessage.user(String text) => ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sender: MessageSender.user,
        type: MessageType.text,
        text: text,
        createdAt: DateTime.now(),
      );

  /// 用户上传图片（支持字节流，兼容 Web）
  factory ChatMessage.userImage(String imagePath, {Uint8List? bytes}) =>
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sender: MessageSender.user,
        type: MessageType.image,
        imagePath: imagePath,
        imageBytes: bytes,
        createdAt: DateTime.now(),
      );

  factory ChatMessage.cards(List<ResultCard> cards, {String? intro}) =>
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sender: MessageSender.advisor,
        type: MessageType.cards,
        text: intro,
        cards: cards,
        createdAt: DateTime.now(),
      );

  ChatMessage copyWith({bool? isAnimating}) => ChatMessage(
        id: id,
        sender: sender,
        type: type,
        text: text,
        imagePath: imagePath,
        imageBytes: imageBytes,
        cards: cards,
        createdAt: createdAt,
        isAnimating: isAnimating ?? this.isAnimating,
        bubbleStyle: bubbleStyle,
      );
}

enum MessageSender { advisor, user }

enum MessageType { text, image, cards, options }

/// 结果卡片（商品/穿搭方案/护肤建议）
class ResultCard {
  final String id;
  final CardType type;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? price;
  final String? originalPrice;
  final List<String> tags; // 推荐理由标签
  final String? buyUrl;
  final String? tryOnUrl; // 试穿/试色
  /// true = 自有商品库商品（buyUrl 是真实链接，直接跳转）
  /// false = AI 生成的搜索词（buyUrl 是搜索关键词，弹平台选择）
  final bool isOwnProduct;

  const ResultCard({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.price,
    this.originalPrice,
    this.tags = const [],
    this.buyUrl,
    this.tryOnUrl,
    this.isOwnProduct = false,
  });
}

enum CardType {
  product, // 商品
  outfit, // 穿搭方案
  skincare, // 护肤方案
  lipstick, // 口红色号
}
