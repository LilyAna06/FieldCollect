/// Core model for the dynamic form engine.
///
/// A [FormSchema] is parsed from a JSON document (see
/// assets/schemas/rha_v1.json for a full example). The app never hardcodes
/// screens for a particular survey — every field, section, validation rule
/// and piece of conditional logic comes from this schema, so adding a new
/// monitoring type (cultural health, macroinvertebrate counts, etc.) is a
/// matter of authoring a new JSON file, not writing new Dart code.

enum FieldType {
  text,
  textarea,
  number,
  date,
  selectOne,
  selectMany,
  scale, // bounded numeric score, e.g. 1-10, rendered as a slider — best for genuinely continuous/graphical scales
  categoryScore, // discrete labeled options (e.g. "0%", "5%", "10%"...) each mapped to a fixed score — rendered as tappable buttons
  geopoint,
  geoshape, // polygon
  geotrace, // line / track
  photo,
  computed, // derived, read-only value (e.g. sum of other fields)
  repeat; // repeating group of sub-fields (e.g. "add another transect")

  static FieldType fromJson(String value) {
    switch (value) {
      case 'text':
        return FieldType.text;
      case 'textarea':
        return FieldType.textarea;
      case 'number':
        return FieldType.number;
      case 'date':
        return FieldType.date;
      case 'select_one':
        return FieldType.selectOne;
      case 'select_many':
        return FieldType.selectMany;
      case 'scale':
        return FieldType.scale;
      case 'category_score':
        return FieldType.categoryScore;
      case 'geopoint':
        return FieldType.geopoint;
      case 'geoshape':
        return FieldType.geoshape;
      case 'geotrace':
        return FieldType.geotrace;
      case 'photo':
        return FieldType.photo;
      case 'computed':
        return FieldType.computed;
      case 'repeat':
        return FieldType.repeat;
      default:
        throw FormatException('Unknown field type "$value" in form schema');
    }
  }
}

/// A single tappable option for a [FieldType.categoryScore] field —
/// e.g. label "20%" mapping to score 6.
class CategoryOption {
  final String label;
  final num score;
  CategoryOption({required this.label, required this.score});

  factory CategoryOption.fromJson(Map<String, dynamic> json) => CategoryOption(
        label: json['label'].toString(),
        score: json['score'] as num,
      );
}

class FormFieldDef {
  final String id;
  final FieldType type;
  final String label;
  final String? hint;
  final bool required;

  /// select_one / select_many options.
  final List<String>? options;

  /// scale / number bounds.
  final num? min;
  final num? max;

  /// category_score options, in display order.
  final List<CategoryOption>? categories;

  /// Simple conditional-visibility expression, e.g. "habitat_type == 'forest'".
  /// Evaluated against the current record's field values.
  final String? visibleIf;

  /// For [FieldType.computed]: a formula like "sum:p1,p2,p3,p4,p5,p6,p7,p8,p9".
  final String? formula;

  /// For [FieldType.repeat]: the field definitions inside each repetition.
  final List<FormFieldDef>? children;

  /// Optional unit label shown next to numeric/scale fields, e.g. "%", "m".
  final String? unit;

  FormFieldDef({
    required this.id,
    required this.type,
    required this.label,
    this.hint,
    this.required = false,
    this.options,
    this.min,
    this.max,
    this.categories,
    this.visibleIf,
    this.formula,
    this.children,
    this.unit,
  });

  factory FormFieldDef.fromJson(Map<String, dynamic> json) {
    return FormFieldDef(
      id: json['id'] as String,
      type: FieldType.fromJson(json['type'] as String),
      label: json['label'] as String? ?? json['id'] as String,
      hint: json['hint'] as String?,
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
      min: json['min'] as num?,
      max: json['max'] as num?,
      categories: (json['categories'] as List?)
          ?.map((e) => CategoryOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      visibleIf: json['visible_if'] as String?,
      formula: json['formula'] as String?,
      unit: json['unit'] as String?,
      children: (json['fields'] as List?)
          ?.map((e) => FormFieldDef.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FormSectionDef {
  final String id;
  final String title;
  final List<FormFieldDef> fields;

  FormSectionDef({required this.id, required this.title, required this.fields});

  factory FormSectionDef.fromJson(Map<String, dynamic> json) {
    return FormSectionDef(
      id: json['id'] as String,
      title: json['title'] as String,
      fields: (json['fields'] as List)
          .map((e) => FormFieldDef.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Flattened list of every non-repeat field in this section, used for
  /// validation and computed-field resolution.
  List<FormFieldDef> get allFields => fields;
}

class FormSchema {
  final String formId;
  final int version;
  final String title;
  final String? description;
  final List<FormSectionDef> sections;

  FormSchema({
    required this.formId,
    required this.version,
    required this.title,
    this.description,
    required this.sections,
  });

  factory FormSchema.fromJson(Map<String, dynamic> json) {
    return FormSchema(
      formId: json['form_id'] as String,
      version: json['version'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      sections: (json['sections'] as List)
          .map((e) => FormSectionDef.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  List<FormFieldDef> get allFields =>
      sections.expand((s) => s.fields).toList();
}

/// Evaluates the small conditional-logic language used by `visible_if` /
/// `required_if`. Supports: field == 'value', field != 'value',
/// field > number, field < number, field >= number, field <= number.
/// Intentionally minimal — extend here (not per-screen) as new monitoring
/// forms need richer conditions.
bool evaluateCondition(String expression, Map<String, dynamic> values) {
  final ops = ['>=', '<=', '==', '!=', '>', '<'];
  for (final op in ops) {
    if (expression.contains(op)) {
      final parts = expression.split(op);
      if (parts.length != 2) continue;
      final fieldId = parts[0].trim();
      var rawTarget = parts[1].trim();
      final actual = values[fieldId];

      if (rawTarget.startsWith("'") && rawTarget.endsWith("'")) {
        final target = rawTarget.substring(1, rawTarget.length - 1);
        final actualStr = actual?.toString() ?? '';
        switch (op) {
          case '==':
            return actualStr == target;
          case '!=':
            return actualStr != target;
        }
      } else {
        final target = num.tryParse(rawTarget);
        final actualNum = actual is num ? actual : num.tryParse(actual?.toString() ?? '');
        if (target == null || actualNum == null) return false;
        switch (op) {
          case '>=':
            return actualNum >= target;
          case '<=':
            return actualNum <= target;
          case '>':
            return actualNum > target;
          case '<':
            return actualNum < target;
          case '==':
            return actualNum == target;
          case '!=':
            return actualNum != target;
        }
      }
    }
  }
  // Unrecognised expression: fail open (show the field) rather than hide
  // data the field worker might need.
  return true;
}

/// Resolves a `formula` string for computed fields. Currently supports
/// "sum:id1,id2,id3" and "avg:id1,id2,id3". Extend as needed.
num? evaluateFormula(String formula, Map<String, dynamic> values) {
  final parts = formula.split(':');
  if (parts.length != 2) return null;
  final op = parts[0];
  final ids = parts[1].split(',').map((e) => e.trim());

  final nums = ids
      .map((id) => values[id])
      .where((v) => v != null)
      .map((v) => v is num ? v : num.tryParse(v.toString()))
      .whereType<num>()
      .toList();

  if (nums.isEmpty) return null;

  switch (op) {
    case 'sum':
      return nums.fold<num>(0, (a, b) => a + b);
    case 'avg':
      return nums.fold<num>(0, (a, b) => a + b) / nums.length;
    default:
      return null;
  }
}
