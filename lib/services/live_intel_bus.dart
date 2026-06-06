import 'dart:async';

import 'package:PiliPlus/models_new/live/live_danmaku/danmaku_msg.dart';

class LiveIntelBusService {
  LiveIntelBusService._();

  static final LiveIntelBusService instance = LiveIntelBusService._();

  final Map<String, StreamController<DanmakuMsg>> _danmakuControllers = {};
  final Map<String, StreamController<int>> _onlineControllers = {};

  Stream<DanmakuMsg> danmakuStream(String tag) =>
      _danmakuControllers
          .putIfAbsent(tag, () => StreamController<DanmakuMsg>.broadcast())
          .stream;

  Stream<int> onlineStream(String tag) =>
      _onlineControllers
          .putIfAbsent(tag, () => StreamController<int>.broadcast())
          .stream;

  void emitDanmaku(String tag, DanmakuMsg msg) {
    _danmakuControllers[tag]?.add(msg);
  }

  void emitOnline(String tag, int count) {
    _onlineControllers[tag]?.add(count);
  }

  void disposeTag(String tag) {
    _danmakuControllers.remove(tag)?.close();
    _onlineControllers.remove(tag)?.close();
  }
}
