# Swar desktop

Flutter presentation layer for Swar on macOS and Windows.

## Run

```sh
flutter pub get
flutter run -d macos
```

Use `-d windows` on a Windows development machine.

## Verify

```sh
flutter analyze
flutter test
```

The app calls `crates/swar_core` through generated `flutter_rust_bridge` bindings. Regenerate them from the repository root with `./scripts/generate_bridge.sh`.
