import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:log_manager_plugin/log_manager_plugin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统
  await LogUtil.instance.init(
    const LogConfig(
      enabled: true,
      enableConsoleInDebug: true,
      enableConsoleInRelease: false,
      enableFileLog: true,
      maxFileSize: 10 * 1024 * 1024, // 10MB
      maxRetentionDays: 7, // 保留7天
      logLevel: Level.debug,
      logDirectory: 'logs', 
    ),
  );


  // 方式1：文件上传方式
  LogReporter.instance.setUploadCallback((zipFile) async {
    // 这里实现你的上报逻辑
    // 例如：上传到服务器
    try {
      // 示例代码（实际使用时取消注释）：
      /*
      final dio = Dio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          zipFile.path,
          filename: 'logs.zip',
        ),
        'deviceId': 'your_device_id',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // 替换为你的上报接口
      final response = await dio.post('https://your-api.com/upload-logs', data: formData);
      return response.statusCode == 200;
      */

      // 示例：模拟上报成功
      await Future.delayed(const Duration(seconds: 1));
      LogUtil.i('模拟上报成功（实际使用时请实现真实的上报逻辑）');
      return true;
    } catch (e) {
      LogUtil.e('上报失败', error: e);
      return false;
    }
  });

  // 方式2：字符串上传方式（分批上传）
  LogReporter.instance.setUploadStringCallback((batches) async {
    try {
      // 示例：分批上传日志内容
      /*
      final dio = Dio();
      
      for (final batch in batches) {
        final response = await dio.post(
          'https://your-api.com/api/logs/upload-string',
          data: {
            'batchIndex': batch.batchIndex,
            'totalBatches': batch.totalBatches,
            'content': batch.content,
            'fileName': batch.fileName,
            'date': batch.date,
            'deviceId': 'your_device_id',
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        
        if (response.statusCode != 200) {
          return false;
        }
      }
      
      return true;
      */

      // 模拟分批上传
      LogUtil.i('开始分批上传 ${batches.length} 批日志');
      for (final batch in batches) {
        await Future.delayed(const Duration(milliseconds: 100));
        LogUtil.d(
            '上传批次 ${batch.batchIndex}/${batch.totalBatches} - ${batch.fileName} (${batch.content.length} 字符)');
      }
      LogUtil.i('所有批次上传完成');
      return true;
    } catch (e) {
      LogUtil.e('字符串上报失败', error: e);
      return false;
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '日志管理插件示例',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Dio _dio;
  String _logInfo = '';

  @override
  void initState() {
    super.initState();
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://jsonplaceholder.typicode.com',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 3),
    ));

    // 添加日志拦截器
    _dio.interceptors.add(
      LogManagerInterceptor(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: true,
        compact: true,
        error: true,
      ),
    );
  }

  Future<void> _testApiCall() async {
    try {
      LogUtil.i('开始测试API调用');
      final response = await _dio.get('/posts/1');
      LogUtil.i('API调用成功: ${response.statusCode}');
    } catch (e) {
      LogUtil.e('API调用失败', error: e);
    }
  }

  Future<void> _testLogs() async {
    LogUtil.v('这是一条Verbose日志');
    LogUtil.d('这是一条Debug日志');
    LogUtil.i('这是一条Info日志');
    LogUtil.w('这是一条Warning日志');
    LogUtil.e('这是一条Error日志');
    LogUtil.f('这是一条Fatal日志');

    setState(() {
      _logInfo = '日志已输出，请查看控制台';
    });
  }

  Future<void> _getLogFiles() async {
    final files = await LogUtil.getAllLogFiles();
    setState(() {
      _logInfo = '日志文件数量: ${files.length}\n';
      for (var file in files) {
        final fileName = file.path.split('/').last;
        final size = file.lengthSync();
        _logInfo += '$fileName (${(size / 1024).toStringAsFixed(2)} KB)\n';
      }
    });
  }

  void _openLogViewer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogViewerPage(),
      ),
    );
  }

  void _openEnhancedLogViewer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EnhancedLogViewer(),
      ),
    );
  }

  void _openLogViewerByDate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogViewerByDate(),
      ),
    );
  }

  Future<void> _uploadLogs() async {
    setState(() {
      _logInfo = '正在上报日志（文件方式）...';
    });

    final success = await LogReporter.instance.uploadLogs();

    setState(() {
      if (success) {
        _logInfo = '日志上报成功！';
      } else {
        _logInfo = '日志上报失败，请检查网络或回调设置';
      }
    });
  }

  Future<void> _uploadLogsAsString() async {
    setState(() {
      _logInfo = '正在上报日志（字符串方式）...';
    });

    final success = await LogReporter.instance.uploadLogsAsString(
      maxBatchSize: 50 * 1024, // 每批50KB
    );

    setState(() {
      if (success) {
        _logInfo = '日志分批上报成功！';
      } else {
        _logInfo = '日志分批上报失败';
      }
    });
  }

  Future<void> _compressLogs() async {
    final zipFile = await LogUtil.compressLogs();
    if (zipFile != null) {
      final size = zipFile.lengthSync();
      setState(() {
        _logInfo =
            '日志已压缩\n文件: ${zipFile.path}\n大小: ${(size / 1024).toStringAsFixed(2)} KB';
      });
      LogUtil.i('日志压缩成功: ${zipFile.path}');
    } else {
      setState(() {
        _logInfo = '日志压缩失败';
      });
    }
  }

  Future<void> _clearLogs() async {
    await LogUtil.clearAllLogs();
    setState(() {
      _logInfo = '所有日志已清空';
    });
    LogUtil.i('日志已清空');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志管理插件示例'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '日志功能测试',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openLogViewerByDate,
              icon: const Icon(Icons.calendar_today),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: const Text('按日期查看日志（推荐）'),
            ),
            const SizedBox(height: 10),
            // OutlinedButton.icon(
            //   onPressed: _openEnhancedLogViewer,
            //   icon: const Icon(Icons.folder_open),
            //   label: const Text('增强版日志查看器'),
            // ),
            // const SizedBox(height: 10),
            // OutlinedButton.icon(
            //   onPressed: _openLogViewer,
            //   icon: const Icon(Icons.description),
            //   label: const Text('基础版日志查看器'),
            // ),
            // const Divider(height: 32),
            ElevatedButton(
              onPressed: _testLogs,
              child: const Text('测试各级别日志'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _testApiCall,
              child: const Text('测试API日志拦截'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _getLogFiles,
              child: const Text('查看日志文件'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _compressLogs,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('压缩日志文件'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _uploadLogs,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('上报日志（文件）'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _uploadLogsAsString,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('上报日志（字符串分批）'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _clearLogs,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('清空所有日志'),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _logInfo.isEmpty ? '点击按钮测试功能' : _logInfo,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '日志目录: ${LogUtil.logDirectoryPath ?? "未初始化"}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
