## 1.0.4

* **New Feature**: 压缩日志后自动弹出系统分享对话框，可直接分享压缩文件
* **New Feature**: 按日期查看日志页面增加日志文件分享功能，可分享单个日志文件
* **New Feature**: 添加查看压缩文件入口，可选择指定压缩文件进行分享
* **New Feature**: 每次应用启动都创建新的日志文件，避免单日日志文件过长
* **Improvement**: 支持iPad分享功能，添加`sharePositionOrigin`参数支持
* **Improvement**: 优化选中状态UI，使用淡蓝色背景，文字清晰可见
* **Improvement**: 修复日志文件读取UTF-8解码错误，支持容错处理
* **Improvement**: 日志内容查看页面标题颜色设置为黑色，提高可读性
* **Dependency**: 添加`share_plus: ^11.0.0`依赖包

## 1.0.4

* **Performance Improvement**: Optimized file logging to prevent UI blocking
  - Changed file writing from synchronous to asynchronous
  - Removed forced buffer flushing for better performance
  - File logging now defaults to Debug mode only (`enableFileLog = kDebugMode`)
* Improved Dio interceptor log format for long content (auto line-wrapping with borders)
* Updated documentation for performance considerations

## 1.0.4

* **Performance Improvement**: Changed default file logging to Debug mode only (`enableFileLog = kDebugMode`)
* Improved app performance in Release mode by disabling file logging by default
* Users can still enable file logging in Release mode by setting `enableFileLog: true`

## 1.0.3

* **Breaking Change**: Renamed `LogUtil` to `LogManager` to avoid naming conflicts
* **Breaking Change**: Renamed `LogConfig` to `LogManagerConfig` to avoid naming conflicts
* Improved Dio interceptor log format:
  - Add newline before START and after END for better readability
  - Add left border (║) to all log lines including wrapped long lines
* Fixed long log truncation issue in console output (auto-split long strings)
* Improved documentation for multi-plugin usage scenarios
* Added log level filtering explanation

### Migration Guide

```dart
// Before
await LogUtil.instance.init(const LogConfig(...));
LogUtil.d('message');

// After
await LogManager.instance.init(const LogManagerConfig(...));
LogManager.d('message');
```

## 1.0.0

* Initial release
* Console and file logging support
* Debug/Release mode configuration
* Dio network request interceptor
* Automatic log file rotation (default 10MB per file)
* Automatic cleanup of old logs (configurable retention days)
* Log file compression
* Built-in log viewer UI with three modes:
  - Date-based viewer (recommended)
  - Enhanced viewer with syntax highlighting
  - Basic viewer
* Log upload support:
  - File upload (multipart/form-data)
  - String batch upload (JSON format)
* Date-based log management
* Log statistics
* Configurable upload behavior
* Support for iOS and Android
