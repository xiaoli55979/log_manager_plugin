import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_log_im_source.dart';
import 'app_log_viewer_config.dart';
import 'app_log_viewer_runtime.dart';
import 'log_manager.dart';
import 'log_viewer_theme.dart';

typedef AppLogViewerOpenCallback = void Function(
  BuildContext context,
  AppLogViewerConfig config,
);

class AppLogFloatingEntry extends StatefulWidget {
  final Widget child;
  final AppLogViewerOpenCallback? onOpen;

  const AppLogFloatingEntry({
    super.key,
    required this.child,
    this.onOpen,
  });

  @override
  State<AppLogFloatingEntry> createState() => _AppLogFloatingEntryState();
}

class _AppLogFloatingEntryState extends State<AppLogFloatingEntry> {
  Offset? _offset;

  static const double _buttonSize = 52;
  static const double _margin = 12;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLogViewerConfig>(
      valueListenable: AppLogViewerRuntime.configListenable,
      child: widget.child,
      builder: (context, config, child) {
        if (!config.showFloatingEntry) {
          return child ?? const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final offset = _resolveOffset(constraints);
            return Stack(
              alignment: Alignment.topLeft,
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                Positioned(
                  left: offset.dx,
                  top: offset.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _offset = _clampOffset(
                          offset + details.delta,
                          constraints,
                        );
                      });
                    },
                    child: Directionality(
                      textDirection: ui.TextDirection.ltr,
                      child: Material(
                        color: Theme.of(context).primaryColor,
                        elevation: 8,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _openViewer(config),
                          child: const SizedBox(
                            width: _buttonSize,
                            height: _buttonSize,
                            child: Icon(
                              Icons.description_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openViewer(AppLogViewerConfig config) {
    final opener = widget.onOpen;
    if (opener != null) {
      opener(context, config);
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => AppLogViewerPage(config: config),
      ),
    );
  }

  Offset _resolveOffset(BoxConstraints constraints) {
    final defaultOffset = Offset(
      constraints.maxWidth - _buttonSize - _margin,
      constraints.maxHeight - _buttonSize - 120,
    );
    return _clampOffset(_offset ?? defaultOffset, constraints);
  }

  Offset _clampOffset(Offset raw, BoxConstraints constraints) {
    final maxLeft = constraints.maxWidth - _buttonSize - _margin;
    final maxTop = constraints.maxHeight - _buttonSize - _margin;
    final left = raw.dx.clamp(_margin, maxLeft < _margin ? _margin : maxLeft);
    final top = raw.dy.clamp(_margin, maxTop < _margin ? _margin : maxTop);
    return Offset(left.toDouble(), top.toDouble());
  }
}

class AppLogViewerPage extends StatelessWidget {
  final AppLogViewerConfig config;

  const AppLogViewerPage({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final tabs = <_AppLogTab>[];
    if (config.showIm) {
      tabs.add(
        _AppLogTab(
          title: 'IM',
          child: _ImLogPanel(maxEntries: config.maxEntries),
        ),
      );
    }
    if (config.showApi) {
      tabs.add(
        _AppLogTab(
          title: 'API',
          child: _ApiLogPanel(maxEntries: config.maxEntries),
        ),
      );
    }

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: logViewerAppBarBackground,
          foregroundColor: logViewerAppBarForeground,
          title: Text(config.title),
        ),
        body: const Center(child: Text('日志入口未开启')),
      );
    }

    if (tabs.length == 1) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: logViewerAppBarBackground,
          foregroundColor: logViewerAppBarForeground,
          title: Text('${config.title}-${tabs.first.title}'),
          actions: [_AppLogExportButton(config: config)],
        ),
        body: tabs.first.child,
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: logViewerAppBarBackground,
          foregroundColor: logViewerAppBarForeground,
          title: Text(config.title),
          actions: [_AppLogExportButton(config: config)],
          bottom: TabBar(tabs: tabs.map((e) => Tab(text: e.title)).toList()),
        ),
        body: TabBarView(children: tabs.map((e) => e.child).toList()),
      ),
    );
  }
}

class _AppLogTab {
  final String title;
  final Widget child;

  const _AppLogTab({required this.title, required this.child});
}

class _AppLogExportButton extends StatefulWidget {
  final AppLogViewerConfig config;

  const _AppLogExportButton({required this.config});

  @override
  State<_AppLogExportButton> createState() => _AppLogExportButtonState();
}

class _AppLogExportButtonState extends State<_AppLogExportButton> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    File? file;
    setState(() => _exporting = true);
    try {
      file = await _buildExportFile(widget.config);
      if (!mounted) return;
      if (file == null) {
        _toast('暂无可导出的日志');
        return;
      }
      await _shareFile(file);
      if (!mounted) return;
      _toast('日志文件已生成');
    } catch (_) {
      if (file != null) {
        await Clipboard.setData(ClipboardData(text: file.path));
        if (!mounted) return;
        _toast('分享失败，已复制日志文件路径');
        return;
      }
      if (!mounted) return;
      _toast('导出日志失败');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareFile(File file) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        title: 'APP 日志导出',
        text: 'APP 日志导出',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '导出',
      icon: _exporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_download_outlined),
      onPressed: _exporting ? null : _export,
    );
  }
}

class _ImLogPanel extends StatefulWidget {
  final int maxEntries;

  const _ImLogPanel({required this.maxEntries});

  @override
  State<_ImLogPanel> createState() => _ImLogPanelState();
}

class _ImLogPanelState extends State<_ImLogPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _levelFilter = 'ALL';
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent - 40;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _autoScroll) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  List<AppLogImEntry> _filtered(AppLogImSource source) {
    final raw = source.snapshotEntries();
    final start =
        raw.length > widget.maxEntries ? raw.length - widget.maxEntries : 0;
    final limited = raw.sublist(start);
    final keyword = _searchController.text.trim().toLowerCase();

    return limited.where((entry) {
      if (_levelFilter != 'ALL' && entry.level != _levelFilter) return false;
      if (keyword.isEmpty) return true;
      return entry.tag.toLowerCase().contains(keyword) ||
          entry.message.toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _copy(List<AppLogImEntry> entries) async {
    final text = entries
        .map(
          (e) => '${_formatTime(e.time)} [${e.level}] ${e.tag}: ${e.message}',
        )
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    _toast('已复制 IM 日志');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLogImSource?>(
      valueListenable: AppLogViewerRuntime.imSourceListenable,
      builder: (context, source, _) {
        if (source == null) {
          return const _EmptyLogView(text: '暂无 IM 日志');
        }
        return Column(
          children: [
            _LogToolbar(
              hintText: '搜索 IM 日志',
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              actions: [
                PopupMenuButton<String>(
                  tooltip: '级别',
                  icon: const Icon(Icons.filter_list),
                  onSelected: (value) => setState(() => _levelFilter = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ALL', child: Text('全部')),
                    PopupMenuItem(value: 'ERROR', child: Text('Error')),
                    PopupMenuItem(value: 'WARNING', child: Text('Warning')),
                    PopupMenuItem(value: 'INFO', child: Text('Info')),
                    PopupMenuItem(value: 'DEBUG', child: Text('Debug')),
                  ],
                ),
                IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(_filtered(source)),
                ),
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: source.clear,
                ),
              ],
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: source.tick,
                builder: (_, __, ___) {
                  final entries = _filtered(source);
                  _scrollToBottom();
                  if (entries.isEmpty) {
                    return const _EmptyLogView(text: '暂无 IM 日志');
                  }
                  return ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) =>
                        _ImLogTile(entry: entries[index]),
                  );
                },
              ),
            ),
            if (!_autoScroll)
              SafeArea(
                top: false,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _autoScroll = true);
                    _scrollToBottom();
                  },
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('跳到最新'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ApiLogPanel extends StatefulWidget {
  final int maxEntries;

  const _ApiLogPanel({required this.maxEntries});

  @override
  State<_ApiLogPanel> createState() => _ApiLogPanelState();
}

class _ApiLogPanelState extends State<_ApiLogPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<_ApiLogBlock> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final blocks = await _loadApiLogBlocks(widget.maxEntries);

      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blocks = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载 API 日志失败: $e')),
      );
    }
  }

  List<_ApiLogBlock> get _filtered {
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) return _blocks;
    return _blocks
        .where((block) => block.content.toLowerCase().contains(keyword))
        .toList();
  }

  Future<void> _copy() async {
    final text = _filtered.map((e) => e.content).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 API 日志'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('确定要清空本地 APP 日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LogManager.clearAllLogs();
    await AppLogViewerRuntime.restoreAfterClear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _filtered;
    return Column(
      children: [
        _LogToolbar(
          hintText: '搜索 API 日志',
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
            IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy),
              onPressed: _copy,
            ),
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : blocks.isEmpty
                  ? const _EmptyLogView(text: '暂无 API 日志')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: blocks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) =>
                          _ApiLogTile(block: blocks[index]),
                    ),
        ),
      ],
    );
  }
}

class _LogToolbar extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<Widget> actions;

  const _LogToolbar({
    required this.hintText,
    required this.controller,
    required this.onChanged,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FA),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: hintText,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _ImLogTile extends StatelessWidget {
  final AppLogImEntry entry;

  const _ImLogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(entry.level);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9EDF2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _formatTime(entry.time),
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
                const SizedBox(width: 6),
                _LevelBadge(level: entry.level, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.tag,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              entry.message,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiLogTile extends StatelessWidget {
  final _ApiLogBlock block;

  const _ApiLogTile({required this.block});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9EDF2)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        title: Text(
          block.title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${DateFormat('MM-dd HH:mm:ss').format(block.modified)}  '
          '${block.fileName}',
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              block.content,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final String level;
  final Color color;

  const _LevelBadge({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        level,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EmptyLogView extends StatelessWidget {
  final String text;

  const _EmptyLogView({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 52, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _ApiLogBlock {
  final String title;
  final String content;
  final String fileName;
  final DateTime modified;

  const _ApiLogBlock({
    required this.title,
    required this.content,
    required this.fileName,
    required this.modified,
  });
}

class _ApiLogFile {
  final File file;
  final FileStat stat;

  const _ApiLogFile({required this.file, required this.stat});
}

Future<File?> _buildExportFile(AppLogViewerConfig config) async {
  final buffer = StringBuffer()
    ..writeln('APP 日志导出')
    ..writeln('导出时间: ${DateTime.now().toIso8601String()}')
    ..writeln('日志类型: ${_enabledLogTypes(config).join(', ')}')
    ..writeln();

  var hasContent = false;
  if (config.showIm) {
    final entries = _limitedImEntries(config.maxEntries);
    _writeSection(buffer, 'IM 日志');
    if (entries.isEmpty) {
      buffer.writeln('暂无 IM 日志');
    } else {
      hasContent = true;
      for (final entry in entries) {
        buffer.writeln(
          '${_formatTime(entry.time)} [${entry.level}] '
          '${entry.tag}: ${entry.message}',
        );
      }
    }
    buffer.writeln();
  }

  if (config.showApi) {
    final blocks = await _loadApiLogBlocks(config.maxEntries);
    _writeSection(buffer, 'API 日志');
    if (blocks.isEmpty) {
      buffer.writeln('暂无 API 日志');
    } else {
      hasContent = true;
      for (final block in blocks) {
        buffer
          ..writeln(
            '${DateFormat('MM-dd HH:mm:ss').format(block.modified)}  '
            '${block.fileName}',
          )
          ..writeln(block.content)
          ..writeln();
      }
    }
  }

  if (!hasContent) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/app_log_${_fileTimestamp()}.txt');
  await file.writeAsString(buffer.toString(), flush: true);
  return file;
}

List<String> _enabledLogTypes(AppLogViewerConfig config) {
  final types = <String>[];
  if (config.showIm) types.add('IM');
  if (config.showApi) types.add('API');
  return types.isEmpty ? ['未开启'] : types;
}

List<AppLogImEntry> _limitedImEntries(int maxEntries) {
  final source = AppLogViewerRuntime.imSource;
  if (source == null) return const [];
  final entries = source.snapshotEntries();
  final start = entries.length > maxEntries ? entries.length - maxEntries : 0;
  return entries.sublist(start);
}

Future<List<_ApiLogBlock>> _loadApiLogBlocks(int maxEntries) async {
  final files = await LogManager.getAllLogFiles();
  final fileStats = <_ApiLogFile>[];
  for (final file in files) {
    fileStats.add(_ApiLogFile(file: file, stat: await file.stat()));
  }
  fileStats.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));

  final blocks = <_ApiLogBlock>[];
  for (final item in fileStats) {
    if (blocks.length >= maxEntries) break;
    final bytes = await item.file.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final extracted = _extractApiBlocks(
      content,
      fileName: item.file.path.split('/').last,
      modified: item.stat.modified,
    );
    blocks.addAll(extracted.take(maxEntries - blocks.length));
  }
  return blocks;
}

List<_ApiLogBlock> _extractApiBlocks(
  String content, {
  required String fileName,
  required DateTime modified,
}) {
  final blockPattern = RegExp(
    r'={15} START ={15}[\s\S]*?={16} END ={16}',
    multiLine: true,
  );
  final matches = blockPattern.allMatches(content).toList().reversed;
  final blocks = <_ApiLogBlock>[];

  for (final match in matches) {
    final text = _maskSensitive(match.group(0) ?? '');
    if (_isApiBlock(text)) {
      blocks.add(
        _ApiLogBlock(
          title: _resolveApiTitle(text),
          content: text,
          fileName: fileName,
          modified: modified,
        ),
      );
    }
  }

  if (blocks.isNotEmpty) return blocks;

  final lines = content
      .split('\n')
      .where(_isApiBlock)
      .map(_maskSensitive)
      .toList()
      .reversed;
  return lines
      .map(
        (line) => _ApiLogBlock(
          title: _resolveApiTitle(line),
          content: line,
          fileName: fileName,
          modified: modified,
        ),
      )
      .toList();
}

bool _isApiBlock(String text) {
  return text.contains('REQUEST ') ||
      text.contains('RESPONSE ') ||
      text.contains('ERROR DioExceptionType') ||
      text.contains('Original:') ||
      text.contains('[NETWORK]');
}

String _resolveApiTitle(String text) {
  for (final line in text.split('\n')) {
    if (line.contains('REQUEST ') ||
        line.contains('RESPONSE ') ||
        line.contains('ERROR DioExceptionType') ||
        line.contains('[NETWORK]')) {
      return line.replaceAll('║', '').trim();
    }
  }
  return 'API 日志';
}

void _writeSection(StringBuffer buffer, String title) {
  buffer.writeln('================ $title ================');
}

String _fileTimestamp() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

Color _levelColor(String level) {
  switch (level) {
    case 'ERROR':
      return const Color(0xFFE53935);
    case 'WARNING':
      return const Color(0xFFEF6C00);
    case 'INFO':
      return const Color(0xFF1565C0);
    case 'DEBUG':
    default:
      return Colors.black87;
  }
}

String _formatTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
      '${three(time.millisecond)}';
}

String _maskSensitive(String input) {
  var text = input;
  final lineSecretPattern = RegExp(
    r'((?:Authorization|X-Key|X-Signature|X-Encrypt-Signature|X-Device-Signature|X-Sign|x-t-id|trace_id)\s*:\s*)(.+)',
    caseSensitive: false,
  );
  text = text.replaceAllMapped(lineSecretPattern, (m) => '${m[1]}***');

  final kvPatterns = [
    RegExp(
      r'''(["']?(?:access[_-]?)?(?:refresh[_-]?)?token["']?\s*[:=]\s*["']?)([^"',}\s]+)(["']?)''',
      caseSensitive: false,
    ),
    RegExp(
      r'''(["']?(?:password|pwd|passwd)["']?\s*[:=]\s*["']?)([^"',}\s]+)(["']?)''',
      caseSensitive: false,
    ),
    RegExp(
      r'''(["']?authorization["']?\s*[:=]\s*["']?)([^"',}\s]+)(["']?)''',
      caseSensitive: false,
    ),
    RegExp(r'(Bearer\s+)([A-Za-z0-9\-_\.]+)', caseSensitive: false),
    RegExp(r'(?<!\d)(1[3-9])(\d{4})(\d{4})(?!\d)'),
    RegExp(r'(?<!\d)(\d{6})\d{8}(\d{4})(?!\d)'),
  ];
  for (var i = 0; i < 3; i++) {
    text = text.replaceAllMapped(kvPatterns[i], (m) => '${m[1]}***${m[3]}');
  }
  text = text.replaceAllMapped(kvPatterns[3], (m) => '${m[1]}***');
  text = text.replaceAllMapped(kvPatterns[4], (m) => '${m[1]}****${m[3]}');
  text = text.replaceAllMapped(kvPatterns[5], (m) => '${m[1]}********${m[2]}');
  return text;
}
