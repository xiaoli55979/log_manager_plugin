## 1.0.3

* **Breaking Change**: Renamed `LogUtil` to `LogManager` to avoid naming conflicts
* **Breaking Change**: Renamed `LogConfig` to `LogManagerConfig` to avoid naming conflicts
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
