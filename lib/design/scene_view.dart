import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scene.dart';
import 'scene_painter.dart';

typedef DesignOverride = Widget? Function(DesignNode node);
typedef DesignAction = VoidCallback? Function(DesignNode node);

/// Reuses source components at their authored reference geometry. A parent
/// viewport supplies the responsive scale; all controls remain native widgets.
class DesignScene extends StatelessWidget {
  const DesignScene({
    super.key,
    required this.root,
    required this.library,
    this.nodeOverride,
    this.action,
    this.text,
    this.style,
    this.hidden = const {},
    this.bounds = const {},
  });

  final DesignNode root;
  final DesignLibrary library;
  final DesignOverride? nodeOverride;
  final DesignAction? action;
  final String Function(DesignNode)? text;
  final DesignNode? Function(DesignNode)? style;
  final Set<String> hidden;
  final Map<String, Rect> bounds;

  Widget _node(DesignNode node) {
    if (!node.visible || hidden.contains(node.id)) {
      return const SizedBox.shrink();
    }
    final custom = nodeOverride?.call(node);
    if (custom != null) return custom;
    Widget child;
    if (node.type == 'TEXT') {
      child = DesignText(node: node, value: text?.call(node));
    } else {
      final sourceStyle = style?.call(node);
      child = CustomPaint(
        painter: DesignShapePainter(
          node,
          library,
          fills: sourceStyle?.list('fills'),
          strokes: sourceStyle?.list('strokes'),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final item in node.children)
              Positioned(
                left: bounds[item.id]?.left ?? item.x,
                top: bounds[item.id]?.top ?? item.y,
                width: bounds[item.id]?.width ?? item.width,
                height: bounds[item.id]?.height ?? item.height,
                child: Transform(
                  transform: Matrix4.identity()
                    ..setEntry(
                      0,
                      0,
                      DesignNode.number(item.transform['m00'], 1),
                    )
                    ..setEntry(0, 1, DesignNode.number(item.transform['m01']))
                    ..setEntry(1, 0, DesignNode.number(item.transform['m10']))
                    ..setEntry(
                      1,
                      1,
                      DesignNode.number(item.transform['m11'], 1),
                    ),
                  child: _node(item),
                ),
              ),
          ],
        ),
      );
      if (node.data['clip'] == true) {
        child = ClipPath(clipper: DesignClipper(node, library), child: child);
      }
    }
    if (node.opacity != 1) child = Opacity(opacity: node.opacity, child: child);
    final onTap = action?.call(node);
    if (onTap != null) {
      child = DesignButton(
        label: node.descendants
            .where((n) => n.text != null)
            .map((n) => text?.call(n) ?? n.text!)
            .join(' '),
        onTap: onTap,
        child: child,
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: root.width, height: root.height, child: _node(root));
}

class DesignButton extends StatelessWidget {
  const DesignButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    ),
  );
}

class DesignText extends StatelessWidget {
  const DesignText({super.key, required this.node, this.value});
  final DesignNode node;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final original = node.text ?? '';
    final resolved = value ?? original;
    final style = designTextStyle(node);
    if (resolved != original || node.list('lines').isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          resolved,
          style: style.copyWith(
            height: node.list('lines').isEmpty
                ? 1.3
                : DesignNode.number(node.list('lines').first['lineHeight']) /
                      DesignNode.number(node.data['fontSize'], 13),
          ),
          textAlign: switch (node.data['align']) {
            'CENTER' => TextAlign.center,
            'RIGHT' => TextAlign.right,
            _ => TextAlign.left,
          },
        ),
      );
    }
    return Semantics(
      label: resolved,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final line in node.list('lines'))
            Positioned(
              left: DesignNode.number((line['position'] as Map)['x']),
              top: 0,
              child: Baseline(
                baseline: DesignNode.number((line['position'] as Map)['y']),
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  original
                      .substring(
                        (line['firstCharacter'] as num).toInt().clamp(
                          0,
                          original.length,
                        ),
                        (line['endCharacter'] as num).toInt().clamp(
                          0,
                          original.length,
                        ),
                      )
                      .replaceAll('\n', ''),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DesignField extends StatelessWidget {
  const DesignField({
    super.key,
    required this.node,
    required this.controller,
    this.hint,
    this.label,
    this.onChanged,
    this.maxLength,
  });
  final DesignNode node;
  final TextEditingController controller;
  final String? hint;
  final String? label;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: designTextStyle(node),
    textAlignVertical: TextAlignVertical.center,
    cursorColor: const Color(0xff61476d),
    maxLength: maxLength,
    inputFormatters: [
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ],
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: designTextStyle(node),
      semanticCounterText: label,
      counterText: '',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
  );
}

class DesignToggle extends StatelessWidget {
  const DesignToggle({
    super.key,
    required this.node,
    required this.library,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.onStyle,
    required this.offStyle,
  });
  final DesignNode node;
  final DesignLibrary library;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final DesignNode onStyle;
  final DesignNode offStyle;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: value,
    excludeSemantics: true,
    child: DesignButton(
      label: label,
      onTap: () => onChanged(!value),
      child: CustomPaint(
        painter: DesignShapePainter(
          node,
          library,
          fills: (value ? onStyle : offStyle).list('fills'),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final handle in node.children)
              Positioned(
                left: value ? 17 : 3,
                top: 3,
                width: handle.width,
                height: handle.height,
                child: CustomPaint(
                  painter: DesignShapePainter(handle, library),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
