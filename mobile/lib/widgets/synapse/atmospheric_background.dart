import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Dynamic Atmospheric Background Canvas
/// Directly renders the Stitch WebGL GLSL organic domain-warped smoke shader
/// with interactive mouse tracking and smooth dual-mode (Alpha <-> G-Mode) transition.
class AtmosphericBackground extends StatefulWidget {
  final bool isGMode;
  final double speed;
  final Widget? child;

  const AtmosphericBackground({
    super.key,
    required this.isGMode,
    this.speed = 0.35, // Slower, relaxed ambient pace (approx ~35% of original speed)
    this.child,
  });

  @override
  State<AtmosphericBackground> createState() => _AtmosphericBackgroundState();
}

class _AtmosphericBackgroundState extends State<AtmosphericBackground>
    with TickerProviderStateMixin {
  ui.FragmentProgram? _program;
  late final AnimationController _timeController;
  late final AnimationController _gModeController;
  late final Stopwatch _stopwatch;
  Offset _mousePosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3600),
    )..repeat();

    _gModeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: widget.isGMode ? 1.0 : 0.0,
    );

    _loadShader();
  }

  @override
  void didUpdateWidget(covariant AtmosphericBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isGMode != widget.isGMode) {
      if (widget.isGMode) {
        _gModeController.forward();
      } else {
        _gModeController.reverse();
      }
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/atmospheric_smoke.frag',
      );
      if (mounted) {
        setState(() {
          _program = program;
        });
      }
    } catch (e) {
      debugPrint('AtmosphericBackground shader load: $e');
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    _gModeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        _mousePosition = event.localPosition;
      },
      child: Stack(
        children: [
          // Animated Background Shader with fallback
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_timeController, _gModeController]),
              builder: (context, _) {
                final time = (_stopwatch.elapsedMilliseconds / 1000.0) * widget.speed;
                final gModeVal = _gModeController.value;

                if (_program != null) {
                  return CustomPaint(
                    painter: _GlslAtmosphericSmokePainter(
                      shader: _program!.fragmentShader(),
                      time: time,
                      mousePosition: _mousePosition,
                      isGMode: gModeVal,
                    ),
                  );
                }

                // High-fidelity fallback painter if shader is compiling or in headless tests
                return CustomPaint(
                  painter: _ShaderSmokePainter(
                    progress: (_timeController.value * (25 * widget.speed)) % 1.0,
                    isGMode: widget.isGMode,
                  ),
                );
              },
            ),
          ),

          // Foreground content if provided
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

/// GPU-Accelerated GLSL Runtime Shader Painter
class _GlslAtmosphericSmokePainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final Offset mousePosition;
  final double isGMode;

  _GlslAtmosphericSmokePainter({
    required this.shader,
    required this.time,
    required this.mousePosition,
    required this.isGMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // uniform vec2 u_resolution; // index 0, 1
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);

    // uniform float u_time;      // index 2
    shader.setFloat(2, time);

    // uniform vec2 u_mouse;      // index 3, 4
    final mx = mousePosition == Offset.zero ? size.width * 0.5 : mousePosition.dx;
    final my = mousePosition == Offset.zero ? size.height * 0.5 : mousePosition.dy;
    shader.setFloat(3, mx);
    shader.setFloat(4, my);

    // uniform float u_is_gmode;  // index 5
    shader.setFloat(5, isGMode);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _GlslAtmosphericSmokePainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.isGMode != isGMode ||
        oldDelegate.mousePosition != mousePosition;
  }
}

/// Fallback Procedural Painter for environments without GLSL runtime effect support
class _ShaderSmokePainter extends CustomPainter {
  final double progress;
  final bool isGMode;

  _ShaderSmokePainter({
    required this.progress,
    required this.isGMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;

    final primary = isGMode
        ? const Color(0xFFFF5625)
        : const Color(0xFF00F0FF);
    final secondary = isGMode
        ? const Color(0xFFFF3300)
        : const Color(0xFF4D3BFF);
    final ambient = isGMode
        ? const Color(0x1FFF6E40)
        : const Color(0x1800F0FF);

    // Layer 1: Background Aura
    final path1 = Path();
    path1.moveTo(0, size.height * 0.2);
    for (double x = 0; x <= size.width; x += 15) {
      final y = size.height * 0.25 +
          math.sin(x * 0.003 + t * 0.6) * 45 +
          math.cos(x * 0.007 - t * 0.4) * 35;
      path1.lineTo(x, y);
    }
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();

    final paint1 = Paint()
      ..shader = RadialGradient(
        center: Alignment(math.sin(t * 0.5) * 0.4, -0.2),
        radius: 0.9,
        colors: [ambient, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path1, paint1);

    // Layer 2: Ribbon A
    final path2 = Path();
    final yBase2 = size.height * 0.45;
    path2.moveTo(0, yBase2);
    for (double x = 0; x <= size.width; x += 20) {
      final wave = math.sin((x / size.width) * 4.0 + t) * 55 +
          math.sin((x / size.width) * 8.0 - t * 1.5) * 25;
      path2.lineTo(x, yBase2 + wave);
    }
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          secondary.withOpacity(0.08),
          primary.withOpacity(0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawPath(path2, paint2);

    // Layer 3: Ribbon B
    final path3 = Path();
    final yBase3 = size.height * 0.65;
    path3.moveTo(0, yBase3);
    for (double x = 0; x <= size.width; x += 20) {
      final wave = math.cos((x / size.width) * 5.0 - t * 0.8) * 60 +
          math.sin((x / size.width) * 3.0 + t * 0.5) * 30;
      path3.lineTo(x, yBase3 + wave);
    }
    path3.lineTo(size.width, size.height);
    path3.lineTo(0, size.height);
    path3.close();

    final paint3 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          primary.withOpacity(0.09),
          secondary.withOpacity(0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant _ShaderSmokePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isGMode != isGMode;
  }
}
