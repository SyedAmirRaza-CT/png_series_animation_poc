import 'dart:ui';
import 'package:flutter/material.dart';
import 'png_series_animator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PNG Series Animation POC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
      ),
      home: const AnimationShowcaseScreen(),
    );
  }
}

class AnimationShowcaseScreen extends StatefulWidget {
  const AnimationShowcaseScreen({super.key});

  @override
  State<AnimationShowcaseScreen> createState() => _AnimationShowcaseScreenState();
}

class _AnimationShowcaseScreenState extends State<AnimationShowcaseScreen> {
  // Generate the image paths from assets/1/10001.png to assets/1/10018.png
  final List<String> _imagePaths = List.generate(
    18,
    (index) => 'assets/1/${10001 + index}.png',
  );

  double _durationSeconds = 1.5;
  bool _isPlaying = true;
  bool _repeat = true;

  // Dropdown transition selection
  String _selectedTransition = 'None (Default)';

  // Mapping from dropdown strings to actual Transition Builders
  PngSeriesTransitionBuilder? _getTransitionBuilder() {
    switch (_selectedTransition) {
      case 'Quick Crossfade':
        return (context, currentFrame, nextFrame, progress) {
          // Cross-fades frames only at the frame boundary (last 15% of frame duration)
          double nextOpacity = 0.0;
          const double transitionWindow = 0.15;
          if (progress > (1.0 - transitionWindow)) {
            nextOpacity = (progress - (1.0 - transitionWindow)) / transitionWindow;
          }
          return Stack(
            fit: StackFit.passthrough,
            children: [
              currentFrame,
              if (nextOpacity > 0.0)
                Opacity(
                  opacity: nextOpacity,
                  child: nextFrame,
                ),
            ],
          );
        };
      case 'Ghost Trail':
        return (context, currentFrame, nextFrame, progress) {
          // Stacks frames and fades the previous frame out while the new one fades in (ghosting)
          // To prevent background leakage (blackish look), we ensure one frame is always fully solid (1.0).
          final double currentOpacity = progress < 0.5 ? 1.0 : (1.0 - progress) / 0.5;
          final double nextOpacity = progress >= 0.5 ? 1.0 : progress / 0.5;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              if (currentOpacity > 0.0)
                Opacity(
                  opacity: currentOpacity.clamp(0.0, 1.0),
                  child: currentFrame,
                ),
              if (nextOpacity > 0.0)
                Opacity(
                  opacity: nextOpacity.clamp(0.0, 1.0),
                  child: nextFrame,
                ),
            ],
          );
        };
      case 'Horizontal Slide':
        return (context, currentFrame, nextFrame, progress) {
          // Slides out current frame to the left and slides in next frame from the right
          return ClipRect(
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                FractionalTranslation(
                  translation: Offset(-progress, 0.0),
                  child: currentFrame,
                ),
                FractionalTranslation(
                  translation: Offset(1.0 - progress, 0.0),
                  child: nextFrame,
                ),
              ],
            ),
          );
        };
      case 'Vertical Slide':
        return (context, currentFrame, nextFrame, progress) {
          // Slides out current frame upwards and slides in next frame from the bottom
          return ClipRect(
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                FractionalTranslation(
                  translation: Offset(0.0, -progress),
                  child: currentFrame,
                ),
                FractionalTranslation(
                  translation: Offset(0.0, 1.0 - progress),
                  child: nextFrame,
                ),
              ],
            ),
          );
        };
      case 'Scale Zoom':
        return (context, currentFrame, nextFrame, progress) {
          // Zooms next frame in over current frame
          final double scale = 0.85 + (progress * 0.15); // scales 0.85 to 1.0
          return Stack(
            fit: StackFit.passthrough,
            children: [
              currentFrame,
              Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: nextFrame,
                ),
              ),
            ],
          );
        };
      case 'Spin Flip':
        return (context, currentFrame, nextFrame, progress) {
          // Rotates the next frame into view while fading it in
          final double rotationAngle = (1.0 - progress) * -0.25; // rotate from -0.25 rad to 0 rad
          return Stack(
            fit: StackFit.passthrough,
            children: [
              currentFrame,
              Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: rotationAngle,
                  child: nextFrame,
                ),
              ),
            ],
          );
        };
      case 'Blur Dissolve':
        return (context, currentFrame, nextFrame, progress) {
          // Blurs current frame out and blurs next frame in
          final double blurCurrent = progress * 12.0;
          final double blurNext = (1.0 - progress) * 12.0;
          final double currentOpacity = progress < 0.5 ? 1.0 : (1.0 - progress) / 0.5;
          final double nextOpacity = progress >= 0.5 ? 1.0 : progress / 0.5;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              if (currentOpacity > 0.0)
                Opacity(
                  opacity: currentOpacity.clamp(0.0, 1.0),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blurCurrent, sigmaY: blurCurrent),
                    child: currentFrame,
                  ),
                ),
              if (nextOpacity > 0.0)
                Opacity(
                  opacity: nextOpacity.clamp(0.0, 1.0),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blurNext, sigmaY: blurNext),
                    child: nextFrame,
                  ),
                ),
            ],
          );
        };
      case 'None (Default)':
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Slate 900
              Color(0xFF1E1B4B), // Indigo 950
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.movie_filter_rounded, color: Colors.cyan),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PNG Series Animator',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Frame animation with custom builders',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Animated Viewer
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.6), // Slate 800
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyan.withValues(alpha: 0.1),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Checkerboard background for transparency
                            Positioned.fill(
                              child: GridPaper(
                                color: Colors.white.withValues(alpha: 0.02),
                                subdivisions: 1,
                                interval: 30,
                              ),
                            ),
                            Center(
                              child: PngSeriesAnimator(
                                imagePaths: _imagePaths,
                                duration: Duration(
                                  milliseconds: (_durationSeconds * 1000).round(),
                                ),
                                repeat: _repeat,
                                isPlaying: _isPlaying,
                                transitionBuilder: _getTransitionBuilder(),
                                fit: BoxFit.contain,
                                width: 500,
                                height: 500,
                                onCompleted: () {
                                  debugPrint('Showcase screen: onCompleted triggered. Setting _isPlaying = false');
                                  setState(() {
                                    _isPlaying = false;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Controls Panel
              Container(
                margin: const EdgeInsets.all(24.0),
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Playback & Looping Controls
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildControlButton(
                          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          label: _isPlaying ? 'Pause' : 'Play',
                          color: _isPlaying ? Colors.cyan : Colors.green,
                          onPressed: () {
                            setState(() {
                              _isPlaying = !_isPlaying;
                            });
                          },
                        ),
                        _buildControlButton(
                          icon: _repeat ? Icons.loop_rounded : Icons.play_disabled_rounded,
                          label: _repeat ? 'Looping' : 'Once',
                          color: _repeat ? Colors.purpleAccent : Colors.grey,
                          onPressed: () {
                            setState(() {
                              _repeat = !_repeat;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Transition Selector Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.transform_rounded, color: Colors.cyan),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Transition Style',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Selected: $_selectedTransition',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedTransition,
                              dropdownColor: const Color(0xFF0F172A),
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.cyan),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedTransition = newValue;
                                  });
                                }
                              },
                              items: <String>[
                                'None (Default)',
                                'Quick Crossfade',
                                'Ghost Trail',
                                'Horizontal Slide',
                                'Vertical Slide',
                                'Scale Zoom',
                                'Spin Flip',
                                'Blur Dissolve'
                              ].map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Duration Slider
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Animation Cycle Duration',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${_durationSeconds.toStringAsFixed(2)}s',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.cyan,
                            inactiveTrackColor: Colors.cyan.withValues(alpha: 0.2),
                            thumbColor: Colors.cyan,
                            overlayColor: Colors.cyan.withValues(alpha: 0.12),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: _durationSeconds,
                            min: 0.2,
                            max: 5.0,
                            onChanged: (val) {
                              setState(() {
                                _durationSeconds = val;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
