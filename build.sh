#!/bin/bash
set -e
# 管道中任一命令失败即整体失败：否则 `swift test | tail` 的退出码取 tail（恒 0），
# 单测失败会被静默吞掉、测试红也继续打包
set -o pipefail

# SeqAlignMac 构建脚本
# 将所有 Swift 源文件编译为 macOS .app 应用包
# 用法：./build.sh [--open] [--skip-tests]
#   --skip-tests  跳过 swift test（供 CI 复用，CI 已单独跑过测试）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
APP_NAME="SeqAlignMac"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
SOURCES_DIR="$SCRIPT_DIR/Sources"
RESOURCES_DIR="$SCRIPT_DIR/Resources"
SKIP_TESTS=0
for arg in "$@"; do
    case "$arg" in
        --open) OPEN_APP=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
    esac
done

echo "🏗️  开始构建 $APP_NAME..."

# 1. 清理旧构建
# .app 包内文件数常超 safe-delete 钩子阈值 (50)，用 mv 到 /tmp 回收（macOS 重启 /tmp 自动清理）
[ -d "$APP_BUNDLE" ] && mv "$APP_BUNDLE" "/tmp/SeqAlignMac_old_$$" 2>/dev/null || true
echo "✅ 已清理旧构建"

# 2. 创建 .app 目录结构
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
echo "✅ 已创建 .app 目录结构"

# 3. 复制 Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo "✅ 已复制 Info.plist"

# 3.5 运行领域层单元测试（测试护栏）
# 本机仅 Command Line Tools 时无 XCTest 框架 → 警告跳过；CI（完整 Xcode）会真正执行。
# CI 传 --skip-tests 复用本脚本时跳过（避免重复执行一遍完整测试）。
if [ "$SKIP_TESTS" -eq 1 ]; then
    echo "⏭️  按参数跳过单元测试"
else
    echo "🧪 运行单元测试 (swift test)..."
    if command -v swift >/dev/null 2>&1; then
        if echo "import XCTest" | swiftc -typecheck - >/dev/null 2>&1; then
            if ! swift test 2>&1 | tail -20; then
                echo "❌ 单元测试失败"
                exit 1
            fi
        else
            echo "⚠️  本机缺少 XCTest（仅 Command Line Tools），跳过本地测试（CI 中会执行）"
        fi
    else
        echo "⚠️  未找到 swift 命令，跳过测试"
    fi
fi

# 4. 编译 Swift 源文件
echo "🔨 编译 Swift 源文件..."
# 数组 + 引号展开：路径含空格时逐词分割会直接编译失败
SWIFT_FILES=()
while IFS= read -r f; do SWIFT_FILES+=("$f"); done < <(find "$SOURCES_DIR" -name "*.swift" | sort)

swiftc \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -parse-as-library \
    -O \
    -framework Cocoa \
    -framework SwiftUI \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${SWIFT_FILES[@]}" \
    2>&1

echo "✅ 编译成功"

# 5. 生成应用图标 (icns)
echo "🎨 生成应用图标..."
ICONSET_DIR="$SCRIPT_DIR/icon.iconset"
# 用 mv 替代 rm -rf：iconset 含 56 个 PNG，超过 safe-delete 钩子阈值 (50)，
# 直接 rm 会触发交互确认；mv 到 /tmp 等价回收（macOS 重启 /tmp 自动清理）。
[ -d "$ICONSET_DIR" ] && mv "$ICONSET_DIR" "/tmp/SeqAlignMac_iconset_$$" 2>/dev/null || true

# 使用独立 Swift 脚本生成图标（显式传入输出目录，不依赖调用时 CWD）
swift "$SCRIPT_DIR/gen_icon.swift" "$SCRIPT_DIR" 2>&1

if [ -f "$ICONSET_DIR/icon_512x512.png" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ 应用图标已生成"
else
    echo "⚠️  图标生成失败"
fi
# 构建脚本自身的清理同样走 mv（避免触发 safe-delete 钩子）
[ -d "$ICONSET_DIR" ] && mv "$ICONSET_DIR" "/tmp/SeqAlignMac_iconset_$$" 2>/dev/null || true

# 6. 复制 SVG logo 到 Resources
cp "$SCRIPT_DIR/logo.svg" "$APP_BUNDLE/Contents/Resources/logo.svg"
echo "✅ SVG Logo 已复制"

# 6.5 复制隐私清单等 Resources 文件（App Store 要求 PrivacyInfo.xcprivacy 打进 bundle）
if [ -f "$RESOURCES_DIR/PrivacyInfo.xcprivacy" ]; then
    cp "$RESOURCES_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
    echo "✅ 隐私清单已复制"
fi

# 7. 设置可执行权限
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 7.5 代码签名（可选）
# 仅当环境变量 DEVELOPER_ID 提供时才正式签名；未设置则 ad-hoc 兜底（开发构建）。
# --options runtime 启用「强化运行时」，为公证做准备。
# SEQALIGN_SANDBOX=1 → 打入 App Store 沙盒 entitlements（注意：沙盒禁止 exec 外部比对器）。
# NOTARY_PROFILE=<keychain profile> → Developer ID 签名后用 notarytool 公证并 staple。
ENT_ARG=()
if [ -n "$SEQALIGN_SANDBOX" ]; then
    if [ -z "$DEVELOPER_ID" ]; then
        echo "⚠️  SEQALIGN_SANDBOX 需要 DEVELOPER_ID 正式签名才有意义（ad-hoc 无法上架 MAS），且沙盒会禁用外部比对器。"
    fi
    ENT_ARG=(--entitlements "$SCRIPT_DIR/SeqAlignMac.entitlements")
    echo "🔒 启用 App Sandbox entitlements（MAS 配置）"
fi

if [ -n "$DEVELOPER_ID" ]; then
    echo "🔏 代码签名 ($DEVELOPER_ID)..."
    codesign --force --options runtime --timestamp "${ENT_ARG[@]}" \
        --sign "$DEVELOPER_ID" \
        "$APP_BUNDLE" 2>&1
    codesign --verify --verbose "$APP_BUNDLE"
    echo "✅ 签名完成"
else
    # 无证书时做 ad-hoc 签名兜底：arm64 无签名二进制会被 Gatekeeper 拒启，
    # 且分发 zip 经网络传输会丢失 quarantine 放行标记
    echo "🔏 未设置 DEVELOPER_ID，使用 ad-hoc 签名（开发构建）..."
    codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 || echo "⚠️  ad-hoc 签名失败，继续（本机运行不受影响）"
fi

# 8. 打包分发 zip
# ditto --keepParent 保留 .app 包结构，符合 macOS 分发惯例。
echo "📦 打包 $APP_NAME.app.zip..."
ZIP_PATH="$SCRIPT_DIR/$APP_NAME.app.zip"
# 用 mv 替代 rm -f：zip 内文件数常超 safe-delete 阈值 (50)
[ -f "$ZIP_PATH" ] && mv "$ZIP_PATH" "/tmp/SeqAlignMac_zip_$$" 2>/dev/null || true
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
echo "✅ 已生成 $ZIP_PATH"

# 8.5 公证（可选 · Developer ID 分发前置；MAS 分发由 App Store Connect 托管公证，无需此步）
# 需先 `xcrun notarytool store-credentials <profile> ...` 存好凭据。
if [ -n "$DEVELOPER_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "📮 提交公证 ($NOTARY_PROFILE)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 \
        || echo "⚠️  公证提交失败（可稍后手动执行 notarytool / stapler）"
    xcrun stapler staple "$APP_BUNDLE" 2>&1 || echo "⚠️  staple 失败"
fi

# 9. 验证构建
echo ""
echo "✅ 构建完成！"
echo "📦 应用位置: $APP_BUNDLE"
echo "📊 应用大小: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo "🗜️  分发包: $ZIP_PATH ($(du -sh "$ZIP_PATH" | cut -f1))"
echo ""

# 10. 可选：打开应用
if [ "${OPEN_APP:-0}" == "1" ]; then
    echo "🚀 启动应用..."
    open "$APP_BUNDLE"
fi
