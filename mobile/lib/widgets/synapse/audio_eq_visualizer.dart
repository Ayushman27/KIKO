import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'synapse_theme.dart';

/// 32-Bar Animated Audio Frequency Equalizer
/// Dynamically bounces and responds during speech/listening/synthesis.
class AudioEqVisualizer extends StatefulWidget {
  final bool isGMode;
  final bool isSpeaking;
  final bool isListening;
  final int barCount;
  final double height;

  const AudioEqVisualizer({
    super.key,
    required this.isGMode,
    this.isSpeaking = true,
    this.isListening = false,
    this.barCount = 32,
    this.height = 32.0,
  });

  @override
  State<AudioEqVisualizer> createState() => _AudioEqVisualizerState();
}

class _AudioEqVisualizerState extends State<AudioEqVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _baseHeights = [];
  final math.Random _random = math.Random(42);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    for (int i = 0; i < widget.barCount; i++) {
      _baseHeights.add(0.2 + _random.nextDouble() * 0.8);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);

    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(widget.barCount, (i) {
              final active = widget.isSpeaking || widget.isListening;
              final barColor = widget.isListening
                  ? (widget.isGMode ? const Color(0xFFFF5252) : const Color(0xFF00E5FF))
                  : accent;

              double barRatio;
              if (active) {
                // Organic audio wave fluctuation based on time and index
                final t = DateTime.now().millisecondsSinceEpoch / (widget.isListening ? 70.0 : 100.0);
                final wave = math.sin(t * 0.9 + i * 0.5) * 0.45 +
                    math.cos(t * 1.5 - i * 0.35) * 0.35;
                barRatio = (0.28 + (wave + 0.7) * 0.55 * _baseHeights[i]).clamp(0.15, 1.0);
              } else {
                barRatio = 0.15; // idle hairline
              }

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.0),
                  height: widget.height * barRatio,
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(active ? 0.45 + (barRatio * 0.55) : 0.2),
                    borderRadius: BorderRadius.circular(4.0),
                    boxShadow: active && barRatio > 0.55
                        ? [
                            BoxShadow(
                              color: barColor.withOpacity(0.4),
                              blurRadius: 5.0,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Dynamic Spectral Density Sparkline Graph
class SpectralSparkline extends StatefulWidget {
  final bool isGMode;
  final double height;

  const SpectralSparkline({
    super.key,
    required this.isGMode,
    this.height = 36.0,
  });

  @override
  State<SpectralSparkline> createState() => _SpectralSparklineState();
}

class _SpectralSparklineState extends State<SpectralSparkline>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SparklinePainter(
              progress: _controller.value,
              accent: accent,
            ),
          );
        },
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final double progress;
  final Color accent;

  _SparklinePainter({
    required this.progress,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final fillPath = Path();

    final t = progress * 2 * math.pi;
    final w = size.width;
    final h = size.height;

    path.moveTo(0, h * 0.5);
    fillPath.moveTo(0, h * 0.5);

    const int steps = 40;
    for (int i = 0; i <= steps; i++) {
      final x = (i / steps) * w;
      final normX = i / steps;
      final y = h * 0.5 +
          math.sin(normX * 12.0 + t) * (h * 0.3) +
          math.cos(normX * 24.0 - t * 1.5) * (h * 0.15);

      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(w, h);
    fillPath.lineTo(0, h);
    fillPath.close();

    // Fill under curve
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accent.withOpacity(0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Glowing stroke
    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accent != accent;
  }
}
