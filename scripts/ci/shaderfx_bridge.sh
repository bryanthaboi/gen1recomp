#!/usr/bin/env bash
set -euo pipefail

cmd_env() {
  fingerprint="$RUNNER_TEMP/bridge-environment.txt"
  printf '%s\n' "${ImageOS:-}" "${ImageVersion:-}" > "$fingerprint"
  if [ "$PLAT" = android ]; then
    ndk_ver="$(sed -n "s/^[[:space:]]*ndkVersion[[:space:]]*['\"]\([0-9.]*\)['\"].*/\1/p" mobile/android/app/build.gradle)"
    test -n "$ndk_ver"
    sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
    test -n "$sdk"
    ndk="$sdk/ndk/$ndk_ver"
    if [ ! -f "$ndk/source.properties" ]; then
      (yes || true) | "$sdk/cmdline-tools/latest/bin/sdkmanager" --install "ndk;$ndk_ver" >/dev/null
    fi
    test -f "$ndk/source.properties"
    grep -Eq "^Pkg\.Revision[[:space:]]*=[[:space:]]*$ndk_ver\$" "$ndk/source.properties"
    cat "$ndk/source.properties" >> "$fingerprint"
    echo "ANDROID_NDK_HOME=$ndk" >> "$GITHUB_ENV"
    echo "ANDROID_NDK_ROOT=$ndk" >> "$GITHUB_ENV"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "$fingerprint")"
  else
    hash="$(shasum -a 256 "$fingerprint")"
  fi
  echo "hash=${hash%% *}" >> "$GITHUB_OUTPUT"
}

cmd_build() {
  out="dist/native/$PLAT"
  mkdir -p "$out"
  cd tools/shaderfx-bridge
  case "$PLAT" in
    win-x64)
      rustup target add x86_64-pc-windows-msvc
      cargo build --locked --release --target x86_64-pc-windows-msvc
      cp "target/x86_64-pc-windows-msvc/release/$LIB" "$GITHUB_WORKSPACE/$out/$LIB"
      ;;
    mac)
      rustup target add x86_64-apple-darwin aarch64-apple-darwin
      cargo build --locked --release --target x86_64-apple-darwin
      cargo build --locked --release --target aarch64-apple-darwin
      lipo -create -output "$GITHUB_WORKSPACE/$out/$LIB" \
        "target/x86_64-apple-darwin/release/$LIB" \
        "target/aarch64-apple-darwin/release/$LIB"
      lipo -info "$GITHUB_WORKSPACE/$out/$LIB"
      ;;
    ios)
      rustup target add aarch64-apple-ios
      IPHONEOS_DEPLOYMENT_TARGET=15.0 cargo build --locked --release --target aarch64-apple-ios
      cp "target/aarch64-apple-ios/release/$LIB" "$GITHUB_WORKSPACE/$out/$LIB"
      ;;
    linux-x64|linux-arm64)
      pipx install 'cargo-zigbuild==0.23.4'
      pipx inject cargo-zigbuild 'ziglang==0.16.0'
      zigpy="$(pipx environment --value PIPX_LOCAL_VENVS)/cargo-zigbuild/bin/python"
      "$zigpy" -m ziglang version
      export CARGO_ZIGBUILD_PYTHON_PATH="$zigpy"
      triple="$GLIBC_TRIPLE"
      rustup target add "${triple%%.*}"
      cargo zigbuild --locked --release --target "$triple"
      cp "target/${triple%%.*}/release/$LIB" "$GITHUB_WORKSPACE/$out/$LIB"
      ;;
    android)
      rustup target add aarch64-linux-android armv7-linux-androideabi
      cargo install cargo-ndk --version 4.1.2 --locked
      export CARGO_PROFILE_RELEASE_STRIP=symbols
      cargo ndk -t arm64-v8a -t armeabi-v7a \
        -o "$GITHUB_WORKSPACE/$out" build --locked --release
      for abi in arm64-v8a armeabi-v7a; do
        test -f "$GITHUB_WORKSPACE/$out/$abi/$LIB" \
          || { echo "::error::no Android bridge for $abi"; exit 1; }
      done
      ;;
  esac
}

cmd_verify() {
  if [ "$PLAT" = android ]; then
    for abi in arm64-v8a armeabi-v7a; do
      test -s "dist/native/$PLAT/$abi/$LIB"
      case "$abi" in
        arm64-v8a) triple=aarch64-linux-android ;;
        armeabi-v7a) triple=arm-linux-androideabi ;;
      esac
      libcxx="$(ls "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot/usr/lib/"$triple"/libc++_shared.so)"
      bash scripts/android_bridge_link_check.sh "dist/native/$PLAT/$abi/$LIB" "$libcxx"
    done
  else
    test -s "dist/native/$PLAT/$LIB"
  fi
  if [ "$PLAT" = mac ]; then
    lipo "dist/native/$PLAT/$LIB" -verify_arch x86_64 arm64
  fi
}

case "${1:-}" in
  env) cmd_env ;;
  build) cmd_build ;;
  verify) cmd_verify ;;
  *) echo "usage: $0 env|build|verify" >&2; exit 2 ;;
esac
