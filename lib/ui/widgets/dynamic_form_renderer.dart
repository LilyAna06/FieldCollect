import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/form_schema.dart';
import '../../services/location_service.dart';

/// Renders any [FormSchema] as a scrollable, sectioned form.
///
/// This is the piece that makes the app extensible: adding a new
/// monitoring type (cultural health, macroinvertebrates, whatever comes
/// next) means authoring a new JSON schema and dropping it in
/// assets/schemas/ — this widget doesn't change.
class DynamicFormRenderer extends StatefulWidget {
  final FormSchema schema;
  final Map<String, dynamic> initialValues;
  final void Function(Map<String, dynamic> values) onChanged;

  const DynamicFormRenderer({
    super.key,
    required this.schema,
    required this.onChanged,
    this.initialValues = const {},
  });

  @override
  State<DynamicFormRenderer> createState() => DynamicFormRendererState();
}

class DynamicFormRendererState extends State<DynamicFormRenderer> {
  late Map<String, dynamic> _values;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.initialValues);
  }

  /// Validates required/required_if fields across the whole schema.
  /// Returns a list of human-readable errors (empty if valid).
  List<String> validate() {
    final errors = <String>[];
    for (final field in widget.schema.allFields) {
      if (field.type == FieldType.computed) continue;
      final visible =
          field.visibleIf == null || evaluateCondition(field.visibleIf!, _values);
      if (!visible) continue;

      final value = _values[field.id];
      final isEmpty = value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is List && value.isEmpty);

      if (field.required && isEmpty) {
        errors.add('"${field.label}" is required');
      }
    }
    return errors;
  }

  void _setValue(String fieldId, dynamic value) {
    setState(() {
      _values[fieldId] = value;
      _recomputeDerivedFields();
    });
    widget.onChanged(_values);
  }

  void _recomputeDerivedFields() {
    for (final field in widget.schema.allFields) {
      if (field.type == FieldType.computed && field.formula != null) {
        _values[field.id] = evaluateFormula(field.formula!, _values);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in widget.schema.sections) ...[
            _SectionHeader(title: section.title),
            for (final field in section.fields) _buildFieldIfVisible(field),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldIfVisible(FormFieldDef field) {
    final visible =
        field.visibleIf == null || evaluateCondition(field.visibleIf!, _values);
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _FieldBuilder(
        field: field,
        value: _values[field.id],
        onChanged: (v) => _setValue(field.id, v),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// Dispatches to the right input widget based on [FormFieldDef.type].
/// This switch is the entire "form catalogue" — every field type the
/// engine supports lives here, once, shared by every schema.
class _FieldBuilder extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic value) onChanged;

  const _FieldBuilder({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.text:
        return _TextInput(field: field, value: value, onChanged: onChanged, maxLines: 1);
      case FieldType.textarea:
        return _TextInput(field: field, value: value, onChanged: onChanged, maxLines: 4);
      case FieldType.number:
        return _NumberInput(field: field, value: value, onChanged: onChanged);
      case FieldType.scale:
        return _ScaleInput(field: field, value: value, onChanged: onChanged);
      case FieldType.selectOne:
        return _SelectOneInput(field: field, value: value, onChanged: onChanged);
      case FieldType.selectMany:
        return _SelectManyInput(field: field, value: value, onChanged: onChanged);
      case FieldType.date:
        return _DateInput(field: field, value: value, onChanged: onChanged);
      case FieldType.geopoint:
        return _GeopointInput(field: field, value: value, onChanged: onChanged);
      case FieldType.photo:
        return _PhotoInput(field: field, value: value, onChanged: onChanged);
      case FieldType.computed:
        return _ComputedDisplay(field: field, value: value);
      case FieldType.geoshape:
      case FieldType.geotrace:
        return _UnsupportedPlaceholder(field: field);
      case FieldType.repeat:
        return _UnsupportedPlaceholder(field: field); // scaffold hook — see README
    }
  }
}

class _TextInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final int maxLines;
  final void Function(dynamic) onChanged;
  const _TextInput({required this.field, required this.value, required this.onChanged, required this.maxLines});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value?.toString(),
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
        helperText: field.hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}

class _NumberInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _NumberInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value?.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
        helperText: field.hint,
        suffixText: field.unit,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) => onChanged(num.tryParse(text)),
    );
  }
}

/// Bounded numeric score (e.g. RHA parameters 1-10 / 1-20) rendered as a
/// slider with the current value shown — quick to fill out one-handed in
/// the field.
class _ScaleInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _ScaleInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final min = (field.min ?? 1).toDouble();
    final max = (field.max ?? 10).toDouble();
    final current = (value is num ? value.toDouble() : min).clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(field.required ? '${field.label} *' : field.label,
                style: Theme.of(context).textTheme.bodyLarge),
            Text(current.round().toString(),
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        if (field.hint != null)
          Text(field.hint!, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: current,
          min: min,
          max: max,
          divisions: (max - min).round(),
          label: current.round().toString(),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

class _SelectOneInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _SelectOneInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value as String?,
      decoration: InputDecoration(
        labelText: field.required ? '${field.label} *' : field.label,
        border: const OutlineInputBorder(),
      ),
      items: (field.options ?? [])
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _SelectManyInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _SelectManyInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = (value as List?)?.cast<String>() ?? <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.required ? '${field.label} *' : field.label,
            style: Theme.of(context).textTheme.bodyLarge),
        Wrap(
          spacing: 8,
          children: (field.options ?? []).map((option) {
            final isSelected = selected.contains(option);
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (sel) {
                final next = List<String>.from(selected);
                sel ? next.add(option) : next.remove(option);
                onChanged(next);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DateInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _DateInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked.toIso8601String().split('T').first);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.required ? '${field.label} *' : field.label,
          border: const OutlineInputBorder(),
        ),
        child: Text(value?.toString() ?? 'Tap to select'),
      ),
    );
  }
}

/// Captures a GPS fix offline — works with no signal, just a GPS lock.
class _GeopointInput extends StatefulWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _GeopointInput({required this.field, required this.value, required this.onChanged});

  @override
  State<_GeopointInput> createState() => _GeopointInputState();
}

class _GeopointInputState extends State<_GeopointInput> {
  bool _loading = false;
  String? _error;

  Future<void> _capture() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await LocationService().getCurrentLocation();
      widget.onChanged({'lat': result.lat, 'lng': result.lng, 'accuracy_m': result.accuracyMeters});
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.value as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.field.required ? '${widget.field.label} *' : widget.field.label,
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _loading ? null : _capture,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location),
          label: Text(point == null ? 'Capture GPS location' : 'Recapture location'),
        ),
        if (point != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${point['lat'].toStringAsFixed(6)}, ${point['lng'].toStringAsFixed(6)}'
              '${point['accuracy_m'] != null ? ' (±${(point['accuracy_m'] as num).toStringAsFixed(0)}m)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}

/// Captures a photo and stores the local file path. The actual bytes stay
/// on-device until sync uploads them to Supabase Storage — see README for
/// the upload hook.
class _PhotoInput extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  final void Function(dynamic) onChanged;
  const _PhotoInput({required this.field, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final paths = (value as List?)?.cast<String>() ?? <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.required ? '${field.label} *' : field.label,
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...paths.map((path) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(path, width: 72, height: 72, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image),
                          )),
                )),
            InkWell(
              onTap: () async {
                final picker = ImagePicker();
                final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600);
                if (photo != null) onChanged([...paths, photo.path]);
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ComputedDisplay extends StatelessWidget {
  final FormFieldDef field;
  final dynamic value;
  const _ComputedDisplay({required this.field, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(field.label, style: Theme.of(context).textTheme.bodyLarge),
          Text(value?.toString() ?? '—', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _UnsupportedPlaceholder extends StatelessWidget {
  final FormFieldDef field;
  const _UnsupportedPlaceholder({required this.field});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${field.label}: field type "${field.type.name}" not yet implemented in this skeleton',
      style: TextStyle(color: Theme.of(context).colorScheme.error, fontStyle: FontStyle.italic),
    );
  }
}
