#!/bin/sh

set -eu

CODESIGN="${CODESIGN:-codesign}"
DITTO="${DITTO:-ditto}"
PLUTIL="${PLUTIL:-plutil}"
XCRUN="${XCRUN:-xcrun}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"

usage() {
	printf '%s\n' \
		"Usage: APP_STORE_CONNECT_ISSUER_ID=<issuer> \\" \
		"       APP_STORE_CONNECT_KEY_ID=<key-id> \\" \
		"       NOTARY_KEY_PATH=<key.p8> \\" \
		"       ./Scripts/notarize-release.sh <executable>..." \
		"" \
		"Submits the signed executables to Apple's notary service and verifies" \
		"that Gatekeeper recognizes the resulting online notarization tickets."
}

if \
	[ -z "$APP_STORE_CONNECT_ISSUER_ID" ] \
	|| [ -z "$APP_STORE_CONNECT_KEY_ID" ] \
	|| [ -z "$NOTARY_KEY_PATH" ] \
	|| [ "$#" -eq 0 ]
then
	usage >&2
	exit 64
fi

if [ ! -f "$NOTARY_KEY_PATH" ]; then
	printf 'Missing App Store Connect API key: %s\n' "$NOTARY_KEY_PATH" >&2
	exit 1
fi

WORK_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/skillrack-notarization.XXXXXX")
trap 'rm -rf "$WORK_DIRECTORY"' EXIT HUP INT TERM
PAYLOAD_DIRECTORY="$WORK_DIRECTORY/skillrack-notarization"
ARCHIVE_PATH="$WORK_DIRECTORY/skillrack-notarization.zip"
SUBMISSION_PATH="$WORK_DIRECTORY/submission.plist"
mkdir -p "$PAYLOAD_DIRECTORY"

for executable in "$@"; do
	if [ ! -f "$executable" ]; then
		printf 'Missing executable: %s\n' "$executable" >&2
		exit 1
	fi
	cp -p "$executable" "$PAYLOAD_DIRECTORY/"
done

"$DITTO" -c -k --keepParent "$PAYLOAD_DIRECTORY" "$ARCHIVE_PATH"

submission_exit=0
"$XCRUN" notarytool submit "$ARCHIVE_PATH" \
	--issuer "$APP_STORE_CONNECT_ISSUER_ID" \
	--key "$NOTARY_KEY_PATH" \
	--key-id "$APP_STORE_CONNECT_KEY_ID" \
	--output-format plist \
	--wait \
	> "$SUBMISSION_PATH" \
	|| submission_exit=$?
cat "$SUBMISSION_PATH"

if [ "$submission_exit" -ne 0 ]; then
	exit "$submission_exit"
fi

submission_id=$("$PLUTIL" -extract id raw -o - "$SUBMISSION_PATH")
submission_status=$("$PLUTIL" -extract status raw -o - "$SUBMISSION_PATH")
if [ "$submission_status" != "Accepted" ]; then
	"$XCRUN" notarytool log "$submission_id" \
		--issuer "$APP_STORE_CONNECT_ISSUER_ID" \
		--key "$NOTARY_KEY_PATH" \
		--key-id "$APP_STORE_CONNECT_KEY_ID" \
		|| true
	exit 1
fi

for executable in "$@"; do
	"$CODESIGN" --verify --strict --verbose=2 "$executable"
	"$CODESIGN" -vvvv -R="notarized" --check-notarization "$executable"
done
