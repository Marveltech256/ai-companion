import 'package:flutter/material.dart';

import 'dart:async';

import '../data/models.dart';
import '../design/scene.dart';
import '../design/scene_painter.dart';
import '../design/scene_view.dart';
import 'companion_controller.dart';

typedef SourceBuilder = Widget Function(DesignNode node);

TextStyle _flowStyle(DesignNode node) {
  final lines = node.list('lines');
  final size = DesignNode.number(node.data['fontSize'], 13);
  return designTextStyle(node).copyWith(
    height: lines.isEmpty
        ? 1.4
        : DesignNode.number(lines.first['lineHeight']) / size,
  );
}

/// Live content occupies the same message column and composer slots as Figma.
/// Message text is reflowed rather than clipped into the example transcript.
class LiveConversationPanel extends StatelessWidget {
  const LiveConversationPanel({
    super.key,
    required this.root,
    required this.library,
    required this.controller,
    required this.source,
  });
  final DesignNode root;
  final DesignLibrary library;
  final CompanionController controller;
  final SourceBuilder source;

  @override
  Widget build(BuildContext context) {
    final desktop = root.id == '2:6996';
    final nodes = {
      for (final n
          in library
              .screens[desktop ? 'desktop_conversation' : 'conversation']!
              .descendants)
        n.id: n,
    };
    final composer = root.children.firstWhere(
      (n) => n.name == 'Message composer',
    );
    final date = root.children.firstWhere(
      (n) => n.name == 'Date' || n.name == 'Conversation date',
    );
    final user = nodes[desktop ? '2:7005' : '2:6777']!;
    final userText = nodes[desktop ? '2:7006' : '2:6778']!;
    final assistantText = nodes[desktop ? '2:7003' : '2:6775']!;
    final speaker = nodes[desktop ? '2:7000' : '2:6780']!;
    final memory = desktop ? null : nodes['2:6787'];
    final top = desktop ? 57.0 : 42.0;
    final bottom = composer.y - (desktop ? 20 : 42);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: date.x,
          top: date.y,
          width: date.width,
          height: date.height,
          child: source(date),
        ),
        Positioned(
          left: composer.x,
          top: top,
          width: composer.width,
          height: bottom - top,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 40) {
                unawaited(controller.loadOlderMessages());
              }
              return false;
            },
            child: ListView.builder(
              reverse: true,
              padding: EdgeInsets.zero,
              itemCount: controller.messages.length,
              itemBuilder: (context, index) {
                final message =
                    controller.messages[controller.messages.length - 1 - index];
                final isUser = message.role == 'user';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isUser ? user.width : composer.width,
                      ),
                      child: isUser
                          ? Container(
                              padding: EdgeInsets.all(desktop ? 18 : 16),
                              decoration: BoxDecoration(
                                color: designColor(
                                  user.list('fills').first['color'],
                                ),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: const Radius.circular(20),
                                  bottomRight: const Radius.circular(4),
                                ),
                              ),
                              child: SelectableText(
                                message.content,
                                style: _flowStyle(userText),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (desktop ||
                                    controller.messages.indexOf(message) >
                                        0) ...[
                                  SizedBox(
                                    width: speaker.width,
                                    height: speaker.height,
                                    child: source(speaker),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                SelectableText(
                                  message.content.isEmpty && message.pending
                                      ? '…'
                                      : message.content,
                                  style: _flowStyle(assistantText),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (memory != null)
          Positioned(
            left: memory.x,
            top: composer.y - 32,
            width: memory.width,
            height: memory.height,
            child: source(memory),
          ),
        Positioned(
          left: composer.x,
          top: composer.y,
          width: composer.width,
          height: composer.height,
          child: source(composer),
        ),
      ],
    );
  }
}

class LiveMemoryCollection extends StatelessWidget {
  const LiveMemoryCollection({
    super.key,
    required this.template,
    required this.memories,
    required this.library,
  });
  final DesignNode template;
  final List<CompanionMemory> memories;
  final DesignLibrary library;

  DesignNode _category(String category) {
    final id = switch (category) {
      'people' || 'important_dates' => '2:7159',
      'preferences' => '2:7176',
      'communication_preferences' || 'goals' => '2:7184',
      _ => '2:7167',
    };
    return library.screens['desktop_memories']!.descendants
        .firstWhere((n) => n.id == id)
        .children
        .firstWhere((n) => n.name == 'Category');
  }

  String _categoryLabel(String category) => switch (category) {
    'people' || 'important_dates' => 'PEOPLE YOU LOVE',
    'preferences' => 'LITTLE JOYS',
    'communication_preferences' || 'goals' => 'WHAT MATTERS TO YOU',
    _ => 'YOUR WORLD',
  };

  @override
  Widget build(BuildContext context) {
    final title = template.children.firstWhere((n) => n.name == 'Title');
    final detail = template.children.firstWhere((n) => n.name == 'Detail');
    final meta = template.children.firstWhere((n) => n.name == 'Source');
    final category = template.children.firstWhere((n) => n.name == 'Category');
    final categoryText = category.children.firstWhere((n) => n.text != null);
    return SingleChildScrollView(
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final memory in memories)
            SizedBox(
              width: template.width,
              child: Container(
                constraints: const BoxConstraints(minHeight: 161),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: designColor(template.list('fills').first['color']),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: designColor(template.list('strokes').first['color']),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          for (final icon
                              in _category(memory.category).children
                                  .where(
                                    (n) =>
                                        n.type == 'FRAME' &&
                                        n.name != 'ellipsis',
                                  )
                                  .take(1))
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: DesignScene(root: icon, library: library),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _categoryLabel(memory.category),
                              style: _flowStyle(categoryText),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final icon in category.children.where(
                            (n) => n.name == 'ellipsis',
                          ))
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: DesignScene(root: icon, library: library),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(memory.title, style: _flowStyle(title)),
                    const SizedBox(height: 11),
                    SelectableText(memory.content, style: _flowStyle(detail)),
                    const SizedBox(height: 11),
                    Text(
                      'Yours to keep, change, or let go.',
                      style: _flowStyle(meta),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps live values inside the original fixed-height context card.
class LiveMemoryReference extends StatelessWidget {
  const LiveMemoryReference({
    super.key,
    required this.node,
    required this.library,
    required this.memory,
  });
  final DesignNode node;
  final DesignLibrary library;
  final CompanionMemory memory;

  @override
  Widget build(BuildContext context) {
    final heading = node.children.firstWhere((n) => n.name == 'Memory title');
    final title = heading.children.firstWhere((n) => n.name == 'Title');
    final icon = heading.children.firstWhere((n) => n.type == 'FRAME');
    final detail = node.children.firstWhere((n) => n.name == 'Detail');
    return CustomPaint(
      painter: DesignShapePainter(node, library),
      child: Stack(
        children: [
          Positioned(
            left: heading.x,
            top: heading.y,
            width: icon.width,
            height: icon.height,
            child: DesignScene(root: icon, library: library),
          ),
          Positioned(
            left: heading.x + title.x,
            top: heading.y,
            width: node.width - heading.x - title.x - 15,
            height: heading.height,
            child: Text(
              memory.title,
              style: _flowStyle(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: detail.x,
            top: detail.y,
            width: detail.width,
            height: detail.height,
            child: Text(
              memory.content,
              style: _flowStyle(detail),
              maxLines: (detail.height / 18).round(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
