import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'log_file_manager.dart';
import 'log_manager.dart';

/// 日志查看器页面
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
          TextButton(
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
          color: Colors.grey[200],
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '共 ${_logFiles.length} 个日志文件',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
              if (_selectedIndices.isNotEmpty)
                Text(
                  '已选 ${_selectedIndices.length} 个',
                  style: const TextStyle(fontSize: 14, color: Colors.blue),
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
          color: isSelected ? Colors.blue[50] : null,
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
                Text('大小: ${_formatFileSize(size)}'),
                if (modified != null)
                  Text(
                      '修改时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(modified)}'),
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _compressSelectedLogs,
              icon: const Icon(Icons.archive, size: 20),
              label: const Text('压缩选中'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _deleteSelectedLogs,
              icon: const Icon(Icons.delete, size: 20),
              label: const Text('删除选中'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _viewLogFile(File file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogFileViewerPage(file: file),
      ),
    );
  }
}

/// 日志文件内容查看页面
class LogFileViewerPage extends StatefulWidget {
  final File file;

  const LogFileViewerPage({super.key, required this.file});

  @override
  State<LogFileViewerPage> createState() => _LogFileViewerPageState();
}

class _LogFileViewerPageState extends State<LogFileViewerPage> {
  String _content = '';
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

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
      setState(() {
        _content = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _content = '读取文件失败: $e';
        _isLoading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split('/').last;

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
            icon: const Icon(Icons.share),
            onPressed: () {
              // 可以实现分享功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('分享功能待实现')),
              );
            },
            tooltip: '分享',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<FileStat>(
                          future: widget.file.stat(),
                          builder: (context, snapshot) {
                            final size = snapshot.data?.size ?? 0;
                            return Text(
                              '文件大小: ${_formatFileSize(size)} | 行数: ${_content.split('\n').length}',
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: _scrollToTop,
                        tooltip: '滚动到顶部',
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        onPressed: _scrollToBottom,
                        tooltip: '滚动到底部',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _content,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
