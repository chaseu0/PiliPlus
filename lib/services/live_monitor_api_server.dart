import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/live_monitor_service.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class LiveMonitorApiServer extends GetxService {
  LiveMonitorApiServer._();

  static LiveMonitorApiServer get instance {
    if (Get.isRegistered<LiveMonitorApiServer>()) {
      return Get.find<LiveMonitorApiServer>();
    }
    return Get.put(LiveMonitorApiServer._(), permanent: true);
  }

  HttpServer? _server;

  final isRunning = false.obs;
  final boundHost = '127.0.0.1'.obs;
  final boundPort = 0.obs;
  final requestCount = 0.obs;
  final lastError = RxnString();
  final startedAt = Rxn<DateTime>();

  String get desktopUrl => 'http://127.0.0.1:${boundPort.value}/';
  String get adbForwardCommand =>
      'adb forward tcp:${boundPort.value} tcp:${boundPort.value}';

  Future<void> ensureStarted() async {
    if (!Pref.liveMonitorApiAutoStart) {
      return;
    }
    await start();
  }

  Future<void> start({bool forceRestart = false, int? overridePort}) async {
    if (isRunning.value && !forceRestart) {
      return;
    }
    if (forceRestart) {
      await stop();
    }
    final preferredPort = overridePort ?? Pref.liveMonitorApiPort;
    Object? lastBindError;
    for (int offset = 0; offset < 8; offset++) {
      final port = preferredPort + offset;
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        boundPort.value = port;
        Pref.liveMonitorApiPort = port;
        isRunning.value = true;
        startedAt.value = DateTime.now();
        lastError.value = null;
        debugPrint(
          'LiveMonitorApiServer listening on http://${boundHost.value}:$port',
        );
        _server!.listen(
          _handleRequest,
          onError: (Object error) {
            lastError.value = error.toString();
            debugPrint('LiveMonitorApiServer request error: $error');
          },
        );
        return;
      } catch (error) {
        lastBindError = error;
        debugPrint('LiveMonitorApiServer bind failed on $port: $error');
      }
    }
    lastError.value = 'HTTP 服务启动失败: $lastBindError';
    throw Exception(lastError.value);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    isRunning.value = false;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    requestCount.value++;
    try {
      final path = request.uri.path;
      if (request.method == 'OPTIONS') {
        _setCorsHeaders(request.response);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      if (path == '/' || path == '/dashboard') {
        await _writeHtml(request.response, _dashboardHtml());
        return;
      }
      if (path == '/api/health') {
        await _writeJson(request.response, {
          'ok': true,
          'host': boundHost.value,
          'port': boundPort.value,
          'request_count': requestCount.value,
          'started_at': startedAt.value?.toIso8601String(),
          'monitor_running': LiveMonitorService.instance.isRunning.value,
        });
        return;
      }
      if (path == '/api/status') {
        await _writeJson(request.response, _serverStatusJson());
        return;
      }
      if (path == '/api/summary') {
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildSummaryJson(),
        );
        return;
      }
      if (path == '/api/coverage') {
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildCoverageJson(),
        );
        return;
      }
      if (path == '/api/areas') {
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildAreaOptionsJson(),
        );
        return;
      }
      if (path == '/api/rooms') {
        final roomId = _intQuery(request.uri, 'room_id');
        final limit = _intQuery(request.uri, 'limit');
        final matchedOnly = _boolQuery(request.uri, 'matched_only');
        final missingOnly = _boolQuery(request.uri, 'missing_only');
        final keyword = request.uri.queryParameters['keyword'];
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildRoomsJson(
            roomId: roomId,
            limit: limit,
            matchedOnly: matchedOnly,
            missingOnly: missingOnly,
            keyword: keyword,
          ),
        );
        return;
      }
      if (path == '/api/comments') {
        final roomId = _intQuery(request.uri, 'room_id');
        final limit = _intQuery(request.uri, 'limit');
        final matchedOnly = _boolQuery(request.uri, 'matched_only');
        final keyword = request.uri.queryParameters['keyword'];
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildCommentsJson(
            roomId: roomId,
            limit: limit,
            matchedOnly: matchedOnly,
            keyword: keyword,
          ),
        );
        return;
      }
      if (path == '/api/debug') {
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildDebugJson(
            limit: _intQuery(request.uri, 'limit'),
          ),
        );
        return;
      }
      if (path == '/api/export') {
        final content = await LiveMonitorService.instance.exportAllDataJson();
        _setCorsHeaders(request.response);
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="piliplus_live_monitor_export.json"',
        );
        request.response.write(content);
        await request.response.close();
        return;
      }
      if (path == '/api/control/start' && request.method == 'POST') {
        await LiveMonitorService.instance.startMonitoring();
        await _writeJson(request.response, _serverStatusJson());
        return;
      }
      if (path == '/api/control/stop' && request.method == 'POST') {
        await LiveMonitorService.instance.stopMonitoring();
        await _writeJson(request.response, _serverStatusJson());
        return;
      }
      if (path == '/api/control/refresh' && request.method == 'POST') {
        await LiveMonitorService.instance.refreshNow();
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildSummaryJson(),
        );
        return;
      }
      if (path == '/api/control/select-area' && request.method == 'POST') {
        final body = await _readRequestBody(request);
        final parentAreaId =
            _asInt(body['parent_area_id']) ??
            _intQuery(request.uri, 'parent_area_id');
        final areaId =
            _asInt(body['area_id']) ?? _intQuery(request.uri, 'area_id');
        final area = LiveMonitorService.instance.areaOptions.firstWhereOrNull(
          (item) => item.parentAreaId == parentAreaId && item.areaId == areaId,
        );
        if (area == null) {
          await _writeJson(request.response, {
            'ok': false,
            'error': '分区不存在',
          }, statusCode: HttpStatus.notFound);
          return;
        }
        await LiveMonitorService.instance.selectArea(area);
        await _writeJson(
          request.response,
          LiveMonitorService.instance.buildSummaryJson(),
        );
        return;
      }
      if (path == '/api/control/prioritize-room' && request.method == 'POST') {
        final body = await _readRequestBody(request);
        final roomId =
            _asInt(body['room_id']) ?? _intQuery(request.uri, 'room_id');
        if (roomId == null) {
          await _writeJson(request.response, {
            'ok': false,
            'error': '缺少 room_id',
          }, statusCode: HttpStatus.badRequest);
          return;
        }
        await LiveMonitorService.instance.prioritizeRoom(roomId);
        await _writeJson(request.response, {'ok': true, 'room_id': roomId});
        return;
      }
      if (path == '/api/control/add-keyword' && request.method == 'POST') {
        final body = await _readRequestBody(request);
        final group =
            (body['group'] ?? request.uri.queryParameters['group'] ?? '')
                .toString();
        final keyword =
            (body['keyword'] ?? request.uri.queryParameters['keyword'] ?? '')
                .toString();
        if (group.trim().isEmpty || keyword.trim().isEmpty) {
          await _writeJson(request.response, {
            'ok': false,
            'error': '缺少 group 或 keyword',
          }, statusCode: HttpStatus.badRequest);
          return;
        }
        LiveMonitorService.instance.addKeyword(group, keyword);
        await _writeJson(request.response, {
          'ok': true,
          'keyword_groups': LiveMonitorService.instance.keywordGroups,
        });
        return;
      }
      await _writeJson(request.response, {
        'ok': false,
        'error': 'Not Found',
      }, statusCode: HttpStatus.notFound);
    } catch (error) {
      lastError.value = error.toString();
      await _writeJson(request.response, {
        'ok': false,
        'error': error.toString(),
      }, statusCode: HttpStatus.internalServerError);
    }
  }

  Map<String, dynamic> _serverStatusJson() {
    return {
      'ok': true,
      'api_server': {
        'is_running': isRunning.value,
        'host': boundHost.value,
        'port': boundPort.value,
        'started_at': startedAt.value?.toIso8601String(),
        'request_count': requestCount.value,
        'desktop_url': desktopUrl,
        'adb_forward_command': adbForwardCommand,
        'last_error': lastError.value,
      },
      'monitor': LiveMonitorService.instance.buildSummaryJson(),
    };
  }

  Future<Map<String, dynamic>> _readRequestBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeJson(
    HttpResponse response,
    Object payload, {
    int statusCode = HttpStatus.ok,
  }) async {
    _setCorsHeaders(response);
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(const JsonEncoder.withIndent('  ').convert(payload));
    await response.close();
  }

  Future<void> _writeHtml(HttpResponse response, String html) async {
    _setCorsHeaders(response);
    response.headers.contentType = ContentType.html;
    response.write(html);
    await response.close();
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'Content-Type',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  int? _intQuery(Uri uri, String key) {
    return int.tryParse(uri.queryParameters[key] ?? '');
  }

  bool _boolQuery(Uri uri, String key) {
    final value = uri.queryParameters[key];
    return value == '1' || value == 'true';
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  String _dashboardHtml() {
    return r'''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>PiliPlus 直播监控面板</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4efe7;
      --card: #fffaf2;
      --line: #d9cdb8;
      --text: #241f17;
      --muted: #7b6e5d;
      --accent: #b04c2f;
      --accent-soft: #f2d2b4;
      --good: #2f7d47;
      --warn: #a56812;
      --bad: #b3261e;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "SF Pro Display","PingFang SC","Helvetica Neue",sans-serif;
      background:
        radial-gradient(circle at top right, rgba(176,76,47,.18), transparent 26%),
        linear-gradient(180deg, #faf5ed 0%, var(--bg) 100%);
      color: var(--text);
    }
    .wrap { max-width: 1500px; margin: 0 auto; padding: 20px; }
    h1,h2,h3 { margin: 0; }
    .hero, .card {
      background: rgba(255,250,242,.92);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: 0 14px 36px rgba(52,33,10,.08);
      backdrop-filter: blur(10px);
    }
    .hero { padding: 18px; margin-bottom: 16px; }
    .hero-top {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 14px;
    }
    .muted { color: var(--muted); }
    .grid {
      display: grid;
      grid-template-columns: repeat(12, minmax(0, 1fr));
      gap: 14px;
    }
    .card { padding: 14px; }
    .span-12 { grid-column: span 12; }
    .span-8 { grid-column: span 8; }
    .span-6 { grid-column: span 6; }
    .span-4 { grid-column: span 4; }
    .metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
      gap: 10px;
      margin-top: 12px;
    }
    .metric {
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 10px 12px;
      background: rgba(255,255,255,.56);
    }
    .metric b {
      display: block;
      font-size: 22px;
      margin-top: 6px;
    }
    .toolbar, .filters {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
    }
    button, select, input {
      border-radius: 12px;
      border: 1px solid var(--line);
      background: white;
      color: var(--text);
      padding: 10px 12px;
      font: inherit;
    }
    button {
      cursor: pointer;
      background: linear-gradient(180deg, #cb6a47 0%, var(--accent) 100%);
      color: white;
      border: none;
    }
    button.alt {
      background: white;
      color: var(--text);
      border: 1px solid var(--line);
    }
    a { color: var(--accent); }
    .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; }
    .chip {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border-radius: 999px;
      padding: 6px 10px;
      font-size: 13px;
      border: 1px solid var(--line);
      background: #fff;
    }
    .chip.bad { border-color: rgba(179,38,30,.25); color: var(--bad); background: #fff2f1; }
    .chip.good { border-color: rgba(47,125,71,.25); color: var(--good); background: #effaf2; }
    .chip.warn { border-color: rgba(165,104,18,.25); color: var(--warn); background: #fff5e7; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td {
      text-align: left;
      padding: 10px 8px;
      border-bottom: 1px solid rgba(217,205,184,.72);
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; }
    tbody tr:hover { background: rgba(176,76,47,.05); }
    .hit {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 999px;
      background: var(--accent-soft);
      font-size: 12px;
      margin: 2px 4px 0 0;
    }
    .mono {
      font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      white-space: pre-wrap;
      word-break: break-all;
      font-size: 12px;
      background: #fff;
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 10px;
    }
    .comment {
      padding: 12px 0;
      border-bottom: 1px solid rgba(217,205,184,.72);
    }
    .comment:last-child { border-bottom: none; }
    .comment-text { margin: 8px 0; line-height: 1.55; }
    .room-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(290px, 1fr));
      gap: 12px;
    }
    .room-card {
      border: 1px solid var(--line);
      border-radius: 14px;
      overflow: hidden;
      background: white;
    }
    .room-card img {
      width: 100%;
      aspect-ratio: 16 / 10;
      object-fit: cover;
      display: block;
      background: #eadfce;
    }
    .room-card .body { padding: 12px; }
    .small { font-size: 12px; }
    details { margin-top: 8px; }
    summary { cursor: pointer; color: var(--accent); }
    @media (max-width: 980px) {
      .span-8, .span-6, .span-4 { grid-column: span 12; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <section class="hero">
      <div class="hero-top">
        <div>
          <h1>PiliPlus 直播监控电脑面板</h1>
          <div class="muted">手机内置服务已开放，浏览器直连当前手机数据与控制接口。</div>
        </div>
        <div class="toolbar">
          <button id="startBtn">开始抓取</button>
          <button id="stopBtn" class="alt">停止抓取</button>
          <button id="refreshBtn" class="alt">立即刷新</button>
          <a id="exportLink" href="/api/export" target="_blank">导出 JSON</a>
        </div>
      </div>
      <div class="filters">
        <select id="areaSelect"></select>
        <input id="keywordInput" placeholder="关键词筛选，如 微信 / 礼物" />
        <label><input type="checkbox" id="matchedOnly" /> 仅看命中</label>
        <label><input type="checkbox" id="missingOnly" /> 仅看缺口</label>
        <label><input type="checkbox" id="frameMode" checked /> 优先显示当前帧</label>
      </div>
      <div class="chips" id="statusChips"></div>
      <div class="metrics" id="summaryMetrics"></div>
    </section>

    <section class="grid">
      <article class="card span-4">
        <h2>抓取覆盖缺口</h2>
        <div class="chips" id="coverageChips"></div>
        <div class="mono" id="coverageMissing"></div>
      </article>

      <article class="card span-8">
        <div style="display:flex;justify-content:space-between;gap:10px;align-items:center;">
          <h2>房间覆盖面板</h2>
          <div class="muted small">缺失字段、真实在线线索、命中量、最新评论状态都会在这里汇总。</div>
        </div>
        <div class="room-grid" id="roomGrid"></div>
      </article>

      <article class="card span-7">
        <div style="display:flex;justify-content:space-between;gap:10px;align-items:center;">
          <h2>评论流</h2>
          <div class="muted small">点击房间按钮可优先抓该直播间。</div>
        </div>
        <div id="commentList"></div>
      </article>

      <article class="card span-5">
        <h2>调试请求</h2>
        <div id="debugList"></div>
      </article>

      <article class="card span-12">
        <h2>房间表</h2>
        <div style="overflow:auto;">
          <table>
            <thead>
              <tr>
                <th>房间</th>
                <th>真实在线线索</th>
                <th>评论</th>
                <th>缺失字段</th>
                <th>动作</th>
              </tr>
            </thead>
            <tbody id="roomTable"></tbody>
          </table>
        </div>
      </article>
    </section>
  </div>

  <script>
    const state = {
      areas: [],
      summary: null,
      rooms: [],
      comments: [],
      debug: [],
      coverage: null,
      selectedArea: null,
    };

    const fmt = (value) => value == null || value === '' ? '-' : String(value);
    const qs = (id) => document.getElementById(id);
    const esc = (value) => String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

    async function getJson(url) {
      const res = await fetch(url, { cache: 'no-store' });
      return res.json();
    }

    async function postJson(url, body = {}) {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      return res.json();
    }

    function renderAreas() {
      const select = qs('areaSelect');
      select.innerHTML = state.areas.map((area) => {
        const selected = state.selectedArea &&
          area.parent_area_id === state.selectedArea.parent_area_id &&
          area.area_id === state.selectedArea.area_id;
        return `<option value="${area.parent_area_id}:${area.area_id}" ${selected ? 'selected' : ''}>${esc(area.label)} · 在线 ${fmt(area.reported_total_room_count)} · 已监控 ${fmt(area.monitored_room_count)}</option>`;
      }).join('');
    }

    function renderSummary() {
      const payload = state.summary || {};
      const data = payload.summary || {};
      const metrics = [
        ['分区在线房间', data.total_room_count],
        ['已监控房间', data.monitored_room_count],
        ['未覆盖估算', data.unmonitored_room_estimate],
        ['UP 数量', data.unique_up_count],
        ['总评论', data.total_comment_count],
        ['命中评论', data.total_matched_comment_count],
        ['命中房间', data.matched_room_count],
        ['可看帧', data.ready_frame_count],
        ['抓取失败', data.failed_room_count],
      ];
      qs('summaryMetrics').innerHTML = metrics.map(([label, value]) => `
        <div class="metric">
          <div class="small muted">${label}</div>
          <b>${fmt(value)}</b>
        </div>
      `).join('');

      const chips = [
        ['监控状态', payload.is_running ? '运行中' : '已停止', payload.is_running ? 'good' : 'warn'],
        ['分区刷新', fmt(data.last_area_refresh_at), ''],
        ['房间刷新', fmt(data.last_room_refresh_at), ''],
        ['采样', `${payload.sampling?.page_limit ?? '-'}页 / ${payload.sampling?.room_limit ?? '-'}房`, ''],
        ['电脑地址', location.origin, ''],
      ];
      qs('statusChips').innerHTML = chips.map(([k, v, kind]) => `
        <span class="chip ${kind}"><strong>${esc(k)}</strong><span>${esc(v)}</span></span>
      `).join('');
    }

    function renderCoverage() {
      const coverage = state.coverage || {};
      const counts = coverage.missing_field_counts || {};
      qs('coverageChips').innerHTML = [
        ['未覆盖房间估算', coverage.unmonitored_room_estimate, 'warn'],
        ['字段缺口房间', coverage.rooms_with_missing_fields, 'warn'],
        ['陈旧房间', coverage.stale_room_count, 'warn'],
      ].concat(Object.entries(counts).map(([key, value]) => [key, value, value > 0 ? 'bad' : 'good']))
      .map(([k, v, kind]) => `<span class="chip ${kind}">${esc(k)}: ${fmt(v)}</span>`).join('');

      qs('coverageMissing').textContent = JSON.stringify({
        unmonitored_room_estimate: coverage.unmonitored_room_estimate,
        stale_room_ids: coverage.stale_room_ids,
        top_gap_rooms: coverage.rooms,
      }, null, 2);
    }

    function renderRooms() {
      const showFrame = qs('frameMode').checked;
      qs('roomGrid').innerHTML = state.rooms.slice(0, 24).map((room) => {
        const image = showFrame ? (room.keyframe || room.cover || '') : (room.cover || room.keyframe || '');
        return `
          <article class="room-card">
            <img src="${esc(image)}" alt="${esc(room.uname)}" />
            <div class="body">
              <div style="display:flex;justify-content:space-between;gap:8px;">
                <strong>${esc(room.uname)}</strong>
                <span class="small muted">#${room.room_id}</span>
              </div>
              <div style="margin-top:6px;">${esc(room.title)}</div>
              <div class="chips">
                <span class="chip">房间在线 ${fmt(room.room_online)}</span>
                <span class="chip">高能 ${fmt(room.active_online)}</span>
                <span class="chip">展示 ${fmt(room.display_online)}</span>
                <span class="chip">命中 ${fmt(room.matched_comment_count)}</span>
              </div>
              <div class="chips">
                ${(room.missing_fields || []).map((field) => `<span class="chip bad">${esc(field)}</span>`).join('')}
              </div>
            </div>
          </article>
        `;
      }).join('');

      qs('roomTable').innerHTML = state.rooms.map((room) => `
        <tr>
          <td>
            <div><strong>${esc(room.uname)}</strong> <span class="small muted">#${room.room_id}</span></div>
            <div class="small muted">${esc(room.title)}</div>
            <div class="small muted">${esc(room.area_name || '')}</div>
          </td>
          <td>
            <div>房间在线: ${fmt(room.room_online)}</div>
            <div>高能观众: ${fmt(room.active_online)}</div>
            <div>展示热度: ${fmt(room.display_online)}</div>
            <div>累计观看: ${fmt(room.watched_text)}</div>
          </td>
          <td>
            <div>总评论: ${fmt(room.total_comment_count)}</div>
            <div>命中评论: ${fmt(room.matched_comment_count)}</div>
          </td>
          <td>${(room.missing_fields || []).map((field) => `<span class="hit">${esc(field)}</span>`).join('') || '-'}</td>
          <td><button class="alt" onclick="prioritizeRoom(${room.room_id})">优先抓</button></td>
        </tr>
      `).join('');
    }

    function renderComments() {
      qs('commentList').innerHTML = state.comments.map((item) => `
        <div class="comment">
          <div style="display:flex;justify-content:space-between;gap:10px;">
            <strong>${esc(item.room_owner)} · ${esc(item.room_title)}</strong>
            <span class="small muted">${esc(item.captured_at)}</span>
          </div>
          <div class="small muted">${esc(item.user_name)} (${esc(item.user_id)}) · ${esc(item.source)}</div>
          <div class="comment-text">${esc(item.text)}</div>
          <div>${(item.matched_keywords || []).map((word) => `<span class="hit">${esc(word)}</span>`).join('')}</div>
          <div style="margin-top:8px;">
            <button class="alt" onclick="prioritizeRoom(${item.room_id})">抓这个房间</button>
          </div>
        </div>
      `).join('');
    }

    function renderDebug() {
      qs('debugList').innerHTML = state.debug.slice(0, 12).map((item) => `
        <details>
          <summary>${esc(item.label)} · ${esc(item.method)} · ${esc(item.status_code ?? '-')}</summary>
          <div class="small muted" style="margin:8px 0;">${esc(item.url)}</div>
          <div class="mono">${esc(item.curl || item.url)}</div>
          ${item.error_message ? `<div class="mono" style="margin-top:8px;">${esc(item.error_message)}</div>` : ''}
        </details>
      `).join('');
    }

    async function prioritizeRoom(roomId) {
      await postJson('/api/control/prioritize-room', { room_id: roomId });
      await refreshData();
    }

    async function refreshData() {
      const keyword = encodeURIComponent(qs('keywordInput').value.trim());
      const matchedOnly = qs('matchedOnly').checked ? '1' : '0';
      const missingOnly = qs('missingOnly').checked ? '1' : '0';
      const [areas, summary, coverage, rooms, comments, debug] = await Promise.all([
        getJson('/api/areas'),
        getJson('/api/summary'),
        getJson('/api/coverage'),
        getJson(`/api/rooms?limit=120&matched_only=${matchedOnly}&missing_only=${missingOnly}&keyword=${keyword}`),
        getJson(`/api/comments?limit=150&matched_only=${matchedOnly}&keyword=${keyword}`),
        getJson('/api/debug?limit=20'),
      ]);
      state.areas = areas;
      state.summary = summary;
      state.selectedArea = summary.selected_area;
      state.coverage = coverage;
      state.rooms = rooms;
      state.comments = comments;
      state.debug = debug;
      renderAreas();
      renderSummary();
      renderCoverage();
      renderRooms();
      renderComments();
      renderDebug();
    }

    qs('startBtn').addEventListener('click', async () => {
      await postJson('/api/control/start');
      await refreshData();
    });
    qs('stopBtn').addEventListener('click', async () => {
      await postJson('/api/control/stop');
      await refreshData();
    });
    qs('refreshBtn').addEventListener('click', async () => {
      await postJson('/api/control/refresh');
      await refreshData();
    });
    qs('areaSelect').addEventListener('change', async (event) => {
      const [parent_area_id, area_id] = event.target.value.split(':').map((v) => Number(v));
      await postJson('/api/control/select-area', { parent_area_id, area_id });
      await refreshData();
    });
    qs('keywordInput').addEventListener('change', refreshData);
    qs('matchedOnly').addEventListener('change', refreshData);
    qs('missingOnly').addEventListener('change', refreshData);
    qs('frameMode').addEventListener('change', renderRooms);

    refreshData();
    setInterval(refreshData, 12000);
  </script>
</body>
</html>
''';
  }
}
