import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/sync_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';

// TODO: move these to --dart-define / a .env file before committing real
// values. Placeholder keys here so the skeleton compiles out of the box.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://YOUR-PROJECT.supabase.co');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  SyncService.instance.start();

  runApp(const FieldMonitorApp());
}

class FieldMonitorApp extends StatelessWidget {
  const FieldMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field Monitor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)), // teal, ecological
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows [LoginScreen] when there's no active session, [HomeScreen] once
/// signed in. Supabase persists sessions locally, so a field worker who
/// signed in once stays signed in across app restarts — including offline
/// — until they explicitly sign out.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;

  @override
  void initState() {
    super.initState();
    // Pick up whatever session Supabase already restored from local
    // storage (may be null if never signed in, or if signed out).
    _session = Supabase.instance.client.auth.currentSession;

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() => _session = data.session);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _session == null ? const LoginScreen() : const HomeScreen();
  }
}
