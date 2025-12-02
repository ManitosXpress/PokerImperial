import 'package:flutter/material.dart';
import 'dart:math' as math;

class PokerLoadingIndicator extends StatefulWidget {
  final String? statusText;
  final double size;
  final Color color;

  const PokerLoadingIndicator({
    super.key,
    this.statusText,
    this.size = 60.0,
    this.color = const Color(0xFFFFD700), // Gold
  });

  @override
  State<PokerLoadingIndicator> createState() => _PokerLoadingIndicatorState();
}

class _PokerLoadingIndicatorState extends State<PokerLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Rotating outer ring
                  Transform.rotate(
                    angle: _controller.value * 2 * math.pi,
                    child: CustomPaint(
                      painter: _RingPainter(color: widget.color),
                      size: Size(widget.size, widget.size),
                    ),
                  ),
                  // Pulsing inner chip
                  Transform.scale(
                    scale: 0.8 + (0.2 * math.sin(_controller.value * 2 * math.pi)),
                    child: Icon(
                      Icons.casino, // Use a poker-related icon
                      color: widget.color,
                      size: widget.size * 0.5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (widget.statusText != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.statusText!,
            style: TextStyle(
              color: widget.color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;

  _RingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 3) / 2;

    // Draw a broken ring (3 segments)
    const segmentAngle = 2 * math.pi / 3;
    const gapAngle = 0.4;

    for (int i = 0; i < 3; i++) {
      final startAngle = (i * segmentAngle) + gapAngle / 2;
      final sweepAngle = segmentAngle - gapAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
