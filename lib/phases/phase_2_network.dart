import 'package:flutter/material.dart';
import '../png_series_animator/png_series_animator.dart';

class NetworkAssetDemo extends StatelessWidget {
  const NetworkAssetDemo({super.key});

  @override
  Widget build(BuildContext context) {
    // Using a more reliable set of placeholder images for the demo
    final List<String> networkImages = List.generate(
      30,
      (index) => 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${index + 71}.png',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Network Assets')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Fetching and caching network sequence...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Center(
              child: PngSeriesAnimator.videoPlayer(
                imagePaths: networkImages,
                audioPath: 'audio/default_sync.mp3',
                duration: const Duration(seconds: 10),
                heroTag: 'network_hero',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
