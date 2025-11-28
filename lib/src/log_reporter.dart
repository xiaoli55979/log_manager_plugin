import 'dart:io';
import 'log_file_manager.dart';
import 'log_util.dart';
import 'log_config.dart';

/// 日志上报回调类型（文件方式）
typedef LogUploadCallback = Future<bool> Function(File zipFile);

/// 日志上报回调类型（字符串方式）
typedef LogUploadStringCallback = Future<bool> Function(List<LogBatch> batches);

/// 日志批次数据
class LogBatch {
  /// 批次索引（从1开始）
  final int batchIndex;

  /// 总批次数
  final int totalBatches;

  /// 日志内容
  final String content;

  /// 文件名
  final String fileName;

  /// 日期（格式：yyyyMMdd）
  final String date;

  LogBatch({
    required this.batchIndex,
    required this.totalBatches,
    required this.content,
    required this.fileName,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'batchIndex': batchIndex,
        'totalBatches': totalBatches,
        'content': content,
        'fileName': fileName,
        'date': date,
      };
}

/// 日志上报器
class LogReporter {
  static LogReporter? _instance;
  static LogReporter get instance => _instance ??= LogReporter._();

  LogReporter._();

  /// 日志上报回调（文件方式）
  LogUploadCallback? _uploadCallback;

  /// 日志上报回调（字符串方式）
  LogUploadStringCallback? _uploadStringCallback;

  /// 日志配置
  LogManagerConfig? _config;

  /// 设置日志上报回调（文件方式）
  void setUploadCallback(LogUploadCallback callback) {
    _uploadCallback = callback;
  }

  /// 设置日志上报回调（字符串方式）
  void setUploadStringCallback(LogUploadStringCallback callback) {
    _uploadStringCallback = callback;
  }

  /// 设置配置
  void setConfig(LogManagerConfig config) {
    _config = config;
  }

  /// 一键上报日志
  ///
  /// [deleteAfterUpload] 上报成功后是否删除压缩文件，为null时使用配置中的值
  /// [specificFiles] 指定要上报的文件，为空则上报所有文件
  ///
  /// 返回值：
  /// - true: 上报成功
  /// - false: 上报失败或未设置回调
  Future<bool> uploadLogs({
    bool? deleteAfterUpload,
    List<File>? specificFiles,
  }) async {
    final shouldDelete =
        deleteAfterUpload ?? _config?.deleteAfterUpload ?? true;
    try {
      LogUtil.i('开始压缩日志文件...');

      // 压缩日志
      final File? zipFile;
      if (specificFiles != null && specificFiles.isNotEmpty) {
        zipFile =
            await LogFileManager.instance.compressSpecificLogs(specificFiles);
      } else {
        zipFile = await LogFileManager.instance.compressLogs();
      }

      if (zipFile == null) {
        LogUtil.w('日志压缩失败：没有日志文件');
        return false;
      }

      LogUtil.i('日志压缩成功: ${zipFile.path}');

      // 检查是否设置了上报回调
      if (_uploadCallback == null) {
        LogUtil.w('未设置日志上报回调，请先调用 LogReporter.instance.setUploadCallback()');
        return false;
      }

      // 调用上报回调
      LogUtil.i('开始上报日志...');
      final success = await _uploadCallback!(zipFile);

      if (success) {
        LogUtil.i('日志上报成功');

        // 上报成功后删除压缩文件
        if (shouldDelete) {
          try {
            await zipFile.delete();
            LogUtil.d('已删除压缩文件: ${zipFile.path}');
          } catch (e) {
            LogUtil.w('删除压缩文件失败: $e');
          }
        }
      } else {
        LogUtil.e('日志上报失败');
      }

      return success;
    } catch (e, stackTrace) {
      LogUtil.e('日志上报异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 上报指定日期的日志
  ///
  /// [deleteAfterUpload] 上报成功后是否删除压缩文件，为null时使用配置中的值
  Future<bool> uploadLogsByDate(
    String date, {
    bool? deleteAfterUpload,
  }) async {
    final shouldDelete =
        deleteAfterUpload ?? _config?.deleteAfterUpload ?? true;
    try {
      LogUtil.i('开始压缩 $date 的日志...');

      final zipFile = await LogFileManager.instance.compressLogsByDate(date);

      if (zipFile == null) {
        LogUtil.w('日志压缩失败：没有找到 $date 的日志文件');
        return false;
      }

      LogUtil.i('日志压缩成功: ${zipFile.path}');

      if (_uploadCallback == null) {
        LogUtil.w('未设置日志上报回调');
        return false;
      }

      LogUtil.i('开始上报日志...');
      final success = await _uploadCallback!(zipFile);

      if (success) {
        LogUtil.i('日志上报成功');

        if (shouldDelete) {
          try {
            await zipFile.delete();
            LogUtil.d('已删除压缩文件: ${zipFile.path}');
          } catch (e) {
            LogUtil.w('删除压缩文件失败: $e');
          }
        }
      } else {
        LogUtil.e('日志上报失败');
      }

      return success;
    } catch (e, stackTrace) {
      LogUtil.e('日志上报异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 以字符串方式上报日志（分批上传）
  ///
  /// [maxBatchSize] 每批最大字符数（字节），为null时使用配置中的值
  /// [specificFiles] 指定要上报的文件，为空则上报所有文件
  Future<bool> uploadLogsAsString({
    int? maxBatchSize,
    List<File>? specificFiles,
  }) async {
    final batchSize = maxBatchSize ?? _config?.maxBatchSize ?? 100 * 1024;
    try {
      if (_uploadStringCallback == null) {
        LogUtil.w('未设置字符串上报回调，请先调用 setUploadStringCallback()');
        return false;
      }

      LogUtil.i('开始读取日志文件...');

      // 获取要上报的文件
      final List<File> files;
      if (specificFiles != null && specificFiles.isNotEmpty) {
        files = specificFiles;
      } else {
        files = await LogFileManager.instance.getAllLogFiles();
      }

      if (files.isEmpty) {
        LogUtil.w('没有日志文件可上报');
        return false;
      }

      // 读取所有文件并分批
      final batches = <LogBatch>[];

      for (final file in files) {
        try {
          final fileName = file.path.split('/').last;
          final content = await file.readAsString();

          // 提取日期
          final dateMatch = RegExp(r'log_(\d{8})_').firstMatch(fileName);
          final date = dateMatch?.group(1) ?? 'unknown';

          // 如果文件内容小于批次大小，直接作为一批
          if (content.length <= batchSize) {
            batches.add(LogBatch(
              batchIndex: 1,
              totalBatches: 1,
              content: content,
              fileName: fileName,
              date: date,
            ));
          } else {
            // 分批处理
            final totalBatches = (content.length / batchSize).ceil();
            for (int i = 0; i < totalBatches; i++) {
              final start = i * batchSize;
              final end = (start + batchSize < content.length)
                  ? start + batchSize
                  : content.length;

              batches.add(LogBatch(
                batchIndex: i + 1,
                totalBatches: totalBatches,
                content: content.substring(start, end),
                fileName: fileName,
                date: date,
              ));
            }
          }
        } catch (e) {
          LogUtil.w('读取文件失败: ${file.path}, 错误: $e');
        }
      }

      if (batches.isEmpty) {
        LogUtil.w('没有可上报的日志内容');
        return false;
      }

      LogUtil.i('准备上报 ${batches.length} 批日志数据...');

      // 调用上报回调
      final success = await _uploadStringCallback!(batches);

      if (success) {
        LogUtil.i('日志上报成功');
      } else {
        LogUtil.e('日志上报失败');
      }

      return success;
    } catch (e, stackTrace) {
      LogUtil.e('日志上报异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 以字符串方式上报指定日期的日志
  ///
  /// [maxBatchSize] 每批最大字符数（字节），为null时使用配置中的值
  Future<bool> uploadLogsByDateAsString(
    String date, {
    int? maxBatchSize,
  }) async {
    try {
      final allFiles = await LogFileManager.instance.getAllLogFiles();
      final dateFiles =
          allFiles.where((file) => file.path.contains('log_$date')).toList();

      if (dateFiles.isEmpty) {
        LogUtil.w('没有找到 $date 的日志文件');
        return false;
      }

      return await uploadLogsAsString(
        maxBatchSize: maxBatchSize,
        specificFiles: dateFiles,
      );
    } catch (e, stackTrace) {
      LogUtil.e('日志上报异常', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}
