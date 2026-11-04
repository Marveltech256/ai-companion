import 'package:ai_companion/auth/firebase_session.dart';
import 'package:ai_companion/core/app_failure.dart';

import 'test_services.dart';

class AccountTestSession extends TestSession
    implements EmailSessionGateway, AccountSessionGateway {
  @override
  bool isAnonymous = true;
  @override
  String? email;
  int creates = 0, links = 0, logins = 0, googleLogins = 0, resets = 0;
  bool cancelGoogle = false;
  void _authenticated(String id, String address) {
    isAnonymous = false;
    email = address;
    switchUser(id);
  }

  @override
  Future<void> createEmailAccount(String email, String password) async {
    creates++;
    _authenticated('email-user', email);
  }

  @override
  Future<void> linkEmail(String email, String password) async {
    links++;
    _authenticated(uid!, email);
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    logins++;
    _authenticated('returning-user', email);
  }

  @override
  Future<void> googleSignIn({
    bool link = false,
    bool reauthenticate = false,
  }) async {
    googleLogins++;
    if (cancelGoogle) {
      throw const AppFailure(
        'sign_in_cancelled',
        'Google sign-in was cancelled.',
      );
    }
    if (reauthenticate) return;
    _authenticated(link ? uid! : 'google-user', 'person@example.com');
  }

  @override
  Future<void> reauthenticate(String email, String password) async {}
  @override
  Future<void> resetPassword(String email) async {
    resets++;
  }

  @override
  Future<void> signOut() async {
    isAnonymous = true;
    email = null;
    await super.signOut();
  }
}

class AccountTestApi extends TestApi {
  AccountTestApi(this.session) {
    companion = {...companion!, 'learning_enabled': true};
  }
  final AccountTestSession session;
  final profiles = <String, Map<String, dynamic>>{};
  bool failProfile = false;
  int bootstraps = 0;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    if (action == 'bootstrap') {
      bootstraps++;
      return {'profile': profiles[session.uid] ?? {}, 'companion': companion};
    }
    if (action == 'save_personal_profile') {
      if (failProfile) {
        throw const AppFailure(
          'username_taken',
          'That username is already taken. Choose another one.',
        );
      }
      profiles[session.uid!] = {...?profiles[session.uid!], ...body};
      return {'profile': profiles[session.uid]};
    }
    if (action == 'save_introduction') {
      profiles[session.uid!] = {
        ...?profiles[session.uid!],
        ...body,
        'introduction_completed_at': '2026-11-03T12:00:00Z',
      };
      return {'profile': profiles[session.uid]};
    }
    if (action == 'activate_friend_mode') {
      companion = {
        ...companion!,
        'memory_enabled': true,
        'learning_enabled': true,
      };
      return {'companion': companion};
    }
    if (action == 'set_reply_mode') {
      profiles[session.uid!] = {
        ...?profiles[session.uid!],
        'reply_mode': body['mode'],
      };
      return {'profile': profiles[session.uid]};
    }
    if (action == 'save_timezone') {
      profiles[session.uid!] = {
        ...?profiles[session.uid!],
        'timezone': body['timezone'],
        'timezone_automatic': body['automatic'],
      };
      return {'profile': profiles[session.uid]};
    }
    if (action == 'complete_welcome') {
      profiles[session.uid!] = {
        ...profiles[session.uid!]!,
        'welcome_completed_at': '2026-11-03T12:01:00Z',
      };
      return {'profile': profiles[session.uid]};
    }
    return super.call(action, body);
  }
}
