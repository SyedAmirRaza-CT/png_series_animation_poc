import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_manager.dart';

class SyncedPlaybackDemo extends StatefulWidget {
  const SyncedPlaybackDemo({super.key});

  @override
  State<SyncedPlaybackDemo> createState() => _SyncedPlaybackDemoState();
}

class _SyncedPlaybackDemoState extends State<SyncedPlaybackDemo> with TickerProviderStateMixin {
  final _service = AssetBundleManager();
  final _audioPlayer = AudioPlayer();

  final _pngController = PngSeriesController();

  final String _bundleId = 'synced_bundle_v1';
  final String _zipUrl = 'https://github.com/ultralytics/yolov5/releases/download/v1.0/coco128.zip';
  final String _fallbackAudioAsset = 'audio/default_sync.mp3';

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isInstalled = false;

  List<String> _imagePaths = [];
  String? _audioPath;
  Duration _totalDuration = const Duration(seconds: 10);

  bool _isReady = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _setupAudioListeners();
  }

  void _setupAudioListeners() {
    _audioPlayer.onPositionChanged.listen((pos) {
      if (_isPlaying && mounted) {
        final double value = pos.inMilliseconds / _totalDuration.inMilliseconds;
        _pngController.seekTo(value.clamp(0.0, 1.0));
      }
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() {
          _totalDuration = dur;
          _isReady = true;
        });

        // Phase 4 Autoplay using the controller
        if (_isInstalled && !_isPlaying) {
          _pngController.play();
        }
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
       if (mounted) {
         _pngController.seekTo(0.0);
         _audioPlayer.seek(Duration.zero);
       }
    });
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
          _prepareAudio();
        } else {
          _audioPath = null;
          _prepareAudio();
        }

      });
    }
  }

  Future<void> _prepareAudio() async {
    try {
      if (_audioPath != null) {
        await _audioPlayer.setSource(DeviceFileSource(_audioPath!));
      } else {
        await _audioPlayer.setSource(AssetSource(_fallbackAudioAsset));
      }
    } catch (e) {
      debugPrint('Error preparing audio: $e');
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

  Future<void> _handleSyncPlayPause(bool playing) async {
    debugPrint('Phase 4: Sync Play/Pause called with: $playing');
    if (playing) {
      if (_audioPath != null) {
        await _audioPlayer.play(DeviceFileSource(_audioPath!));
      } else {
        await _audioPlayer.play(AssetSource(_fallbackAudioAsset));
      }
    } else {
      await _audioPlayer.pause();
    }
  }

  Future<void> _handleSyncSeek(double value) async {
    final targetMs = (value * _totalDuration.inMilliseconds).toInt();
    await _audioPlayer.seek(Duration(milliseconds: targetMs));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
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
            Text('Initializing Audio Sync...'),
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
            duration: _totalDuration,
            isPlaying: _isPlaying,
            fit: BoxFit.contain,
            onPlayStateChanged: _handleSyncPlayPause,
            onSeek: _handleSyncSeek,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                _audioPath != null
                  ? 'Audio: ${p.basename(_audioPath!)} (Bundle)'
                  : 'Audio: $_fallbackAudioAsset (Local Asset)',
                style: const TextStyle(color: Colors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  await _audioPlayer.stop();
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
