import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_failure.dart';

abstract interface class ReviewGuestGateway {
  bool get isReviewGuest;
  Future<bool> reviewGuestAvailable();
  Future<void> signInReviewGuest(String code, {bool renew = false});
}

class HttpReviewAccess {
  HttpReviewAccess({required this.baseUrl, required this.publicKey});
  final String baseUrl, publicKey;
  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/functions/v1/review-access'),
          headers: {
            'apikey': publicKey,
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const AppFailure(
        'review_unavailable',
        'Guest review access is not available. Please sign in.',
      );
    }
    if (response.statusCode != 200) {
      throw AppFailure(
        data['code'] as String? ?? 'review_unavailable',
        data['message'] as String? ??
            'Guest review access is not available. Please sign in.',
      );
    }
    return data;
  }

  Future<bool> available() async {
    try {
      return (await _request({'action': 'status'}))['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> enter(String code, {String? token}) async {
    final result = await _request({
      'action': 'enter',
      'access_code': code.trim(),
      'renew': token != null,
    }, token: token);
    if (result['custom_token'] is! String) {
      throw const AppFailure(
        'review_unavailable',
        'Guest review access could not be opened.',
      );
    }
    return result['custom_token'] as String;
  }
}
