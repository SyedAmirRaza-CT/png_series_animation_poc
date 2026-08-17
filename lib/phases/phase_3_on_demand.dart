import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_service.dart';

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

  bool _isDownloading = false;
  double _progress = 0;
  bool _isInstalled = false;
  int _installedVersion = 0;
  int _targetVersion = 1;
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
      final version = await _service.getInstalledVersion(_bundleId);
      
      setState(() {
        _isInstalled = true;
        _installedVersion = version;
        _totalFiles = allEntities.length;
        _localImagePaths = images;
        if (_targetVersion < _installedVersion) {
          _targetVersion = _installedVersion;
        }
      });
    } else {
      setState(() {
        _isInstalled = false;
        _installedVersion = 0;
        _totalFiles = 0;
        _localImagePaths = [];
      });
    }
  }

  Future<void> _handleDownload({int? version}) async {
    final targetVer = version ?? _targetVersion;
    setState(() {
      _isDownloading = true;
      _progress = 0;
    });

    try {
      await _service.downloadBundle(
        bundleId: _bundleId,
        url: _zipUrl,
        version: targetVer,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              if (total > 0) {
                _progress = received / total;
              } else {
                _progress = -1.0; 
              }
            });
          }
        },
      );
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bundle v$targetVer installed successfully!')),
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
                key: ValueKey(_localImagePaths.length),
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
                    _isInstalled ? 'Status: INSTALLED (v$_installedVersion)' : 'Status: NOT DOWNLOADED',
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
              onPressed: () => _handleDownload(version: _targetVersion),
              icon: const Icon(Icons.download),
              label: Text('Download Bundle (v$_targetVersion)'),
            )
          else ...[
            if (_installedVersion < _targetVersion) ...[
              ElevatedButton.icon(
                onPressed: () => _handleDownload(version: _targetVersion),
                icon: const Icon(Icons.system_update),
                label: Text('Update Bundle to v$_targetVersion'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _handleDelete,
              icon: const Icon(Icons.delete, color: Colors.white),
              label: const Text('Delete Bundle'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Extracted Items: $_totalFiles', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _targetVersion++;
                    });
                  },
                  icon: const Icon(Icons.add_alert, size: 16),
                  label: const Text('Simulate New Version', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
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
