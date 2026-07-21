# RepoFocus

RepoFocus is a local-first macOS app for deciding which GitHub repositories matter now, recording progress, and keeping one clear next action for each repository.

![RepoFocus dashboard](Preview.png)

## Current MVP

- Native three-column macOS interface built with SwiftUI
- Focus, All Repositories, Needs Attention, Completed and Settings views
- Personal status, priority, progress, next action, deadline and notes
- Local JSON persistence in Application Support
- Reuses the signed-in GitHub CLI session without storing a duplicate token
- Paginated GitHub GraphQL sync
- Local Git checks for uncommitted files, commits waiting to push, commits waiting to pull and merge conflicts
- Offline cache and sample workspace
- Light Mode plus a neutral charcoal Dark Mode, with keyboard-friendly custom controls
- Custom app icon and in-app theme/language preferences
- Vietnamese interface written for project-management context, with English available

The app only reads repository data from GitHub. Personal tracking fields remain on this Mac.

## Check local Git status

1. Select a repository.
2. In **Local Git**, paste the path to its cloned folder on this Mac.
3. Choose **Check Git**.

RepoFocus runs read-only `git status` checks. It does not commit, push, pull, fetch or change repository files. Linked repositories are refreshed when the app starts and when the main refresh button is used.

## Run from source

This Mac currently has Swift Command Line Tools but does not have an active full Xcode installation. The app therefore ships as a Swift Package that can be built immediately:

```sh
cd /Users/toiladem/Documents/Codex/2026-07-21/t/outputs/RepoFocus
swift run RepoFocus
```

To build a double-clickable local app bundle:

```sh
cd /Users/toiladem/Documents/Codex/2026-07-21/t/outputs/RepoFocus
./Scripts/package_app.sh
open dist/RepoFocus.app
```

The bundle is ad-hoc signed for local use. It is not notarized for distribution to other Macs.

## Connect GitHub

1. Sign in once with `gh auth login` in Terminal.
2. Open **Settings** in RepoFocus.
3. Choose **Connect current account**.

RepoFocus asks GitHub CLI for the active session when it syncs. It does not write a duplicate token to Keychain, the repository database or logs.

## Local data

Tracking data and the latest GitHub cache are stored at:

```text
~/Library/Application Support/RepoFocus/repositories.json
```

## Verification

```sh
swift build
swift test
```

## Project structure

```text
Sources/RepoFocusCore   Models, persistence, Keychain and GitHub client
Sources/RepoFocus       SwiftUI application and views
Tests                   Core behavior and persistence tests
Scripts                 Local .app packaging
Resources               Bundle metadata
```
