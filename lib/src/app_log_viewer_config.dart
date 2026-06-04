import 'package:flutter/foundation.dart';

@immutable
class AppLogViewerConfig {
  static const String featureFlagKey = 'app_log_viewer_config';

  final bool enabled;
  final bool showIm;
  final bool showApi;
  final bool showFloating;
  final bool printConsole;
  final List<String> usernames;
  final String title;
  final int maxEntries;

  const AppLogViewerConfig({
    required this.enabled,
    required this.showIm,
    required this.showApi,
    this.showFloating = false,
    this.printConsole = false,
    this.usernames = const [],
    this.title = 'APP日志',
    this.maxEntries = 300,
  });

  const AppLogViewerConfig.disabled()
      : enabled = false,
        showIm = false,
        showApi = false,
        showFloating = false,
        printConsole = false,
        usernames = const [],
        title = 'APP日志',
        maxEntries = 300;

  bool get isVisible => enabled && (showIm || showApi);
  bool get showFloatingEntry => isVisible && showFloating;

  bool isAllowedForUsername(String? username) {
    if (usernames.isEmpty) return true;
    final normalized = username?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return usernames.contains(normalized);
  }

  AppLogViewerConfig effectiveForUsername(String? username) {
    if (isAllowedForUsername(username)) return this;
    return AppLogViewerConfig(
      enabled: false,
      showIm: false,
      showApi: false,
      showFloating: false,
      printConsole: false,
      usernames: usernames,
      title: title,
      maxEntries: maxEntries,
    );
  }

  String get typeLabel {
    final labels = <String>[];
    if (showIm) labels.add('IM');
    if (showApi) labels.add('API');
    return labels.join('/');
  }

  factory AppLogViewerConfig.fromRemote(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const AppLogViewerConfig.disabled();
    }

    final types = _readTypes(raw['types'] ?? raw['logTypes']);
    final imFlag = _readOptionalBool(raw, const [
      'im',
      'showIm',
      'showIM',
      'show_im',
      'imLog',
      'im_log',
    ]);
    final apiFlag = _readOptionalBool(raw, const [
      'api',
      'showApi',
      'showAPI',
      'show_api',
      'apiLog',
      'api_log',
      'network',
      'networkLog',
      'network_log',
    ]);

    final explicitEnabled = _readOptionalBool(raw, const [
      'enabled',
      'enable',
      'visible',
      'show',
      'showEntry',
      'show_entry',
    ]);
    final enabled = explicitEnabled ??
        (imFlag == true || apiFlag == true || types.isNotEmpty);

    final hasTypes = types.isNotEmpty;
    final showIm = imFlag ?? (hasTypes ? types.contains('im') : enabled);
    final showApi = apiFlag ?? (hasTypes ? types.contains('api') : enabled);

    return AppLogViewerConfig(
      enabled: enabled,
      showIm: showIm,
      showApi: showApi,
      showFloating: _readOptionalBool(raw, const [
            'floating',
            'float',
            'showFloating',
            'show_floating',
            'globalFloating',
            'global_floating',
            'floatingEntry',
            'floating_entry',
            'quickEntry',
            'quick_entry',
          ]) ??
          false,
      printConsole: _readOptionalBool(raw, const [
            'console',
            'print',
            'printConsole',
            'print_console',
            'enableConsole',
            'enable_console',
          ]) ??
          false,
      usernames: _readStringList(raw, const [
        'usernames',
        'userNames',
        'usernameList',
        'username_list',
        'users',
        'userList',
        'user_list',
      ]),
      title: _readString(raw, const ['title', 'name'], defaultValue: 'APP日志'),
      maxEntries: _readInt(raw, const ['maxEntries', 'max_entries', 'limit']),
    );
  }

  static bool? _readOptionalBool(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      if (!raw.containsKey(key)) continue;
      final value = raw[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.trim().toLowerCase();
        if (lower == 'true' ||
            lower == '1' ||
            lower == 'yes' ||
            lower == 'on') {
          return true;
        }
        if (lower == 'false' ||
            lower == '0' ||
            lower == 'no' ||
            lower == 'off') {
          return false;
        }
      }
    }
    return null;
  }

  static Set<String> _readTypes(dynamic value) {
    Iterable<dynamic> values;
    if (value is Iterable) {
      values = value;
    } else if (value is String) {
      values = value.split(RegExp(r'[,，|;；\s]+'));
    } else {
      return const {};
    }

    return values
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e == 'im' || e == 'api')
        .toSet();
  }

  static List<String> _readStringList(
    Map<String, dynamic> raw,
    List<String> keys,
  ) {
    dynamic value;
    for (final key in keys) {
      if (raw.containsKey(key)) {
        value = raw[key];
        break;
      }
    }
    if (value == null) return const [];

    Iterable<dynamic> values;
    if (value is Iterable) {
      values = value;
    } else if (value is String) {
      values = value.split(RegExp(r'[,，|;；\s]+'));
    } else {
      return const [];
    }

    final result = values
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return List<String>.unmodifiable(result);
  }

  static String _readString(
    Map<String, dynamic> raw,
    List<String> keys, {
    required String defaultValue,
  }) {
    for (final key in keys) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return defaultValue;
  }

  static int _readInt(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is int && value > 0) return value;
      if (value is num && value > 0) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 300;
  }
}
