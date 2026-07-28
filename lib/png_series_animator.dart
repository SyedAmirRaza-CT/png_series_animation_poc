import 'package:flutter/material.dart';

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
  }) : assert(imagePaths.length > 0, 'imagePaths cannot be empty');

  @override
  State<PngSeriesAnimator> createState() => _PngSeriesAnimatorState();
}

class _PngSeriesAnimatorState extends State<PngSeriesAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _precached = false;
  bool _shouldTriggerCompleted = false;
  final Map<String, ImageProvider> _imageProviders = {};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _controller.addStatusListener((status) {
      debugPrint('PngSeriesAnimator status: $status, repeat: ${widget.repeat}, shouldTrigger: $_shouldTriggerCompleted');
      if (status == AnimationStatus.completed) {
        if (_shouldTriggerCompleted && widget.onCompleted != null) {
          debugPrint(
            'PngSeriesAnimator animation completed. Calling onCompleted...',
          );
          _shouldTriggerCompleted = false; // Reset to prevent double triggers
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onCompleted!();
            }
          });
        }
      }
    });

    // Initialize all ImageProviders so they are cached/reused.
    for (final path in widget.imagePaths) {
      _imageProviders[path] = AssetImage(path);
    }

    _updateAnimationState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precacheImages();
    }
  }

  Future<void> _precacheImages() async {
    for (final provider in _imageProviders.values) {
      try {
        await precacheImage(provider, context);
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
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.repeat != widget.repeat) {
      _updateAnimationState();
    }
  }

  void _updateAnimationState() {
    if (widget.isPlaying) {
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

  @override
  void dispose() {
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

        if (totalFrames == 1) {
          return _buildImage(widget.imagePaths.first);
        }

        // Map value (0.0 -> 1.0) to frame index range (0 -> totalFrames - 1)
        final double exactFrame = value * (totalFrames - 1);

        // If no transition builder is provided, step transition (flipbook style) is used by default.
        if (widget.transitionBuilder == null) {
          final int roundedFrameIndex = exactFrame.round().clamp(0, totalFrames - 1);
          return _buildImage(widget.imagePaths[roundedFrameIndex]);
        }

        final int currentFrameIndex = exactFrame.floor();
        final int nextFrameIndex = (currentFrameIndex + 1) < totalFrames
            ? currentFrameIndex + 1
            : currentFrameIndex;
        final double progressToNextFrame = exactFrame - currentFrameIndex;

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.transitionBuilder!(
            context,
            _buildImage(widget.imagePaths[currentFrameIndex]),
            _buildImage(widget.imagePaths[nextFrameIndex]),
            progressToNextFrame,
          ),
        );
      },
    );
  }

  Widget _buildImage(String path) {
    final provider = _imageProviders[path];
    if (provider == null) {
      return const SizedBox.shrink();
    }
    return Image(
      image: provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
    );
  }
}
