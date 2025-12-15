import 'package:dio/dio.dart';
import 'log_manager.dart';

/// Dio网络请求日志拦截器
/// 用于记录HTTP请求和响应的详细信息
class LogManagerInterceptor extends Interceptor {
  /// 是否打印请求头
  final bool requestHeader;

  /// 是否打印请求体
  final bool requestBody;

  /// 是否打印响应头
  final bool responseHeader;

  /// 是否打印响应体
  final bool responseBody;

  /// 是否打印错误信息
  final bool error;

  /// 是否使用紧凑模式（超长内容会被截断）
  final bool compact;

  /// 紧凑模式下的最大显示宽度
  final int maxWidth;

  LogManagerInterceptor({
    this.requestHeader = true,
    this.requestBody = true,
    this.responseHeader = true,
    this.responseBody = true,
    this.error = true,
    this.compact = true,
    this.maxWidth = 90,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logRequest(options);
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logResponse(response);
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (error) {
      _logError(err);
    }
    super.onError(err, handler);
  }

  void _logRequest(RequestOptions options) {
    final buffer = StringBuffer();
    buffer.write('\n${'=' * 35} START ${'=' * 35}\n');
    buffer.write(_addBorder('📤 REQUEST ${options.method} ${options.uri}'));
    buffer.write('\n');

    if (requestHeader && options.headers.isNotEmpty) {
      buffer.write(_addBorder('Headers:'));
      buffer.write('\n');
      options.headers.forEach((key, value) {
        buffer.write(_addBorder('  $key: $value'));
        buffer.write('\n');
      });
    }

    if (requestBody && options.data != null) {
      buffer.write(_addBorder('Body:'));
      buffer.write('\n');
      final data = _formatData(options.data);
      buffer.write(_formatBody(data));
      buffer.write('\n');
    }

    buffer.write('${'=' * 36} END ${'=' * 36}\n');
    LogManager.d(buffer.toString());
  }

  void _logResponse(Response response) {
    final buffer = StringBuffer();
    buffer.write('\n${'=' * 35} START ${'=' * 35}\n');
    buffer.write(_addBorder(
        '📥 RESPONSE ${response.statusCode} ${response.requestOptions.uri}'));
    buffer.write('\n');

    if (responseHeader && response.headers.map.isNotEmpty) {
      buffer.write(_addBorder('Headers:'));
      buffer.write('\n');
      response.headers.map.forEach((key, value) {
        buffer.write(_addBorder('  $key: ${value.join(', ')}'));
        buffer.write('\n');
      });
    }

    if (responseBody && response.data != null) {
      buffer.write(_addBorder('Body:'));
      buffer.write('\n');
      final data = _formatData(response.data);
      buffer.write(_formatBody(data));
      buffer.write('\n');
    }

    buffer.write('${'=' * 36} END ${'=' * 36}\n');
    LogManager.i(buffer.toString());
  }

  void _logError(DioException err) {
    final buffer = StringBuffer();
    buffer.write('\n${'=' * 35} START ${'=' * 35}\n');
    buffer.write(_addBorder('❌ ERROR ${err.type} ${err.requestOptions.uri}'));
    buffer.write('\n');
    buffer.write(_addBorder('Message: ${err.message}'));
    buffer.write('\n');

    if (err.response != null) {
      buffer.write(_addBorder('Status Code: ${err.response?.statusCode}'));
      buffer.write('\n');
      if (responseBody && err.response?.data != null) {
        buffer.write(_addBorder('Response:'));
        buffer.write('\n');
        final data = _formatData(err.response?.data);
        buffer.write(_formatBody(data));
        buffer.write('\n');
      }
    }

    buffer.write('${'=' * 36} END ${'=' * 36}\n');
    LogManager.e(buffer.toString(), error: err);
  }

  String _formatData(dynamic data) {
    if (data == null) return 'null';
    if (data is Map || data is List) {
      return data.toString();
    }
    return data.toString();
  }

  /// 给每一行添加左边框
  String _addBorder(String text, {String prefix = '║ '}) {
    return text.split('\n').map((line) => '$prefix$line').join('\n');
  }

  /// 格式化并添加边框的 Body 内容（处理超长内容）
  String _formatBody(String data, {int indent = 2}) {
    final prefix = ' ' * indent;
    final lines = <String>[];

    // 如果内容很长，按合理长度分行
    const maxLineLength = 100;
    if (data.length > maxLineLength) {
      for (int i = 0; i < data.length; i += maxLineLength) {
        final end =
            (i + maxLineLength < data.length) ? i + maxLineLength : data.length;
        lines.add('$prefix${data.substring(i, end)}');
      }
    } else {
      lines.add('$prefix$data');
    }

    return lines.map((line) => _addBorder(line)).join('\n');
  }
}
