import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/firebase_session.dart';
import '../auth/review_guest.dart';
import '../core/app_failure.dart';
import '../data/companion_api.dart';
import '../data/models.dart';
import '../notifications/push_gateway.dart';

class CompanionController extends ChangeNotifier {
  CompanionController({
    required SessionGateway session,
    required CompanionApi api,
    PushGateway? push,
    bool journalOnly = false,
  }) : this._(session, api, push, journalOnly);
  CompanionController._(
    this._session,
    this._api,
    this._push,
    this.journalOnly,
  ) {
    final session = _session!;
    _identity = session.userId;
    _identityChanged = (uid) {
      if (uid == _identity) return;
      final creatingFirstSession =
          _identity == null && busy && !_authenticating;
      _identity = uid;
      _epoch++;
      companion = null;
      displayName = null;
      personalProfile = const PersonalProfile();
      homeSummary = null;
      conversations = [];
      welcomeAudioAvailable = false;
      billingAvailable = false;
      messages = [];
      memories = [];
      notificationPreferences = const NotificationPreferences();
      activeConversation = null;
      settingsSaved = true;
      error = null;
      loadingOlder = false;
      loadingConversation = false;
      _hasOlder = false;
      _revision++;
      _conversationRevision++;
      _saveQueue = Future.value();
      erasureStatus = null;
      exporting = false;
      busy = creatingFirstSession || _authenticating;
      sending = false;
      _retryId = null;
      _retryContent = null;
      _retryGreeting = false;
      _pendingPush = null;
      _newConversationId = null;
      _memoryPoll?.cancel();
      _memoryRevision++;
      _memoryPolls = 0;
      _notify();
      if (uid != null && !creatingFirstSession && !_authenticating) {
        unawaited(restore());
      }
    };
    _authSubscription = session.changes.listen((uid) {
      if (uid == session.userId) _identityChanged(uid);
    });
    _tokenSubscription = _push?.tokens.listen((token) {
      if (notificationPreferences.enabled && _session.userId != null) {
        unawaited(_registerToken(token).catchError((Object _) {}));
      }
    });
    if (_push is RoutedPushGateway) {
      final routed = _push as RoutedPushGateway;
      _routedOpenSubscription = routed.routedOpens.listen((route) {
        unawaited(_receivePush(route, true));
      });
      _receiptSubscription = routed.receipts.listen((route) {
        unawaited(_receivePush(route, false));
      });
      unawaited(
        routed
            .initialRoute()
            .then((route) async {
              if (route != null) await _receivePush(route, true);
            })
            .catchError((Object _) {}),
      );
    } else {
      _pushOpenSubscription = _push?.opens.listen((_) {
        _notificationOpen = true;
        _notify();
      });
      if (_push != null) {
        unawaited(
          _push
              .initialOpen()
              .then((open) {
                if (!_disposed && open) {
                  _notificationOpen = true;
                  _notify();
                }
              })
              .catchError((Object _) {}),
        );
      }
    }
  }
  CompanionController.unconfigured(this.error)
    : journalOnly = false,
      _session = null,
      _api = null,
      _push = null;
  final PushGateway? _push;
  final bool journalOnly;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<void>? _pushOpenSubscription;
  StreamSubscription<PushRoute>? _routedOpenSubscription, _receiptSubscription;
  PushRoute? _pendingPush;
  Future<void> _receivePush(PushRoute route, bool opened) async {
    if (_disposed) return;
    if (_session?.userId == null || companion == null || sending) {
      if (opened) _pendingPush = route;
      return;
    }
    final epoch = _epoch;
    try {
      final result = await _api!.call('checkin_receipt', {
        'id': route.checkinId,
        'opened': opened,
      });
      if (!_current(epoch) || !opened || result['conversation'] == null) return;
      await openConversation(
        Conversation.fromJson(
          Map<String, dynamic>.from(result['conversation']),
        ),
      );
      if (!_current(epoch)) return;
      _notificationOpen = true;
      _notify();
    } catch (_) {
      if (opened && _current(epoch)) {
        _pendingPush = route;
      }
    }
  }

  bool _notificationOpen = false;
  bool takeNotificationOpen() {
    final open = _notificationOpen;
    _notificationOpen = false;
    return open;
  }

  final SessionGateway? _session;
  final CompanionApi? _api;
  StreamSubscription<String?>? _authSubscription;
  String? _identity;
  int _epoch = 0, _revision = 0;
  int _conversationRevision = 0;
  String? _newConversationId;
  bool loadingOlder = false, _hasOlder = false;
  bool loadingConversation = false;
  bool _disposed = false;
  Future<void> _saveQueue = Future.value();
  Timer? _memoryPoll;
  int _memoryPolls = 0, _memoryRevision = 0;
  Companion? companion;
  String? displayName;
  PersonalProfile personalProfile = const PersonalProfile();
  Map<String, dynamic>? homeSummary;
  bool welcomeAudioAvailable = false;
  bool transcriptionAvailable = false;
  bool billingAvailable = false;
  bool _retryGreeting = false;
  AppFailure? error;
  bool busy = false, sending = false, settingsSaved = true;
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  List<CompanionMemory> memories = [];
  Conversation? activeConversation;
  NotificationPreferences notificationPreferences =
      const NotificationPreferences();
  String? _retryId, _retryContent;
  String? erasureStatus;
  bool exporting = false;

  bool get configured => _api != null;
  void clearNotice() {
    error = null;
    _notify();
  }

  Future<void> flushSettings() => _saveQueue;
  bool get supportsEmail => _session is EmailSessionGateway;
  bool get supportsAccounts => _session is AccountSessionGateway;
  bool reviewGuestAvailable = false;
  bool get reviewGuestAccount =>
      _session is ReviewGuestGateway &&
      (_session as ReviewGuestGateway).isReviewGuest;
  Future<void> refreshReviewGuestAvailability() async {
    final session = _session;
    reviewGuestAvailable =
        session is ReviewGuestGateway &&
        await (session as ReviewGuestGateway).reviewGuestAvailable();
    _notify();
  }

  Future<void> enterReviewGuest(
    String code, {
    bool reauthenticate = false,
  }) async {
    final session = _session;
    if (session is! ReviewGuestGateway) {
      throw const AppFailure(
        'review_unavailable',
        'Guest review access is not available.',
      );
    }
    await _authenticate(
      () => (session as ReviewGuestGateway).signInReviewGuest(
        code,
        renew: reauthenticate,
      ),
      reauthenticate: reauthenticate,
      username:
          'review_${const Uuid().v4().replaceAll('-', '').substring(0, 20)}',
      preferredName: 'Reviewer',
    );
  }

  bool get registeredAccount =>
      supportsEmail && !anonymousAccount && userId != null;
  bool get needsAccountDetails =>
      registeredAccount &&
      ((personalProfile.username ?? '').isEmpty ||
          (personalProfile.preferredName ?? '').isEmpty);
  bool get authenticating => _authenticating;
  bool get needsWelcome =>
      registeredAccount &&
      personalProfile.introductionCompletedAt != null &&
      personalProfile.welcomeCompletedAt == null;
  bool get needsIntroduction =>
      registeredAccount && personalProfile.ageGroup == null;
  bool get needsFriendMode =>
      registeredAccount &&
      companion != null &&
      (!companion!.memoryEnabled || !companion!.learningEnabled);
  bool _authenticating = false;
  late final void Function(String?) _identityChanged;
  bool get anonymousAccount =>
      _session is EmailSessionGateway &&
      (_session as EmailSessionGateway).isAnonymous;
  String? get accountEmail => _session is EmailSessionGateway
      ? (_session as EmailSessionGateway).email
      : null;
  Future<void> authenticateEmail(
    String email,
    String password, {
    bool link = false,
    bool reauthenticate = false,
  }) async {
    final session = _session is EmailSessionGateway
        ? _session as EmailSessionGateway
        : null;
    if (session == null) {
      throw const AppFailure(
        'cloud_required',
        'Connect a cloud account first.',
      );
    }
    await _authenticate(() async {
      if (reauthenticate) {
        await session.reauthenticate(email, password);
      } else if (link) {
        await session.linkEmail(email, password);
      } else {
        await session.signInWithEmail(email, password);
      }
    }, reauthenticate: reauthenticate);
  }

  void _validateAccountNames(String username, String preferredName) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_]{2,29}$').hasMatch(username.trim())) {
      throw const AppFailure(
        'invalid_username',
        'Choose a username of 3–30 letters, numbers or underscores.',
      );
    }
    if (preferredName.trim().isEmpty || preferredName.trim().length > 80) {
      throw const AppFailure(
        'preferred_name_required',
        'Tell us what you would like to be called.',
      );
    }
  }

  Future<void> createAccount(
    String email,
    String password, {
    required String username,
    required String preferredName,
  }) async {
    _validateAccountNames(username, preferredName);
    final account = _session;
    if (account is! AccountSessionGateway) {
      throw const AppFailure(
        'cloud_required',
        'Connect a cloud account first.',
      );
    }
    await _authenticate(
      () async {
        if (anonymousAccount && userId != null) {
          await (_session as EmailSessionGateway).linkEmail(email, password);
        } else {
          await (account as AccountSessionGateway).createEmailAccount(
            email,
            password,
          );
        }
      },
      username: username,
      preferredName: preferredName,
    );
  }

  Future<void> authenticateGoogle({
    bool link = false,
    bool reauthenticate = false,
    String? username,
    String? preferredName,
  }) async {
    final account = _session;
    if (account is! AccountSessionGateway) {
      throw const AppFailure(
        'cloud_required',
        'Connect a cloud account first.',
      );
    }
    if (username != null || preferredName != null) {
      _validateAccountNames(username ?? '', preferredName ?? '');
    }
    await _authenticate(
      () => (account as AccountSessionGateway).googleSignIn(
        link: link,
        reauthenticate: reauthenticate,
      ),
      username: username,
      preferredName: preferredName,
      reauthenticate: reauthenticate,
    );
  }

  Future<void> _authenticate(
    Future<void> Function() action, {
    String? username,
    String? preferredName,
    bool reauthenticate = false,
  }) async {
    if (_authenticating) {
      throw const AppFailure(
        'auth_busy',
        'Please wait for the current sign-in.',
      );
    }
    final previous = userId;
    _authenticating = true;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      if (_disposed) return;
      _identityChanged(_session!.userId);
      if (reauthenticate) {
        if (userId != previous) {
          throw const AppFailure(
            'session_changed',
            'The account changed. Please sign in again.',
          );
        }
        return;
      }
      final epoch = _epoch;
      await restore();
      if (!_current(epoch)) {
        throw const AppFailure(
          'session_changed',
          'The account changed. Please sign in again.',
        );
      }
      if (error != null) throw error!;
      if (((personalProfile.username ?? '').isEmpty ||
              (personalProfile.preferredName ?? '').isEmpty) &&
          username != null &&
          preferredName != null) {
        await completeAccountDetails(username, preferredName);
      }
    } finally {
      _authenticating = false;
      busy = false;
      _notify();
    }
  }

  Future<void> completeAccountDetails(
    String username,
    String preferredName,
  ) async {
    _validateAccountNames(username, preferredName);
    final p = personalProfile;
    await savePersonalProfile(
      PersonalProfile(
        username: username.trim().toLowerCase(),
        preferredName: preferredName.trim(),
        displayName: p.displayName,
        timezone: p.timezone,
        language: p.language,
        location: p.location,
        ageGroup: p.ageGroup,
        introductionCompletedAt: p.introductionCompletedAt,
        welcomeCompletedAt: p.welcomeCompletedAt,
      ),
    );
  }

  Future<void> resetPassword(String email) async {
    final account = _session;
    if (account is! AccountSessionGateway) {
      throw const AppFailure(
        'cloud_required',
        'Connect a cloud account first.',
      );
    }
    await (account as AccountSessionGateway).resetPassword(email.trim());
  }

  String? get userId => _session?.userId;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void notice(String code, String message) {
    error = AppFailure(code, message);
    _notify();
  }

  AppFailure _failure(Object error) {
    if (error is AppFailure &&
        {
          'session_revoked',
          'account_deleted',
          'unauthenticated',
          'sign_in_required',
          'review_access_ended',
        }.contains(error.code)) {
      companion = null;
      messages = [];
      memories = [];
      conversations = [];
      displayName = null;
      personalProfile = const PersonalProfile();
      homeSummary = null;
      _memoryPoll?.cancel();
      welcomeAudioAvailable = false;
      unawaited(_session?.signOut());
      if (error.code == 'review_access_ended') reviewGuestAvailable = false;
    }
    return error is AppFailure
        ? error
        : const AppFailure(
            'unavailable',
            'Connection unavailable. Please try again.',
            retryable: true,
          );
  }

  Future<void> restore() async {
    if (_session?.userId == null) return;
    final epoch = _epoch;
    busy = true;
    _notify();
    try {
      final result = await _api!.call('bootstrap');
      if (!_current(epoch)) return;
      welcomeAudioAvailable =
          (result['capabilities'] as Map?)?['welcome_audio'] == true;
      transcriptionAvailable =
          (result['capabilities'] as Map?)?['transcription'] == true;
      billingAvailable = (result['capabilities'] as Map?)?['billing'] == true;
      displayName = (result['profile'] as Map?)?['display_name'] as String?;
      personalProfile = PersonalProfile.fromJson(
        Map<String, dynamic>.from(result['profile'] as Map? ?? {}),
      );
      displayName =
          personalProfile.preferredName ?? personalProfile.displayName;
      if (result['companion'] != null) {
        companion = Companion.fromJson(
          Map<String, dynamic>.from(result['companion']),
        );
      }
      error = null;
      if (companion != null && !needsIntroduction) {
        await loadConversations();
        await loadNotificationPreferences();
        await loadHomeActivity();
        final pending = _pendingPush;
        _pendingPush = null;
        if (pending != null) await _receivePush(pending, true);
      }
    } catch (e) {
      if (_current(epoch)) error = _failure(e);
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> create({
    required String name,
    required String style,
    required List<String> interests,
    required bool memoryEnabled,
    bool friendMode = false,
    CompanionPreferences? preferences,
  }) async {
    if (!configured || busy) return false;
    if (needsAccountDetails) {
      notice(
        'profile_required',
        'Save your username and preferred name first.',
      );
      return false;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await _session!.start();
      _identity = _session.userId;
      final epoch = _epoch;
      await _api!.call('bootstrap');
      if (!_current(epoch)) return false;
      var result = await _api.call('save_companion', {
        'name': name,
        'style': style,
        'interests': interests,
        'response_length': .5,
        'memory_enabled': memoryEnabled,
        'retention_days': null,
      });
      if (!_current(epoch)) return false;
      if (preferences != null) {
        result = await _api.call('save_friend_preferences', {
          'companion_id': (result['companion'] as Map)['id'],
          'name': name,
          ...preferences.toInput(),
        });
        if (!_current(epoch)) return false;
      }
      if (friendMode) {
        result = await _api.call('activate_friend_mode', {
          'companion_id': (result['companion'] as Map)['id'],
          'consent': true,
        });
      }
      if (!_current(epoch)) return false;
      companion = Companion.fromJson(
        Map<String, dynamic>.from(result['companion']),
      );
      return true;
    } catch (e) {
      error = _failure(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> savePersonalProfile(PersonalProfile desired) async {
    final epoch = _epoch;
    final result = await _api!.call('save_personal_profile', desired.toInput());
    if (!_current(epoch)) return;
    personalProfile = PersonalProfile.fromJson(
      Map<String, dynamic>.from(result['profile']),
    );
    displayName = personalProfile.preferredName ?? personalProfile.displayName;
    await loadNotificationPreferences();
    if (!_current(epoch)) return;
    _notify();
  }

  Future<void> saveFriendPreferences(
    String name,
    CompanionPreferences preferences,
  ) async {
    final current = companion;
    if (current == null) return;
    final epoch = _epoch;
    final result = await _api!.call('save_friend_preferences', {
      'companion_id': current.id,
      'name': name,
      ...preferences.toInput(),
    });
    if (!_current(epoch)) return;
    companion = Companion.fromJson(
      Map<String, dynamic>.from(result['companion']),
    );
    _notify();
  }

  Future<void> saveIntroduction({
    String? ageGroup,
    required String language,
    required String timezone,
    bool? automatic,
  }) async {
    final epoch = _epoch;
    final result = await _api!.call('save_introduction', {
      'age_group': ageGroup,
      'language': language,
      'timezone': timezone,
      'timezone_automatic': ?automatic,
    });
    if (!_current(epoch)) return;
    personalProfile = PersonalProfile.fromJson(
      Map<String, dynamic>.from(result['profile']),
    );
    _notify();
  }

  Future<void> activateFriendMode() async {
    if (companion == null || busy) return;
    final epoch = _epoch;
    busy = true;
    _notify();
    try {
      final result = await _api!.call('activate_friend_mode', {
        'companion_id': companion!.id,
        'consent': true,
      });
      if (!_current(epoch)) return;
      companion = Companion.fromJson(
        Map<String, dynamic>.from(result['companion']),
      );
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> setReplyMode(String mode) async {
    final epoch = _epoch;
    if (mode == 'voice') await setVoiceEnabled(true);
    if (!_current(epoch)) return;
    final result = await _api!.call('set_reply_mode', {'mode': mode});
    if (!_current(epoch)) return;
    personalProfile = PersonalProfile.fromJson(
      Map<String, dynamic>.from(result['profile']),
    );
    _notify();
  }

  Future<void> saveTimezone(String zone, bool automatic) async {
    final epoch = _epoch;
    final result = await _api!.call('save_timezone', {
      'timezone': zone,
      'automatic': automatic,
    });
    if (!_current(epoch)) return;
    personalProfile = PersonalProfile.fromJson(
      Map<String, dynamic>.from(result['profile']),
    );
    await loadNotificationPreferences();
    await loadHomeActivity();
    _notify();
  }

  Future<void> completeWelcome() async {
    final epoch = _epoch;
    final result = await _api!.call('complete_welcome');
    if (!_current(epoch)) return;
    personalProfile = PersonalProfile.fromJson(
      Map<String, dynamic>.from(result['profile']),
    );
    _notify();
  }

  Future<void> loadHomeActivity() async {
    if (journalOnly || companion == null) return;
    final epoch = _epoch;
    try {
      final result = await _api!.call('home_summary', {
        'companion_id': companion!.id,
      });
      if (!_current(epoch)) return;
      homeSummary = result;
      _notify();
    } catch (_) {
      if (_current(epoch)) {
        homeSummary = null;
        _notify();
      }
    }
  }

  Future<void> saveSettings(Companion desired) {
    final revision = ++_revision, epoch = _epoch;
    companion = desired;
    settingsSaved = false;
    if (!desired.memoryEnabled) _memoryPoll?.cancel();
    _notify();
    final next = _saveQueue.then((_) async {
      if (!_current(epoch)) return;
      try {
        final result = await _api!.call('save_companion', desired.toInput());
        if (_current(epoch) && revision == _revision) {
          companion = Companion.fromJson(
            Map<String, dynamic>.from(result['companion']),
          );
          settingsSaved = true;
          error = null;
        }
      } catch (e) {
        if (_current(epoch) && revision == _revision) error = _failure(e);
      } finally {
        _notify();
      }
    });
    _saveQueue = next;
    return next;
  }

  Future<void> loadConversations({bool restoreLatest = true}) async {
    if (!configured || companion == null) return;
    final epoch = _epoch;
    try {
      final result = await _api!.call('list_conversations');
      if (!_current(epoch)) return;
      conversations = (result['conversations'] as List)
          .map((x) => Conversation.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      if (restoreLatest &&
          activeConversation == null &&
          conversations.isNotEmpty) {
        await openConversation(conversations.first);
      }
      _notify();
    } catch (e) {
      if (_current(epoch)) {
        error = _failure(e);
        _notify();
      }
    }
  }

  Future<void> openConversation(Conversation conversation) async {
    if (sending && activeConversation?.id != conversation.id) {
      notice('turn_busy', 'Please wait for the current reply.');
      return;
    }
    final epoch = _epoch;
    final revision = ++_conversationRevision;
    final sameConversation = activeConversation?.id == conversation.id;
    activeConversation = conversation;
    // Keep the streamed answer on screen while replacing temporary IDs with
    // persisted records. A refresh is not an empty conversation.
    if (!sameConversation) messages = [];
    loadingConversation = true;
    loadingOlder = false;
    _hasOlder = false;
    _retryId = null;
    _retryContent = null;
    _retryGreeting = false;
    _notify();
    try {
      final result = await _api!.call('messages', {
        'conversation_id': conversation.id,
      });
      if (!_current(epoch) ||
          activeConversation?.id != conversation.id ||
          revision != _conversationRevision) {
        return;
      }
      messages = (result['messages'] as List)
          .map((x) => ChatMessage.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      _hasOlder = messages.length == 50;
      if (messages.isNotEmpty && messages.last.failed) {
        _retryId = messages.last.requestId;
        _retryGreeting = messages.last.turnKind == 'greeting';
        final originals = messages.where(
          (m) => m.role == 'user' && m.requestId == _retryId,
        );
        if (originals.isNotEmpty) _retryContent = originals.last.content;
      }
      error = null;
      _notify();
    } catch (e) {
      if (_current(epoch) && revision == _conversationRevision) {
        error = _failure(e);
        _notify();
      }
    } finally {
      if (_current(epoch) && revision == _conversationRevision) {
        loadingConversation = false;
        _notify();
      }
    }
  }

  void newConversation() {
    if (sending) return;
    activeConversation = null;
    _newConversationId = null;
    _conversationRevision++;
    loadingConversation = false;
    messages = [];
    _retryId = null;
    _retryContent = null;
    _retryGreeting = false;
    error = null;
    _notify();
    unawaited(ensureGreeting());
  }

  Future<void> ensureGreeting() async {
    if (needsAccountDetails) return;
    if (journalOnly ||
        loadingConversation ||
        sending ||
        busy ||
        messages.isNotEmpty ||
        _retryGreeting ||
        companion == null) {
      return;
    }
    await _turn('', initiate: true);
  }

  Future<void> send(String value) => _turn(value);
  Future<void> _turn(String value, {bool initiate = false}) async {
    if (needsAccountDetails) {
      notice(
        'profile_required',
        'Save your username and preferred name first.',
      );
      return;
    }
    final content = value.trim();
    if (sending ||
        loadingConversation ||
        companion == null ||
        !configured ||
        (!initiate && content.isEmpty)) {
      return;
    }
    if (content.length > 12000) {
      notice('message_too_long', 'Please send a shorter message.');
      return;
    }
    final epoch = _epoch;
    await _saveQueue;
    if (!_current(epoch) || sending) return;
    if (!settingsSaved) {
      notice('settings_not_saved', 'Please save your settings before sending.');
      return;
    }
    sending = true;
    error = null;
    _notify();
    try {
      if (activeConversation == null) {
        _newConversationId ??= const Uuid().v4();
        final created = await _api!.call('create_conversation', {
          'companion_id': companion!.id,
          'conversation_id': _newConversationId,
        });
        if (!_current(epoch)) return;
        activeConversation = Conversation.fromJson(
          Map<String, dynamic>.from(created['conversation']),
        );
        _newConversationId = null;
      }
      final conversation = activeConversation!.id;
      final requestId =
          ((_retryContent == content || (initiate && _retryGreeting)) &&
              _retryId != null)
          ? _retryId!
          : const Uuid().v4();
      _retryId = requestId;
      _retryContent = initiate ? null : content;
      _retryGreeting = initiate;
      messages = [
        ...messages.where((m) => m.requestId != requestId),
        if (!initiate)
          ChatMessage(
            id: 'user-$requestId',
            requestId: requestId,
            role: 'user',
            content: content,
            pending: journalOnly,
          ),
        if (!journalOnly)
          ChatMessage(
            id: 'assistant-$requestId',
            requestId: requestId,
            role: 'assistant',
            content: '',
            pending: true,
          ),
      ];
      _notify();
      var reply = '';
      await for (final event in _api!.turn({
        'conversation_id': conversation,
        'request_id': requestId,
        'content': content,
        if (initiate) 'initiate': true,
      })) {
        if (!_current(epoch)) return;
        if (event['type'] == 'delta') {
          reply += event['text'] as String;
          if (activeConversation?.id == conversation) {
            messages = [
              for (final message in messages)
                if (message.role == 'assistant' &&
                    message.requestId == requestId)
                  ChatMessage(
                    id: message.id,
                    requestId: requestId,
                    role: 'assistant',
                    content: reply,
                    pending: true,
                  )
                else
                  message,
            ];
            _notify();
          }
        }
      }
      if (!_current(epoch)) return;
      messages = [
        for (final m in messages)
          if (m.role == 'assistant' && m.requestId == requestId)
            ChatMessage(
              id: m.id,
              requestId: requestId,
              role: m.role,
              content: m.content,
            )
          else
            m,
      ];
      _retryId = null;
      _retryContent = null;
      _retryGreeting = false;
      if (activeConversation?.id == conversation) {
        await openConversation(activeConversation!);
      }
      // The owned message IDs must be restored before voice playback. Sidebar
      // and memory refreshes can finish independently of the next user turn.
      if (_current(epoch)) {
        unawaited(loadConversations(restoreLatest: false));
        unawaited(loadMemories());
      }
    } catch (e) {
      if (_current(epoch)) {
        error = _failure(e);
        messages = [
          for (final m in messages)
            if ((m.role == 'assistant' && m.pending) ||
                (journalOnly &&
                    m.role == 'user' &&
                    m.pending &&
                    m.requestId == _retryId))
              ChatMessage(
                id: m.id,
                requestId: m.requestId,
                role: m.role,
                content: m.content,
                failed: true,
              )
            else
              m,
        ];
      }
    } finally {
      if (_current(epoch)) {
        sending = false;
        _notify();
        final pending = _pendingPush;
        _pendingPush = null;
        if (pending != null) unawaited(_receivePush(pending, true));
      }
    }
  }

  String? get retryContent => _retryContent;
  Future<void> loadOlderMessages() async {
    if (loadingOlder ||
        !_hasOlder ||
        sending ||
        activeConversation == null ||
        messages.isEmpty) {
      return;
    }
    final before = messages.first.seq;
    if (before == null) return;
    final epoch = _epoch,
        revision = _conversationRevision,
        id = activeConversation!.id;
    loadingOlder = true;
    try {
      final result = await _api!.call('messages', {
        'conversation_id': id,
        'before': before,
      });
      if (!_current(epoch) || revision != _conversationRevision) return;
      final older = (result['messages'] as List)
          .map((x) => ChatMessage.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      final known = messages.map((m) => m.id).toSet();
      messages = [...older.where((m) => !known.contains(m.id)), ...messages];
      _hasOlder = older.length == 50;
      _notify();
    } catch (e) {
      if (_current(epoch)) {
        error = _failure(e);
        _notify();
      }
    } finally {
      loadingOlder = false;
    }
  }

  Future<void> retrySend() async {
    if (_retryGreeting) {
      await _turn('', initiate: true);
      return;
    }
    if (_retryContent != null) await send(_retryContent!);
  }

  Future<void> renameConversation(String id, String title) async {
    await _api!.call('rename_conversation', {
      'conversation_id': id,
      'title': title,
    });
    await loadConversations();
  }

  Future<void> setLearningEnabled(bool enabled) async {
    if (companion == null || !configured) return;
    final epoch = _epoch;
    final result = await _api!.call('set_learning', {
      'companion_id': companion!.id,
      'enabled': enabled,
    });
    if (!_current(epoch)) return;
    companion = Companion.fromJson(
      Map<String, dynamic>.from(result['companion']),
    );
    _notify();
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    final epoch = _epoch;
    await _saveQueue;
    if (!_current(epoch)) {
      throw const AppFailure(
        'session_changed',
        'Please reconnect your session.',
      );
    }
    if (companion?.voiceEnabled == enabled) return;
    if (companion == null || !configured) {
      throw const AppFailure(
        'configuration_required',
        'Voice is not connected yet.',
      );
    }
    final result = await _api!.call('set_voice', {
      'companion_id': companion!.id,
      'enabled': enabled,
    });
    if (!_current(epoch)) return;
    companion = Companion.fromJson(
      Map<String, dynamic>.from(result['companion']),
    );
    _notify();
  }

  Future<void> deleteConversation(String id) async {
    await _api!.call('delete_conversation', {'conversation_id': id});
    if (activeConversation?.id == id) newConversation();
    await loadConversations();
  }

  Future<void> reportMessage({
    required String messageId,
    required String requestId,
    required String reason,
    required String details,
  }) async {
    final epoch = _epoch;
    await _api!.call('report_message', {
      'message_id': messageId,
      'request_id': requestId,
      'reason': reason,
      'details': details,
    });
    if (!_current(epoch)) {
      throw const AppFailure(
        'session_changed',
        'Your account changed. Please reopen the conversation.',
      );
    }
  }

  Future<Map<String, dynamic>> billingAction(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    final epoch = _epoch;
    final result = await _api!.call(action, body);
    if (!_current(epoch)) {
      throw const AppFailure(
        'session_changed',
        'Your account changed. Please reopen your membership.',
      );
    }
    return result;
  }

  Future<void> loadMemories() async {
    if (companion == null || !configured) return;
    final epoch = _epoch;
    final revision = _memoryRevision;
    try {
      final result = await _api!.call('list_memories', {
        'companion_id': companion!.id,
      });
      if (!_current(epoch) || revision != _memoryRevision) return;
      memories = (result['memories'] as List)
          .map((x) => CompanionMemory.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      _memoryPoll?.cancel();
      if ((result['pending_count'] as num? ?? 0) > 0 &&
          companion?.memoryEnabled == true &&
          _memoryPolls < 6) {
        _memoryPolls++;
        _memoryPoll = Timer(const Duration(seconds: 5), () {
          if (_current(epoch)) unawaited(loadMemories());
        });
      } else {
        _memoryPolls = 0;
      }
      _notify();
    } catch (e) {
      if (_current(epoch)) {
        error = _failure(e);
        _notify();
      }
    }
  }

  Future<void> saveMemory({
    String? id,
    required String category,
    required String title,
    required String content,
    DateTime? expiresAt,
    Map<String, dynamic>? attributes,
  }) async {
    if (companion == null) return;
    await _api!.call('save_memory', {
      'companion_id': companion!.id,
      'id': id,
      'category': category,
      'title': title,
      'content': content,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'attributes': ?attributes,
    });
    await loadMemories();
  }

  Future<void> forgetMemory(String id) async {
    _memoryRevision++;
    await _api!.call('forget_memory', {'id': id});
    await loadMemories();
  }

  Future<List<Map<String, dynamic>>> checkinHistory() async {
    final epoch = _epoch;
    final result = await _api!.call('checkin_history');
    return _current(epoch)
        ? (result['checkins'] as List)
              .map((x) => Map<String, dynamic>.from(x))
              .toList()
        : [];
  }

  Future<void> cancelCheckin(String id) async {
    await _api!.call('cancel_checkin', {'id': id});
    await loadHomeActivity();
  }

  Future<void> scheduleReminder({
    required String requestId,
    required String reason,
    required String localTime,
    String? source,
  }) async {
    await _api!.call('schedule_personal_reminder', {
      'request_id': requestId,
      'kind': 'important_date',
      'reason': reason,
      'local_time': localTime,
      'timezone': notificationPreferences.timezone,
      'conversation_id': activeConversation?.id,
      'source_memory_id': source,
    });
    await loadHomeActivity();
  }

  Future<void> forgetAllMemories() async {
    if (companion == null) return;
    _memoryRevision++;
    _memoryPoll?.cancel();
    await _api!.call('forget_all_memories', {'companion_id': companion!.id});
    memories = [];
    _notify();
  }

  Future<void> _registerToken(String token) async {
    final epoch = _epoch;
    final installation = await _push!.installationId();
    if (!_current(epoch)) return;
    await _api!.call('register_device', {
      'installation_id': installation,
      'token': token,
    });
  }

  Future<void> loadNotificationPreferences() async {
    final epoch = _epoch;
    final result = await _api!.call('notification_preferences');
    if (!_current(epoch)) return;
    notificationPreferences = result['preferences'] == null
        ? const NotificationPreferences()
        : NotificationPreferences.fromJson(
            Map<String, dynamic>.from(result['preferences']),
          );
    _notify();
  }

  Future<void> saveNotificationPreferences(
    NotificationPreferences desired,
  ) async {
    if (!configured || companion == null) return;
    if (desired.enabled && desired.timezone == null) {
      notice(
        'schedule_required',
        'Choose your timezone, days, and quiet hours first.',
      );
      return;
    }
    final epoch = _epoch;
    try {
      if (desired.enabled && !notificationPreferences.enabled) {
        if (_push == null) {
          throw const AppFailure(
            'push_unavailable',
            'Notifications are not connected yet.',
          );
        }
        final token = await _push.requestToken();
        if (!_current(epoch)) {
          if (!notificationPreferences.enabled) await _push.revoke();
          return;
        }
        await _registerToken(token);
        if (!_current(epoch)) return;
      }
      final result = await _api!.call(
        'save_notification_preferences',
        desired.toInput(companion!.id),
      );
      if (!_current(epoch)) return;
      notificationPreferences = NotificationPreferences.fromJson(
        Map<String, dynamic>.from(result['preferences']),
      );
      error = null;
      if (!desired.enabled) await _push?.revoke();
    } catch (e) {
      if (_current(epoch)) error = _failure(e);
    }
    _notify();
  }

  Future<void> signOut() async {
    try {
      if (_push != null && configured && _session?.userId != null) {
        await _api!.call('unregister_device', {
          'installation_id': await _push.installationId(),
        });
      }
    } catch (_) {
      /* Sign-out remains possible while offline. */
    }
    try {
      await _push?.revoke();
    } catch (_) {}
    await _session?.signOut();
  }

  @override
  void dispose() {
    _routedOpenSubscription?.cancel();
    _receiptSubscription?.cancel();
    _pushOpenSubscription?.cancel();
    _tokenSubscription?.cancel();
    _disposed = true;
    _epoch++;
    _authSubscription?.cancel();
    _memoryPoll?.cancel();
    _api?.close();
    super.dispose();
  }

  Future<void> setConversationRetention(int? days) async {
    if (companion == null || !configured) return;
    final epoch = _epoch;
    final result = await _api!.call('set_conversation_retention', {
      'companion_id': companion!.id,
      'days': days,
    });
    if (!_current(epoch)) return;
    companion = Companion.fromJson(
      Map<String, dynamic>.from(result['companion']),
    );
    await loadConversations();
    _notify();
  }

  Future<String?> exportData() async {
    if (!configured || companion == null || exporting) return null;
    final epoch = _epoch;
    exporting = true;
    error = null;
    _notify();
    final data = <String, dynamic>{
      'format': 'morrow-export-v1',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
    };
    var size = 0;
    try {
      for (final section in [
        'profile',
        'companion',
        'conversations',
        'messages',
        'memories',
        'patterns',
        'notifications',
        'checkins',
        'consents',
        if (!journalOnly) ...['reports', 'subscriptions', 'usage'],
      ]) {
        final rows = <dynamic>[];
        String? cursor;
        final seen = <String>{};
        do {
          final page = await _api!.call('export_data', {
            'section': section,
            'after': ?cursor,
          });
          if (!_current(epoch)) return null;
          final items = page['rows'] as List;
          size += utf8.encode(jsonEncode(items)).length;
          if (size > 25 * 1024 * 1024) {
            throw const AppFailure(
              'export_too_large',
              'This export is too large to download here.',
            );
          }
          rows.addAll(items);
          cursor = page['next_cursor'] as String?;
          if (cursor != null && !seen.add(cursor)) {
            throw const AppFailure(
              'export_interrupted',
              'Export interrupted. Please try again.',
            );
          }
        } while (cursor != null);
        data[section] = rows;
      }
      return jsonEncode(data);
    } catch (e) {
      if (_current(epoch)) error = _failure(e);
      return null;
    } finally {
      if (_current(epoch)) {
        exporting = false;
        _notify();
      }
    }
  }

  Future<void> requestAccountErasure(String confirmation) async {
    if (confirmation != 'DELETE_MY_ACCOUNT') {
      throw const AppFailure(
        'confirmation_required',
        'Please confirm account removal.',
      );
    }
    if (!configured || _session?.userId == null) return;
    final epoch = _epoch;
    await _session!.token(refresh: true);
    if (!_current(epoch)) return;
    final result = await _api!.call('request_account_erasure', {
      'confirmation': confirmation,
    });
    if (!_current(epoch)) return;
    _epoch++;
    _memoryRevision++;
    _memoryPoll?.cancel();
    erasureStatus = result['status'] as String? ?? 'requested';
    companion = null;
    messages = [];
    memories = [];
    conversations = [];
    displayName = null;
    personalProfile = const PersonalProfile();
    homeSummary = null;
    activeConversation = null;
    welcomeAudioAvailable = false;
    sending = false;
    loadingConversation = false;
    exporting = false;
    notice('erasure_pending', 'Account removal is in progress.');
  }

  Future<void> refreshErasureStatus() async {
    if (!configured) return;
    final epoch = _epoch;
    final result = await _api!.call('erasure_status');
    if (!_current(epoch)) return;
    erasureStatus = result['status'] as String?;
    if (erasureStatus == 'complete') await signOut();
    _notify();
  }
}
