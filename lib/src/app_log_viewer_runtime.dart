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
    final next = configFromRemote(raw, username: username);
    await applyConfig(next, dio: dio);
    return next;
  }

  static Future<void> applyConfig(
    AppLogViewerConfig next, {
    Dio? dio,
  }) async {
    _configNotifier.value = next;
    _imSourceNotifier.value?.setEnabled(next.showIm);
    await configureLogManager(next);
    if (dio != null) {
      _trackedDios.add(dio);
    }
    for (final trackedDio in List<Dio>.of(_trackedDios)) {
      configureDio(trackedDio, next, false);
    }
  }

  static void registerImSource(AppLogImSource source) {
    _imSourceNotifier.value = source;
    source.setEnabled(_configNotifier.value.showIm);
  }

  static void unregisterImSource(AppLogImSource source) {
    if (identical(_imSourceNotifier.value, source)) {
      _imSourceNotifier.value = null;
    }
  }

  static Future<void> restoreAfterClear() async {
    await applyConfig(_configNotifier.value);
  }

  static Future<void> configureLogManager(AppLogViewerConfig next) async {
    final logEnabled =
        _debugBuildLogEnabled || next.isVisible || next.printConsole;
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
}
