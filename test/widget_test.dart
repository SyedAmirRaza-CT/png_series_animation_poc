import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:png_series_animation_poc/png_series_animator/png_series_animator.dart';

void main() {
  testWidgets('PngSeriesAnimator once behavior calls onCompleted', (WidgetTester tester) async {
    bool completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PngSeriesAnimator(
            imagePaths: const ['assets/1/10001.png', 'assets/1/10002.png'],
            duration: const Duration(milliseconds: 200),
            repeat: false,
            isPlaying: true,
            onCompleted: () {
              completed = true;
            },
          ),
        ),
      ),
    );

    // Initial frame
    await tester.pump();
    expect(completed, isFalse);

    // Let the animation complete (duration is 200ms)
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(completed, isTrue);
  });
}
