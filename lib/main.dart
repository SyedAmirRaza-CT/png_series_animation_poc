import 'package:flutter/material.dart';
import 'utils/image_cache_manager.dart';
import 'phases/phase_1_local.dart';
import 'phases/phase_2_network.dart';
import 'phases/phase_3_on_demand.dart';
import 'phases/phase_4_synced_av.dart';
import 'phases/phase_5_subtitles.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PNG Series Animation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PNG Series Animator'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MenuButton(
                title: 'Local Asset Series',
                subtitle: 'Animation from bundled PNGs',
                icon: Icons.folder_open,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LocalAssetDemo()),
                ),
              ),
              const SizedBox(height: 20),
              _MenuButton(
                title: 'Network URL Series',
                subtitle: 'Animation with persistent caching',
                icon: Icons.cloud_download,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NetworkAssetDemo()),
                ),
              ),
              const SizedBox(height: 20),
              _MenuButton(
                title: 'On-Demand Asset Bundles',
                subtitle: 'Download and manage ZIP bundles',
                icon: Icons.inventory_2,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AssetBundleDemo()),
                ),
              ),
              const SizedBox(height: 20),
              _MenuButton(
                title: 'Phase 4: Synced AV',
                subtitle: 'Synced Images & Audio Bundle',
                icon: Icons.sync,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncedPlaybackDemo()),
                ),
              ),
              const SizedBox(height: 20),
              _MenuButton(
                title: 'Phase 5: Subtitles & Highlights',
                subtitle: 'Word-level sync & Multi-language',
                icon: Icons.subtitles,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const Phase5SubtitlesDemo()),
                ),
              ),
              const SizedBox(height: 40),
              TextButton.icon(
                onPressed: () async {
                  await ImageCacheManager().clearCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Persistent storage cleared')),
                    );
                  }
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                label: const Text('Clear Persistent Storage', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: Colors.cyan),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
