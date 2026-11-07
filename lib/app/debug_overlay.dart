import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../detection/detection_result.dart';
import '../detection/object_detector.dart';

/// Draws detection boxes over the preview. Researcher tool, off by default and
/// hidden from screen readers; end users never see it.
class DebugOverlay extends StatelessWidget {
  const DebugOverlay({super.key, required this.output});

  final ValueListenable<DetectionOutput?> output;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ValueListenableBuilder<DetectionOutput?>(
          valueListenable: output,
          builder: (BuildContext context, DetectionOutput? value, Widget? _) {
            return CustomPaint(
              size: Size.infinite,
              painter: value == null ? null : DebugOverlayPainter(value),
            );
          },
        ),
      ),
    );
  }
}

/// Maps normalized boxes to the screen the same way the preview is cropped to
/// fill it (BoxFit.cover).
class DebugOverlayPainter extends CustomPainter {
  const DebugOverlayPainter(this.output);

  final DetectionOutput output;

  /// Screen rectangle of a normalized box.
  static Rect mapBox(Rect box, Size screen, int imageWidth, int imageHeight) {
    final double scaleX = screen.width / imageWidth;
    final double scaleY = screen.height / imageHeight;
    final double scale = scaleX > scaleY ? scaleX : scaleY;
    final double width = imageWidth * scale;
    final double height = imageHeight * scale;
    final double left = (screen.width - width) / 2;
    final double top = (screen.height - height) / 2;
    return Rect.fromLTRB(
      left + box.left * width,
      top + box.top * height,
      left + box.right * width,
      top + box.bottom * height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final DetectionResult d in output.detections) {
      final Rect rect = mapBox(
        d.box,
        size,
        output.imageWidth,
        output.imageHeight,
      );
      canvas.drawRect(rect, stroke);
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: '${d.classId} ${d.confidence.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRect(
        rect.topLeft & Size(label.width + 4, label.height),
        Paint()..color = Colors.amber,
      );
      label.paint(canvas, rect.topLeft + const Offset(2, 0));
    }
  }

  @override
  bool shouldRepaint(DebugOverlayPainter oldDelegate) =>
      !identical(oldDelegate.output, output);
}
