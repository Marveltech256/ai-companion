import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'scene.dart';

/// Paints the original source paths, including expanded stroke outlines.
/// No screenshot, substituted icon font, or hand-redrawn companion is used.
class DesignShapePainter extends CustomPainter {
  DesignShapePainter(this.node, this.library, {this.fills, this.strokes});
  final DesignNode node;
  final DesignLibrary library;
  final List<Map>? fills;
  final List<Map>? strokes;

  Path pathFor(Map geometry) {
    final original = library.geometry['${geometry['commandsBlob']}'];
    if (original == null) throw StateError('Original path is missing.');
    return Path.from(original)
      ..fillType = geometry['windingRule'] == 'ODD'
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paths = node.list('fillGeometry');
    for (final effect in node.list('effects')) {
      if (effect['visible'] == false || effect['type'] != 'DROP_SHADOW') {
        continue;
      }
      final offset = effect['offset'] as Map?;
      for (final geometry in paths) {
        canvas.drawPath(
          pathFor(geometry).shift(
            Offset(
              DesignNode.number(offset?['x']),
              DesignNode.number(offset?['y']),
            ),
          ),
          Paint()
            ..color = designColor(effect['color'])
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              DesignNode.number(effect['radius']) / 2,
            ),
        );
      }
    }
    _paintPaths(canvas, paths, fills ?? node.list('fills'));
    // Figma strokeGeometry already describes the entire stroke as a filled
    // outline. Stroking it again would double its thickness and round its ends.
    _paintPaths(
      canvas,
      node.list('strokeGeometry'),
      strokes ?? node.list('strokes'),
    );
  }

  void _paintPaths(Canvas canvas, List<Map> geometry, List<Map> paints) {
    for (final source in paints.reversed) {
      if (source['visible'] == false) continue;
      final paint = Paint()..isAntiAlias = true;
      final opacity = DesignNode.number(source['opacity'], 1);
      if (source['type'] == 'SOLID') {
        paint.color = designColor(source['color'], opacity);
      } else if (source['type'] == 'GRADIENT_RADIAL' ||
          source['type'] == 'GRADIENT_LINEAR') {
        final stops = (source['stops'] as List).cast<Map>();
        final colors = stops
            .map((s) => designColor(s['color'], opacity))
            .toList();
        final positions = stops
            .map((s) => DesignNode.number(s['position']))
            .toList();
        final transform = source['transform'] as Map;
        final a = DesignNode.number(transform['m00'], 1);
        final b = DesignNode.number(transform['m01']);
        final c = DesignNode.number(transform['m02']);
        final d = DesignNode.number(transform['m10']);
        final e = DesignNode.number(transform['m11'], 1);
        final f = DesignNode.number(transform['m12']);
        final determinant = a * e - b * d;
        final matrix = Matrix4.identity();
        matrix.setEntry(0, 0, node.width * e / determinant);
        matrix.setEntry(0, 1, -node.width * b / determinant);
        matrix.setEntry(0, 3, node.width * (b * f - e * c) / determinant);
        matrix.setEntry(1, 0, -node.height * d / determinant);
        matrix.setEntry(1, 1, node.height * a / determinant);
        matrix.setEntry(1, 3, node.height * (d * c - a * f) / determinant);
        paint.shader = source['type'] == 'GRADIENT_RADIAL'
            ? ui.Gradient.radial(
                const Offset(.5, .5),
                .5,
                colors,
                positions,
                TileMode.clamp,
                matrix.storage,
              )
            : ui.Gradient.linear(
                const Offset(0, .5),
                const Offset(1, .5),
                colors,
                positions,
                TileMode.clamp,
                matrix.storage,
              );
      } else {
        throw StateError('Unsupported original paint ${source['type']}');
      }
      for (final shape in geometry) {
        canvas.drawPath(pathFor(shape), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DesignShapePainter oldDelegate) =>
      oldDelegate.node != node ||
      oldDelegate.fills != fills ||
      oldDelegate.strokes != strokes;
}

class DesignClipper extends CustomClipper<Path> {
  DesignClipper(this.node, this.library);
  final DesignNode node;
  final DesignLibrary library;
  @override
  Path getClip(Size size) {
    final geometry = node.list('fillGeometry');
    if (geometry.isNotEmpty) {
      return DesignShapePainter(node, library).pathFor(geometry.first);
    }
    return Path()..addRect(Offset.zero & size);
  }

  @override
  bool shouldReclip(DesignClipper oldClipper) => oldClipper.node != node;
}
