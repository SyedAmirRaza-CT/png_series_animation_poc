import 'package:flutter/material.dart';
import '../png_series_animator/png_series_animator.dart';

class LocalAssetDemo extends StatelessWidget {
  const LocalAssetDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> images = List.generate(
      18,
      (index) => 'assets/1/${10001 + index}.png',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Local Assets')),
      body: Center(
        child: PngSeriesAnimator.videoPlayer(
          imagePaths: images,
          duration: const Duration(seconds: 2),
          heroTag: 'local_hero',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
