import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/app_failure.dart';
import 'review_guest.dart';

abstract interface class SessionGateway {
  String? get userId;
  Stream<String?> get changes;
  Future<void> start();
  Future<String> token({bool refresh = false});
  Future<void> signOut();
}

abstract interface class EmailSessionGateway {
  String? get email;
  bool get isAnonymous;
  Future<void> signInWithEmail(String email, String password);
  Future<void> linkEmail(String email, String password);
  Future<void> reauthenticate(String email, String password);
}

abstract interface class AccountSessionGateway {
  Future<void> createEmailAccount(String email, String password);
  Future<void> googleSignIn({bool link = false, bool reauthenticate = false});
  Future<void> resetPassword(String email);
}

class FirebaseSession
    implements
        SessionGateway,
        EmailSessionGateway,
        AccountSessionGateway,
        ReviewGuestGateway {
  FirebaseSession(
    this.auth, {
    this.googleServerClientId,
    this.googleIosClientId,
    this.googleIosConfigured = false,
    this.googleCredential,
    this.web = kIsWeb,
    this.reviewAccess,
  });
  final FirebaseAuth auth;
  final HttpReviewAccess? reviewAccess;
  String? _reviewOwner;
  @override
  bool get isReviewGuest => _reviewOwner != null && _reviewOwner == userId;
  @override
  Future<bool> reviewGuestAvailable() async =>
      await reviewAccess?.available() ?? false;
  @override
  Future<void> signInReviewGuest(String code, {bool renew = false}) async {
    if (reviewAccess == null || (renew && !isReviewGuest)) {
      throw const AppFailure(
        'review_unavailable',
        'Guest review access is not available.',
      );
    }
    final previous = userId;
    final custom = await reviewAccess!.enter(
      code,
      token: renew ? await token() : null,
    );
    if (userId != previous) {
      throw const AppFailure(
        'session_changed',
        'The account changed. Please try again.',
      );
    }
    await auth.signInWithCustomToken(custom);
    final result = await auth.currentUser?.getIdTokenResult();
    _reviewOwner = result?.claims?['review_guest'] == true ? userId : null;
  }

  final String? googleServerClientId, googleIosClientId;
  final bool googleIosConfigured, web;
  final Future<AuthCredential> Function()? googleCredential;
  static Future<void>? _googleInitialization;
  @override
  String? get email => auth.currentUser?.email;
  @override
  bool get isAnonymous => auth.currentUser?.isAnonymous ?? true;
  @override
  String? get userId => auth.currentUser?.uid;
  @override
  Stream<String?> get changes => auth.idTokenChanges().map((u) {
    if (u?.uid != _reviewOwner) _reviewOwner = null;
    return u?.uid;
  });
  @override
  Future<void> start() async {
    if (auth.currentUser == null || auth.currentUser!.isAnonymous) {
      throw const AppFailure('sign_in_required', 'Sign in to continue.');
    }
  }

  @override
  Future<String> token({bool refresh = false}) async {
    final user = auth.currentUser;
    String? value;
    try {
      value = await user?.getIdToken(refresh);
      if (user != null && user.uid.startsWith('review_')) {
        final result = await user.getIdTokenResult();
        if (auth.currentUser?.uid == user.uid) {
          _reviewOwner = result.claims?['review_guest'] == true
              ? user.uid
              : null;
        }
      } else {
        _reviewOwner = null;
      }
    } on FirebaseAuthException catch (error) {
      if (auth.currentUser?.uid != user?.uid) {
        throw const AppFailure(
          'session_changed',
          'Please reconnect your session.',
        );
      }
      if ({
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      }.contains(error.code)) {
        try {
          await auth.signOut();
        } catch (_) {}
        throw const AppFailure('session_revoked', 'Please sign in again.');
      }
      throw const AppFailure(
        'auth_unavailable',
        'Connection unavailable. Please try again.',
        retryable: true,
      );
    }
    if (value == null) {
      throw const AppFailure(
        'unauthenticated',
        'Please reconnect your session.',
      );
    }
    return value;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> createEmailAccount(String email, String password) async {
    await auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> resetPassword(String email) =>
      auth.sendPasswordResetEmail(email: email);
  Future<AuthCredential> _googleCredential() async {
    if (googleCredential != null) return googleCredential!();
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw const AppFailure(
        'google_unavailable',
        'Google sign-in is available on Android, iOS, and the web.',
      );
    }
    if ((googleServerClientId ?? '').isEmpty ||
        (defaultTargetPlatform == TargetPlatform.iOS &&
            ((googleIosClientId ?? '').isEmpty || !googleIosConfigured))) {
      throw const AppFailure(
        'google_configuration_required',
        'Google sign-in is not connected in this build yet. Try email instead.',
      );
    }
    try {
      await (_googleInitialization ??= GoogleSignIn.instance.initialize(
        serverClientId: googleServerClientId,
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? googleIosClientId
            : null,
      ));
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw const AppFailure(
          'google_unavailable',
          'Google could not verify this sign-in. Please try again.',
        );
      }
      return GoogleAuthProvider.credential(idToken: token);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AppFailure(
          'sign_in_cancelled',
          'Google sign-in was cancelled.',
        );
      }
      throw const AppFailure(
        'google_unavailable',
        'Google sign-in is unavailable. Check your connection or try email instead.',
      );
    }
  }

  @override
  Future<void> googleSignIn({
    bool link = false,
    bool reauthenticate = false,
  }) async {
    final user = auth.currentUser;
    if ((link || reauthenticate) && user == null) {
      throw const AppFailure('unauthenticated', 'Sign in first.');
    }
    if (web) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      if (reauthenticate) {
        await user!.reauthenticateWithPopup(provider);
      } else if (link) {
        await user!.linkWithPopup(provider);
      } else {
        await auth.signInWithPopup(provider);
      }
    } else {
      final credential = await _googleCredential();
      if ((link || reauthenticate) && auth.currentUser?.uid != user!.uid) {
        throw const AppFailure(
          'session_changed',
          'The account changed. Please sign in again.',
        );
      }
      if (reauthenticate) {
        await user!.reauthenticateWithCredential(credential);
      } else if (link) {
        await user!.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }
    }
    if ((link || reauthenticate) && auth.currentUser?.uid != user!.uid) {
      throw const AppFailure(
        'session_changed',
        'The account changed. Please sign in again.',
      );
    }
    await auth.currentUser?.getIdToken(true);
  }

  @override
  Future<void> linkEmail(String email, String password) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AppFailure('unauthenticated', 'Sign in first.');
    }
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> reauthenticate(String email, String password) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AppFailure('unauthenticated', 'Sign in first.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    await user.getIdToken(true);
  }

  @override
  Future<void> signOut() async {
    await auth.signOut();
    if (!web && _googleInitialization != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }
}
