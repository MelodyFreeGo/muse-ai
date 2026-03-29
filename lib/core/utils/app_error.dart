import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// ════════════════════════════════════════════════════════════════
//  AppException — 统一异常类型
// ════════════════════════════════════════════════════════════════

/// MUSE 统一异常，覆盖所有已知错误场景
enum AppErrorType {
  /// 设备无网络连接
  noNetwork,
  /// 请求超时
  timeout,
  /// 服务器返回 4xx / 5xx
  serverError,
  /// API Key 无效 / 余额不足
  authError,
  /// 内容被安全策略拒绝
  contentFiltered,
  /// 解析响应失败（JSON 格式错误等）
  parseError,
  /// 本地资源加载失败
  localError,
  /// 未知错误
  unknown,
}

class AppException implements Exception {
  AppException({
    required this.type,
    required this.message,
    this.statusCode,
    this.cause,
  });

  final AppErrorType type;

  /// 用户可见的友好提示
  final String message;

  /// HTTP 状态码（仅网络错误时有值）
  final int? statusCode;

  /// 原始异常（用于日志）
  final Object? cause;

  /// 是否值得重试（网络类错误可重试，鉴权错误不重试）
  bool get isRetryable =>
      type == AppErrorType.noNetwork ||
      type == AppErrorType.timeout ||
      type == AppErrorType.serverError;

  @override
  String toString() =>
      'AppException(type=$type, status=$statusCode, msg=$message)';
}

// ════════════════════════════════════════════════════════════════
//  ErrorMapper — 将原始异常映射到 AppException
// ════════════════════════════════════════════════════════════════

class ErrorMapper {
  ErrorMapper._();

  static AppException from(Object error, {int? statusCode}) {
    // ── HTTP 状态码 ────────────────────────────────────────────
    if (statusCode != null) {
      if (statusCode == 401 || statusCode == 403) {
        return AppException(
          type: AppErrorType.authError,
          message: 'API Key 无效或余额不足，请检查配置',
          statusCode: statusCode,
          cause: error,
        );
      }
      if (statusCode == 429) {
        return AppException(
          type: AppErrorType.serverError,
          message: '请求过于频繁，请稍后再试',
          statusCode: statusCode,
          cause: error,
        );
      }
      if (statusCode >= 500) {
        return AppException(
          type: AppErrorType.serverError,
          message: 'AI 服务暂时繁忙，请稍候重试',
          statusCode: statusCode,
          cause: error,
        );
      }
      return AppException(
        type: AppErrorType.serverError,
        message: '服务请求失败（$statusCode），请稍后重试',
        statusCode: statusCode,
        cause: error,
      );
    }

    // ── 超时 ───────────────────────────────────────────────────
    if (error is TimeoutException) {
      return AppException(
        type: AppErrorType.timeout,
        message: '响应超时，可能是网络不稳定，请重试',
        cause: error,
      );
    }

    // ── 无网络 ─────────────────────────────────────────────────
    if (error is SocketException) {
      return AppException(
        type: AppErrorType.noNetwork,
        message: '网络连接失败，请检查网络后重试',
        cause: error,
      );
    }

    // ── JSON 解析 ──────────────────────────────────────────────
    if (error is FormatException) {
      return AppException(
        type: AppErrorType.parseError,
        message: '数据解析出错，请重试',
        cause: error,
      );
    }

    // ── 已是 AppException → 透传 ──────────────────────────────
    if (error is AppException) return error;

    // ── 兜底 ──────────────────────────────────────────────────
    return AppException(
      type: AppErrorType.unknown,
      message: '出了点小问题，稍后再试吧～',
      cause: error,
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  AppLogger — 分级日志（debug/info/warn/error）
// ════════════════════════════════════════════════════════════════

enum LogLevel { debug, info, warn, error }

class AppLogger {
  AppLogger._();

  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.warn;

  static void setLevel(LogLevel level) => _minLevel = level;

  static void d(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  static void i(String tag, String msg) => _log(LogLevel.info,  tag, msg);
  static void w(String tag, String msg, [Object? err]) =>
      _log(LogLevel.warn, tag, msg, err);
  static void e(String tag, String msg, [Object? err, StackTrace? st]) =>
      _log(LogLevel.error, tag, msg, err, st);

  static void _log(
    LogLevel level,
    String tag,
    String msg, [
    Object? err,
    StackTrace? st,
  ]) {
    if (level.index < _minLevel.index) return;

    final prefix = switch (level) {
      LogLevel.debug => '🔍 DEBUG',
      LogLevel.info  => '✅ INFO ',
      LogLevel.warn  => '⚠️ WARN ',
      LogLevel.error => '🔴 ERROR',
    };

    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$timestamp] $prefix [$tag] $msg';

    debugPrint(line);
    if (err != null) debugPrint('  cause: $err');
    if (st != null && level == LogLevel.error) {
      debugPrint('  stack: ${st.toString().split('\n').take(5).join('\n         ')}');
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  RetryHelper — 指数退避自动重试
// ════════════════════════════════════════════════════════════════

class RetryHelper {
  RetryHelper._();

  /// 执行 [action]，失败时自动重试最多 [maxRetries] 次
  ///
  /// [retryIf]：返回 true 才重试（默认：仅重试 isRetryable 的 AppException）
  static Future<T> run<T>({
    required Future<T> Function() action,
    int maxRetries = 2,
    Duration baseDelay = const Duration(milliseconds: 1000),
    bool Function(Object err)? retryIf,
    String tag = 'RetryHelper',
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (e) {
        attempt++;

        // 判断是否可以重试
        final shouldRetry = retryIf != null
            ? retryIf(e)
            : (e is AppException && e.isRetryable);

        if (!shouldRetry || attempt > maxRetries) {
          rethrow;
        }

        // 指数退避：1s, 2s, 4s...
        final delay = baseDelay * (1 << (attempt - 1));
        AppLogger.w(tag, '第 $attempt 次重试（${delay.inMilliseconds}ms 后）原因: $e');
        await Future.delayed(delay);
      }
    }
  }
}
