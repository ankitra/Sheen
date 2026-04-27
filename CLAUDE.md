# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sheen is an iOS app that syncs an Obsidian vault to a git repository. Built with SwiftUI + SwiftPM, targeting iOS 17+.

## Build & Develop

**Prerequisites**: Install XcodeGen (`brew install xcodegen`).  

**Build:**
```bash
xcodegen          # generates Sheen.xcodeproj from project.yml
open Sheen.xcodeproj
```
Or build from CLI:
```bash
xcodebuild -scheme Sheen -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild test -scheme Sheen -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Dependencies

- **libgit2-apple** (fork: ankitra/libgit2-apple) — libgit2 C API via CGit module — SPM package
- **KeychainAccess** — secure credential storage — SPM package

## Architecture

```
Sources/Sheen/
├── SheenApp.swift            # @main entry point, routes to Setup or Dashboard
├── Models/
│   ├── AppState.swift        # @Observable state, holds config + shared services
│   ├── RepositoryConfig.swift # vault path, remote URL, branch
│   ├── SyncState.swift        # idle / syncing / success(Date) / error(String)
│   └── FileChange.swift       # detected file changes from vault monitoring
├── Services/
│   ├── GitService.swift       # libgit2 C API wrapper: clone, open, status, commit, push, pull
│   ├── VaultMonitor.swift     # DispatchSource directory monitoring with snapshot diff
│   ├── SyncEngine.swift       # Coordinates monitor + git, auto-sync with debounce
│   └── KeychainManager.swift  # KeychainAccess wrapper for GitHub PAT
├── Views/
│   ├── SetupView.swift        # First-launch onboarding: folder picker, repo URL, PAT
│   ├── DashboardView.swift    # Main screen: sync status, push/pull buttons, activity log
│   └── SettingsView.swift     # Edit config, token management, reset
└── Intents/
    └── AppIntents.swift       # Push, Pull, GetStatus intents for iOS Shortcuts
```

## Sync Flow

1. `VaultMonitor` watches the vault directory via `DispatchSourceFileSystemObject` + snapshot comparison (ignores `.obsidian/` and hidden files)
2. Changes are debounced for 2 seconds (Obsidian saves frequently during edits)
3. `SyncEngine` stages, commits ("Auto-sync: filename"), and pushes to the remote
4. Pull merges remote into local (keeps local version on conflict)
5. GitHub PAT stored in Keychain, used via libgit2 credentials callback (`git_cred_userpass_plaintext_new`)

## Services Lifecycle

- `GitService`, `VaultMonitor`, and `SyncEngine` are created during setup and stored in `AppState`
- `DashboardView` uses `appState.syncEngine` for push/pull (shared instance)
- App Intents create fresh service instances and call `engine.resume()` to open the repo

## Known Caveats

- **Security-scoped bookmarks**: `vaultBookmark` is captured in SetupView but not yet used for persistent access across launches — implement security-scoped bookmark resolution on app launch if needed.
