import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Original authoring values from the approved .fig export, without glyph data
/// or Figma account metadata. Each screen remains an editable native scene.
class DesignNode {
  DesignNode(this.data)
    : children = ((data['children'] as List?) ?? [])
          .map((item) => DesignNode(Map<String, dynamic>.from(item)))
          .toList();

  final Map<String, dynamic> data;
  final List<DesignNode> children;
  String get id => data['id'];
  String get name => data['name'];
  String get type => data['type'];
  String? get text => data['text'];
  double get width => number((data['size'] as Map?)?['x']);
  double get height => number((data['size'] as Map?)?['y']);
  Map get transform => data['transform'] ?? const {};
  double get x => number(transform['m02']);
  double get y => number(transform['m12']);
  double get opacity => number(data['opacity'], 1);
  bool get visible => data['visible'] != false;
  List<Map> list(String key) => ((data[key] as List?) ?? []).cast<Map>();
  Iterable<DesignNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  static double number(dynamic value, [double fallback = 0]) =>
      value is num ? value.toDouble() : fallback;
}

class DesignLibrary {
  DesignLibrary._(this.screens, this.geometry);
  final Map<String, DesignNode> screens;
  final Map<String, ui.Path> geometry;
  static const screenNames = [
    'setup',
    'home',
    'conversation',
    'voice',
    'memories',
    'desktop_conversation',
    'desktop_memories',
  ];

  static Future<DesignLibrary> load() async {
    final values = await Future.wait([
      for (final name in screenNames)
        rootBundle.loadString('assets/design/$name.json'),
      rootBundle.loadString('assets/design/geometry.json'),
    ]);
    final screens = <String, DesignNode>{};
    for (var i = 0; i < screenNames.length; i++) {
      screens[screenNames[i]] = DesignNode(jsonDecode(values[i]));
    }
    final rawGeometry = jsonDecode(values.last) as Map<String, dynamic>;
    final geometry = <String, ui.Path>{};
    for (final entry in rawGeometry.entries) {
      final path = ui.Path();
      for (final raw in entry.value as List) {
        final command = (raw as List).cast<num>();
        double v(int i) => command[i].toDouble();
        switch (command.first.toInt()) {
          case 1:
            path.moveTo(v(1), v(2));
          case 2:
            path.lineTo(v(1), v(2));
          case 3:
            path.quadraticBezierTo(v(1), v(2), v(3), v(4));
          case 4:
            path.cubicTo(v(1), v(2), v(3), v(4), v(5), v(6));
          case 5:
            path.close();
          default:
            throw FormatException('Unsupported original geometry command.');
        }
      }
      geometry[entry.key] = path;
    }
    return DesignLibrary._(screens, geometry);
  }
}

Color designColor(Map? color, [double opacity = 1]) => Color.from(
  alpha: DesignNode.number(color?['a'], 1) * opacity,
  red: DesignNode.number(color?['r']),
  green: DesignNode.number(color?['g']),
  blue: DesignNode.number(color?['b']),
);

TextStyle designTextStyle(DesignNode node) => TextStyle(
  fontFamily: (node.data['font'] as Map?)?['family'] ?? 'Inter',
  fontSize: DesignNode.number(node.data['fontSize'], 13),
  fontWeight:
      FontWeight.values[((DesignNode.number(node.data['weight'], 400) / 100)
                  .round() -
              1)
          .clamp(0, 8)],
  color: node.list('fills').isEmpty
      ? const Color(0xff302638)
      : designColor(node.list('fills').first['color']),
  height: 1,
  letterSpacing:
      DesignNode.number((node.data['letterSpacing'] as Map?)?['value']) *
      DesignNode.number(node.data['fontSize'], 13) /
      100,
);
