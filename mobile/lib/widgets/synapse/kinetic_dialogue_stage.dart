import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'synapse_theme.dart';
import 'audio_eq_visualizer.dart';

/// Kinetic Dialogue Stage
/// Frosted glass card with glowing top edge, typewriter streaming text,
/// animated 32-bar EQ spectrum, and interactive action chips.
class KineticDialogueStage extends StatefulWidget {
  final bool isGMode;
  final String text;
  final bool isStreaming;
  final bool isSpeaking;
  final bool isListening;
  final VoidCallback? onReplay;
  final VoidCallback? onBranch;
  final VoidCallback? onToggleMode;

  const KineticDialogueStage({
    super.key,
    required this.isGMode,
    required this.text,
    this.isStreaming = false,
    this.isSpeaking = true,
    this.isListening = false,
    this.onReplay,
    this.onBranch,
    this.onToggleMode,
  });

  @override
  State<KineticDialogueStage> createState() => _KineticDialogueStageState();
}

class _KineticDialogueStageState extends State<KineticDialogueStage> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);
    final glow = SynapseTokens.glowColor(widget.isGMode);

    return Container(
      decoration: BoxDecoration(
        color: SynapseTokens.surfaceLow.withOpacity(0.75),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(
          color: Colors.white.withOpacity(0.09),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: glow.withOpacity(0.08),
            blurRadius: 30,
            spreadRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Glowing Top Edge Accent Line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2.0,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    accent,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Metadata
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isListening ? Icons.mic : Icons.psychology,
                            color: widget.isListening ? const Color(0xFFFF3D00) : accent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.isListening
                                  ? '🔴 LIVE MIC STREAM'
                                  : (widget.isGMode
                                      ? 'VOLCANIC OVERDRIVE'
                                      : 'LIVE SYNTHESIS STREAM'),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: widget.isListening ? const Color(0xFFFF5252) : accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.isListening ? 'MIC: ' : 'CONF: ',
                          style: TextStyle(
                            color: SynapseTokens.onSurfaceVariant.withOpacity(0.7),
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          widget.isListening ? '16kHz' : '99.82%',
                          style: TextStyle(
                            color: widget.isListening ? const Color(0xFFFF5252) : SynapseTokens.onSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isListening ? const Color(0xFFFF3D00) : accent,
                            boxShadow: [
                              BoxShadow(
                                color: widget.isListening ? const Color(0xFFFF3D00) : accent,
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Main Kinetic Output Text
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 65),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.text,
                          style: TextStyle(
                            color: SynapseTokens.onSurface,
                            fontSize: 16,
                            height: 1.55,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (widget.isStreaming || widget.isSpeaking || widget.isListening)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              margin: const EdgeInsets.only(left: 4),
                              width: 3,
                              height: 18,
                              decoration: BoxDecoration(
                                color: widget.isListening ? const Color(0xFFFF3D00) : accent,
                                borderRadius: BorderRadius.circular(1),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.isListening ? const Color(0xFFFF3D00) : accent,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Audio Waveform Visualization Header & EQ Bar Array
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isListening ? Icons.mic : Icons.graphic_eq,
                            color: widget.isListening ? const Color(0xFFFF5252) : SynapseTokens.outline,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.isListening
                                  ? 'PC MIC STREAM'
                                  : (widget.isGMode
                                      ? 'SYNAPSE G-CORE TTS // 48kHz'
                                      : 'SYNAPSE NEURAL TTS // V4.8'),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: widget.isListening ? const Color(0xFFFF5252) : SynapseTokens.outline,
                                fontSize: 10,
                                fontFamily: 'monospace',
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isListening ? 'STREAMING...' : '00:04 / 00:08',
                      style: TextStyle(
                        color: widget.isListening ? const Color(0xFFFF5252) : SynapseTokens.onSurfaceVariant,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 32 Animated EQ Bars
                AudioEqVisualizer(
                  isGMode: widget.isGMode,
                  isSpeaking: widget.isSpeaking,
                  isListening: widget.isListening,
                  barCount: 32,
                  height: 26,
                ),

                const SizedBox(height: 16),

                // Quick Action Chips Row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildChip(
                      icon: Icons.replay,
                      label: 'Play Audio Again',
                      onTap: widget.onReplay,
                    ),
                    _buildChip(
                      icon: _copied ? Icons.check : Icons.content_copy,
                      label: _copied ? 'Copied to Enclave!' : 'Copy Response',
                      highlighted: _copied,
                      onTap: _copyToClipboard,
                    ),
                    _buildChip(
                      icon: Icons.fork_right,
                      label: 'Branch Thought',
                      onTap: widget.onBranch,
                    ),
                    _buildChip(
                      icon: Icons.fast_forward,
                      label: widget.isGMode
                          ? 'Return to Alpha Mode'
                          : 'Switch to G-Mode Overdrive',
                      isAccent: true,
                      onTap: widget.onToggleMode,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    bool highlighted = false,
    bool isAccent = false,
    VoidCallback? onTap,
  }) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);
    final bg = isAccent
        ? accent.withOpacity(0.14)
        : SynapseTokens.surfaceContainer.withOpacity(0.8);
    final border = isAccent
        ? accent.withOpacity(0.4)
        : (highlighted ? SynapseTokens.success.withOpacity(0.5) : Colors.white.withOpacity(0.08));
    final textColor = isAccent
        ? accent
        : (highlighted ? SynapseTokens.success : SynapseTokens.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: isAccent ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
