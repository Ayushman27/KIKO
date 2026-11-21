import 'package:flutter/material.dart';
import 'synapse_theme.dart';

/// Synapse Command Deck & Speech Bar
/// Features Push-to-Talk mic sphere, terminal prompt field (>_),
/// synthesize button, and real-time telemetry status footer.
class SynapseCommandDeck extends StatefulWidget {
  final bool isGMode;
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onPttStart;
  final VoidCallback? onPttEnd;
  final bool isPttActive;
  final bool isAutoMic;
  final VoidCallback? onToggleAutoMic;

  const SynapseCommandDeck({
    super.key,
    required this.isGMode,
    required this.controller,
    this.onSubmitted,
    this.onPttStart,
    this.onPttEnd,
    this.isPttActive = false,
    this.isAutoMic = true,
    this.onToggleAutoMic,
  });

  @override
  State<SynapseCommandDeck> createState() => _SynapseCommandDeckState();
}

class _SynapseCommandDeckState extends State<SynapseCommandDeck> {
  final FocusNode _focusNode = FocusNode();

  void _handleSubmit() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty && widget.onSubmitted != null) {
      widget.onSubmitted!(text);
      widget.controller.clear();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(widget.isGMode);
    final glow = SynapseTokens.glowColor(widget.isGMode);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glass Command Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: SynapseTokens.surfaceLowest.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? accent.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
              if (_focusNode.hasFocus || widget.isPttActive)
                BoxShadow(
                  color: glow.withOpacity(0.2),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Row(
            children: [
              // Tap-to-Talk Mic Button
              GestureDetector(
                onTap: () => widget.onPttStart?.call(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: widget.isPttActive ? 86 : 46,
                  height: 46,
                  padding: EdgeInsets.symmetric(horizontal: widget.isPttActive ? 10 : 0),
                  decoration: BoxDecoration(
                    color: widget.isPttActive
                        ? const Color(0xFFFF2A2A)
                        : accent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isPttActive ? const Color(0xFFFF2A2A) : glow)
                            .withOpacity(widget.isPttActive ? 0.75 : 0.3),
                        blurRadius: widget.isPttActive ? 20 : 10,
                        spreadRadius: widget.isPttActive ? 3 : 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: widget.isPttActive
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.fiber_manual_record,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'REC',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          )
                        : Icon(
                            Icons.mic,
                            color: widget.isGMode
                                ? const Color(0xFF541100)
                                : const Color(0xFF00363A),
                            size: 22,
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Terminal Prompt Glyphs '>_'
              Text(
                '>_',
                style: TextStyle(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),

              const SizedBox(width: 10),

              // Prompt Input Field
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    color: SynapseTokens.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.isPttActive
                        ? '🔴 [REC] Listening for instruction...'
                        : (widget.isAutoMic
                            ? '🎙️ Say "Kiko" or type your instruction...'
                            : 'Prompt engine or tap mic...'),
                    hintStyle: TextStyle(
                      color: widget.isPttActive
                          ? const Color(0xFFFF6E6E)
                          : (widget.isAutoMic
                              ? accent.withOpacity(0.9)
                              : SynapseTokens.outline.withOpacity(0.8)),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),

              const SizedBox(width: 6),

              // Synthesize Action Button
              InkWell(
                onTap: _handleSubmit,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: SynapseTokens.surfaceContainer.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Synthesize',
                        style: TextStyle(
                          color: SynapseTokens.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_upward,
                        color: accent,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Telemetry Status Bar Under Input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Auto-Mic Toggle Pill
                InkWell(
                  onTap: widget.onToggleAutoMic,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.isAutoMic
                          ? const Color(0xFF00E676).withOpacity(0.12)
                          : SynapseTokens.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.isAutoMic
                            ? const Color(0xFF00E676).withOpacity(0.4)
                            : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isAutoMic ? const Color(0xFF00E676) : SynapseTokens.outline,
                            boxShadow: widget.isAutoMic
                                ? [
                                    const BoxShadow(
                                      color: Color(0xFF00E676),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.isAutoMic ? 'WAKE-WORD: "KIKO"' : 'WAKE-WORD: OFF',
                          style: TextStyle(
                            color: widget.isAutoMic ? const Color(0xFF00E676) : SynapseTokens.outline,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: [
                      BoxShadow(
                        color: accent,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.isGMode
                      ? 'TEMP: 0.88'
                      : 'TEMP: 0.20',
                  style: TextStyle(
                    color: SynapseTokens.outline,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '14ms REALTIME',
                  style: TextStyle(
                    color: SynapseTokens.outline,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                // Secure Enclave
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SECURE ENCLAVE',
                      style: TextStyle(
                        color: SynapseTokens.outline,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.verified_user,
                      color: accent,
                      size: 11,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
