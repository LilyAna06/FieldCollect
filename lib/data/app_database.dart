import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Sync lifecycle for a locally-created record.
enum SyncStatus { pending, syncing, synced, failed }

extension SyncStatusX on SyncStatus {
  String get value => toString().split('.').last;
  static SyncStatus fromValue(String v) =>
      SyncStatus.values.firstWhere((e) => e.value == v, orElse: () => SyncStatus.pending);
}

/// A single field-collected record. Storing the answers as a JSON blob
/// (rather than one SQL column per field) is what lets the form engine stay
/// schema-agnostic — a new monitoring form doesn't require a migration.
class Submission {
  final String id; // client-generated UUID — safe to create offline
  final String formId;
  final int formVersion;
  final Map<String, dynamic> data; // field id -> value
  final double? lat;
  final double? lng;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String deviceId;
  final String? syncError;

  Submission({
    required this.id,
    required this.formId,
    required this.formVersion,
    required this.data,
    this.lat,
    this.lng,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
    required this.deviceId,
    this.syncError,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'form_id': formId,
        'form_version': formVersion,
        'data': jsonEncode(data),
        'lat': lat,
        'lng': lng,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'sync_status': syncStatus.value,
        'device_id': deviceId,
        'sync_error': syncError,
      };

  factory Submission.fromRow(Map<String, dynamic> row) => Submission(
        id: row['id'] as String,
        formId: row['form_id'] as String,
        formVersion: row['form_version'] as int,
        data: jsonDecode(row['data'] as String) as Map<String, dynamic>,
        lat: row['lat'] as double?,
        lng: row['lng'] as double?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        syncStatus: SyncStatusX.fromValue(row['sync_status'] as String),
        deviceId: row['device_id'] as String,
        syncError: row['sync_error'] as String?,
      );

  Submission copyWith({SyncStatus? syncStatus, String? syncError, DateTime? updatedAt}) =>
      Submission(
        id: id,
        formId: formId,
        formVersion: formVersion,
        data: data,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        deviceId: deviceId,
        syncError: syncError ?? this.syncError,
      );
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'field_monitor.db');
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE submissions (
            id TEXT PRIMARY KEY,
            form_id TEXT NOT NULL,
            form_version INTEGER NOT NULL,
            data TEXT NOT NULL,
            lat REAL,
            lng REAL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            device_id TEXT NOT NULL,
            sync_error TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_submissions_sync_status ON submissions(sync_status)');
        await db.execute('CREATE INDEX idx_submissions_form_id ON submissions(form_id)');
      },
    );
  }

  Future<void> upsert(Submission s) async {
    final db = await database;
    await db.insert('submissions', s.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Submission>> all({String? formId}) async {
    final db = await database;
    final rows = await db.query(
      'submissions',
      where: formId != null ? 'form_id = ?' : null,
      whereArgs: formId != null ? [formId] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(Submission.fromRow).toList();
  }

  Future<List<Submission>> pendingSync() async {
    final db = await database;
    final rows = await db.query(
      'submissions',
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: [SyncStatus.pending.value, SyncStatus.failed.value],
    );
    return rows.map(Submission.fromRow).toList();
  }

  Future<void> markStatus(String id, SyncStatus status, {String? error}) async {
    final db = await database;
    await db.update(
      'submissions',
      {
        'sync_status': status.value,
        'sync_error': error,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('submissions', where: 'id = ?', whereArgs: [id]);
  }
}
