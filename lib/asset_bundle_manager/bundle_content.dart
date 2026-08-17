class BundleContent {
  final List<String> images;
  final List<String> audio;
  final List<String> subtitles;
  final List<String> videos;

  BundleContent({
    required this.images,
    required this.audio,
    required this.subtitles,
    required this.videos,
  });

  bool get isEmpty =>
      images.isEmpty && audio.isEmpty && subtitles.isEmpty && videos.isEmpty;

  bool get hasImages => images.isNotEmpty;
  bool get hasAudio => audio.isNotEmpty;
  bool get hasSubtitles => subtitles.isNotEmpty;
  bool get hasVideos => videos.isNotEmpty;
}
