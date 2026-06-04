import 'package:flutter/foundation.dart';

@immutable
class AppLogImEntry {
  final DateTime time;
  final String level;
  final String tag;
  final String message;

  const AppLogImEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });
}

abstract class AppLogImSource {
  ValueListenable<int> get tick;

  List<AppLogImEntry> snapshotEntries();

  void clear();

  void setEnabled(bool enabled);
}
