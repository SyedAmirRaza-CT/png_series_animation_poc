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
  double? _aspectRatio;

  // State for video controls
  late bool _isPlaying;
  bool _wasPlayingBeforeDrag = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

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

    _updateAnimationState();
    
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

    for (int i = 0; i < widget.imagePaths.length; i++) {
      if (!mounted) return;
      final path = widget.imagePaths[i];
      ImageProvider provider;

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

      _imageProviders[path] = provider;

      try {
        if (i == 0) {
          if (!mounted) return;
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
      } catch (e) {
        debugPrint('Error precaching image: $e');
      }
    }
    if (mounted) {
      setState(() {
        _precached = true;
      });
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
       _precached = false;
       _precacheImages();
    }
  }

  void _updateAnimationState() {
    if (_isPlaying) {
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
    final double delta = seconds / widget.duration.inSeconds;
    final double newValue = (_controller.value + delta).clamp(0.0, 1.0);
    setState(() {
      _controller.value = newValue;
    });
    
    if (_isPlaying) {
      _updateAnimationState();
    }
    
    _showOverlayIcon(icon: seconds > 0 ? Icons.forward_10 : Icons.replay_10);
    _startHideTimer();
  }

  void _toggleFullScreen() async {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
      return;
    }

    final bool isLandscape = (_aspectRatio ?? 1.0) > 1.0;

    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: PngSeriesAnimator.videoPlayer(
              imagePaths: widget.imagePaths,
              duration: widget.duration,
              repeat: widget.repeat,
              isPlaying: _isPlaying,
              fit: BoxFit.contain,
              initialValue: _controller.value,
              isFullScreen: true,
              heroTag: widget.heroTag,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
              thumbColor: widget.thumbColor,
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_precached) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double value = _controller.value;
        final int totalFrames = widget.imagePaths.length;

        Widget imageWidget;
        if (totalFrames == 1) {
          imageWidget = _buildImage(widget.imagePaths.first);
        } else {
          final double exactFrame = value * (totalFrames - 1);
          
          if (widget.transitionBuilder == null) {
            final int frameIndex = (value * totalFrames).floor().clamp(0, totalFrames - 1);
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

        if (!widget.showControls) {
          return SizedBox(width: widget.width, height: widget.height, child: imageWidget);
        }

        return MouseRegion(
          onHover: (_) {
            if (!_controlsVisible) {
              setState(() {
                _controlsVisible = true;
                _startHideTimer();
              });
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
                  width: widget.width,
                  height: widget.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageWidget,
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
                      if (widget.isFullScreen)
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
                                onPressed: () => Navigator.of(context).pop(),
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
                            child: _buildVideoControls(),
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
    );
  }

  Widget _buildVideoControls() {
    final currentDuration = widget.duration * _controller.value;

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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                activeTrackColor: widget.activeColor ?? Colors.redAccent,
                inactiveTrackColor: widget.inactiveColor ?? Colors.white24,
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
                  '${_formatDuration(currentDuration)} / ${_formatDuration(widget.duration)}',
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
