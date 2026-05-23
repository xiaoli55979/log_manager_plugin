import 'dart:convert';
import 'dart:typed_data';
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
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    // ResponseBody 流式数据先 drain 再打印,同时用 fromBytes 重建塞回去,业务还能继续读
    await _drainStreamIfNeeded(response);
    _logResponse(response);
    handler.next(response);
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
    buffer.write('\n${'=' * 15} START ${'=' * 15}\n');
    buffer.write(_addBorder('📤 REQUEST ${options.method} ${options.uri}'));
    buffer.write('\n');
    // encryption_handler 加密 path 时把明文存到了 extra,这里同步显示,定位接口用
    final originalPath = options.extra['_originalPath'];
    if (originalPath is String && originalPath.isNotEmpty) {
      buffer.write(_addBorder('🔓 Original: $originalPath'));
      buffer.write('\n');
    }

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
      // walnut_cobalt_creek 把加密前的原始 Map 备份在 extra['__originalData']
      final rawData = options.extra['__originalData'] ?? options.data;
      final data = _formatData(rawData);
      buffer.write(_formatBody(data));
      buffer.write('\n');
    }

    buffer.write('${'=' * 16} END ${'=' * 16}\n');
    LogManager.d(buffer.toString());
  }

  void _logResponse(Response response) {
    final buffer = StringBuffer();
    buffer.write('\n${'=' * 15} START ${'=' * 15}\n');
    buffer.write(_addBorder(
        '📥 RESPONSE ${response.statusCode} ${response.requestOptions.uri}'));
    buffer.write('\n');
    final originalPath = response.requestOptions.extra['_originalPath'];
    if (originalPath is String && originalPath.isNotEmpty) {
      buffer.write(_addBorder('🔓 Original: $originalPath'));
      buffer.write('\n');
    }

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
      // drain 出来的字符串优先用,避免 ResponseBody.toString 还是 "Instance of"
      final decoded = response.extra['__log_decoded_body'];
      final data = decoded is String && decoded.isNotEmpty
          ? _tryFormatAsJson(decoded)
          : _formatData(response.data);
      buffer.write(_formatBody(data));
      buffer.write('\n');
    }

    buffer.write('${'=' * 16} END ${'=' * 16}\n');
    LogManager.i(buffer.toString());
  }

  void _logError(DioException err) {
    final buffer = StringBuffer();
    buffer.write('\n${'=' * 15} START ${'=' * 15}\n');
    buffer.write(_addBorder('❌ ERROR ${err.type} ${err.requestOptions.uri}'));
    buffer.write('\n');
    final originalPath = err.requestOptions.extra['_originalPath'];
    if (originalPath is String && originalPath.isNotEmpty) {
      buffer.write(_addBorder('🔓 Original: $originalPath'));
      buffer.write('\n');
    }
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

    buffer.write('${'=' * 16} END ${'=' * 16}\n');
    LogManager.e(buffer.toString(), error: err);
  }

  String _formatData(dynamic data) {
    if (data == null) return 'null';

    // 先检查 toString 是否返回 "Instance of"，这通常意味着对象没有重写 toString
    final str = data.toString();
    if (str.contains('Instance of')) {
      // 尝试获取对象的实际内容
      try {
        // 如果是 ResponseBody 类型，尝试获取其 data 属性
        if (data.runtimeType.toString().contains('ResponseBody')) {
          try {
            // 尝试访问 data 属性
            final dataValue = (data as dynamic).data;
            if (dataValue != null && dataValue.toString() != str) {
              return _formatData(dataValue); // 递归处理实际数据
            }
          } catch (e) {
            // 忽略错误，继续尝试其他方法
          }
          
          // 尝试访问 stream 或 bytes
          try {
            final stream = (data as dynamic).stream;
            if (stream != null) {
              return 'ResponseBody (流数据，无法直接显示)';
            }
          } catch (e) {
            // 忽略错误
          }
          
          try {
            final bytes = (data as dynamic).bytes;
            if (bytes != null && bytes is List<int>) {
              // 尝试将字节转换为字符串
              try {
                final stringData = utf8.decode(bytes);
                return _tryFormatAsJson(stringData);
              } catch (e) {
                return 'ResponseBody (二进制数据，${bytes.length} 字节)';
              }
            }
          } catch (e) {
            // 忽略错误
          }
          
          return 'ResponseBody (无法解析内容)';
        }
        
        // 对于其他 "Instance of" 类型，尝试 toJson 方法
        try {
          final jsonData = (data as dynamic).toJson();
          if (jsonData != null) {
            return _formatData(jsonData);
          }
        } catch (e) {
          // 忽略错误
        }
        
        // 如果都失败了，返回类型信息
        return '${data.runtimeType} (无法格式化)';
      } catch (e) {
        return '${data.runtimeType} (处理失败: $e)';
      }
    }

    // 加密后的 body 是字节数组,按行打成几十行没意义,只留长度摘要
    if (data is Uint8List) {
      return '<binary ${data.length} bytes>';
    }
    if (data is List && data.isNotEmpty && data.every((e) => e is int)) {
      return '<binary ${data.length} bytes>';
    }

    // 如果是Map或List，尝试格式化为JSON
    if (data is Map || data is List) {
      try {
        // 使用JsonEncoder美化JSON输出，缩进2个空格
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(data);
      } catch (e) {
        // 如果JSON编码失败，回退到toString
        return str;
      }
    }

    // 如果是字符串，尝试解析为JSON并美化
    if (data is String) {
      return _tryFormatAsJson(data);
    }

    return str;
  }

  /// ResponseBody 流式响应在拦截器阶段还是 stream,直接 toString 看不到内容
  /// 这里把 stream 收完转 bytes,然后用 fromBytes 重建 response.data,下游订阅照常拿到完整数据
  ///
  /// 注意:server-streaming(responseType=stream,如 flagd EventStream 长连接)不能 drain,
  /// stream.toList() 会一直 hang 等 close,handler.next 永远不调用业务收不到任何消息
  Future<void> _drainStreamIfNeeded(Response response) async {
    final data = response.data;
    if (data == null) return;
    if (data.runtimeType.toString() != 'ResponseBody') return;
    // 业务侧主动声明的 stream 响应直接放过,避免破坏长连接
    if (response.requestOptions.responseType == ResponseType.stream) return;
    try {
      final stream = (data as dynamic).stream as Stream<List<int>>?;
      if (stream == null) return;
      final chunks = await stream.toList();
      final bytes = <int>[];
      for (final c in chunks) {
        bytes.addAll(c);
      }
      response.data = ResponseBody.fromBytes(
        bytes,
        (data as dynamic).statusCode as int,
        headers: ((data as dynamic).headers as Map<String, List<String>>?) ?? const {},
        statusMessage: (data as dynamic).statusMessage as String?,
        isRedirect: ((data as dynamic).isRedirect as bool?) ?? false,
      );
      // 在 response.extra 里塞一份解码后的字符串,_formatData 优先读它
      try {
        response.extra['__log_decoded_body'] = utf8.decode(bytes);
      } catch (_) {
        response.extra['__log_decoded_body'] = '<binary ${bytes.length} bytes>';
      }
    } catch (e) {
      // drain 失败就放弃,日志走原路径
    }
  }

  /// 尝试将字符串格式化为JSON
  String _tryFormatAsJson(String data) {
    if (data.isEmpty) return data;
    
    try {
      final decoded = jsonDecode(data);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (e) {
      // 如果不是JSON字符串，直接返回
      return data;
    }
  }

  /// 给每一行添加左边框
  String _addBorder(String text, {String prefix = '║ '}) {
    return text.split('\n').map((line) => '$prefix$line').join('\n');
  }

  /// 格式化并添加边框的 Body 内容（处理超长内容）
  String _formatBody(String data) {
    final lines = <String>[];

    // 按行分割（JSON格式化后已经是多行的）
    final dataLines = data.split('\n');

    for (var line in dataLines) {
      // 每行添加边框，保持原有的缩进
      lines.add(_addBorder(line));
    }

    return lines.join('\n');
  }
}
