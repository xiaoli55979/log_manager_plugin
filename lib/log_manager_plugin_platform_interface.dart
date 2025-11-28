import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'log_manager_plugin_method_channel.dart';

abstract class LogManagerPluginPlatform extends PlatformInterface {
  /// Constructs a LogManagerPluginPlatform.
  LogManagerPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static LogManagerPluginPlatform _instance = MethodChannelLogManagerPlugin();

  /// The default instance of [LogManagerPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelLogManagerPlugin].
  static LogManagerPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LogManagerPluginPlatform] when
  /// they register themselves.
  static set instance(LogManagerPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
