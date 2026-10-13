#!/bin/zsh
# 编译成 build/一键切换win.app（arm64 + x86_64）。传 --zip 再打一个发布用的 zip。
set -e
cd "${0:A:h}"
APP="build/一键切换win.app"
VERSION=${VERSION:-0.1.0}
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 -o build/onekey-win-$arch Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/onekey-win" build/onekey-win-arm64 build/onekey-win-x86_64
rm build/onekey-win-arm64 build/onekey-win-x86_64
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
# 有固定签名证书就用它（TCC 授权跨编译保留），否则 ad-hoc
if security find-identity -p codesigning | grep -q "${SIGN_IDENTITY:-EdgeDrop Local Signing}"; then
  codesign --force --sign "${SIGN_IDENTITY:-EdgeDrop Local Signing}" "$APP"
else
  codesign --force --sign - "$APP"
fi
if [[ $1 == --zip ]]; then
  ditto -c -k --keepParent "$APP" "build/onekey-win-$VERSION.zip"
  echo "build/onekey-win-$VERSION.zip"
fi
echo "$APP"
