#!/bin/zsh
set -eu
PROJECT_DIR="${0:A:h}"
APP_PATH="${1:-${PROJECT_DIR:h}/Fader.app}"
mkdir -p "$PROJECT_DIR/.build" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
xcrun clang++ -std=c++20 -fobjc-arc -O2 -mmacosx-version-min=14.2 -c "$PROJECT_DIR/Sources/FaderAudio.mm" -o "$PROJECT_DIR/.build/FaderAudio.o"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.2 -module-cache-path "$PROJECT_DIR/.build/module-cache" \
  -import-objc-header "$PROJECT_DIR/Sources/FaderAudio.h" \
  "$PROJECT_DIR/Sources/Model.swift" "$PROJECT_DIR/Sources/UI.swift" "$PROJECT_DIR/Sources/Slider.swift" "$PROJECT_DIR/Sources/main.swift" "$PROJECT_DIR/.build/FaderAudio.o" \
  -framework AppKit -framework SwiftUI -framework CoreAudio -framework AudioToolbox -lc++ \
  -o "$APP_PATH/Contents/MacOS/Fader"
/usr/bin/python3 - "$APP_PATH" <<'PY'
import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]); p=app/'Contents/Info.plist'
p.write_bytes(plistlib.dumps(dict(CFBundleName='Fader',CFBundleDisplayName='Fader',CFBundleIdentifier='dev.ybivashhka.fader',CFBundleVersion='1',CFBundleShortVersionString='0.1',CFBundleExecutable='Fader',CFBundlePackageType='APPL',CFBundleIconFile='Fader',LSMinimumSystemVersion='14.2',LSUIElement=True,NSHighResolutionCapable=True,NSAudioCaptureUsageDescription='Fader обрабатывает звук приложений, чтобы отдельно менять их громкость. Звук не записывается и не отправляется в интернет.')))
PY
if [[ -f "$PROJECT_DIR/Resources/Fader.icns" ]]; then cp "$PROJECT_DIR/Resources/Fader.icns" "$APP_PATH/Contents/Resources/Fader.icns"; fi
codesign --force --sign - --identifier dev.ybivashhka.fader "$APP_PATH"
print "Готово: $APP_PATH"
