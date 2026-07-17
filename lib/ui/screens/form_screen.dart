import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';
import '../../data/app_database.dart';
import '../../models/form_schema.dart';
import '../../services/sync_service.dart';
import '../widgets/dynamic_form_renderer.dart';

class FormScreen extends StatefulWidget {
  final String schemaAsset;
  const FormScreen({super.key, required this.schemaAsset});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  FormSchema? _schema;
  Map<String, dynamic> _values = {};
  final _rendererKey = GlobalKey<DynamicFormRendererState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  Future<void> _loadSchema() async {
    final raw = await rootBundle.loadString(widget.schemaAsset);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    setState(() => _schema = FormSchema.fromJson(json));
  }

  Future<void> _save() async {
    final rendererState = _rendererKey.currentState;
    if (rendererState == null || _schema == null) return;

    final errors = rendererState.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errors.first)),
      );
      return;
    }

    setState(() => _saving = true);

    // Pull top-level site geopoint if the schema captured one under a
    // conventional field id, so records are queryable spatially without
    // digging into the JSON blob.
    final geopointField = _values.values.firstWhere(
      (v) => v is Map && v.containsKey('lat') && v.containsKey('lng'),
      orElse: () => null,
    );

    final submission = Submission(
      id: const Uuid().v4(),
      formId: _schema!.formId,
      formVersion: _schema!.version,
      data: _values,
      lat: geopointField != null ? (geopointField['lat'] as num).toDouble() : null,
      lng: geopointField != null ? (geopointField['lng'] as num).toDouble() : null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: SyncStatus.pending,
      deviceId: 'device-placeholder', // TODO: persist a stable per-install device id
    );

    await AppDatabase.instance.upsert(submission);
    // Fire-and-forget: succeeds silently if online, queues quietly if not.
    SyncService.instance.syncNow();

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved locally — will sync when online')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_schema == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_schema!.title),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
            tooltip: 'Save record',
          ),
        ],
      ),
      body: DynamicFormRenderer(
        key: _rendererKey,
        schema: _schema!,
        onChanged: (values) => _values = values,
      ),
    );
  }
}
