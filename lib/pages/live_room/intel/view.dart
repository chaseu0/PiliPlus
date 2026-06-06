import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/selectable_text.dart';
import 'package:PiliPlus/pages/live_room/intel/controller.dart';
import 'package:PiliPlus/pages/live_room/intel/model.dart';
import 'package:PiliPlus/services/request_debug.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LiveIntelPanel extends StatelessWidget {
  const LiveIntelPanel({
    super.key,
    required this.heroTag,
  });

  final String heroTag;

  LiveIntelController get controller => Get.find<LiveIntelController>(tag: heroTag);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          _Header(controller: controller),
          const TabBar(
            tabs: [
              Tab(text: '评论'),
              Tab(text: '房间'),
              Tab(text: '关键词'),
              Tab(text: 'Debug'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CommentsTab(controller: controller),
                _RoomsTab(controller: controller),
                _KeywordsTab(controller: controller),
                _DebugTab(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final LiveIntelController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Obx(
        () {
          final summary = controller.summary.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '直播情报面板',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary == null
                              ? '准备抓取当前分区的房间、评论和统计指标'
                              : '分区 ${summary.areaName.isEmpty ? '-' : summary.areaName} · 已监控 ${summary.monitoredRoomCount} 房',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '采样设置',
                    onPressed: () => _showSamplingDialog(context, controller),
                    icon: const Icon(Icons.tune),
                  ),
                  Obx(
                    () => IconButton(
                      tooltip: '刷新',
                      onPressed: controller.isLoading.value
                          ? null
                          : controller.refreshAll,
                      icon: controller.isLoading.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ),
                ],
              ),
              if (summary != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip('分区总房间', summary.totalRoomCount),
                    _MetricChip('已发现房间', summary.discoveredRoomCount),
                    _MetricChip('已发现UP', summary.discoveredUpCount),
                    _MetricChip('已抓房间', summary.historySuccessCount),
                    _MetricChip('失败房间', summary.historyFailedCount),
                    _MetricChip('抓到评论', summary.totalCommentCount),
                    _MetricChip('命中评论', summary.totalMatchedCount),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: Style.mdRadius,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Text(
                  '人数说明：房间在线/展示人数与高能观众不是同一指标。面板里“房间在线”来自房间状态接口，“高能观众”来自 getOnlineGoldRank / 实时 ONLINE_RANK_COUNT，更接近当前有效在线观众。',
                  style: textTheme.bodySmall,
                ),
              ),
              if (controller.loadError.value?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  controller.loadError.value!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CommentsTab extends StatelessWidget {
  const _CommentsTab({required this.controller});

  final LiveIntelController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.comments;
      if (items.isEmpty) {
        return const Center(child: Text('还没有抓到评论'));
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            borderRadius: Style.mdRadius,
            onTap: () => _showCommentDetail(context, item),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: Style.mdRadius,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.roomOwner} · ${item.roomTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StateBadge(text: item.source.label),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.userName}: ${item.text}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.roomId} · ${_formatTime(item.capturedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (item.matchedKeywords.isNotEmpty)
                        Text(
                          '命中 ${item.matchedKeywords.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  void _showCommentDetail(BuildContext context, LiveIntelCommentItem item) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.userName} @ ${item.roomOwner}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Utils.copyText(item.text),
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              selectableText(item.text),
              const SizedBox(height: 12),
              _InfoLine(label: '房间', value: '${item.roomTitle} (${item.roomId})'),
              _InfoLine(label: '来源', value: item.source.label),
              _InfoLine(label: '用户ID', value: item.userId.toString()),
              _InfoLine(label: '时间', value: _formatTime(item.capturedAt)),
              _InfoLine(
                label: '命中关键词',
                value: item.matchedKeywords.isEmpty
                    ? '-'
                    : item.matchedKeywords.join(', '),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => PageUtils.toLiveRoom(item.roomId),
                    child: const Text('打开直播间'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => Get.toNamed('/member?mid=${item.userId}'),
                    child: const Text('打开用户'),
                  ),
                ],
              ),
              if (item.rawPayload?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text(
                  '原始载荷',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                selectableText(item.rawPayload!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab({required this.controller});

  final LiveIntelController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.roomStatuses;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _RankingCard(
            title: '粉丝排行',
            items: controller.followerRanking.take(5).toList(),
            valueBuilder: (item) => NumUtils.numFormat(item.followerCount),
          ),
          const SizedBox(height: 10),
          _RankingCard(
            title: '真实大航海排行',
            items: controller.guardRanking.take(5).toList(),
            valueBuilder: (item) => NumUtils.numFormat(item.guardCount),
          ),
          const SizedBox(height: 10),
          _RankingCard(
            title: '高能观众排行',
            items: controller.trueOnlineRanking.take(5).toList(),
            valueBuilder: (item) => NumUtils.numFormat(item.trueOnline),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RoomCard(item: item),
              )),
        ],
      );
    });
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.item});

  final LiveIntelRoomStatus item;

  @override
  Widget build(BuildContext context) {
    final image = item.keyframe ?? item.cover;
    return InkWell(
      borderRadius: Style.mdRadius,
      onTap: () => PageUtils.toLiveRoom(item.roomId),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: Style.mdRadius,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkImgLayer(
              src: image,
              width: 120,
              height: 68,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title.isEmpty ? '房间 ${item.roomId}' : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StateBadge(
                        text: item.historyState.label,
                        active: item.historyState == LiveIntelFetchState.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.uname} · ${item.areaName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniMetric('房间在线', item.displayOnline),
                      _MiniMetric('高能观众', item.trueOnline),
                      _MiniMetric('粉丝', item.followerCount),
                      _MiniMetric('大航海', item.guardCount),
                      _MiniMetric('实时', item.realtimeCommentCount),
                      _MiniMetric('历史', item.historyCommentCount),
                      _MiniMetric('命中', item.matchedCommentCount),
                    ],
                  ),
                  if (item.lastError?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.lastError!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeywordsTab extends StatelessWidget {
  const _KeywordsTab({required this.controller});

  final LiveIntelController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final groups = controller.keywordGroups;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '扩大词库后，后续刷新会按新词重新匹配。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showNewGroupDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('新增分类'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...groups.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: Style.mdRadius,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showAddKeywordDialog(context, entry.key),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value.map((keyword) {
                        return InputChip(
                          label: Text(keyword),
                          onDeleted: () => controller.removeKeyword(entry.key, keyword),
                        );
                      }).toList(),
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

  Future<void> _showNewGroupDialog(BuildContext context) async {
    final text = await _showTextInputDialog(
      context,
      title: '新增分类',
      hint: '例如：夜聊导流',
    );
    if (text != null) {
      controller.addGroup(text);
    }
  }

  Future<void> _showAddKeywordDialog(BuildContext context, String group) async {
    final text = await _showTextInputDialog(
      context,
      title: '添加关键词',
      hint: '多个词请用逗号分隔',
    );
    if (text != null) {
      for (final keyword in text.split(RegExp(r'[,，\n]'))) {
        controller.addKeyword(group, keyword);
      }
    }
  }
}

class _DebugTab extends StatelessWidget {
  const _DebugTab({required this.controller});

  final LiveIntelController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final _ = RequestDebugService.instance.records.length;
      final items = controller.debugRecords;
      if (items.isEmpty) {
        return const Center(child: Text('还没有调试记录'));
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            borderRadius: Style.mdRadius,
            onTap: () => _showDebugDetail(context, item),
            child: Ink(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: Style.mdRadius,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.label)),
                      _StateBadge(
                        text: '${item.method}${item.statusCode != null ? ' ${item.statusCode}' : ''}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(item.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  void _showDebugDetail(BuildContext context, RequestDebugRecord item) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Utils.copyText(item.curl ?? item.url),
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
              _InfoLine(label: '方法', value: item.method),
              _InfoLine(label: '状态', value: item.statusCode?.toString() ?? '-'),
              _InfoLine(label: '时间', value: _formatTime(item.createdAt)),
              _InfoLine(label: 'URL', value: item.url),
              if (item.curl?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Curl',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                selectableText(item.curl!),
              ],
              if (item.requestBody?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Request',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                selectableText(item.requestBody!),
              ],
              if (item.responsePreview?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Response',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                selectableText(item.responsePreview!),
              ],
              if (item.errorMessage?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(
                  'Error',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                selectableText(item.errorMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.items,
    required this.valueBuilder,
  });

  final String title;
  final List<LiveIntelRoomStatus> items;
  final String Function(LiveIntelRoomStatus item) valueBuilder;

  @override
  Widget build(BuildContext context) {
    return Ink(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: Style.mdRadius,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              '暂无数据',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...items.asMap().entries.map((entry) {
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text('${entry.key + 1}'),
                    ),
                    Expanded(
                      child: Text(
                        item.uname.isEmpty ? '房间 ${item.roomId}' : item.uname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(valueBuilder(item)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value);

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Text('$label ${NumUtils.numFormat(value)}'),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value);

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label ${NumUtils.numFormat(value)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.text,
    this.active = false,
  });

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label：$value'),
    );
  }
}

String _formatTime(DateTime time) {
  final value = time.toLocal().toString();
  return value.length >= 19 ? value.substring(0, 19) : value;
}

Future<String?> _showTextInputDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final textController = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: textController,
        maxLines: 4,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Get.back(result: textController.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<void> _showSamplingDialog(
  BuildContext context,
  LiveIntelController controller,
) async {
  final pageLimitController =
      TextEditingController(text: controller.pageLimit.toString());
  final roomLimitController =
      TextEditingController(text: controller.roomLimit.toString());
  final pageSizeController =
      TextEditingController(text: controller.pageSize.toString());
  final result = await showDialog<(int, int, int)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('采样设置'),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final pageLimit = int.tryParse(pageLimitController.text) ?? controller.pageLimit;
            final roomLimit = int.tryParse(roomLimitController.text) ?? controller.roomLimit;
            final pageSize = int.tryParse(pageSizeController.text) ?? controller.pageSize;
            Get.back(result: (pageLimit, roomLimit, pageSize));
          },
          child: const Text('保存并刷新'),
        ),
      ],
    ),
  );
  if (result != null) {
    await controller.updateSampling(
      nextPageLimit: result.$1.clamp(1, 20).toInt(),
      nextRoomLimit: result.$2.clamp(1, 200).toInt(),
      nextPageSize: result.$3.clamp(1, 100).toInt(),
    );
  }
}
