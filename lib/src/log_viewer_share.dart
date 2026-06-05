import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'log_file_manager.dart';

/// 压缩并分享日志：弹进度框 → 后台 isolate 压缩 → 调起系统分享。
Future<void> compressAndShareLogs(BuildContext context, List<File> files) async {
  final messenger = ScaffoldMessenger.of(context);
  if (files.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('没有可压缩的日志文件')));
    return;
  }

  final done = ValueNotifier<int>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => LogCompressProgressDialog(total: files.length, done: done),
  );

  File? zipFile;
  try {
    zipFile = await LogFileManager.instance.compressSpecificLogs(
      files,
      onProgress: (d, _) => done.value = d,
    );
  } catch (e) {
    debugPrint('压缩失败: $e');
  }

  if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
  done.dispose();

  if (!context.mounted) return;
  if (zipFile == null) {
    messenger.showSnackBar(const SnackBar(content: Text('压缩失败')));
    return;
  }

  try {
    await LogFileManager.instance.shareCompressedLog(zipFile, context: context);
  } catch (e) {
    debugPrint('分享失败: $e');
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }
}

/// 压缩进度对话框，显示已压缩文件数与百分比
class LogCompressProgressDialog extends StatelessWidget {
  final int total;
  final ValueListenable<int> done;

  const LogCompressProgressDialog({
    super.key,
    required this.total,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: done,
                builder: (context, value, _) {
                  final pct = total == 0 ? 0 : (value * 100 ~/ total);
                  return Text('正在压缩日志… $value/$total（$pct%）');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
