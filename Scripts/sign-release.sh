#!/bin/sh

set -eu

CODESIGN="${CODESIGN:-codesign}"
SHASUM="${SHASUM:-shasum}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"

usage() {
	printf '%s\n' \
		"Usage: SIGNING_IDENTITY=<identity> ./Scripts/sign-release.sh <executable>..." \
		"" \
		"Signs each executable with hardened runtime and a secure timestamp," \
		"verifies the signature, and replaces its adjacent SHA-256 checksum." \
		"Set SIGNING_KEYCHAIN when the identity is stored in a non-default keychain."
}

if [ -z "$SIGNING_IDENTITY" ] || [ "$#" -eq 0 ]; then
	usage >&2
	exit 64
fi

for executable in "$@"; do
	if [ ! -f "$executable" ]; then
		printf 'Missing executable: %s\n' "$executable" >&2
		exit 1
	fi

	if [ -n "$SIGNING_KEYCHAIN" ]; then
		"$CODESIGN" \
			--force \
			--keychain "$SIGNING_KEYCHAIN" \
			--options runtime \
			--sign "$SIGNING_IDENTITY" \
			--timestamp \
			"$executable"
	else
		"$CODESIGN" \
			--force \
			--options runtime \
			--sign "$SIGNING_IDENTITY" \
			--timestamp \
			"$executable"
	fi

	"$CODESIGN" --verify --strict --verbose=2 "$executable"
	"$CODESIGN" -dvv "$executable" 2>&1

	executable_directory=$(dirname -- "$executable")
	executable_name=$(basename -- "$executable")
	(
		cd "$executable_directory"
		"$SHASUM" -a 256 "$executable_name" > "$executable_name.sha256"
	)
done
