#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
APP_DIRECTORY="${PROJECT_DIRECTORY}/dist/RepoFocus.app"
APP_EXECUTABLE="${APP_DIRECTORY}/Contents/MacOS/RepoFocus"
STAGING_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/repofocus-package.XXXXXX")"
STAGED_APP_DIRECTORY="${STAGING_DIRECTORY}/RepoFocus.app"
PREVIOUS_APP_DIRECTORY="${STAGING_DIRECTORY}/Previous RepoFocus.app"

cleanup() {
    rm -rf "${STAGING_DIRECTORY}"
}
trap cleanup EXIT

cd "${PROJECT_DIRECTORY}"
swift build -c release

mkdir -p "${STAGED_APP_DIRECTORY}/Contents/MacOS"
mkdir -p "${STAGED_APP_DIRECTORY}/Contents/Resources"

cp "${PROJECT_DIRECTORY}/.build/release/RepoFocus" "${STAGED_APP_DIRECTORY}/Contents/MacOS/RepoFocus"
cp "${PROJECT_DIRECTORY}/Resources/Info.plist" "${STAGED_APP_DIRECTORY}/Contents/Info.plist"
cp "${PROJECT_DIRECTORY}/Resources/AppIcon.icns" "${STAGED_APP_DIRECTORY}/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "${STAGED_APP_DIRECTORY}"
codesign --verify --deep --strict "${STAGED_APP_DIRECTORY}"

was_running=false
if pgrep -f "${APP_EXECUTABLE}" >/dev/null; then
    was_running=true
    osascript -e 'tell application id "com.repofocus.desktop" to quit' >/dev/null 2>&1 || true

    for _ in {1..80}; do
        if ! pgrep -f "${APP_EXECUTABLE}" >/dev/null; then
            break
        fi
        sleep 0.1
    done

    if pgrep -f "${APP_EXECUTABLE}" >/dev/null; then
        for process_id in $(pgrep -f "${APP_EXECUTABLE}"); do
            kill -TERM "${process_id}"
        done
        for _ in {1..40}; do
            if ! pgrep -f "${APP_EXECUTABLE}" >/dev/null; then
                break
            fi
            sleep 0.1
        done
    fi

    if pgrep -f "${APP_EXECUTABLE}" >/dev/null; then
        echo "RepoFocus is still running. Quit the app, then package again." >&2
        exit 1
    fi
fi

mkdir -p "${PROJECT_DIRECTORY}/dist"
if [[ -d "${APP_DIRECTORY}" ]]; then
    mv "${APP_DIRECTORY}" "${PREVIOUS_APP_DIRECTORY}"
fi

if ! mv "${STAGED_APP_DIRECTORY}" "${APP_DIRECTORY}"; then
    if [[ -d "${PREVIOUS_APP_DIRECTORY}" ]]; then
        mv "${PREVIOUS_APP_DIRECTORY}" "${APP_DIRECTORY}"
    fi
    exit 1
fi

codesign --verify --deep --strict "${APP_DIRECTORY}"

if [[ "${was_running}" == true ]]; then
    open "${APP_DIRECTORY}"
fi

echo "Packaged ${APP_DIRECTORY}"
