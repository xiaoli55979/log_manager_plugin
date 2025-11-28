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
    buffer.write('${'=' * 35} START ${'=' * 35}\n');
    buffer.write('📤 REQUEST ${options.method} ${options.uri}\n');

    if (requestHeader && options.headers.isNotEmpty) {
      buffer.write('Headers:\n');
      options.headers.forEach((key, value) {
        buffer.write('  $key: $value\n');
      });
    }

    if (requestBody && options.data != null) {
      buffer.write('Body:\n');
      final data = _formatData(options.data);
      buffer.write('  $data\n');
    }

    buffer.write('\n${'=' * 36} END ${'=' * 36}');
    LogManager.d(buffer.toString());
  }

  void _logResponse(Response response) {
    final buffer = StringBuffer();
    buffer.write('${'=' * 35} START ${'=' * 35}\n');
    buffer.write(
        '📥 RESPONSE ${response.statusCode} ${response.requestOptions.uri}\n');

    if (responseHeader && response.headers.map.isNotEmpty) {
      buffer.write('Headers:\n');
      response.headers.map.forEach((key, value) {
        buffer.write('  $key: ${value.join(', ')}\n');
      });
    }

    if (responseBody && response.data != null) {
      buffer.write('Body:\n');
      final data = _formatData(response.data);
      if (compact && data.length > maxWidth) {
        buffer.write('  ${data.substring(0, maxWidth)}...\n');
      } else {
        buffer.write('  $data\n');
      }
    }

    buffer.write('\n${'=' * 36} END ${'=' * 36}');
    LogManager.i(buffer.toString());
  }

  void _logError(DioException err) {
    final buffer = StringBuffer();
    buffer.write('${'=' * 35} START ${'=' * 35}\n');
    buffer.write('❌ ERROR ${err.type} ${err.requestOptions.uri}\n');
    buffer.write('Message: ${err.message}\n');

    if (err.response != null) {
      buffer.write('Status Code: ${err.response?.statusCode}\n');
      if (responseBody && err.response?.data != null) {
        buffer.write('Response:\n');
        final data = _formatData(err.response?.data);
        buffer.write('  $data\n');
      }
    }

    buffer.write('\n${'=' * 36} END ${'=' * 36}');
    LogManager.e(buffer.toString(), error: err);
  }

  String _formatData(dynamic data) {
    if (data == null) return 'null';
    if (data is Map || data is List) {
      return data.toString();
    }
    return data.toString();
  }
}
