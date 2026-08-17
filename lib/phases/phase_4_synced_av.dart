import 'dart:async';
import 'package:flutter/material.dart';

import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_service.dart';

class SyncedPlaybackDemo extends StatefulWidget {
  const SyncedPlaybackDemo({super.key});

  @override
  State<SyncedPlaybackDemo> createState() => _SyncedPlaybackDemoState();
}

class _SyncedPlaybackDemoState extends State<SyncedPlaybackDemo> with TickerProviderStateMixin {
  final _service = AssetBundleService();
  final _pngController = PngSeriesController();

  final String _bundleId = 'synced_bundle_v1';
  final String _zipUrl = 'https://github.com/ultralytics/yolov5/releases/download/v1.0/coco128.zip';
  final String _fallbackAudioAsset = 'audio/default_sync.mp3';

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isInstalled = false;

  List<String> _imagePaths = [];
  String? _audioPath;
  
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final installed = await _service.isBundleDownloaded(_bundleId);
    if (installed) {
      final images = await _service.getAllImages(_bundleId);
      final audioFiles = await _service.getAllAudio(_bundleId);

      setState(() {
        _isInstalled = true;
        _imagePaths = images;
        if (audioFiles.isNotEmpty) {
          _audioPath = audioFiles.first;
        } else {
          _audioPath = _fallbackAudioAsset;
        }
        _isReady = true;
        
        // Autoplay once ready
        _pngController.play();
      });
    }
  }

  Future<void> _handleDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      await _service.downloadBundle(
        bundleId: _bundleId,
        url: _zipUrl,
        version: 1,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = total > 0 ? received / total : -1.0;
            });
          }
        },
      );
      await _checkStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  void dispose() {
    _pngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synced AV Playback')),
      body: Center(
        child: _isInstalled
          ? _buildPlayer()
          : _buildDownloadPrompt(),
      ),
    );
  }

  Widget _buildPlayer() {
    if (!_isReady) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: PngSeriesAnimator.videoPlayer(
            imagePaths: _imagePaths,
            controller: _pngController,
            audioPath: _audioPath,
            fit: BoxFit.contain,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                _audioPath != null && p.isAbsolute(_audioPath!)
                  ? 'Audio: ${p.basename(_audioPath!)} (Bundle)'
                  : 'Audio: $_fallbackAudioAsset (Local Asset)',
                style: const TextStyle(color: Colors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  _pngController.pause();
                  await _service.deleteBundle(_bundleId);
                  setState(() {
                     _isInstalled = false;
                     _isReady = false;
                  });
                },
                icon: const Icon(Icons.delete),
                label: const Text('Delete and Try Again'),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.redAccent),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sync, size: 80, color: Colors.cyan),
        const SizedBox(height: 20),
        const Text(
          'Synced Phase 4 Demo',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
          child: Text(
            'This will download a bundle containing images and audio, then play them in perfect synchronization.',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 30),
        if (_isDownloading) ...[
          SizedBox(
            width: 250,
            child: LinearProgressIndicator(value: _downloadProgress < 0 ? null : _downloadProgress),
          ),
          const SizedBox(height: 10),
          Text(_downloadProgress < 0 ? 'Downloading...' : '${(_downloadProgress * 100).toInt()}%'),
        ] else
          ElevatedButton(
            onPressed: _handleDownload,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            ),
            child: const Text('Download Sync Bundle'),
          ),
      ],
    );
  }
}
