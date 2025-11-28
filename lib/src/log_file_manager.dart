import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

/// 日志文件管理器 - 按天管理日志文件
class LogFileManager {
  static LogFileManager? _instance;
  static LogFileManager get instance => _instance ??= LogFileManager._();

  LogFileManager._();

  String? _logDirectory;
  File? _currentLogFile;
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

    final directory = await getApplicationDocumentsDirectory();
    _logDirectory = '${directory.path}/$logDirectory';

    final dir = Directory(_logDirectory!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _initCurrentLogFile();

    // 安全地清理旧文件，捕获所有异常
    try {
      await _cleanOldLogFiles();
    } catch (e) {
      print('清理旧日志文件时出错（已忽略）: $e');
    }
  }

  /// 初始化当前日志文件
  Future<void> _initCurrentLogFile() async {
    if (_logDirectory == null) return;

    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    _currentDate = today;

    // 查找今天的日志文件
    final todayFiles = await _getTodayLogFiles();

    if (todayFiles.isNotEmpty) {
      // 检查最后一个文件是否还有空间
      final latestFile = todayFiles.last;
      final stat = await latestFile.stat();
      if (stat.size < _maxFileSize) {
        _currentLogFile = latestFile;
        _currentFileSize = stat.size;
        return;
      }
    }

    // 创建新文件
    await _createNewLogFile();
  }

  /// 创建新的日志文件
  Future<void> _createNewLogFile() async {
    if (_logDirectory == null) return;

    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    _currentDate = today;

    // 查找今天已有的文件数量
    final todayFiles = await _getTodayLogFiles();
    final fileIndex = todayFiles.length + 1;

    // 文件名格式: log_20231128_001.txt, log_20231128_002.txt
    final fileName = 'log_${today}_${fileIndex.toString().padLeft(3, '0')}.txt';
    _currentLogFile = File('$_logDirectory/$fileName');
    _currentFileSize = 0;
  }

  /// 写入日志到文件
  Future<void> writeLog(String log) async {
    if (_currentLogFile == null) return;

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
      await _createNewLogFile();
    }

    try {
      await _currentLogFile!.writeAsString(
        logWithNewline,
        mode: FileMode.append,
        flush: true,
      );
      _currentFileSize += bytes;
    } catch (e) {
      print('写入日志文件失败: $e');
    }
  }

  /// 获取今天的日志文件（只返回新格式的文件）
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
          // 只匹配新格式: log_20231128_001.txt
          // 排除旧格式: log_20231128_120530.txt
          final newFormatMatch =
              RegExp(r'log_' + today + r'_(\d{3})\.txt$').hasMatch(fileName);
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
        // 支持两种格式:
        // 1. log_20231128_001.txt (新格式)
        // 2. log_20231128_120530.txt (旧格式，时间戳)
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
              print('删除过期日志文件: $fileName');
            }
          } else {
            print('无法解析日志文件日期: $fileName (日期格式: $dateStr)');
          }
        }
      } catch (e) {
        print('清理日志文件失败: $e');
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
            print('日志文件日期格式错误: $fileName (日期: $dateStr)');
          }
        }
      } catch (e) {
        print('解析日志文件日期失败: $e');
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
      print('压缩日志文件失败: $e');
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
      print('压缩指定日志文件失败: $e');
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
      print('压缩指定日期日志失败: $e');
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
        print('删除日志文件失败: $e');
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
        print('删除日志文件: ${file.path.split('/').last}');
      } catch (e) {
        print('删除日志文件失败: $e');
      }
    }
  }

  /// 清理旧格式的日志文件（迁移辅助方法）
  Future<void> cleanLegacyLogFiles() async {
    final files = await _getLogFiles();

    for (final file in files) {
      try {
        final fileName = file.path.split('/').last;

        // 检查是否是旧格式: log_20231128_120530.txt (时间戳格式)
        // 新格式是: log_20231128_001.txt (序号格式)
        final legacyMatch =
            RegExp(r'log_(\d{8})_(\d{6})\.txt$').firstMatch(fileName);

        if (legacyMatch != null) {
          print('发现旧格式日志文件: $fileName，将在下次清理时删除');
          // 可以选择立即删除或标记为待删除
          // await file.delete();
        }
      } catch (e) {
        print('检查旧格式日志文件失败: $e');
      }
    }
  }

  /// 获取日志目录路径
  String? get logDirectoryPath => _logDirectory;

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
        print('获取文件大小失败: $e');
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
