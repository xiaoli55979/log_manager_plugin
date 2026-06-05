import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' show Level;

import 'app_log_im_source.dart';
import 'app_log_viewer_config.dart';
import 'dio_log_interceptor.dart';
import 'log_config.dart';
import 'log_manager.dart';

class AppLogViewerRuntime {
  AppLogViewerRuntime._();

  static bool get _debugBuildLogEnabled => kDebugMode;
  static final ValueNotifier<AppLogViewerConfig> _configNotifier =
      ValueNotifier<AppLogViewerConfig>(const AppLogViewerConfig.disabled());
  static final ValueNotifier<AppLogImSource?> _imSourceNotifier =
      ValueNotifier<AppLogImSource?>(null);
  static final Set<Dio> _trackedDios = LinkedHashSet<Dio>.identity();
  static AppLogImSource? _attachedImUploadSource;
  static VoidCallback? _imUploadListener;
  static String? _lastUploadedImEntryKey;

  static ValueListenable<AppLogViewerConfig> get configListenable =>
      _configNotifier;

  static AppLogViewerConfig get config => _configNotifier.value;

  static ValueListenable<AppLogImSource?> get imSourceListenable =>
      _imSourceNotifier;

  static AppLogImSource? get imSource => _imSourceNotifier.value;

  static AppLogViewerConfig configFromRemote(
    Map<String, dynamic>? raw, {
    String? username,
  }) {
    return AppLogViewerConfig.fromRemote(raw).effectiveForUsername(username);
  }

  static Future<AppLogViewerConfig> applyRemoteConfig(
    Map<String, dynamic>? raw, {
    String? username,
    Dio? dio,
  }) async {
    LogManager.updateRemoteFullLogContext({'username': username});
    final next = configFromRemote(raw, username: username);
    await applyConfig(next, dio: dio);
    return next;
  }

  static Future<void> applyConfig(
    AppLogViewerConfig next, {
    Dio? dio,
  }) async {
    final previous = _configNotifier.value;
    _configNotifier.value = next;
    final imSource = _imSourceNotifier.value;
    imSource?.setEnabled(next.showIm || next.shouldAutoUploadLogs);
    if (next.shouldAutoUploadLogs &&
        !previous.shouldAutoUploadLogs &&
        imSource != null) {
      _markImEntriesUploaded(imSource);
    }
    await configureLogManager(next);
    if (dio != null) {
      _trackedDios.add(dio);
    }
    for (final trackedDio in List<Dio>.of(_trackedDios)) {
      configureDio(trackedDio, next, false);
    }
  }

  static void registerImSource(AppLogImSource source) {
    _detachImSourceUploadListener();
    _imSourceNotifier.value = source;
    source.setEnabled(
      _configNotifier.value.showIm ||
          _configNotifier.value.shouldAutoUploadLogs,
    );
    _attachImSourceUploadListener(source);
  }

  static void unregisterImSource(AppLogImSource source) {
    if (identical(_imSourceNotifier.value, source)) {
      _detachImSourceUploadListener();
      _imSourceNotifier.value = null;
    }
  }

  static Future<void> restoreAfterClear() async {
    await applyConfig(_configNotifier.value);
  }

  static Future<void> configureLogManager(AppLogViewerConfig next) async {
    LogManager.enableAppLogViewerRemoteFullLog(
      enabled: next.shouldAutoUploadLogs,
      minLevel: Level.debug,
    );
    final logEnabled = _debugBuildLogEnabled ||
        next.isVisible ||
        next.printConsole ||
        next.shouldAutoUploadLogs;
    await LogManager.instance.updateConfig(
      LogManagerConfig(
        enabled: logEnabled,
        enableConsoleInDebug: _debugBuildLogEnabled || next.printConsole,
        enableConsoleInRelease: next.printConsole,
        enableFileLog: logEnabled,
        maxFileSize: 10 * 1024 * 1024,
        maxRetentionDays: 7,
        logLevel: Level.debug,
        logDirectory: 'logs',
        deleteAfterUpload: true,
        maxBatchSize: 100 * 1024,
      ),
    );
  }

  static bool shouldRecordApiLogs([AppLogViewerConfig? next]) {
    final cfg = next ?? _configNotifier.value;
    return _debugBuildLogEnabled || cfg.showApi;
  }

  static void configureDio(
    Dio dio, [
    AppLogViewerConfig? next,
    bool track = true,
  ]) {
    if (track) {
      _trackedDios.add(dio);
    }
    final cfg = next ?? _configNotifier.value;
    final shouldRecord = shouldRecordApiLogs(cfg);
    final installed = dio.interceptors.any((i) => i is LogManagerInterceptor);

    if (shouldRecord && !installed) {
      dio.interceptors.add(
        LogManagerInterceptor(
          requestHeader: _debugBuildLogEnabled,
          requestBody: true,
          responseHeader: _debugBuildLogEnabled,
          responseBody: true,
          compact: true,
          error: true,
        ),
      );
      return;
    }

    if (!shouldRecord && installed) {
      dio.interceptors.removeWhere((i) => i is LogManagerInterceptor);
    }
  }

  static void configureTransientDio(
    Dio dio, [
    AppLogViewerConfig? next,
  ]) {
    configureDio(dio, next, false);
  }

  static void _attachImSourceUploadListener(AppLogImSource source) {
    _attachedImUploadSource = source;
    _markImEntriesUploaded(source);
    void listener() => _uploadPendingImEntries(source);
    _imUploadListener = listener;
    source.tick.addListener(listener);
  }

  static void _detachImSourceUploadListener() {
    final source = _attachedImUploadSource;
    final listener = _imUploadListener;
    if (source != null && listener != null) {
      source.tick.removeListener(listener);
    }
    _attachedImUploadSource = null;
    _imUploadListener = null;
    _lastUploadedImEntryKey = null;
  }

  static void _markImEntriesUploaded(AppLogImSource source) {
    final entries = source.snapshotEntries();
    _lastUploadedImEntryKey =
        entries.isEmpty ? null : _imEntryKey(entries.last);
  }

  static void _uploadPendingImEntries(AppLogImSource source) {
    if (!identical(source, _attachedImUploadSource)) return;
    final entries = source.snapshotEntries();
    if (entries.isEmpty) {
      _lastUploadedImEntryKey = null;
      return;
    }

    final cfg = _configNotifier.value;
    if (!cfg.shouldAutoUploadLogs || !cfg.showIm) {
      _lastUploadedImEntryKey = _imEntryKey(entries.last);
      return;
    }

    var start = 0;
    final lastKey = _lastUploadedImEntryKey;
    if (lastKey != null) {
      final index = entries.lastIndexWhere(
        (entry) => _imEntryKey(entry) == lastKey,
      );
      if (index >= 0) {
        start = index + 1;
      }
    }

    for (var i = start; i < entries.length; i++) {
      final entry = entries[i];
      LogManager.reportRemoteFullLogLine(
        _formatImEntry(entry),
        level: _levelOfImEntry(entry),
        time: entry.time,
      );
    }
    _lastUploadedImEntryKey = _imEntryKey(entries.last);
  }

  static String _imEntryKey(AppLogImEntry entry) {
    return '${entry.time.microsecondsSinceEpoch}|${entry.level}|'
        '${entry.tag}|${entry.message}';
  }

  static String _formatImEntry(AppLogImEntry entry) {
    final time = entry.time;
    final timestamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    return '$timestamp [${entry.level}] ${entry.tag}: ${entry.message}';
  }

  static Level _levelOfImEntry(AppLogImEntry entry) {
    switch (entry.level.toUpperCase()) {
      case 'DEBUG':
        return Level.debug;
      case 'INFO':
        return Level.info;
      case 'WARNING':
      case 'WARN':
        return Level.warning;
      case 'ERROR':
        return Level.error;
      default:
        return Level.info;
    }
  }
}
