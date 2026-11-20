// Renders the workbench screenshots in assets/screenshots (README and
// pub.dev): a desktop window in dark (the default) and in light, and three
// phone screens.
//
//   flutter test tool/screenshots_test.dart
//
// It runs as a widget test with the real Roboto and Material Icons fonts
// (from the Flutter SDK) and a monospace font from the system, so text is
// not drawn as test boxes. Add --dart-define=raw=<folder> to also write each
// screen on its own, unframed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_storage/ui.dart';

import '../test/support/memory_storage.dart';

const _out = 'assets/screenshots';
const _raw = String.fromEnvironment('raw');

/// Pixels per logical pixel in the files.
const _scale = 2.0;

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

final _boundary = GlobalKey();

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

Directory _materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) return dir;
  }
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    final fonts = Directory('${dir.path}/material_fonts');
    if (fonts.existsSync()) return fonts;
    dir = dir.parent;
  }
  throw StateError('The Material fonts were not found; set FLUTTER_ROOT.');
}

const _monoFiles = [
  r'C:\Windows\Fonts\consola.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
  '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
  '/Library/Fonts/Courier New.ttf',
];

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final fonts = _materialFonts().path;
  await load('Roboto', [
    for (final w in ['regular', 'medium', 'bold', 'italic', 'mediumitalic'])
      '$fonts/roboto-$w.ttf',
  ]);
  await load('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  // Under the first name the workbench asks for, whichever font it is.
  final mono = _monoFiles.where((f) => File(f).existsSync()).take(1);
  if (mono.isNotEmpty) await load('Consolas', mono);
}

// ---------------------------------------------------------------------------
// Sample data: a small ninja platformer's storages
// ---------------------------------------------------------------------------

const _standard = {
  'player':
      '{"name":"Aria","level":34,"xp":51240,"gold":1830,"skin":"crimson",'
      '"weapon":"moonblade","stats":{"runs":128,"best_combo":47,"deaths":61,'
      '"play_time_s":184260},"unlocked":["dash","wall_jump","shadow_step"]}',
  'settings':
      '{"music":0.6,"sfx":0.8,"vsync":true,"scale":2,"language":"en",'
      '"subtitles":true}',
  'controls':
      '{"jump":"Space","dash":"Shift","attack":"J","throw":"K",'
      '"pause":"Escape"}',
  'levels.unlocked': '["bamboo_forest","moonlit_castle","sky_temple"]',
  'levels.best_times':
      '{"bamboo_forest":95120,"moonlit_castle":141870,"sky_temple":null}',
  'achievements':
      '[{"id":"first_blood","at":"2026-11-02"},'
      '{"id":"no_damage_run","at":"2026-11-14"},'
      '{"id":"combo_40","at":"2026-11-19"}]',
  'last_level': 'moonlit_castle',
  'last_played': '2026-11-20T09:41:00Z',
  'launch_count': '42',
  'tutorial_done': 'true',
  'news_seen': '2026.11.2',
  'window': '{"width":1600,"height":900,"fullscreen":false}',
};

const _secure = {
  'auth.token':
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwbGF5ZXItNDIiLCJleHAiOjE3OTU2NTEyMDB9'
      '.k3XqvR0yQe8m2HfJt9Wc4LbZ1sNpUo7aGdV5xYi6TrE',
  'auth.refresh': 'rt_7Q2mX9vKp4LwZs8NdE3fHjC6bYtR1uGa',
  'account':
      '{"id":"player-42","email":"aria@example.com","region":"eu-west",'
      '"linked":["steam"],"newsletter":false}',
  'purchases':
      '[{"sku":"skin.crimson","price":"2.99 EUR","at":"2026-10-30"},'
      '{"sku":"pack.sky_temple","price":"4.99 EUR","at":"2026-11-12"}]',
  'cloud_save.key': 'q8Zt3yN1cV0rB6mW2xK9pL5sD7fH4jG0aE2uI8oT1wQ=',
  'parental_pin': '4821',
};

String _slot(String level, int checkpoint, int hp, String time, int gold) =>
    '{"level":"$level","checkpoint":$checkpoint,"hp":$hp,"time":"$time",'
    '"gold":$gold,"inventory":[{"item":"shuriken","qty":24},'
    '{"item":"smoke_bomb","qty":3},{"item":"healing_potion","qty":2}],'
    '"saved_at":"2026-11-20T09:3$checkpoint:00Z"}';

final _saves = {
  'slot_1': _slot('moonlit_castle', 3, 72, '05:41:12', 1830),
  'slot_2': _slot('bamboo_forest', 5, 100, '02:10:47', 640),
  'slot_3': _slot('sky_temple', 1, 38, '07:02:31', 2115),
  'autosave': _slot('moonlit_castle', 4, 65, '05:44:03', 1852),
  'slots.last_used': 'slot_1',
};

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

/// The app gives the workbench its font and [platform] (a desktop's density
/// and mouse-style text selection, or a phone's); the colours are the
/// workbench's.
Widget _app(StorageAdminController c, TargetPlatform platform) =>
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Roboto', platform: platform),
        home: JustStorageAdminScreen(controller: c),
      ),
    );

Future<ui.Image> _grab(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: _scale),
  ))!;
  if (_raw.isNotEmpty) await _write(tester, image, '$_raw/$name.png');
  return image;
}

Future<void> _write(WidgetTester tester, ui.Image image, String path) async {
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// [shots] side by side on a transparent background, with rounded corners
/// and a soft shadow; [phone] adds a phone's bezel. A window's edge is
/// outlined, lightly when the shots are [dark].
Future<ui.Image> _frame(
  WidgetTester tester,
  List<ui.Image> shots, {
  required bool phone,
  bool dark = false,
}) async {
  const s = _scale;
  const pad = 20 * s;
  const gap = 36 * s;
  final bezel = phone ? 9 * s : 0.0;
  final screenRadius = (phone ? 34 : 10) * s;
  final w = shots.first.width.toDouble();
  final h = shots.first.height.toDouble();
  final frameW = w + 2 * bezel;
  final frameH = h + 2 * bezel;
  final width = 2 * pad + shots.length * frameW + (shots.length - 1) * gap;
  final height = 2 * pad + frameH;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var i = 0; i < shots.length; i++) {
    final frame = Rect.fromLTWH(pad + i * (frameW + gap), pad, frameW, frameH);
    final outer = RRect.fromRectAndRadius(
      frame,
      Radius.circular(screenRadius + bezel),
    );
    canvas.drawShadow(
      Path()..addRRect(outer),
      const Color(0xFF000000),
      6 * s,
      false,
    );
    if (phone) {
      canvas.drawRRect(outer, Paint()..color = const Color(0xFF1D1B20));
    }
    final screen = RRect.fromRectAndRadius(
      frame.deflate(bezel),
      Radius.circular(screenRadius),
    );
    canvas
      ..save()
      ..clipRRect(screen)
      ..drawImage(shots[i], screen.outerRect.topLeft, Paint())
      ..restore();
    if (!phone) {
      canvas.drawRRect(
        screen,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s
          ..color = dark ? const Color(0x2EFFFFFF) : const Color(0x24000000),
      );
    }
  }
  final picture = recorder.endRecording();
  return (await tester.runAsync(
    () => picture.toImage(width.round(), height.round()),
  ))!;
}

void _useWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// The shots
// ---------------------------------------------------------------------------

void main() {
  late MemoryStandardStorage standard;
  late MemorySecureStorage secure;
  late MemoryStandardStorage saves;

  setUp(() {
    standard = MemoryStandardStorage()..values.addAll(_standard);
    secure = MemorySecureStorage()..values.addAll(_secure);
    saves = MemoryStandardStorage()..values.addAll(_saves);
  });

  StorageAdminController controller() => StorageAdminController(
    stores: [
      StorageAdminStore(
        'Standard',
        standard,
        description: 'JustStorage.standard(): plain values',
      ),
      StorageAdminStore(
        'Secure',
        secure,
        description: 'JustStorage.encrypted(): AES-256-GCM',
      ),
      StorageAdminStore(
        'Game saves',
        saves,
        description: 'One entry per save slot',
      ),
    ],
  );

  testWidgets('desktop', (tester) async {
    debugDisableShadows = false; // real shadows instead of black outlines
    await tester.runAsync(_loadFonts);
    _useWindow(tester, _desktop);
    final c = controller();
    await tester.pumpWidget(_app(c, TargetPlatform.windows));
    await tester.pumpAndSettle();

    // Dark: an entry as a JSON tree, and a value the game just wrote.
    await _tapKey(tester, 'jst-entry-player');
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'jst-tree-expand');
    await standard.write('last_played', '2026-11-20T09:44:12Z');
    final dark = await _grab(tester, 'desktop_tree');
    await _write(
      tester,
      await _frame(tester, [dark], phone: false, dark: true),
      '$_out/workbench_desktop.png',
    );

    // Light: the user's pick (the app bar's button). The secure storage
    // with its values shown, editing one.
    c.setThemeMode(ThemeMode.light);
    await _tapKey(tester, 'jst-store-Secure');
    await _tapKey(tester, 'jst-toggle-values');
    await _tapKey(tester, 'jst-entry-account');
    await _tapKey(tester, 'jst-value-edit');
    await tester.tap(find.text('Format'));
    final light = await _grab(tester, 'desktop_edit_light');
    await _write(
      tester,
      await _frame(tester, [light], phone: false),
      '$_out/workbench_desktop_light.png',
    );

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    debugDisableShadows = true; // checked before tear-downs run
  });

  testWidgets('phone', (tester) async {
    debugDisableShadows = false; // real shadows instead of black outlines
    await tester.runAsync(_loadFonts);
    _useWindow(tester, _phone);
    final c = controller();
    await tester.pumpWidget(_app(c, TargetPlatform.android));
    await tester.pumpAndSettle();
    final home = await _grab(tester, 'phone_home');

    await _tapKey(tester, 'jst-store-Game saves');
    final entries = await _grab(tester, 'phone_entries');

    await _tapKey(tester, 'jst-entry-slot_1');
    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'jst-tree-expand');
    final value = await _grab(tester, 'phone_value');

    await _write(
      tester,
      await _frame(tester, [home, entries, value], phone: true, dark: true),
      '$_out/workbench_phone.png',
    );

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    debugDisableShadows = true; // checked before tear-downs run
  });
}
