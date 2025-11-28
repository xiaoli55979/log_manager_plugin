import 'package:logger/logger.dart';
import 'log_file_manager.dart';

/// 文件日志输出类，去除ANSI颜色代码
class FileOutput extends LogOutput {
  // ANSI颜色代码的正则表达式
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');

  @override
  void output(OutputEvent event) {
    // 去除颜色代码后写入文件
    final cleanLines = event.lines.map((line) => _removeAnsiCodes(line));
    final logText = cleanLines.join('\n');
    LogFileManager.instance.writeLog(logText);
  }

  /// 移除ANSI颜色代码
  String _removeAnsiCodes(String text) {
    return text.replaceAll(_ansiRegex, '');
  }
}
