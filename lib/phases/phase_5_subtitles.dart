import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_service.dart';

class Phase5SubtitlesDemo extends StatefulWidget {
  const Phase5SubtitlesDemo({super.key});

  @override
  State<Phase5SubtitlesDemo> createState() => _Phase5SubtitlesDemoState();
}

class _Phase5SubtitlesDemoState extends State<Phase5SubtitlesDemo> with TickerProviderStateMixin {
  final _service = AssetBundleService();
  final _pngController = PngSeriesController();
  final _subtitleController = PngSubtitleController();
  final _transcriptScrollController = ScrollController();
  final Map<int, GlobalKey> _segmentKeys = {};
  int _lastActiveSegmentIndex = -1;
  
  final String _bundleId = 'subtitle_bundle_v1';
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

  Future<void> _checkStatus() async {
    final installed = await _service.isBundleDownloaded(_bundleId);
    if (installed) {
      final images = await _service.getAllImages(_bundleId);
      final audioFiles = await _service.getAllAudio(_bundleId);
      final subtitleFiles = await _service.getAllSubtitles(_bundleId);
      
      if (subtitleFiles.isNotEmpty) {
        try {
          debugPrint('Phase 5: Loading subtitles from bundle path: ${subtitleFiles.first}');
          final data = await _service.getJsonFromAbsolutePath(subtitleFiles.first);
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
        } else {
          _audioPath = _fallbackAudioAsset;
        }
        _isReady = true;

        // Autoplay once ready
        _pngController.play();
      });
    } else {
      await _loadFallbackSubtitles();
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
    _subtitleController.dispose();
    _transcriptScrollController.dispose();
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
            Text('Preparing Experience...'),
          ],
        ),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Column(
      children: [
        SizedBox(
          height: isLandscape ? 150 : 300,
          child: PngSeriesAnimator.videoPlayer(
            imagePaths: _imagePaths,
            controller: _pngController,
            audioPath: _audioPath,
            subtitleController: _subtitleController,
            fit: BoxFit.contain,
            subtitleBuilder: (context, segment, currentTime) {
              if (segment == null) return const SizedBox.shrink();

              return Directionality(
                textDirection: _subtitleController.isRTL ? TextDirection.rtl : TextDirection.ltr,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 0),
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
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLandscape)
                Text(
                  _audioPath != null && p.isAbsolute(_audioPath!)
                    ? 'Audio: ${p.basename(_audioPath!)} (Bundle)' 
                    : 'Audio: $_fallbackAudioAsset (Local Asset)',
                  style: const TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              if (!isLandscape) const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  _pngController.pause();
                  await _service.deleteBundle(_bundleId);
                  setState(() {
                     _isInstalled = false;
                     _isReady = false;
                  });
                },
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Reset Bundle'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  minimumSize: const Size(0, 36),
                ),
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
        // Use animation controller's duration or a fallback
        final Duration dur = _pngController.animationController?.duration ?? const Duration(seconds: 10);
        final double currentTime = _pngController.value * dur.inSeconds;
        final segments = _subtitleController.currentSegments;

        if (segments.isEmpty) {
          return const Center(child: Text('No transcript available for this language.'));
        }

        // Auto-scroll logic: Find current active segment
        int activeIndex = -1;
        for (int i = 0; i < segments.length; i++) {
          if (currentTime >= segments[i].start && currentTime <= segments[i].end) {
            activeIndex = i;
            break;
          }
        }

        if (activeIndex != -1 && activeIndex != _lastActiveSegmentIndex) {
          _lastActiveSegmentIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
             final key = _segmentKeys[activeIndex];
             if (key?.currentContext != null) {
               Scrollable.ensureVisible(
                 key!.currentContext!,
                 duration: const Duration(milliseconds: 500),
                 curve: Curves.easeInOut,
                 alignment: 0.5, // Center in viewport
               );
             }
          });
        }

        return Directionality(
          textDirection: _subtitleController.isRTL ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            crossAxisAlignment: _subtitleController.isRTL ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: List.generate(segments.length, (index) {
              final segment = segments[index];
              _segmentKeys[index] ??= GlobalKey();

              return Container(
                key: _segmentKeys[index],
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 4,
                  runSpacing: 8,
                  children: segment.words.map((word) {
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
                  }).toList(),
                ),
              );
            }),
          ),
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
