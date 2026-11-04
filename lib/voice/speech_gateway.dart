import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/firebase_session.dart';
import '../core/app_failure.dart';

abstract interface class SpeechGateway {
  Future<String> transcribe(Uint8List wave);
  Future<List<Uint8List>> speech(String messageId);
  void close();
}

class HttpSpeechGateway implements SpeechGateway {
  HttpSpeechGateway({
    required this.baseUrl,
    required this.publicKey,
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String baseUrl, publicKey;
  final SessionGateway session;
  final http.Client _client;
  Future<http.Response> _post(String action, Object body, String type) async {
    final identity = session.userId;
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await session.token(refresh: attempt == 1);
      if (identity != session.userId) {
        throw const AppFailure(
          'session_changed',
          'Please reconnect your session.',
        );
      }
      final response = await _client
          .post(
            Uri.parse('$baseUrl/functions/v1/voice?action=$action'),
            headers: {
              'Authorization': 'Bearer $token',
              'apikey': publicKey,
              'Content-Type': type,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 65));
      if (identity != session.userId) {
        throw const AppFailure(
          'session_changed',
          'Please reconnect your session.',
        );
      }
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        Map<String, dynamic> error = {};
        try {
          error = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        throw AppFailure(
          error['code'] as String? ?? 'voice_unavailable',
          error['message'] as String? ?? 'Voice interrupted. Please try again.',
          retryable: true,
        );
      }
      return response;
    }
    throw const AppFailure('unauthenticated', 'Please reconnect your session.');
  }

  @override
  Future<String> transcribe(Uint8List wave) async {
    final response = await _post('transcribe', wave, 'audio/wav');
    final value = jsonDecode(response.body)['text'];
    if (value is! String || value.trim().isEmpty || value.length > 12000) {
      throw const AppFailure(
        'no_speech',
        'I could not hear clear speech. Please try again.',
      );
    }
    return value;
  }

  @override
  Future<List<Uint8List>> speech(String messageId) async {
    final identity = session.userId;
    final segments = <Uint8List>[];
    var count = 1;
    for (var part = 0; part < count; part++) {
      if (identity != session.userId) {
        throw const AppFailure(
          'session_changed',
          'Please reconnect your session.',
        );
      }
      final response = await _post(
        'speech',
        jsonEncode({'message_id': messageId, 'part': part}),
        'application/json',
      );
      count = int.tryParse(response.headers['x-morrow-audio-parts'] ?? '') ?? 0;
      if (count < 1 ||
          count > 12 ||
          response.bodyBytes.length > 4 * 1024 * 1024 ||
          !['audio/mpeg', 'audio/wav'].any(
            (type) => (response.headers['content-type'] ?? '').startsWith(type),
          )) {
        throw const AppFailure(
          'invalid_audio',
          'Voice interrupted. Please try again.',
        );
      }
      segments.add(response.bodyBytes);
    }
    return segments;
  }

  @override
  void close() => _client.close();
}
