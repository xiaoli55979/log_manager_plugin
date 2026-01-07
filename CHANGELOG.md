# Changelog

## 1.0.7

* **Improvement**: 优化日志分隔线长度，缩短1/3避免换行问题
  - START 和 END 分隔线从35/36个等号缩短到23/24个等号
* **Improvement**: 改进API接口Body格式化显示
  - JSON数据自动美化，带缩进显示
  - 支持Map、List和JSON字符串的格式化
* **Fix**: 修复日志输出被打断的问题
  - 将整个日志块一次性输出，避免多线程环境下被其他日志打断
  - 改进分段逻辑，尽量保持行的完整性
* **Fix**: 修复ResponseBody类型显示为"Instance of 'ResponseBody'"的问题
  - 自动检测并解析ResponseBody的实际内容
  - 支持字节数组转换为UTF-8字符串
  - 提供更友好的错误提示信息

## 1.0.6

* **Fix**: 修复 Release 模式下日志文件未记录的问题
  - 修复 `flush: false` 导致 Release 模式下日志未写入磁盘的问题
  - Release 模式使用 `flush: true` 确保日志数据写入磁盘
  - 添加文件初始化失败时的自动重试机制
  - 增强错误处理和诊断信息
  - 确保当 `enableFileLog: true` 时，所有日志都能正确写入文件

## 1.0.5

* **Performance**: 默认 `enableFileLog` 改为 `kDebugMode`（仅在 Debug 模式下写入日志）
* 通过默认禁用文件日志提升 Release 模式性能
* 用户仍可通过设置 `enableFileLog: true` 在 Release 模式下启用文件日志

## 1.0.4

* **New Feature**: 压缩日志后自动弹出系统分享对话框，可直接分享压缩文件
* **New Feature**: 按日期查看日志页面增加日志文件分享功能，可分享单个日志文件
* **New Feature**: 添加查看压缩文件入口，可选择指定压缩文件进行分享
* **New Feature**: 每次应用启动都创建新的日志文件，避免单日日志文件过长
* **Improvement**: 支持 iPad 分享功能，添加 `sharePositionOrigin` 参数支持
* **Improvement**: 优化选中状态 UI，使用淡蓝色背景，文字清晰可见
* **Improvement**: 修复日志文件读取 UTF-8 解码错误，支持容错处理
* **Improvement**: 日志内容查看页面标题颜色设置为黑色，提高可读性
* **Performance**: 优化文件日志写入，防止 UI 阻塞
  - 文件写入从同步改为异步
  - 移除强制缓冲区刷新以提升性能
* **Improvement**: 优化 Dio 拦截器长内容日志格式（自动换行带边框）
* **Dependency**: 添加 `share_plus: ^11.0.0` 依赖包

## 1.0.3

* **Breaking Change**: `LogUtil` 重命名为 `LogManager`，避免命名冲突
* **Breaking Change**: `LogConfig` 重命名为 `LogManagerConfig`，避免命名冲突
* **Improvement**: 优化 Dio 拦截器日志格式
  - START 前和 END 后添加空行，提高可读性
  - 所有日志行（包括长文本换行）添加左边框（║）
* **Fix**: 修复控制台输出长日志截断问题（自动分割长字符串）
* **Docs**: 完善多插件使用场景文档
* **Docs**: 添加日志级别过滤说明

### 迁移指南

```dart
// 之前
await LogUtil.instance.init(const LogConfig(...));
LogUtil.d('message');

// 之后
await LogManager.instance.init(const LogManagerConfig(...));
LogManager.d('message');
```

## 1.0.0

* 首次发布
* 支持控制台和文件日志
* Debug/Release 模式配置
* Dio 网络请求拦截器
* 自动日志文件轮转（默认每个文件 10MB）
* 自动清理旧日志（可配置保留天数）
* 日志文件压缩
* 内置日志查看器 UI，三种模式：
  - 按日期查看（推荐）
  - 增强查看器（语法高亮）
  - 基础查看器
* 日志上传支持：
  - 文件上传（multipart/form-data）
  - 字符串批量上传（JSON 格式）
* 按日期管理日志
* 日志统计
* 可配置上传行为
* 支持 iOS 和 Android
