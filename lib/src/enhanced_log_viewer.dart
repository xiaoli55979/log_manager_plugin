import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'log_file_manager.dart';
import 'log_manager.dart';

/// 增强版日志查看器
class EnhancedLogViewer extends StatefulWidget {
  const EnhancedLogViewer({super.key});

  @override
  State<EnhancedLogViewer> createState() => _EnhancedLogViewerState();
}

class _EnhancedLogViewerState extends State<EnhancedLogViewer> {
  List<File> _logFiles = [];
  bool _isLoading = true;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
  }

  Future<void> _loadLogFiles() async {
    setState(() => _isLoading = true);
    try {
      final files = await LogManager.getAllLogFiles();
      setState(() {
        _logFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showMessage('加载日志文件失败: $e');
      }
    }
  }

  Future<void> _compressSelectedLogs() async {
    if (_selectedIndices.isEmpty) {
      _showMessage('请先选择要压缩的日志文件');
      return;
    }

    try {
      final selectedFiles = _selectedIndices.map((i) => _logFiles[i]).toList();
      final zipFile =
          await LogFileManager.instance.compressSpecificLogs(selectedFiles);

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

  Future<void> _compressAllLogs() async {
    if (_logFiles.isEmpty) {
      _showMessage('没有日志文件可压缩');
      return;
    }

    try {
      final zipFile = await LogManager.compressLogs();
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

  Future<void> _deleteSelectedLogs() async {
    if (_selectedIndices.isEmpty) {
      _showMessage('请先选择要删除的日志文件');
      return;
    }

    final confirmed = await _showConfirmDialog(
        '确认删除', '确定要删除选中的 ${_selectedIndices.length} 个日志文件吗？');
    if (confirmed != true) return;

    try {
      for (final index in _selectedIndices) {
        await _logFiles[index].delete();
      }
      _selectedIndices.clear();
      await _loadLogFiles();
      _showMessage('删除成功');
    } catch (e) {
      _showMessage('删除失败: $e');
    }
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await _showConfirmDialog('确认清空', '确定要清空所有日志文件吗？此操作不可恢复！');
    if (confirmed != true) return;

    try {
      await LogManager.clearAllLogs();
      _selectedIndices.clear();
      await _loadLogFiles();
      _showMessage('清空成功');
    } catch (e) {
      _showMessage('清空失败: $e');
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _logFiles.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(_logFiles.length, (i) => i));
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
        title: const Text('日志文件管理'),
        actions: [
          if (_logFiles.isNotEmpty)
            IconButton(
              icon: Icon(_selectedIndices.length == _logFiles.length
                  ? Icons.check_box
                  : Icons.check_box_outline_blank),
              onPressed: _toggleSelectAll,
              tooltip: '全选/取消全选',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'compress_all':
                  _compressAllLogs();
                  break;
                case 'clear_all':
                  _clearAllLogs();
                  break;
                case 'refresh':
                  _loadLogFiles();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'compress_all',
                child: Row(
                  children: [
                    Icon(Icons.archive),
                    SizedBox(width: 8),
                    Text('压缩全部'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('清空全部', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('刷新'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logFiles.isEmpty
              ? _buildEmptyView()
              : _buildLogList(),
      bottomNavigationBar:
          _selectedIndices.isNotEmpty ? _buildBottomBar() : null,
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无日志文件',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadLogFiles,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '共 ${_logFiles.length} 个日志文件',
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              if (_selectedIndices.isNotEmpty)
                Text(
                  '已选 ${_selectedIndices.length} 个',
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _logFiles.length,
            itemBuilder: (context, index) {
              final file = _logFiles[index];
              final isSelected = _selectedIndices.contains(index);
              return _buildLogFileItem(file, index, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogFileItem(File file, int index, bool isSelected) {
    final fileName = file.path.split('/').last;

    return FutureBuilder<FileStat>(
      future: file.stat(),
      builder: (context, snapshot) {
        final stat = snapshot.data;
        final size = stat?.size ?? 0;
        final modified = stat?.modified;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: isSelected ? 4 : 1,
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: ListTile(
            leading: Checkbox(
              value: isSelected,
              onChanged: (_) => _toggleSelection(index),
            ),
            title: Text(
              fileName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.storage, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(_formatFileSize(size)),
                  ],
                ),
                if (modified != null)
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(modified)),
                    ],
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.visibility),
              onPressed: () => _viewLogFile(file),
              tooltip: '查看内容',
            ),
            onTap: () => _toggleSelection(index),
          ),
        );
      },
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
                onPressed: _compressSelectedLogs,
                icon: const Icon(Icons.archive, size: 20),
                label: const Text('压缩选中'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _deleteSelectedLogs,
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

  void _viewLogFile(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedLogContentViewer(file: file),
      ),
    );
  }
}

/// 增强版日志内容查看器
class EnhancedLogContentViewer extends StatefulWidget {
  final File file;

  const EnhancedLogContentViewer({super.key, required this.file});

  @override
  State<EnhancedLogContentViewer> createState() =>
      _EnhancedLogContentViewerState();
}

class _EnhancedLogContentViewerState extends State<EnhancedLogContentViewer> {
  List<LogEntry> _logEntries = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);
    try {
      final content = await widget.file.readAsString();
      final entries = _parseLogContent(content);
      setState(() {
        _logEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _logEntries = [];
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败: $e')),
        );
      }
    }
  }

  List<LogEntry> _parseLogContent(String content) {
    final lines = content.split('\n');
    final entries = <LogEntry>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // 尝试解析日志级别
      LogLevel? level;
      if (line.contains('[TRACE]') || line.contains('TRACE')) {
        level = LogLevel.trace;
      } else if (line.contains('[DEBUG]') || line.contains('DEBUG')) {
        level = LogLevel.debug;
      } else if (line.contains('[INFO]') || line.contains('INFO')) {
        level = LogLevel.info;
      } else if (line.contains('[WARNING]') || line.contains('WARNING')) {
        level = LogLevel.warning;
      } else if (line.contains('[ERROR]') || line.contains('ERROR')) {
        level = LogLevel.error;
      } else if (line.contains('[FATAL]') || line.contains('FATAL')) {
        level = LogLevel.fatal;
      }

      entries.add(LogEntry(content: line, level: level));
    }

    return entries;
  }

  List<LogEntry> get _filteredEntries {
    var entries = _logEntries;

    // 级别过滤
    if (_filterLevel != null) {
      entries = entries.where((e) => e.level == _filterLevel).toList();
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      entries = entries
          .where((e) =>
              e.content.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return entries;
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _copyToClipboard() {
    final content = _filteredEntries.map((e) => e.content).join('\n');
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split('/').last;
    final filteredEntries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadContent,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyToClipboard,
            tooltip: '复制全部',
          ),
          PopupMenuButton<LogLevel?>(
            icon: const Icon(Icons.filter_list),
            tooltip: '过滤级别',
            onSelected: (level) {
              setState(() => _filterLevel = level);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('全部'),
              ),
              ...LogLevel.values.map((level) => PopupMenuItem(
                    value: level,
                    child: Row(
                      children: [
                        Icon(level.icon, size: 16, color: level.color),
                        const SizedBox(width: 8),
                        Text(level.name.toUpperCase()),
                      ],
                    ),
                  )),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                _buildInfoBar(filteredEntries.length),
                Expanded(
                  child: filteredEntries.isEmpty
                      ? const Center(child: Text('没有匹配的日志'))
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: filteredEntries.length,
                          itemBuilder: (context, index) {
                            return _buildLogEntry(filteredEntries[index]);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'top',
            onPressed: _scrollToTop,
            child: const Icon(Icons.arrow_upward),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'bottom',
            onPressed: _scrollToBottom,
            child: const Icon(Icons.arrow_downward),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索日志内容...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildInfoBar(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.description,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '共 $count 条日志',
            style: const TextStyle(fontSize: 12),
          ),
          if (_filterLevel != null) ...[
            const SizedBox(width: 16),
            Chip(
              label: Text(_filterLevel!.name.toUpperCase()),
              avatar: Icon(_filterLevel!.icon, size: 16),
              onDeleted: () {
                setState(() => _filterLevel = null);
              },
              deleteIconColor: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogEntry(LogEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
        color: entry.level?.color.withValues(alpha: 0.05),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.level != null) ...[
            Icon(entry.level!.icon, size: 16, color: entry.level!.color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SelectableText(
              entry.content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: entry.level?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogEntry {
  final String content;
  final LogLevel? level;

  LogEntry({required this.content, this.level});
}

enum LogLevel {
  trace(Icons.bug_report, Colors.grey),
  debug(Icons.code, Colors.blue),
  info(Icons.info, Colors.green),
  warning(Icons.warning, Colors.orange),
  error(Icons.error, Colors.red),
  fatal(Icons.dangerous, Colors.purple);

  final IconData icon;
  final Color color;

  const LogLevel(this.icon, this.color);
}
