import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/app_database.dart';
import '../../services/sync_service.dart';
import 'form_screen.dart';
import 'record_list_screen.dart';

/// A schema catalogue entry. Adding a new monitoring type (cultural health,
/// macroinvertebrate counts, etc.) means adding one entry here pointing at
/// a new JSON asset — no new screens required.
class FormCatalogueEntry {
  final String assetPath;
  final String title;
  final String description;
  final IconData icon;
  const FormCatalogueEntry({
    required this.assetPath,
    required this.title,
    required this.description,
    required this.icon,
  });
}

const formCatalogue = <FormCatalogueEntry>[
  FormCatalogueEntry(
    assetPath: 'assets/schemas/rha_v1.json',
    title: 'Rapid Habitat Assessment',
    description: 'Stream reach habitat quality scoring',
    icon: Icons.water,
  ),
  // Next monitoring types get added here as new JSON schemas, e.g.:
  // FormCatalogueEntry(
  //   assetPath: 'assets/schemas/cultural_health_v1.json',
  //   title: 'Cultural Health Index',
  //   description: 'Mana whenua-led site assessment',
  //   icon: Icons.landscape,
  // ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _pendingCount = 0;
  String _syncLabel = 'idle';
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    _refreshPendingCount();
    _syncSub = SyncService.instance.statusStream.listen((status) {
      setState(() => _syncLabel = status);
      _refreshPendingCount();
    });
    // Attempt a sync on open in case records queued up while signed out.
    SyncService.instance.syncNow();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final pending = await AppDatabase.instance.pendingSync();
    if (mounted) setState(() => _pendingCount = pending.length);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          _pendingCount > 0
              ? 'You have $_pendingCount record(s) not yet synced. They\'ll stay saved on '
                  'this device and sync next time you sign in.'
              : 'You can sign back in any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      // AuthGate in main.dart picks up the change automatically.
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field monitoring'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$_pendingCount'),
              isLabelVisible: _pendingCount > 0,
              child: const Icon(Icons.sync),
            ),
            tooltip: 'Sync status: $_syncLabel',
            onPressed: () => SyncService.instance.syncNow(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: email ?? 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (email != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Signed in as $email', style: Theme.of(context).textTheme.bodySmall),
            ),
          Text('New record', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in formCatalogue)
            Card(
              child: ListTile(
                leading: Icon(entry.icon),
                title: Text(entry.title),
                subtitle: Text(entry.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FormScreen(schemaAsset: entry.assetPath)),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text('Records', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('All submissions'),
              subtitle: Text('$_pendingCount pending sync'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordListScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
