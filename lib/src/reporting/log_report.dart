import 'dart:async';

/// 上报发送抽象，后端实现(如 CLS)由主项目注入，插件零后端 SDK 依赖。
/// send 返回是否成功，队列据此决定重试。
abstract class LogReportSink {
  Future<bool> send(String topic, List<LogReportEntry> batch);
}

/// 单条上报数据。level 取 logger 包 Level.value，timeMs 为毫秒时间戳。
///
/// 注意：插件内已存在 UI 用途的 `LogEntry`(enhanced_log_viewer.dart 并已导出)，
/// 为保持零破坏的公共导出，本类命名为 LogReportEntry，避免顶层符号冲突。
class LogReportEntry {
  final String topic;
  final Map<String, String> fields;
  final int level;
  final int timeMs;

  LogReportEntry({
    required this.topic,
    required this.fields,
    required this.level,
    required this.timeMs,
  });

  /// 粗略字节数:按 UTF-16 长度估算，仅用于字节触发判断，不要求精确。
  int get approxBytes {
    var n = topic.length;
    fields.forEach((k, v) {
      n += k.length + v.length;
    });
    return n;
  }
}

/// 可靠上报队列:数量/字节/时间三触发批量发送，失败重试 + 限流退避，
/// 失败批保留不丢，内存上限超限丢最旧，防重入，flush 真 async 退出兜底，Timer 不泄漏。
///
/// sink 未注入时入队的数据会缓存(受 maxQueueSize 约束)，注入后下次触发即发。
class LogReportQueue {
  LogReportQueue({
    this.maxBatchCount = 50,
    this.maxBatchBytes = 32 * 1024,
    this.flushInterval = const Duration(seconds: 5),
    this.maxRetries = 3,
    this.maxQueueSize = 2000,
    this.retryBackoff = const Duration(seconds: 2),
    this.throttleBackoff = const Duration(seconds: 15),
    this.sendTimeout = const Duration(seconds: 10),
  });

  /// 数量触发阈值。
  final int maxBatchCount;

  /// 字节触发阈值(approxBytes 累计)。
  final int maxBatchBytes;

  /// 时间触发间隔。
  final Duration flushInterval;

  /// 单批最大重试次数(不含首次发送)。
  final int maxRetries;

  /// 内存队列条数上限，超限丢弃最旧。
  final int maxQueueSize;

  /// 普通发送失败的退避基准。
  final Duration retryBackoff;

  /// 收到限流(send 返回 false 近似 429)的退避时长。
  final Duration throttleBackoff;

  /// 单次 sink.send 超时;防后端无响应卡住 flush/dispose 退出。
  final Duration sendTimeout;

  LogReportSink? _sink;
  final List<LogReportEntry> _buffer = <LogReportEntry>[];
  int _bufferBytes = 0;
  Timer? _flushTimer;
  bool _sending = false;
  bool _disposed = false;
  bool _closing = false; // dispose 进行中:拒绝新入队,但允许最后一次发送跑完
  bool _drainScheduled = false; // 防重复 microtask 调度

  /// 退避截止时间;在此之前不发起新的发送。
  DateTime? _backoffUntil;

  /// 注入/替换 sink。注入后若已有积压且无退避，启动定时器待发。
  void setSink(LogReportSink sink) {
    _sink = sink;
    if (_buffer.isNotEmpty) {
      _ensureTimer();
    }
  }

  bool get hasSink => _sink != null;

  /// 入队一条。数量或字节达阈值立即触发；否则确保定时器在跑。
  void enqueue(LogReportEntry entry) {
    if (_disposed || _closing) return;
    _buffer.add(entry);
    _bufferBytes += entry.approxBytes;
    _trimOverflow();

    if (_buffer.length >= maxBatchCount || _bufferBytes >= maxBatchBytes) {
      _flushTimer?.cancel();
      _flushTimer = null;
      // 防重复调度:多次触发只排一个 microtask,_sending 再兜并发
      if (!_drainScheduled) {
        _drainScheduled = true;
        scheduleMicrotask(() {
          _drainScheduled = false;
          _drain();
        });
      }
    } else {
      _ensureTimer();
    }
  }

  /// 超内存上限时丢弃最旧条目(不崩溃),同步维护字节计数。
  void _trimOverflow() {
    while (_buffer.length > maxQueueSize) {
      final removed = _buffer.removeAt(0);
      _bufferBytes -= removed.approxBytes;
      if (_bufferBytes < 0) _bufferBytes = 0;
    }
  }

  void _ensureTimer() {
    if (_disposed) return;
    _flushTimer ??= Timer(flushInterval, () {
      _flushTimer = null;
      _drain();
    });
  }

  /// 时间触发入口。
  void _drain() {
    if (_disposed) return;
    unawaited(_send());
  }

  /// 退出兜底:真 async/await 把当前积压尽量发完。
  /// 即使无 sink 或处于退避也立即返回，不阻塞退出流程。
  Future<void> flush() async {
    if (_disposed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _send(force: true);
  }

  /// 取一批并发送;失败保留重试,限流退避,防重入。
  /// force=true 时忽略退避窗口(退出兜底场景)。
  Future<void> _send({bool force = false}) async {
    if (_sending || _disposed) return;
    final sink = _sink;
    if (sink == null) return; // 无 sink:静默缓存,等注入
    if (_buffer.isEmpty) return;

    if (!force && _backoffUntil != null &&
        DateTime.now().isBefore(_backoffUntil!)) {
      _ensureTimer(); // 仍在退避,稍后再试
      return;
    }

    _sending = true;
    var failStreak = 0;
    try {
      while (_buffer.isNotEmpty) {
        final batch = _takeBatch();
        if (batch.isEmpty) break; // 守卫:空批不取 batch.first,避免崩溃
        var ok = false;
        try {
          ok = await sink
              .send(batch.first.topic, batch)
              .timeout(sendTimeout, onTimeout: () => false);
        } catch (_) {
          ok = false;
        }
        if (_disposed) {
          // dispose 期间发送返回:成功则丢弃该批,失败则放回,随后退出
          if (!ok) _restore(batch);
          return;
        }
        if (ok) {
          _backoffUntil = null;
          failStreak = 0;
          continue;
        }
        // 失败:整批放回队首保留
        _restore(batch);
        if (!force) {
          // 非 force:设退避,交给定时器稍后重试
          _backoffUntil = DateTime.now().add(throttleBackoff);
          _ensureTimer();
          return;
        }
        // force(退出兜底):有限次重试后放弃,保留数据,不留退避卡死后续
        failStreak++;
        if (failStreak > maxRetries) break;
      }
    } finally {
      _sending = false;
    }
    // force 退出务必清退避,否则后续发送被锁死(审计 blocker)
    if (force) _backoffUntil = null;
    if (_buffer.isNotEmpty && !_disposed) _ensureTimer();
  }

  /// 取一批:只含队首 topic 的同 topic 条目(避免一批混多 topic 被 sink 用
  /// batch.first.topic 误路由),再按数量+字节双阈值切。队首非空则至少 1 条。
  List<LogReportEntry> _takeBatch() {
    final batch = <LogReportEntry>[];
    if (_buffer.isEmpty) return batch;
    final topic = _buffer.first.topic;
    var bytes = 0;
    while (_buffer.isNotEmpty && batch.length < maxBatchCount) {
      final e = _buffer.first;
      if (e.topic != topic) break; // 只取同 topic,不同 topic 留到下一批
      if (batch.isNotEmpty && bytes + e.approxBytes > maxBatchBytes) break;
      batch.add(e);
      bytes += e.approxBytes;
      _buffer.removeAt(0);
      _bufferBytes -= e.approxBytes;
    }
    if (_bufferBytes < 0) _bufferBytes = 0;
    return batch;
  }

  /// 失败批放回队首并维护字节计数,随后裁剪保证不超上限。
  void _restore(List<LogReportEntry> batch) {
    _buffer.insertAll(0, batch);
    for (final e in batch) {
      _bufferBytes += e.approxBytes;
    }
    _trimOverflow();
  }

  /// 回收资源:先停止接收新入队,把残留尽量发完,再标记销毁清空。
  Future<void> dispose() async {
    if (_disposed || _closing) return;
    _closing = true; // 拒绝新入队,消除 dispose 期间入队丢失窗口
    _flushTimer?.cancel();
    _flushTimer = null;
    await _send(force: true);
    _disposed = true;
    _buffer.clear();
    _bufferBytes = 0;
  }
}
