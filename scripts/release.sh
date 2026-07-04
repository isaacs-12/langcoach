#!/usr/bin/env bash
#
# Cut a signed, notarized LangCoach release and publish it to GitHub.
#
# Usage:
#   make release                  # bump the last version component (0.0.1 -> 0.0.2)
#   make release VERSION=1.0.0    # release an explicit version (major releases etc.)
#
# What it does, in order:
#   1. Preflight: clean tree, tooling, Developer ID cert, notary profile, gh auth.
#   2. Compute the next version from git tags (or use $VERSION).
#   3. Build Release, signed with your Developer ID Application identity
#      (hardened runtime is already on via ENABLE_HARDENED_RUNTIME).
#   4. Notarize with Apple (notarytool, keychain profile "$NOTARY_PROFILE"),
#      then staple the ticket so the app opens with no warnings offline.
#   5. Tag vX.Y.Z, push, and create a GitHub release with LangCoach.zip attached.
#
# One-time setup required (see PR / docs):
#   - Apple Developer Program membership + "Developer ID Application" certificate
#     in your login keychain.
#   - xcrun notarytool store-credentials langcoach-notary \
#       --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
#   - gh auth login
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="LangCoach/LangCoach.xcodeproj"
SCHEME="LangCoach"
APP_NAME="LangCoach.app"
BUILD_DIR="build/release"
NOTARY_PROFILE="${NOTARY_PROFILE:-langcoach-notary}"
VERSION="${VERSION:-}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
bold "==> Preflight"

command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"
command -v gh >/dev/null         || die "gh not found (brew install gh)"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean — commit or stash first"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || die "releases must be cut from main (currently on '$BRANCH')"

git fetch origin main --tags --quiet
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || die "local main is not in sync with origin/main — pull/push first"

IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 || true)"
[ -n "$IDENTITY_LINE" ] || die "no 'Developer ID Application' certificate in your keychain.
  Enroll at https://developer.apple.com/programs/ then create the certificate via
  Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application."
TEAM_ID="$(echo "$IDENTITY_LINE" | sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/')"
[ ${#TEAM_ID} -eq 10 ] || die "couldn't extract a team ID from: $IDENTITY_LINE"
echo "    Signing identity: $(echo "$IDENTITY_LINE" | sed -E 's/^[^"]*"([^"]*)".*$/\1/')"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' not found or invalid. Create it with:
  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id <your-apple-id> --team-id $TEAM_ID --password <app-specific-password>
  (app-specific password: https://account.apple.com > Sign-In and Security)"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run: gh auth login"

# ------------------------------------------------------------------ version
if [ -n "$VERSION" ]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3 (got '$VERSION')"
else
  LAST_TAG="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
  if [ -z "$LAST_TAG" ]; then
    VERSION="0.0.1"
  else
    BASE="${LAST_TAG#v}"
    IFS=. read -r MAJ MIN PATCH <<< "$BASE"
    VERSION="$MAJ.$MIN.$((PATCH + 1))"
  fi
fi
TAG="v$VERSION"
git rev-parse "$TAG" >/dev/null 2>&1 && die "tag $TAG already exists"
BUILD_NUMBER="$(git rev-list --count HEAD)"

bold "==> Releasing LangCoach $VERSION (build $BUILD_NUMBER, team $TEAM_ID)"

# -------------------------------------------------------------------- build
bold "==> Building signed Release"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" clean build \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  | grep -E '^(\*\*|error|warning|note: Signing)' || true

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || die "build failed — $APP not found (re-run without the grep filter to see full output)"

codesign --verify --strict --deep "$APP" || die "code signature verification failed"

# ---------------------------------------------------------------- notarize
bold "==> Notarizing (this usually takes a minute or two)"
SUBMIT_ZIP="build/LangCoach-submit.zip"
rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

SUBMIT_OUT="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
echo "$SUBMIT_OUT" | tail -5
if ! echo "$SUBMIT_OUT" | grep -q 'status: Accepted'; then
  SUBMISSION_ID="$(echo "$SUBMIT_OUT" | grep -m1 '  id:' | awk '{print $2}')"
  die "notarization was not accepted. Inspect the log with:
  xcrun notarytool log $SUBMISSION_ID --keychain-profile $NOTARY_PROFILE"
fi

bold "==> Stapling notarization ticket"
xcrun stapler staple "$APP"
spctl -a -vv "$APP" || die "Gatekeeper assessment failed after stapling"

FINAL_ZIP="build/LangCoach.zip"
rm -f "$FINAL_ZIP" "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"

# ----------------------------------------------------------- tag & publish
bold "==> Tagging $TAG and publishing GitHub release"
git tag -a "$TAG" -m "LangCoach $VERSION"
git push origin main --tags

gh release create "$TAG" "$FINAL_ZIP" \
  --title "LangCoach $VERSION" \
  --generate-notes

bold "==> Done"
echo "    Release: $(gh release view "$TAG" --json url -q .url)"
echo "    Users on older versions will be offered this update in-app."
