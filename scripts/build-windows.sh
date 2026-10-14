#!/bin/bash
# Builds DigUp for Windows 10 and 11 (x64): build.noindex/windows/DigUp-<version>-setup.exe, a per-user NSIS installer
# (no administrator needed) holding the shell (shell/, Tauri) and, in its helper\ folder, DigUp's helper `digup.exe`
# with everything it loads: llama.cpp and ggml's backends (the CPU variants and Vulkan, which runs on integrated
# graphics too), PDFium, the Swift runtime, the Visual C++ runtime, and ffmpeg/ffprobe for audio and video.
#
# Run it in Git for Windows' bash inside the MSVC environment (an "x64 Native Tools Command Prompt", then `bash`), with
# on PATH: Swift 6.2 or later, Rust (MSVC), Node.js (for the Tauri CLI, through npx), CMake and Ninja, Python 3, and the
# Vulkan SDK (VULKAN_SDK set and its Bin\ on PATH: llama.cpp compiles its Vulkan shaders with glslc).
#   scripts/build-windows.sh                   the installer
#   LLAMA_GPU=cpu scripts/build-windows.sh     without the Vulkan backend (no SDK needed; indexing then runs on the
#                                              processor alone)
#   VERSION=1.2.3 scripts/build-windows.sh     another version than Resources/Info.plist's
# .github/workflows/windows.yml runs it on GitHub's Windows machines. The installer isn't code-signed: Windows'
# SmartScreen asks once ("More info", then "Run anyway").
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *) echo "build-windows.sh runs on Windows, in Git for Windows' bash" >&2; exit 1 ;;
esac
: "${VCToolsRedistDir:?run this inside the MSVC environment (vcvars64.bat, or an x64 Native Tools prompt)}"
VERSION="${VERSION:-$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)}"
TAURI_CLI=2.12.2         # @tauri-apps/cli, the same 2.x line as the shell's tauri crate
# ffmpeg, LGPL, as DLLs (BtbN/FFmpeg-Builds): LGPL keeps DigUp's own license free of copyleft. The newest release branch
# it builds, unless FFMPEG_ZIP names a zip: its "latest" builds are rebuilt with each branch's fixes, and old branches
# drop out, so the one used and its checksum are logged rather than pinned. GH_TOKEN, when set, is used for the lookup.
FFMPEG_RELEASE=https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/tags/latest
OUT=build.noindex/windows
HELPER=shell/src-tauri/helper   # what the installer puts in helper\ (tauri.windows.conf.json)

# The engine's C libraries, then llama.cpp: Vulkan unless told otherwise (releases always have it).
scripts/fetch-vendor.sh
LLAMA_GPU="${LLAMA_GPU:-vulkan}" scripts/build-llama.sh
echo "llama.cpp: $(cat Vendor/llama/BUILD)"

swift build -c release --product digup
BIN_DIR="$(swift build -c release --show-bin-path)"

# The helper folder: digup.exe and every DLL it loads (or ggml loads beside it), nothing from PATH.
rm -rf "$HELPER" && mkdir -p "$HELPER"
cp "$BIN_DIR/digup.exe" "$HELPER/"
cp Vendor/llama/lib/*.dll "$HELPER/"          # llama, mtmd, ggml, ggml-base, ggml-cpu-* and ggml-vulkan
cp Vendor/pdfium/bin/pdfium.dll "$HELPER/"
# The Swift runtime: the folder on PATH with swiftCore.dll that isn't the toolchain's own (that one has swiftc.exe).
SWIFT_RUNTIME=""
IFS=: read -ra FOLDERS <<< "$PATH"
for folder in "${FOLDERS[@]}"; do
  if [[ -f "$folder/swiftCore.dll" && ! -f "$folder/swiftc.exe" ]]; then SWIFT_RUNTIME="$folder"; break; fi
done
[[ -n "$SWIFT_RUNTIME" ]] || { echo "no Swift runtime (swiftCore.dll) on PATH" >&2; exit 1; }
echo "Swift runtime: $SWIFT_RUNTIME"
cp "$SWIFT_RUNTIME"/*.dll "$HELPER/"
# The Visual C++ runtime, beside the programs that need it (Windows doesn't always have it, and Microsoft allows this
# app-local copy of the files in VC\Redist).
cp "$(cygpath -u "$VCToolsRedistDir")"/x64/Microsoft.VC*.CRT/*.dll "$HELPER/"

PYTHON=python3
python3 -c 'import zipfile' 2>/dev/null || PYTHON=python   # "python3" can be the Microsoft Store's stub
if [[ -z "${FFMPEG_ZIP:-}" ]]; then
  FFMPEG_ZIP=$(curl -fsSL --retry 3 ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "$FFMPEG_RELEASE" | "$PYTHON" -c '
import json, re, sys
pattern = re.compile(r"ffmpeg-n(\d+)\.(\d+)-latest-win64-lgpl-shared-\d+\.\d+\.zip")
builds = [(tuple(map(int, m.groups())), a["browser_download_url"])
          for a in json.load(sys.stdin)["assets"] if (m := pattern.fullmatch(a["name"]))]
print(max(builds)[1])')
fi
echo "ffmpeg ($FFMPEG_ZIP)"
T=Vendor/ffmpeg-tmp
rm -rf "$T" && mkdir -p "$T"
curl -fsSL --retry 3 -o "$T/ffmpeg.zip" "$FFMPEG_ZIP"
echo "ffmpeg sha256: $(sha256sum "$T/ffmpeg.zip" | cut -d' ' -f1)"
"$PYTHON" -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$T/ffmpeg.zip" "$T"
FFMPEG_DIR="$(dirname "$(find "$T" -name ffprobe.exe | head -1)")"
cp "$FFMPEG_DIR/ffmpeg.exe" "$FFMPEG_DIR/ffprobe.exe" "$FFMPEG_DIR"/*.dll "$HELPER/"

# The notices: DigUp's own (llama.cpp and the rest), then the libraries only this build carries.
mkdir -p "$HELPER/licenses"
cp Resources/Acknowledgements.txt "$HELPER/licenses/DigUp.txt"
cp "$(find "$T" -maxdepth 2 -name LICENSE.txt | head -1)" "$HELPER/licenses/ffmpeg.txt"
[[ -f Vendor/pdfium/LICENSE ]] && cp Vendor/pdfium/LICENSE "$HELPER/licenses/PDFium.txt"
rm -rf "$T"

# The helper starts with only Windows' own folders on PATH: a DLL missing from helper\ fails here, not on someone's PC.
SYSTEM="$(cygpath -u "$SYSTEMROOT")"
PATH="$SYSTEM/System32:$SYSTEM" "$HELPER/digup.exe" --help > /dev/null
PATH="$SYSTEM/System32:$SYSTEM" "$HELPER/ffprobe.exe" -version > /dev/null
echo "helper\\: $(ls "$HELPER" | wc -l) files, $(du -sh "$HELPER" | cut -f1)"

# The shell and its installer.
(cd shell && npx --yes "@tauri-apps/cli@$TAURI_CLI" build --config "{\"version\":\"$VERSION\"}")
mkdir -p "$OUT"
INSTALLER="$OUT/DigUp-$VERSION-setup.exe"
cp shell/src-tauri/target/release/bundle/nsis/*_"$VERSION"_x64-setup.exe "$INSTALLER"
echo "Built $INSTALLER ($(du -h "$INSTALLER" | cut -f1))"
