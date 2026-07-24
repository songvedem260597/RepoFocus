# RepoFocus for Windows

Lightweight Windows port of RepoFocus using Tauri 2, React, TypeScript, and a Rust backend.

## Requirements

- Windows 10 (1803+) or Windows 11
- Git for Windows
- WebView2 Runtime (normally included with Windows)
- Optional: GitHub CLI (`gh`) for account sync

## Development

```powershell
npm install
npm run tauri dev
```

## Release build

```powershell
npm run tauri build
```

Outputs:

- Portable executable: `src-tauri/target/release/repofocus.exe`
- NSIS installer: `src-tauri/target/release/bundle/nsis/RepoFocus_*_x64-setup.exe`

## Architecture

- React/TypeScript renders the three-column RepoFocus interface.
- Rust runs local Git commands off the UI thread and persists tracking data under the current user's app-data directory.
- The app uses the system WebView2 runtime, keeping the installer and memory footprint smaller than an Electron bundle.
- Release builds enable LTO, size optimization, panic abort, and symbol stripping.

Personal status, priority, progress, deadlines, notes, and local paths stay on the Windows machine.
