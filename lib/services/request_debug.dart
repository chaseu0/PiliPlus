import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

class RequestDebugRecord {
  const RequestDebugRecord({
    required this.id,
    required this.label,
    required this.category,
    required this.method,
    required this.url,
    required this.createdAt,
    this.curl,
    this.requestBody,
    this.responsePreview,
    this.errorMessage,
    this.statusCode,
  });

  final String id;
  final String label;
  final String category;
  final String method;
  final String url;
  final DateTime createdAt;
  final String? curl;
  final String? requestBody;
  final String? responsePreview;
  final String? errorMessage;
  final int? statusCode;
}

class RequestDebugService {
  RequestDebugService._();

  static final RequestDebugService instance = RequestDebugService._();
  static const int _maxRecords = 240;

  final RxList<RequestDebugRecord> records = <RequestDebugRecord>[].obs;

  void recordFromResponse(
    Response response, {
    required String label,
    required String category,
  }) {
    final requestOptions = response.requestOptions;
    _insert(
      RequestDebugRecord(
        id: _makeId(),
        label: label,
        category: category,
        method: requestOptions.method,
        url: requestOptions.uri.toString(),
        createdAt: DateTime.now(),
        curl: buildCurl(requestOptions),
        requestBody: _stringifyData(requestOptions.data),
        responsePreview: _stringifyData(response.data),
        statusCode: response.statusCode,
      ),
    );
  }

  void recordError({
    required RequestOptions requestOptions,
    Response? response,
    Object? error,
    required String label,
    required String category,
  }) {
    _insert(
      RequestDebugRecord(
        id: _makeId(),
        label: label,
        category: category,
        method: requestOptions.method,
        url: requestOptions.uri.toString(),
        createdAt: DateTime.now(),
        curl: buildCurl(requestOptions),
        requestBody: _stringifyData(requestOptions.data),
        responsePreview: _stringifyData(response?.data),
        errorMessage: _truncate(error?.toString()),
        statusCode: response?.statusCode,
      ),
    );
  }

  void recordManual({
    required String label,
    required String category,
    required String method,
    required String url,
    String? requestBody,
    String? responsePreview,
    String? errorMessage,
  }) {
    _insert(
      RequestDebugRecord(
        id: _makeId(),
        label: label,
        category: category,
        method: method,
        url: url,
        createdAt: DateTime.now(),
        requestBody: _truncate(requestBody),
        responsePreview: _truncate(responsePreview),
        errorMessage: _truncate(errorMessage),
      ),
    );
  }

  static String buildCurl(RequestOptions options) {
    final buffer = StringBuffer('curl');
    buffer.write(' -X ${options.method.toUpperCase()}');
    options.headers.forEach((key, value) {
      if (value == null) {
        return;
      }
      final headerValue = value is List ? value.join('; ') : value.toString();
      buffer.write(" \\\n  -H '${_escape(headerValue, prefix: '$key: ')}'");
    });
    final body = _stringifyData(options.data);
    if (body != null && body.isNotEmpty) {
      buffer.write(" \\\n  --data-raw '${_escape(body)}'");
    }
    buffer.write(" \\\n  '${_escape(options.uri.toString())}'");
    return buffer.toString();
  }

  static String _makeId() => DateTime.now().microsecondsSinceEpoch.toString();

  static String _escape(String value, {String prefix = ''}) {
    return '$prefix${value.replaceAll("'", r"'\''")}';
  }

  static String? _stringifyData(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is String) {
      return _truncate(data);
    }
    if (data is FormData) {
      final map = <String, dynamic>{};
      for (final field in data.fields) {
        map[field.key] = field.value;
      }
      if (data.files.isNotEmpty) {
        map['__files__'] = data.files.map((e) => e.key).toList();
      }
      return _truncate(const JsonEncoder.withIndent('  ').convert(map));
    }
    try {
      return _truncate(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {
      return _truncate(data.toString());
    }
  }

  static String? _truncate(String? value, {int max = 6000}) {
    if (value == null || value.isEmpty) {
      return value;
    }
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}\n...<truncated>';
  }

  void _insert(RequestDebugRecord record) {
    records.insert(0, record);
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
  }
}
