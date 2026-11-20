# Just Storage DevTools extension

The Just Storage workbench as a tab in Flutter DevTools: the same screen as
`JustStorageAdminScreen`, on the storages of the app DevTools is connected
to. It talks to the workbench service that just_storage registers when an
app opens its first storage in a debug build (`lib/src/core/workbench_service.dart`).

This app is not published. Its build is: just_storage ships
`extension/devtools/` (this app compiled for the web, plus `config.yaml`), and
DevTools finds it there in every app that depends on just_storage.

## Build

Rebuild after changing the workbench UI, its remote side, or this app, and
before publishing just_storage:

```console
cd devtools_extension
flutter pub get
dart run tool/build.dart
dart run devtools_extensions validate --package=..
```

`tool/build.dart` runs `flutter build web` with the `flutter` on your PATH
(use the Flutter just_storage is tested with) and copies the result to
`../extension/devtools/build`. CanvasKit comes from the build itself, so the
tab works offline; debug symbols and the renderers a JavaScript build never
loads are left out, which keeps the package small. That folder is
git-ignored but published.

## Try it

Run any app that depends on just_storage (by path) in debug mode, open
DevTools from the link `flutter run` prints (or "Dart: Open DevTools" in
VS Code), and choose the **just_storage** tab. DevTools asks once whether to
enable the extension.

If the tab is missing in an app that uses just_storage by path, delete that app's
`.dart_tool/extension_discovery/` folder and reload DevTools. DevTools keeps
the list of the app's extensions there and reads it again only when the
app's `package_config.json` changes, so an extension added to a path
dependency after the list was made goes unseen.

DevTools labels an extension's tab with its package name and allows only
lowercase letters, digits and underscores there, so the tab reads
`just_storage`; the workbench inside it is titled "Just Storage".

While developing this app, run it in the simulated DevTools environment and
paste the VM service URI of a running app:

```console
flutter run -d chrome --dart-define=use_simulated_environment=true
```
