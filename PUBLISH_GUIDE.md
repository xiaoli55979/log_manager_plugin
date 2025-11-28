# 发布到 pub.dev 指南

## 前置准备

### 1. 确保你有 pub.dev 账号
访问 https://pub.dev 并使用 Google 账号登录

### 2. 验证本地环境
```bash
flutter doctor
dart --version
```

## 发布步骤

### 1. 最终检查
```bash
# 运行测试（如果有）
flutter test

# 分析代码
flutter analyze

# 格式化代码
dart format .

# 干运行发布（检查是否有问题）
flutter pub publish --dry-run
```

### 2. 提交代码到 GitHub
```bash
git add .
git commit -m "Release version 1.0.0"
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

### 3. 发布到 pub.dev
```bash
flutter pub publish
```

系统会提示：
- 显示将要发布的文件列表
- 要求确认发布
- 可能需要在浏览器中授权

输入 `y` 确认发布。

### 4. 验证发布
访问 https://pub.dev/packages/log_manager_plugin 查看你的包

## 后续版本发布

### 1. 更新版本号
编辑 `pubspec.yaml`：
```yaml
version: 1.0.1  # 或 1.1.0, 2.0.0
```

版本号规则（语义化版本）：
- **主版本号**（1.x.x）：不兼容的 API 修改
- **次版本号**（x.1.x）：向下兼容的功能性新增
- **修订号**（x.x.1）：向下兼容的问题修正

### 2. 更新 CHANGELOG.md
```markdown
## 1.0.1

* Fixed bug in log compression
* Improved performance

## 1.0.0

* Initial release
```

### 3. 重复发布步骤

## 常见问题

### Q: 发布失败，提示包名已存在
A: 包名在 pub.dev 上是唯一的，需要修改 `pubspec.yaml` 中的 `name` 字段

### Q: 如何撤回已发布的版本？
A: pub.dev 不支持删除已发布的版本，但可以标记为 discontinued：
```bash
dart pub discontinue log_manager_plugin
```

### Q: 如何更新包的描述或文档？
A: 修改 `pubspec.yaml` 和 `README.md`，然后发布新版本

### Q: 发布后多久能在 pub.dev 上看到？
A: 通常几分钟内就能看到，但完整的分析和评分可能需要几小时

## 最佳实践

1. **遵循语义化版本**：让用户清楚了解更新的影响
2. **维护 CHANGELOG**：记录每个版本的变更
3. **完善文档**：README 要清晰易懂
4. **添加示例**：example 目录提供完整示例
5. **响应问题**：及时回复 GitHub Issues
6. **持续更新**：定期修复 bug 和添加新功能

## 包的评分标准

pub.dev 会根据以下标准评分：
- ✅ 遵循 Dart 文件约定
- ✅ 提供文档
- ✅ 支持多平台
- ✅ 通过静态分析
- ✅ 支持最新的 Dart SDK
- ✅ 提供示例代码

当前状态：✅ 所有检查通过，可以发布！
