import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
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
  VoidCallback? _onPlay;
  VoidCallback? _onPause;
  ValueChanged<double>? _onSeek;

  void _attach(AnimationController controller, {
    VoidCallback? onPlay,
    VoidCallback? onPause,
    ValueChanged<double>? onSeek,
  }) {
    _animationController = controller;
    _onPlay = onPlay;
    _onPause = onPause;
    _onSeek = onSeek;
    _animationController!.addListener(_onControllerTick);
  }

  void _detach() {
    _animationController?.removeListener(_onControllerTick);
    _animationController = null;
    _onPlay = null;
    _onPause = null;
    _onSeek = null;
  }

  void _onControllerTick() {
    notifyListeners();
  }

  /// Internal sync for the state to update the controller
  void _updatePlayState(bool playing) {
    if (_isPlaying != playing) {
      _isPlaying = playing;
      notifyListeners();
    }
  }

  /// Starts playback
  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    if (_onPlay != null) {
      _onPlay!();
    } else {
      _animationController?.forward();
    }
    notifyListeners();
  }

  /// Pauses playback
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    if (_onPause != null) {
      _onPause!();
    } else {
      _animationController?.stop();
    }
    notifyListeners();
  }

  /// Seeks to a specific progress (0.0 to 1.0)
  void seekTo(double value) {
    final clampedValue = value.clamp(0.0, 1.0);
    if (_onSeek != null) {
      _onSeek!(clampedValue);
    } else {
      _animationController?.value = clampedValue;
    }
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
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: (json['text'] as String?) ?? '',
      words: (json['words'] as List<dynamic>?)
              ?.where((w) => w != null && w is Map<String, dynamic>)
              .map((w) => SubtitleWord.fromJson(w as Map<String, dynamic>))
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
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      text: (json['text'] as String?) ?? '',
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
    this._isVisible = true,
    this._style,
    this._highlightStyle,
  }) {
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

  /// Returns true if the current language is Right-To-Left (RTL)
  bool get isRTL {
    final lang = _currentLanguage?.toLowerCase() ?? '';
    // Common RTL language codes
    final rtlCodes = {'ur', 'ar', 'fa', 'he', 'ps', 'sd', 'ckb'};
    return rtlCodes.contains(lang);
  }

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

enum PngPlaybackState { playing, paused, buffering, seeking }

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

  // Audio property
  final String? audioPath;

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
    this.audioPath,
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
    this.audioPath,
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

  // Audio state
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  bool _audioReady = false;
  Duration _effectiveDuration = Duration.zero;
  PngPlaybackState _state = PngPlaybackState.paused;
  Timer? _seekTimer;
  Timer? _syncTimer;
  int _lastSeekActionTime = 0;
  int _targetSeekMs = 0;
  StreamSubscription? _posSub;
  
  // Use ValueNotifier for high-performance frame updates
  final ValueNotifier<int> _frameIndexNotifier = ValueNotifier<int>(0);
  StreamSubscription? _durSub;
  StreamSubscription? _compSub;

  @override
  void initState() {
    super.initState();
    
    // OPTIMIZATION: Limit image cache for iPad 3
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024; // 100MB
    
    debugPrint('PngSeriesAnimator: InitState - Version 6.0 (just_audio)');
    _effectiveDuration = widget.duration;
    
    widget.subtitleController?.addListener(_onSubtitleControllerChanged);
    _setupAudio();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.initialValue,
    )..addListener(_onAnimationTick);

    if (widget.controller != null) {
      _state = widget.controller!.isPlaying ? PngPlaybackState.playing : PngPlaybackState.paused;
      _isPlaying = widget.controller!.isPlaying;
      widget.controller?._attach(
        _controller,
        onPlay: () => _togglePlayPause(manualPlayState: true),
        onPause: () => _togglePlayPause(manualPlayState: false),
        onSeek: (val) => _seekTo(val),
      );
      
      if (_isPlaying && widget.onPlayStateChanged != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onPlayStateChanged!(true);
        });
      }
    } else {
      _isPlaying = widget.isPlaying;
      _state = widget.isPlaying ? PngPlaybackState.playing : PngPlaybackState.paused;
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

  void _onAnimationTick() {
    final int totalFrames = widget.imagePaths.length;
    if (totalFrames == 0) return;
    final int index = (_controller.value * totalFrames).floor().clamp(0, totalFrames - 1);
    if (_frameIndexNotifier.value != index) {
      _frameIndexNotifier.value = index;
    }
  }

  void _onSubtitleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _setupAudio() {
    if (widget.audioPath == null) {
      _audioReady = true;
      return;
    }

    _durSub = _audioPlayer.durationStream.listen((dur) {
      if (dur != null && mounted) {
        debugPrint('PngSeriesAnimator: Audio Duration Received: ${dur.inMilliseconds}ms');
        setState(() {
          _effectiveDuration = dur;
          _controller.duration = dur;
          _audioReady = true;
          
          if (widget.initialValue > 0) {
            _audioPlayer.seek(Duration(milliseconds: (widget.initialValue * dur.inMilliseconds).toInt()));
          }
          
          _syncPlayback();
        });
      }
    });

    _posSub = _audioPlayer.positionStream.listen((pos) {
      if (!mounted || _state != PngPlaybackState.playing) return;

      final int audioMs = pos.inMilliseconds;
      final int now = DateTime.now().millisecondsSinceEpoch;

      // Ignore updates immediately after seek
      if (now - _lastSeekActionTime < 1000) return;

      // Sync the AnimationController to audio
      final double audioProgress = (audioMs / _effectiveDuration.inMilliseconds).clamp(0.0, 1.0);
      final double drift = (audioProgress - _controller.value).abs();
      
      // If drift is significant (> 100ms), snap the controller
      if (drift > (100 / _effectiveDuration.inMilliseconds)) {
        _controller.value = audioProgress;
      }
    });

    _compSub = _audioPlayer.processingStateStream.listen((state) {
      if (state == ja.ProcessingState.completed && mounted) {
        if (widget.repeat) {
          _seekTo(0.0, resume: true);
        } else {
          _updateState(PngPlaybackState.paused);
        }
      }
    });

    _resolveAudioSource();
  }

  void _updateState(PngPlaybackState newState) {
    if (_state == newState) return;
    
    setState(() {
      _state = newState;
      _isPlaying = (newState == PngPlaybackState.playing);
      widget.controller?._updatePlayState(_isPlaying);
      _syncPlayback();
    });
  }

  void _syncPlayback() {
    if (!_precached || !_audioReady) {
      debugPrint('PngSeriesAnimator: Sync Deferred - Precached: $_precached, AudioReady: $_audioReady');
      return;
    }

    switch (_state) {
      case PngPlaybackState.playing:
        debugPrint('PngSeriesAnimator: Resuming Audio');
        _audioPlayer.play();
        _controller.forward();
        break;
      case PngPlaybackState.paused:
      case PngPlaybackState.buffering:
      case PngPlaybackState.seeking:
        debugPrint('PngSeriesAnimator: Pausing Audio (State: $_state)');
        _audioPlayer.pause();
        _controller.stop();
        break;
    }
  }

  Future<void> _resolveAudioSource() async {
    if (widget.audioPath == null) return;

    try {
      final path = widget.audioPath!;
      debugPrint('PngSeriesAnimator: Resolving Audio Source (just_audio): $path');
      if (path.startsWith('http')) {
        await _audioPlayer.setUrl(path);
      } else if (p.isAbsolute(path)) {
        await _audioPlayer.setFilePath(path);
      } else {
        await _audioPlayer.setAsset(path);
      }
      debugPrint('PngSeriesAnimator: Audio Source Set Successfully');
    } catch (e) {
      debugPrint('PngSeriesAnimator: Error loading audio source: $e');
      _audioReady = true; // Proceed without audio if failed
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
        _syncPlayback();
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
      } else if (p.isAbsolute(path)) {
        // Absolute file path from a downloaded bundle
        provider = FileImage(File(path));
      } else {
        // Bundled asset
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
          if (_state == PngPlaybackState.buffering) {
            final int total = widget.imagePaths.length;
            final int currentRequiredFrame = (_controller.value * total).floor().clamp(0, total - 1);
            if (_loadedIndices.contains(currentRequiredFrame)) {
              _updateState(PngPlaybackState.playing);
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
      _updateState(widget.isPlaying ? PngPlaybackState.playing : PngPlaybackState.paused);
    }
    if (oldWidget.repeat != widget.repeat) {
      _syncPlayback();
    }
    
    if (oldWidget.audioPath != widget.audioPath) {
       _audioReady = false;
       _setupAudio();
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


  void _togglePlayPause({bool? manualPlayState}) {
    final bool targetPlay = manualPlayState ?? !_isPlaying;
    _updateState(targetPlay ? PngPlaybackState.playing : PngPlaybackState.paused);
    
    _showOverlayIcon(icon: _isPlaying ? Icons.play_arrow : Icons.pause);
    if (widget.onPlayStateChanged != null) {
      widget.onPlayStateChanged!(_isPlaying);
    }
    _fullScreenEntry?.markNeedsBuild();

    if (_isPlaying) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
      _controlsVisible = true;
    }
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
    final double delta = seconds / _effectiveDuration.inSeconds;
    final double newValue = (_controller.value + delta).clamp(0.0, 1.0);
    _seekTo(newValue);
    _showOverlayIcon(icon: seconds > 0 ? Icons.forward_10 : Icons.replay_10);
    _startHideTimer();
  }

  Future<void> _seekTo(double value, {bool? resume}) async {
    _seekTimer?.cancel();
    final int targetMs = (value * _effectiveDuration.inMilliseconds).toInt();
    final bool shouldResume = resume ?? _isPlaying;
    
    _targetSeekMs = targetMs;
    _lastSeekActionTime = DateTime.now().millisecondsSinceEpoch;
    
    // 1. Instant Visual Jump
    setState(() {
      _controller.value = value;
      _frameIndexNotifier.value = (value * widget.imagePaths.length).floor().clamp(0, widget.imagePaths.length - 1);
      _state = PngPlaybackState.seeking;
      _isPlaying = shouldResume;
    });

    if (widget.audioPath != null) {
      try {
        // 2. Clear hardware state
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration(milliseconds: targetMs));
        
        // 3. Resync and resume
        if (mounted) {
          // In just_audio, we call play() to resume
          if (shouldResume) {
            _audioPlayer.play();
          } else {
            _audioPlayer.pause();
          }
          _updateState(shouldResume ? PngPlaybackState.playing : PngPlaybackState.paused);
        }
      } catch (e) {
        _updateState(shouldResume ? PngPlaybackState.playing : PngPlaybackState.paused);
      }
    } else {
      _updateState(shouldResume ? PngPlaybackState.playing : PngPlaybackState.paused);
    }
    
    if (widget.onSeek != null) {
      widget.onSeek!(value);
    }
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
    
    // Reset to allow all orientations after a frame to let the UI settle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });
    
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
    _seekTimer?.cancel();
    _syncTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _compSub?.cancel();
    _frameIndexNotifier.dispose();
    if (_fullScreenEntry != null) {
      _fullScreenEntry?.remove();
      _fullScreenEntry = null;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    widget.controller?._detach();
    widget.subtitleController?.removeListener(_onSubtitleControllerChanged);
    
    // Hard stop for audio
    _audioPlayer.stop();
    _audioPlayer.dispose();
    
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreenInternal) {
      return SizedBox(
        width: widget.width,
        height: widget.height ?? (widget.showControls ? 40 : 0),
        child: const Center(
          child: Text('Playing in Full Screen', style: TextStyle(color: Colors.grey, fontSize: 10)),
        ),
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
          : ValueListenableBuilder<int>(
              valueListenable: _frameIndexNotifier,
              builder: (context, frameIndex, _) {
                // Buffering Logic: If the current frame isn't loaded yet
                if (!_loadedIndices.contains(frameIndex) && _state == PngPlaybackState.playing) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _state != PngPlaybackState.buffering) {
                      _updateState(PngPlaybackState.buffering);
                      _fullScreenEntry?.markNeedsBuild();
                    }
                  });
                } else if (_state == PngPlaybackState.buffering && _loadedIndices.contains(frameIndex)) {
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _updateState(PngPlaybackState.playing);
                    }
                  });
                }

                Widget imageWidget;
                final totalFrames = widget.imagePaths.length;
                if (totalFrames == 0) {
                  imageWidget = const SizedBox.shrink();
                } else {
                  imageWidget = _buildImage(widget.imagePaths[frameIndex]);
                }

                if (widget.heroTag != null) {
                  imageWidget = Hero(tag: widget.heroTag!, child: imageWidget);
                }

                Widget content = imageWidget;

                // Overlay buffer loader if necessary
                if (_state == PngPlaybackState.buffering) {
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

    return Directionality(
      textDirection: controller.isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 120),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: RichText(
            textAlign: TextAlign.start,
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
        ),
      ),
    );
  }

  Widget _buildVideoControls(bool isFullScreen) {
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
                value: _controller.value.clamp(0.0, 1.0),
                onChangeStart: (val) {
                  _wasPlayingBeforeDrag = _isPlaying;
                  _togglePlayPause(manualPlayState: false);
                  _hideTimer?.cancel();
                },
                onChangeEnd: (val) {
                  _seekTo(val, resume: _wasPlayingBeforeDrag);
                  _startHideTimer();
                },
                onChanged: (val) {
                  _seekTo(val);
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () => _togglePlayPause(),
                ),
                Text(
                  '${_formatDuration(_effectiveDuration * _controller.value)} / ${_formatDuration(_effectiveDuration)}',
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


