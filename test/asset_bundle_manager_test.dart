import 'package:flutter_test/flutter_test.dart';
import 'package:png_series_animation_poc/asset_bundle_manager/asset_bundle_manager.dart';

void main() {
  // Note: These tests interact with the filesystem. 
  // In a real CI environment, you might want to mock path_provider.
  
  group('AssetBundleManager Path Logic', () {
    final service = AssetBundleManager();
    const bundleId = 'test_bundle';

    test('getBundlePath returns a path containing bundleId', () async {
      final path = await service.getBundlePath(bundleId);
      expect(path, contains(bundleId));
      expect(path, contains('asset_bundles'));
    });

    test('getFilePath returns path within files subdirectory', () async {
      const relPath = 'images/hero.png';
      final path = await service.getFilePath(bundleId, relPath);
      expect(path, contains(bundleId));
      expect(path, contains('files'));
      expect(path, endsWith(relPath));
    });
  });

  group('AssetBundleManager Existence & Deletion', () {
    final service = AssetBundleManager();
    const bundleId = 'temp_test_bundle';

    test('Initially bundle should not exist', () async {
      final exists = await service.isBundleDownloaded(bundleId);
      expect(exists, isFalse);
    });

    test('deleteBundle handles non-existent bundle gracefully', () async {
      await service.deleteBundle(bundleId);
      expect(true, isTrue); // Should not throw
    });
  });
}
