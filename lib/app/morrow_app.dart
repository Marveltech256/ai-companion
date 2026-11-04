import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';

import '../design/scene.dart';
import '../design/scene_painter.dart';
import '../design/scene_view.dart';
import 'companion_controller.dart';
import 'live_panels.dart';
import '../voice/voice_controller.dart';
import 'companionship.dart';
import '../privacy/export_stub.dart'
    if (dart.library.js_interop) '../privacy/export_web.dart'
    as exporting;

enum CompanionPage { setup, home, conversation, voice, memories }

/// Original Figma presentation bound to live services. Review mode retains the
/// source examples for visual comparison.
class MorrowApp extends StatefulWidget {
  const MorrowApp({
    super.key,
    required this.library,
    this.initialScreen,
    this.controller,
    this.voice,
    this.reviewMode = false,
  });
  final DesignLibrary library;
  final String? initialScreen;
  final CompanionController? controller;
  final VoiceController? voice;
  final bool reviewMode;
  @override
  State<MorrowApp> createState() => _MorrowAppState();
}

class _MorrowAppState extends State<MorrowApp> with WidgetsBindingObserver {
  late CompanionPage _page;
  late final TextEditingController _name;
  final _draft = TextEditingController();
  final _search = TextEditingController();
  String _style = 'Gentle & warm';
  final _interests = {'Art & making', 'Music'};
  String _filter = 'All';
  bool _memory = true;
  bool _checkins = true;
  bool _suggestions = true;
  bool _birthdays = false;
  bool _muted = false;
  bool _captions = true;
  double _responseLength = .5;
  bool _forceDesktop = false;
  late final Map<String, DesignNode> _nodes;
  late final Map<String, String> _choiceGroups;
  late final Map<String, VoidCallback> _navigation;
  String? _boundCompanion;
  DateTime? _forgetConfirmation;
  bool get _live => !widget.reviewMode;
  CompanionController? get _controller => widget.controller;

  DesignLibrary get _library => widget.library;
  String get _companionName =>
      _name.text.trim().isEmpty ? 'Lumi' : _name.text.trim();
  DesignNode _node(String id) => _nodes[id]!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.voice?.addListener(_voiceChanged);
    final initial = widget.reviewMode
        ? widget.initialScreen ?? Uri.base.queryParameters['screen'] ?? 'setup'
        : 'setup';
    _forceDesktop = initial.startsWith('desktop_');
    _page = switch (initial) {
      'home' => CompanionPage.home,
      'conversation' || 'desktop_conversation' => CompanionPage.conversation,
      'voice' => CompanionPage.voice,
      'memories' || 'desktop_memories' => CompanionPage.memories,
      _ => CompanionPage.setup,
    };
    _name = TextEditingController(text: 'Lumi');
    _nodes = {
      for (final screen in _library.screens.values)
        for (final node in screen.descendants) node.id: node,
    };
    _choiceGroups = {};
    _navigation = {};
    for (final node in _nodes.values) {
      if (node.name == 'Style choices' ||
          node.name == 'Other styles' ||
          node.name == 'Interest choices' ||
          node.name == 'Memory filters' ||
          node.name == 'Filters') {
        for (final child in node.children) {
          _choiceGroups[child.id] = node.name;
        }
      }
      if (node.name == 'Destination' || node.name == 'Navigation item') {
        final destination = switch (_label(node)) {
          'Home' || 'Today' => CompanionPage.home,
          'Talk' || 'Conversation' => CompanionPage.conversation,
          'Memories' || 'Our rhythm' => CompanionPage.memories,
          _ => null,
        };
        if (destination != null) {
          _navigation[node.id] = () => _go(destination);
        }
      }
    }
    _controller?.addListener(_stateChanged);
    if (_controller?.companion != null) _stateChanged();
  }

  void _stateChanged() {
    if (!mounted) return;
    final companion = _controller?.companion;
    setState(() {
      if (companion != null) {
        if (_name.text != companion.name) _name.text = companion.name;
        _style = companion.style;
        _interests
          ..clear()
          ..addAll(companion.interests);
        _responseLength = companion.responseLength;
        _memory = companion.memoryEnabled;
        _checkins = _controller!.notificationPreferences.checkins;
        _suggestions = _controller!.notificationPreferences.suggestions;
        _birthdays = _controller!.notificationPreferences.birthdays;
        if (_boundCompanion == null) {
          _page = CompanionPage.home;
          _boundCompanion = companion.id;
        }
        if (_controller!.takeNotificationOpen()) {
          if (_page == CompanionPage.voice) unawaited(widget.voice?.stop());
          _page = CompanionPage.conversation;
        }
      } else if (_boundCompanion != null) {
        _boundCompanion = null;
        _draft.clear();
        _name.text = 'Lumi';
        _page = CompanionPage.setup;
      }
    });
  }

  void _save() {
    final current = _controller?.companion;
    if (!_live || current == null) return;
    unawaited(
      _controller!.saveSettings(
        current.copyWith(
          name: _companionName,
          style: _style,
          interests: _interests.toList(),
          responseLength: _responseLength,
          memoryEnabled: _memory,
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (!_live) {
      _go(CompanionPage.home);
      return;
    }
    if (_controller == null) return;
    final ok = await _controller!.create(
      name: _companionName,
      style: _style,
      interests: _interests.toList(),
      memoryEnabled: _memory,
    );
    if (ok && mounted) _go(CompanionPage.home);
  }

  Future<void> _send() async {
    if (_controller == null) return;
    final text = _draft.text;
    if (text.trim().isEmpty) {
      await _controller!.retrySend();
      return;
    }
    _draft.clear();
    await _controller!.send(text);
    if (mounted &&
        _controller!.error != null &&
        _controller!.retryContent == null &&
        _draft.text.isEmpty) {
      _draft.text = text;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.voice?.removeListener(_voiceChanged);
    widget.voice?.dispose();
    _controller?.removeListener(_stateChanged);
    _name.dispose();
    _draft.dispose();
    _search.dispose();
    super.dispose();
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(widget.voice?.stop());
  }

  void _go(CompanionPage page) {
    if (_live && page == CompanionPage.voice && widget.voice == null) {
      _controller?.notice(
        'voice_unavailable',
        'Voice conversations are not enabled yet.',
      );
      return;
    }
    if (_live && _page == CompanionPage.voice && page != CompanionPage.voice) {
      unawaited(widget.voice?.stop());
    }
    setState(() {
      _page = page;
      _forceDesktop = false;
    });
    if (_live && page == CompanionPage.conversation) {
      unawaited(_controller!.loadConversations());
    }
    if (_live && page == CompanionPage.memories) {
      unawaited(_controller!.loadMemories());
    }
  }

  String _label(DesignNode node) => node.descendants
      .where((n) => n.text != null)
      .map((n) => n.text!)
      .join(' ');

  String _text(DesignNode node) {
    var value = node.text ?? '';
    if (_live) {
      final error = _controller?.error;
      final count = _controller?.memories.length ?? 0;
      switch (node.id) {
        case '2:6830':
          return widget.voice?.stage == VoiceStage.recording
              ? 'Recording · 00:${widget.voice!.seconds.toString().padLeft(2, '0')}'
              : 'A voice, at your pace';
        case '2:6846':
          return widget.voice?.status ?? 'Voice is not connected';
        case '2:6848':
          return widget.voice?.caption.isNotEmpty == true
              ? widget.voice!.caption
              : 'Unmute when you are ready to talk.';
        case '2:6849':
          return widget.voice?.stage == VoiceStage.recording
              ? 'Mute when you want to finish your turn.'
              : 'Unmute to speak. Always your choice.';
        case '2:6855':
          return widget.voice?.stage == VoiceStage.recording
              ? 'Mute'
              : 'Unmute';
        case '2:6866':
          return 'AI voice · OpenAI · Transcripts saved in history';
        case '2:6684':
          return error == null
              ? 'Start free. No card needed. Always your choice.'
              : error.code == 'configuration_required'
              ? 'Connection unavailable. Please try again.'
              : error.message;
        case '2:6683':
          if (_controller?.busy == true) return 'Connecting…';
        case '2:6708':
          return _controller?.displayName == null
              ? 'A softer landing.'
              : 'A softer landing, ${_controller!.displayName}.';
        case '2:6705':
        case '2:6981':
        case '2:7118':
          return _controller?.displayName?.substring(0, 1).toUpperCase() ?? '';
        case '2:6983':
        case '2:7120':
          return _controller?.displayName ?? '';
        case '2:6717':
          return 'A little space for you.';
        case '2:6718':
          return error?.message ?? 'Your AI companion · Here to listen';
        case '2:6733':
          return companionshipInvitation(
            _controller?.companion?.interests ?? [],
          ).$1;
        case '2:6734':
          return companionshipInvitation(
            _controller?.companion?.interests ?? [],
          ).$2;
        case '2:6737':
          return _checkins
              ? 'Check-ins follow your rhythm'
              : 'Check-ins are paused · Always your choice';
        case '2:6886':
          return error?.message ?? 'Pause anytime. Nothing here is permanent.';
        case '2:7069':
          return _checkins
              ? 'Following your chosen rhythm.'
              : 'Check-ins are paused.';
        case '2:7241':
          final preferences = _controller?.notificationPreferences;
          if (preferences?.timezone == null) return 'Choose your rhythm';
          final minute = preferences!.localMinute;
          return '${minute ~/ 60 % 12 == 0 ? 12 : minute ~/ 60 % 12}:${(minute % 60).toString().padLeft(2, '0')} ${minute < 720 ? 'am' : 'pm'} · ${preferences.timezone}';
        case '2:6989':
          return _controller?.activeConversation?.title ??
              'A little space for you.';
        case '2:6799':
        case '2:7039':
          if (error != null) return error.message;
        case '2:6789':
          return _memory
              ? 'Memory is on, with your permission.'
              : 'Memory is paused.';
        case '2:6891':
          return 'All · $count';
        case '2:7150':
          return 'All memories · $count';
        case '2:7193':
          return 'Showing $count little things';
        case '2:7198':
          if (_forgetConfirmation != null) return 'Confirm forget all';
        case '2:7256':
          return error != null
              ? 'Not saved. Tap to retry.'
              : _controller?.settingsSaved == false
              ? 'Saving…'
              : '✓  Saved. This can change as you do.';
        case '2:6707':
        case '2:6774':
        case '2:6997':
          return _today();
      }
    }
    if (node.id == '2:7223' && _responseLength != .5) {
      return _responseLength < .34
          ? 'Short & sweet'
          : _responseLength > .66
          ? 'More room'
          : 'A little of both';
    }
    if (node.id == '2:6855' && _muted) return 'Unmute';
    if (node.id == '2:7212') value = _style;
    return value
        .replaceAll('Lumi', _companionName)
        .replaceAll('LUMI', _companionName.toUpperCase());
  }

  VoidCallback? _action(DesignNode node) {
    if (_live && node.name == 'Export') return () => unawaited(_export());
    if (_navigation.containsKey(node.id)) return _navigation[node.id];
    final group = _choiceGroups[node.id];
    if (group != null) {
      final label = _label(node);
      return () {
        setState(() {
          if (group == 'Style choices' || group == 'Other styles') {
            _style = label;
          } else if (group == 'Interest choices') {
            _interests.contains(label)
                ? _interests.remove(label)
                : _interests.add(label);
          } else {
            _filter = label.startsWith('All') ? 'All' : label;
          }
        });
        _save();
      };
    }
    return switch (node.id) {
      '2:6681' => _controller?.busy == true ? null : () => unawaited(_create()),
      '2:6719' => () => _go(CompanionPage.conversation),
      '2:6722' ||
      '2:7339' ||
      '2:6991' ||
      '2:7468' => () => _go(CompanionPage.voice),
      '2:6790' || '2:7063' || '2:7070' => () => _go(CompanionPage.memories),
      '2:6856' || '2:7363' => () => _go(CompanionPage.conversation),
      '2:6852' =>
        _live
            ? () => unawaited(widget.voice?.toggle())
            : () => setState(() => _muted = !_muted),
      '2:6860' => () => setState(() => _captions = !_captions),
      '2:6797' || '2:7037' =>
        _live && _controller?.sending != true ? () => unawaited(_send()) : null,
      '2:7194' ||
      '2:6921' => _live ? () => unawaited(_controller!.loadMemories()) : null,
      '2:7256' => _live && _controller?.error != null ? _save : null,
      '2:7242' =>
        _live
            ? () => _controller?.notice(
                'design_required',
                'Scheduling controls are not available yet.',
              )
            : null,
      '2:7198' =>
        _live
            ? () async {
                if (_forgetConfirmation == null ||
                    DateTime.now().difference(_forgetConfirmation!).inSeconds >
                        10) {
                  setState(() => _forgetConfirmation = DateTime.now());
                  return;
                }
                try {
                  await _controller!.forgetAllMemories();
                } catch (_) {
                  _controller!.notice(
                    'delete_failed',
                    'Could not forget memories. Please try again.',
                  );
                }
                if (mounted) setState(() => _forgetConfirmation = null);
              }
            : null,
      _ => null,
    };
  }

  DesignNode? _choiceStyle(DesignNode node) {
    final group = _choiceGroups[node.id];
    if (group == null) return null;
    final label = _label(node);
    final selected = switch (group) {
      'Style choices' || 'Other styles' => label == _style,
      'Interest choices' => _interests.contains(label),
      _ => _filter == 'All' ? label.startsWith('All') : label == _filter,
    };
    return _node(selected ? '2:6651' : '2:6653');
  }

  Future<void> _export() async {
    try {
      final owner = _controller?.userId;
      final json = await _controller?.exportData();
      if (json != null && mounted && owner == _controller?.userId) {
        await exporting.downloadExport(json);
      }
    } catch (_) {
      _controller?.notice(
        'export_unavailable',
        'Export unavailable here. Please try in a browser.',
      );
    }
  }

  Widget? _override(DesignNode node) {
    if (_live && {'2:6830', '2:6846', '2:6849'}.contains(node.id)) {
      return Semantics(
        label: node.id == '2:6849' ? widget.voice?.error?.message : null,
        child: Text(
          node.id == '2:6849'
              ? widget.voice?.error?.message ?? _text(node)
              : _text(node),
          style: designTextStyle(node).copyWith(
            height: node.list('lines').isEmpty
                ? 1.3
                : DesignNode.number(node.list('lines').first['lineHeight']) /
                      DesignNode.number(node.data['fontSize'], 13),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (_live && node.id == '2:6848') {
      return SingleChildScrollView(
        child: Text(
          _text(node),
          style: designTextStyle(node).copyWith(
            height: node.list('lines').isEmpty
                ? 1.3
                : DesignNode.number(node.list('lines').first['lineHeight']) /
                      DesignNode.number(node.data['fontSize'], 13),
          ),
        ),
      );
    }
    if (node.id == '2:7214' && _style != 'Gentle & warm') {
      final choices = _node('2:6650').children
          .where((choice) => _label(choice) != _style);
      return Row(
        children: [
          for (final choice in choices)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: SizedBox(
                width: choice.width,
                height: choice.height,
                child: _source(choice),
              ),
            ),
        ],
      );
    }
    if (_live) {
      if (node.id == '2:6681') {
        final arrow = node.children.firstWhere((n) => n.name == 'arrow-right');
        final label = node.children.firstWhere((n) => n.text != null);
        final value = _controller?.busy == true
            ? 'Connecting…'
            : 'Meet $_companionName';
        return DesignButton(
          label: value,
          onTap: () => unawaited(_create()),
          child: CustomPaint(
            painter: DesignShapePainter(node, _library),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: DesignScene(root: arrow, library: _library),
                ),
                const SizedBox(width: 10),
                Text(
                  value,
                  style: designTextStyle(label).copyWith(height: 17 / 14),
                ),
              ],
            ),
          ),
        );
      }
      if (node.id == '2:6772' || node.id == '2:6996') {
        return LiveConversationPanel(
          root: node,
          library: _library,
          controller: _controller!,
          source: _source,
        );
      }
      if (node.id == '2:7157' || node.id == '2:6898') {
        final template = node.id == '2:7157'
            ? _node('2:7159')
            : _node('2:6898');
        final memories =
            _controller?.memories.where((m) {
              final text = '${m.title} ${m.content}'.toLowerCase();
              final matches = switch (_filter) {
                'People' => ['people', 'important_dates'].contains(m.category),
                'Little joys' => m.category == 'preferences',
                'Your world' => [
                  'personal_information',
                  'experiences',
                  'goals',
                ].contains(m.category),
                _ => true,
              };
              return matches && text.contains(_search.text.toLowerCase());
            }).toList() ??
            [];
        return LiveMemoryCollection(
          template: template,
          memories: memories,
          library: _library,
        );
      }
      if (node.name == 'Recent conversations') {
        final label = node.children.firstWhere(
          (n) => n.name == 'Section label',
        );
        final slots = node.children
            .where((n) => n.name == 'Conversation')
            .toList();
        final conversations = _controller?.conversations ?? [];
        return Stack(
          children: [
            Positioned(
              left: label.x,
              top: label.y,
              width: label.width,
              height: label.height,
              child: _source(label),
            ),
            for (
              var i = 0;
              i < math.min(slots.length, conversations.length);
              i++
            )
              Positioned(
                left: slots[i].x,
                top: slots[i].y,
                width: node.width - slots[i].x,
                height: slots[i].height,
                child: DesignButton(
                  label: conversations[i].title,
                  onTap: () {
                    _go(CompanionPage.conversation);
                    unawaited(_controller!.openConversation(conversations[i]));
                  },
                  child: Text(
                    conversations[i].title,
                    style: designTextStyle(slots[i]).copyWith(height: 15 / 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        );
      }
      if (node.id == '2:7053' || node.id == '2:7058') {
        if (!_memory) return const SizedBox.shrink();
        final index = node.id == '2:7053' ? 0 : 1;
        final memories = _controller?.memories ?? [];
        if (memories.length <= index) return const SizedBox.shrink();
        final memory = memories[index];
        return LiveMemoryReference(
          node: node,
          library: _library,
          memory: memory,
        );
      }
      if (node.id == '2:7027') return const SizedBox.shrink();
    }
    if (node.id == '2:6646') {
      return Semantics(
        label: 'Companion name',
        textField: true,
        child: DesignField(
          node: node,
          controller: _name,
          label: 'Companion name',
          maxLength: 24,
          onChanged: (_) => setState(() {}),
        ),
      );
    }
    if (node.id == '2:6795' || node.id == '2:7035') {
      return Semantics(
        label: 'Message draft',
        textField: true,
        child: DesignField(
          node: node,
          controller: _draft,
          hint: node.text,
          label: 'Message draft',
        ),
      );
    }
    if (node.id == '2:7147') {
      return Semantics(
        label: 'Search memories',
        textField: true,
        child: DesignField(
          node: node,
          controller: _search,
          hint: node.text,
          label: 'Search memories',
          onChanged: (_) => setState(() {}),
        ),
      );
    }
    if (node.name == 'Switch') {
      if (_live && !{'2:6678', '2:6887', '2:7143'}.contains(node.id)) {
        final preferences = _controller!.notificationPreferences;
        final (value, label) = switch (node.id) {
          '2:7067' ||
          '2:7238' => (preferences.checkins, 'Thoughtful check-ins'),
          '2:7247' => (preferences.suggestions, 'Little suggestions'),
          _ => (preferences.birthdays, 'Birthday nudges'),
        };
        return DesignToggle(
          node: node,
          library: _library,
          value: value,
          label: label,
          onStyle: _node('2:6678'),
          offStyle: _node('2:7253'),
          onChanged: (enabled) => unawaited(
            _controller!.saveNotificationPreferences(switch (node.id) {
              '2:7067' || '2:7238' => preferences.copyWith(checkins: enabled),
              '2:7247' => preferences.copyWith(suggestions: enabled),
              _ => preferences.copyWith(birthdays: enabled),
            }),
          ),
        );
      }
      final (value, label, setter) = switch (node.id) {
        '2:6678' || '2:6887' || '2:7143' => (
          _memory,
          'Allow companion memories',
          (bool v) => _memory = v,
        ),
        '2:7067' || '2:7238' => (
          _checkins,
          'Thoughtful check-ins',
          (bool v) => _checkins = v,
        ),
        '2:7247' => (
          _suggestions,
          'Little suggestions',
          (bool v) => _suggestions = v,
        ),
        _ => (_birthdays, 'Birthday nudges', (bool v) => _birthdays = v),
      };
      return DesignToggle(
        node: node,
        library: _library,
        value: value,
        label: label,
        onStyle: _node('2:6678'),
        offStyle: _node('2:7253'),
        onChanged: (value) {
          setState(() => setter(value));
          _save();
        },
      );
    }
    if (node.id == '2:7224') {
      return _ResponseSlider(
        node: node,
        library: _library,
        value: _responseLength,
        onChanged: (value) {
          setState(() => _responseLength = value);
          _save();
        },
      );
    }
    if (node.id == '2:7157' && (_filter != 'All' || _search.text.isNotEmpty)) {
      final memories = node.descendants
          .where((n) => n.name == 'Memory')
          .where(_matchesMemory)
          .toList();
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final memory in memories)
            DesignScene(root: memory, library: _library, text: _text),
        ],
      );
    }
    return null;
  }

  Widget _source(DesignNode node) => DesignScene(
    root: node,
    library: _library,
    nodeOverride: _override,
    action: _action,
    text: _text,
    style: _choiceStyle,
  );

  String _today() {
    final date = DateTime.now();
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  bool _matchesMemory(DesignNode memory) {
    final value = _label(memory).toLowerCase();
    final category = switch (_filter) {
      'People' => value.contains('people you love'),
      'Little joys' => value.contains('little joys'),
      'Your world' => value.contains('your world') || value.contains('bristol'),
      _ => true,
    };
    return category && value.contains(_search.text.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Morrow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: const Color(0xfff9f7f2),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff61476d)),
    ),
    home: Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = _forceDesktop || constraints.maxWidth >= 1000;
          final name = switch (_page) {
            CompanionPage.setup => 'setup',
            CompanionPage.home => 'home',
            CompanionPage.conversation =>
              desktop ? 'desktop_conversation' : 'conversation',
            CompanionPage.voice => 'voice',
            CompanionPage.memories => desktop ? 'desktop_memories' : 'memories',
          };
          final root = _library.screens[name]!;
          final scale = math.min(1.0, constraints.maxWidth / root.width);
          final hidden = <String>{};
          if (_live) {
            hidden.addAll({'2:6906', '2:6914'});
          }
          if (!_captions) hidden.add('2:6848');
          if (!_live && name == 'memories' && _filter != 'All') {
            for (final memory in root.descendants.where(
              (n) => n.name == 'Memory',
            )) {
              if (!_matchesMemory(memory)) hidden.add(memory.id);
            }
            if (_filter != 'Little joys') hidden.add('2:6914');
          }
          return SingleChildScrollView(
            key: ValueKey('viewport-$name'),
            child: Center(
              child: SizedBox(
                width: root.width * scale,
                height: root.height * scale,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  child: DesignScene(
                    root: root,
                    library: _library,
                    nodeOverride: _override,
                    action: _action,
                    text: _text,
                    style: _choiceStyle,
                    hidden: hidden,
                    bounds: {
                      '2:6646': Rect.fromLTWH(
                        _node('2:6646').x,
                        _node('2:6646').y,
                        286,
                        _node('2:6646').height,
                      ),
                      '2:6649': Rect.fromLTWH(
                        _node('2:6649').x,
                        _node('2:6649').y,
                        350,
                        _node('2:6649').height,
                      ),
                      if (_live)
                        '2:6898': const Rect.fromLTWH(24, 269, 354, 423),
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _ResponseSlider extends StatelessWidget {
  const _ResponseSlider({
    required this.node,
    required this.library,
    required this.value,
    required this.onChanged,
  });
  final DesignNode node;
  final DesignLibrary library;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final left = value * (node.width - 16);
    return Semantics(
      label: 'Response length',
      value: '${(value * 100).round()}%',
      increasedValue: '${((value + .1).clamp(0, 1) * 100).round()}%',
      decreasedValue: '${((value - .1).clamp(0, 1) * 100).round()}%',
      onIncrease: () => onChanged((value + .1).clamp(0, 1)),
      onDecrease: () => onChanged((value - .1).clamp(0, 1)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => onChanged(
          ((details.localPosition.dx - 8) / (node.width - 16)).clamp(0, 1),
        ),
        onHorizontalDragUpdate: (details) => onChanged(
          ((details.localPosition.dx - 8) / (node.width - 16)).clamp(0, 1),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 7.5,
              width: left,
              height: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: designColor(
                    node.children.first.list('fills').first['color'],
                  ),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            Positioned(
              left: left + 16,
              top: 7.5,
              width: node.width - left - 16,
              height: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: designColor(
                    node.children.last.list('fills').first['color'],
                  ),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: 1,
              width: 16,
              height: 16,
              child: CustomPaint(
                painter: DesignShapePainter(node.children[1], library),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
