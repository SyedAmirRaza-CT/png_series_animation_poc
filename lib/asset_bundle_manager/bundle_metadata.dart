import 'dart:convert';

class BundleMetadata {
  final String bundleId;
  final int version;
  final DateTime downloadedAt;
  final String sourceUrl;
  final int size;

  BundleMetadata({
    required this.bundleId,
    required this.version,
    required this.downloadedAt,
    required this.sourceUrl,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'bundleId': bundleId,
        'version': version,
        'downloadedAt': downloadedAt.toIso8601String(),
        'sourceUrl': sourceUrl,
        'size': size,
      };

  factory BundleMetadata.fromJson(Map<String, dynamic> json) => BundleMetadata(
        bundleId: json['bundleId'],
        version: json['version'],
        downloadedAt: DateTime.parse(json['downloadedAt']),
        sourceUrl: json['sourceUrl'],
        size: json['size'],
      );

  String toRawJson() => json.encode(toJson());

  factory BundleMetadata.fromRawJson(String str) =>
      BundleMetadata.fromJson(json.decode(str));
}
