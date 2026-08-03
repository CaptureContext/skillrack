#!/bin/sh

set -eu

PRODUCT="${PRODUCT:-skillrack}"
CONFIGURATION="${CONFIGURATION:-release}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-15.0}"
SCRATCH_PATH="${SCRATCH_PATH:-.build/universal}"
OUTPUT_PATH="${OUTPUT_PATH:-dist/${PRODUCT}-universal-apple-darwin}"
BUILD_SYSTEM="${BUILD_SYSTEM:-native}"
SWIFT="${SWIFT:-swift}"
XCRUN="${XCRUN:-xcrun}"

usage() {
	printf '%s\n' \
		"Usage: ./Scripts/build-universal.sh" \
		"" \
		"Builds arm64 and x86_64 slices of the skillrack executable, combines" \
		"them into one universal macOS binary, and generates a SHA-256 checksum." \
		"" \
		"Environment variables:" \
		"  PRODUCT                    Swift package product (default: skillrack)" \
		"  CONFIGURATION              Swift build configuration (default: release)" \
		"  MACOS_DEPLOYMENT_TARGET    Minimum macOS version (default: 15.0)" \
		"  SCRATCH_PATH               SwiftPM scratch path (default: .build/universal)" \
		"  OUTPUT_PATH                Output executable path" \
		"  BUILD_SYSTEM               SwiftPM build system (default: native)" \
		"  SWIFT                      Swift executable (default: swift)" \
		"  XCRUN                      xcrun executable (default: xcrun)"
}

case "${1:-}" in
	-h|--help)
		usage
		exit 0
		;;
	"")
		;;
	*)
		usage >&2
		exit 64
		;;
esac

SCRIPT_DIRECTORY=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(dirname -- "$SCRIPT_DIRECTORY")

case "$SCRATCH_PATH" in
	/*) ;;
	*) SCRATCH_PATH="$REPOSITORY_ROOT/$SCRATCH_PATH" ;;
esac

case "$OUTPUT_PATH" in
	/*) ;;
	*) OUTPUT_PATH="$REPOSITORY_ROOT/$OUTPUT_PATH" ;;
esac

build_architecture() {
	architecture="$1"
	triple="${architecture}-apple-macosx${MACOS_DEPLOYMENT_TARGET}"
	architecture_scratch_path="$SCRATCH_PATH/$architecture"

	printf 'Building %s for %s...\n' "$PRODUCT" "$triple"
	"$SWIFT" build \
		--package-path "$REPOSITORY_ROOT" \
		--scratch-path "$architecture_scratch_path" \
		--configuration "$CONFIGURATION" \
		--product "$PRODUCT" \
		--triple "$triple" \
		--build-system "$BUILD_SYSTEM"
}

rm -f "$OUTPUT_PATH" "$OUTPUT_PATH.sha256"

build_architecture arm64
build_architecture x86_64

ARM64_EXECUTABLE="$SCRATCH_PATH/arm64/arm64-apple-macosx/$CONFIGURATION/$PRODUCT"
X86_64_EXECUTABLE="$SCRATCH_PATH/x86_64/x86_64-apple-macosx/$CONFIGURATION/$PRODUCT"
OUTPUT_DIRECTORY=$(dirname -- "$OUTPUT_PATH")
OUTPUT_NAME=$(basename -- "$OUTPUT_PATH")

if [ ! -f "$ARM64_EXECUTABLE" ]; then
	printf 'Missing arm64 executable: %s\n' "$ARM64_EXECUTABLE" >&2
	exit 1
fi

if [ ! -f "$X86_64_EXECUTABLE" ]; then
	printf 'Missing x86_64 executable: %s\n' "$X86_64_EXECUTABLE" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"
"$XCRUN" lipo \
	-create \
	"$ARM64_EXECUTABLE" \
	"$X86_64_EXECUTABLE" \
	-output "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
"$XCRUN" lipo "$OUTPUT_PATH" -verify_arch arm64
"$XCRUN" lipo "$OUTPUT_PATH" -verify_arch x86_64

(
	cd "$OUTPUT_DIRECTORY"
	shasum -a 256 "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)

ARCHITECTURES=$("$XCRUN" lipo -archs "$OUTPUT_PATH")
printf 'Built universal executable: %s\n' "$OUTPUT_PATH"
printf 'Architectures: %s\n' "$ARCHITECTURES"
printf 'Checksum: %s.sha256\n' "$OUTPUT_PATH"
