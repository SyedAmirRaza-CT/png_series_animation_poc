import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../png_series_animator/png_series_animator.dart';
import '../asset_bundle_manager/asset_bundle_service.dart';

class Phase6NoFallbackDemo extends StatefulWidget {
  const Phase6NoFallbackDemo({super.key});

  @override
  State<Phase6NoFallbackDemo> createState() => _Phase6NoFallbackDemoState();
}

class _Phase6NoFallbackDemoState extends State<Phase6NoFallbackDemo> with TickerProviderStateMixin {
  final _service = AssetBundleService();
  final _pngController = PngSeriesController();
  final _subtitleController = PngSubtitleController();
  final _transcriptScrollController = ScrollController();
  final Map<int, GlobalKey> _segmentKeys = {};
  int _lastActiveSegmentIndex = -1;
  
  final String _bundleId = 'no_fallback_bundle_v1';
  // Note: Using the same test URL as Phase 5 for logic demonstration
  final String _zipUrl = 'http://172.16.82.65:8080/1.zip';

  bool _isDownloading = false;
  double _downloadProgress = 0;
  bool _isInstalled = false;
  
  List<String> _imagePaths = [];
  String? _audioPath;
  List<String> _videoPaths = [];
  bool _hasSubtitles = false;
  
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final installed = await _service.isBundleDownloaded(_bundleId);
    if (installed) {
      final content = await _service.getBundleContent(_bundleId);
      
      final images = content.images;
      final audioFiles = content.audio;
      final subtitleFiles = content.subtitles;
      final videos = content.videos;

      debugPrint("Phase 6: Detected Bundle Content:");
      debugPrint("Images: ${images.length}");
      debugPrint("Audio: ${audioFiles.length}");
      debugPrint("Subtitles: ${subtitleFiles.length}");
      debugPrint("Videos: ${videos.length}");

      // 1. Load Subtitles if available
      if (content.hasSubtitles) {
        try {
          final data = await _service.getJsonFromAbsolutePath(content.subtitles.first);
          _subtitleController.updateData(data, initialLanguage: 'en');
          _hasSubtitles = true;
        } catch (e) {
          debugPrint('Phase 6 Error: Failed to load bundle subtitles: $e');
        }
      }

      setState(() {
        _isInstalled = true;
        _imagePaths = images;
        _videoPaths = videos;
        _audioPath = audioFiles.isNotEmpty ? audioFiles.first : null;
        
        // Phase 6 is "Ready" if there is at least something to show/play
        _isReady = _imagePaths.isNotEmpty || _videoPaths.isNotEmpty || _audioPath != null;

        if (_isReady) {
          _pngController.play();
        }
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
    _subtitleController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 6: Strict Bundle Content')),
      body: Center(
        child: _isInstalled 
          ? _buildPlayer()
          : _buildDownloadPrompt(),
      ),
    );
  }

  Widget _buildPlayer() {
    if (!_isReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Incomplete Bundle Content',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'The downloaded bundle appears to be empty. No images, audio, or video files were found.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                 await _service.deleteBundle(_bundleId);
                 setState(() => _isInstalled = false);
              },
              child: const Text('Redownload Bundle'),
            )
          ],
        ),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Column(
      children: [
        if (_imagePaths.isNotEmpty)
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
                      textAlign: TextAlign.start,
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
          )
        else if (_audioPath != null)
           Container(
            height: 100,
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.audiotrack, color: Colors.cyan),
                  const SizedBox(width: 12),
                  Text('Playing Audio: ${p.basename(_audioPath!)}'),
                ],
              ),
            ),
          ),
        if (_hasSubtitles)
          Expanded(
            child: SingleChildScrollView(
              controller: _transcriptScrollController,
              padding: const EdgeInsets.all(20),
              child: _buildTranscript(),
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Text('No images or subtitles to display.', style: TextStyle(color: Colors.white24)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isLandscape && _audioPath != null)
                Text(
                  'Audio: ${p.basename(_audioPath!)}', 
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
        final Duration dur = _pngController.animationController?.duration ?? const Duration(seconds: 10);
        final double currentTime = _pngController.value * dur.inSeconds;
        final segments = _subtitleController.currentSegments;

        if (segments.isEmpty) {
          return const Center(child: Text('No transcript available in bundle.'));
        }

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
                 alignment: 0.5,
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
        const Icon(Icons.cloud_off, size: 80, color: Colors.cyan),
        const SizedBox(height: 20),
        const Text(
          'Phase 6: Strict Bundle',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
          child: Text(
            'This phase strictly requires content from the bundle. If any part (Audio, Images, JSON) is missing, playback will not start. Asset fallbacks are disabled.',
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
            child: const Text('Download Content Bundle'),
          ),
      ],
    );
  }
}
