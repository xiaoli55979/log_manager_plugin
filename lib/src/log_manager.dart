import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'log_config.dart';
import 'log_file_manager.dart';
import 'log_reporter.dart';
import 'reporting/log_report.dart';
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
      try {
        await LogFileManager.instance.init(
          logDirectory: _config.logDirectory,
          maxFileSize: _config.maxFileSize,
          maxRetentionDays: _config.maxRetentionDays,
        );

        // 验证初始化是否成功
        final logDirPath = LogFileManager.instance.logDirectoryPath;
        if (logDirPath == null) {
          if (kDebugMode) {
            debugPrint('警告: 日志文件管理器初始化后 logDirectoryPath 为 null');
          }
          // 即使路径为 null，也继续，因为可能是权限问题，但不应该阻止日志系统运行
        } else {
          // 验证目录是否存在且可写
          final dir = Directory(logDirPath);
          if (!await dir.exists()) {
            if (kDebugMode) {
              debugPrint('警告: 日志目录不存在: $logDirPath');
            }
          }
        }
      } catch (e, stackTrace) {
        // 如果 enableFileLog 为 true，初始化失败应该抛出异常，让用户知道
        // 但为了不影响应用启动，我们只记录错误，不抛出异常
        if (kDebugMode) {
          debugPrint('初始化日志文件管理器失败: $e');
          debugPrint('堆栈: $stackTrace');
        }
        // 注意：即使初始化失败，_CustomMultiOutput 仍然会尝试写入
        // writeLog 方法会处理 _currentLogFile 为 null 的情况
      }
    } else {
      if (kDebugMode) {
        debugPrint('文件日志已禁用 (enableFileLog: false)');
      }
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

  // ===== 以下为纯新增的公共上报接口(默认不启用,不影响以上任何现有方法) =====

  /// full_logs 全量日志上报使用的 topic 常量。
  static const String fullLogsTopic = 'full_logs';

  static final LogReportQueue _reportQueue = LogReportQueue();
  static bool _remoteFullLogEnabled = false;
  static Level _remoteFullLogMinLevel = Level.warning;
  static bool _appLogViewerRemoteFullLogEnabled = false;
  static Level _appLogViewerRemoteFullLogMinLevel = Level.debug;
  static Map<String, String> _remoteFullLogContext = const {};

  /// full_logs 上报前的脱敏钩子(默认 null = 不脱敏)。开启 full_logs 应注入,
  /// 对每行原始日志做 token/手机号/订单等敏感信息处理后再入队。
  static String Function(String line)? _fullLogDesensitizer;

  /// 注入上报实现(CLS 等后端由主项目实现并注入,插件零后端依赖)。
  static void setReportSink(LogReportSink sink) {
    _reportQueue.setSink(sink);
  }

  /// 设置 full_logs 每条实时上报都会携带的公共字段。
  /// 典型字段: username/accountNo/deviceId/packageName/ip 等。
  static void setRemoteFullLogContext(Map<String, String?> context) {
    _remoteFullLogContext = Map<String, String>.unmodifiable(
      _cleanReportFields(context),
    );
  }

  /// 增量更新 full_logs 公共字段。传空字符串/null 会移除对应字段。
  static void updateRemoteFullLogContext(Map<String, String?> context) {
    final merged = <String, String?>{..._remoteFullLogContext, ...context};
    setRemoteFullLogContext(merged);
  }

  /// 统一结构化上报入口。sink 未注入时静默缓存待注入,不报错。
  static void report(
    String topic,
    Map<String, String> fields, {
    Level level = Level.info,
  }) {
    _reportQueue.enqueue(LogReportEntry(
      topic: topic,
      fields: Map<String, String>.of(fields),
      level: level.value,
      timeMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// full_logs 远程全量日志开关。开启后控制台/文件出口的全量日志(>= minLevel)
  /// 经同一可靠队列上报。定向开启 + 自动过期 + 脱敏由调用方/后台约束。
  static void enableRemoteFullLog({
    required bool enabled,
    Level minLevel = Level.warning,
  }) {
    _remoteFullLogEnabled = enabled;
    _remoteFullLogMinLevel = minLevel;
  }

  /// APP 日志查看器远程全量日志开关。与 enableRemoteFullLog 独立计数,
  /// 避免宿主旧开关和 viewer 远程配置互相覆盖。
  static void enableAppLogViewerRemoteFullLog({
    required bool enabled,
    Level minLevel = Level.debug,
  }) {
    _appLogViewerRemoteFullLogEnabled = enabled;
    _appLogViewerRemoteFullLogMinLevel = minLevel;
  }

  /// 注入 full_logs 脱敏钩子。开启 full_logs 上报前应配置,逐行脱敏。
  static void setFullLogDesensitizer(String Function(String line)? fn) {
    _fullLogDesensitizer = fn;
  }

  /// full_logs 队列退出兜底:真 await 尽量发完积压。
  static Future<void> flushReports() => _reportQueue.flush();

  /// 直接投递一行 full_logs。用于接入已有独立日志系统的 ring buffer,
  /// 不额外写文件/控制台；远程开关未启用时静默跳过。
  static void reportRemoteFullLogLine(
    String line, {
    Level level = Level.info,
    DateTime? time,
  }) {
    if (!_isRemoteFullLogEnabled) return;
    if (level < _effectiveRemoteFullLogMinLevel) return;
    if (line.isEmpty) return;
    final desensitize = _fullLogDesensitizer;
    final safeLine = desensitize == null ? line : desensitize(line);
    if (safeLine.isEmpty) return;
    _reportQueue.enqueue(LogReportEntry(
      topic: fullLogsTopic,
      fields: {
        ..._remoteFullLogContext,
        'line': safeLine,
      },
      level: level.value,
      timeMs: (time ?? DateTime.now()).millisecondsSinceEpoch,
    ));
  }

  static Map<String, String> _cleanReportFields(
    Map<String, String?> fields,
  ) {
    final cleaned = <String, String>{};
    fields.forEach((key, value) {
      final normalizedKey = key.trim();
      final normalizedValue = value?.trim();
      if (normalizedKey.isEmpty ||
          normalizedKey == 'line' ||
          normalizedValue == null ||
          normalizedValue.isEmpty) {
        return;
      }
      cleaned[normalizedKey] = normalizedValue;
    });
    return cleaned;
  }

  static bool get _isRemoteFullLogEnabled =>
      _remoteFullLogEnabled || _appLogViewerRemoteFullLogEnabled;

  static Level get _effectiveRemoteFullLogMinLevel {
    if (!_remoteFullLogEnabled) return _appLogViewerRemoteFullLogMinLevel;
    if (!_appLogViewerRemoteFullLogEnabled) return _remoteFullLogMinLevel;
    return _appLogViewerRemoteFullLogMinLevel.value <
            _remoteFullLogMinLevel.value
        ? _appLogViewerRemoteFullLogMinLevel
        : _remoteFullLogMinLevel;
  }

  /// 供 _CustomMultiOutput 调用的全量日志 tap。未开启/未达阈值/无 sink 时静默丢弃。
  static void _tapFullLog(OutputEvent event, List<String> cleanLines) {
    for (final raw in cleanLines) {
      if (raw.isEmpty) continue;
      LogManager.reportRemoteFullLogLine(
        raw,
        level: event.level,
        time: event.origin.time,
      );
    }
  }
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
      // 将整个日志块合并为一个字符串，一次性输出
      // 这样可以避免在多线程环境下被其他日志打断
      final logText = event.lines.join('\n');
      _printLongString(logText);
    }

    // 文件输出（去除颜色）
    if (enableFile) {
      final cleanLines = event.lines.map((line) => _removeAnsiCodes(line));
      final logText = cleanLines.join('\n');
      LogFileManager.instance.writeLog(logText);
    }

    // full_logs 远程全量上报(纯新增第三分支,不影响以上 console/file 两个分支)
    if (LogManager._isRemoteFullLogEnabled) {
      final tapLines =
          event.lines.map((line) => _removeAnsiCodes(line)).toList();
      LogManager._tapFullLog(event, tapLines);
    }
  }

  /// 打印超长字符串，自动分段避免 debugPrint 截断
  /// 尽量按行分段，保持日志块的完整性
  void _printLongString(String text) {
    const int chunkSize = 800; // debugPrint 限制约1000，留点余量
    if (text.length <= chunkSize) {
      debugPrint(text);
      return;
    }

    // 按行分割，尽量保持行的完整性
    final lines = text.split('\n');
    final buffer = StringBuffer();

    for (var line in lines) {
      // 如果当前缓冲区加上新行会超过限制，先输出缓冲区
      if (buffer.length > 0 && buffer.length + line.length + 1 > chunkSize) {
        debugPrint(buffer.toString());
        buffer.clear();
      }

      // 如果单行就超过限制，需要进一步分段
      if (line.length > chunkSize) {
        // 先输出缓冲区
        if (buffer.length > 0) {
          debugPrint(buffer.toString());
          buffer.clear();
        }
        // 分段输出超长行
        for (int i = 0; i < line.length; i += chunkSize) {
          final end =
              (i + chunkSize < line.length) ? i + chunkSize : line.length;
          debugPrint(line.substring(i, end));
        }
      } else {
        // 添加到缓冲区
        if (buffer.length > 0) {
          buffer.write('\n');
        }
        buffer.write(line);
      }
    }

    // 输出剩余的缓冲区内容
    if (buffer.length > 0) {
      debugPrint(buffer.toString());
    }
  }

  /// 移除ANSI颜色代码
  String _removeAnsiCodes(String text) {
    return text.replaceAll(_ansiRegex, '');
  }
}
