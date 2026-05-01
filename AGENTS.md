# AGENTS.md

## Repository Overview

This is a multi-project personal repository ("sunfu") with three independent projects on separate branches:

| Branch | Project | Tech Stack |
|--------|---------|------------|
| `cursor/qdrant-805e` | Qdrant Knowledge Base Skill | Python 3.12+, qdrant-client |
| `cursor/offline-game-md-f6aa` | 2048 Solo Mobile Game | Flutter (Dart), Android |
| `cursor/polish-dunhuang-script-fc5a` | Dunhuang Storyboard Scripts | Pure Markdown (no code) |

The `main` branch is essentially empty (just a README placeholder).

## Cursor Cloud specific instructions

### Branch-based workflow

All code lives on feature branches — checkout the relevant branch before working. Use `git worktree` for simultaneous multi-branch work.

### Qdrant Knowledge Skill (`cursor/qdrant-805e`)

- **Dependencies**: `pip install -r requirements.txt` (installs `qdrant-client>=1.12.0`)
- **Lint**: No linter configured; use standard Python style checks (`python3 -m py_compile qdrant_skill.py text_splitter.py`)
- **Tests**: `python3 test_qdrant_skill.py` — requires network access to remote Qdrant at `101.132.184.213:6333`
- **Caveat**: The `store_knowledge` test may timeout on slow/high-latency connections because it sends 1024-dim vectors to the remote server. The read-only tests (list collections, browse knowledge) are reliable.
- **No virtual env needed**: Dependencies install globally with pip in the Cloud VM.

### 2048 Flutter Game (`cursor/offline-game-md-f6aa`)

- **Flutter SDK**: Installed at `/opt/flutter` (added to PATH via `~/.bashrc`). Version 3.41.x (Dart 3.11.x) satisfies `sdk: ^3.11.4`.
- **Dependencies**: `flutter pub get` in the `game_app/` directory
- **Lint**: `flutter analyze` in `game_app/` — should report "No issues found!"
- **Tests**: `flutter test` in `game_app/` — 6 unit tests for game logic
- **Build (web demo)**: The app is Android-first. To demo in Cloud VM, enable web platform with `flutter create . --platforms web` then `flutter build web --release`. Serve with `python3 -m http.server 8080 --directory build/web`.
- **Build (Android)**: Requires Android SDK (not installed in Cloud VM by default). Use `flutter build apk` when Android SDK is available.
- **Caveat**: `flutter create . --platforms web` modifies the project to add web support — do not commit these changes back to the game branch unless intended.

### Dunhuang Scripts (`cursor/polish-dunhuang-script-fc5a`)

Pure Markdown content — no build, lint, or test steps needed.
