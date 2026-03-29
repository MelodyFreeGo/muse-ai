import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
import 'core/services/storage_service.dart';
import 'features/splash/splash_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/home/home_page.dart';
import 'features/profile/profile_page.dart';
import 'features/beauty/beauty_page.dart';
import 'features/wardrobe/wardrobe_page.dart';
import 'features/analysis/analysis_report_page.dart';
import 'features/ingredient/ingredient_report_page.dart';
import 'features/history/history_page.dart';
import 'features/beauty/lipstick_page.dart';
import 'features/settings/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地存储
  await StorageService.to.init();

  // 状态栏透明
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // 锁定竖屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MuseApp());
}

class MuseApp extends StatelessWidget {
  const MuseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.splash,  // 始终从 Splash 启动，由它决定跳转
      getPages: [
        GetPage(
          name: AppRoutes.splash,
          page: () => const SplashPage(),
        ),
        GetPage(
          name: AppRoutes.onboarding,
          page: () => const OnboardingPage(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: AppRoutes.home,
          page: () => const HomePage(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name: AppRoutes.profile,
          page: () => const ProfilePage(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppRoutes.beauty,
          page: () => const BeautyPage(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppRoutes.wardrobe,
          page: () => const WardrobePage(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppRoutes.analysisReport,
          page: () => const AnalysisReportPage(),
          transition: Transition.downToUp,
        ),
        GetPage(
          name: AppRoutes.ingredientReport,
          page: () => const IngredientReportPage(),
          transition: Transition.downToUp,
        ),
        GetPage(
          name: AppRoutes.history,
          page: () => const HistoryPage(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppRoutes.lipstick,
          page: () => const LipstickPage(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name: AppRoutes.settings,
          page: () => const SettingsPage(),
          transition: Transition.rightToLeft,
        ),
      ],
    );
  }
}
