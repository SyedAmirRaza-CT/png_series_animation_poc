import 'package:flutter/material.dart';
import 'png_series_animator.dart';
import 'utils/image_cache_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PNG Series Animation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PNG Series Animator'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MenuButton(
              title: 'Local Asset Series',
              subtitle: 'Animation from bundled PNGs',
              icon: Icons.folder_open,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LocalAssetDemo()),
              ),
            ),
            const SizedBox(height: 20),
            _MenuButton(
              title: 'Network URL Series',
              subtitle: 'Animation with persistent caching',
              icon: Icons.cloud_download,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NetworkAssetDemo()),
              ),
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: () async {
                await ImageCacheManager().clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Persistent storage cleared')),
                  );
                }
              },
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              label: const Text('Clear Persistent Storage', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: Colors.cyan),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

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
