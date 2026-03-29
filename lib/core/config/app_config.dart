/// MUSE — 应用统一配置中心
///
/// 企业级最佳实践：
/// • 所有硬编码常量从这里读取，不散落在各服务文件
/// • 上线前可将此文件指向后端代理层，一处修改全局生效
/// • Key 真正加固建议：后台下发 + 本地 AES 加密存储；
///   当前阶段先集中管理，便于后续一键迁移
class AppConfig {
  AppConfig._();

  // ════════════════════════════════════════════════════════════
  //  🔐  API Keys（统一管理，上线前移至后端中间层）
  // ════════════════════════════════════════════════════════════

  /// DeepSeek 文字对话 Key
  static const deepSeekKey = 'sk-809cbe53e04444c8b9057d8eab097390';

  /// 通义千问 VL 视觉分析 + CosyVoice TTS Key（同一账号）
  static const dashscopeKey = 'sk-5dcfa8c8dfe7408e80756a31b36fa0f4';

  // ════════════════════════════════════════════════════════════
  //  🌐  API Endpoints
  // ════════════════════════════════════════════════════════════

  static const deepSeekBase  = 'https://api.deepseek.com/v1';
  static const deepSeekModel = 'deepseek-chat';

  static const visionBase    = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const visionModel   = 'qwen-vl-plus';

  static const ttsBase       = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2audiostream/generation';
  static const ttsModel      = 'cosyvoice-v3-flash';

  // ════════════════════════════════════════════════════════════
  //  ⏱  超时 & 重试
  // ════════════════════════════════════════════════════════════

  /// LLM 请求超时（视觉分析可能较慢，建议 45s）
  static const llmTimeout    = Duration(seconds: 30);
  static const visionTimeout = Duration(seconds: 45);
  static const ttsTimeout    = Duration(seconds: 20);

  /// 最大重试次数（网络错误自动重试）
  static const maxRetries    = 2;

  /// 重试间隔基准（指数退避：1s, 2s）
  static const retryBaseMs   = 1000;

  // ════════════════════════════════════════════════════════════
  //  💬  对话上限（防止 Token 超出 + 内存膨胀）
  // ════════════════════════════════════════════════════════════

  /// 对话历史保留轮数（用户 + 助理各算1条）
  static const maxHistoryPairs = 20;

  /// 单条用户消息最大字符数
  static const maxInputLength = 500;

  /// 持久化最近N轮对话（退出后恢复）
  static const persistedHistoryPairs = 10;

  // ════════════════════════════════════════════════════════════
  //  🔑  Storage Keys（防止拼写错误的字符串 Key 散落各处）
  // ════════════════════════════════════════════════════════════

  static const kIsFirstLaunch    = 'is_first_launch';
  static const kIsOnboardingDone = 'is_onboarding_done';
  static const kSelectedAdvisor  = 'selected_advisor';
  static const kThemeMode        = 'theme_mode';
  static const kUserProfile      = 'user_profile';
  static const kChatHistory      = 'chat_history_v1';
  static const kTtsEnabled       = 'tts_enabled';

  // ════════════════════════════════════════════════════════════
  //  ✅  运行时校验：启动时调用，防止 Key 忘记配置
  // ════════════════════════════════════════════════════════════

  /// 返回是否所有 Key 都已配置（用于启动检查 / 灰度逻辑）
  static bool get isFullyConfigured =>
      deepSeekKey.isNotEmpty &&
      deepSeekKey != 'YOUR_DEEPSEEK_KEY' &&
      dashscopeKey.isNotEmpty &&
      dashscopeKey != 'YOUR_DASHSCOPE_KEY';

  /// Mock 模式：Key 未配置时自动走 Mock，方便开发
  static bool get useMock => !isFullyConfigured;
}
