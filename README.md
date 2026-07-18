# swar

Swar is a private, offline voice keyboard for macOS and Windows.

## Compatibility

- macOS 10.15 and newer on Intel and Apple Silicon
- Windows 10 version 1809 and newer on x64

See [`docs/compatibility.md`](docs/compatibility.md) for the release matrix and hardware fallback policy.

## Prerequisites

- Flutter 3.35 or newer
- Rust 1.88 or newer
- `flutter_rust_bridge_codegen` 2.12.0

## Generate the bridge

```sh
./scripts/generate_bridge.sh
```

## Verify

```sh
flutter test apps/swar_desktop
cargo test --workspace
```

## GitHub access on restricted laptops

Never save a GitHub token in this repository or paste it into a chat.

Authenticate locally through GitHub CLI:

```sh
./scripts/github_login.sh
```

The token is stored in `~/.swar/.git-credentials` with owner-only permissions. It is separate from Oynix credentials. The fine-grained token needs access to the selected repository, Metadata read permission, and Contents read and write permission.

If normal Git transport is blocked, publish the workspace through the GitHub HTTPS API:

```sh
./scripts/github_api_publish.sh OWNER/REPOSITORY "Initial Swar build"
```

The API publisher creates one commit, does not call `git push`, and respects all `.gitignore` rules.
