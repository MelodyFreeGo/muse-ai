import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/advisor_model.dart';
import '../../core/models/chat_message.dart';
import '../../core/constants/app_constants.dart';
import 'home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(HomeController());
    final size = MediaQuery.of(context).size;
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── 背景 ────────────────────────────────────────────
          const _Background(),

          // ── AI 人物（全屏主角） ─────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 80 + bottom,
            child: _AvatarStage(controller: controller),
          ),

          // ── 对话历史气泡（上方可滑动区域） ──────────────────
          Positioned(
            top: top + 8,
            left: 0,
            right: 0,
            bottom: 80 + bottom + 10,
            child: _ChatBubbleLayer(controller: controller),
          ),

          // ── 结果面板（可拖拽，两档高度） ─────────────────────
          _DraggableResultPanel(
            controller: controller,
            inputBarHeight: 80 + bottom,
            screenHeight: size.height,
          ),

          // ── 底部极简输入栏 ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _MinimalInputBar(controller: controller),
          ),

          // ── 智能快捷回复 chip ─────────────────────────────────
          Obx(() {
            final chips = controller.quickReplies;
            if (chips.isEmpty) return const SizedBox.shrink();
            return Positioned(
              bottom: 80 + bottom + 8,
              left: 0,
              right: 0,
              child: _QuickReplyChips(
                chips: chips,
                onTap: (chip) {
                  controller.quickReplies.clear();
                  controller.sendTextMessage(chip);
                },
              ),
            );
          }),

          // ── 长按人物触发的浮层快捷菜单 ───────────────────────
          _AdvisorLongPressMenu(controller: controller),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  背景
// ══════════════════════════════════════════════════════════════
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? AppColors.darkGradient
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF5EE), Color(0xFFFAF8F5)],
              ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            left: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.roseGold.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  AI 人物舞台
// ══════════════════════════════════════════════════════════════
class _AvatarStage extends StatelessWidget {
  final HomeController controller;
  const _AvatarStage({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Obx(() {
      final character = controller.selectedAdvisor.value;
      final state = controller.advisorState.value;
      final isListening = controller.isListening.value;

      // 长按人物 → 弹出快捷浮层
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          controller.showAvatarMenu();
        },
        child: SizedBox(
          width: size.width,
          height: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 最外层大光晕（idle/thinking时低透明）
              _PulseHalo(
                color: character.primaryColor,
                size: size.width * 0.9,
                opacity: state == AdvisorState.speaking ? 0.18 : 0.09,
                duration: const Duration(seconds: 4),
              ),

              // 中层光晕（listening时激活）
              if (isListening)
                ..._buildListeningRipples(character.primaryColor, size),

              // 主光晕
              _PulseHalo(
                color: character.primaryColor,
                size: size.width * 0.62,
                opacity: 0.18,
                duration: const Duration(seconds: 3),
              ),

              // 人物主体
              _CharacterBody(
                character: character,
                state: state,
                isListening: isListening,
              ),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _buildListeningRipples(Color color, Size size) {
    return List.generate(3, (i) {
      return _PulseHalo(
        color: color,
        size: size.width * (0.5 + i * 0.18),
        opacity: 0.22 - i * 0.06,
        duration: Duration(milliseconds: 1200 + i * 400),
      );
    });
  }
}

class _PulseHalo extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  final Duration duration;
  const _PulseHalo({
    required this.color,
    required this.size,
    required this.opacity,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(opacity),
            Colors.transparent,
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(0.88, 0.88),
          end: const Offset(1.12, 1.12),
          duration: duration,
          curve: Curves.easeInOut,
        );
  }
}

class _CharacterBody extends StatelessWidget {
  final AdvisorCharacter character;
  final AdvisorState state;
  final bool isListening;
  const _CharacterBody({
    required this.character,
    required this.state,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: isListening ? 200 : 175,
      height: isListening ? 265 : 235,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isListening ? 100 : 88),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            character.primaryColor.withOpacity(0.9),
            character.secondaryColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: character.primaryColor.withOpacity(isListening ? 0.55 : 0.35),
            blurRadius: isListening ? 65 : 45,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 状态表情（动画切换）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Text(
              _stateEmoji(state),
              key: ValueKey(state),
              style: TextStyle(fontSize: isListening ? 72 : 60),
            ),
          ),
          const SizedBox(height: 10),
          // 助理名字
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: isListening ? 18 : 15,
            ),
            child: Text(character.name),
          ),
          // listening时显示声波条
          if (isListening) ...[
            const SizedBox(height: 10),
            _VoiceWaveBar(),
          ],
        ],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(
          begin: 0,
          end: -14,
          duration: const Duration(milliseconds: 2600),
          curve: Curves.easeInOut,
        );
  }

  String _stateEmoji(AdvisorState s) {
    switch (s) {
      case AdvisorState.idle:      return '😊';
      case AdvisorState.listening: return '👂';
      case AdvisorState.thinking:  return '🤔';
      case AdvisorState.speaking:  return '💬';
      case AdvisorState.happy:     return '🎉';
      case AdvisorState.curious:   return '🧐';
      case AdvisorState.scanning:  return '🔍';
    }
  }
}

// 语音波纹条
class _VoiceWaveBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final heights = [14.0, 22.0, 32.0, 22.0, 14.0];
        return Container(
          width: 4,
          height: heights[i],
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(2),
          ),
        )
            .animate(
              onPlay: (c) => c.repeat(reverse: true),
              delay: Duration(milliseconds: i * 100),
            )
            .scaleY(
              begin: 0.3,
              end: 1.0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  轻量 Markdown 渲染器（无外部依赖）
// ══════════════════════════════════════════════════════════════

/// 把常见 Markdown 符号渲染成 InlineSpan 列表
List<InlineSpan> _parseMarkdown(String text, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  // 按行处理
  final lines = text.split('\n');
  for (int li = 0; li < lines.length; li++) {
    final line = lines[li];
    if (li > 0) spans.add(const TextSpan(text: '\n'));

    // ─ 分割线 ────────────────────────────────────────────────
    if (RegExp(r'^[-─━]{3,}$').hasMatch(line.trim())) {
      spans.add(WidgetSpan(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(
            height: 1,
            color: AppColors.glassBorder,
          ),
        ),
      ));
      continue;
    }

    // ─ 有序/无序列表 ─────────────────────────────────────────
    final bulletMatch = RegExp(r'^(\s*)([-•*]|\d+\.)\s+(.+)$').firstMatch(line);
    if (bulletMatch != null) {
      final content = bulletMatch.group(3)!;
      final indent = (bulletMatch.group(1)?.length ?? 0) * 6.0;
      spans.add(WidgetSpan(
        child: Padding(
          padding: EdgeInsets.only(left: indent, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('• ', style: baseStyle.copyWith(color: AppColors.primary)),
              Flexible(child: _InlineMarkdown(text: content, baseStyle: baseStyle)),
            ],
          ),
        ),
      ));
      continue;
    }

    // ─ 普通行（含内联加粗/斜体） ──────────────────────────────
    spans.addAll(_parseInline(line, baseStyle));
  }
  return spans;
}

/// 解析行内的加粗/斜体
List<InlineSpan> _parseInline(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
  int last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    if (m.group(1) != null) {
      // **bold**
      spans.add(TextSpan(
        text: m.group(1),
        style: base.copyWith(fontWeight: FontWeight.w700),
      ));
    } else if (m.group(2) != null) {
      // *italic*
      spans.add(TextSpan(
        text: m.group(2),
        style: base.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (m.group(3) != null) {
      // `code`
      spans.add(TextSpan(
        text: m.group(3),
        style: base.copyWith(
          fontFamily: 'monospace',
          color: AppColors.primary,
          backgroundColor: AppColors.primary.withOpacity(0.08),
        ),
      ));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}

class _InlineMarkdown extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  const _InlineMarkdown({required this.text, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(children: _parseInline(text, baseStyle)),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  对话历史气泡层（可上滑查看）
// ══════════════════════════════════════════════════════════════
class _ChatBubbleLayer extends StatefulWidget {
  final HomeController controller;
  const _ChatBubbleLayer({required this.controller});

  @override
  State<_ChatBubbleLayer> createState() => _ChatBubbleLayerState();
}

class _ChatBubbleLayerState extends State<_ChatBubbleLayer> {
  final _scrollCtrl = ScrollController();
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    // 监听新消息 → 自动滚底
    ever(widget.controller.messages, (_) {
      if (!_userScrolled) _scrollToBottom();
    });
    _scrollCtrl.addListener(() {
      final atBottom = _scrollCtrl.offset >=
          _scrollCtrl.position.maxScrollExtent - 60;
      if (atBottom) _userScrolled = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) _userScrolled = true;
        return false;
      },
      child: Obx(() {
        final msgs = widget.controller.messages.toList();
        if (msgs.isEmpty) return const SizedBox.shrink();

        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: msgs.length,
          itemBuilder: (ctx, i) {
            final m = msgs[i];
            final isAdvisor = m.sender == MessageSender.advisor;

            // 思考中点点动画（最后一条且isThinking）
            final isLastAdvisor = isAdvisor &&
                i == msgs.length - 1 &&
                widget.controller.isThinking.value;

            // 图片消息气泡
            if (m.type == MessageType.image) {
              return _ImageBubble(
                message: m,
                index: i,
                character: widget.controller.selectedAdvisor.value,
              );
            }

            if (m.type == MessageType.text) {
              return _ChatBubble(
                text: m.text ?? '',
                isAdvisor: isAdvisor,
                isThinking: isLastAdvisor,
                index: i,
                character: widget.controller.selectedAdvisor.value,
                controller: widget.controller,
                bubbleStyle: m.bubbleStyle,
              );
            }
            return const SizedBox.shrink();
          },
        );
      }),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isAdvisor;
  final bool isThinking;
  final int index;
  final AdvisorCharacter character;
  final HomeController controller;
  final BubbleStyle bubbleStyle;
  const _ChatBubble({
    required this.text,
    required this.isAdvisor,
    required this.isThinking,
    required this.index,
    required this.character,
    required this.controller,
    this.bubbleStyle = BubbleStyle.normal,
  });

  // ── 样式配置表 ──────────────────────────────────────────────
  static const _styleConfig = {
    BubbleStyle.mood: (
      icon: '🫂',
      gradientColors: [Color(0xFFFFF0F5), Color(0xFFFFE4EE)],
      borderColor: Color(0xFFFFB3CC),
      label: '情绪关怀',
      labelColor: Color(0xFFE75480),
    ),
    BubbleStyle.sceneCard: (
      icon: '✨',
      gradientColors: [Color(0xFFFFF9F0), Color(0xFFFFF3E0)],
      borderColor: Color(0xFFFFCC80),
      label: '今日场景',
      labelColor: Color(0xFFE6931A),
    ),
    BubbleStyle.tip: (
      icon: '💡',
      gradientColors: [Color(0xFFF0F8FF), Color(0xFFE8F4FD)],
      borderColor: Color(0xFFB3D9F2),
      label: '小贴士',
      labelColor: Color(0xFF4A90D9),
    ),
    BubbleStyle.insight: (
      icon: '⚡',
      gradientColors: [Color(0xFFFFFBF0), Color(0xFFFFF8E1)],
      borderColor: Color(0xFFFFE082),
      label: '档案洞察',
      labelColor: Color(0xFFE6AC00),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── 特殊样式气泡 ──────────────────────────────────────────
    final config = _styleConfig[bubbleStyle];
    if (config != null && isAdvisor) {
      return _StyledBubble(
        text: text,
        index: index,
        icon: config.icon,
        gradientColors: isDark
            ? [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.04)]
            : config.gradientColors,
        borderColor: isDark
            ? config.borderColor.withOpacity(0.3)
            : config.borderColor,
        label: config.label,
        labelColor: config.labelColor,
        controller: controller,
        character: character,
      );
    }

    // ── 普通气泡 ──────────────────────────────────────────────
    final bubbleBg = isAdvisor
        ? (isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.90))
        : character.primaryColor.withOpacity(0.92);
    final textColor = isAdvisor
        ? (isDark ? Colors.white.withOpacity(0.92) : AppColors.textPrimary)
        : Colors.white;
    final baseStyle = TextStyle(fontSize: 14, height: 1.6, color: textColor);

    final bubbleContent = GestureDetector(
      onLongPress: isThinking
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _showBubbleActions(context);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isAdvisor ? 4 : 18),
            bottomRight: Radius.circular(isAdvisor ? 18 : 4),
          ),
          border: isAdvisor
              ? Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : AppColors.glassBorder,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: isAdvisor
                  ? character.primaryColor.withOpacity(0.06)
                  : character.primaryColor.withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: isThinking
            ? const _ThinkingDots()
            : (isAdvisor && _hasMarkdown(text))
                // ── AI气泡：Markdown 富文本 ───────────────
                ? RichText(
                    text: TextSpan(
                      children: _parseMarkdown(text, baseStyle),
                    ),
                  )
                // ── 普通纯文本（用户气泡 or 无格式AI回复）
                : Text(text, style: baseStyle),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8,
        left: isAdvisor ? 0 : 50,
        right: isAdvisor ? 50 : 0,
      ),
      child: Row(
        mainAxisAlignment:
            isAdvisor ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isAdvisor) ...[
            // ── 助理头像小圆（颜色跟随当前助理） ───────────────
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    character.primaryColor.withOpacity(0.85),
                    character.secondaryColor,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: character.primaryColor.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  character.name.characters.first,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          Flexible(child: bubbleContent),
        ],
      ),
    )
        .animate(key: ValueKey('msg_$index'))
        .fadeIn(
          duration: const Duration(milliseconds: 300),
          delay: const Duration(milliseconds: 40),
        )
        .slideY(
          begin: isAdvisor ? -0.06 : 0.06,
          end: 0,
          duration: const Duration(milliseconds: 300),
        );
  }

  /// 长按气泡弹出操作菜单
  void _showBubbleActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 消息预览
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(
                text.length > 80 ? '${text.substring(0, 80)}…' : text,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: _BubbleActionBtn(
                    icon: Icons.copy_rounded,
                    label: '复制文字',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(text: text));
                      // 用 GetX Snackbar 替代 ScaffoldMessenger
                      Get.snackbar(
                        '',
                        '已复制到剪贴板',
                        snackPosition: SnackPosition.BOTTOM,
                        backgroundColor: AppColors.primary.withOpacity(0.9),
                        colorText: Colors.white,
                        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        borderRadius: 12,
                        duration: const Duration(seconds: 2),
                        icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (!isAdvisor)
                  Expanded(
                    child: _BubbleActionBtn(
                      icon: Icons.replay_rounded,
                      label: '重新发送',
                      color: const Color(0xFF4EC9A0),
                      onTap: () {
                        Navigator.pop(context);
                        controller.sendTextMessage(text);
                      },
                    ),
                  ),
                if (isAdvisor)
                  Expanded(
                    child: _BubbleActionBtn(
                      icon: Icons.volume_up_rounded,
                      label: '朗读',
                      color: const Color(0xFF6C4EC9),
                      onTap: () {
                        Navigator.pop(context);
                        if (!controller.ttsEnabled.value) {
                          controller.ttsEnabled.value = true;
                        }
                        controller.speakText(text);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 检查文本是否包含 Markdown 格式符号
  bool _hasMarkdown(String t) =>
      t.contains('**') ||
      t.contains('*') ||
      t.contains('`') ||
      RegExp(r'^\s*[-•*]\s', multiLine: true).hasMatch(t) ||
      RegExp(r'^\s*\d+\.\s', multiLine: true).hasMatch(t) ||
      RegExp(r'^[-─━]{3,}$', multiLine: true).hasMatch(t);
}

// ══════════════════════════════════════════════════════════════
//  特色样式气泡（mood / sceneCard / tip / insight）
// ══════════════════════════════════════════════════════════════
class _StyledBubble extends StatelessWidget {
  final String text;
  final int index;
  final String icon;
  final List<Color> gradientColors;
  final Color borderColor;
  final String label;
  final Color labelColor;
  final HomeController controller;
  final AdvisorCharacter character;

  const _StyledBubble({
    required this.text,
    required this.index,
    required this.icon,
    required this.gradientColors,
    required this.borderColor,
    required this.label,
    required this.labelColor,
    required this.controller,
    required this.character,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white.withOpacity(0.9) : AppColors.textPrimary;
    final baseStyle = TextStyle(fontSize: 14, height: 1.65, color: textColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 助理头像
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  character.primaryColor.withOpacity(0.85),
                  character.secondaryColor,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: character.primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                character.name.characters.first,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // 特色气泡卡片
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                HapticFeedback.mediumImpact();
                Clipboard.setData(ClipboardData(text: text));
                Get.snackbar(
                  '',
                  '已复制',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: labelColor.withOpacity(0.9),
                  colorText: Colors.white,
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  borderRadius: 12,
                  duration: const Duration(seconds: 2),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: borderColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withOpacity(0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标签头部
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: borderColor.withOpacity(0.18),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(icon,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: labelColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 正文
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: RichText(
                        text: TextSpan(
                          children: _parseMarkdown(text, baseStyle),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate(key: ValueKey('styled_$index'))
        .fadeIn(duration: const Duration(milliseconds: 350))
        .slideY(begin: -0.05, end: 0, duration: const Duration(milliseconds: 350))
        .scaleXY(
          begin: 0.97,
          end: 1.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
        );
  }
}

// ══════════════════════════════════════════════════════════════
//  图片消息气泡
// ══════════════════════════════════════════════════════════════
class _ImageBubble extends StatelessWidget {
  final ChatMessage message;
  final int index;
  final AdvisorCharacter character;

  const _ImageBubble({
    required this.message,
    required this.index,
    required this.character,
  });

  @override
  Widget build(BuildContext context) {
    final isAdvisor = message.sender == MessageSender.advisor;
    Widget imageWidget;

    if (message.imageBytes != null) {
      // Web：用字节流
      imageWidget = Image.memory(
        message.imageBytes!,
        fit: BoxFit.cover,
        width: 180,
        height: 180,
      );
    } else if (message.imagePath != null && message.imagePath!.isNotEmpty) {
      // Native：用文件路径
      imageWidget = Image.network(
        message.imagePath!,
        fit: BoxFit.cover,
        width: 180,
        height: 180,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 180,
          height: 180,
          child: Center(
            child: Icon(Icons.broken_image_rounded,
                color: Colors.grey, size: 40),
          ),
        ),
      );
    } else {
      imageWidget = const SizedBox(
        width: 180,
        height: 180,
        child: Center(child: Icon(Icons.image_rounded, size: 40, color: Colors.grey)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8,
        left: isAdvisor ? 36 : 80,
        right: isAdvisor ? 80 : 0,
      ),
      child: Row(
        mainAxisAlignment:
            isAdvisor ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: character.primaryColor.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: imageWidget,
            ),
          ),
        ],
      ),
    )
        .animate(key: ValueKey('img_$index'))
        .fadeIn(duration: const Duration(milliseconds: 300))
        .scaleXY(
          begin: 0.92,
          end: 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
        );
  }
}

// 气泡长按操作按钮
class _BubbleActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _BubbleActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 思考中小点（内嵌在气泡里）
class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: AppColors.textHint,
            shape: BoxShape.circle,
          ),
        )
            .animate(
              onPlay: (c) => c.repeat(),
              delay: Duration(milliseconds: i * 160),
            )
            .scaleXY(
              begin: 0.4,
              end: 1.0,
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeInOut,
            )
            .then()
            .scaleXY(
              begin: 1.0,
              end: 0.4,
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeInOut,
            );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  智能快捷回复 chip
// ══════════════════════════════════════════════════════════════
class _QuickReplyChips extends StatelessWidget {
  final List<String> chips;
  final void Function(String) onTap;
  const _QuickReplyChips({required this.chips, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap(chips[i]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  AppColors.primary.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.8),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 11,
                  color: AppColors.primary.withOpacity(0.65),
                ),
                const SizedBox(width: 5),
                Text(
                  chips[i],
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          )
              .animate(
                delay: Duration(milliseconds: i * 55),
              )
              .fadeIn(duration: const Duration(milliseconds: 220))
              .slideX(begin: 0.12, end: 0, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  可拖拽结果面板（两档：半展/全展）
// ══════════════════════════════════════════════════════════════
class _DraggableResultPanel extends StatefulWidget {
  final HomeController controller;
  final double inputBarHeight;
  final double screenHeight;
  const _DraggableResultPanel({
    required this.controller,
    required this.inputBarHeight,
    required this.screenHeight,
  });

  @override
  State<_DraggableResultPanel> createState() => _DraggableResultPanelState();
}

class _DraggableResultPanelState extends State<_DraggableResultPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _heightAnim;

  // 两档高度（占屏幕比例）
  double get _halfH => widget.screenHeight * 0.42;
  double get _fullH => widget.screenHeight * 0.75;

  bool _isExpanded = false;
  double _dragStart = 0;
  double _currentH = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _heightAnim = Tween<double>(begin: _halfH, end: _halfH).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _currentH = _halfH;

    ever(widget.controller.isPanelVisible, (visible) {
      if (!visible) {
        _isExpanded = false;
        _currentH = _halfH;
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _snapToHeight(double target) {
    _heightAnim = Tween<double>(begin: _currentH, end: target).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward(from: 0);
    setState(() => _currentH = target);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final visible = widget.controller.isPanelVisible.value;

      return AnimatedPositioned(
        duration: visible ? Duration.zero : const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        bottom: visible ? widget.inputBarHeight : -widget.screenHeight,
        left: 0,
        right: 0,
        child: visible
            ? GestureDetector(
                onVerticalDragStart: (d) {
                  _dragStart = d.localPosition.dy;
                },
                onVerticalDragUpdate: (d) {
                  final delta = _dragStart - d.localPosition.dy;
                  final newH = (_currentH + delta).clamp(_halfH, _fullH);
                  setState(() {
                    _heightAnim =
                        AlwaysStoppedAnimation(newH);
                  });
                },
                onVerticalDragEnd: (d) {
                  final mid = (_halfH + _fullH) / 2;
                  if (_currentH > mid) {
                    _isExpanded = true;
                    _snapToHeight(_fullH);
                  } else {
                    _isExpanded = false;
                    _snapToHeight(_halfH);
                  }
                },
                child: AnimatedBuilder(
                  animation: _heightAnim,
                  builder: (ctx, _) => SizedBox(
                    height: _heightAnim.value,
                    child: _ResultPanelContent(
                      controller: widget.controller,
                      isExpanded: _isExpanded,
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    });
  }
}

class _ResultPanelContent extends StatelessWidget {
  final HomeController controller;
  final bool isExpanded;
  const _ResultPanelContent({
    required this.controller,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.97),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 36,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // 拖拽把手
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.glassBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          // 标题行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Obx(() => Text(
                    controller.panelTitle.value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    controller.isPanelVisible.value = false;
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 15, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 卡片区域
          Expanded(
            child: Obx(() => isExpanded
                ? _GridCards(cards: controller.panelCards)
                : _HorizontalCards(cards: controller.panelCards)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// 横滑卡片（半展）
class _HorizontalCards extends StatelessWidget {
  final List<ResultCard> cards;
  const _HorizontalCards({required this.cards});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, i) => _ResultCard(card: cards[i], index: i),
    );
  }
}

// 网格卡片（全展）
class _GridCards extends StatelessWidget {
  final List<ResultCard> cards;
  const _GridCards({required this.cards});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => _ResultCard(card: cards[i], index: i),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ResultCard card;
  final int index;
  const _ResultCard({required this.card, required this.index});

  // 根据卡片类型获取封面颜色和emoji
  (List<Color>, String) _cardTheme() {
    final title = card.title.toLowerCase();
    // 根据标题关键词做更精准的 emoji 匹配
    switch (card.type) {
      case CardType.outfit:
        if (title.contains('裙') || title.contains('连衣')) {
          return ([const Color(0xFFFDE8F5), const Color(0xFFEEBDD8)], '👗');
        } else if (title.contains('外套') || title.contains('开衫') ||
            title.contains('风衣') || title.contains('大衣')) {
          return ([const Color(0xFFE8EDF5), const Color(0xFFBDC7EE)], '🧥');
        } else if (title.contains('裤') || title.contains('牛仔')) {
          return ([const Color(0xFFE8F0FD), const Color(0xFFBDD0EE)], '👖');
        } else if (title.contains('T恤') || title.contains('上衣') ||
            title.contains('polo') || title.contains('衬衫')) {
          return ([const Color(0xFFE8FDF8), const Color(0xFFBDEEE5)], '👕');
        } else if (title.contains('运动') || title.contains('健身') ||
            title.contains('瑜伽')) {
          return ([const Color(0xFFEDF5E8), const Color(0xFFD0EEBD)], '🏃');
        } else if (title.contains('鞋') || title.contains('靴')) {
          return ([const Color(0xFFF5EEE8), const Color(0xFFEEDABD)], '👟');
        } else if (title.contains('包') || title.contains('手提')) {
          return ([const Color(0xFFF5E8E8), const Color(0xFFEEBDBD)], '👜');
        }
        return ([const Color(0xFFE8F4FD), const Color(0xFFBDD7EE)], '👗');
      case CardType.lipstick:
        if (title.contains('眼影') || title.contains('眼妆')) {
          return ([const Color(0xFFF0E8FD), const Color(0xFFD8BDEE)], '👁️');
        } else if (title.contains('粉底') || title.contains('气垫') ||
            title.contains('遮瑕')) {
          return ([const Color(0xFFFDF5E8), const Color(0xFFEEDBBD)], '🪞');
        } else if (title.contains('腮红') || title.contains('高光')) {
          return ([const Color(0xFFFDE8F0), const Color(0xFFEEBDCF)], '✨');
        }
        return ([const Color(0xFFFDE8EE), const Color(0xFFEEBDD0)], '💄');
      case CardType.skincare:
        if (title.contains('精华') || title.contains('安瓶')) {
          return ([const Color(0xFFEDF8E8), const Color(0xFFD0EEBD)], '💊');
        } else if (title.contains('防晒')) {
          return ([const Color(0xFFFDF8E8), const Color(0xFFEEE2BD)], '☀️');
        } else if (title.contains('面膜')) {
          return ([const Color(0xFFE8F8F8), const Color(0xFFBDE8E8)], '🫧');
        } else if (title.contains('洁面') || title.contains('卸妆')) {
          return ([const Color(0xFFE8F5FD), const Color(0xFFBDD9EE)], '🧼');
        }
        return ([const Color(0xFFE8FDF0), const Color(0xFFBDEED0)], '🧴');
      case CardType.product:
        return ([const Color(0xFFF5E8FD), const Color(0xFFD8BDEE)], '✨');
    }
  }

  /// emoji 占位封面（无图片时使用）
  Widget _buildEmojiCover(
      List<Color> gradientColors, String emoji, bool hasKeyword) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            if (hasKeyword) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      card.isOwnProduct
                          ? Icons.shopping_bag_outlined
                          : Icons.search,
                      size: 10,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      card.isOwnProduct ? '点击立即购买' : '点击选择平台',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 直接跳转自有商品链接
  void _launchUrl(BuildContext context, String url) {
    HapticFeedback.mediumImpact();
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('链接跳转失败，请稍后重试')),
        );
      }
      return false;
    });
  }

  /// 弹出多平台选择底部面板
  void _showPlatformPicker(BuildContext context, String keyword) {
    HapticFeedback.mediumImpact();
    final encoded = Uri.encodeComponent(keyword);

    // 各平台配置 { 名称, emoji, App scheme, 网页URL, 主题色 }
    final platforms = [
      (
        name: '淘宝',
        emoji: '🛒',
        appUrl: 'taobao://s.taobao.com/?q=$encoded',
        webUrl: 'https://s.taobao.com/search?q=$encoded',
        color: const Color(0xFFFF5A00),
      ),
      (
        name: '京东',
        emoji: '🏪',
        appUrl: 'jd://search?keyword=$encoded',
        webUrl: 'https://search.jd.com/Search?keyword=$encoded',
        color: const Color(0xFFE1171E),
      ),
      (
        name: '拼多多',
        emoji: '🛍️',
        appUrl: 'pinduoduo://com.xunmeng.pinduoduo/search_result.html?search_key=$encoded',
        webUrl: 'https://mobile.yangkeduo.com/search_result.html?search_key=$encoded',
        color: const Color(0xFFE02E2E),
      ),
      (
        name: '抖音商城',
        emoji: '🎵',
        appUrl: 'snssdk1128://ec/search?keyword=$encoded',
        webUrl: 'https://www.douyin.com/search/$encoded',
        color: const Color(0xFF161823),
      ),
      (
        name: '小红书',
        emoji: '📕',
        appUrl: 'xhsdiscover://search/result?keyword=$encoded',
        webUrl: 'https://www.xiaohongshu.com/search_result?keyword=$encoded',
        color: const Color(0xFFFF2441),
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 把手
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '选择购物平台',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '搜索：$keyword',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            // 平台格子
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: platforms.map((p) {
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    HapticFeedback.lightImpact();
                    bool launched = false;
                    try {
                      launched = await launchUrl(
                        Uri.parse(p.appUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}
                    if (!launched) {
                      await launchUrl(
                        Uri.parse(p.webUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: p.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: p.color.withOpacity(0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            p.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 10,
                          color: p.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (gradientColors, emoji) = _cardTheme();
    final hasKeyword = card.buyUrl != null && card.buyUrl!.isNotEmpty;

    // 自营商品：玫瑰金边框 + 轻微暖色背景
    final isOwn = card.isOwnProduct;
    const ownBorderColor = Color(0xFFC9956C);

    return GestureDetector(
      onTap: hasKeyword
          ? () {
              if (isOwn) {
                // 自有商品：直接跳转购买链接
                _launchUrl(context, card.buyUrl!);
              } else {
                // AI 搜索词：弹出平台选择
                _showPlatformPicker(context, card.buyUrl!);
              }
            }
          : null,
      child: Container(
        width: 170,
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFFFFFBF8) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOwn ? ownBorderColor.withOpacity(0.45) : AppColors.glassBorder,
            width: isOwn ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isOwn
                  ? ownBorderColor.withOpacity(0.12)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isOwn ? 18 : 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 封面图区域 ──────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: card.imageUrl != null && card.imageUrl!.isNotEmpty
                        // ── 真实商品图 ──
                        ? Image.network(
                            card.imageUrl!,
                            fit: BoxFit.cover,
                            headers: const {'crossOrigin': 'anonymous'},
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: gradientColors,
                                  ),
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: progress.expectedTotalBytes != null
                                        ? progress.cumulativeBytesLoaded /
                                            progress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    color: Colors.white54,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => _buildEmojiCover(
                              gradientColors, emoji, hasKeyword),
                          )
                        // ── 无图时 emoji 占位 ──
                        : _buildEmojiCover(gradientColors, emoji, hasKeyword),
                  ),
                ),
                // ── 左上角：自营优选角标 ──
                if (isOwn)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFC9956C), Color(0xFFE8B08A)],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.verified_rounded,
                              size: 9, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            '自营优选',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 右上角标签：购买CTA
                if (hasKeyword)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: isOwn
                            ? const LinearGradient(colors: [
                                Color(0xFFC9956C),
                                Color(0xFFE8B594),
                              ])
                            : AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: (isOwn ? ownBorderColor : AppColors.primary)
                                .withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        isOwn ? '立即购买 →' : '选择平台 →',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // ── 文字信息区 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (card.subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      card.subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 7),
                  // 标签行
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: card.tags.take(3).map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )).toList(),
                  ),
                  // 价格行
                  if (card.price != null) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Text(
                          card.price!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const Spacer(),
                        // 自有商品：显示「✓ 自营」徽章；外部搜索词：显示搜索关键词
                        if (hasKeyword)
                          isOwn
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC9956C)
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xFFC9956C)
                                            .withOpacity(0.35)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.check_circle_rounded,
                                          size: 8,
                                          color: Color(0xFFC9956C)),
                                      SizedBox(width: 2),
                                      Text(
                                        '自营',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Color(0xFFC9956C),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Flexible(
                                  child: Text(
                                    card.buyUrl!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: AppColors.textHint,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                      ],
                    ),
                  ],
                  // 无价格时：自有商品显示「立即购买」，外部显示搜索词
                  if (card.price == null && hasKeyword) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: card.isOwnProduct
                            ? const Color(0xFFFAF0E8)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: card.isOwnProduct
                                ? const Color(0xFFC9956C).withOpacity(0.3)
                                : AppColors.glassBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            card.isOwnProduct
                                ? Icons.shopping_bag_outlined
                                : Icons.search_rounded,
                            size: 11,
                            color: card.isOwnProduct
                                ? const Color(0xFFC9956C)
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              card.isOwnProduct ? '点击查看商品详情' : card.buyUrl!,
                              style: TextStyle(
                                fontSize: 10,
                                color: card.isOwnProduct
                                    ? const Color(0xFFC9956C)
                                    : AppColors.textSecondary,
                                fontStyle: card.isOwnProduct
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: index * 90))
        .fadeIn(duration: const Duration(milliseconds: 350))
        .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
  }
}

// ══════════════════════════════════════════════════════════════
//  极简底部输入栏
// ══════════════════════════════════════════════════════════════
class _MinimalInputBar extends StatefulWidget {
  final HomeController controller;
  const _MinimalInputBar({required this.controller});

  @override
  State<_MinimalInputBar> createState() => _MinimalInputBarState();
}

class _MinimalInputBarState extends State<_MinimalInputBar> {
  final _tc = TextEditingController();
  final _focus = FocusNode();
  bool _isExpanded = false;
  int _hintIndex = 0;
  List<String> _suggestions = []; // 联想词

  // ── 联想词词典 ─────────────────────────────────────────────
  static const _suggestionMap = {
    '今天': ['今天穿什么？', '今天通勤穿搭', '今天有约会'],
    '穿': ['穿什么好看', '穿搭推荐', '穿出显瘦效果', '穿出显高效果'],
    '护': ['护肤方案推荐', '护肤顺序怎么排', '护肤品成分检测'],
    '口红': ['口红色号推荐', '口红适合我吗', '口红哪个颜色显白'],
    '推荐': ['推荐穿搭', '推荐护肤品', '推荐口红', '推荐适合我的风格'],
    '显': ['显瘦穿搭', '显高穿搭', '显白口红', '显气质的搭配'],
    '成分': ['成分安全检测', '成分有哪些禁忌', '成分表怎么看'],
    '约会': ['约会穿搭推荐', '约会彩妆建议', '约会适合什么风格'],
    '上班': ['上班通勤穿搭', '上班不踩雷的搭配', '上班适合什么妆容'],
    '春': ['春季穿搭推荐', '春天流行什么单品', '春季护肤注意啥'],
    '夏': ['夏季穿搭推荐', '夏天显瘦穿搭', '夏季防晒推荐'],
    '秋': ['秋季穿搭推荐', '秋天叠穿技巧', '秋冬护肤重点'],
    '冬': ['冬季穿搭推荐', '冬天保暖又好看', '冬季护肤干燥怎么办'],
    '肤色': ['我的肤色适合什么颜色', '冷白皮穿搭', '暖黄皮口红推荐'],
    '身材': ['我的身材怎么穿', '梨形身材穿搭', 'H型身材搭配'],
  };

  void _updateSuggestions(String value) {
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final matches = <String>[];
    for (final entry in _suggestionMap.entries) {
      if (value.contains(entry.key)) {
        matches.addAll(entry.value);
      }
    }
    // 去重 + 最多显示4个
    final unique = matches.toSet().take(4).toList();
    setState(() => _suggestions = unique);
  }

  // 轮播提示词（覆盖多种意图场景）
  static const _hints = [
    '今天穿什么？',
    '适合我肤色的口红色号是？',
    '约会穿哪套最有效果？',
    '今天天气穿什么好？',
    '帮我看看这件衣服适不适合',
    '皮肤最近出油严重怎么护理？',
    '推荐几套春季穿搭',
    '有什么显瘦的裤子推荐？',
    '心情有点低落，穿什么提振精神？',
    '我是梨形身材，什么裙子好看？',
  ];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      setState(() => _isExpanded = _focus.hasFocus);
    });
    // 每3秒轮播一次hint
    _startHintRotation();
  }

  void _startHintRotation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _hintIndex = (_hintIndex + 1) % _hints.length;
      });
      _startHintRotation();
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _tc.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.controller.sendTextMessage(text);
    _tc.clear();
    widget.controller.inputText.value = '';
    _focus.unfocus();
    setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: _isExpanded ? 14 : 12,
        bottom: bottom + 12,
      ),
      decoration: BoxDecoration(
        color: _isExpanded
            ? Colors.white.withOpacity(0.96)
            : Colors.white.withOpacity(0.75),
        border: Border(
          top: BorderSide(
            color: _isExpanded
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.glassBorder.withOpacity(0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isExpanded ? 0.08 : 0.03),
            blurRadius: _isExpanded ? 30 : 15,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 联想词行（有内容时显示） ─────────────────────────
          if (_suggestions.isNotEmpty)
            _SuggestionRow(
              suggestions: _suggestions,
              onTap: (s) {
                _tc.text = s;
                _tc.selection = TextSelection.collapsed(offset: s.length);
                widget.controller.inputText.value = s;
                setState(() => _suggestions = []);
              },
            ),
          // ── 输入行 ─────────────────────────────────────────
          Row(
        children: [
          // ── 拍照按钮 ───────────────────────────────────────
          _AnimatedIconBtn(
            icon: Icons.camera_alt_outlined,
            onTap: () => widget.controller.triggerQuickAction('photo'),
            active: false,
          ),
          const SizedBox(width: 10),

          // ── 输入框 ─────────────────────────────────────────
          Expanded(
            child: Obx(() {
              final isThinking = widget.controller.isThinking.value;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: isThinking
                      ? AppColors.surfaceLight.withOpacity(0.6)
                      : (_isExpanded ? Colors.white : AppColors.surfaceLight),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isThinking
                        ? AppColors.glassBorder.withOpacity(0.5)
                        : (_isExpanded
                            ? AppColors.primary.withOpacity(0.35)
                            : AppColors.glassBorder),
                    width: _isExpanded && !isThinking ? 1.5 : 1,
                  ),
                  boxShadow: _isExpanded && !isThinking
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                  child: TextField(
                  controller: _tc,
                  focusNode: _focus,
                  enabled: !isThinking,
                  onChanged: (v) {
                    widget.controller.inputText.value = v;
                    _updateSuggestions(v);
                  },
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: isThinking
                        ? '${widget.controller.selectedAdvisor.value.name} 正在思考中…'
                        : (_isExpanded ? '说吧，我在听～' : _hints[_hintIndex]),
                    hintStyle: TextStyle(
                      color: isThinking
                          ? AppColors.textHint.withOpacity(0.5)
                          : AppColors.textHint,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                ),
              );
            }),
          ),
          const SizedBox(width: 10),

          // ── 发送 / 语音 ────────────────────────────────────
          Obx(() {
            final hasText =
                widget.controller.inputText.value.trim().isNotEmpty;
            final isListening = widget.controller.isListening.value;

            if (hasText) {
              return GestureDetector(
                onTap: _send,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.38),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 19),
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.65, 0.65),
                    end: const Offset(1.0, 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                  );
            } else {
              // 语音按钮（长按触发）
              return GestureDetector(
                onLongPressStart: (_) {
                  HapticFeedback.mediumImpact();
                  widget.controller.startVoiceInput();
                },
                onLongPressEnd: (_) {
                  widget.controller.stopVoiceInput();
                },
                onLongPressCancel: () {
                  widget.controller.stopVoiceInput();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: isListening ? AppColors.primaryGradient : null,
                    color: isListening ? null : AppColors.surfaceLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isListening
                          ? AppColors.primary
                          : AppColors.glassBorder,
                    ),
                    boxShadow: isListening
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.42),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    isListening ? Icons.mic : Icons.mic_none_rounded,
                    color: isListening ? Colors.white : AppColors.textSecondary,
                    size: 21,
                  ),
                ),
              );
            }
          }),
        ],
      ), // end Row
        ], // end Column children
      ), // end Column
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  输入联想词行
// ══════════════════════════════════════════════════════════════
class _SuggestionRow extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;
  const _SuggestionRow({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(suggestions[i]);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 12,
                    color: AppColors.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    suggestions[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
              .animate(delay: Duration(milliseconds: i * 40))
              .fadeIn(duration: const Duration(milliseconds: 180))
              .slideX(begin: 0.1, end: 0),
        ),
      ),
    );
  }
}

// 带动画的图标按钮
class _AnimatedIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _AnimatedIconBtn({
    required this.icon,
    required this.onTap,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.surfaceLight,
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? AppColors.primary.withOpacity(0.3)
                : AppColors.glassBorder,
          ),
        ),
        child: Icon(
          icon,
          color: active ? AppColors.primary : AppColors.textSecondary,
          size: 21,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  长按AI人物弹出的浮层快捷菜单（替代顶部按钮）
// ══════════════════════════════════════════════════════════════
class _AdvisorLongPressMenu extends StatelessWidget {
  final HomeController controller;
  const _AdvisorLongPressMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    // 监听 controller 的菜单可见状态
    return Obx(() {
      if (!controller.avatarMenuVisible.value) return const SizedBox.shrink();

      return Positioned.fill(
        child: GestureDetector(
          onTap: () => controller.avatarMenuVisible.value = false,
          child: Container(
            color: Colors.black.withOpacity(0.35),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 菜单标题
                  Text(
                    '长按唤起 · 快捷设置',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 菜单项行 1：助理选择
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: AdvisorCharacter.values.map((c) {
                        final isSelected =
                            controller.selectedAdvisor.value == c;
                        return GestureDetector(
                          onTap: () {
                            controller.avatarMenuVisible.value = false;
                            if (!isSelected) controller.switchAdvisor(c);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? c.primaryColor.withOpacity(0.9)
                                  : Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: isSelected
                                    ? c.primaryColor
                                    : Colors.white.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: c.primaryColor.withOpacity(0.5),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Text(
                              c.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 菜单项行 2：功能快捷操作（两行 × 4个）
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // 第一行：语音 / 深色 / 浅色 / 档案
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 语音开关（点击立即切，不关菜单）
                            Obx(() => _MenuIconBtn(
                              icon: controller.isSpeaking.value
                                  ? Icons.stop_circle_rounded
                                  : (controller.ttsEnabled.value
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_off_rounded),
                              label: controller.isSpeaking.value
                                  ? '停止'
                                  : (controller.ttsEnabled.value ? '语音开' : '语音关'),
                              active: controller.ttsEnabled.value,
                              color: AppColors.primary,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                if (controller.isSpeaking.value) {
                                  controller.stopTts();
                                  controller.avatarMenuVisible.value = false;
                                } else {
                                  // 先切换，再判断新状态来播消息
                                  final wasEnabled = controller.ttsEnabled.value;
                                  controller.toggleTts();
                                  controller.avatarMenuVisible.value = false;
                                  final msg = wasEnabled
                                      ? '明白，只显示文字不说话～'
                                      : '好的，我说话你都能听到了 🔊';
                                  controller.addSystemMessage(msg);
                                  if (!wasEnabled) controller.speakText(msg);
                                }
                              },
                            )),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.dark_mode_rounded,
                              label: '深色',
                              active: false,
                              color: const Color(0xFF6C4EC9),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                controller.avatarMenuVisible.value = false;
                                controller.setTheme('dark');
                              },
                            ),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.light_mode_rounded,
                              label: '浅色',
                              active: false,
                              color: const Color(0xFFC99C4E),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                controller.avatarMenuVisible.value = false;
                                controller.setTheme('light');
                              },
                            ),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.person_outline_rounded,
                              label: '我的档案',
                              active: false,
                              color: const Color(0xFF4EC9C9),
                              onTap: () {
                                controller.avatarMenuVisible.value = false;
                                controller.sendTextMessage('查看我的档案');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 第二行：历史 / 衣橱 / 穿搭 / 诊断
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MenuIconBtn(
                              icon: Icons.history_rounded,
                              label: '诊断历史',
                              active: false,
                              color: const Color(0xFF4EC9A0),
                              onTap: () {
                                controller.avatarMenuVisible.value = false;
                                controller.sendTextMessage('看我的诊断历史');
                              },
                            ),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.checkroom_rounded,
                              label: '我的衣橱',
                              active: false,
                              color: const Color(0xFFC96C9C),
                              onTap: () {
                                controller.avatarMenuVisible.value = false;
                                controller.sendTextMessage('我的衣橱');
                              },
                            ),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.style_rounded,
                              label: '今日穿搭',
                              active: false,
                              color: const Color(0xFFC9956C),
                              onTap: () {
                                controller.avatarMenuVisible.value = false;
                                controller.sendTextMessage('帮我搭配今天的穿搭');
                              },
                            ),
                            const SizedBox(width: 16),
                            _MenuIconBtn(
                              icon: Icons.face_retouching_natural,
                              label: '形象诊断',
                              active: false,
                              color: const Color(0xFFC96CA0),
                              onTap: () {
                                controller.avatarMenuVisible.value = false;
                                controller.startPhotoAnalysis();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  // 关闭提示
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 14, color: Colors.white.withOpacity(0.5)),
                      const SizedBox(width: 6),
                      Text(
                        '点击任意位置关闭',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn(duration: const Duration(milliseconds: 200))
                .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1.0, 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                ),
            ),
          ),
        ),
      );
    });
  }
}

class _MenuIconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _MenuIconBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active
                  ? color.withOpacity(0.85)
                  : Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? color : Colors.white.withOpacity(0.3),
                width: active ? 2 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
