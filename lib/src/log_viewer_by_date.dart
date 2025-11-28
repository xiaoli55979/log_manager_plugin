import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'log_file_manager.dart';
import 'enhanced_log_viewer.dart';

/// 按日期查看日志
class LogViewerByDate extends StatefulWidget {
  const LogViewerByDate({super.key});

  @override
  State<LogViewerByDate> createState() => _LogViewerByDateState();
}

class _LogViewerByDateState extends State<LogViewerByDate> {
  Map<String, List<File>> _logsByDate = {};
  LogStatistics? _statistics;
  bool _isLoading = true;
  final Set<String> _selectedDates = {};

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logsByDate = await LogFileManager.instance.getLogFilesByDate();
      final stats = await LogFileManager.instance.getStatistics();
      setState(() {
        _logsByDate = logsByDate;
        _statistics = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showMessage('加载日志失败: $e');
      }
    }
  }

  Future<void> _compressSelectedDates() async {
    if (_selectedDates.isEmpty) {
      _showMessage('请先选择要压缩的日期');
      return;
    }

    try {
      final List<File> filesToCompress = [];
      for (final date in _selectedDates) {
        filesToCompress.addAll(_logsByDate[date] ?? []);
      }

      final zipFile =
          await LogFileManager.instance.compressSpecificLogs(filesToCompress);

      if (zipFile != null) {
        if (mounted) {
          final size = await zipFile.length();
          _showMessage(
              '压缩成功！\n文件: ${zipFile.path.split('/').last}\n大小: ${_formatFileSize(size)}');
        }
      } else {
        _showMessage('压缩失败');
      }
    } catch (e) {
      _showMessage('压缩失败: $e');
    }
  }

  Future<void> _deleteSelectedDates() async {
    if (_selectedDates.isEmpty) {
      _showMessage('请先选择要删除的日期');
      return;
    }

    final confirmed = await _showConfirmDialog(
        '确认删除', '确定要删除选中的 ${_selectedDates.length} 天的日志吗？');
    if (confirmed != true) return;

    try {
      for (final date in _selectedDates) {
        await LogFileManager.instance.deleteLogsByDate(date);
      }
      _selectedDates.clear();
      await _loadLogs();
      _showMessage('删除成功');
    } catch (e) {
      _showMessage('删除失败: $e');
    }
  }

  void _toggleDateSelection(String date) {
    setState(() {
      if (_selectedDates.contains(date)) {
        _selectedDates.remove(date);
      } else {
        _selectedDates.add(date);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedDates.length == _logsByDate.length) {
        _selectedDates.clear();
      } else {
        _selectedDates.clear();
        _selectedDates.addAll(_logsByDate.keys);
      }
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateFormat('yyyyMMdd').parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final fileDate = DateTime(date.year, date.month, date.day);

      if (fileDate == today) {
        return '今天 (${DateFormat('MM-dd').format(date)})';
      } else if (fileDate == yesterday) {
        return '昨天 (${DateFormat('MM-dd').format(date)})';
      } else {
        return DateFormat('yyyy-MM-dd').format(date);
      }
    } catch (e) {
      return dateStr;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('按日期查看日志'),
        actions: [
          if (_logsByDate.isNotEmpty)
            IconButton(
              icon: Icon(_selectedDates.length == _logsByDate.length
                  ? Icons.check_box
                  : Icons.check_box_outline_blank),
              onPressed: _toggleSelectAll,
              tooltip: '全选/取消全选',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logsByDate.isEmpty
              ? _buildEmptyView()
              : Column(
                  children: [
                    if (_statistics != null) _buildStatisticsCard(),
                    Expanded(child: _buildDateList()),
                  ],
                ),
      bottomNavigationBar: _selectedDates.isNotEmpty ? _buildBottomBar() : null,
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无日志文件',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    final stats = _statistics!;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '日志统计',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                    '总天数', '${stats.daysCount}', Icons.calendar_month),
                _buildStatItem('总文件', '${stats.totalFiles}', Icons.description),
                _buildStatItem('总大小', stats.formattedTotalSize, Icons.storage),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildDateList() {
    final sortedDates = _logsByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 最新的在前

    return ListView.builder(
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final files = _logsByDate[date]!;
        final isSelected = _selectedDates.contains(date);
        return _buildDateItem(date, files, isSelected);
      },
    );
  }

  Widget _buildDateItem(String date, List<File> files, bool isSelected) {
    return FutureBuilder<int>(
      future: _calculateTotalSize(files),
      builder: (context, snapshot) {
        final totalSize = snapshot.data ?? 0;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: isSelected ? 4 : 1,
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ExpansionTile(
            leading: Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleDateSelection(date),
            ),
            title: Text(
              _formatDate(date),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle:
                Text('${files.length} 个文件 · ${_formatFileSize(totalSize)}'),
            children: files.map((file) => _buildFileItem(file)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFileItem(File file) {
    final fileName = file.path.split('/').last;

    return FutureBuilder<FileStat>(
      future: file.stat(),
      builder: (context, snapshot) {
        final size = snapshot.data?.size ?? 0;

        return ListTile(
          dense: true,
          leading: const Icon(Icons.description, size: 20),
          title: Text(fileName, style: const TextStyle(fontSize: 13)),
          subtitle: Text(_formatFileSize(size)),
          trailing: IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            onPressed: () => _viewFile(file),
          ),
          onTap: () => _viewFile(file),
        );
      },
    );
  }

  Future<int> _calculateTotalSize(List<File> files) async {
    int total = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        total += stat.size;
      } catch (e) {
        // 忽略错误
      }
    }
    return total;
  }

  void _viewFile(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedLogContentViewer(file: file),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _compressSelectedDates,
                icon: const Icon(Icons.archive, size: 20),
                label: const Text('压缩选中'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _deleteSelectedDates,
                icon: const Icon(Icons.delete, size: 20),
                label: const Text('删除选中'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
