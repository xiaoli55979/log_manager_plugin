import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_manager_plugin_platform_interface.dart';

/// An implementation of [LogManagerPluginPlatform] that uses method channels.
class MethodChannelLogManagerPlugin extends LogManagerPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('log_manager_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
