import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';

/// 日志文件管理器 - 按天管理日志文件
class LogFileManager {
  static LogFileManager? _instance;
  static LogFileManager get instance => _instance ??= LogFileManager._();

  LogFileManager._();

  String? _logDirectory;
  File? _currentLogFile;
  IOSink? _writeSink; // 使用 IOSink 进行更可靠的文件写入
  int _currentFileSize = 0;
  int _maxFileSize = 10 * 1024 * 1024; // 10MB
  int _maxRetentionDays = 7; // 保留7天
  String _currentDate = '';

  /// 初始化日志文件管理器
  Future<void> init({
    required String logDirectory,
    required int maxFileSize,
    required int maxRetentionDays,
  }) async {
    _maxFileSize = maxFileSize;
    _maxRetentionDays = maxRetentionDays;

    try {
      final directory = await getApplicationDocumentsDirectory();
      _logDirectory = '${directory.path}/$logDirectory';

      final dir = Directory(_logDirectory!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _initCurrentLogFile();

      // 验证文件是否创建成功
      if (_currentLogFile == null) {
        if (kDebugMode) {
          debugPrint('警告: 日志文件初始化后 _currentLogFile 为 null');
        }
        // 尝试重新创建
        await _createNewLogFile();
      }

      // 安全地清理旧文件，捕获所有异常
      try {
        await _cleanOldLogFiles();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('清理旧日志文件时出错（已忽略）: $e');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('初始化日志文件管理器失败: $e');
        debugPrint('堆栈: $stackTrace');
      }
      rethrow;
    }
  }

  /// 关闭写入流
  Future<void> _closeWriteSink() async {
    if (_writeSink != null) {
      try {
        await _writeSink!.flush();
        await _writeSink!.close();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('关闭写入流失败: $e');
        }
      } finally {
        _writeSink = null;
      }
    }
  }

  /// 初始化当前日志文件
  ///
  /// 每次应用启动时都会创建新的日志文件，避免单日日志过长
  Future<void> _initCurrentLogFile() async {
    if (_logDirectory == null) {
      if (kDebugMode) {
        debugPrint('警告: _logDirectory 为 null，无法初始化日志文件');
      }
      return;
    }

    try {
      // 关闭旧的写入流
      await _closeWriteSink();

      final today = DateFormat('yyyyMMdd').format(DateTime.now());
      _currentDate = today;

      // 每次启动都创建新文件，不检查现有文件
      await _createNewLogFile();

      // 验证文件是否创建成功
      if (_currentLogFile == null) {
        if (kDebugMode) {
          debugPrint('警告: 创建日志文件后 _currentLogFile 仍为 null');
        }
        throw Exception('无法创建日志文件');
      }

      // 验证文件是否可写
      if (!await _currentLogFile!.exists()) {
        // 文件不存在，尝试创建
        await _currentLogFile!.create(recursive: true);
      }

      // 打开写入流，使用追加模式
      try {
        _writeSink = _currentLogFile!.openWrite(mode: FileMode.append);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('打开日志文件写入流失败: $e');
        }
        _writeSink = null;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('初始化当前日志文件失败: $e');
        debugPrint('堆栈: $stackTrace');
      }
      _currentLogFile = null;
      _writeSink = null;
      rethrow;
    }
  }

  /// 创建新的日志文件
  ///
  /// 文件名格式: log_20231128_120530_001.txt (日期_时间_序号)
  /// 每次应用启动都会创建新文件，使用时间戳确保唯一性
  Future<void> _createNewLogFile() async {
    if (_logDirectory == null) return;

    final now = DateTime.now();
    final today = DateFormat('yyyyMMdd').format(now);
    final time = DateFormat('HHmmss').format(now);
    _currentDate = today;

    // 查找今天同一时间戳的文件数量（处理同一秒内多次创建的情况）
    final timePrefix = 'log_${today}_$time';
    final dir = Directory(_logDirectory!);
    int fileIndex = 1;

    if (await dir.exists()) {
      final existingFiles = await dir.list().where((entity) {
        if (entity is! File || !entity.path.endsWith('.txt')) {
          return false;
        }
        final fileName = entity.path.split('/').last;
        return fileName.startsWith(timePrefix);
      }).toList();

      fileIndex = existingFiles.length + 1;
    }

    // 文件名格式: log_20231128_120530_001.txt
    final fileName =
        '${timePrefix}_${fileIndex.toString().padLeft(3, '0')}.txt';
    _currentLogFile = File('$_logDirectory/$fileName');
    _currentFileSize = 0;

    // 注意：写入流在 _initCurrentLogFile 中打开，这里不需要重复打开
  }

  /// 写入日志到文件（异步，不阻塞主线程）
  ///
  /// 如果 enableFileLog 为 true，必须确保日志写入文件
  ///
  /// 注意：只有在文件管理器被正确初始化后才会写入文件
  /// 如果 enabled 为 false，文件管理器不会被初始化，此方法不会写入任何内容
  void writeLog(String log) {
    // 如果文件管理器未初始化（enabled 为 false 时），直接返回
    if (_logDirectory == null) {
      // 文件管理器未初始化，不写入文件
      return;
    }

    // 如果文件未初始化，尝试重新初始化
    if (_currentLogFile == null) {
      if (_logDirectory != null) {
        // 尝试重新初始化文件
        _initCurrentLogFile().then((_) {
          // 初始化成功后，再次尝试写入
          if (_currentLogFile != null) {
            _writeLogAsync(log).catchError((error, stackTrace) {
              if (kDebugMode) {
                debugPrint('写入日志文件异步错误: $error');
              }
            });
          }
        }).catchError((error) {
          if (kDebugMode) {
            debugPrint('重新初始化日志文件失败: $error');
          }
        });
      }
      return;
    }

    // 异步执行，不阻塞主线程
    _writeLogAsync(log).catchError((error, stackTrace) {
      // 捕获异步错误，尝试重新初始化后重试
      if (kDebugMode) {
        debugPrint('写入日志文件异步错误: $error');
      }

      // 如果写入失败，尝试重新初始化文件
      if (_logDirectory != null) {
        _initCurrentLogFile().catchError((e) {
          if (kDebugMode) {
            debugPrint('重新初始化日志文件失败: $e');
          }
        });
      }
    });
  }

  /// 异步写入日志实现
  Future<void> _writeLogAsync(String log) async {
    try {
      // 检查日期是否变化
      final today = DateFormat('yyyyMMdd').format(DateTime.now());
      if (today != _currentDate) {
        await _initCurrentLogFile();
        await _cleanOldLogFiles();
      }

      final logWithNewline = '$log\n';
      final bytes = logWithNewline.length;

      // 检查是否需要创建新文件
      if (_currentFileSize + bytes > _maxFileSize) {
        await _closeWriteSink(); // 关闭旧文件的写入流
        await _createNewLogFile();
        // 重新初始化文件（包括打开新的写入流）
        await _initCurrentLogFile();
      }

      // 检查文件是否仍然有效
      if (_currentLogFile == null) {
        // 尝试重新初始化
        if (_logDirectory != null) {
          await _initCurrentLogFile();
          if (_currentLogFile == null) {
            if (kDebugMode) {
              debugPrint('写入日志文件失败: 重新初始化后 _currentLogFile 仍为 null');
            }
            return;
          }
        } else {
          if (kDebugMode) {
            debugPrint('写入日志文件失败: _logDirectory 为 null');
          }
          return;
        }
      }

      // 使用 IOSink 进行写入，更可靠
      if (_writeSink != null) {
        try {
          _writeSink!.write(logWithNewline);
          // Release 模式立即刷新，确保数据写入磁盘
          if (!kDebugMode) {
            await _writeSink!.flush();
          }
          _currentFileSize += bytes;
        } catch (e) {
          // 如果写入失败，尝试重新打开文件
          if (kDebugMode) {
            debugPrint('使用 IOSink 写入失败，尝试重新打开文件: $e');
          }
          await _closeWriteSink();
          try {
            _writeSink = _currentLogFile!.openWrite(mode: FileMode.append);
            _writeSink!.write(logWithNewline);
            if (!kDebugMode) {
              await _writeSink!.flush();
            }
            _currentFileSize += bytes;
          } catch (e2) {
            // 如果还是失败，回退到 writeAsString
            if (kDebugMode) {
              debugPrint('重新打开文件失败，使用 writeAsString: $e2');
            }
            await _currentLogFile!.writeAsString(
              logWithNewline,
              mode: FileMode.append,
              flush: true, // 强制刷新
            );
            _currentFileSize += bytes;
          }
        }
      } else {
        // 如果没有写入流，使用 writeAsString（向后兼容）
        await _currentLogFile!.writeAsString(
          logWithNewline,
          mode: FileMode.append,
          flush: true, // 强制刷新，确保写入
        );
        _currentFileSize += bytes;
      }
    } catch (e, stackTrace) {
      // 在 release 模式下也记录错误，但使用更安全的方式
      if (kDebugMode) {
        debugPrint('写入日志文件失败: $e');
        debugPrint('堆栈: $stackTrace');
      }

      // 尝试重新初始化文件管理器
      try {
        if (_logDirectory != null && _currentLogFile == null) {
          await _initCurrentLogFile();
        }
      } catch (e2) {
        // 如果重新初始化也失败，静默处理
        if (kDebugMode) {
          debugPrint('重新初始化日志文件失败: $e2');
        }
      }
    }
  }

  /// 获取今天的日志文件（支持新旧两种格式）
  ///
  /// 注意：此方法现在主要用于兼容性，因为每次启动都会创建新文件
  // ignore: unused_element
  @Deprecated('每次启动都创建新文件，此方法不再使用')
  Future<List<File>> _getTodayLogFiles() async {
    if (_logDirectory == null) return [];

    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final dir = Directory(_logDirectory!);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) {
          if (entity is! File || !entity.path.endsWith('.txt')) {
            return false;
          }

          final fileName = entity.path.split('/').last;
          // 匹配新格式: log_20231128_120530_001.txt (日期_时间_序号)
          // 也兼容旧格式: log_20231128_001.txt (日期_序号)
          final newFormatMatch =
              RegExp(r'log_' + today + r'_(\d{6}_\d{3}|\d{3})\.txt$')
                  .hasMatch(fileName);
          return newFormatMatch;
        })
        .map((entity) => entity as File)
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 获取所有日志文件
  Future<List<File>> _getLogFiles() async {
    if (_logDirectory == null) return [];

    final dir = Directory(_logDirectory!);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.txt'))
        .map((entity) => entity as File)
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 清理旧的日志文件（超过保留天数的）
  Future<void> _cleanOldLogFiles() async {
    final files = await _getLogFiles();
    if (files.isEmpty) return;

    final now = DateTime.now();
    final cutoffDate = now.subtract(Duration(days: _maxRetentionDays));

    for (final file in files) {
      try {
        // 从文件名中提取日期
        // 支持多种格式:
        // 1. log_20231128_120530_001.txt (最新格式：日期_时间_序号)
        // 2. log_20231128_001.txt (旧格式：日期_序号)
        // 3. log_20231128_120530.txt (更旧格式：日期_时间)
        final fileName = file.path.split('/').last;
        final dateMatch = RegExp(r'log_(\d{8})_').firstMatch(fileName);

        if (dateMatch != null) {
          final dateStr = dateMatch.group(1)!;

          // 手动解析日期字符串，避免DateFormat的问题
          final fileDate = _parseDateString(dateStr);

          if (fileDate != null) {
            // 如果文件日期早于截止日期，删除
            if (fileDate.isBefore(cutoffDate)) {
              await file.delete();
              debugPrint('删除过期日志文件: $fileName');
            }
          } else {
            debugPrint('无法解析日志文件日期: $fileName (日期格式: $dateStr)');
          }
        }
      } catch (e) {
        debugPrint('清理日志文件失败: $e');
      }
    }
  }

  /// 手动解析日期字符串 (yyyyMMdd)
  DateTime? _parseDateString(String dateStr) {
    try {
      if (dateStr.length != 8) return null;

      final year = int.parse(dateStr.substring(0, 4));
      final month = int.parse(dateStr.substring(4, 6));
      final day = int.parse(dateStr.substring(6, 8));

      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// 获取所有日志文件列表
  Future<List<File>> getAllLogFiles() async {
    return await _getLogFiles();
  }

  /// 按日期分组获取日志文件
  Future<Map<String, List<File>>> getLogFilesByDate() async {
    final files = await _getLogFiles();
    final Map<String, List<File>> groupedFiles = {};

    for (final file in files) {
      try {
        final fileName = file.path.split('/').last;
        final dateMatch = RegExp(r'log_(\d{8})_').firstMatch(fileName);

        if (dateMatch != null) {
          final dateStr = dateMatch.group(1)!;

          // 验证日期格式是否正确
          final fileDate = _parseDateString(dateStr);

          if (fileDate != null) {
            if (!groupedFiles.containsKey(dateStr)) {
              groupedFiles[dateStr] = [];
            }
            groupedFiles[dateStr]!.add(file);
          } else {
            debugPrint('日志文件日期格式错误: $fileName (日期: $dateStr)');
          }
        }
      } catch (e) {
        debugPrint('解析日志文件日期失败: $e');
      }
    }

    return groupedFiles;
  }

  /// 压缩所有日志文件
  Future<File?> compressLogs() async {
    try {
      final files = await _getLogFiles();
      if (files.isEmpty) return null;

      return await compressSpecificLogs(files);
    } catch (e) {
      debugPrint('压缩日志文件失败: $e');
      return null;
    }
  }

  /// 压缩指定的日志文件
  Future<File?> compressSpecificLogs(List<File> files) async {
    try {
      if (files.isEmpty) return null;

      final archive = Archive();

      for (final file in files) {
        final fileName = file.path.split('/').last;
        final fileBytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(fileName, fileBytes.length, fileBytes));
      }

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final zipFile = File('$_logDirectory/logs_$timestamp.zip');
      await zipFile.writeAsBytes(zipData);

      return zipFile;
    } catch (e) {
      debugPrint('压缩指定日志文件失败: $e');
      return null;
    }
  }

  /// 压缩指定日期的日志文件
  Future<File?> compressLogsByDate(String date) async {
    try {
      final allFiles = await _getLogFiles();
      final dateFiles =
          allFiles.where((file) => file.path.contains('log_$date')).toList();

      if (dateFiles.isEmpty) return null;

      return await compressSpecificLogs(dateFiles);
    } catch (e) {
      debugPrint('压缩指定日期日志失败: $e');
      return null;
    }
  }

  /// 清空所有日志文件
  Future<void> clearAllLogs() async {
    final files = await _getLogFiles();
    for (final file in files) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('删除日志文件失败: $e');
      }
    }
    await _createNewLogFile();
  }

  /// 删除指定日期的日志文件
  Future<void> deleteLogsByDate(String date) async {
    final allFiles = await _getLogFiles();
    final dateFiles =
        allFiles.where((file) => file.path.contains('log_$date')).toList();

    for (final file in dateFiles) {
      try {
        await file.delete();
        debugPrint('删除日志文件: ${file.path.split('/').last}');
      } catch (e) {
        debugPrint('删除日志文件失败: $e');
      }
    }
  }

  /// 清理旧格式的日志文件（迁移辅助方法）
  Future<void> cleanLegacyLogFiles() async {
    final files = await _getLogFiles();

    for (final file in files) {
      try {
        final fileName = file.path.split('/').last;

        // 检查是否是旧格式: log_20231128_120530.txt (日期_时间，无序号)
        // 新格式是: log_20231128_120530_001.txt (日期_时间_序号)
        // 或: log_20231128_001.txt (日期_序号)
        final legacyMatch =
            RegExp(r'log_(\d{8})_(\d{6})\.txt$').firstMatch(fileName);

        if (legacyMatch != null) {
          debugPrint('发现旧格式日志文件: $fileName，将在下次清理时删除');
          // 可以选择立即删除或标记为待删除
          // await file.delete();
        }
      } catch (e) {
        debugPrint('检查旧格式日志文件失败: $e');
      }
    }
  }

  /// 获取日志目录路径
  String? get logDirectoryPath => _logDirectory;

  /// 获取所有压缩文件（.zip文件）
  Future<List<File>> getCompressedFiles() async {
    if (_logDirectory == null) return [];

    final dir = Directory(_logDirectory!);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.zip'))
        .map((entity) => entity as File)
        .toList();

    // 按修改时间倒序排列（最新的在前）
    final filesWithStat = await Future.wait(
      files.map((file) async {
        final stat = await file.stat();
        return (file: file, modified: stat.modified);
      }),
    );

    filesWithStat.sort((a, b) => b.modified.compareTo(a.modified));
    return filesWithStat.map((item) => item.file).toList();
  }

  /// 获取日志统计信息
  Future<LogStatistics> getStatistics() async {
    final files = await _getLogFiles();
    final groupedFiles = await getLogFilesByDate();

    int totalSize = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        totalSize += stat.size;
      } catch (e) {
        debugPrint('获取文件大小失败: $e');
      }
    }

    return LogStatistics(
      totalFiles: files.length,
      totalSize: totalSize,
      daysCount: groupedFiles.length,
      oldestDate: groupedFiles.keys.isEmpty
          ? null
          : groupedFiles.keys.reduce((a, b) => a.compareTo(b) < 0 ? a : b),
      newestDate: groupedFiles.keys.isEmpty
          ? null
          : groupedFiles.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b),
    );
  }

  /// 分享压缩的日志文件
  ///
  /// [context] 可选的 BuildContext，用于在 iPad 上设置分享位置
  Future<void> shareCompressedLog(File zipFile, {BuildContext? context}) async {
    try {
      if (!await zipFile.exists()) {
        debugPrint('分享失败：压缩文件不存在');
        return;
      }

      final fileName = zipFile.path.split('/').last;
      final xFile = XFile(zipFile.path, name: fileName);

      // 获取分享位置（iPad 需要）- 在异步操作之前获取
      Rect? sharePositionOrigin;
      if (context != null && context.mounted) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final size = box.size;
          final offset = box.localToGlobal(Offset.zero);
          sharePositionOrigin = Rect.fromLTWH(
            offset.dx,
            offset.dy,
            size.width,
            size.height,
          );
        } else {
          // 如果无法获取位置，使用屏幕中心
          final mediaQuery = MediaQuery.maybeOf(context);
          if (mediaQuery != null) {
            final screenSize = mediaQuery.size;
            sharePositionOrigin = Rect.fromLTWH(
              screenSize.width / 2,
              screenSize.height / 2,
              0,
              0,
            );
          }
        }
      }

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [xFile],
        subject: '日志文件',
        text: '日志压缩文件：$fileName',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      debugPrint('分享压缩日志文件失败: $e');
      rethrow;
    }
  }

  /// 分享单个日志文件
  ///
  /// [context] 可选的 BuildContext，用于在 iPad 上设置分享位置
  Future<void> shareLogFile(File logFile, {BuildContext? context}) async {
    try {
      if (!await logFile.exists()) {
        debugPrint('分享失败：日志文件不存在');
        return;
      }

      final fileName = logFile.path.split('/').last;
      final xFile = XFile(logFile.path, name: fileName);

      // 获取分享位置（iPad 需要）- 在异步操作之前获取
      Rect? sharePositionOrigin;
      if (context != null && context.mounted) {
        final RenderBox? box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final size = box.size;
          final offset = box.localToGlobal(Offset.zero);
          sharePositionOrigin = Rect.fromLTWH(
            offset.dx,
            offset.dy,
            size.width,
            size.height,
          );
        } else {
          // 如果无法获取位置，使用屏幕中心
          final mediaQuery = MediaQuery.maybeOf(context);
          if (mediaQuery != null) {
            final screenSize = mediaQuery.size;
            sharePositionOrigin = Rect.fromLTWH(
              screenSize.width / 2,
              screenSize.height / 2,
              0,
              0,
            );
          }
        }
      }

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [xFile],
        subject: '日志文件',
        text: '日志文件：$fileName',
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      debugPrint('分享日志文件失败: $e');
      rethrow;
    }
  }
}

/// 日志统计信息
class LogStatistics {
  final int totalFiles;
  final int totalSize;
  final int daysCount;
  final String? oldestDate;
  final String? newestDate;

  LogStatistics({
    required this.totalFiles,
    required this.totalSize,
    required this.daysCount,
    this.oldestDate,
    this.newestDate,
  });

  String get formattedTotalSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    }
    return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
