#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
APP_DIRECTORY="${PROJECT_DIRECTORY}/dist/RepoFocus.app"

cd "${PROJECT_DIRECTORY}"
swift build -c release

mkdir -p "${APP_DIRECTORY}/Contents/MacOS"
mkdir -p "${APP_DIRECTORY}/Contents/Resources"

cp "${PROJECT_DIRECTORY}/.build/release/RepoFocus" "${APP_DIRECTORY}/Contents/MacOS/RepoFocus"
cp "${PROJECT_DIRECTORY}/Resources/Info.plist" "${APP_DIRECTORY}/Contents/Info.plist"
cp "${PROJECT_DIRECTORY}/Resources/AppIcon.icns" "${APP_DIRECTORY}/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "${APP_DIRECTORY}"

echo "Packaged ${APP_DIRECTORY}"
