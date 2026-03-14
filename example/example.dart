// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:just_storage/just_storage.dart';
import 'package:just_storage/ui.dart';

/// Flutter app example demonstrating just_storage and the built-in admin UI.
///
/// Tap "Open Storage Admin" to inspect and edit standard and secure storage
/// entries from a live running app.
void main() {
  runApp(const JustStorageExampleApp());
}

class JustStorageExampleApp extends StatelessWidget {
  const JustStorageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'just_storage example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  JustStandardStorage? _storage;
  JustSecureStorage? _secure;
  String _status = 'Initialising…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final storage = await JustStorage.standard();
    final secure = await JustStorage.encrypted();

    // Seed a few demo values so the admin screen has something to show.
    await storage.write('theme', 'dark');
    await storage.write('language', 'en');
    await secure.write('access_token', 'eyJhbGciOiJIUzI1NiJ9.demo');

    if (mounted) {
      setState(() {
        _storage = storage;
        _secure = secure;
        _status = 'Storage ready';
      });
    }
  }

  void _openAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JUStorageAdminScreen(
          standard: _storage,
          secure: _secure,
        ),
      ),
    );
  }

  Future<void> _runDemo() async {
    if (_storage == null || _secure == null) return;

    // Standard storage
    await _storage!.write('counter', '1');
    final counter = await _storage!.read('counter');

    // Secure storage
    await _secure!.write('pin', '9999');
    final pin = await _secure!.read('pin');

    print('counter: $counter, pin: $pin');

    if (mounted) setState(() => _status = 'Demo values written — open admin to inspect');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('just_storage example')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _storage != null ? _openAdmin : null,
              icon: const Icon(Icons.storage_outlined),
              label: const Text('Open Storage Admin'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _storage != null ? _runDemo : null,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Write demo values'),
            ),
          ],
        ),
      ),
    );
  }
}
