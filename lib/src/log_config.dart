import 'package:logger/logger.dart';

/// 日志管理器配置
class LogManagerConfig {
  /// 是否启用日志系统
  final bool enabled;

  /// Debug模式下是否输出到控制台
  final bool enableConsoleInDebug;

  /// Release模式下是否输出到控制台
  final bool enableConsoleInRelease;

  /// 是否写入文件
  ///
  /// 默认为 true，在 Debug 和 Release 模式下都会记录日志文件
  /// 如需只在 Debug 模式下记录，可设置为：enableFileLog: kDebugMode
  final bool enableFileLog;

  /// 单个日志文件最大大小（字节），默认10MB
  /// 超过此大小会创建新文件
  final int maxFileSize;

  /// 日志文件保留天数，默认7天
  /// 超过此天数的日志会被自动删除
  final int maxRetentionDays;

  /// 日志输出级别
  final Level logLevel;

  /// 日志文件存储目录名
  final String logDirectory;

  /// 上报成功后是否删除压缩文件
  final bool deleteAfterUpload;

  /// 字符串上报时每批最大字符数（字节），默认100KB
  final int maxBatchSize;

  const LogManagerConfig({
    this.enabled = true,
    this.enableConsoleInDebug = true,
    this.enableConsoleInRelease = false,
    this.enableFileLog = true,
    this.maxFileSize = 10 * 1024 * 1024, // 10MB
    this.maxRetentionDays = 7, // 保留7天
    this.logLevel = Level.debug,
    this.logDirectory = 'logs',
    this.deleteAfterUpload = true,
    this.maxBatchSize = 100 * 1024, // 100KB
  });

  LogManagerConfig copyWith({
    bool? enabled,
    bool? enableConsoleInDebug,
    bool? enableConsoleInRelease,
    bool? enableFileLog,
    int? maxFileSize,
    int? maxRetentionDays,
    Level? logLevel,
    String? logDirectory,
    bool? deleteAfterUpload,
    int? maxBatchSize,
  }) {
    return LogManagerConfig(
      enabled: enabled ?? this.enabled,
      enableConsoleInDebug: enableConsoleInDebug ?? this.enableConsoleInDebug,
      enableConsoleInRelease:
          enableConsoleInRelease ?? this.enableConsoleInRelease,
      enableFileLog: enableFileLog ?? this.enableFileLog,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      maxRetentionDays: maxRetentionDays ?? this.maxRetentionDays,
      logLevel: logLevel ?? this.logLevel,
      logDirectory: logDirectory ?? this.logDirectory,
      deleteAfterUpload: deleteAfterUpload ?? this.deleteAfterUpload,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
    );
  }
}
