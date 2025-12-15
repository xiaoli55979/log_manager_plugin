import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'log_config.dart';
import 'log_file_manager.dart';
import 'log_reporter.dart';
import 'simple_log_printer.dart';

/// 日志工具类
class LogManager {
  static LogManager? _instance;
  static LogManager get instance => _instance ??= LogManager._();

  LogManager._();

  late Logger _logger;
  late LogManagerConfig _config;
  bool _initialized = false;

  /// 初始化日志系统
  ///
  /// 注意：在多插件项目中，只需在主应用中初始化一次
  /// 重复调用会使用新配置重新初始化
  ///
  /// 示例：
  /// ```dart
  /// // 在 main.dart 中初始化
  /// await LogManager.instance.init(const LogManagerConfig(...));
  ///
  /// // 其他插件直接使用，无需再次初始化
  /// LogManager.d('插件A的日志');
  /// LogManager.i('插件B的日志');
  /// ```
  Future<void> init([LogManagerConfig? config]) async {
    _config = config ?? const LogManagerConfig();

    if (!_config.enabled) {
      _initialized = false;
      return;
    }

    // 初始化文件管理器
    // 注意：文件日志在 Debug 和 Release 模式下都会记录（如果 enableFileLog 为 true）
    if (_config.enableFileLog) {
      await LogFileManager.instance.init(
        logDirectory: _config.logDirectory,
        maxFileSize: _config.maxFileSize,
        maxRetentionDays: _config.maxRetentionDays,
      );
    }

    // 设置上报器配置
    LogReporter.instance.setConfig(_config);

    // 判断是否启用控制台输出（根据 Debug/Release 模式区分）
    final enableConsole = kDebugMode
        ? _config.enableConsoleInDebug
        : _config.enableConsoleInRelease;

    // 创建Logger实例
    // 文件输出：在 Debug 和 Release 模式下都会记录（如果 enableFileLog 为 true）
    _logger = Logger(
      filter: ProductionFilter(),
      printer: SimpleLogPrinter(
        printTime: true,
        printLevel: true,
      ),
      output: _CustomMultiOutput(
        enableConsole: enableConsole,
        enableFile: _config.enableFileLog,
      ),
      level: _config.logLevel,
    );

    _initialized = true;
  }

  /// 更新配置
  Future<void> updateConfig(LogManagerConfig config) async {
    await init(config);
  }

  /// Verbose日志
  static void v(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.t(message, error: error, stackTrace: stackTrace);
  }

  /// Debug日志
  static void d(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Info日志
  static void i(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning日志
  static void w(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error日志
  static void e(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Fatal日志
  static void f(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    if (!instance._initialized) return;
    instance._logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// 获取所有日志文件
  static Future<List<File>> getAllLogFiles() async {
    return await LogFileManager.instance.getAllLogFiles();
  }

  /// 压缩日志文件
  static Future<File?> compressLogs() async {
    return await LogFileManager.instance.compressLogs();
  }

  /// 清空所有日志
  static Future<void> clearAllLogs() async {
    await LogFileManager.instance.clearAllLogs();
  }

  /// 获取日志目录路径
  static String? get logDirectoryPath =>
      LogFileManager.instance.logDirectoryPath;

  /// 获取当前配置
  static LogManagerConfig get config => instance._config;
}

/// 自定义多输出类
class _CustomMultiOutput extends LogOutput {
  final bool enableConsole;
  final bool enableFile;

  // ANSI颜色代码的正则表达式
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');

  _CustomMultiOutput({
    required this.enableConsole,
    required this.enableFile,
  });

  @override
  void output(OutputEvent event) {
    // 控制台输出
    if (enableConsole) {
      // 使用 debugPrint 输出，每行单独打印
      // debugPrint 有长度限制（约1000字符），需要分段
      for (var line in event.lines) {
        _printLongString(line);
      }
    }

    // 文件输出（去除颜色）
    if (enableFile) {
      final cleanLines = event.lines.map((line) => _removeAnsiCodes(line));
      final logText = cleanLines.join('\n');
      LogFileManager.instance.writeLog(logText);
    }
  }

  /// 打印超长字符串，自动分段避免 debugPrint 截断
  void _printLongString(String text) {
    const int chunkSize = 800; // debugPrint 限制约1000，留点余量
    if (text.length <= chunkSize) {
      debugPrint(text);
      return;
    }

    // 分段打印
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      debugPrint(text.substring(i, end));
    }
  }

  /// 移除ANSI颜色代码
  String _removeAnsiCodes(String text) {
    return text.replaceAll(_ansiRegex, '');
  }
}
