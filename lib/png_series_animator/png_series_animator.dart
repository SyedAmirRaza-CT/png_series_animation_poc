import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/image_cache_manager.dart';

typedef PngSeriesTransitionBuilder = Widget Function(
  BuildContext context,
  Widget currentFrame,
  Widget nextFrame,
  double progress,
);

typedef PngSubtitleBuilder = Widget Function(
  BuildContext context,
  SubtitleSegment? segment,
  double currentTimeInSeconds,
);

class PngSeriesController extends ChangeNotifier {
  AnimationController? _animationController;
  bool _isPlaying = false;

  void _attach(AnimationController controller) {
    _animationController = controller;
    _animationController!.addListener(_onControllerTick);
  }

  void _detach() {
    _animationController?.removeListener(_onControllerTick);
    _animationController = null;
  }

  void _onControllerTick() {
    notifyListeners();
  }

  /// Starts playback
  void play() {
    _isPlaying = true;
    _animationController?.forward();
    notifyListeners();
  }

  /// Pauses playback
  void pause() {
    _isPlaying = false;
    _animationController?.stop();
    notifyListeners();
  }

  /// Seeks to a specific progress (0.0 to 1.0)
  void seekTo(double value) {
    _animationController?.value = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Current progress of the animation (0.0 to 1.0)
  double get value => _animationController?.value ?? 0.0;

  /// Whether the animation is currently playing
  bool get isPlaying => _isPlaying;

  /// Access to the raw AnimationController (useful for advanced syncing)
  AnimationController? get animationController => _animationController;

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

class SubtitleSegment {
  final double start;
  final double end;
  final String text;
  final List<SubtitleWord> words;

  SubtitleSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.words,
  });

  factory SubtitleSegment.fromJson(Map<String, dynamic> json) {
    return SubtitleSegment(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => SubtitleWord.fromJson(w))
              .toList() ??
          [],
    );
  }
}

class SubtitleWord {
  final double start;
  final double end;
  final String text;

  SubtitleWord({
    required this.start,
    required this.end,
    required this.text,
  });

  factory SubtitleWord.fromJson(Map<String, dynamic> json) {
    return SubtitleWord(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
    );
  }
}

class PngSubtitleController extends ChangeNotifier {
  Map<String, List<SubtitleSegment>> _data = {};
  String? _currentLanguage;
  bool _isVisible = true;
  TextStyle? _style;
  TextStyle? _highlightStyle;

  PngSubtitleController({
    Map<String, dynamic>? data,
    String? initialLanguage,
    bool isVisible = true,
    TextStyle? style,
    TextStyle? highlightStyle,
  })  : _isVisible = isVisible,
        _style = style,
        _highlightStyle = highlightStyle {
    if (data != null) {
      updateData(data, initialLanguage: initialLanguage);
    }
  }

  /// Updates the underlying subtitle data and optionally changes the language
  void updateData(Map<String, dynamic> rawData, {String? initialLanguage}) {
    _data = rawData.map((key, value) {
      return MapEntry(
        key,
        (value as List).map((s) => SubtitleSegment.fromJson(s as Map<String, dynamic>)).toList(),
      );
    });
    if (initialLanguage != null || _currentLanguage == null) {
      _currentLanguage = initialLanguage ?? _data.keys.firstOrNull;
    }
    notifyListeners();
  }

  /// Changes the current subtitle language
  set language(String? lang) {
    if (_data.containsKey(lang)) {
      _currentLanguage = lang;
      notifyListeners();
    }
  }

  String? get language => _currentLanguage;

  /// Toggles subtitle visibility
  set isVisible(bool visible) {
    _isVisible = visible;
    notifyListeners();
  }

  bool get isVisible => _isVisible;

  /// Updates the base text style
  set style(TextStyle? newStyle) {
    _style = newStyle;
    notifyListeners();
  }

  TextStyle? get style => _style;

  /// Updates the highlighting text style
  set highlightStyle(TextStyle? newStyle) {
    _highlightStyle = newStyle;
    notifyListeners();
  }

  TextStyle? get highlightStyle => _highlightStyle;

  /// Returns segments for the current language
  List<SubtitleSegment> get currentSegments => _data[_currentLanguage] ?? [];

  /// Returns all available languages in the data
  List<String> get availableLanguages => _data.keys.toList();

  /// Cycles through available languages
  void cycleLanguage() {
    if (_data.isEmpty) return;
    final languages = availableLanguages;
    final currentIndex = languages.indexOf(_currentLanguage ?? '');
    if (currentIndex == -1 || currentIndex == languages.length - 1) {
      _currentLanguage = languages.first;
    } else {
      _currentLanguage = languages[currentIndex + 1];
    }
    notifyListeners();
  }

  /// Toggles subtitle visibility
  void toggleVisibility() {
    _isVisible = !_isVisible;
    notifyListeners();
  }

  /// Gets the active segment for a specific time
  SubtitleSegment? getSegmentAt(double timeInSeconds) {
    if (!_isVisible) return null;
    final segments = currentSegments;
    for (final s in segments) {
      if (timeInSeconds >= s.start && timeInSeconds <= s.end) return s;
    }
    return null;
  }
}

class PngSeriesAnimator extends StatefulWidget {
  final List<String> imagePaths;
  final Duration duration;
  final bool repeat;
  final bool isPlaying;
  final BoxFit fit;
  final double? width;
  final double? height;
  final PngSeriesTransitionBuilder? transitionBuilder;
  final VoidCallback? onCompleted;
  final Object? heroTag;
  final PngSeriesController? controller;
  final ValueChanged<bool>? onPlayStateChanged;
  final ValueChanged<double>? onSeek;

  // Video Player specific properties
  final bool showControls;
  final bool isFullScreen;
  final double initialValue;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  // Subtitle property (Single variable control)
  final PngSubtitleController? subtitleController;
  final PngSubtitleBuilder? subtitleBuilder;

  const PngSeriesAnimator({
    super.key,
    required this.imagePaths,
    this.duration = const Duration(seconds: 2),
    this.repeat = true,
    this.isPlaying = true,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.transitionBuilder,
    this.onCompleted,
    this.heroTag,
    this.controller,
    this.onPlayStateChanged,
    this.onSeek,
    this.showControls = false,
    this.isFullScreen = false,
    this.initialValue = 0.0,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.subtitleController,
    this.subtitleBuilder,
  }) : assert(imagePaths.length > 0, 'imagePaths cannot be empty');

  const PngSeriesAnimator.videoPlayer({
    super.key,
    required this.imagePaths,
    this.duration = const Duration(seconds: 2),
    this.repeat = true,
    this.isPlaying = true,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.transitionBuilder,
    this.onCompleted,
    this.heroTag,
    this.controller,
    this.onPlayStateChanged,
    this.onSeek,
    this.initialValue = 0.0,
    this.isFullScreen = false,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.subtitleController,
    this.subtitleBuilder,
  })  : showControls = true,
        assert(imagePaths.length > 0, 'imagePaths cannot be empty');

  @override
  State<PngSeriesAnimator> createState() => _PngSeriesAnimatorState();
}

class _PngSeriesAnimatorState extends State<PngSeriesAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _precached = false;
  bool _shouldTriggerCompleted = false;
  final Map<String, ImageProvider> _imageProviders = {};
  final Set<int> _loadedIndices = {};
  double? _aspectRatio;
  bool _isBuffering = false;

  // State for video controls
  late bool _isPlaying;
  bool _wasPlayingBeforeDrag = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isFullScreenInternal = false;
  OverlayEntry? _fullScreenEntry;

  // State for play/pause animation overlay
  bool _showOverlayIconVisible = false;
  IconData _overlayIcon = Icons.play_arrow;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    
    widget.subtitleController?.addListener(_onSubtitleControllerChanged);

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.initialValue,
    );

    // If a controller is provided, it becomes the source of truth for the initial play state
    if (widget.controller != null) {
      _isPlaying = widget.controller!.isPlaying;
      widget.controller?._attach(_controller);
      widget.controller?.addListener(_onControllerChanged);
      
      // If we are starting in play mode, notify the parent (Phase 4) 
      // so it can start the synced audio.
      if (_isPlaying && widget.onPlayStateChanged != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onPlayStateChanged!(true);
        });
      }
    } else {
      _isPlaying = widget.isPlaying;
    }

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_shouldTriggerCompleted && widget.onCompleted != null) {
          _shouldTriggerCompleted = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onCompleted!();
            }
          });
        }
      }
    });

    // We do NOT call _updateAnimationState() here anymore.
    // Startup will be managed by _precacheImages once initial buffer is ready.
    
    if (widget.showControls) {
      _startHideTimer();
    }
  }

  void _onControllerChanged() {
    if (widget.controller != null && widget.controller!.isPlaying != _isPlaying) {
      setState(() {
        _isPlaying = widget.controller!.isPlaying;
        _updateAnimationState();
      });
      _fullScreenEntry?.markNeedsBuild();

      // Notify the parent (Phase 4) to play/pause the audio
      if (widget.onPlayStateChanged != null) {
        widget.onPlayStateChanged!(_isPlaying);
      }
    }
  }

  void _onSubtitleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_wasPlayingBeforeDrag) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _toggleControls() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
        _startHideTimer();
      });
    } else {
      _togglePlayPause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precacheImages();
    }
  }

  Future<void> _precacheImages() async {
    final cacheManager = ImageCacheManager();
    final int total = widget.imagePaths.length;
    
    // 1. Load the essential startup buffer (First 15% or at least 5 frames)
    // We wait for these to be FULLY ready before showing anything to the user.
    final int startupBufferCount = (total * 0.15).ceil().clamp(3, 8);
    
    for (int i = 0; i < startupBufferCount; i++) {
      if (i < total) {
        await _loadFrame(i, cacheManager);
      }
    }
    
    // 2. Start the show
    if (mounted) {
      setState(() {
        _precached = true;
        _updateAnimationState();
      });
    }
    
    // 3. Load all remaining frames in parallel in the background
    // We don't await these, they will fill the buffer as the user watches.
    for (int i = startupBufferCount; i < total; i++) {
      _loadFrame(i, cacheManager);
    }
  }

  Future<void> _loadFrame(int index, ImageCacheManager cacheManager) async {
    if (!mounted) return;
    final path = widget.imagePaths[index];
    
    if (_imageProviders.containsKey(path) && _loadedIndices.contains(index)) return;

    ImageProvider provider;
    try {
      if (path.startsWith('http')) {
        final localFile = await cacheManager.getCachedFile(path);
        if (localFile != null) {
          provider = FileImage(localFile);
        } else {
          provider = NetworkImage(path);
        }
      } else {
        provider = AssetImage(path);
      }

      if (!mounted) return;
      _imageProviders[path] = provider;

      // Handle aspect ratio from frame 0
      if (index == 0 && _aspectRatio == null) {
        final ImageStream stream = provider.resolve(createLocalImageConfiguration(context));
        final Completer<void> completer = Completer<void>();
        final ImageStreamListener listener = ImageStreamListener(
          (ImageInfo info, bool synchronousCall) {
            if (mounted) {
              setState(() {
                _aspectRatio = info.image.width / info.image.height;
              });
            }
            if (!completer.isCompleted) completer.complete();
          },
          onError: (dynamic exception, StackTrace? stackTrace) {
            if (!completer.isCompleted) completer.complete();
          },
        );
        stream.addListener(listener);
        await precacheImage(provider, context);
        await completer.future;
        stream.removeListener(listener);
      } else {
        await precacheImage(provider, context);
      }

      if (mounted) {
        setState(() {
          _loadedIndices.add(index);
          
          // BUFFER RESUMPTION
          if (_isBuffering) {
            final int total = widget.imagePaths.length;
            final int currentRequiredFrame = (_controller.value * total).floor().clamp(0, total - 1);
            if (_loadedIndices.contains(currentRequiredFrame)) {
              _isBuffering = false;
              _updateAnimationState();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading frame $index: $e');
      if (mounted) {
        setState(() {
          _loadedIndices.add(index);
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant PngSeriesAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.isPlaying != widget.isPlaying) {
      _isPlaying = widget.isPlaying;
      _updateAnimationState();
    } else if (oldWidget.repeat != widget.repeat) {
      _updateAnimationState();
    }
    
    if (oldWidget.imagePaths != widget.imagePaths) {
       _imageProviders.clear();
       _loadedIndices.clear();
       _precached = false;
       _precacheImages();
    }
    if (oldWidget.subtitleController != widget.subtitleController) {
      oldWidget.subtitleController?.removeListener(_onSubtitleControllerChanged);
      widget.subtitleController?.addListener(_onSubtitleControllerChanged);
    }
  }

  void _updateAnimationState() {
    if (!_precached) return; // Wait for initial buffer

    if (_isPlaying && !_isBuffering) {
      if (widget.repeat) {
        _shouldTriggerCompleted = false;
        _controller.repeat();
      } else {
        _shouldTriggerCompleted = true;
        if (_controller.value == 1.0) {
          _controller.forward(from: 0.0);
        } else {
          _controller.forward();
        }
      }
    } else {
      _shouldTriggerCompleted = false;
      _controller.stop();
    }
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      _updateAnimationState();
      _showOverlayIcon(icon: _isPlaying ? Icons.play_arrow : Icons.pause);

      if (widget.onPlayStateChanged != null) {
        widget.onPlayStateChanged!(_isPlaying);
      }

      if (_isPlaying) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
        _controlsVisible = true;
      }
    });
  }

  void _showOverlayIcon({required IconData icon}) {
    setState(() {
      _overlayIcon = icon;
      _showOverlayIconVisible = true;
      _overlayTimer?.cancel();
      _overlayTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _showOverlayIconVisible = false;
          });
        }
      });
    });
  }

  void _seekRelative(int seconds) {
    final Duration effectiveDuration = _controller.duration ?? widget.duration;
    final double delta = seconds / effectiveDuration.inSeconds;
    final double newValue = (_controller.value + delta).clamp(0.0, 1.0);
    setState(() {
      _controller.value = newValue;
    });
    
    if (widget.onSeek != null) {
      widget.onSeek!(newValue);
    }
    
    if (_isPlaying) {
      _updateAnimationState();
    }
    
    _showOverlayIcon(icon: seconds > 0 ? Icons.forward_10 : Icons.replay_10);
    _startHideTimer();
  }

  void _toggleFullScreen() async {
    if (_isFullScreenInternal) {
      _exitFullScreen();
    } else {
      _enterFullScreen();
    }
  }

  void _enterFullScreen() {
    setState(() {
      _isFullScreenInternal = true;
    });

    final bool isLandscape = (_aspectRatio ?? 1.0) > 1.0;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    _fullScreenEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black,
        child: _buildMainContent(isFullScreen: true),
      ),
    );

    Overlay.of(context).insert(_fullScreenEntry!);
  }

  void _exitFullScreen() async {
    _fullScreenEntry?.remove();
    _fullScreenEntry = null;

    setState(() {
      _isFullScreenInternal = false;
    });

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    _fullScreenEntry?.remove();
    _fullScreenEntry = null;
    widget.controller?.removeListener(_onControllerChanged);
    widget.controller?._detach();
    widget.subtitleController?.removeListener(_onSubtitleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenInternal) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: Text('Playing in Full Screen', style: TextStyle(color: Colors.grey))),
      );
    }
    return _buildMainContent(isFullScreen: false);
  }

  Widget _buildMainContent({required bool isFullScreen}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: !_precached
          ? SizedBox(
              key: const ValueKey('loader'),
              width: widget.width,
              height: widget.height,
              child: const Center(child: CircularProgressIndicator()),
            )
          : AnimatedBuilder(
              key: const ValueKey('animator'),
              animation: _controller,
              builder: (context, child) {
                final double value = _controller.value;
                final int totalFrames = widget.imagePaths.length;
                final int frameIndex = (value * totalFrames).floor().clamp(0, totalFrames - 1);

                // Buffering Logic: If the current frame isn't loaded yet
                if (!_loadedIndices.contains(frameIndex) && !_isBuffering) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_isBuffering) {
                      setState(() {
                        _isBuffering = true;
                        _controller.stop();
                      });
                      _fullScreenEntry?.markNeedsBuild();
                    }
                  });
                }

                Widget imageWidget;
                if (totalFrames == 0) {
                  imageWidget = const SizedBox.shrink();
                } else if (totalFrames == 1) {
                  imageWidget = _buildImage(widget.imagePaths.first);
                } else {
                  final double exactFrame = value * (totalFrames - 1);
                  
                  if (widget.transitionBuilder == null) {
                    imageWidget = _buildImage(widget.imagePaths[frameIndex]);
                  } else {
                    final int currentFrameIndex = exactFrame.floor();
                    final int nextFrameIndex = (currentFrameIndex + 1) < totalFrames
                        ? currentFrameIndex + 1
                        : currentFrameIndex;
                    final double progressToNextFrame = exactFrame - currentFrameIndex;
                    imageWidget = widget.transitionBuilder!(
                      context,
                      _buildImage(widget.imagePaths[currentFrameIndex]),
                      _buildImage(widget.imagePaths[nextFrameIndex]),
                      progressToNextFrame,
                    );
                  }
                }

                if (widget.heroTag != null) {
                  imageWidget = Hero(tag: widget.heroTag!, child: imageWidget);
                }

                Widget content = imageWidget;

                // Overlay buffer loader if necessary
                if (_isBuffering) {
                  content = Stack(
                    fit: StackFit.expand,
                    children: [
                      imageWidget,
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        ),
                      ),
                    ],
                  );
                }

                if (!widget.showControls) {
                  return SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        content,
                        if (widget.subtitleController?.isVisible == true)
                          Positioned(
                            bottom: 40,
                            left: 20,
                            right: 20,
                            child: _buildSubtitles(),
                          ),
                      ],
                    ),
                  );
                }

                return MouseRegion(
                  onHover: (_) {
                    if (!_controlsVisible) {
                      setState(() {
                        _controlsVisible = true;
                        _startHideTimer();
                      });
                      _fullScreenEntry?.markNeedsBuild();
                    }
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTap: _toggleControls,
                        onDoubleTap: () {},
                        onDoubleTapDown: (details) {
                          final double width = constraints.maxWidth;
                          if (details.localPosition.dx < width / 2) {
                            _seekRelative(-10);
                          } else {
                            _seekRelative(10);
                          }
                        },
                        child: SizedBox(
                          width: isFullScreen ? null : widget.width,
                          height: isFullScreen ? null : widget.height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              content,
                              if (widget.subtitleController?.isVisible == true)
                                Positioned(
                                  bottom: widget.showControls && _controlsVisible ? 100 : 40,
                                  left: 20,
                                  right: 20,
                                  child: _buildSubtitles(),
                                ),
                              Center(
                                child: AnimatedOpacity(
                                  opacity: _showOverlayIconVisible ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                    child: Icon(_overlayIcon, size: 50, color: Colors.white),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: isFullScreen ? 40 : 10,
                                right: 20,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: IgnorePointer(
                                    ignoring: !_controlsVisible,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.subtitleController != null) ...[
                                          // 1. Subtitle Visibility Toggle
                                          IconButton(
                                            tooltip: 'Toggle Subtitles',
                                            icon: Icon(
                                              widget.subtitleController!.isVisible
                                                  ? Icons.subtitles
                                                  : Icons.subtitles_off,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                widget.subtitleController!.toggleVisibility();
                                              });
                                            },
                                          ),
                                          // 2. Language Cycle Button
                                          if (widget.subtitleController!.isVisible &&
                                              widget.subtitleController!.availableLanguages.length > 1)
                                            if (widget.subtitleController!.language != null)
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    widget.subtitleController!.cycleLanguage();
                                                  });
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets.only(left: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black45,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.white24),
                                                  ),
                                                  child: Text(
                                                    widget.subtitleController!.language!.toUpperCase(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                        ],
                                        if (isFullScreen)
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                            onPressed: _exitFullScreen,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: AnimatedOpacity(
                                  opacity: _controlsVisible ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: IgnorePointer(
                                    ignoring: !_controlsVisible,
                                    child: _buildVideoControls(isFullScreen),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSubtitles() {
    final controller = widget.subtitleController;
    if (controller == null || !controller.isVisible) return const SizedBox.shrink();

    final Duration effectiveDuration = _controller.duration ?? widget.duration;
    final double currentTimeInSeconds = _controller.value * effectiveDuration.inSeconds;

    final segment = controller.getSegmentAt(currentTimeInSeconds);

    if (widget.subtitleBuilder != null) {
      return widget.subtitleBuilder!(context, segment, currentTimeInSeconds);
    }

    if (segment == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: segment.words.map((word) {
            final bool isHighlighted = currentTimeInSeconds >= word.start && currentTimeInSeconds <= word.end;
            return TextSpan(
              text: "${word.text} ",
              style: isHighlighted
                  ? (controller.highlightStyle ?? const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 18))
                  : (controller.style ?? const TextStyle(color: Colors.white, fontSize: 18)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVideoControls(bool isFullScreen) {
    final Duration effectiveDuration = _controller.duration ?? widget.duration;
    final currentDuration = effectiveDuration * _controller.value;
    
    // Calculate contiguous buffer progress from current position
    final int total = widget.imagePaths.length;
    double bufferProgress = 0.0;
    if (total > 0) {
      final int currentFrame = (_controller.value * total).floor().clamp(0, total - 1);
      int contiguousEnd = currentFrame;
      while (contiguousEnd < total && _loadedIndices.contains(contiguousEnd)) {
        contiguousEnd++;
      }
      bufferProgress = contiguousEnd / total;
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.0,
                trackShape: BufferSliderTrackShape(
                  bufferProgress: bufferProgress,
                  bufferColor: (widget.activeColor ?? Colors.redAccent).withValues(alpha: 0.3),
                ),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                activeTrackColor: widget.activeColor ?? Colors.redAccent,
                inactiveTrackColor: (widget.inactiveColor ?? Colors.white).withValues(alpha: 0.1),
                thumbColor: widget.thumbColor ?? widget.activeColor ?? Colors.redAccent,
              ),
              child: Slider(
                value: _controller.value,
                onChangeStart: (_) {
                  _wasPlayingBeforeDrag = _isPlaying;
                  _isPlaying = false;
                  _updateAnimationState();
                  _hideTimer?.cancel();
                },
                onChangeEnd: (_) {
                  if (_wasPlayingBeforeDrag) {
                    _isPlaying = true;
                    _updateAnimationState();
                  }
                  _startHideTimer();
                },
                onChanged: (val) {
                  setState(() {
                    _controller.value = val;
                  });
                  if (widget.onSeek != null) {
                    widget.onSeek!(val);
                  }
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: _togglePlayPause,
                ),
                Text(
                  '${_formatDuration(currentDuration)} / ${_formatDuration(effectiveDuration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(widget.isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                  onPressed: _toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _buildImage(String path) {
    final provider = _imageProviders[path];
    if (provider == null) return const SizedBox.shrink();
    return Image(
      image: provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.black26,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, color: Colors.redAccent, size: 32),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'Error loading frame:\n${path.length > 30 ? "...${path.substring(path.length - 27)}" : path}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BufferSliderTrackShape extends RoundedRectSliderTrackShape {
  final double bufferProgress;
  final Color bufferColor;

  BufferSliderTrackShape({required this.bufferProgress, required this.bufferColor});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // 1. Paint the standard inactive and active track
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    if (bufferProgress <= 0) return;

    // 2. Calculate the track rectangle
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    // 3. Paint the buffer bar over the inactive track
    final Paint bufferPaint = Paint()..color = bufferColor;
    final double bufferWidth = trackRect.width * bufferProgress;

    context.canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        trackRect.left,
        trackRect.top,
        trackRect.left + bufferWidth,
        trackRect.bottom,
        topLeft: Radius.circular(trackRect.height / 2),
        bottomLeft: Radius.circular(trackRect.height / 2),
        topRight: bufferProgress >= 0.99 ? Radius.circular(trackRect.height / 2) : Radius.zero,
        bottomRight: bufferProgress >= 0.99 ? Radius.circular(trackRect.height / 2) : Radius.zero,
      ),
      bufferPaint,
    );
  }
}


