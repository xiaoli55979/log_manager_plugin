import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

/// 简洁的日志打印器，带有简单的装饰线
class SimpleLogPrinter extends LogPrinter {
  final bool printTime;
  final bool printLevel;
  final int lineLength;

  SimpleLogPrinter({
    this.printTime = true,
    this.printLevel = true,
    this.lineLength = 80,
  });

  @override
  List<String> log(LogEvent event) {
    final messageStr = stringifyMessage(event.message);
    final errorStr = event.error != null ? '${event.error}' : '';
    final stackTraceStr = event.stackTrace != null ? '${event.stackTrace}' : '';

    final lines = <String>[];

    // 时间和级别行
    final buffer = StringBuffer();
    if (printTime) {
      final time = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(event.time);
      buffer.write('$time ');
    }
    if (printLevel) {
      final levelStr = _getLevelString(event.level);
      buffer.write('[$levelStr]');
    }
    lines.add(buffer.toString());

    // 消息内容
    if (messageStr.isNotEmpty) {
      lines.add(messageStr);
    }

    // 错误信息
    if (errorStr.isNotEmpty) {
      lines.add('Error: $errorStr');
    }

    // 堆栈信息
    if (stackTraceStr.isNotEmpty) {
      lines.add('StackTrace:');
      lines.add(stackTraceStr);
    }

    return lines;
  }

  String _getLevelString(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARNING';
      case Level.error:
        return 'ERROR';
      case Level.fatal:
        return 'FATAL';
      default:
        return 'UNKNOWN';
    }
  }

  String stringifyMessage(dynamic message) {
    if (message is Map || message is Iterable) {
      return message.toString();
    }
    return message.toString();
  }
}
