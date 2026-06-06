import 'dart:async';

import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_danmaku/danmaku_msg.dart';
import 'package:PiliPlus/models_new/live/live_feed_index/card_data_list_item.dart';
import 'package:PiliPlus/pages/live_room/intel/model.dart';
import 'package:PiliPlus/services/live_intel_bus.dart';
import 'package:PiliPlus/services/request_debug.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

class LiveIntelController extends GetxController {
  LiveIntelController({
    required this.heroTag,
    required this.roomId,
    required this.initialRoomTitle,
    required this.initialRoomOwner,
    required this.seedMessages,
    this.initialTrueOnline,
  });

  final String heroTag;
  final int roomId;
  final String initialRoomTitle;
  final String initialRoomOwner;
  final List<DanmakuMsg> seedMessages;
  final int? initialTrueOnline;

  final isLoading = false.obs;
  final loadError = RxnString();
  final lastRefreshAt = Rxn<DateTime>();
  final summary = Rxn<LiveIntelAreaSummary>();
  final comments = <LiveIntelCommentItem>[].obs;
  final roomStatuses = <LiveIntelRoomStatus>[].obs;
  final keywordGroups = <String, List<String>>{}.obs;

  final Set<String> _seenCommentKeys = <String>{};
  StreamSubscription<DanmakuMsg>? _danmakuSubscription;
  StreamSubscription<int>? _onlineSubscription;

  int? _parentAreaId;
  int? _areaId;
  String _areaName = '';
  int _totalRoomCount = 0;
  int _discoveredRoomCount = 0;
  int _discoveredUpCount = 0;

  int get pageLimit => Pref.liveIntelAreaPageLimit;
  int get roomLimit => Pref.liveIntelAreaRoomLimit;
  int get pageSize => Pref.liveIntelAreaPageSize;

  List<RequestDebugRecord> get debugRecords =>
      RequestDebugService.instance.records
          .where((item) => item.category == 'live_intel' || item.category == 'ws')
          .toList();

  List<LiveIntelRoomStatus> get followerRanking => _rankBy(
    roomStatuses,
    selector: (item) => item.followerCount,
  );

  List<LiveIntelRoomStatus> get guardRanking => _rankBy(
    roomStatuses,
    selector: (item) => item.guardCount,
  );

  List<LiveIntelRoomStatus> get trueOnlineRanking => _rankBy(
    roomStatuses,
    selector: (item) => item.trueOnline,
  );

  LiveIntelRoomStatus? _findStatusByRoomId(int targetRoomId) {
    for (final item in roomStatuses) {
      if (item.roomId == targetRoomId) {
        return item;
      }
    }
    return null;
  }

  LiveIntelRoomStatus? _findStatusByUid(int uid) {
    for (final item in roomStatuses) {
      if (item.uid == uid) {
        return item;
      }
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    keywordGroups.assignAll(
      Pref.liveIntelKeywordGroups.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    _ensureCurrentRoomPlaceholder();
    for (final item in seedMessages) {
      ingestRealtimeDanmaku(item, fromSeed: true);
    }
    if (initialTrueOnline != null) {
      _updateCurrentRoom(trueOnline: initialTrueOnline);
    }
    _danmakuSubscription = LiveIntelBusService.instance
        .danmakuStream(heroTag)
        .listen(ingestRealtimeDanmaku);
    _onlineSubscription = LiveIntelBusService.instance
        .onlineStream(heroTag)
        .listen((count) => _updateCurrentRoom(trueOnline: count));
    refreshAll();
  }

  @override
  void onClose() {
    _danmakuSubscription?.cancel();
    _onlineSubscription?.cancel();
    super.onClose();
  }

  Future<void> refreshAll() async {
    if (isLoading.value) {
      return;
    }
    isLoading.value = true;
    loadError.value = null;
    try {
      _prepareForRefresh();
      final baseInfo = await _bootstrapCurrentRoom();
      if (baseInfo != null) {
        await _scanAndCaptureAreaRooms();
      } else {
        _rebuildSummary();
      }
      lastRefreshAt.value = DateTime.now();
    } catch (e) {
      loadError.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void ingestRealtimeDanmaku(
    DanmakuMsg msg, {
    bool fromSeed = false,
  }) {
    final matchedKeywords = _matchKeywords(msg.text);
    final key = _commentKey(roomId, msg.extra.id);
    final currentTitle = _currentRoom?.title ?? initialRoomTitle;
    final currentOwner = _currentRoom?.uname ?? initialRoomOwner;
    if (!_seenCommentKeys.add(key)) {
      return;
    }
    comments.insert(
      0,
      LiveIntelCommentItem(
        id: key,
        roomId: roomId,
        roomTitle: currentTitle.isNotEmpty ? currentTitle : initialRoomTitle,
        roomOwner: currentOwner.isNotEmpty ? currentOwner : initialRoomOwner,
        userId: _safeInt(msg.extra.mid) ?? 0,
        userName: msg.name,
        text: msg.text,
        source: LiveIntelCommentSource.realtime,
        capturedAt: DateTime.now(),
        rawPayload: Utils.jsonEncoder.convert(msg.toJson()),
        matchedKeywords: matchedKeywords,
      ),
    );
    final current = _currentRoom;
    if (current != null) {
      _upsertStatus(
        current.copyWith(
          realtimeCommentCount: current.realtimeCommentCount + 1,
          matchedCommentCount:
              current.matchedCommentCount + (matchedKeywords.isNotEmpty ? 1 : 0),
        ),
      );
      if (!fromSeed) {
        RequestDebugService.instance.recordManual(
          label: '实时弹幕 ${msg.name}',
          category: 'ws',
          method: 'WS',
          url: 'live://$roomId/danmaku',
          responsePreview: msg.text,
        );
      }
    }
    _rebuildSummary();
  }

  void addKeyword(String group, String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final list = List<String>.from(keywordGroups[group] ?? const <String>[]);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      keywordGroups[group] = list;
      _persistKeywordGroups();
    }
  }

  void removeKeyword(String group, String keyword) {
    final list = List<String>.from(keywordGroups[group] ?? const <String>[]);
    list.remove(keyword);
    if (list.isEmpty) {
      keywordGroups.remove(group);
    } else {
      keywordGroups[group] = list;
    }
    _persistKeywordGroups();
  }

  void addGroup(String group) {
    final trimmed = group.trim();
    if (trimmed.isEmpty || keywordGroups.containsKey(trimmed)) {
      return;
    }
    keywordGroups[trimmed] = <String>[];
    _persistKeywordGroups();
  }

  Future<void> updateSampling({
    required int nextPageLimit,
    required int nextRoomLimit,
    required int nextPageSize,
  }) async {
    Pref.liveIntelAreaPageLimit = nextPageLimit;
    Pref.liveIntelAreaRoomLimit = nextRoomLimit;
    Pref.liveIntelAreaPageSize = nextPageSize;
    await refreshAll();
  }

  Future<Map<String, dynamic>?> _bootstrapCurrentRoom() async {
    final res = await LiveHttp.liveRoomBaseInfo(
      roomId: roomId,
      options: _debugOptions('当前房间基础信息'),
    );
    if (res case Success(:final response)) {
      _parentAreaId = _safeInt(response['parent_area_id'] ?? response['area_v2_parent_id']);
      _areaId = _safeInt(response['area_id'] ?? response['area_v2_id']);
      _areaName = response['area_name']?.toString() ?? _areaName;
      final current = (_currentRoom ??
              LiveIntelRoomStatus(
                roomId: roomId,
                uid: _safeInt(response['uid']) ?? 0,
                title: initialRoomTitle,
                uname: initialRoomOwner,
                areaName: _areaName,
                historyState: LiveIntelFetchState.idle,
                isCurrentRoom: true,
              ))
          .copyWith(
            uid: _safeInt(response['uid']) ?? _currentRoom?.uid ?? 0,
            title: response['title']?.toString() ?? initialRoomTitle,
            uname: response['uname']?.toString() ?? initialRoomOwner,
            areaName: _areaName,
            displayOnline: _safeInt(response['online']),
            cover: response['user_cover']?.toString(),
            keyframe: response['keyframe']?.toString(),
            isCurrentRoom: true,
          );
      _upsertStatus(current);
      if (current.uid > 0) {
        await _applyBatchStatus([current.uid]);
      }
      await _captureSingleRoom(current.roomId);
      return response;
    }
    loadError.value = res.toString();
    _upsertStatus(
      (_currentRoom ??
              LiveIntelRoomStatus(
                roomId: roomId,
                uid: 0,
                title: initialRoomTitle,
                uname: initialRoomOwner,
                areaName: _areaName,
                historyState: LiveIntelFetchState.failed,
                isCurrentRoom: true,
              ))
          .copyWith(
            historyState: LiveIntelFetchState.failed,
            lastError: res.toString(),
          ),
    );
    return null;
  }

  Future<void> _scanAndCaptureAreaRooms() async {
    if (_areaId == null || _parentAreaId == null) {
      return;
    }
    final cards = await _fetchAreaRooms();
    final currentStatus = _currentRoom;
    final nextStatuses = <LiveIntelRoomStatus>[
      if (currentStatus != null) currentStatus,
      ...cards
          .where((item) => item.roomid != null && item.roomid != roomId)
          .map(
            (item) => LiveIntelRoomStatus(
              roomId: item.roomid!,
              uid: item.uid ?? 0,
              title: item.title ?? '',
              uname: item.uname ?? '',
              areaName: item.areaName ?? _areaName,
              historyState: LiveIntelFetchState.idle,
            ),
          ),
    ];
    roomStatuses.assignAll(nextStatuses);
    _sortStatuses();
    final batchUids = nextStatuses
        .map((item) => item.uid)
        .where((item) => item > 0)
        .toSet()
        .toList();
    await _applyBatchStatus(batchUids);
    for (final status in List<LiveIntelRoomStatus>.from(roomStatuses)) {
      if (status.isCurrentRoom) {
        continue;
      }
      await _captureSingleRoom(status.roomId);
    }
    _rebuildSummary();
  }

  Future<List<CardLiveItem>> _fetchAreaRooms() async {
    final result = <int, CardLiveItem>{};
    int? totalCount;
    for (int page = 1; page <= pageLimit; page++) {
      final res = await LiveHttp.liveSecondList(
        pn: page,
        areaId: _areaId,
        parentAreaId: _parentAreaId,
        pageSize: pageSize,
        options: _debugOptions('分区房间列表 p$page'),
      );
      if (res case Success(:final response)) {
        totalCount ??= response.count;
        final list = response.cardList ?? const <CardLiveItem>[];
        for (final item in list) {
          final rid = item.roomid;
          if (rid == null) {
            continue;
          }
          result.putIfAbsent(rid, () => item);
          if (result.length >= roomLimit) {
            break;
          }
        }
        if (list.length < pageSize || result.length >= roomLimit) {
          break;
        }
      } else {
        loadError.value ??= res.toString();
        break;
      }
    }
    _totalRoomCount = totalCount ?? result.length;
    _discoveredRoomCount = result.length;
    _discoveredUpCount = result.values
        .map((item) => item.uid)
        .whereType<int>()
        .toSet()
        .length;
    return result.values.take(roomLimit).toList();
  }

  Future<void> _applyBatchStatus(List<int> uids) async {
    if (uids.isEmpty) {
      return;
    }
    for (final chunk in _chunk(uids, 50)) {
      final res = await LiveHttp.liveRoomStatusByUids(
        uids: chunk,
        options: _debugOptions('批量房间状态 ${chunk.length}'),
      );
      if (res case Success(:final response)) {
        response.forEach((key, value) {
          final uid = _safeInt(value['uid']) ?? int.tryParse(key);
          final status = uid == null ? null : _findStatusByUid(uid);
          if (status == null) {
            return;
          }
          _upsertStatus(
            status.copyWith(
              displayOnline: _safeInt(value['online']),
              cover: value['cover_from_user']?.toString() ?? value['cover']?.toString(),
              keyframe: value['keyframe']?.toString(),
            ),
          );
        });
      }
    }
  }

  Future<void> _captureSingleRoom(int targetRoomId) async {
    final status = _findStatusByRoomId(targetRoomId);
    if (status == null) {
      return;
    }
    _upsertStatus(
      status.copyWith(
        historyState: LiveIntelFetchState.loading,
        lastError: null,
        clearError: true,
      ),
    );
    await Future.wait([
      _fetchOnlineMetric(targetRoomId),
      _fetchFollowerMetric(targetRoomId),
      _fetchGuardMetric(targetRoomId),
    ]);
    await _fetchHistoryComments(targetRoomId);
  }

  Future<void> _fetchOnlineMetric(int targetRoomId) async {
    final status = _findStatusByRoomId(targetRoomId);
    if (status == null || status.uid == 0) {
      return;
    }
    final res = await LiveHttp.liveOnlineGoldRank(
      roomId: status.roomId,
      ruid: status.uid,
      pageSize: 1,
      options: _debugOptions('高能观众 ${status.roomId}'),
    );
    if (res case Success(:final response)) {
      final latest = _findStatusByRoomId(targetRoomId);
      if (latest == null) {
        return;
      }
      _upsertStatus(
        latest.copyWith(
          trueOnline: _safeInt(response['onlineNum']) ?? latest.trueOnline,
        ),
      );
    }
  }

  Future<void> _fetchFollowerMetric(int targetRoomId) async {
    final status = _findStatusByRoomId(targetRoomId);
    if (status == null || status.uid == 0) {
      return;
    }
    final res = await LiveHttp.liveMasterInfo(
      uid: status.uid,
      options: _debugOptions('主播信息 ${status.uid}'),
    );
    if (res case Success(:final response)) {
      final latest = _findStatusByRoomId(targetRoomId);
      if (latest == null) {
        return;
      }
      _upsertStatus(
        latest.copyWith(
          followerCount: _safeInt(response['follower_num']),
        ),
      );
    }
  }

  Future<void> _fetchGuardMetric(int targetRoomId) async {
    final status = _findStatusByRoomId(targetRoomId);
    if (status == null || status.uid == 0) {
      return;
    }
    final res = await LiveHttp.liveGuardTopList(
      roomId: status.roomId,
      ruid: status.uid,
      pageSize: 1,
      options: _debugOptions('大航海统计 ${status.roomId}'),
    );
    if (res case Success(:final response)) {
      final info = response['info'];
      final latest = _findStatusByRoomId(targetRoomId);
      if (latest == null) {
        return;
      }
      _upsertStatus(
        latest.copyWith(
          guardCount: info is Map ? _safeInt(info['num']) : latest.guardCount,
        ),
      );
    }
  }

  Future<void> _fetchHistoryComments(int targetRoomId) async {
    final status = _findStatusByRoomId(targetRoomId);
    if (status == null) {
      return;
    }
    final res = await LiveHttp.liveRoomDmPrefetchRaw(
      roomId: targetRoomId,
      options: _debugOptions('历史弹幕 ${status.roomId}'),
    );
    if (res case Success(:final response)) {
      final latest = _findStatusByRoomId(targetRoomId);
      if (latest == null) {
        return;
      }
      final roomList = response['room'];
      int added = 0;
      int matched = 0;
      if (roomList is List) {
        for (final item in roomList) {
          if (item is! Map) {
            continue;
          }
          final json = Map<String, dynamic>.from(item);
          final msg = DanmakuMsg.fromPrefetch(json);
          final commentKey = _commentKey(status.roomId, msg.extra.id);
          if (!_seenCommentKeys.add(commentKey)) {
            continue;
          }
          final matchedKeywords = _matchKeywords(msg.text);
          if (matchedKeywords.isNotEmpty) {
            matched++;
          }
          added++;
          comments.add(
            LiveIntelCommentItem(
              id: commentKey,
              roomId: status.roomId,
              roomTitle: latest.title,
              roomOwner: latest.uname,
              userId: _safeInt(msg.extra.mid) ?? 0,
              userName: msg.name,
              text: msg.text,
              source: LiveIntelCommentSource.history,
              capturedAt: DateTime.fromMillisecondsSinceEpoch(
                (_safeInt(msg.extra.ts) ?? DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
              ),
              rawPayload: Utils.jsonEncoder.convert(json),
              matchedKeywords: matchedKeywords,
            ),
          );
        }
      }
      comments.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      _upsertStatus(
        latest.copyWith(
          historyState: LiveIntelFetchState.success,
          historyCommentCount: added,
          matchedCommentCount: latest.matchedCommentCount + matched,
          clearError: true,
        ),
      );
    } else {
      final latest = _findStatusByRoomId(targetRoomId);
      if (latest == null) {
        return;
      }
      _upsertStatus(
        latest.copyWith(
          historyState: LiveIntelFetchState.failed,
          lastError: res.toString(),
        ),
      );
    }
    _rebuildSummary();
  }

  void _prepareForRefresh() {
    comments.removeWhere((item) => item.source == LiveIntelCommentSource.history);
    _seenCommentKeys
      ..clear()
      ..addAll(
        comments.map((item) => item.id),
      );
    roomStatuses.assignAll(
      roomStatuses.map(
        (item) => item.copyWith(
          historyState: LiveIntelFetchState.idle,
          historyCommentCount: 0,
          matchedCommentCount: item.realtimeCommentCount > 0
              ? comments
                  .where(
                    (comment) =>
                        comment.roomId == item.roomId &&
                        comment.source == LiveIntelCommentSource.realtime &&
                        comment.matchedKeywords.isNotEmpty,
                  )
                  .length
              : 0,
          lastError: null,
          clearError: true,
        ),
      ),
    );
  }

  void _rebuildSummary() {
    summary.value = LiveIntelAreaSummary(
      parentAreaId: _parentAreaId ?? 0,
      areaId: _areaId ?? 0,
      areaName: _areaName,
      pageLimit: pageLimit,
      pageSize: pageSize,
      roomLimit: roomLimit,
      totalRoomCount: _totalRoomCount,
      discoveredRoomCount: _discoveredRoomCount,
      discoveredUpCount: _discoveredUpCount,
      monitoredRoomCount: roomStatuses.length,
      historySuccessCount: roomStatuses
          .where((item) => item.historyState == LiveIntelFetchState.success)
          .length,
      historyFailedCount: roomStatuses
          .where((item) => item.historyState == LiveIntelFetchState.failed)
          .length,
      totalCommentCount: roomStatuses.fold<int>(
        0,
        (sum, item) => sum + item.totalCommentCount,
      ),
      totalMatchedCount: roomStatuses.fold<int>(
        0,
        (sum, item) => sum + item.matchedCommentCount,
      ),
    );
  }

  void _ensureCurrentRoomPlaceholder() {
    final placeholder = LiveIntelRoomStatus(
      roomId: roomId,
      uid: 0,
      title: initialRoomTitle,
      uname: initialRoomOwner,
      areaName: _areaName,
      historyState: LiveIntelFetchState.idle,
      isCurrentRoom: true,
      trueOnline: initialTrueOnline,
    );
    roomStatuses.assignAll([placeholder]);
  }

  void _persistKeywordGroups() {
    Pref.liveIntelKeywordGroups = keywordGroups.map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
  }

  void _updateCurrentRoom({
    int? trueOnline,
  }) {
    final current = _currentRoom;
    if (current == null) {
      return;
    }
    _upsertStatus(
      current.copyWith(
        trueOnline: trueOnline ?? current.trueOnline,
      ),
    );
    _rebuildSummary();
  }

  LiveIntelRoomStatus? get _currentRoom =>
      _findStatusByRoomId(roomId);

  void _upsertStatus(LiveIntelRoomStatus next) {
    final index = roomStatuses.indexWhere((item) => item.roomId == next.roomId);
    if (index == -1) {
      roomStatuses.add(next);
    } else {
      roomStatuses[index] = next;
    }
    _sortStatuses();
  }

  void _sortStatuses() {
    roomStatuses.sort((a, b) {
      if (a.isCurrentRoom != b.isCurrentRoom) {
        return a.isCurrentRoom ? -1 : 1;
      }
      return (b.trueOnline ?? -1).compareTo(a.trueOnline ?? -1);
    });
  }

  List<String> _matchKeywords(String text) {
    final lower = text.toLowerCase();
    final result = <String>{};
    keywordGroups.forEach((group, words) {
      for (final word in words) {
        final keyword = word.trim();
        if (keyword.isEmpty) {
          continue;
        }
        if (lower.contains(keyword.toLowerCase())) {
          result.add('$group:$keyword');
        }
      }
    });
    return result.toList();
  }

  String _commentKey(int roomId, Object id) => '$roomId:$id';

  int? _safeInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  List<List<int>> _chunk(List<int> values, int size) {
    final result = <List<int>>[];
    for (int i = 0; i < values.length; i += size) {
      result.add(values.sublist(i, i + size > values.length ? values.length : i + size));
    }
    return result;
  }

  List<LiveIntelRoomStatus> _rankBy(
    List<LiveIntelRoomStatus> items, {
    required int? Function(LiveIntelRoomStatus item) selector,
  }) {
    final list = items.where((item) => selector(item) != null).toList();
    list.sort((a, b) => (selector(b) ?? -1).compareTo(selector(a) ?? -1));
    return list;
  }

  Options _debugOptions(String label) => Options(
    extra: {
      'debugLabel': label,
      'debugCategory': 'live_intel',
    },
  );
}
