enum LiveIntelCommentSource {
  realtime('实时'),
  history('历史');

  const LiveIntelCommentSource(this.label);
  final String label;
}

enum LiveIntelFetchState {
  idle('待抓取'),
  loading('抓取中'),
  success('已抓取'),
  failed('失败'),
  skipped('跳过');

  const LiveIntelFetchState(this.label);
  final String label;
}

class LiveIntelCommentItem {
  const LiveIntelCommentItem({
    required this.id,
    required this.roomId,
    required this.roomTitle,
    required this.roomOwner,
    required this.userId,
    required this.userName,
    required this.text,
    required this.source,
    required this.capturedAt,
    this.rawPayload,
    this.matchedKeywords = const <String>[],
  });

  final String id;
  final int roomId;
  final String roomTitle;
  final String roomOwner;
  final int userId;
  final String userName;
  final String text;
  final LiveIntelCommentSource source;
  final DateTime capturedAt;
  final String? rawPayload;
  final List<String> matchedKeywords;
}

class LiveIntelRoomStatus {
  const LiveIntelRoomStatus({
    required this.roomId,
    required this.uid,
    required this.title,
    required this.uname,
    required this.areaName,
    required this.historyState,
    this.isCurrentRoom = false,
    this.displayOnline,
    this.trueOnline,
    this.guardCount,
    this.followerCount,
    this.cover,
    this.keyframe,
    this.realtimeCommentCount = 0,
    this.historyCommentCount = 0,
    this.matchedCommentCount = 0,
    this.lastError,
  });

  final int roomId;
  final int uid;
  final String title;
  final String uname;
  final String areaName;
  final LiveIntelFetchState historyState;
  final bool isCurrentRoom;
  final int? displayOnline;
  final int? trueOnline;
  final int? guardCount;
  final int? followerCount;
  final String? cover;
  final String? keyframe;
  final int realtimeCommentCount;
  final int historyCommentCount;
  final int matchedCommentCount;
  final String? lastError;

  int get totalCommentCount => realtimeCommentCount + historyCommentCount;

  LiveIntelRoomStatus copyWith({
    int? uid,
    String? title,
    String? uname,
    String? areaName,
    LiveIntelFetchState? historyState,
    bool? isCurrentRoom,
    int? displayOnline,
    int? trueOnline,
    int? guardCount,
    int? followerCount,
    String? cover,
    String? keyframe,
    int? realtimeCommentCount,
    int? historyCommentCount,
    int? matchedCommentCount,
    String? lastError,
    bool clearError = false,
  }) {
    return LiveIntelRoomStatus(
      roomId: roomId,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      uname: uname ?? this.uname,
      areaName: areaName ?? this.areaName,
      historyState: historyState ?? this.historyState,
      isCurrentRoom: isCurrentRoom ?? this.isCurrentRoom,
      displayOnline: displayOnline ?? this.displayOnline,
      trueOnline: trueOnline ?? this.trueOnline,
      guardCount: guardCount ?? this.guardCount,
      followerCount: followerCount ?? this.followerCount,
      cover: cover ?? this.cover,
      keyframe: keyframe ?? this.keyframe,
      realtimeCommentCount: realtimeCommentCount ?? this.realtimeCommentCount,
      historyCommentCount: historyCommentCount ?? this.historyCommentCount,
      matchedCommentCount: matchedCommentCount ?? this.matchedCommentCount,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class LiveIntelAreaSummary {
  const LiveIntelAreaSummary({
    required this.parentAreaId,
    required this.areaId,
    required this.areaName,
    required this.pageLimit,
    required this.pageSize,
    required this.roomLimit,
    required this.totalRoomCount,
    required this.discoveredRoomCount,
    required this.discoveredUpCount,
    required this.monitoredRoomCount,
    required this.historySuccessCount,
    required this.historyFailedCount,
    required this.totalCommentCount,
    required this.totalMatchedCount,
  });

  final int parentAreaId;
  final int areaId;
  final String areaName;
  final int pageLimit;
  final int pageSize;
  final int roomLimit;
  final int totalRoomCount;
  final int discoveredRoomCount;
  final int discoveredUpCount;
  final int monitoredRoomCount;
  final int historySuccessCount;
  final int historyFailedCount;
  final int totalCommentCount;
  final int totalMatchedCount;
}
