import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../core/services/storage_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // 等Logo动画播放完
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    if (StorageService.to.isOnboardingDone) {
      Get.offAllNamed(AppRoutes.home);
    } else {
      Get.offAllNamed(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF0E8), // 浅粉橙
              Color(0xFFFAF8F5), // 米白
              Color(0xFFF5EEE8), // 浅玫瑰
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // MUSE Logo
            Column(
              children: [
                // 图标（占位，后续替换为真实Logo）
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('✦', style: TextStyle(fontSize: 44, color: Colors.white)),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .scale(begin: const Offset(0.7, 0.7), duration: 700.ms,
                        curve: Curves.elasticOut),

                const SizedBox(height: 20),

                // 品牌名
                const Text(
                  'MUSE',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 8,
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 500.ms)
                    .slideY(begin: 0.3, end: 0, duration: 500.ms),

                const SizedBox(height: 8),

                const Text(
                  '你的 AI 私人风格顾问',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    letterSpacing: 2,
                  ),
                )
                    .animate(delay: 400.ms)
                    .fadeIn(duration: 500.ms),
              ],
            ),

            const Spacer(flex: 4),

            // 底部加载指示
            const Text(
              '正在为你准备...',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            )
                .animate(delay: 800.ms)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
