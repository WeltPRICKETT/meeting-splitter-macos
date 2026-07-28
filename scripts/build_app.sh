#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_name="会议拆分器"
dist_path="$project_root/dist"
staging_root="$(mktemp -d /private/tmp/meeting-splitter-build.XXXXXX)"
bundle_path="$staging_root/$app_name.app"
final_bundle_path="$dist_path/$app_name.app"
contents_path="$bundle_path/Contents"
macos_path="$contents_path/MacOS"
resources_path="$contents_path/Resources"
frameworks_path="$contents_path/Frameworks"
icon_work_path="$project_root/.build/icon-work"

trap 'rm -rf "$staging_root"' EXIT

if [[ -n "${MEETING_SPLITTER_FFMPEG:-}" ]]; then
    ffmpeg_source="$MEETING_SPLITTER_FFMPEG"
else
    ffmpeg_source="$(command -v ffmpeg || true)"
fi

if [[ -z "$ffmpeg_source" || ! -x "$ffmpeg_source" ]]; then
    print -u2 "未找到 FFmpeg。请先安装 FFmpeg，或设置 MEETING_SPLITTER_FFMPEG。"
    exit 1
fi

print "正在构建 release 版本…"
swift build \
    --package-path "$project_root" \
    -c release \
    -j 2
binary_path="$(swift build --package-path "$project_root" -c release --show-bin-path)"

rm -rf "$icon_work_path"
mkdir -p \
    "$macos_path" \
    "$resources_path" \
    "$frameworks_path" \
    "$icon_work_path/AppIcon.iconset"

cp "$binary_path/MeetingSplitter" "$macos_path/MeetingSplitter"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/THIRD_PARTY_NOTICES.txt" "$resources_path/"

print "正在生成应用图标…"
swift "$project_root/scripts/generate_icon.swift" "$icon_work_path/AppIcon-1024.png"

typeset -A icon_sizes
icon_sizes=(
    icon_16x16.png 16
    icon_16x16@2x.png 32
    icon_32x32.png 32
    icon_32x32@2x.png 64
    icon_128x128.png 128
    icon_128x128@2x.png 256
    icon_256x256.png 256
    icon_256x256@2x.png 512
    icon_512x512.png 512
    icon_512x512@2x.png 1024
)

for icon_name icon_size in ${(kv)icon_sizes}; do
    sips \
        -z "$icon_size" "$icon_size" \
        "$icon_work_path/AppIcon-1024.png" \
        --out "$icon_work_path/AppIcon.iconset/$icon_name" \
        >/dev/null
done

iconutil \
    -c icns \
    "$icon_work_path/AppIcon.iconset" \
    -o "$resources_path/AppIcon.icns"

print "正在封装媒体转换组件…"
cp -L "$ffmpeg_source" "$resources_path/ffmpeg"
chmod u+w,ugo+x "$resources_path/ffmpeg"

typeset -A bundled_seen

bundle_dependencies() {
    local target="$1"
    local dependency
    local destination
    local rewritten_path

    if [[ -n "${bundled_seen[$target]:-}" ]]; then
        return
    fi
    bundled_seen[$target]=1

    for dependency in ${(f)"$(otool -L "$target" \
        | tail -n +2 \
        | awk '{print $1}' \
        | grep -E '^/(opt/homebrew|usr/local)/' \
        || true)"}; do
        destination="$frameworks_path/${dependency:t}"
        rewritten_path="@executable_path/../Frameworks/${dependency:t}"

        if [[ ! -f "$destination" ]]; then
            cp -L "$dependency" "$destination"
            chmod u+w "$destination"
        fi

        install_name_tool \
            -change "$dependency" "$rewritten_path" "$target" \
            2>/dev/null
        bundle_dependencies "$destination"
    done

    if [[ "$target" == "$frameworks_path/"*.dylib ]]; then
        install_name_tool \
            -id "@executable_path/../Frameworks/${target:t}" \
            "$target" \
            2>/dev/null
    fi
}

bundle_dependencies "$resources_path/ffmpeg"

if find "$resources_path/ffmpeg" "$frameworks_path" -type f -print0 \
    | xargs -0 otool -L 2>/dev/null \
    | grep -qE '/(opt/homebrew|usr/local)/'; then
    print -u2 "仍有 Homebrew 动态库没有封装，构建已停止。"
    exit 1
fi

plutil -lint "$contents_path/Info.plist" >/dev/null
xattr -cr "$bundle_path"

for embedded_library in "$frameworks_path"/*.dylib; do
    codesign --force --sign - "$embedded_library"
done
codesign --force --sign - "$resources_path/ffmpeg"
xattr -cr "$bundle_path"
xattr -d com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
xattr -d "com.apple.fileprovider.fpfs#P" "$bundle_path" 2>/dev/null || true
codesign --force --deep --sign - "$bundle_path"

for embedded_library in "$frameworks_path"/*.dylib; do
    codesign --verify --strict "$embedded_library"
done
codesign --verify --strict "$resources_path/ffmpeg"
codesign --verify --deep --strict "$bundle_path"

if ! env -i PATH=/usr/bin:/bin "$resources_path/ffmpeg" -version >/dev/null 2>&1; then
    print -u2 "内置 FFmpeg 无法脱离 Homebrew 环境启动，构建已停止。"
    exit 1
fi

mkdir -p "$dist_path"
zip_path="$dist_path/$app_name-macOS-AppleSilicon.zip"
rm -rf "$final_bundle_path"
rm -f "$zip_path"

ditto --noextattr --noqtn "$bundle_path" "$final_bundle_path"
ditto \
    -c \
    -k \
    --norsrc \
    --noextattr \
    --noqtn \
    --keepParent \
    "$bundle_path" \
    "$zip_path"
xattr -d com.apple.FinderInfo "$final_bundle_path" 2>/dev/null || true
xattr -d "com.apple.fileprovider.fpfs#P" "$final_bundle_path" 2>/dev/null || true
codesign --verify --deep --strict "$final_bundle_path"

print
print "构建完成："
print "  $final_bundle_path"
print "  $zip_path"
du -sh "$final_bundle_path" "$zip_path"
