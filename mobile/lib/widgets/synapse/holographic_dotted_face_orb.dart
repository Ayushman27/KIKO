import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'synapse_theme.dart';

/// Holographic Dotted Face Synthesizer Orb
/// Complete reproduction of the animated holographic dotted wireframe face
/// with revolving orbit ring, pulsing halo, scanning laser beam, and articulating jaw cadence.
class HolographicDottedFaceOrb extends StatefulWidget {
  final bool isGMode;
  final bool isSpeaking;
  final double size;
  final VoidCallback? onTap;

  const HolographicDottedFaceOrb({
    super.key,
    required this.isGMode,
    this.isSpeaking = true,
    this.size = 180.0,
    this.onTap,
  });

  @override
  State<HolographicDottedFaceOrb> createState() => _HolographicDottedFaceOrbState();
}

class _HolographicDottedFaceOrbState extends State<HolographicDottedFaceOrb>
    with TickerProviderStateMixin {
  late AnimationController _orbitController;
  late AnimationController _scanController;
  late AnimationController _pulseController;
  late AnimationController _cadenceController;

  @override
  void initState() {
    super.initState();
    // Orbit rotation (24s cycle)
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();

    // Laser scan sweep (3.5s cycle)
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);

    // Idle ocular pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Phonetic speech cadence (rapid articulatory micro-movements)
    _cadenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _scanController.dispose();
    _pulseController.dispose();
    _cadenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);
    final glow = SynapseTokens.glowColor(widget.isGMode);

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _orbitController,
            _scanController,
            _pulseController,
            _cadenceController,
          ]),
          builder: (context, _) {
            // Speech cadence modulation
            final cadenceVal = widget.isSpeaking ? _cadenceController.value : 0.0;
            final jawOffset = widget.isSpeaking
                ? (math.sin(cadenceVal * math.pi) * 4.5 + math.cos(_scanController.value * 12.0) * 1.5).clamp(0.0, 6.0)
                : 0.0;
            final mouthHeight = widget.isSpeaking
                ? (1.0 + cadenceVal * 3.2).clamp(1.0, 4.2)
                : 1.0;
            final haloScale = widget.isSpeaking
                ? 1.0 + (cadenceVal * 0.12)
                : 1.0 + (_pulseController.value * 0.04);

            return Stack(
              alignment: Alignment.center,
              children: [
                // 1. Pulsing Audio Waveform Halo
                Transform.scale(
                  scale: haloScale,
                  child: Container(
                    width: widget.size * 0.88,
                    height: widget.size * 0.88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(widget.isSpeaking ? 0.14 : 0.06),
                      boxShadow: [
                        BoxShadow(
                          color: glow.withOpacity(widget.isSpeaking ? 0.35 : 0.15),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Revolving Orbit Ring with satellite node
                Transform.rotate(
                  angle: _orbitController.value * 2 * math.pi,
                  child: Container(
                    width: widget.size * 0.98,
                    height: widget.size * 0.98,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withOpacity(0.28),
                        width: 1.2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                              boxShadow: [
                                BoxShadow(
                                  color: accent,
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Central Glass Core with Dotted Face Hologram
                Container(
                  width: widget.size * 0.78,
                  height: widget.size * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0B0E13).withOpacity(0.92),
                    border: Border.all(
                      color: accent.withOpacity(0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.8),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: glow.withOpacity(0.25),
                        blurRadius: 18,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Dotted Face Matrix Painter
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DottedFacePainter(
                            accent: accent,
                            eyePulse: _pulseController.value,
                            jawOffset: jawOffset,
                            mouthHeight: mouthHeight,
                          ),
                        ),
                      ),

                      // Scanning Laser Sweep Beam
                      Positioned(
                        top: _scanController.value * (widget.size * 0.78),
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                accent.withOpacity(0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DottedFacePainter extends CustomPainter {
  final Color accent;
  final double eyePulse;
  final double jawOffset;
  final double mouthHeight;

  _DottedFacePainter({
    required this.accent,
    required this.eyePulse,
    required this.jawOffset,
    required this.mouthHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinate scale: original SVG is 100x100
    final scale = size.width / 100.0;

    final dotPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    final dimDotPaint = Paint()
      ..color = accent.withOpacity(0.65)
      ..style = PaintingStyle.fill;

    final eyeGlowPaint = Paint()
      ..color = accent.withOpacity(0.4 + eyePulse * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    void drawDot(double x, double y, double r, [Paint? p]) {
      canvas.drawCircle(Offset(x * scale, y * scale), r * scale, p ?? dotPaint);
    }

    // Forehead array
    drawDot(34, 24, 1.2);
    drawDot(42, 21, 1.3);
    drawDot(50, 20, 1.4);
    drawDot(58, 21, 1.3);
    drawDot(66, 24, 1.2);

    // Brow row
    drawDot(30, 32, 1.3);
    drawDot(37, 30, 1.5);
    drawDot(44, 30, 1.4);
    drawDot(56, 30, 1.4);
    drawDot(63, 30, 1.5);
    drawDot(70, 32, 1.3);

    // Ocular points (Eyes)
    // Left eye
    final eyeR = 2.0 + eyePulse * 0.35;
    canvas.drawCircle(Offset(38 * scale, 40 * scale), (eyeR + 1.2) * scale, eyeGlowPaint);
    drawDot(38, 40, eyeR);
    drawDot(34, 40, 1.0, dimDotPaint);
    drawDot(42, 40, 1.0, dimDotPaint);

    // Right eye
    canvas.drawCircle(Offset(62 * scale, 40 * scale), (eyeR + 1.2) * scale, eyeGlowPaint);
    drawDot(62, 40, eyeR);
    drawDot(58, 40, 1.0, dimDotPaint);
    drawDot(66, 40, 1.0, dimDotPaint);

    // Nasal bridge nodes
    drawDot(50, 38, 1.1, dimDotPaint);
    drawDot(50, 44, 1.2, dimDotPaint);
    drawDot(50, 50, 1.4, dimDotPaint);
    drawDot(46, 54, 1.0, dimDotPaint);
    drawDot(54, 54, 1.0, dimDotPaint);

    // Cheekbones
    drawDot(26, 46, 1.1, dimDotPaint);
    drawDot(28, 54, 1.2, dimDotPaint);
    drawDot(74, 46, 1.1, dimDotPaint);
    drawDot(72, 54, 1.2, dimDotPaint);

    // Upper Lip
    drawDot(44, 62, 1.3);
    drawDot(50, 61, 1.6);
    drawDot(56, 62, 1.3);

    // Articulating Jaw & Mouth group (offset by jawOffset)
    final jY = jawOffset * 0.8;

    // Mouth void aperture
    final mouthRect = Rect.fromCenter(
      center: Offset(50 * scale, (65 + jY * 0.5) * scale),
      width: 7.0 * scale,
      height: (mouthHeight * 2.0) * scale,
    );
    canvas.drawOval(
      mouthRect,
      Paint()
        ..color = accent.withOpacity(0.35 + (jawOffset / 12.0).clamp(0.0, 0.45))
        ..style = PaintingStyle.fill,
    );

    // Lower Lip
    drawDot(50, 68 + jY * 0.7, 1.5);
    drawDot(45, 67 + jY * 0.7, 1.2);
    drawDot(55, 67 + jY * 0.7, 1.2);

    // Jaw Contours & Chin Apex
    drawDot(34, 64 + jY * 0.5, 1.2, dimDotPaint);
    drawDot(38, 72 + jY * 0.7, 1.3, dimDotPaint);
    drawDot(44, 78 + jY, 1.4);
    // Chin Apex with prominent beacon
    drawDot(50, 80 + jY, 2.0);
    drawDot(56, 78 + jY, 1.4);
    drawDot(62, 72 + jY * 0.7, 1.3, dimDotPaint);
    drawDot(66, 64 + jY * 0.5, 1.2, dimDotPaint);
  }

  @override
  bool shouldRepaint(covariant _DottedFacePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.eyePulse != eyePulse ||
        oldDelegate.jawOffset != jawOffset ||
        oldDelegate.mouthHeight != mouthHeight;
  }
}
