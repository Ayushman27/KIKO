import 'dart:convert';
import 'package:flutter/material.dart';
import 'synapse_theme.dart';
import 'audio_eq_visualizer.dart';

/// Task Execution Status for Cognitive Thread Display
enum CognitionTaskStatus {
  idle,
  executing,
  completed,
  failed,
}

/// Model Cognition Metrics Panel
/// Shows Cognitive Thread ID, Current Task Being Performed,
/// Live Execution & Completion Status, and Spectral Sparkline.
class CognitionMetricsCard extends StatelessWidget {
  final bool isGMode;
  final String? threadId;
  final String? taskName;
  final CognitionTaskStatus status;
  final String? statusMessage;
  final String? activeUrl;
  final List<String>? sources;
  final String? screenshotB64;
  final VoidCallback? onStopTask;

  const CognitionMetricsCard({
    super.key,
    required this.isGMode,
    this.threadId,
    this.taskName,
    this.status = CognitionTaskStatus.idle,
    this.statusMessage,
    this.activeUrl,
    this.sources,
    this.screenshotB64,
    this.onStopTask,
  });

  @override
  Widget build(BuildContext context) {
    final accent = SynapseTokens.primaryColor(isGMode);

    Color statusColor;
    Color statusBg;
    String statusBadgeText;
    IconData statusIcon;

    switch (status) {
      case CognitionTaskStatus.executing:
        statusColor = const Color(0xFFFFB800); // Amber
        statusBg = const Color(0xFFFFB800).withOpacity(0.14);
        statusBadgeText = 'PERFORMING TASK';
        statusIcon = Icons.sync;
        break;
      case CognitionTaskStatus.completed:
        statusColor = const Color(0xFF00E676); // Vivid Emerald Green
        statusBg = const Color(0xFF00E676).withOpacity(0.14);
        statusBadgeText = 'SUCCESSFULLY COMPLETED';
        statusIcon = Icons.check_circle_outline;
        break;
      case CognitionTaskStatus.failed:
        statusColor = const Color(0xFFFF5252); // Vivid Red
        statusBg = const Color(0xFFFF5252).withOpacity(0.14);
        statusBadgeText = 'TASK FAILED';
        statusIcon = Icons.error_outline;
        break;
      case CognitionTaskStatus.idle:
      default:
        statusColor = accent;
        statusBg = accent.withOpacity(0.12);
        statusBadgeText = 'STANDBY // READY';
        statusIcon = Icons.radio_button_checked;
        break;
    }

    final hasTask = taskName != null && taskName!.trim().isNotEmpty;
    final displayTaskTitle = hasTask ? taskName!.trim() : 'Awaiting Instruction';

    String resolvedSubtitle;
    if (statusMessage != null && statusMessage!.trim().isNotEmpty) {
      resolvedSubtitle = statusMessage!.trim();
    } else {
      switch (status) {
        case CognitionTaskStatus.executing:
          resolvedSubtitle = 'Dispatched to Windows PC • Executing in real-time...';
          break;
        case CognitionTaskStatus.completed:
          resolvedSubtitle = 'Executed and finished successfully on Windows PC.';
          break;
        case CognitionTaskStatus.failed:
          resolvedSubtitle = 'Execution interrupted or encountered an error.';
          break;
        case CognitionTaskStatus.idle:
        default:
          resolvedSubtitle = isGMode
              ? 'Hyper-velocity engine online. Say "Kiko" or type instruction.'
              : 'Analytical matrix online. Say "Kiko" or type instruction.';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: SynapseTokens.surfaceLowest.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: status == CognitionTaskStatus.executing
              ? statusColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
          ),
          if (status == CognitionTaskStatus.executing)
            BoxShadow(
              color: statusColor.withOpacity(0.15),
              blurRadius: 18,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header: Cognitive Thread Title + PID ──────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'COGNITIVE THREAD',
                style: TextStyle(
                  color: SynapseTokens.outline,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                threadId ?? 'PID #904-SYN',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Status Badge & Action Controls (Stop Button) ───────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 13),
                    const SizedBox(width: 6),
                    Text(
                      statusBadgeText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              // Stop Button when task is running
              if (status == CognitionTaskStatus.executing && onStopTask != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onStopTask,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF2A2A).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF2A2A).withOpacity(0.6), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.stop_rounded, color: Color(0xFFFF4D4D), size: 14),
                        SizedBox(width: 4),
                        Text(
                          'STOP',
                          style: TextStyle(
                            color: Color(0xFFFF4D4D),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // ── Performing Task Display ───────────────────────────────
          Text(
            displayTaskTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SynapseTokens.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),

          // ── Live Browser URL Pill (if available) ─────────────────
          if (activeUrl != null && activeUrl!.isNotEmpty && activeUrl != 'about:blank') ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withOpacity(0.3), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, color: accent, size: 11),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      activeUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 4),

          // ── Subtitle / Detailed Status ────────────────────────────
          Text(
            resolvedSubtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: SynapseTokens.onSurfaceVariant.withOpacity(0.85),
              fontSize: 12,
              height: 1.35,
            ),
          ),

          // ── Visited Genuine Sources (if available) ───────────────
          if (sources != null && sources!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: sources!.take(3).map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link, color: SynapseTokens.outline, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        Uri.tryParse(s)?.host ?? s,
                        style: const TextStyle(
                          color: SynapseTokens.onSurfaceVariant,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          // ── Screenshot Preview Thumbnail (if available) ───────────
          if (screenshotB64 != null && screenshotB64!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 80,
                width: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: accent.withOpacity(0.4), width: 1),
                ),
                child: Image.memory(
                  base64Decode(screenshotB64!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Spectral Density Waveform ─────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SPECTRAL DENSITY',
                style: TextStyle(
                  color: SynapseTokens.outline,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                status == CognitionTaskStatus.executing
                    ? 'PROCESSING CADENCE'
                    : '18.4 kHz (OPTIMAL)',
                style: TextStyle(
                  color: status == CognitionTaskStatus.executing ? statusColor : accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SpectralSparkline(
            isGMode: isGMode,
            height: 32,
          ),
        ],
      ),
    );
  }
}
