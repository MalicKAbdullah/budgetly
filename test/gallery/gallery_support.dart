import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:core_storage/core_storage.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screen previews only render on request: `GALLERY=out_dir flutter test
/// test/gallery`. Pixels differ per platform, so they are design-review
/// previews, not CI goldens.
final String? galleryOut = Platform.environment['GALLERY'];

final class MemoryVaultFile implements IVaultFile {
  Uint8List? _bytes;
  @override
  Future<Uint8List?> read() async => _bytes;
  @override
  Future<void> write(Uint8List bytes) async => _bytes = bytes;
}

final class MemorySecureStorage implements ISecureStorage {
  final _map = <String, String>{};
  @override
  Future<void> write({required String key, required String value}) async =>
      _map[key] = value;
  @override
  Future<String?> read({required String key}) async => _map[key];
  @override
  Future<void> delete({required String key}) async => _map.remove(key);
  @override
  Future<void> deleteAll() async => _map.clear();
  @override
  Future<Map<String, String>> readAll() async => Map.of(_map);
}

/// The bundled fonts live in the resolved `core_theme` package; test runs do
/// not load package fonts on their own, so text would render as boxes.
Future<void> loadGalleryFonts() async {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  final theme = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == 'core_theme');
  final root = Uri.parse(theme['rootUri'] as String);
  final fonts = Directory.fromUri(
    root.isAbsolute
        ? root
        : Uri.directory(
            Directory.current.path,
          ).resolveUri(Uri.parse('.dart_tool/').resolveUri(root)),
  ).uri.resolve('fonts/').toFilePath();

  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  await family(AppTextStyles.fontFamily, [
    for (final w in weights) '${fonts}MonaSans-$w.ttf',
  ]);
  await family(AppTextStyles.displayFamily, [
    for (final w in weights) '${fonts}MonaSansDisplay-$w.ttf',
  ]);
  await family(AppTextStyles.monoFamily, [
    for (final w in ['Regular', 'Medium', 'SemiBold'])
      '${fonts}MonaSansMono-$w.ttf',
  ]);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      '/Users/abdullah/development/flutter';
  await family('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// An appearance controller loaded from preferences that hold [mode], the
/// way main() loads the owner's saved choice.
Future<AppearanceController> appearanceFor(ThemeMode mode) async {
  SharedPreferences.setMockInitialValues({
    AppearanceController.storageKey: mode.name,
  });
  return AppearanceController.load();
}

/// Pumps one [app] per mode in [modes] side by side at phone size and writes
/// `GALLERY/name.png`. Each pane's app gets a controller loaded with its
/// mode and must bind `themeMode` to it, as BudgetlyApp does; the device
/// itself reports light, so dark panes come from the setting alone.
/// [interact] runs before capture and should act on every pane.
Future<void> renderPanes(
  WidgetTester tester,
  String name,
  Widget Function(AppearanceController appearance) app, {
  List<ThemeMode> modes = const [ThemeMode.light, ThemeMode.dark],
  double width = 390,
  double height = 844,
  EdgeInsets viewInsets = EdgeInsets.zero,
  Widget Function(Widget panes)? wrap,
  Future<void> Function(WidgetTester tester)? interact,
}) async {
  await loadGalleryFonts();
  final n = modes.length;
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size((width * n + 2 * (n - 1)) * 2, height * 2);
  addTearDown(tester.view.reset);

  final controllers = [for (final m in modes) await appearanceFor(m)];
  final key = GlobalKey();
  Widget pane(AppearanceController appearance) => SizedBox(
    width: width,
    height: height,
    child: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        padding: const EdgeInsets.only(top: 24),
        viewPadding: const EdgeInsets.only(top: 24),
        viewInsets: viewInsets,
        disableAnimations: true,
      ),
      child: app(appearance),
    ),
  );

  final panes = Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: const Color(0xFF808080),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, c) in controllers.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              pane(c),
            ],
          ],
        ),
      ),
    ),
  );
  await tester.pumpWidget(wrap == null ? panes : wrap(panes));
  await tester.pumpAndSettle();
  if (interact != null) {
    await interact(tester);
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(galleryOut!).createSync(recursive: true);
    File('$galleryOut/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Pumps [screen] over [data] in light and dark side by side (see
/// [renderPanes]) and writes `GALLERY/name.png`.
Future<void> renderScreen(
  WidgetTester tester,
  String name,
  Widget Function() screen, {
  required AppData data,
  double width = 390,
  double height = 1500,
  Future<void> Function(WidgetTester tester)? interact,
}) async {
  final vault = MemoryVaultFile();
  final storage = MemorySecureStorage();
  List<Override> overrides() => [
    vaultFileProvider.overrideWithValue(vault),
    vaultWorkerProvider.overrideWithValue(<R>(work) async => work()),
    secureStorageProvider.overrideWithValue(storage),
  ];
  final seeding = ProviderContainer(overrides: overrides());
  await seeding.read(budgetlyStoreProvider).save(data);
  seeding.dispose();
  final container = ProviderContainer(overrides: overrides());
  addTearDown(container.dispose);

  await renderPanes(
    tester,
    name,
    (appearance) {
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => screen())],
      );
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: [appearanceProvider.overrideWithValue(appearance)],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.light, accent: AppAccents.budgetly),
          darkTheme: AppTheme.build(
            Brightness.dark,
            accent: AppAccents.budgetly,
          ),
          themeMode: appearance.mode,
          routerConfig: router,
        ),
      );
    },
    width: width,
    height: height,
    wrap: (panes) =>
        UncontrolledProviderScope(container: container, child: panes),
    interact: interact,
  );
  // Let the auto-backup debounce fire so no timer outlives the test.
  await tester.pump(const Duration(seconds: 6));
}
