import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';

/// Watches connectivity and pushes any queued submissions to Supabase.
///
/// Design notes:
/// - Records are created with a client-generated UUID, so upload is a
///   plain upsert — no server-assigned ID round trip needed, and retrying
///   a failed sync never creates duplicates.
/// - One submission fails to sync != the whole batch fails. Each record is
///   pushed independently and marked pending/synced/failed on its own.
/// - Every synced row is tagged with `created_by` (the signed-in user's
///   ID), which is what the tightened RLS policies check against.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _db = AppDatabase.instance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  void start() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        syncNow();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }

  Future<void> syncNow() async {
    if (_syncing) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // Not signed in (or offline before the first-ever sign-in) — nothing
      // to do. Records stay queued locally until the worker signs in.
      _statusController.add('signed_out');
      return;
    }

    _syncing = true;
    _statusController.add('syncing');

    try {
      final pending = await _db.pendingSync();
      if (pending.isEmpty) {
        _statusController.add('idle');
        _syncing = false;
        return;
      }

      final client = Supabase.instance.client;
      var successCount = 0;

      for (final submission in pending) {
        try {
          await _db.markStatus(submission.id, SyncStatus.syncing);

          await client.from('submissions').upsert({
            'id': submission.id,
            'form_id': submission.formId,
            'form_version': submission.formVersion,
            'data': submission.data,
            'lat': submission.lat,
            'lng': submission.lng,
            'created_at': submission.createdAt.toIso8601String(),
            'device_id': submission.deviceId,
            'created_by': user.id,
          });

          await _db.markStatus(submission.id, SyncStatus.synced);
          successCount++;
        } catch (e) {
          await _db.markStatus(submission.id, SyncStatus.failed, error: e.toString());
        }
      }

      _statusController.add('done:$successCount/${pending.length}');
    } finally {
      _syncing = false;
    }
  }
}
