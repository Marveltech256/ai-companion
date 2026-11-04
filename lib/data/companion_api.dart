import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/firebase_session.dart';
import '../core/app_failure.dart';

abstract interface class CompanionApi {
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]);
  Stream<Map<String, dynamic>> turn(Map<String, dynamic> body);
  void close();
}

String apiEndpoint(String action) =>
    {
      'billing_status',
      'billing_prepare',
      'billing_verify',
      'billing_refresh',
    }.contains(action)
    ? 'billing'
    : {
        'export_data',
        'erasure_status',
        'request_account_erasure',
        'set_conversation_retention',
      }.contains(action)
    ? 'privacy'
    : 'companion-api';

/// Firebase tokens are verified by the Edge Function, never trusted by decoding
/// them in the client. The function applies ownership on every database call.
class HttpCompanionApi implements CompanionApi {
  HttpCompanionApi({
    required this.baseUrl,
    required this.publishableKey,
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl, publishableKey;
  final SessionGateway session;
  final http.Client _client;

  Future<http.StreamedResponse> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final identity = session.userId;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await session.token(refresh: attempt == 1);
      if (identity != session.userId) {
        throw const AppFailure(
          'session_changed',
          'Please reconnect your session.',
        );
      }
      final request =
          http.Request('POST', Uri.parse('$baseUrl/functions/v1/$endpoint'))
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'apikey': publishableKey,
              'Content-Type': 'application/json',
            })
            ..body = jsonEncode(body);
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 && attempt == 0) {
        await response.stream.drain<void>();
        continue;
      }
      return response;
    }
    throw const AppFailure('unauthenticated', 'Please reconnect your session.');
  }

  Future<Never> _fail(http.StreamedResponse response) async {
    Map<String, dynamic> error = {};
    try {
      error = jsonDecode(
        await response.stream.bytesToString(),
      ) as Map<String, dynamic>;
    } catch (_) {
      /* Do not expose proxy/provider error bodies. */
    }
    throw AppFailure(
      error['code'] as String? ?? 'backend_error',
      error['message'] as String? ??
          'Connection unavailable. Please try again.',
      retryable: response.statusCode == 429 || response.statusCode >= 500,
    );
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final response = await _post(apiEndpoint(action), {
        'action': action,
        ...body,
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _fail(response);
      }
      return jsonDecode(
        await response.stream.bytesToString().timeout(
          const Duration(seconds: 30),
        ),
      ) as Map<String, dynamic>;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        'network_error',
        'Connection unavailable. Please try again.',
        retryable: true,
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> turn(Map<String, dynamic> body) async* {
    try {
      final response = await _post('conversation-turn', body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _fail(response);
      }
      var completed = false;
      await for (final event in decodeServerEvents(
        response.stream.timeout(const Duration(seconds: 45)),
      )) {
        if (event['type'] == 'error') {
          throw AppFailure(
            event['code'] as String? ?? 'generation_failed',
            event['message'] as String? ??
                'Reply interrupted. Tap send to retry.',
            retryable: true,
          );
        }
        if (event['type'] == 'done') completed = true;
        yield event;
      }
      if (!completed) {
        throw const AppFailure(
          'interrupted',
          'Reply interrupted. Tap send to retry.',
          retryable: true,
        );
      }
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        'network_error',
        'Reply interrupted. Tap send to retry.',
        retryable: true,
      );
    }
  }

  @override
  void close() => _client.close();
}

/// SSE framing can span arbitrary UTF-8/network chunks, CRLF, and multiple data
/// lines. Parsing is shared by the actual transport and protocol tests.
Stream<Map<String, dynamic>> decodeServerEvents(
  Stream<List<int>> bytes,
) async* {
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final payload = data.join('\n');
        data.clear();
        if (payload != '[DONE]') {
          yield jsonDecode(payload) as Map<String, dynamic>;
        }
      }
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
    }
  }
  if (data.isNotEmpty && data.join('\n') != '[DONE]') {
    yield jsonDecode(data.join('\n')) as Map<String, dynamic>;
  }
}
