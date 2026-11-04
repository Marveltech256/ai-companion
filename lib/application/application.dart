import 'dart:async';

import 'package:flutter_timezone/flutter_timezone.dart';

import '../voice/voice_controller.dart';

import 'package:flutter/material.dart';

import '../core/app_failure.dart';
import 'actions.dart';
import 'connection.dart';
import 'conversation_page.dart';
import 'home_page.dart';
import 'memories_page.dart';
import 'settings_page.dart';
import 'sign_in_page.dart';
import 'setup_page.dart';
import 'theme.dart';
import 'talk_preview.dart';
import 'welcome_page.dart';
import 'friend_mode_page.dart';

/// The shipped application uses responsive Flutter widgets exclusively. The
/// archived Figma scene renderer is isolated in main_design_reference.dart.
class MorrowApplication extends StatefulWidget {
  const MorrowApplication({
    super.key,
    required this.connection,
    this.connectCloud,
    this.useDevice,
    this.requireSignIn = true,
  });
  final AppConnection connection;
  final bool requireSignIn;
  final Future<AppConnection> Function()? connectCloud, useDevice;
  @override
  State<MorrowApplication> createState() => _MorrowApplicationState();
}

class _MorrowApplicationState extends State<MorrowApplication>
    with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  late AppConnection _connection;
  late Listenable _listenable;
  int _page = 0;
  bool _voice = false, _switching = false;
  String? _protectedOwner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind(widget.connection);
    unawaited(_syncTimezone());
  }

  void _bind(AppConnection connection) {
    _connection = connection;
    _listenable = Listenable.merge([
      connection.controller,
      if (connection.voice != null) connection.voice!,
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_connection.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_connection.voice?.suspend());
    } else {
      unawaited(_syncTimezone());
    }
  }

  Future<void> _syncTimezone() async {
    final c = _connection.controller;
    if (!c.registeredAccount ||
        c.needsIntroduction ||
        c.erasureStatus != null ||
        !c.personalProfile.timezoneAutomatic) {
      return;
    }
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (mounted && zone != c.personalProfile.timezone) {
        await c.saveTimezone(zone, true);
      }
    } catch (_) {}
  }

  void _go(int page) {
    if (page != 1) unawaited(_connection.voice?.suspend());
    if (_voice) unawaited(_connection.voice?.stop());
    setState(() {
      _voice = false;
      _page = page;
    });
    if (page == 1 &&
        !(_connection.voice?.hasRecording ?? false) &&
        _connection.voice?.stage != VoiceStage.recording) {
      unawaited(_connection.controller.ensureGreeting());
    }
    if (page == 0) unawaited(_connection.controller.loadHomeActivity());
  }

  void _openVoice() => _go(2);
  Future<void> _switch(Future<AppConnection> Function()? factory) async {
    if (_switching) return;
    if (factory == null) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Cloud connection is not configured in this build yet.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _switching = true;
      _voice = false;
    });
    try {
      await _connection.controller.flushSettings();
      await _connection.voice?.stop();
      final next = await factory();
      if (!mounted) {
        await next.dispose();
        return;
      }
      final previous = _connection;
      setState(() {
        _bind(next);
        _page = 0;
      });
      await previous.dispose();
    } catch (error) {
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            error is AppFailure ? error.message : 'Could not open that workspace. Your existing space is still here.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _connect() async {
    await _switch(widget.connectCloud);
    final context = _navigator.currentContext;
    if (mounted &&
        context != null &&
        context.mounted &&
        !_connection.deviceOnly &&
        _connection.controller.supportsAccounts &&
        (!_connection.controller.registeredAccount ||
            _connection.controller.needsAccountDetails)) {
      await accountDialog(
        context,
        _connection.controller,
        create: !_connection.controller.registeredAccount,
      );
    }
  }

  Future<void> _device() async {
    if (widget.requireSignIn) return;
    await _switch(widget.useDevice ?? openDeviceWorkspace);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ai Companion',
    debugShowCheckedModeBanner: false,
    theme: morrowTheme(),
    scaffoldMessengerKey: _messenger,
    navigatorKey: _navigator,
    home: AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        final controller = _connection.controller;
        final previousOwner = _protectedOwner;
        if (widget.requireSignIn &&
            previousOwner != null &&
            previousOwner != controller.userId) {
          _page = 0;
          _voice = false;
          unawaited(_connection.voice?.stop());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _navigator.currentState?.popUntil((route) => route.isFirst);
            }
          });
        }
        _protectedOwner = controller.registeredAccount
            ? controller.userId
            : null;
        if (controller.takeNotificationOpen()) {
          _page = 1;
          _voice = false;
        }
        if (_switching) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LumiOrb(size: 70),
                  SizedBox(height: 30),
                  CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }
        if (widget.requireSignIn && !controller.registeredAccount) {
          _page = 0;
          _voice = false;
          return SignInPage(controller: controller, reconnect: _connect);
        }
        if (controller.erasureStatus != null) {
          _voice = false;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Brand(),
                        const SizedBox(height: 30),
                        Text(
                          controller.erasureStatus == 'complete'
                              ? 'Your space has been removed.'
                              : 'Your account removal is in progress.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 20),
                        if (controller.erasureStatus != 'complete')
                          ActionButton(
                            label: 'Check progress',
                            onPressed: () async {
                              await perform(
                                context,
                                controller,
                                controller.refreshErasureStatus,
                              );
                            },
                          ),
                        const SizedBox(height: 16),
                        ActionButton(
                          label: widget.requireSignIn
                              ? 'Back to sign in'
                              : 'Open a new device workspace',
                          secondary: true,
                          onPressed: widget.requireSignIn
                              ? controller.signOut
                              : _device,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        if (controller.companion == null ||
            controller.needsAccountDetails ||
            controller.needsIntroduction) {
          _voice = false;
          return SetupPage(
            key: ValueKey(
              'setup-${_connection.deviceOnly}-${controller.userId}',
            ),
            controller: controller,
            deviceOnly: _connection.deviceOnly,
            useDevice: widget.requireSignIn ? null : _device,
            connectCloud: _connect,
          );
        }
        if (widget.requireSignIn &&
            controller.needsFriendMode &&
            _page != 3 &&
            _page != 4) {
          return FriendModePage(controller: controller, privacy: () => _go(3));
        }
        if (controller.needsWelcome) {
          return WelcomePage(
            controller: controller,
            voice: _connection.voice,
            continueChat: () => _go(1),
          );
        }
        final pages = [
          HomePage(
            controller: controller,
            deviceOnly: _connection.deviceOnly,
            talk: () => _go(1),
            voice: _openVoice,
            memories: () => _go(4),
            settings: () => _go(3),
          ),
          ConversationPage(
            key: ValueKey(
              'talk-${controller.userId}-${controller.companion!.id}',
            ),
            controller: controller,
            deviceOnly: _connection.deviceOnly,
            voice: _openVoice,
            audio: _connection.voice,
            connect: () => _go(3),
          ),
          TalkPreview(name: controller.companion!.name, chat: () => _go(1)),
          SettingsPage(
            key: ValueKey(
              'settings-${controller.userId}-${controller.companion!.id}',
            ),
            controller: controller,
            deviceOnly: _connection.deviceOnly,
            connect: _connect,
            useDevice: widget.requireSignIn ? null : _device,
            billing: _connection.billing,
            memories: () => _go(4),
          ),
          MemoriesPage(
            key: ValueKey(
              'memories-${controller.userId}-${controller.companion!.id}',
            ),
            controller: controller,
          ),
        ];
        return LayoutBuilder(
          builder: (context, layout) {
            final desktop = layout.maxWidth >= 1000;
            return Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    if (desktop) SizedBox(width: 232, child: _sidebar(context)),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 14, 14, 12),
                            child: Row(
                              children: [
                                if (!desktop)
                                  const Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 12),
                                      child: Brand(),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: Text(
                                      _page == 0
                                          ? 'Today, at your pace.'
                                          : const [
                                              'Today',
                                              'Chat',
                                              'Talk · Coming soon',
                                              'Your settings',
                                              'Your saved memories',
                                            ][_page],
                                      style: const TextStyle(color: mutedInk),
                                    ),
                                  ),
                                if (layout.maxWidth > 360 &&
                                    (desktop ||
                                        MediaQuery.textScalerOf(context)
                                                .scale(11) <=
                                            15))
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: desktop ? 220 : 110,
                                      ),
                                      child: Text(
                                        _connection.deviceOnly
                                            ? 'On this device'
                                            : 'With ${controller.companion!.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: mutedInk,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Your settings',
                                  onPressed: () => _go(3),
                                  icon: const Icon(Icons.tune, color: plum),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          if (controller.error != null)
                            Material(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: .4),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(18, 5, 6, 5),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          controller.error!.message,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Dismiss message',
                                      onPressed: controller.clearNotice,
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Expanded(
                            child: IndexedStack(index: _page, children: pages),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: desktop
                  ? null
                  : NavigationBar(
                      selectedIndex: _page < 3 ? _page : 0,
                      onDestinationSelected: _go,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.chat_bubble_outline),
                          selectedIcon: Icon(Icons.chat_bubble),
                          label: 'Chat',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.graphic_eq),
                          label: 'Talk',
                        ),
                      ],
                    ),
            );
          },
        );
      },
    ),
  );

  Widget _sidebar(BuildContext context) {
    final controller = _connection.controller;
    return Material(
      color: const Color(0xFFF4EFF7),
      shape: const Border(right: BorderSide(color: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(26, 30, 22, 34),
            child: Brand(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const LumiOrb(size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.companion!.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Your AI companion',
                        style: TextStyle(fontSize: 11, color: mutedInk),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                selectedTileColor: lilac,
                selected: i == _page,
                leading: Icon(
                  const [
                    Icons.wb_sunny_outlined,
                    Icons.chat_bubble_outline,
                    Icons.graphic_eq,
                  ][i],
                  size: 20,
                  color: plum,
                ),
                title: Text(
                  const ['Home', 'Chat', 'Talk'][i],
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => _go(i),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 28, 22, 12),
            child: Text(
              'LITTLE MOMENTS',
              style: TextStyle(
                fontSize: 10,
                color: mutedInk,
                letterSpacing: .6,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TextButton.icon(
              onPressed: controller.sending
                  ? null
                  : () {
                      controller.newConversation();
                      _go(1);
                    },
              icon: const Icon(Icons.add, size: 17),
              label: Text(
                _connection.deviceOnly
                    ? 'New journal moment'
                    : 'New conversation',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: controller.conversations.length,
              itemBuilder: (context, index) {
                final conversation = controller.conversations[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    conversation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: mutedInk),
                  ),
                  selected:
                      controller.activeConversation?.id == conversation.id &&
                      _page == 1,
                  onTap: controller.sending
                      ? null
                      : () async {
                          _go(1);
                          await controller.openConversation(conversation);
                        },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _connection.deviceOnly
                  ? 'Your journal stays on this device.'
                  : controller.accountEmail ?? 'Your guest account',
              style: const TextStyle(fontSize: 11, color: mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}
