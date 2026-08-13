import 'package:flutter/material.dart';
import 'png_series_animator.dart';
import 'utils/image_cache_manager.dart';
import 'services/asset_bundle_service.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
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
              const SizedBox(height: 20),
              _MenuButton(
                title: 'On-Demand Asset Bundles',
                subtitle: 'Download and manage ZIP bundles',
                icon: Icons.inventory_2,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AssetBundleDemo()),
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

class AssetBundleDemo extends StatefulWidget {
  const AssetBundleDemo({super.key});

  @override
  State<AssetBundleDemo> createState() => _AssetBundleDemoState();
}

class _AssetBundleDemoState extends State<AssetBundleDemo> {
  final _service = AssetBundleService();
  final String _bundleId = 'verified_bundle_v1';
  
  // VERIFIED STABLE URL: This is a public GitHub Release Asset (Guaranteed no 401/403)
  // It provides Content-Length and contains a high-quality set of 128 images.
  final String _zipUrl = 'https://github.com/ultralytics/yolov5/releases/download/v1.0/coco128.zip';

  // ALTERNATIVE: Square Image Test Bundle
  // Use this for checking exact square aspect ratios (256x256 / 512x512)
  // final String _zipUrl = 'https://github.com/MathieuLoutre/square-images/archive/refs/heads/master.zip';
  
  bool _isDownloading = false;
  double _progress = 0;
  bool _isInstalled = false;
  List<String> _localImagePaths = [];
  int _totalFiles = 0;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final installed = await _service.isBundleDownloaded(_bundleId);
    if (installed) {
      final images = await _service.getAllImages(_bundleId);
      final allEntities = await _service.listFiles(_bundleId, '');
      setState(() {
        _isInstalled = true;
        _totalFiles = allEntities.length;
        _localImagePaths = images;
      });
    } else {
      setState(() {
        _isInstalled = false;
        _totalFiles = 0;
        _localImagePaths = [];
      });
    }
  }

  Future<void> _handleDownload() async {
    debugPrint('UI: Download button clicked');
    setState(() {
      _isDownloading = true;
      _progress = 0;
    });

    try {
      debugPrint('UI: Calling service.downloadBundle with URL: $_zipUrl');
      await _service.downloadBundle(
        bundleId: _bundleId,
        url: _zipUrl,
        version: 1,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              if (total > 0) {
                _progress = received / total;
              } else {
                // If total is unknown, we use a negative value to signal indeterminate state to UI
                _progress = -1.0; 
              }
            });
          }
        },
      );
      debugPrint('UI: Download and installation finished');
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bundle installed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _handleDelete() async {
    await _service.deleteBundle(_bundleId);
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asset Bundle Manager')),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          if (_localImagePaths.isNotEmpty)
            SizedBox(
              height: 300,
              child: PngSeriesAnimator.videoPlayer(
                key: ValueKey(_localImagePaths.length), // Rebuild when path list changes
                duration: const Duration(minutes: 1),
                imagePaths: _localImagePaths,
                fit: BoxFit.contain,
              ),
            ),
          const SizedBox(height: 10),
          Card(
            color: Colors.white.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Icon(Icons.archive, size: 48, color: Colors.cyan),
                  const SizedBox(height: 16),
                  Text(
                    'Bundle ID: $_bundleId',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isInstalled ? 'Status: INSTALLED' : 'Status: NOT DOWNLOADED',
                    style: TextStyle(
                      color: _isInstalled ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress < 0 ? null : _progress),
            const SizedBox(height: 8),
            Text(
              _progress < 0 
                ? 'Downloading... (Size unknown)' 
                : 'Downloading: ${(_progress * 100).toStringAsFixed(0)}%', 
              textAlign: TextAlign.center
            ),
          ] else if (!_isInstalled)
            ElevatedButton.icon(
              onPressed: _handleDownload,
              icon: const Icon(Icons.download),
              label: const Text('Download Bundle (v1)'),
            )
          else ...[
            ElevatedButton.icon(
              onPressed: _handleDelete,
              icon: const Icon(Icons.delete, color: Colors.white),
              label: const Text('Delete Bundle'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
            ),
            const SizedBox(height: 20),
            Text('Extracted Items: $_totalFiles', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_localImagePaths.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('No images found in bundle.'),
              ))
            else
              ..._localImagePaths.map((path) => ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(
                    File(path),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(p.basename(path)),
                subtitle: Text(path, style: const TextStyle(fontSize: 10)),
              )),
          ],
        ],
      ),
    );
  }
}
