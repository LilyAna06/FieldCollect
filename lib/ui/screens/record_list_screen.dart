import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/app_database.dart';

class RecordListScreen extends StatefulWidget {
  const RecordListScreen({super.key});

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  List<Submission> _submissions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppDatabase.instance.all();
    setState(() => _submissions = all);
  }

  Color _statusColor(SyncStatus s, BuildContext context) {
    switch (s) {
      case SyncStatus.synced:
        return Colors.green;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.failed:
        return Theme.of(context).colorScheme.error;
      case SyncStatus.pending:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _submissions.isEmpty
            ? const Center(child: Text('No records yet'))
            : ListView.builder(
                itemCount: _submissions.length,
                itemBuilder: (context, i) {
                  final s = _submissions[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _statusColor(s.syncStatus, context),
                      radius: 6,
                    ),
                    title: Text(s.formId),
                    subtitle: Text(DateFormat.yMMMd().add_jm().format(s.createdAt)),
                    trailing: Text(s.syncStatus.value),
                  );
                },
              ),
      ),
    );
  }
}
