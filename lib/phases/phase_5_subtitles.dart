import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_manager.dart';

class Phase5SubtitlesDemo extends StatefulWidget {
  const Phase5SubtitlesDemo({super.key});

  @override
  State<Phase5SubtitlesDemo> createState() => _Phase5SubtitlesDemoState();
}

class _Phase5SubtitlesDemoState extends State<Phase5SubtitlesDemo> with TickerProviderStateMixin {
  final _service = AssetBundleManager();
  final _audioPlayer = AudioPlayer();
  final _pngController = PngSeriesController();
  final _subtitleController = PngSubtitleController();
  
  final String _bundleId = 'subtitle_bundle_v1';
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

  Future<void> _loadFallbackSubtitles() async {
    try {
      debugPrint('Phase 5: Loading fallback subtitles from assets...');
      final String response = await rootBundle.loadString('assets/metadata/subtitles.json');
      final data = json.decode(response);
      _subtitleController.updateData(data, initialLanguage: 'en');
    } catch (e) {
      debugPrint('Error loading fallback subtitles: $e');
    }
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
      final subtitleFiles = await _service.getAllSubtitles(_bundleId);
      
      // 1. Try to load subtitles from bundle
      if (subtitleFiles.isNotEmpty) {
        try {
          debugPrint('Phase 5: Loading subtitles from bundle: ${subtitleFiles.first}');
          final data = await _service.getJsonFile(_bundleId, p.relative(subtitleFiles.first, from: await _service.getBundlePath(_bundleId)).replaceFirst('files/', ''));
          _subtitleController.updateData(data, initialLanguage: 'en');
        } catch (e) {
          debugPrint('Error loading bundle subtitles: $e');
          await _loadFallbackSubtitles();
        }
      } else {
        await _loadFallbackSubtitles();
      }

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
    } else {
      // If not installed, load fallback immediately so they are ready
      await _loadFallbackSubtitles();
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
    _subtitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 5: Subtitles & Highlights')),
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
            Text('Preparing Synced Experience...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PngSeriesAnimator.videoPlayer(
            imagePaths: _imagePaths,
            controller: _pngController,
            duration: _totalDuration,
            isPlaying: _isPlaying,
            subtitleController: _subtitleController,
            fit: BoxFit.contain,
            onPlayStateChanged: _handleSyncPlayPause,
            onSeek: _handleSyncSeek,
            subtitleBuilder: (context, segment, currentTime) {
              if (segment == null) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: segment.words.map((word) {
                      final bool isCurrent = currentTime >= word.start && currentTime <= word.end;
                      final bool isPast = currentTime > word.end;

                      return TextSpan(
                        text: "${word.text} ",
                        style: TextStyle(
                          color: isCurrent ? Colors.yellowAccent : (isPast ? Colors.white : Colors.white38),
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: isCurrent ? 18 : 18,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildTranscript(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            children: [
              Text(
                _audioPath != null 
                  ? 'Audio: ${p.basename(_audioPath!)} (Bundle)' 
                  : 'Audio: $_fallbackAudioAsset (Local Asset)',
                style: const TextStyle(color: Colors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
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
                label: const Text('Reset Bundle'),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.redAccent),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTranscript() {
    return ListenableBuilder(
      listenable: Listenable.merge([_pngController, _subtitleController]),
      builder: (context, child) {
        final double currentTime = _pngController.value * _totalDuration.inSeconds;
        final segments = _subtitleController.currentSegments;

        if (segments.isEmpty) {
          return const Center(child: Text('No transcript available for this language.'));
        }

        return Wrap(
          spacing: 4,
          runSpacing: 8,
          children: segments.expand((segment) {
            return segment.words.map((word) {
              final bool isCurrent = currentTime >= word.start && currentTime <= word.end;
              final bool isPast = currentTime > word.end;

              Color textColor = Colors.white38;
              FontWeight fontWeight = FontWeight.normal;
              double fontSize = 16;

              if (isCurrent) {
                textColor = Colors.yellowAccent;
                fontWeight = FontWeight.bold;
                fontSize = 18;
              } else if (isPast) {
                textColor = Colors.white;
                fontWeight = FontWeight.w500;
              }

              return AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: textColor,
                  fontWeight: fontWeight,
                  fontSize: fontSize,
                ),
                child: Text(word.text),
              );
            });
          }).toList(),
        );
      },
    );
  }

  Widget _buildDownloadPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.subtitles, size: 80, color: Colors.cyan),
        const SizedBox(height: 20),
        const Text(
          'Phase 5: Subtitles Demo',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
          child: Text(
            'This phase adds multi-language subtitles with word-level highlighting and a custom options menu.',
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
            child: const Text('Download Phase 5 Bundle'),
          ),
      ],
    );
  }
}
