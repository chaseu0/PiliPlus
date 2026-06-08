import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/live/live_area_list/area_item.dart';
import 'package:PiliPlus/models_new/live/live_area_list/area_list.dart';
import 'package:PiliPlus/models_new/live/live_danmaku/danmaku_msg.dart';
import 'package:PiliPlus/models_new/live/live_feed_index/card_data_list_item.dart';
import 'package:PiliPlus/services/request_debug.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum LiveMonitorFetchState {
  idle('待抓取'),
  loading('抓取中'),
  success('已抓取'),
  failed('失败');

  const LiveMonitorFetchState(this.label);
  final String label;
}

class LiveMonitorAreaOption {
  const LiveMonitorAreaOption({
    required this.parentAreaId,
    required this.areaId,
    required this.groupName,
    required this.areaName,
    this.iconUrl,
    this.reportedTotalRoomCount = 0,
    this.monitoredRoomCount = 0,
    this.lastRefreshAt,
  });

  final int parentAreaId;
  final int areaId;
  final String groupName;
  final String areaName;
  final String? iconUrl;
  final int reportedTotalRoomCount;
  final int monitoredRoomCount;
  final DateTime? lastRefreshAt;

  String get label => '$areaName · $groupName';

  LiveMonitorAreaOption copyWith({
    String? groupName,
    String? areaName,
    String? iconUrl,
    int? reportedTotalRoomCount,
    int? monitoredRoomCount,
    DateTime? lastRefreshAt,
  }) {
    return LiveMonitorAreaOption(
      parentAreaId: parentAreaId,
      areaId: areaId,
      groupName: groupName ?? this.groupName,
      areaName: areaName ?? this.areaName,
      iconUrl: iconUrl ?? this.iconUrl,
      reportedTotalRoomCount:
          reportedTotalRoomCount ?? this.reportedTotalRoomCount,
      monitoredRoomCount: monitoredRoomCount ?? this.monitoredRoomCount,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
    );
  }
}

class LiveMonitorRoomRecord {
  const LiveMonitorRoomRecord({
    required this.roomId,
    required this.parentAreaId,
    required this.areaId,
    required this.uid,
    required this.title,
    required this.uname,
    required this.areaName,
    required this.fetchState,
    this.displayOnline,
    this.roomOnline,
    this.activeOnline,
    this.watchedText,
    this.followerCount,
    this.guardCount,
    this.cover,
    this.keyframe,
    this.totalCommentCount = 0,
    this.matchedCommentCount = 0,
    this.lastError,
    this.lastMetricsAt,
    this.lastCommentAt,
    this.lastSeenAt,
  });

  final int roomId;
  final int parentAreaId;
  final int areaId;
  final int uid;
  final String title;
  final String uname;
  final String areaName;
  final LiveMonitorFetchState fetchState;
  final int? displayOnline;
  final int? roomOnline;
  final int? activeOnline;
  final String? watchedText;
  final int? followerCount;
  final int? guardCount;
  final String? cover;
  final String? keyframe;
  final int totalCommentCount;
  final int matchedCommentCount;
  final String? lastError;
  final DateTime? lastMetricsAt;
  final DateTime? lastCommentAt;
  final DateTime? lastSeenAt;

  bool get hasFrame => (keyframe ?? '').isNotEmpty || (cover ?? '').isNotEmpty;
  bool get hasMatchedComments => matchedCommentCount > 0;
  bool get hasMetrics =>
      displayOnline != null ||
      roomOnline != null ||
      activeOnline != null ||
      followerCount != null ||
      guardCount != null;

  List<String> get missingFields {
    final missing = <String>[];
    if (!hasFrame) {
      missing.add('frame');
    }
    if (displayOnline == null) {
      missing.add('display_online');
    }
    if (roomOnline == null) {
      missing.add('room_online');
    }
    if (activeOnline == null) {
      missing.add('active_online');
    }
    if (followerCount == null) {
      missing.add('follower_count');
    }
    if (guardCount == null) {
      missing.add('guard_count');
    }
    if (lastCommentAt == null && totalCommentCount <= 0) {
      missing.add('comments');
    }
    return missing;
  }

  double get coverageRatio {
    int ready = 0;
    if (hasFrame) ready++;
    if (displayOnline != null) ready++;
    if (roomOnline != null) ready++;
    if (activeOnline != null) ready++;
    if (followerCount != null) ready++;
    if (guardCount != null) ready++;
    if (lastCommentAt != null || totalCommentCount > 0) ready++;
    return ready / 7;
  }

  int get rankingScore => activeOnline ?? roomOnline ?? displayOnline ?? 0;

  LiveMonitorRoomRecord copyWith({
    int? parentAreaId,
    int? areaId,
    int? uid,
    String? title,
    String? uname,
    String? areaName,
    LiveMonitorFetchState? fetchState,
    int? displayOnline,
    int? roomOnline,
    int? activeOnline,
    String? watchedText,
    int? followerCount,
    int? guardCount,
    String? cover,
    String? keyframe,
    int? totalCommentCount,
    int? matchedCommentCount,
    String? lastError,
    bool clearError = false,
    DateTime? lastMetricsAt,
    DateTime? lastCommentAt,
    DateTime? lastSeenAt,
  }) {
    return LiveMonitorRoomRecord(
      roomId: roomId,
      parentAreaId: parentAreaId ?? this.parentAreaId,
      areaId: areaId ?? this.areaId,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      uname: uname ?? this.uname,
      areaName: areaName ?? this.areaName,
      fetchState: fetchState ?? this.fetchState,
      displayOnline: displayOnline ?? this.displayOnline,
      roomOnline: roomOnline ?? this.roomOnline,
      activeOnline: activeOnline ?? this.activeOnline,
      watchedText: watchedText ?? this.watchedText,
      followerCount: followerCount ?? this.followerCount,
      guardCount: guardCount ?? this.guardCount,
      cover: cover ?? this.cover,
      keyframe: keyframe ?? this.keyframe,
      totalCommentCount: totalCommentCount ?? this.totalCommentCount,
      matchedCommentCount: matchedCommentCount ?? this.matchedCommentCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastMetricsAt: lastMetricsAt ?? this.lastMetricsAt,
      lastCommentAt: lastCommentAt ?? this.lastCommentAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'room_id': roomId,
      'parent_area_id': parentAreaId,
      'area_id': areaId,
      'uid': uid,
      'title': title,
      'uname': uname,
      'area_name': areaName,
      'display_online': displayOnline,
      'room_online': roomOnline,
      'active_online': activeOnline,
      'watched_text': watchedText,
      'follower_count': followerCount,
      'guard_count': guardCount,
      'cover': cover,
      'keyframe': keyframe,
      'total_comment_count': totalCommentCount,
      'matched_comment_count': matchedCommentCount,
      'fetch_state': fetchState.name,
      'last_error': lastError,
      'last_metrics_at': lastMetricsAt?.millisecondsSinceEpoch,
      'last_comment_at': lastCommentAt?.millisecondsSinceEpoch,
      'last_seen_at': lastSeenAt?.millisecondsSinceEpoch,
    };
  }

  factory LiveMonitorRoomRecord.fromMap(Map<String, Object?> map) {
    return LiveMonitorRoomRecord(
      roomId: _asInt(map['room_id']),
      parentAreaId: _asInt(map['parent_area_id']),
      areaId: _asInt(map['area_id']),
      uid: _asInt(map['uid']),
      title: (map['title'] ?? '').toString(),
      uname: (map['uname'] ?? '').toString(),
      areaName: (map['area_name'] ?? '').toString(),
      displayOnline: _asNullableInt(map['display_online']),
      roomOnline: _asNullableInt(map['room_online']),
      activeOnline: _asNullableInt(map['active_online']),
      watchedText: map['watched_text']?.toString(),
      followerCount: _asNullableInt(map['follower_count']),
      guardCount: _asNullableInt(map['guard_count']),
      cover: map['cover']?.toString(),
      keyframe: map['keyframe']?.toString(),
      totalCommentCount: _asInt(map['total_comment_count']),
      matchedCommentCount: _asInt(map['matched_comment_count']),
      fetchState: LiveMonitorFetchState.values.firstWhere(
        (item) => item.name == map['fetch_state'],
        orElse: () => LiveMonitorFetchState.idle,
      ),
      lastError: map['last_error']?.toString(),
      lastMetricsAt: _asDateTime(map['last_metrics_at']),
      lastCommentAt: _asDateTime(map['last_comment_at']),
      lastSeenAt: _asDateTime(map['last_seen_at']),
    );
  }
}

class LiveMonitorCommentRecord {
  const LiveMonitorCommentRecord({
    required this.id,
    required this.parentAreaId,
    required this.areaId,
    required this.roomId,
    required this.roomTitle,
    required this.roomOwner,
    required this.userId,
    required this.userName,
    required this.text,
    required this.source,
    required this.capturedAt,
    required this.matchedKeywords,
    this.rawPayload,
  });

  final String id;
  final int parentAreaId;
  final int areaId;
  final int roomId;
  final String roomTitle;
  final String roomOwner;
  final int userId;
  final String userName;
  final String text;
  final String source;
  final DateTime capturedAt;
  final List<String> matchedKeywords;
  final String? rawPayload;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'parent_area_id': parentAreaId,
      'area_id': areaId,
      'room_id': roomId,
      'room_title': roomTitle,
      'room_owner': roomOwner,
      'user_id': userId,
      'user_name': userName,
      'text': text,
      'source': source,
      'captured_at': capturedAt.millisecondsSinceEpoch,
      'matched_keywords': jsonEncode(matchedKeywords),
      'raw_payload': rawPayload,
    };
  }

  factory LiveMonitorCommentRecord.fromMap(Map<String, Object?> map) {
    final raw = map['matched_keywords']?.toString();
    List<String> matchedKeywords = const <String>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        matchedKeywords = List<String>.from(jsonDecode(raw) as List);
      } catch (_) {}
    }
    return LiveMonitorCommentRecord(
      id: (map['id'] ?? '').toString(),
      parentAreaId: _asInt(map['parent_area_id']),
      areaId: _asInt(map['area_id']),
      roomId: _asInt(map['room_id']),
      roomTitle: (map['room_title'] ?? '').toString(),
      roomOwner: (map['room_owner'] ?? '').toString(),
      userId: _asInt(map['user_id']),
      userName: (map['user_name'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
      source: (map['source'] ?? '').toString(),
      capturedAt:
          _asDateTime(map['captured_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      matchedKeywords: matchedKeywords,
      rawPayload: map['raw_payload']?.toString(),
    );
  }
}

class LiveMonitorSummary {
  const LiveMonitorSummary({
    required this.totalRoomCount,
    required this.monitoredRoomCount,
    required this.uniqueUpCount,
    required this.totalCommentCount,
    required this.totalMatchedCommentCount,
    required this.matchedRoomCount,
    required this.readyFrameCount,
    required this.readyMetricCount,
    required this.failedRoomCount,
    required this.loadingRoomCount,
    this.lastAreaRefreshAt,
    this.lastRoomRefreshAt,
  });

  final int totalRoomCount;
  final int monitoredRoomCount;
  final int uniqueUpCount;
  final int totalCommentCount;
  final int totalMatchedCommentCount;
  final int matchedRoomCount;
  final int readyFrameCount;
  final int readyMetricCount;
  final int failedRoomCount;
  final int loadingRoomCount;
  final DateTime? lastAreaRefreshAt;
  final DateTime? lastRoomRefreshAt;
}

class LiveMonitorService extends GetxService {
  LiveMonitorService._();

  static LiveMonitorService get instance {
    if (Get.isRegistered<LiveMonitorService>()) {
      return Get.find<LiveMonitorService>();
    }
    return Get.put(LiveMonitorService._(), permanent: true);
  }

  static LiveMonitorService? get maybeInstance =>
      Get.isRegistered<LiveMonitorService>()
      ? Get.find<LiveMonitorService>()
      : null;

  final isInitialized = false.obs;
  final isRunning = false.obs;
  final isRefreshingArea = false.obs;
  final isRefreshingRooms = false.obs;
  final loadError = RxnString();
  final selectedArea = Rxn<LiveMonitorAreaOption>();
  final areaOptions = <LiveMonitorAreaOption>[].obs;
  final rooms = <LiveMonitorRoomRecord>[].obs;
  final comments = <LiveMonitorCommentRecord>[].obs;
  final summary = Rxn<LiveMonitorSummary>();
  final keywordGroups = <String, List<String>>{}.obs;
  final lastAreaRefreshAt = Rxn<DateTime>();
  final lastRoomRefreshAt = Rxn<DateTime>();

  Database? _db;
  Future<void>? _initFuture;
  Timer? _areaTimer;
  Timer? _roomTimer;
  int _reportedTotalRoomCountRaw = 0;
  int _roomCursor = 0;
  final List<int> _priorityRooms = <int>[];
  final Set<String> _seenCommentIds = <String>{};

  int get pageLimit => Pref.liveMonitorAreaPageLimit;
  int get roomLimit => Pref.liveMonitorAreaRoomLimit;
  int get pageSize => Pref.liveMonitorAreaPageSize;
  int get areaRefreshSeconds => Pref.liveMonitorAreaRefreshSeconds;
  int get roomRefreshSeconds => Pref.liveMonitorRoomRefreshSeconds;
  bool get showFirstFrame => Pref.liveMonitorShowFirstFrame;

  bool get hasReliableReportedRoomTotal =>
      _isReliableReportedRoomTotal(_reportedTotalRoomCountRaw);

  int get effectiveTotalRoomCount =>
      hasReliableReportedRoomTotal ? _reportedTotalRoomCountRaw : rooms.length;

  set showFirstFrame(bool value) => Pref.liveMonitorShowFirstFrame = value;

  List<RequestDebugRecord> get debugRecords => RequestDebugService
      .instance
      .records
      .where((item) => item.category == 'live_monitor' || item.category == 'ws')
      .toList();

  List<LiveMonitorRoomRecord> get followerRanking =>
      _rankRooms((item) => item.followerCount);

  List<LiveMonitorRoomRecord> get guardRanking =>
      _rankRooms((item) => item.guardCount);

  List<LiveMonitorRoomRecord> get activeRanking =>
      _rankRooms((item) => item.activeOnline ?? item.displayOnline);

  List<LiveMonitorRoomRecord> get matchedRoomRanking {
    final list = List<LiveMonitorRoomRecord>.from(rooms);
    list.sort((a, b) {
      final matchedRank = b.matchedCommentCount.compareTo(
        a.matchedCommentCount,
      );
      if (matchedRank != 0) {
        return matchedRank;
      }
      return (b.activeOnline ?? b.displayOnline ?? 0).compareTo(
        a.activeOnline ?? a.displayOnline ?? 0,
      );
    });
    return list;
  }

  Future<void> ensureInitialized() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    keywordGroups.assignAll(
      Pref.liveIntelKeywordGroups.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    await _openDatabase();
    await _hydrateSeenCommentIds();
    await _hydratePersistedSelection();
    await _refreshAreaOptionsInternal();
    if (selectedArea.value != null) {
      await _loadPersistedAreaSnapshot(
        selectedArea.value!.parentAreaId,
        selectedArea.value!.areaId,
      );
    } else if (areaOptions.isNotEmpty) {
      await _selectAreaInternal(areaOptions.first, refresh: false);
    }
    _rebuildSummary();
    isInitialized.value = true;
  }

  Future<void> startMonitoring({bool forceRefresh = true}) async {
    await ensureInitialized();
    if (selectedArea.value == null && areaOptions.isNotEmpty) {
      await selectArea(areaOptions.first, refresh: false);
    }
    if (selectedArea.value == null) {
      loadError.value = '未找到可用分区';
      return;
    }
    isRunning.value = true;
    _scheduleTimers();
    if (forceRefresh) {
      await refreshNow();
    }
  }

  Future<void> stopMonitoring() async {
    isRunning.value = false;
    _areaTimer?.cancel();
    _roomTimer?.cancel();
    _areaTimer = null;
    _roomTimer = null;
  }

  Future<void> refreshNow() async {
    await ensureInitialized();
    await _refreshAreaRooms();
    await _refreshRoomBatch();
  }

  Future<void> refreshAreaOptions() async {
    await ensureInitialized();
    await _refreshAreaOptionsInternal();
  }

  Future<void> _refreshAreaOptionsInternal() async {
    final res = await LiveHttp.liveAreaList(options: _debugOptions('直播分区列表'));
    if (res case Success(:final response)) {
      final mergedMeta = await _loadAreaMetaMap();
      final flattened = <LiveMonitorAreaOption>[];
      for (final group in response ?? const <AreaList>[]) {
        for (final area in group.areaList ?? const <AreaItem>[]) {
          final parentAreaId = _asNullableInt(area.parentId);
          final areaId = _asNullableInt(area.id);
          if (parentAreaId == null || areaId == null) {
            continue;
          }
          final key = '$parentAreaId:$areaId';
          final meta = mergedMeta[key];
          flattened.add(
            LiveMonitorAreaOption(
              parentAreaId: parentAreaId,
              areaId: areaId,
              groupName: group.name ?? area.parentName ?? '',
              areaName: area.name ?? '',
              iconUrl: area.pic,
              reportedTotalRoomCount: _asInt(
                meta?['reported_total_room_count'],
              ),
              monitoredRoomCount: _asInt(meta?['monitored_room_count']),
              lastRefreshAt: _asDateTime(meta?['last_refresh_at']),
            ),
          );
        }
      }
      areaOptions.assignAll(flattened);
      final current = selectedArea.value;
      if (current != null) {
        final matched = flattened.firstWhereOrNull(
          (item) =>
              item.parentAreaId == current.parentAreaId &&
              item.areaId == current.areaId,
        );
        if (matched != null) {
          selectedArea.value = matched;
        }
      }
    } else {
      loadError.value ??= res.toString();
    }
  }

  Future<void> selectArea(
    LiveMonitorAreaOption option, {
    bool refresh = true,
  }) async {
    await ensureInitialized();
    await _selectAreaInternal(option, refresh: refresh);
  }

  Future<void> _selectAreaInternal(
    LiveMonitorAreaOption option, {
    bool refresh = true,
  }) async {
    selectedArea.value = option;
    Pref.liveMonitorSelectedParentAreaId = option.parentAreaId;
    Pref.liveMonitorSelectedAreaId = option.areaId;
    Pref.liveMonitorSelectedAreaName = option.areaName;
    _reportedTotalRoomCountRaw = option.reportedTotalRoomCount;
    _roomCursor = 0;
    await _loadPersistedAreaSnapshot(option.parentAreaId, option.areaId);
    _rebuildSummary();
    if (refresh) {
      await refreshNow();
    }
  }

  Future<void> updateSampling({
    required int nextPageLimit,
    required int nextRoomLimit,
    required int nextPageSize,
    required int nextAreaRefreshSeconds,
    required int nextRoomRefreshSeconds,
  }) async {
    Pref.liveMonitorAreaPageLimit = nextPageLimit;
    Pref.liveMonitorAreaRoomLimit = nextRoomLimit;
    Pref.liveMonitorAreaPageSize = nextPageSize;
    Pref.liveMonitorAreaRefreshSeconds = nextAreaRefreshSeconds;
    Pref.liveMonitorRoomRefreshSeconds = nextRoomRefreshSeconds;
    if (isRunning.value) {
      _scheduleTimers();
    }
    await refreshNow();
  }

  void addKeyword(String group, String keyword) {
    final nextGroup = group.trim();
    final nextKeyword = keyword.trim();
    if (nextGroup.isEmpty || nextKeyword.isEmpty) {
      return;
    }
    final list = List<String>.from(
      keywordGroups[nextGroup] ?? const <String>[],
    );
    if (!list.contains(nextKeyword)) {
      list.add(nextKeyword);
      keywordGroups[nextGroup] = list;
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
    final nextGroup = group.trim();
    if (nextGroup.isEmpty || keywordGroups.containsKey(nextGroup)) {
      return;
    }
    keywordGroups[nextGroup] = <String>[];
    _persistKeywordGroups();
  }

  Future<void> prioritizeRoom(int roomId) async {
    if (!_priorityRooms.contains(roomId)) {
      _priorityRooms.insert(0, roomId);
    }
    await _refreshRoomBatch(forceRoomIds: <int>[roomId]);
  }

  Future<String> exportAllDataJson() async {
    await ensureInitialized();
    final db = _db!;
    final payload = {
      'metadata': {
        'exported_at': DateTime.now().toIso8601String(),
        'selected_area': selectedArea.value == null
            ? null
            : {
                'parent_area_id': selectedArea.value!.parentAreaId,
                'area_id': selectedArea.value!.areaId,
                'area_name': selectedArea.value!.areaName,
                'group_name': selectedArea.value!.groupName,
              },
        'sampling': {
          'page_limit': pageLimit,
          'room_limit': roomLimit,
          'page_size': pageSize,
          'area_refresh_seconds': areaRefreshSeconds,
          'room_refresh_seconds': roomRefreshSeconds,
        },
        'summary': summary.value == null
            ? null
            : {
                'total_room_count': summary.value!.totalRoomCount,
                'monitored_room_count': summary.value!.monitoredRoomCount,
                'unique_up_count': summary.value!.uniqueUpCount,
                'total_comment_count': summary.value!.totalCommentCount,
                'total_matched_comment_count':
                    summary.value!.totalMatchedCommentCount,
              },
      },
      'keyword_groups': keywordGroups.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
      'areas': await db.query(
        'live_monitor_area',
        orderBy: 'last_refresh_at DESC',
      ),
      'rooms': await db.query(
        'live_monitor_room',
        orderBy: 'COALESCE(active_online, display_online, 0) DESC',
      ),
      'comments': await db.query(
        'live_monitor_comment',
        orderBy: 'captured_at DESC',
      ),
      'samples': await db.query(
        'live_monitor_room_sample',
        orderBy: 'captured_at DESC',
      ),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, dynamic> buildSummaryJson() {
    final area = selectedArea.value;
    final data = summary.value;
    final reliableTotal = hasReliableReportedRoomTotal;
    final unmonitoredEstimate = data == null || !reliableTotal
        ? null
        : math.max(data.totalRoomCount - data.monitoredRoomCount, 0);
    return {
      'generated_at': DateTime.now().toIso8601String(),
      'is_initialized': isInitialized.value,
      'is_running': isRunning.value,
      'is_refreshing_area': isRefreshingArea.value,
      'is_refreshing_rooms': isRefreshingRooms.value,
      'selected_area': area == null ? null : _areaToJson(area),
      'sampling': {
        'page_limit': pageLimit,
        'room_limit': roomLimit,
        'page_size': pageSize,
        'area_refresh_seconds': areaRefreshSeconds,
        'room_refresh_seconds': roomRefreshSeconds,
      },
      'summary': data == null
          ? null
          : {
              'total_room_count': data.totalRoomCount,
              'reported_total_room_count_raw': _reportedTotalRoomCountRaw,
              'total_room_count_is_reliable': reliableTotal,
              'monitored_room_count': data.monitoredRoomCount,
              'unmonitored_room_estimate': unmonitoredEstimate,
              'unique_up_count': data.uniqueUpCount,
              'total_comment_count': data.totalCommentCount,
              'total_matched_comment_count': data.totalMatchedCommentCount,
              'matched_room_count': data.matchedRoomCount,
              'ready_frame_count': data.readyFrameCount,
              'ready_metric_count': data.readyMetricCount,
              'failed_room_count': data.failedRoomCount,
              'loading_room_count': data.loadingRoomCount,
              'last_area_refresh_at': data.lastAreaRefreshAt?.toIso8601String(),
              'last_room_refresh_at': data.lastRoomRefreshAt?.toIso8601String(),
            },
      'coverage': buildCoverageJson(),
      'rankings': {
        'followers': followerRanking.take(10).map(_roomToJson).toList(),
        'guards': guardRanking.take(10).map(_roomToJson).toList(),
        'active': activeRanking.take(10).map(_roomToJson).toList(),
        'matched': matchedRoomRanking.take(10).map(_roomToJson).toList(),
      },
      'load_error': loadError.value,
    };
  }

  List<Map<String, dynamic>> buildAreaOptionsJson() {
    return areaOptions.map(_areaToJson).toList();
  }

  Map<String, dynamic> buildCoverageJson() {
    final total = summary.value?.totalRoomCount ?? effectiveTotalRoomCount;
    final reliableTotal = hasReliableReportedRoomTotal;
    final monitored = rooms.length;
    final fieldMissing = <String, int>{
      'frame': 0,
      'display_online': 0,
      'room_online': 0,
      'active_online': 0,
      'follower_count': 0,
      'guard_count': 0,
      'comments': 0,
    };
    final staleRooms = <int>[];
    final now = DateTime.now();
    for (final room in rooms) {
      for (final field in room.missingFields) {
        fieldMissing[field] = (fieldMissing[field] ?? 0) + 1;
      }
      final recent = room.lastCommentAt ?? room.lastMetricsAt;
      if (recent == null || now.difference(recent).inMinutes >= 15) {
        staleRooms.add(room.roomId);
      }
    }
    final roomsWithMissingFields = rooms
        .where((room) => room.missingFields.isNotEmpty)
        .toList();
    final gapRooms = roomsWithMissingFields
        .where((room) => room.missingFields.isNotEmpty)
        .map(
          (room) => {
            'room_id': room.roomId,
            'uname': room.uname,
            'title': room.title,
            'missing_fields': room.missingFields,
            'coverage_ratio': room.coverageRatio,
          },
        )
        .take(120)
        .toList();
    return {
      'reported_total_room_count_raw': _reportedTotalRoomCountRaw,
      'total_room_count': total,
      'total_room_count_is_reliable': reliableTotal,
      'reported_total_room_count': total,
      'monitored_room_count': monitored,
      'unmonitored_room_estimate': reliableTotal
          ? math.max(total - monitored, 0)
          : null,
      'rooms_with_missing_fields': roomsWithMissingFields.length,
      'missing_field_counts': fieldMissing,
      'stale_room_count': staleRooms.length,
      'stale_room_ids': staleRooms.take(120).toList(),
      'rooms': gapRooms,
    };
  }

  List<Map<String, dynamic>> buildRoomsJson({
    int? limit,
    bool matchedOnly = false,
    bool missingOnly = false,
    int? roomId,
    String? keyword,
  }) {
    final needle = keyword?.trim().toLowerCase();
    Iterable<LiveMonitorRoomRecord> iterable = rooms;
    if (roomId != null) {
      iterable = iterable.where((item) => item.roomId == roomId);
    }
    if (matchedOnly) {
      iterable = iterable.where((item) => item.matchedCommentCount > 0);
    }
    if (missingOnly) {
      iterable = iterable.where((item) => item.missingFields.isNotEmpty);
    }
    if (needle != null && needle.isNotEmpty) {
      iterable = iterable.where((item) {
        final haystack = '${item.uname} ${item.title} ${item.areaName}'
            .toLowerCase();
        if (haystack.contains(needle)) {
          return true;
        }
        return comments.any(
          (comment) =>
              comment.roomId == item.roomId &&
              (comment.text.toLowerCase().contains(needle) ||
                  comment.matchedKeywords.any(
                    (word) => word.toLowerCase().contains(needle),
                  )),
        );
      });
    }
    final data = iterable.map(_roomToJson).toList();
    if (limit != null && limit > 0 && data.length > limit) {
      return data.take(limit).toList();
    }
    return data;
  }

  List<Map<String, dynamic>> buildCommentsJson({
    int? limit,
    bool matchedOnly = false,
    int? roomId,
    String? keyword,
  }) {
    final needle = keyword?.trim().toLowerCase();
    final data = comments
        .where((item) {
          if (matchedOnly && item.matchedKeywords.isEmpty) {
            return false;
          }
          if (roomId != null && item.roomId != roomId) {
            return false;
          }
          if (needle == null || needle.isEmpty) {
            return true;
          }
          return item.text.toLowerCase().contains(needle) ||
              item.userName.toLowerCase().contains(needle) ||
              item.roomTitle.toLowerCase().contains(needle) ||
              item.roomOwner.toLowerCase().contains(needle) ||
              item.matchedKeywords.any(
                (word) => word.toLowerCase().contains(needle),
              );
        })
        .map(_commentToJson)
        .toList();
    if (limit != null && limit > 0 && data.length > limit) {
      return data.take(limit).toList();
    }
    return data;
  }

  List<Map<String, dynamic>> buildDebugJson({int? limit}) {
    final data = debugRecords.map(_debugRecordToJson).toList();
    if (limit != null && limit > 0 && data.length > limit) {
      return data.take(limit).toList();
    }
    return data;
  }

  Future<void> syncRealtimeDanmaku({
    required int roomId,
    required DanmakuMsg message,
    int? uid,
    String? title,
    String? owner,
    String? areaName,
  }) async {
    await ensureInitialized();
    final area = selectedArea.value;
    if (area == null) {
      return;
    }
    final room = _ensureRoomRecord(
      roomId: roomId,
      uid: uid ?? 0,
      title: title ?? '',
      owner: owner ?? '',
      areaName: areaName ?? area.areaName,
    );
    final commentId = _commentId(room.roomId, message.extra.id);
    if (!_seenCommentIds.add(commentId)) {
      return;
    }
    final matchedKeywords = _matchKeywords(message.text);
    final item = LiveMonitorCommentRecord(
      id: commentId,
      parentAreaId: room.parentAreaId,
      areaId: room.areaId,
      roomId: room.roomId,
      roomTitle: room.title,
      roomOwner: room.uname,
      userId: _asNullableInt(message.extra.mid) ?? 0,
      userName: message.name,
      text: message.text,
      source: 'realtime',
      capturedAt: DateTime.now(),
      matchedKeywords: matchedKeywords,
      rawPayload: Utils.jsonEncoder.convert(message.toJson()),
    );
    await _insertComments(<LiveMonitorCommentRecord>[item]);
    comments.insert(0, item);
    _trimInMemoryComments();
    await _replaceRoom(
      room.copyWith(
        totalCommentCount: room.totalCommentCount + 1,
        matchedCommentCount:
            room.matchedCommentCount + (matchedKeywords.isNotEmpty ? 1 : 0),
        lastCommentAt: item.capturedAt,
        fetchState: LiveMonitorFetchState.success,
      ),
      persist: true,
      writeSample: false,
    );
    _rebuildSummary();
  }

  Future<void> syncRealtimeOnline({
    required int roomId,
    required int count,
    int? uid,
    String? title,
    String? owner,
    String? areaName,
  }) async {
    await ensureInitialized();
    final room = _ensureRoomRecord(
      roomId: roomId,
      uid: uid ?? 0,
      title: title ?? '',
      owner: owner ?? '',
      areaName: areaName ?? selectedArea.value?.areaName ?? '',
    );
    await _replaceRoom(
      room.copyWith(
        activeOnline: count,
        lastMetricsAt: DateTime.now(),
        fetchState: LiveMonitorFetchState.success,
      ),
      persist: true,
    );
    _rebuildSummary();
  }

  Future<void> _openDatabase() async {
    final baseDir = await getApplicationSupportDirectory();
    final dbPath = p.join(baseDir.path, 'piliplus_live_monitor.sqlite');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE live_monitor_area (
            parent_area_id INTEGER NOT NULL,
            area_id INTEGER NOT NULL,
            group_name TEXT NOT NULL DEFAULT '',
            area_name TEXT NOT NULL DEFAULT '',
            icon_url TEXT,
            reported_total_room_count INTEGER NOT NULL DEFAULT 0,
            monitored_room_count INTEGER NOT NULL DEFAULT 0,
            last_refresh_at INTEGER,
            PRIMARY KEY (parent_area_id, area_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE live_monitor_room (
            room_id INTEGER PRIMARY KEY,
            parent_area_id INTEGER NOT NULL,
            area_id INTEGER NOT NULL,
            uid INTEGER NOT NULL DEFAULT 0,
            title TEXT NOT NULL DEFAULT '',
            uname TEXT NOT NULL DEFAULT '',
            area_name TEXT NOT NULL DEFAULT '',
            display_online INTEGER,
            room_online INTEGER,
            active_online INTEGER,
            watched_text TEXT,
            follower_count INTEGER,
            guard_count INTEGER,
            cover TEXT,
            keyframe TEXT,
            total_comment_count INTEGER NOT NULL DEFAULT 0,
            matched_comment_count INTEGER NOT NULL DEFAULT 0,
            fetch_state TEXT NOT NULL DEFAULT 'idle',
            last_error TEXT,
            last_metrics_at INTEGER,
            last_comment_at INTEGER,
            last_seen_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE live_monitor_comment (
            id TEXT PRIMARY KEY,
            parent_area_id INTEGER NOT NULL,
            area_id INTEGER NOT NULL,
            room_id INTEGER NOT NULL,
            room_title TEXT NOT NULL DEFAULT '',
            room_owner TEXT NOT NULL DEFAULT '',
            user_id INTEGER NOT NULL DEFAULT 0,
            user_name TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL DEFAULT '',
            captured_at INTEGER NOT NULL,
            matched_keywords TEXT,
            raw_payload TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE live_monitor_room_sample (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id INTEGER NOT NULL,
            parent_area_id INTEGER NOT NULL,
            area_id INTEGER NOT NULL,
            captured_at INTEGER NOT NULL,
            display_online INTEGER,
            active_online INTEGER,
            watched_text TEXT,
            follower_count INTEGER,
            guard_count INTEGER,
            total_comment_count INTEGER NOT NULL DEFAULT 0,
            matched_comment_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_live_monitor_room_area ON live_monitor_room(parent_area_id, area_id)',
        );
        await db.execute(
          'CREATE INDEX idx_live_monitor_comment_area_time ON live_monitor_comment(parent_area_id, area_id, captured_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_live_monitor_comment_room_time ON live_monitor_comment(room_id, captured_at DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE live_monitor_room ADD COLUMN room_online INTEGER',
          );
        }
      },
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  Future<void> _hydrateSeenCommentIds() async {
    final rows = await _db!.query(
      'live_monitor_comment',
      columns: <String>['id'],
      orderBy: 'captured_at DESC',
      limit: 5000,
    );
    _seenCommentIds
      ..clear()
      ..addAll(rows.map((item) => item['id'].toString()));
  }

  Future<void> _hydratePersistedSelection() async {
    final parentAreaId = Pref.liveMonitorSelectedParentAreaId;
    final areaId = Pref.liveMonitorSelectedAreaId;
    if (parentAreaId > 0 && areaId > 0) {
      selectedArea.value = LiveMonitorAreaOption(
        parentAreaId: parentAreaId,
        areaId: areaId,
        groupName: '',
        areaName: Pref.liveMonitorSelectedAreaName,
      );
    }
  }

  Future<void> _loadPersistedAreaSnapshot(int parentAreaId, int areaId) async {
    final areaMeta = await _db!.query(
      'live_monitor_area',
      where: 'parent_area_id = ? AND area_id = ?',
      whereArgs: <Object>[parentAreaId, areaId],
      limit: 1,
    );
    if (areaMeta.isNotEmpty) {
      final meta = areaMeta.first;
      _reportedTotalRoomCountRaw = _asInt(meta['reported_total_room_count']);
      lastAreaRefreshAt.value = _asDateTime(meta['last_refresh_at']);
    } else {
      _reportedTotalRoomCountRaw = 0;
      lastAreaRefreshAt.value = null;
    }
    final roomRows = await _db!.query(
      'live_monitor_room',
      where: 'parent_area_id = ? AND area_id = ?',
      whereArgs: <Object>[parentAreaId, areaId],
      orderBy: 'COALESCE(active_online, display_online, 0) DESC',
      limit: roomLimit,
    );
    rooms.assignAll(
      roomRows.map((item) => LiveMonitorRoomRecord.fromMap(item)).toList(),
    );
    final commentRows = await _db!.query(
      'live_monitor_comment',
      where: 'parent_area_id = ? AND area_id = ?',
      whereArgs: <Object>[parentAreaId, areaId],
      orderBy: 'captured_at DESC',
      limit: 600,
    );
    comments.assignAll(
      commentRows
          .map((item) => LiveMonitorCommentRecord.fromMap(item))
          .toList(),
    );
    lastRoomRefreshAt.value = rooms
        .map((item) => item.lastCommentAt ?? item.lastMetricsAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (value, element) =>
              value == null || element.isAfter(value) ? element : value,
        );
  }

  Future<Map<String, Map<String, Object?>>> _loadAreaMetaMap() async {
    final rows = await _db!.query('live_monitor_area');
    final result = <String, Map<String, Object?>>{};
    for (final row in rows) {
      result['${row['parent_area_id']}:${row['area_id']}'] =
          Map<String, Object?>.from(row);
    }
    return result;
  }

  void _scheduleTimers() {
    _areaTimer?.cancel();
    _roomTimer?.cancel();
    if (!isRunning.value) {
      return;
    }
    _areaTimer = Timer.periodic(
      Duration(seconds: areaRefreshSeconds),
      (_) => _refreshAreaRooms(),
    );
    _roomTimer = Timer.periodic(
      Duration(seconds: roomRefreshSeconds),
      (_) => _refreshRoomBatch(),
    );
  }

  Future<void> _refreshAreaRooms() async {
    final area = selectedArea.value;
    if (area == null || isRefreshingArea.value) {
      return;
    }
    isRefreshingArea.value = true;
    loadError.value = null;
    try {
      final roomMap = <int, LiveMonitorRoomRecord>{
        for (final room in rooms) room.roomId: room,
      };
      final fetchedRooms = <int, LiveMonitorRoomRecord>{};
      int? totalCount;
      for (int page = 1; page <= pageLimit; page++) {
        final beforeCount = fetchedRooms.length;
        final res = await LiveHttp.liveSecondList(
          pn: page,
          areaId: area.areaId,
          parentAreaId: area.parentAreaId,
          pageSize: pageSize,
          options: _debugOptions('分区房间列表 p$page'),
        );
        if (res case Success(:final response)) {
          totalCount ??= response.count;
          final cards = response.cardList ?? const <CardLiveItem>[];
          for (final card in cards) {
            final roomId = card.roomid;
            if (roomId == null) {
              continue;
            }
            final existing = fetchedRooms[roomId] ?? roomMap[roomId];
            fetchedRooms[roomId] =
                (existing ??
                        LiveMonitorRoomRecord(
                          roomId: roomId,
                          parentAreaId: area.parentAreaId,
                          areaId: area.areaId,
                          uid: _asNullableInt(card.uid) ?? 0,
                          title: card.title ?? '',
                          uname: card.uname ?? '',
                          areaName: card.areaName ?? area.areaName,
                          fetchState: LiveMonitorFetchState.idle,
                        ))
                    .copyWith(
                      parentAreaId: area.parentAreaId,
                      areaId: area.areaId,
                      uid: _asNullableInt(card.uid) ?? existing?.uid ?? 0,
                      title: card.title ?? existing?.title ?? '',
                      uname: card.uname ?? existing?.uname ?? '',
                      areaName:
                          card.areaName ?? existing?.areaName ?? area.areaName,
                      cover: card.cover,
                      keyframe: card.systemCover,
                      watchedText: card.watchedShow?.textLarge,
                      lastSeenAt: DateTime.now(),
                    );
            if (fetchedRooms.length >= roomLimit) {
              break;
            }
          }
          final addedCount = fetchedRooms.length - beforeCount;
          if (cards.isEmpty ||
              addedCount <= 0 ||
              fetchedRooms.length >= roomLimit) {
            break;
          }
        } else {
          loadError.value = res.toString();
          break;
        }
      }
      if (fetchedRooms.isNotEmpty) {
        _reportedTotalRoomCountRaw = totalCount ?? 0;
        rooms.assignAll(_sortRoomList(fetchedRooms.values));
        await _writeRooms(rooms);
        await _applyBatchStatus(rooms.toList());
        await _upsertAreaMeta(
          area: area,
          reportedTotalRoomCount: _reportedTotalRoomCountRaw,
          monitoredRoomCount: rooms.length,
        );
        lastAreaRefreshAt.value = DateTime.now();
      }
    } finally {
      isRefreshingArea.value = false;
      _rebuildSummary();
    }
  }

  Future<void> _applyBatchStatus(
    List<LiveMonitorRoomRecord> targetRooms,
  ) async {
    final uids = targetRooms
        .map((item) => item.uid)
        .where((item) => item > 0)
        .toSet()
        .toList();
    for (final chunk in _chunk(uids, 50)) {
      final res = await LiveHttp.liveRoomStatusByUids(
        uids: chunk,
        options: _debugOptions('批量房间状态 ${chunk.length}'),
      );
      if (res case Success(:final response)) {
        for (final entry in response.entries) {
          final json = entry.value;
          final uid = _asNullableInt(json['uid']) ?? int.tryParse(entry.key);
          if (uid == null) {
            continue;
          }
          final room = rooms.firstWhereOrNull((item) => item.uid == uid);
          if (room == null) {
            continue;
          }
          await _replaceRoom(
            room.copyWith(
              displayOnline: _asNullableInt(json['online']),
              cover:
                  json['cover_from_user']?.toString() ??
                  json['cover']?.toString() ??
                  room.cover,
              keyframe: json['keyframe']?.toString() ?? room.keyframe,
              lastMetricsAt: DateTime.now(),
            ),
            persist: true,
          );
        }
      }
    }
  }

  Future<void> _refreshRoomBatch({List<int>? forceRoomIds}) async {
    if (isRefreshingRooms.value || rooms.isEmpty) {
      return;
    }
    isRefreshingRooms.value = true;
    loadError.value = null;
    try {
      final batchIds = forceRoomIds ?? _pickRoomBatchIds();
      for (final roomId in batchIds) {
        await _captureRoom(roomId);
        _priorityRooms.remove(roomId);
      }
      if (batchIds.isNotEmpty) {
        lastRoomRefreshAt.value = DateTime.now();
      }
    } finally {
      isRefreshingRooms.value = false;
      _rebuildSummary();
    }
  }

  List<int> _pickRoomBatchIds() {
    final int batchSize = roomLimit >= 400
        ? 16
        : roomLimit >= 200
        ? 12
        : 8;
    final nextIds = <int>[];
    for (final roomId in _priorityRooms) {
      if (rooms.any((item) => item.roomId == roomId) &&
          !nextIds.contains(roomId)) {
        nextIds.add(roomId);
      }
      if (nextIds.length >= batchSize) {
        return nextIds;
      }
    }
    final sorted = List<LiveMonitorRoomRecord>.from(rooms);
    sorted.sort((a, b) {
      final aNeeds = a.lastCommentAt == null ? 0 : 1;
      final bNeeds = b.lastCommentAt == null ? 0 : 1;
      final captureRank = aNeeds.compareTo(bNeeds);
      if (captureRank != 0) {
        return captureRank;
      }
      final stateRank = _stateRank(
        a.fetchState,
      ).compareTo(_stateRank(b.fetchState));
      if (stateRank != 0) {
        return stateRank;
      }
      return (b.activeOnline ?? b.roomOnline ?? b.displayOnline ?? 0).compareTo(
        a.activeOnline ?? a.roomOnline ?? a.displayOnline ?? 0,
      );
    });
    if (sorted.isEmpty) {
      return nextIds;
    }
    for (int i = 0; i < sorted.length && nextIds.length < batchSize; i++) {
      final index = (_roomCursor + i) % sorted.length;
      final roomId = sorted[index].roomId;
      if (!nextIds.contains(roomId)) {
        nextIds.add(roomId);
      }
    }
    _roomCursor = sorted.isEmpty
        ? 0
        : (_roomCursor + batchSize) % sorted.length;
    return nextIds;
  }

  Future<void> _captureRoom(int roomId) async {
    final room = rooms.firstWhereOrNull((item) => item.roomId == roomId);
    if (room == null) {
      return;
    }
    await _replaceRoom(
      room.copyWith(
        fetchState: LiveMonitorFetchState.loading,
        clearError: true,
      ),
      persist: true,
      writeSample: false,
    );
    final errors = <String>[];
    LiveMonitorRoomRecord current = rooms.firstWhere(
      (item) => item.roomId == roomId,
      orElse: () => room,
    );
    final roomInfoRes = await LiveHttp.liveRoomBaseInfo(
      roomId: current.roomId,
      options: _debugOptions('房间基础信息 ${current.roomId}'),
    );
    if (roomInfoRes case Success(:final response)) {
      current = current.copyWith(
        roomOnline: _asNullableInt(response['online']),
        watchedText:
            response['watched_show']?.toString() ??
            response['watched_show_text']?.toString() ??
            current.watchedText,
        cover: response['user_cover']?.toString() ?? current.cover,
        keyframe: response['keyframe']?.toString() ?? current.keyframe,
        lastMetricsAt: DateTime.now(),
      );
    } else {
      errors.add('房间基础信息: ${roomInfoRes.toString()}');
    }
    if (current.uid > 0) {
      final onlineRes = await LiveHttp.liveOnlineGoldRank(
        roomId: current.roomId,
        ruid: current.uid,
        pageSize: 1,
        options: _debugOptions('高能观众 ${current.roomId}'),
      );
      if (onlineRes case Success(:final response)) {
        current = current.copyWith(
          activeOnline: _asNullableInt(response['onlineNum']),
          lastMetricsAt: DateTime.now(),
        );
      } else {
        errors.add('高能观众: ${onlineRes.toString()}');
      }

      final followerRes = await LiveHttp.liveMasterInfo(
        uid: current.uid,
        options: _debugOptions('主播信息 ${current.uid}'),
      );
      if (followerRes case Success(:final response)) {
        current = current.copyWith(
          followerCount: _asNullableInt(response['follower_num']),
          lastMetricsAt: DateTime.now(),
        );
      } else {
        errors.add('粉丝: ${followerRes.toString()}');
      }

      final guardRes = await LiveHttp.liveGuardTopList(
        roomId: current.roomId,
        ruid: current.uid,
        pageSize: 1,
        options: _debugOptions('大航海统计 ${current.roomId}'),
      );
      if (guardRes case Success(:final response)) {
        final info = response['info'];
        current = current.copyWith(
          guardCount: info is Map
              ? _asNullableInt(info['num'])
              : current.guardCount,
          lastMetricsAt: DateTime.now(),
        );
      } else {
        errors.add('大航海: ${guardRes.toString()}');
      }
    }

    final commentRes = await LiveHttp.liveRoomDmPrefetchRaw(
      roomId: current.roomId,
      options: _debugOptions('历史弹幕 ${current.roomId}'),
    );
    int added = 0;
    int matched = 0;
    final newComments = <LiveMonitorCommentRecord>[];
    if (commentRes case Success(:final response)) {
      final roomList = response['room'];
      if (roomList is List) {
        for (final item in roomList) {
          if (item is! Map) {
            continue;
          }
          final json = Map<String, dynamic>.from(item);
          final msg = DanmakuMsg.fromPrefetch(json);
          final commentId = _commentId(current.roomId, msg.extra.id);
          if (!_seenCommentIds.add(commentId)) {
            continue;
          }
          final matchedKeywords = _matchKeywords(msg.text);
          final comment = LiveMonitorCommentRecord(
            id: commentId,
            parentAreaId: current.parentAreaId,
            areaId: current.areaId,
            roomId: current.roomId,
            roomTitle: current.title,
            roomOwner: current.uname,
            userId: _asNullableInt(msg.extra.mid) ?? 0,
            userName: msg.name,
            text: msg.text,
            source: 'history',
            capturedAt: DateTime.fromMillisecondsSinceEpoch(
              (_asNullableInt(msg.extra.ts) ??
                      DateTime.now().millisecondsSinceEpoch ~/ 1000) *
                  1000,
            ),
            matchedKeywords: matchedKeywords,
            rawPayload: Utils.jsonEncoder.convert(json),
          );
          newComments.add(comment);
          added++;
          if (matchedKeywords.isNotEmpty) {
            matched++;
          }
        }
      }
    } else {
      errors.add('评论: ${commentRes.toString()}');
    }

    if (newComments.isNotEmpty) {
      await _insertComments(newComments);
      comments.insertAll(0, newComments);
      comments.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      _trimInMemoryComments();
    }

    current = current.copyWith(
      totalCommentCount: current.totalCommentCount + added,
      matchedCommentCount: current.matchedCommentCount + matched,
      lastCommentAt: newComments.isNotEmpty
          ? newComments.first.capturedAt
          : current.lastCommentAt,
      fetchState: errors.isEmpty
          ? LiveMonitorFetchState.success
          : LiveMonitorFetchState.failed,
      lastError: errors.isEmpty ? null : errors.join('\n'),
      clearError: errors.isEmpty,
    );
    await _replaceRoom(current, persist: true);
  }

  Future<void> _insertComments(List<LiveMonitorCommentRecord> items) async {
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'live_monitor_comment',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _writeRooms(List<LiveMonitorRoomRecord> items) async {
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          'live_monitor_room',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _replaceRoom(
    LiveMonitorRoomRecord room, {
    bool persist = false,
    bool writeSample = true,
  }) async {
    final index = rooms.indexWhere((item) => item.roomId == room.roomId);
    if (index == -1) {
      rooms.add(room);
    } else {
      rooms[index] = room;
    }
    rooms.assignAll(_sortRoomList(rooms));
    if (persist) {
      await _db!.insert(
        'live_monitor_room',
        room.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (writeSample) {
        await _db!.insert('live_monitor_room_sample', {
          'room_id': room.roomId,
          'parent_area_id': room.parentAreaId,
          'area_id': room.areaId,
          'captured_at': DateTime.now().millisecondsSinceEpoch,
          'display_online': room.displayOnline,
          'active_online': room.activeOnline,
          'watched_text': room.watchedText,
          'follower_count': room.followerCount,
          'guard_count': room.guardCount,
          'total_comment_count': room.totalCommentCount,
          'matched_comment_count': room.matchedCommentCount,
        });
      }
    }
  }

  Future<void> _upsertAreaMeta({
    required LiveMonitorAreaOption area,
    required int reportedTotalRoomCount,
    required int monitoredRoomCount,
  }) async {
    final now = DateTime.now();
    await _db!.insert('live_monitor_area', {
      'parent_area_id': area.parentAreaId,
      'area_id': area.areaId,
      'group_name': area.groupName,
      'area_name': area.areaName,
      'icon_url': area.iconUrl,
      'reported_total_room_count': reportedTotalRoomCount,
      'monitored_room_count': monitoredRoomCount,
      'last_refresh_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final index = areaOptions.indexWhere(
      (item) =>
          item.parentAreaId == area.parentAreaId && item.areaId == area.areaId,
    );
    if (index != -1) {
      areaOptions[index] = areaOptions[index].copyWith(
        reportedTotalRoomCount: reportedTotalRoomCount,
        monitoredRoomCount: monitoredRoomCount,
        lastRefreshAt: now,
      );
    }
    if (selectedArea.value case final current?) {
      if (current.parentAreaId == area.parentAreaId &&
          current.areaId == area.areaId) {
        selectedArea.value = current.copyWith(
          reportedTotalRoomCount: reportedTotalRoomCount,
          monitoredRoomCount: monitoredRoomCount,
          lastRefreshAt: now,
        );
      }
    }
  }

  LiveMonitorRoomRecord _ensureRoomRecord({
    required int roomId,
    required int uid,
    required String title,
    required String owner,
    required String areaName,
  }) {
    final existing = rooms.firstWhereOrNull((item) => item.roomId == roomId);
    if (existing != null) {
      return existing;
    }
    final area = selectedArea.value;
    final room = LiveMonitorRoomRecord(
      roomId: roomId,
      parentAreaId: area?.parentAreaId ?? 0,
      areaId: area?.areaId ?? 0,
      uid: uid,
      title: title,
      uname: owner,
      areaName: areaName,
      fetchState: LiveMonitorFetchState.idle,
    );
    rooms.insert(0, room);
    return room;
  }

  void _persistKeywordGroups() {
    Pref.liveIntelKeywordGroups = keywordGroups.map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
  }

  void _trimInMemoryComments() {
    if (comments.length > 600) {
      comments.removeRange(600, comments.length);
    }
  }

  void _rebuildSummary() {
    summary.value = LiveMonitorSummary(
      totalRoomCount: effectiveTotalRoomCount,
      monitoredRoomCount: rooms.length,
      uniqueUpCount: rooms
          .map((item) => item.uid)
          .where((item) => item > 0)
          .toSet()
          .length,
      totalCommentCount: rooms.fold<int>(
        0,
        (sum, item) => sum + item.totalCommentCount,
      ),
      totalMatchedCommentCount: rooms.fold<int>(
        0,
        (sum, item) => sum + item.matchedCommentCount,
      ),
      matchedRoomCount: rooms.where((item) => item.hasMatchedComments).length,
      readyFrameCount: rooms.where((item) => item.hasFrame).length,
      readyMetricCount: rooms.where((item) => item.hasMetrics).length,
      failedRoomCount: rooms
          .where((item) => item.fetchState == LiveMonitorFetchState.failed)
          .length,
      loadingRoomCount: rooms
          .where((item) => item.fetchState == LiveMonitorFetchState.loading)
          .length,
      lastAreaRefreshAt: lastAreaRefreshAt.value,
      lastRoomRefreshAt: lastRoomRefreshAt.value,
    );
  }

  List<LiveMonitorRoomRecord> _sortRoomList(
    Iterable<LiveMonitorRoomRecord> items,
  ) {
    final list = items.toList();
    list.sort((a, b) {
      final scoreRank = (b.activeOnline ?? b.roomOnline ?? b.displayOnline ?? 0)
          .compareTo(a.activeOnline ?? a.roomOnline ?? a.displayOnline ?? 0);
      if (scoreRank != 0) {
        return scoreRank;
      }
      return b.matchedCommentCount.compareTo(a.matchedCommentCount);
    });
    return list;
  }

  List<LiveMonitorRoomRecord> _rankRooms(
    int? Function(LiveMonitorRoomRecord item) selector,
  ) {
    final list = rooms.where((item) => selector(item) != null).toList();
    list.sort((a, b) => (selector(b) ?? 0).compareTo(selector(a) ?? 0));
    return list;
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

  Options _debugOptions(String label) {
    return Options(
      extra: <String, Object>{
        'debugLabel': label,
        'debugCategory': 'live_monitor',
      },
    );
  }

  String _commentId(int roomId, Object? id) {
    final suffix = (id == null || '$id'.isEmpty)
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : '$id';
    return '$roomId:$suffix';
  }

  int _stateRank(LiveMonitorFetchState value) {
    switch (value) {
      case LiveMonitorFetchState.failed:
        return 0;
      case LiveMonitorFetchState.idle:
        return 1;
      case LiveMonitorFetchState.loading:
        return 2;
      case LiveMonitorFetchState.success:
        return 3;
    }
  }

  List<List<int>> _chunk(List<int> values, int size) {
    final result = <List<int>>[];
    for (int i = 0; i < values.length; i += size) {
      result.add(
        values.sublist(i, i + size > values.length ? values.length : i + size),
      );
    }
    return result;
  }

  Map<String, dynamic> _areaToJson(LiveMonitorAreaOption area) {
    return {
      'parent_area_id': area.parentAreaId,
      'area_id': area.areaId,
      'group_name': area.groupName,
      'area_name': area.areaName,
      'icon_url': area.iconUrl,
      'reported_total_room_count': area.reportedTotalRoomCount,
      'reported_total_room_count_is_reliable': _isReliableReportedRoomTotal(
        area.reportedTotalRoomCount,
      ),
      'monitored_room_count': area.monitoredRoomCount,
      'last_refresh_at': area.lastRefreshAt?.toIso8601String(),
      'label': area.label,
    };
  }

  bool _isReliableReportedRoomTotal(int total) {
    return total > 0 && total < 10000000;
  }

  Map<String, dynamic> _roomToJson(LiveMonitorRoomRecord room) {
    return {
      'room_id': room.roomId,
      'parent_area_id': room.parentAreaId,
      'area_id': room.areaId,
      'uid': room.uid,
      'uname': room.uname,
      'title': room.title,
      'area_name': room.areaName,
      'fetch_state': room.fetchState.name,
      'display_online': room.displayOnline,
      'room_online': room.roomOnline,
      'active_online': room.activeOnline,
      'watched_text': room.watchedText,
      'follower_count': room.followerCount,
      'guard_count': room.guardCount,
      'cover': room.cover,
      'keyframe': room.keyframe,
      'total_comment_count': room.totalCommentCount,
      'matched_comment_count': room.matchedCommentCount,
      'matched_ratio': room.totalCommentCount == 0
          ? 0
          : room.matchedCommentCount / room.totalCommentCount,
      'coverage_ratio': room.coverageRatio,
      'missing_fields': room.missingFields,
      'real_audience_hints': {
        'room_online': room.roomOnline,
        'active_online': room.activeOnline,
        'display_online': room.displayOnline,
        'watched_text': room.watchedText,
      },
      'last_error': room.lastError,
      'last_metrics_at': room.lastMetricsAt?.toIso8601String(),
      'last_comment_at': room.lastCommentAt?.toIso8601String(),
      'last_seen_at': room.lastSeenAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _commentToJson(LiveMonitorCommentRecord comment) {
    return {
      'id': comment.id,
      'parent_area_id': comment.parentAreaId,
      'area_id': comment.areaId,
      'room_id': comment.roomId,
      'room_title': comment.roomTitle,
      'room_owner': comment.roomOwner,
      'user_id': comment.userId,
      'user_name': comment.userName,
      'text': comment.text,
      'source': comment.source,
      'captured_at': comment.capturedAt.toIso8601String(),
      'matched': comment.matchedKeywords.isNotEmpty,
      'matched_keywords': comment.matchedKeywords,
      'raw_payload': comment.rawPayload,
    };
  }

  Map<String, dynamic> _debugRecordToJson(RequestDebugRecord record) {
    return {
      'id': record.id,
      'label': record.label,
      'category': record.category,
      'method': record.method,
      'url': record.url,
      'created_at': record.createdAt.toIso8601String(),
      'curl': record.curl,
      'request_body': record.requestBody,
      'response_preview': record.responsePreview,
      'error_message': record.errorMessage,
      'status_code': record.statusCode,
    };
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

int? _asNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
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

DateTime? _asDateTime(Object? value) {
  final millis = _asNullableInt(value);
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}
