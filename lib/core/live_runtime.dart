import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../auth/firebase_session.dart';
import '../auth/review_guest.dart';
import '../data/companion_api.dart';
import 'app_config.dart';
import 'app_failure.dart';
import '../notifications/push_gateway.dart';
import '../voice/speech_gateway.dart';

class LiveRuntime {
  LiveRuntime(this.session, this.api, this.speech);
  final SessionGateway session;
  final CompanionApi api;
  final SpeechGateway speech;
  final PushGateway push = FirebasePushGateway();

  static Future<LiveRuntime> connect(AppConfig config) async {
    config.validate();
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(options: config.firebaseOptions)
        : Firebase.app();
    if (app.options.projectId != config.firebaseProjectId) {
      throw const AppFailure(
        'project_mismatch',
        'This build is connected to a different Firebase project.',
      );
    }
    final session = FirebaseSession(
      FirebaseAuth.instanceFor(app: app),
      googleServerClientId: config.googleServerClientId,
      googleIosClientId: config.googleIosClientId,
      googleIosConfigured: config.googleIosConfigured,
      reviewAccess: HttpReviewAccess(
        baseUrl: config.supabaseUrl,
        publicKey: config.supabaseKey,
      ),
    );
    final transport = HttpCompanionApi(
      baseUrl: config.supabaseUrl,
      publishableKey: config.supabaseKey,
      session: session,
    );
    return LiveRuntime(
      session,
      transport,
      HttpSpeechGateway(
        baseUrl: config.supabaseUrl,
        publicKey: config.supabaseKey,
        session: session,
      ),
    );
  }
}
