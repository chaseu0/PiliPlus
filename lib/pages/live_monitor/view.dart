import 'dart:convert';

import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/services/live_monitor_api_server.dart';
import 'package:PiliPlus/services/live_monitor_service.dart';
import 'package:PiliPlus/services/request_debug.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/storage_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({super.key});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage>
    with AutomaticKeepAliveClientMixin {
  final service = LiveMonitorService.instance;
  final apiServer = LiveMonitorApiServer.instance;
  final TextEditingController _commentFilterController =
      TextEditingController();
  final TextEditingController _keywordFilterController =
      TextEditingController();

  bool onlyMatched = false;
  int? roomFilterId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    apiServer.ensureStarted();
    if (Pref.liveMonitorAutoStart) {
      service.startMonitoring();
    } else {
      service.ensureInitialized();
    }
  }

  @override
  void dispose() {
    _commentFilterController.dispose();
    _keywordFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: const Text('直播面板'),
          actions: [
            IconButton(
              tooltip: '分区设置',
              onPressed: () => _showSamplingDialog(context),
              icon: const Icon(Icons.tune),
            ),
            Obx(
              () => IconButton(
                tooltip: service.isRunning.value ? '停止监控' : '开始监控',
                onPressed: () async {
                  if (service.isRunning.value) {
                    await service.stopMonitoring();
                  } else {
                    await service.startMonitoring();
                  }
                },
                icon: Icon(
                  service.isRunning.value
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
              ),
            ),
            IconButton(
              tooltip: '立即刷新',
              onPressed: service.refreshNow,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '导出 JSON',
              onPressed: _exportAll,
              icon: const Icon(Icons.download_outlined),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '总览'),
              Tab(text: '电脑访问'),
              Tab(text: '评论'),
              Tab(text: '帧墙'),
              Tab(text: '词库'),
              Tab(text: 'Debug'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(theme),
            _buildApiTab(theme),
            _buildCommentsTab(theme),
            _buildFrameWallTab(theme),
            _buildKeywordsTab(theme),
            _buildDebugTab(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    return Obx(() {
      final summary = service.summary.value;
      final selectedArea = service.selectedArea.value;
      final rooms = service.rooms;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: Style.mdRadius,
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedArea?.areaName.isNotEmpty == true
                                ? selectedArea!.label
                                : '请选择直播分区',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '展示热度、活跃观众、累计观看、粉丝、大航海分开展示，避免把热度误当真实人数。',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showAreaPicker(context),
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('选区'),
                    ),
                  ],
                ),
                if (summary != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricChip('分区在线房间', summary.totalRoomCount),
                      _MetricChip('已监控房间', summary.monitoredRoomCount),
                      _MetricChip('已发现 UP', summary.uniqueUpCount),
                      _MetricChip(
                        '未覆盖估算',
                        (summary.totalRoomCount - summary.monitoredRoomCount)
                            .clamp(0, 999999),
                      ),
                      _MetricChip('总评论', summary.totalCommentCount),
                      _MetricChip('命中评论', summary.totalMatchedCommentCount),
                      _MetricChip('命中房间', summary.matchedRoomCount),
                      _MetricChip('可看帧', summary.readyFrameCount),
                      _MetricChip('有指标房', summary.readyMetricCount),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '分区刷新: ${_formatTime(summary.lastAreaRefreshAt)}  ·  增量抓评: ${_formatTime(summary.lastRoomRefreshAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (service.loadError.value?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    service.loadError.value!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Obx(() {
            final serverRunning = apiServer.isRunning.value;
            return Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: Style.mdRadius,
                color: theme.colorScheme.surfaceContainerLow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '电脑访问服务',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () async {
                          if (serverRunning) {
                            await apiServer.stop();
                          } else {
                            await apiServer.start();
                          }
                        },
                        child: Text(serverRunning ? '停止服务' : '启动服务'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    serverRunning
                        ? 'ADB 转发: ${apiServer.adbForwardCommand}\n电脑打开: ${apiServer.desktopUrl}'
                        : '服务尚未启动',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          _buildRankingCard(
            context,
            title: '粉丝排行',
            items: service.followerRanking.take(8).toList(),
            valueBuilder: (item) => NumUtils.numFormat(item.followerCount),
          ),
          const SizedBox(height: 12),
          _buildRankingCard(
            context,
            title: '大航海排行',
            items: service.guardRanking.take(8).toList(),
            valueBuilder: (item) => NumUtils.numFormat(item.guardCount),
          ),
          const SizedBox(height: 12),
          _buildRankingCard(
            context,
            title: '活跃观众排行',
            items: service.activeRanking.take(8).toList(),
            valueBuilder: (item) =>
                NumUtils.numFormat(item.activeOnline ?? item.displayOnline),
          ),
          const SizedBox(height: 12),
          Text('抓取覆盖面板', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...rooms.map(
            (room) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomCoverageCard(
                room: room,
                onTap: () => _showRoomDetail(context, room),
                onPrioritize: () => service.prioritizeRoom(room.roomId),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildApiTab(ThemeData theme) {
    return Obx(() {
      final summary = service.summary.value;
      final serverRunning = apiServer.isRunning.value;
      final coverage = service.buildCoverageJson();
      final missingCounts = Map<String, dynamic>.from(
        coverage['missing_field_counts'] as Map? ?? const <String, dynamic>{},
      );
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: Style.mdRadius,
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '手机内置 API 服务',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => apiServer.start(forceRestart: true),
                      child: const Text('重启服务'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip('服务状态', serverRunning ? '运行中' : '已停止'),
                    _MetricChip('端口', apiServer.boundPort.value),
                    _MetricChip('请求数', apiServer.requestCount.value),
                    _MetricChip(
                      '监控状态',
                      service.isRunning.value ? '抓取中' : '已暂停',
                    ),
                    _MetricChip(
                      '分区',
                      service.selectedArea.value?.areaName ?? '-',
                    ),
                    _MetricChip(
                      '未覆盖估算',
                      summary == null
                          ? '-'
                          : service.hasReliableReportedRoomTotal
                          ? (summary.totalRoomCount -
                                    summary.monitoredRoomCount)
                                .clamp(0, 999999)
                          : '未知',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DebugBlock(
                  title: 'ADB 转发命令',
                  value: serverRunning
                      ? apiServer.adbForwardCommand
                      : '服务未启动，暂无命令',
                ),
                _DebugBlock(
                  title: '电脑浏览器地址',
                  value: serverRunning ? apiServer.desktopUrl : '服务未启动',
                ),
                if (apiServer.lastError.value?.isNotEmpty == true)
                  _DebugBlock(title: '服务错误', value: apiServer.lastError.value!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: Style.mdRadius,
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('缺口统计', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: missingCounts.entries
                      .map((entry) => _MetricChip(entry.key, entry.value))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  '这部分会同步到电脑端页面，方便直接看到哪些字段还没抓到，以及大概还有多少房间未覆盖。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildCommentsTab(ThemeData theme) {
    return Obx(() {
      final comments = _filteredComments();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentFilterController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: '筛选评论内容 / 用户 / 房间',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => _showRoomFilterPicker(context),
                      child: Text(
                        roomFilterId == null ? '全部房间' : '房间 $roomFilterId',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordFilterController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.filter_alt_outlined),
                          hintText: '仅看命中的某个词，如 微信 / 礼物',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: onlyMatched,
                      label: const Text('仅看命中'),
                      onSelected: (value) =>
                          setState(() => onlyMatched = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: comments.isEmpty
                ? const Center(child: Text('当前筛选条件下没有评论'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final item = comments[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          onTap: () => PageUtils.toLiveRoom(item.roomId),
                          onLongPress: () => Clipboard.setData(
                            ClipboardData(text: item.rawPayload ?? item.text),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.roomOwner} · ${item.roomTitle}',
                                        style: theme.textTheme.titleSmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      _formatTime(item.capturedAt),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.userName} (${item.userId}) · ${item.source}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Text.rich(
                                  _highlightText(
                                    theme,
                                    item.text,
                                    item.matchedKeywords
                                        .map((e) => e.split(':').last)
                                        .toList(),
                                  ),
                                ),
                                if (item.matchedKeywords.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: item.matchedKeywords
                                        .map(
                                          (word) => Chip(
                                            label: Text(word),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  Widget _buildFrameWallTab(ThemeData theme) {
    return Obx(() {
      final rooms = service.activeRanking;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '长按卡片会优先抓取这个房间，然后立刻弹出详情。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                FilterChip(
                  selected: service.showFirstFrame,
                  label: Text(service.showFirstFrame ? '当前帧' : '封面'),
                  onSelected: (value) => setState(() {
                    service.showFirstFrame = value;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final imageUrl = service.showFirstFrame
                    ? ((room.keyframe ?? '').isNotEmpty
                          ? room.keyframe
                          : room.cover)
                    : room.cover;
                return Card(
                  clipBehavior: Clip.hardEdge,
                  child: InkWell(
                    onTap: () => PageUtils.toLiveRoom(room.roomId),
                    onLongPress: () async {
                      await service.prioritizeRoom(room.roomId);
                      if (!context.mounted) {
                        return;
                      }
                      final updatedRoom = service.rooms.firstWhereOrNull(
                        (item) => item.roomId == room.roomId,
                      );
                      if (updatedRoom != null) {
                        _showRoomDetail(context, updatedRoom);
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) => Stack(
                              fit: StackFit.expand,
                              children: [
                                NetworkImgLayer(
                                  src: imageUrl,
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  type: ImageType.emote,
                                ),
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          room.uname,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '房间在线 ${NumUtils.numFormat(room.roomOnline)} · 高能 ${NumUtils.numFormat(room.activeOnline)} · 航海 ${NumUtils.numFormat(room.guardCount)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                room.watchedText ?? room.areaName,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildKeywordsTab(ThemeData theme) {
    return Obx(() {
      final groups = service.keywordGroups;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          FilledButton.tonalIcon(
            onPressed: () => _showAddGroupDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('新增词组'),
          ),
          const SizedBox(height: 12),
          ...groups.entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: '添加词语',
                          onPressed: () =>
                              _showAddKeywordDialog(context, group: entry.key),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value
                          .map(
                            (word) => InputChip(
                              label: Text(word),
                              onDeleted: () =>
                                  service.removeKeyword(entry.key, word),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    });
  }

  Widget _buildDebugTab(ThemeData theme) {
    return Obx(() {
      final records = service.debugRecords;
      if (records.isEmpty) {
        return const Center(child: Text('还没有抓到请求记录'));
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: records.length,
        itemBuilder: (context, index) {
          final item = records[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(item.label),
              subtitle: Text(
                '${item.method} · ${item.url}\n${_formatTime(item.createdAt)}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: item.errorMessage == null
                  ? const Icon(Icons.chevron_right)
                  : Icon(Icons.error_outline, color: theme.colorScheme.error),
              onTap: () => _showDebugRecord(context, item),
            ),
          );
        },
      );
    });
  }

  Widget _buildRankingCard(
    BuildContext context, {
    required String title,
    required List<LiveMonitorRoomRecord> items,
    required String Function(LiveMonitorRoomRecord item) valueBuilder,
  }) {
    final theme = Theme.of(context);
    return Ink(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: Style.mdRadius,
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('还没有抓到数据', style: theme.textTheme.bodySmall)
          else
            ...items.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.uname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(valueBuilder(item)),
                onTap: () => _showRoomDetail(context, item),
              ),
            ),
        ],
      ),
    );
  }

  List<LiveMonitorCommentRecord> _filteredComments() {
    final textFilter = _commentFilterController.text.trim().toLowerCase();
    final keywordFilter = _keywordFilterController.text.trim().toLowerCase();
    return service.comments.where((item) {
      if (onlyMatched && item.matchedKeywords.isEmpty) {
        return false;
      }
      if (roomFilterId != null && item.roomId != roomFilterId) {
        return false;
      }
      if (textFilter.isNotEmpty) {
        final haystack =
            '${item.text} ${item.userName} ${item.roomTitle} ${item.roomOwner}'
                .toLowerCase();
        if (!haystack.contains(textFilter)) {
          return false;
        }
      }
      if (keywordFilter.isNotEmpty) {
        final matched = item.matchedKeywords.any(
          (word) => word.toLowerCase().contains(keywordFilter),
        );
        if (!matched) {
          return false;
        }
      }
      return true;
    }).toList()..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  Future<void> _exportAll() async {
    SmartDialog.showLoading(msg: '正在导出...');
    try {
      final content = await service.exportAllDataJson();
      await StorageUtils.saveBytes2File(
        name:
            'piliplus_live_monitor_${DateTime.now().millisecondsSinceEpoch}.json',
        bytes: Uint8List.fromList(utf8.encode(content)),
        allowedExtensions: const ['json'],
      );
    } finally {
      SmartDialog.dismiss();
    }
  }

  Future<void> _showAreaPicker(BuildContext context) async {
    final result = await showModalBottomSheet<LiveMonitorAreaOption>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Obx(() {
          final areas = service.areaOptions;
          return ListView.builder(
            itemCount: areas.length,
            itemBuilder: (context, index) {
              final item = areas[index];
              return ListTile(
                title: Text(item.areaName),
                subtitle: Text(
                  '${item.groupName} · 在线 ${item.reportedTotalRoomCount} · 已监控 ${item.monitoredRoomCount}',
                ),
                onTap: () => Get.back(result: item),
              );
            },
          );
        }),
      ),
    );
    if (result != null) {
      await service.selectArea(result);
    }
  }

  Future<void> _showRoomFilterPicker(BuildContext context) async {
    final result = await showModalBottomSheet<int?>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: ListView(
          children: [
            ListTile(
              title: const Text('全部房间'),
              onTap: () => Get.back(result: null),
            ),
            ...service.rooms.map(
              (room) => ListTile(
                title: Text(room.uname),
                subtitle: Text('${room.roomId} · ${room.title}'),
                onTap: () => Get.back(result: room.roomId),
              ),
            ),
          ],
        ),
      ),
    );
    setState(() {
      roomFilterId = result;
    });
  }

  Future<void> _showSamplingDialog(BuildContext context) async {
    final pageLimitController = TextEditingController(
      text: service.pageLimit.toString(),
    );
    final roomLimitController = TextEditingController(
      text: service.roomLimit.toString(),
    );
    final pageSizeController = TextEditingController(
      text: service.pageSize.toString(),
    );
    final areaRefreshController = TextEditingController(
      text: service.areaRefreshSeconds.toString(),
    );
    final roomRefreshController = TextEditingController(
      text: service.roomRefreshSeconds.toString(),
    );
    final result = await showDialog<(int, int, int, int, int)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('直播面板采样设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pageLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '抓取页数'),
            ),
            TextField(
              controller: roomLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '房间上限'),
            ),
            TextField(
              controller: pageSizeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '每页条数'),
            ),
            TextField(
              controller: areaRefreshController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '分区刷新秒数'),
            ),
            TextField(
              controller: roomRefreshController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '增量抓评秒数'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Get.back(
                result: (
                  int.tryParse(pageLimitController.text) ?? service.pageLimit,
                  int.tryParse(roomLimitController.text) ?? service.roomLimit,
                  int.tryParse(pageSizeController.text) ?? service.pageSize,
                  int.tryParse(areaRefreshController.text) ??
                      service.areaRefreshSeconds,
                  int.tryParse(roomRefreshController.text) ??
                      service.roomRefreshSeconds,
                ),
              );
            },
            child: const Text('保存并刷新'),
          ),
        ],
      ),
    );
    if (result != null) {
      await service.updateSampling(
        nextPageLimit: result.$1.clamp(1, 20).toInt(),
        nextRoomLimit: result.$2.clamp(10, 1500).toInt(),
        nextPageSize: result.$3.clamp(10, 100).toInt(),
        nextAreaRefreshSeconds: result.$4.clamp(20, 600).toInt(),
        nextRoomRefreshSeconds: result.$5.clamp(10, 300).toInt(),
      );
    }
  }

  Future<void> _showAddGroupDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增词组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：引流暗语',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          FilledButton(
            onPressed: () => Get.back(result: controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result?.isNotEmpty == true) {
      service.addGroup(result!);
    }
  }

  Future<void> _showAddKeywordDialog(
    BuildContext context, {
    required String group,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('向 $group 添加词语'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '支持一次输入一个词',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          FilledButton(
            onPressed: () => Get.back(result: controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result?.isNotEmpty == true) {
      service.addKeyword(group, result!);
    }
  }

  Future<void> _showDebugRecord(
    BuildContext context,
    RequestDebugRecord record,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: ListView(
            children: [
              Text(
                record.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _DebugBlock(title: 'URL', value: record.url),
              _DebugBlock(title: 'cURL', value: record.curl ?? '-'),
              _DebugBlock(
                title: 'Request Body',
                value: record.requestBody ?? '-',
              ),
              _DebugBlock(
                title: 'Response Preview',
                value: record.responsePreview ?? '-',
              ),
              if (record.errorMessage?.isNotEmpty == true)
                _DebugBlock(title: 'Error', value: record.errorMessage!),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomDetail(
    BuildContext context,
    LiveMonitorRoomRecord room,
  ) async {
    final roomComments =
        service.comments.where((item) => item.roomId == room.roomId).toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(room.uname, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(room.title),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip('房间号', room.roomId),
                _MetricChip('展示热度', NumUtils.numFormat(room.displayOnline)),
                _MetricChip('房间在线', NumUtils.numFormat(room.roomOnline)),
                _MetricChip('活跃观众', NumUtils.numFormat(room.activeOnline)),
                _MetricChip('累计观看', room.watchedText ?? '-'),
                _MetricChip('粉丝', NumUtils.numFormat(room.followerCount)),
                _MetricChip('大航海', NumUtils.numFormat(room.guardCount)),
                _MetricChip('总评论', room.totalCommentCount),
                _MetricChip('命中评论', room.matchedCommentCount),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => PageUtils.toLiveRoom(room.roomId),
                    child: const Text('进入直播间'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await service.prioritizeRoom(room.roomId);
                      if (context.mounted) {
                        SmartDialog.showToast('已优先重新抓取');
                      }
                    },
                    child: const Text('立即重抓'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('最新评论', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (roomComments.isEmpty)
              const Text('还没有抓到该房间评论')
            else
              ...roomComments
                  .take(60)
                  .map(
                    (item) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.userName} · ${_formatTime(item.capturedAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text.rich(
                              _highlightText(
                                Theme.of(context),
                                item.text,
                                item.matchedKeywords
                                    .map((e) => e.split(':').last)
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  TextSpan _highlightText(ThemeData theme, String text, List<String> keywords) {
    if (keywords.isEmpty) {
      return TextSpan(text: text, style: theme.textTheme.bodyMedium);
    }
    final spans = <TextSpan>[];
    final normalizedKeywords =
        keywords
            .where((item) => item.trim().isNotEmpty)
            .map((item) => item.toLowerCase())
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    int cursor = 0;
    final lower = text.toLowerCase();
    while (cursor < text.length) {
      String? hit;
      for (final keyword in normalizedKeywords) {
        if (lower.startsWith(keyword, cursor)) {
          hit = text.substring(cursor, cursor + keyword.length);
          break;
        }
      }
      if (hit != null) {
        spans.add(
          TextSpan(
            text: hit,
            style: theme.textTheme.bodyMedium?.copyWith(
              backgroundColor: theme.colorScheme.tertiaryContainer,
              color: theme.colorScheme.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        cursor += hit.length;
      } else {
        final nextIndex = normalizedKeywords
            .map((keyword) => lower.indexOf(keyword, cursor))
            .where((index) => index >= 0)
            .fold<int?>(null, (value, index) {
              if (value == null || index < value) {
                return index;
              }
              return value;
            });
        final end = nextIndex ?? text.length;
        spans.add(
          TextSpan(
            text: text.substring(cursor, end),
            style: theme.textTheme.bodyMedium,
          ),
        );
        cursor = end;
      }
    }
    return TextSpan(children: spans);
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s 前';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m 前';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h 前';
    }
    return '${value.month}-${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: ${value ?? '-'}'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RoomCoverageCard extends StatelessWidget {
  const _RoomCoverageCard({
    required this.room,
    required this.onTap,
    required this.onPrioritize,
  });

  final LiveMonitorRoomRecord room;
  final VoidCallback onTap;
  final VoidCallback onPrioritize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.uname,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          room.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: onPrioritize,
                    child: const Text('优先抓'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip('房间', room.roomId),
                  _MetricChip('状态', room.fetchState.label),
                  _MetricChip('展示热度', NumUtils.numFormat(room.displayOnline)),
                  _MetricChip('房间在线', NumUtils.numFormat(room.roomOnline)),
                  _MetricChip('活跃观众', NumUtils.numFormat(room.activeOnline)),
                  _MetricChip('累计观看', room.watchedText ?? '-'),
                  _MetricChip('粉丝', NumUtils.numFormat(room.followerCount)),
                  _MetricChip('大航海', NumUtils.numFormat(room.guardCount)),
                  _MetricChip('总评论', room.totalCommentCount),
                  _MetricChip('命中', room.matchedCommentCount),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: room.coverageRatio),
              ),
              if (room.missingFields.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: room.missingFields
                      .map(
                        (field) => Chip(
                          label: Text(field),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (room.lastError?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  room.lastError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugBlock extends StatelessWidget {
  const _DebugBlock({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
}
