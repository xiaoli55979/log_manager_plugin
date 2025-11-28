# log_manager_plugin

Flutter日志管理插件，支持控制台输出、文件存储、日志查看、压缩上报等功能。

## 目录

- [功能](#功能)
- [安装](#安装)
- [快速开始](#快速开始)
  - [初始化](#初始化)
  - [日志输出](#日志输出)
  - [Dio拦截器](#dio拦截器)
- [日志查看](#日志查看)
- [文件管理](#文件管理)
- [高级用法](#高级用法)
- [日志上报](#日志上报)
- [配置参数](#配置参数)
- [日志级别](#日志级别)
- [文件管理策略](#文件管理策略)
- [完整使用示例](#完整使用示例)

## 功能

- 控制台日志输出（基于logger）
- 文件日志存储，按天管理
- Debug/Release模式分别配置
- Dio网络请求日志拦截
- 日志文件自动分块（默认10MB）
- 自动清理过期日志（按天数）
- 日志文件压缩
- 内置日志查看器UI
- 日志上报（支持文件/字符串两种方式）

## 安装

```yaml
dependencies:
  log_manager_plugin:
    git:
      url: your_git_url
```

## 快速开始

### 初始化

```dart
import 'package:log_manager_plugin/log_manager_plugin.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await LogUtil.instance.init(
    const LogConfig(
      enabled: true,
      enableConsoleInDebug: true,
      enableConsoleInRelease: false,
      enableFileLog: true,
      maxFileSize: 10 * 1024 * 1024,   // 10MB
      maxRetentionDays: 7,              // 保留7天
      logLevel: Level.debug,
      logDirectory: 'logs',
      deleteAfterUpload: true,          // 上报后删除压缩文件
      maxBatchSize: 100 * 1024,         // 字符串上报每批100KB
    ),
  );
  
  runApp(const MyApp());
}
```

### 日志输出

```dart
LogUtil.v('verbose');
LogUtil.d('debug');
LogUtil.i('info');
LogUtil.w('warning');
LogUtil.e('error', error: e, stackTrace: stackTrace);
LogUtil.f('fatal');
```

### Dio拦截器

```dart
final dio = Dio();
dio.interceptors.add(
  LogManagerInterceptor(
    requestHeader: true,      // 打印请求头
    requestBody: true,         // 打印请求体
    responseHeader: true,      // 打印响应头
    responseBody: true,        // 打印响应体
    error: true,               // 打印错误信息
    compact: true,             // 紧凑模式（超长内容截断）
    maxWidth: 90,              // 紧凑模式最大宽度
  ),
);
```

## 日志查看

### 按日期查看（推荐）

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const LogViewerByDate()),
);
```

功能：
- 按日期分组
- 统计信息
- 多选操作
- 压缩/删除
- 查看内容

### 增强版查看器

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const EnhancedLogViewer()),
);
```

功能：
- 日志级别着色
- 搜索过滤
- 级别过滤
- 复制内容

### 基础版查看器

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const LogViewerPage()),
);
```

## 文件管理

### 基础操作

```dart
// 获取所有日志文件
final files = await LogUtil.getAllLogFiles();

// 获取日志目录路径
final path = LogUtil.logDirectoryPath;

// 清空所有日志
await LogUtil.clearAllLogs();
```

### 按日期管理

```dart
// 按日期分组获取日志文件
final grouped = await LogFileManager.instance.getLogFilesByDate();
// 返回: {'20231128': [file1, file2], '20231127': [file3]}

// 删除指定日期的日志
await LogFileManager.instance.deleteLogsByDate('20231128');
```

### 日志压缩

```dart
// 压缩所有日志
final zipFile = await LogUtil.compressLogs();

// 压缩指定日期的日志
final zipFile = await LogFileManager.instance.compressLogsByDate('20231128');

// 压缩指定文件
final files = [file1, file2];
final zipFile = await LogFileManager.instance.compressSpecificLogs(files);
```

### 日志统计

```dart
// 获取统计信息
final stats = await LogFileManager.instance.getStatistics();
print('总文件数: ${stats.totalFiles}');
print('总大小: ${stats.totalSize}');
print('日期数: ${stats.dateCount}');
print('最早日期: ${stats.earliestDate}');
print('最新日期: ${stats.latestDate}');
```

### 清理旧格式日志

如果从旧版本升级，可以清理旧格式的日志文件：

```dart
await LogFileManager.instance.cleanLegacyLogFiles();
```

## 高级用法

### 运行时更新配置

```dart
// 动态修改配置
await LogUtil.instance.updateConfig(
  LogConfig(
    enableConsoleInRelease: true,  // 临时开启Release日志
    logLevel: Level.trace,          // 调整日志级别
  ),
);
```

### 获取当前配置

```dart
final config = LogUtil.config;
print('当前日志级别: ${config.logLevel}');
print('文件日志: ${config.enableFileLog}');
```

## 日志上报

### 方式1：文件上传

适合支持 multipart/form-data 的接口。

```dart
// 设置回调
LogReporter.instance.setUploadCallback((zipFile) async {
  try {
    final dio = Dio();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(zipFile.path, filename: 'logs.zip'),
      'deviceId': 'xxx',
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    final response = await dio.post('https://your-api.com/upload', data: formData);
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
});

// 上报所有日志
await LogReporter.instance.uploadLogs();

// 上报指定日期
await LogReporter.instance.uploadLogsByDate('20231128');

// 自定义参数
await LogReporter.instance.uploadLogs(
  deleteAfterUpload: false,  // 保留压缩文件
);
```

### 方式2：字符串分批上传

适合只支持 JSON 格式的接口。

```dart
// 设置回调
LogReporter.instance.setUploadStringCallback((batches) async {
  try {
    final dio = Dio();
    for (final batch in batches) {
      await dio.post('https://your-api.com/upload-string', data: {
        'batchIndex': batch.batchIndex,
        'totalBatches': batch.totalBatches,
        'content': batch.content,
        'fileName': batch.fileName,
        'date': batch.date,
      });
    }
    return true;
  } catch (e) {
    return false;
  }
});

// 上报所有日志
await LogReporter.instance.uploadLogsAsString();

// 上报指定日期
await LogReporter.instance.uploadLogsByDateAsString('20231128');

// 自定义批次大小
await LogReporter.instance.uploadLogsAsString(
  maxBatchSize: 50 * 1024,  // 每批50KB
);
```

### 配置优先级

上报参数的优先级：**方法参数 > 配置项 > 默认值**

```dart
// 在初始化时统一配置
await LogUtil.instance.init(
  const LogConfig(
    deleteAfterUpload: false,  // 默认保留压缩文件
    maxBatchSize: 200 * 1024,  // 默认每批200KB
  ),
);

// 调用时可以临时覆盖
await LogReporter.instance.uploadLogs(
  deleteAfterUpload: true,  // 这次删除
);
```

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| enabled | bool | true | 是否启用 |
| enableConsoleInDebug | bool | true | Debug模式控制台输出 |
| enableConsoleInRelease | bool | false | Release模式控制台输出 |
| enableFileLog | bool | true | 文件日志 |
| maxFileSize | int | 10MB | 单文件最大大小 |
| maxRetentionDays | int | 7 | 保留天数 |
| logLevel | Level | debug | 日志级别 |
| logDirectory | String | 'logs' | 日志目录 |
| deleteAfterUpload | bool | true | 上报成功后删除压缩文件 |
| maxBatchSize | int | 100KB | 字符串上报每批大小 |

## 日志级别

- `Level.trace` - 追踪
- `Level.debug` - 调试
- `Level.info` - 信息
- `Level.warning` - 警告
- `Level.error` - 错误
- `Level.fatal` - 致命

## 文件管理策略

- 按天创建日志文件：`log_20231128_001.txt`
- 单文件超过限制自动创建新文件：`log_20231128_002.txt`
- 自动删除超过保留天数的文件
- 应用启动和跨天时自动清理

## 完整使用示例

```dart
import 'package:flutter/material.dart';
import 'package:log_manager_plugin/log_manager_plugin.dart';
import 'package:dio/dio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 初始化日志系统
  await LogUtil.instance.init(
    const LogConfig(
      enabled: true,
      enableConsoleInDebug: true,
      enableConsoleInRelease: false,
      enableFileLog: true,
      maxFileSize: 10 * 1024 * 1024,
      maxRetentionDays: 7,
      logLevel: Level.debug,
      deleteAfterUpload: true,
      maxBatchSize: 100 * 1024,
    ),
  );
  
  // 2. 配置Dio拦截器
  final dio = Dio();
  dio.interceptors.add(
    LogManagerInterceptor(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      compact: true,
    ),
  );
  
  // 3. 配置日志上报
  LogReporter.instance.setUploadCallback((zipFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(zipFile.path),
      });
      final response = await dio.post('https://api.example.com/logs', data: formData);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  });
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('日志管理示例')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  // 输出各级别日志
                  LogUtil.d('这是调试日志');
                  LogUtil.i('这是信息日志');
                  LogUtil.w('这是警告日志');
                  LogUtil.e('这是错误日志');
                },
                child: const Text('输出日志'),
              ),
              ElevatedButton(
                onPressed: () {
                  // 打开日志查看器
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LogViewerByDate(),
                    ),
                  );
                },
                child: const Text('查看日志'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // 上报日志
                  final success = await LogReporter.instance.uploadLogs();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? '上报成功' : '上报失败')),
                  );
                },
                child: const Text('上报日志'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## 更多示例

查看 `example` 目录获取完整示例代码。

## 常见问题

### 1. 日志文件存储在哪里？

- **iOS**: `Application Support/logs/`
- **Android**: `应用数据目录/logs/`

可以通过 `LogUtil.logDirectoryPath` 获取完整路径。

### 2. 如何在Release模式下查看日志？

```dart
await LogUtil.instance.init(
  const LogConfig(
    enableConsoleInRelease: true,  // 开启Release控制台输出
  ),
);
```

### 3. 日志文件太大怎么办？

调整配置参数：

```dart
const LogConfig(
  maxFileSize: 5 * 1024 * 1024,  // 减小单文件大小到5MB
  maxRetentionDays: 3,            // 只保留3天
)
```

### 4. 如何只上报错误日志？

可以在上报前筛选文件，或者在应用层面控制日志级别：

```dart
const LogConfig(
  logLevel: Level.error,  // 只记录error及以上级别
)
```

### 5. 上报失败怎么办？

日志文件会保留在本地，可以稍后重试：

```dart
final success = await LogReporter.instance.uploadLogs(
  deleteAfterUpload: false,  // 失败时不删除
);
```

## 注意事项

1. **初始化时机**：必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后初始化
2. **文件权限**：iOS/Android 会自动处理，无需额外配置
3. **性能影响**：文件写入是异步的，不会阻塞主线程
4. **日志安全**：上报前建议加密敏感信息
5. **网络请求**：Dio拦截器会记录完整请求响应，注意数据量

## License

MIT
