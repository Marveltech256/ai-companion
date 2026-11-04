import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'app_failure.dart';

/// Public identifiers only. AI and Supabase service-role secrets are never
/// accepted by the client configuration.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseKey,
    required this.firebaseProjectId,
    required this.firebaseApiKey,
    required this.firebaseSenderId,
    required this.firebaseAppId,
    this.firebaseAuthDomain,
    this.firebaseStorageBucket,
    this.iosBundleId,
    this.googleServerClientId,
    this.googleIosClientId,
    this.googleIosConfigured = false,
  });
  final String supabaseUrl, supabaseKey, firebaseProjectId, firebaseApiKey;
  final String firebaseSenderId, firebaseAppId;
  final String? firebaseAuthDomain, firebaseStorageBucket, iosBundleId;
  final String? googleServerClientId, googleIosClientId;
  final bool googleIosConfigured;

  factory AppConfig.fromEnvironment() => AppConfig(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    firebaseProjectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    firebaseApiKey: kIsWeb
        ? const String.fromEnvironment(
            'FIREBASE_WEB_API_KEY',
            defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
          )
        : defaultTargetPlatform == TargetPlatform.iOS
        ? const String.fromEnvironment(
            'FIREBASE_IOS_API_KEY',
            defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
          )
        : const String.fromEnvironment(
            'FIREBASE_ANDROID_API_KEY',
            defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
          ),
    firebaseSenderId: const String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    ),
    firebaseAppId: kIsWeb
        ? const String.fromEnvironment('FIREBASE_WEB_APP_ID')
        : defaultTargetPlatform == TargetPlatform.iOS
        ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
        : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    firebaseAuthDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    firebaseStorageBucket: const String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
    ),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    googleServerClientId: const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    googleIosClientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    googleIosConfigured: const bool.fromEnvironment('GOOGLE_IOS_CONFIGURED'),
  );

  void validate() {
    if ([
      supabaseUrl,
      supabaseKey,
      firebaseProjectId,
      firebaseApiKey,
      firebaseSenderId,
      firebaseAppId,
    ].any((v) => v.trim().isEmpty)) {
      throw const AppFailure(
        'configuration_required',
        'Project configuration is required.',
      );
    }
    final uri = Uri.tryParse(supabaseUrl);
    final local = uri?.host == 'localhost' || uri?.host == '127.0.0.1';
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' &&
            !(local && uri.scheme == 'http' && !kReleaseMode))) {
      throw const AppFailure(
        'invalid_configuration',
        'Use a secure backend URL.',
      );
    }
    if (supabaseKey.startsWith('sb_secret_')) {
      throw const AppFailure(
        'private_key_in_client',
        'A public Supabase key is required.',
      );
    }
    // Legacy service-role keys are JWTs; refuse them before network access.
    if (supabaseKey.startsWith('eyJ')) {
      // Clients should use the current publishable format. Legacy JWT keys
      // must be migrated rather than risking a service-role key in a build.
      throw const AppFailure(
        'legacy_key_in_client',
        'Use a Supabase publishable key (sb_publishable_).',
      );
    }
  }

  FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: firebaseApiKey,
    appId: firebaseAppId,
    messagingSenderId: firebaseSenderId,
    projectId: firebaseProjectId,
    authDomain: firebaseAuthDomain,
    storageBucket: firebaseStorageBucket,
    iosBundleId: iosBundleId,
  );
}
