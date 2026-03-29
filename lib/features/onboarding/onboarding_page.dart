import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/advisor_model.dart';
import '../../core/models/user_profile.dart';
import '../../core/constants/app_routes.dart';
import '../../core/services/storage_service.dart';

// ══════════════════════════════════════════════════════════════
//  Controller
// ══════════════════════════════════════════════════════════════
class OnboardingController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // 当前步骤
  final step = 0.obs; // 0~6
  final isCardVisible = false.obs;
  final isSaving = false.obs;

  // 收集的数据
  final selectedAdvisor = Rx<AdvisorCharacter?>(null);
  final nickname = ''.obs;
  final selectedAgeGroup = Rx<AgeGroup?>(null);
  final selectedStyle = Rx<StyleType?>(null);
  final selectedBodyShape = Rx<BodyShape?>(null);
  final selectedSkinType = Rx<SkinType?>(null);
  final selectedBudget = Rx<BudgetLevel?>(null);

  // 助理状态
  final advisorState = AdvisorState.idle.obs;

  // 小人说的话
  final advisorSaying = ''.obs;

  // 步骤配置
  static const _sayings = [
    '嗨～我是你的专属风格顾问！\n先来认识一下，选一个你喜欢的形象吧 💫',
    '太好啦！\n那我该怎么称呼你呢？',
    '你好呀！\n先告诉我你大概的年龄段？\n这样我能给你最合适的建议～',
    '了解啦～\n你平时喜欢什么穿搭风格？',
    '很有品位！\n你的身材是哪种类型？\n（帮我更好地推荐适合你的剪裁）',
    '好的好的～\n你的肤质是？\n（护肤建议会用到这个）',
    '最后一步！\n你平时单件衣服/单品的预算大概是多少？',
  ];

  @override
  void onReady() {
    super.onReady();
    _showStep(0);
  }

  void _showStep(int s) {
    step.value = s;
    advisorSaying.value = _sayings[s];
    advisorState.value = AdvisorState.speaking;

    // 延迟一点再弹卡片，让说话动画先起来
    Future.delayed(const Duration(milliseconds: 600), () {
      isCardVisible.value = true;
      advisorState.value = AdvisorState.curious;
    });
  }

  void nextStep() {
    isCardVisible.value = false;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (step.value < 6) {
        _showStep(step.value + 1);
      } else {
        _finish();
      }
    });
  }

  bool get canProceed {
    switch (step.value) {
      case 0: return selectedAdvisor.value != null;
      case 1: return nickname.value.trim().isNotEmpty;
      case 2: return selectedAgeGroup.value != null;
      case 3: return selectedStyle.value != null;
      case 4: return selectedBodyShape.value != null;
      case 5: return selectedSkinType.value != null;
      case 6: return selectedBudget.value != null;
      default: return false;
    }
  }

  Future<void> _finish() async {
    if (isSaving.value) return;
    isSaving.value = true;
    advisorState.value = AdvisorState.happy;
    advisorSaying.value = '档案建好啦！✨\n让我们开始吧～';

    final now = DateTime.now();
    final profile = UserProfile(
      id: now.millisecondsSinceEpoch.toString(),
      nickname: nickname.value.trim(),
      ageGroup: selectedAgeGroup.value,
      styleType: selectedStyle.value,
      bodyShape: selectedBodyShape.value,
      skinType: selectedSkinType.value,
      budget: selectedBudget.value,
      createdAt: now,
      updatedAt: now,
      isOnboardingComplete: true,
    );

    await StorageService.to.saveProfile(profile);
    await StorageService.to.saveAdvisor(
        selectedAdvisor.value?.name ?? AdvisorCharacter.xiaoTang.name);
    await StorageService.to.setOnboardingDone();

    await Future.delayed(const Duration(milliseconds: 1200));
    isSaving.value = false;
    Get.offAllNamed(AppRoutes.home);
  }
}

// ══════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnboardingController());
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── 背景 ─────────────────────────────────────────────
          const _OnboardingBackground(),

          // ── AI人物（全屏主体） ──────────────────────────────
          Positioned.fill(
            child: _AvatarStage(controller: controller),
          ),

          // ── 顶部步骤指示点 ──────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: _StepDots(controller: controller),
          ),

          // ── 助理说话气泡 ────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 20,
            right: 20,
            child: _AdvisorSpeechBubble(controller: controller),
          ),

          // ── 科幻选择卡片（底部弹出） ─────────────────────────
          Obx(() => AnimatedPositioned(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                bottom: controller.isCardVisible.value
                    ? MediaQuery.of(context).padding.bottom
                    : -size.height * 0.6,
                left: 0,
                right: 0,
                child: _ChoiceCard(controller: controller, size: size),
              )),
        ],
      ),
    );
  }
}

// ── 背景 ────────────────────────────────────────────────────
class _OnboardingBackground extends StatelessWidget {
  const _OnboardingBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0E8), Color(0xFFFAF8F5), Color(0xFFEEF0FF)],
          stops: [0, 0.5, 1],
        ),
      ),
      child: Stack(
        children: [
          // 装饰光晕1
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // 装饰光晕2
          Positioned(
            bottom: 100,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.roseGold.withOpacity(0.2),
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

// ── 步骤指示点 ────────────────────────────────────────────
class _StepDots extends StatelessWidget {
  final OnboardingController controller;
  const _StepDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(7, (i) {
            final active = i == controller.step.value;
            final done = i < controller.step.value;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: done
                    ? AppColors.primary.withOpacity(0.5)
                    : active
                        ? AppColors.primary
                        : AppColors.glassBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ));
  }
}

// ── 助理气泡 ──────────────────────────────────────────────
class _AdvisorSpeechBubble extends StatelessWidget {
  final OnboardingController controller;
  const _AdvisorSpeechBubble({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final text = controller.advisorSaying.value;
      if (text.isEmpty) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.6,
            fontWeight: FontWeight.w500,
          ),
        ),
      )
          .animate(key: ValueKey(text))
          .fadeIn(duration: 400.ms)
          .slideY(begin: -0.1, end: 0);
    });
  }
}

// ── AI 人物舞台 ───────────────────────────────────────────
class _AvatarStage extends StatelessWidget {
  final OnboardingController controller;
  const _AvatarStage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final character = controller.selectedAdvisor.value;
      final state = controller.advisorState.value;

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 120), // 留出气泡空间
            // 光晕
            Stack(
              alignment: Alignment.center,
              children: [
                // 外光晕
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primaryLight.withOpacity(0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      end: const Offset(1.1, 1.1),
                      duration: const Duration(seconds: 3),
                      curve: Curves.easeInOut,
                    ),
                // 人物容器
                Container(
                  width: 160,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(80),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: character != null
                          ? [
                              character.primaryColor.withOpacity(0.9),
                              character.secondaryColor,
                            ]
                          : [
                              AppColors.primary.withOpacity(0.7),
                              AppColors.roseGold,
                            ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (character?.primaryColor ?? AppColors.primary)
                            .withOpacity(0.35),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _stateEmoji(state),
                        style: const TextStyle(fontSize: 60),
                      ),
                      if (character != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          character.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(
                      begin: 0,
                      end: -10,
                      duration: const Duration(milliseconds: 2500),
                      curve: Curves.easeInOut,
                    ),
              ],
            ),
          ],
        ),
      );
    });
  }

  String _stateEmoji(AdvisorState s) {
    switch (s) {
      case AdvisorState.idle: return '😊';
      case AdvisorState.speaking: return '💬';
      case AdvisorState.curious: return '🧐';
      case AdvisorState.happy: return '🎉';
      case AdvisorState.listening: return '👂';
      case AdvisorState.thinking: return '🤔';
      case AdvisorState.scanning: return '🔍';
    }
  }
}

// ══════════════════════════════════════════════════════════════
//  科幻选择卡片（核心）
// ══════════════════════════════════════════════════════════════
class _ChoiceCard extends StatelessWidget {
  final OnboardingController controller;
  final Size size;
  const _ChoiceCard({required this.controller, required this.size});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.12),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, -8),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖拽条
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // 步骤内容
              _buildStepContent(controller.step.value),
              const SizedBox(height: 20),
            ],
          ),
        ));
  }

  Widget _buildStepContent(int s) {
    switch (s) {
      case 0: return _ChooseAdvisor(controller: controller);
      case 1: return _InputNickname(controller: controller);
      case 2: return _ChooseAgeGroup(controller: controller);
      case 3: return _ChooseStyle(controller: controller);
      case 4: return _ChooseBodyShape(controller: controller);
      case 5: return _ChooseSkinType(controller: controller);
      case 6: return _ChooseBudget(controller: controller);
      default: return const SizedBox.shrink();
    }
  }
}

// ── 共用：确认按钮 ────────────────────────────────────────
class _ConfirmBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ConfirmBtn({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: 200.ms,
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: enabled ? AppColors.primaryGradient : null,
            color: enabled ? null : AppColors.glassBorder,
            borderRadius: BorderRadius.circular(50),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: enabled ? Colors.white : AppColors.textHint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 0：选助理 ────────────────────────────────────────
class _ChooseAdvisor extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseAdvisor({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
          children: [
            SizedBox(
              height: 130,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: AdvisorCharacter.values.map((c) {
                  final sel = controller.selectedAdvisor.value == c;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectedAdvisor.value = c;
                    },
                    child: AnimatedContainer(
                      duration: 200.ms,
                      width: 90,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? LinearGradient(
                                colors: [c.primaryColor.withOpacity(0.8), c.secondaryColor],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: sel ? null : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? c.primaryColor : AppColors.glassBorder,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: c.primaryColor.withOpacity(0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('😊', style: const TextStyle(fontSize: 30)),
                          const SizedBox(height: 6),
                          Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              c.personality,
                              style: TextStyle(
                                fontSize: 9,
                                color: sel
                                    ? Colors.white.withOpacity(0.8)
                                    : AppColors.textHint,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate(delay: (AdvisorCharacter.values.indexOf(c) * 60).ms)
                      .fadeIn()
                      .slideX(begin: 0.2, end: 0);
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _ConfirmBtn(
              label: '就是她了 ✨',
              enabled: controller.selectedAdvisor.value != null,
              onTap: controller.nextStep,
            ),
          ],
        ));
  }
}

// ── Step 1：输入昵称 ──────────────────────────────────────
class _InputNickname extends StatefulWidget {
  final OnboardingController controller;
  const _InputNickname({required this.controller});

  @override
  State<_InputNickname> createState() => _InputNicknameState();
}

class _InputNicknameState extends State<_InputNickname> {
  final _tc = TextEditingController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              TextField(
                controller: _tc,
                onChanged: (v) => widget.controller.nickname.value = v,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '输入你的昵称',
                  hintStyle: const TextStyle(
                      color: AppColors.textHint, fontSize: 18),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 18),
                ),
                onSubmitted: (_) {
                  if (widget.controller.nickname.value.trim().isNotEmpty) {
                    widget.controller.nextStep();
                  }
                },
              ),
              const SizedBox(height: 16),
              _ConfirmBtn(
                label: '好的，继续 →',
                enabled: widget.controller.nickname.value.trim().isNotEmpty,
                onTap: widget.controller.nextStep,
              ),
            ],
          ),
        ));
  }
}

// ── Step 2：年龄段 ────────────────────────────────────────
class _ChooseAgeGroup extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseAgeGroup({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: AgeGroup.values.map((age) {
                  final sel = controller.selectedAgeGroup.value == age;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectedAgeGroup.value = age;
                    },
                    child: AnimatedContainer(
                      duration: 200.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: sel ? AppColors.primaryGradient : null,
                        color: sel ? null : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.glassBorder,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Text(
                        age.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _ConfirmBtn(
                label: '确认 →',
                enabled: controller.selectedAgeGroup.value != null,
                onTap: controller.nextStep,
              ),
            ],
          ),
        ));
  }
}

// ── Step 3：风格偏好 ──────────────────────────────────────
class _ChooseStyle extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseStyle({required this.controller});

  static const _items = [
    (StyleType.sweet, '🎀', '甜美'),
    (StyleType.intellectual, '📚', '知性'),
    (StyleType.cool, '🖤', '酷飒'),
    (StyleType.vintage, '🌹', '复古'),
    (StyleType.minimal, '⬜', '极简'),
    (StyleType.street, '🛹', '街头'),
    (StyleType.elegant, '✨', '优雅'),
    (StyleType.sporty, '⚡', '运动'),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: _items.map((item) {
                  final (style, emoji, label) = item;
                  final sel = controller.selectedStyle.value == style;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectedStyle.value = style;
                    },
                    child: AnimatedContainer(
                      duration: 200.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: sel ? AppColors.primaryGradient : null,
                        color: sel ? null : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.glassBorder,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _ConfirmBtn(
                label: '这就是我 →',
                enabled: controller.selectedStyle.value != null,
                onTap: controller.nextStep,
              ),
            ],
          ),
        ));
  }
}

// ── Step 4：身材 ──────────────────────────────────────────
class _ChooseBodyShape extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseBodyShape({required this.controller});

  static const _items = [
    (BodyShape.apple, '🍎', '苹果型', '上半身丰满'),
    (BodyShape.pear, '🍐', '梨形', '下半身较宽'),
    (BodyShape.hourglass, '⏳', '沙漏型', '腰细臀丰'),
    (BodyShape.rectangle, '📏', '直筒型', '上下均匀'),
    (BodyShape.invertedTriangle, '🔺', '倒三角', '肩宽腰细'),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              ..._items.map((item) {
                final (shape, emoji, label, desc) = item;
                final sel = controller.selectedBodyShape.value == shape;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.selectedBodyShape.value = shape;
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: sel ? AppColors.primaryGradient : null,
                      color: sel ? null : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel ? AppColors.primary : AppColors.glassBorder,
                        width: sel ? 2 : 1,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              desc,
                              style: TextStyle(
                                fontSize: 11,
                                color: sel
                                    ? Colors.white.withOpacity(0.8)
                                    : AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (sel)
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              _ConfirmBtn(
                label: '确认 →',
                enabled: controller.selectedBodyShape.value != null,
                onTap: controller.nextStep,
              ),
            ],
          ),
        ));
  }
}

// ── Step 5：肤质 ──────────────────────────────────────────
class _ChooseSkinType extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseSkinType({required this.controller});

  static const _items = [
    (SkinType.dry, '🏜️', '干性', '容易紧绷脱皮'),
    (SkinType.oily, '💦', '油性', '容易出油发亮'),
    (SkinType.combination, '☯️', '混合性', 'T区油、两颊干'),
    (SkinType.sensitive, '🌸', '敏感肌', '容易泛红过敏'),
    (SkinType.acneProne, '😤', '痘痘肌', '容易长痘'),
    (SkinType.normal, '✨', '中性', '状态比较均衡'),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: _items.map((item) {
                  final (type, emoji, label, desc) = item;
                  final sel = controller.selectedSkinType.value == type;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectedSkinType.value = type;
                    },
                    child: AnimatedContainer(
                      duration: 200.ms,
                      width: (MediaQuery.of(context).size.width - 64) / 2,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: sel ? AppColors.primaryGradient : null,
                        color: sel ? null : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.glassBorder,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            style: TextStyle(
                              fontSize: 10,
                              color: sel
                                  ? Colors.white.withOpacity(0.8)
                                  : AppColors.textHint,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _ConfirmBtn(
                label: '确认 →',
                enabled: controller.selectedSkinType.value != null,
                onTap: controller.nextStep,
              ),
            ],
          ),
        ));
  }
}

// ── Step 6：预算 ──────────────────────────────────────────
class _ChooseBudget extends StatelessWidget {
  final OnboardingController controller;
  const _ChooseBudget({required this.controller});

  static const _emojis = ['💰', '💎', '✨', '👑'];

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              ...List.generate(BudgetLevel.values.length, (i) {
                final budget = BudgetLevel.values[i];
                final sel = controller.selectedBudget.value == budget;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    controller.selectedBudget.value = budget;
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: sel ? AppColors.primaryGradient : null,
                      color: sel ? null : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel ? AppColors.primary : AppColors.glassBorder,
                        width: sel ? 2 : 1,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(_emojis[i], style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Text(
                          budget.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (sel)
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Obx(() => controller.isSaving.value
                  ? const SizedBox(
                      height: 50,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : _ConfirmBtn(
                      label: '完成，开始体验 🎉',
                      enabled: controller.selectedBudget.value != null,
                      onTap: controller.nextStep,
                    )),
            ],
          ),
        ));
  }
}
