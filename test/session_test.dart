import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/auth/firebase_session.dart';
import 'package:ai_companion/core/app_failure.dart';

class TokenUser extends Fake implements User {
  TokenUser(this.code);
  final String code;
  @override
  String get uid => code;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      throw FirebaseAuthException(code: code);
}

class DelayedTokenUser extends TokenUser {
  DelayedTokenUser() : super('old-user');
  final result = Completer<String?>();
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) => result.future;
}

class TokenAuth extends Fake implements FirebaseAuth {
  TokenAuth(String code) : user = TokenUser(code);
  User? user;
  int signouts = 0;
  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signouts++;
    user = null;
  }
}

class CredentialResult extends Fake implements UserCredential {}

class AccountUser extends Fake implements User {
  AccountUser(this.id);
  final String id;
  int links = 0, reauthentications = 0;
  @override
  String get uid => id;
  @override
  bool get isAnonymous => false;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'verified-token';
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    links++;
    return CredentialResult();
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    reauthentications++;
    return CredentialResult();
  }
}

class GuestUser extends AccountUser {
  GuestUser() : super('guest');
  @override
  bool get isAnonymous => true;
}

class AccountAuth extends TokenAuth {
  AccountAuth() : super('initial');
  int creates = 0, credentialLogins = 0, popups = 0;
  AuthCredential? credential;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    user = AccountUser('email-user');
    return CredentialResult();
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialLogins++;
    this.credential = credential;
    user = AccountUser('google-user');
    return CredentialResult();
  }

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    expect(provider.providerId, 'google.com');
    popups++;
    user = AccountUser('web-google-user');
    return CredentialResult();
  }
}

void main() {
  test('starting a session requires a registered account and never creates a guest', () async {
    final auth = AccountAuth()..user = null;
    final session = FirebaseSession(auth);
    final denied = isA<AppFailure>().having(
      (e) => e.code,
      'code',
      'sign_in_required',
    );
    await expectLater(session.start(), throwsA(denied));
    auth.user = GuestUser();
    await expectLater(session.start(), throwsA(denied));
    auth.user = AccountUser('registered');
    await session.start();
    expect(auth.creates, 0);
    expect(auth.credentialLogins, 0);
  });
  test('Firebase signup calls createUserWithEmailAndPassword and Google uses a Firebase Google credential', () async {
    final auth = AccountAuth();
    final session = FirebaseSession(
      auth,
      googleCredential: () async =>
          GoogleAuthProvider.credential(idToken: 'test-token'),
    );
    await session.createEmailAccount('marvin@example.com', 'test-password');
    expect(auth.creates, 1);
    expect(auth.currentUser!.uid, 'email-user');
    await session.googleSignIn();
    expect(auth.credentialLogins, 1);
    expect(auth.credential!.providerId, 'google.com');
    final user = auth.user as AccountUser;
    await session.googleSignIn(link: true);
    expect(user.links, 1);
    expect(auth.credentialLogins, 1);
    await session.googleSignIn(reauthenticate: true);
    expect(user.reauthentications, 1);
  });
  test('web Google login uses Firebase popup and a cancelled native link cannot modify a new identity', () async {
    final auth = AccountAuth();
    await FirebaseSession(auth, web: true).googleSignIn();
    expect(auth.popups, 1);
    final pending = Completer<AuthCredential>();
    final old = AccountUser('guest');
    auth.user = old;
    final operation = FirebaseSession(
      auth,
      googleCredential: () => pending.future,
    ).googleSignIn(link: true);
    final result = expectLater(
      operation,
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'session_changed'),
      ),
    );
    auth.user = AccountUser('new-user');
    pending.complete(GoogleAuthProvider.credential(idToken: 'test-token'));
    await result;
    expect(old.links, 0);
    expect(auth.user!.uid, 'new-user');
  });
  test('a revoked old refresh cannot sign out a different account', () async {
    final auth = TokenAuth('old-user');
    final oldUser = DelayedTokenUser();
    auth.user = oldUser;
    final request = FirebaseSession(auth).token(refresh: true);
    final result = expectLater(
      request,
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'session_changed'),
      ),
    );
    auth.user = TokenUser('new-user');
    oldUser.result.completeError(FirebaseAuthException(code: 'user-disabled'));
    await result;
    expect(auth.signouts, 0);
    expect(auth.currentUser?.uid, 'new-user');
  });
  test('revoked Firebase refresh clears the local identity', () async {
    final auth = TokenAuth('user-disabled');
    await expectLater(
      FirebaseSession(auth).token(refresh: true),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'session_revoked'),
      ),
    );
    expect(auth.signouts, 1);
    expect(auth.currentUser, isNull);
  });
  test('a temporary Firebase network error preserves the current session for retry', () async {
    final auth = TokenAuth('network-request-failed');
    await expectLater(
      FirebaseSession(auth).token(refresh: true),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'auth_unavailable'),
      ),
    );
    expect(auth.signouts, 0);
    expect(auth.currentUser, isNotNull);
  });
}
