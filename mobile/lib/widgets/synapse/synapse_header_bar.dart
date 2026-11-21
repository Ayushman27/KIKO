import 'package:flutter/material.dart';
import 'synapse_theme.dart';

/// Top Utility & Mode Control Bar
/// Contains the Neural Sync pulsing beacon dot, the segmented Alpha/G-Mode switcher,
/// and the real-time audio / mic diagnostic button.
class SynapseHeaderBar extends StatelessWidget {
  final bool isGMode;
  final ValueChanged<bool> onModeChanged;
  final bool isAudioEngaged;
  final VoidCallback? onToggleAudio;

  const SynapseHeaderBar({
    super.key,
    required this.isGMode,
    required this.onModeChanged,
    this.isAudioEngaged = true,
    this.onToggleAudio,
  });

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(isGMode);
    final glow = SynapseTokens.glowColor(isGMode);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Neural State Indicator Capsule
            Flexible(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 10 : 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: SynapseTokens.surfaceContainer.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing Beacon
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withOpacity(0.35),
                          ),
                        ),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [
                              BoxShadow(
                                color: accent,
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isCompact
                            ? (isGMode ? 'G-MODE ACTIVE' : 'ALPHA MODE')
                            : (isGMode
                                ? 'OVERCLOCK // G-MODE OVERDRIVE'
                                : 'NEURAL SYNC // ALPHA MODE'),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          color: SynapseTokens.onSurface,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Right: Segmented Mode Switcher & Mic Stream Toggle
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Segmented Mode Switcher Pill
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: SynapseTokens.surfaceLowest.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modeButton(
                        label: isCompact ? 'ALPHA' : 'ALPHA MODE',
                        icon: Icons.psychology,
                        isSelected: !isGMode,
                        activeColor: SynapseTokens.alphaPrimaryContainer,
                        activeTextColor: const Color(0xFF00363A),
                        isCompact: isCompact,
                        onTap: () => onModeChanged(false),
                      ),
                      _modeButton(
                        label: isCompact ? 'G-MODE' : 'G MODE OVERDRIVE',
                        icon: Icons.bolt,
                        isSelected: isGMode,
                        activeColor: SynapseTokens.gPrimaryContainer,
                        activeTextColor: const Color(0xFF541100),
                        isCompact: isCompact,
                        onTap: () => onModeChanged(true),
                      ),
                    ],
                  ),
                ),

                SizedBox(width: isCompact ? 6 : 10),

                // Audio Stream Toggle Button
                InkWell(
                  onTap: onToggleAudio,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: isCompact ? 34 : 38,
                    height: isCompact ? 34 : 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SynapseTokens.surfaceContainer,
                      border: Border.all(
                        color: isAudioEngaged
                            ? accent.withOpacity(0.4)
                            : Colors.white.withOpacity(0.08),
                      ),
                      boxShadow: isAudioEngaged
                          ? [
                              BoxShadow(
                                color: glow.withOpacity(0.2),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isAudioEngaged ? Icons.mic : Icons.mic_off,
                      color: isAudioEngaged ? accent : SynapseTokens.outline,
                      size: isCompact ? 16 : 18,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required Color activeTextColor,
    required VoidCallback onTap,
    bool isCompact = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 14,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.35),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? activeTextColor : SynapseTokens.outline,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeTextColor : SynapseTokens.onSurfaceVariant,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
