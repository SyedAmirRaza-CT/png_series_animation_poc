import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/image_cache_manager.dart';

typedef PngSeriesTransitionBuilder = Widget Function(
  BuildContext context,
  Widget currentFrame,
  Widget nextFrame,
  double progress,
);

class PngSeriesController extends ChangeNotifier {
  AnimationController? _animationController;
  bool _isPlaying = false;

  void _attach(AnimationController controller, bool isPlaying) {
    _animationController = controller;
    _isPlaying = isPlaying;
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
    _isPlaying = widget.isPlaying;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.initialValue,
    );

    widget.controller?._attach(_controller, _isPlaying);

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
    widget.controller?._detach();
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
                  return SizedBox(width: widget.width, height: widget.height, child: content);
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
                              if (isFullScreen)
                                Positioned(
                                  top: 40,
                                  right: 20,
                                  child: AnimatedOpacity(
                                    opacity: _controlsVisible ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: IgnorePointer(
                                      ignoring: !_controlsVisible,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                        onPressed: _exitFullScreen,
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
