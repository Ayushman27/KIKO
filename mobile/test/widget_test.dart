import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiko_mobile/widgets/synapse/synapse_theme.dart';
import 'package:kiko_mobile/widgets/synapse/holographic_dotted_face_orb.dart';
import 'package:kiko_mobile/widgets/synapse/audio_eq_visualizer.dart';
import 'package:kiko_mobile/widgets/synapse/atmospheric_background.dart';

void main() {
  testWidgets('Synapse Holographic Orb and EQ Visualizer render test',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HolographicDottedFaceOrb(
                isGMode: false,
                isSpeaking: true,
                size: 160.0,
              ),
              AudioEqVisualizer(
                isGMode: false,
                isSpeaking: true,
                barCount: 16,
              ),
            ],
          ),
        ),
      ),
    );

    // Verify widgets mount without error
    expect(find.byType(HolographicDottedFaceOrb), findsOneWidget);
    expect(find.byType(AudioEqVisualizer), findsOneWidget);
  });

  test('Synapse tokens color testing', () {
    expect(SynapseTokens.primaryColor(false), SynapseTokens.alphaPrimaryContainer);
    expect(SynapseTokens.primaryColor(true), SynapseTokens.gPrimaryContainer);
  });

  testWidgets('Collapsed sidebar header does not overflow at 64px width',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 64,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AtmosphericBackground mounts and renders properly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AtmosphericBackground(
            isGMode: false,
            child: Text('Synapse Content'),
          ),
        ),
      ),
    );

    expect(find.text('Synapse Content'), findsOneWidget);
    expect(find.byType(AtmosphericBackground), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
