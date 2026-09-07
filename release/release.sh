#!/usr/bin/env zsh
set -euo pipefail

# Auto-confirm Homebrew's "Do you want to proceed?" upgrade prompt
# Equivalent to passing `--no-ask` / `-y` to `brew upgrade`.
# See `man brew` (Environment section) → HOMEBREW_NO_ASK.
export HOMEBREW_NO_ASK=1

# Usage: ./release.sh <major|minor|patch>
# Example: ./release.sh patch   (v0.1.2 -> v0.1.3)
#          ./release.sh minor   (v0.1.2 -> v0.2.0)
#          ./release.sh major   (v0.1.2 -> v1.0.0)
#          First release (no tags): v0.1.0
#
# Run on a Mac. Bottles macOS; Linux brew installs compile from source.
#
#   1. Tag and push the release in the olive-mail repo
#   2. Wait for GitHub to make the source tarball available, then sha256 it
#   3. Generate the Homebrew formula from the template
#   4. Build from source and bottle for this Mac
#   5. Put the bottle in homebrew-tap, merge the bottle block into the formula
#   6. Commit and push homebrew-tap
#   7. Install/upgrade local olive-mail from the bottle

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAP_REPO="$REPO_DIR/../homebrew-tap"
TEMPLATE="$TAP_REPO/Formula/olive-mail_template.rb"
FORMULA="$TAP_REPO/Formula/olive-mail.rb"
BOTTLES="$TAP_REPO/Bottles"

BUMP="${1:-}"
if [[ "$BUMP" != "major" && "$BUMP" != "minor" && "$BUMP" != "patch" ]]; then
    echo "Usage: $0 <major|minor|patch>"
    echo "Example: $0 patch"
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: Run release.sh on a Mac so it can bottle."
    echo "Linux brew installs build from source and do not need a bottle."
    exit 1
fi

if ! command -v brew >/dev/null; then
    echo "Error: Homebrew is required."
    exit 1
fi

# Determine latest version from git tags
LATEST=$(git -C "$REPO_DIR" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
if [[ -z "$LATEST" ]]; then
    VERSION="v0.1.0"
    echo "No existing version tags. First release: $VERSION"
else
    MAJOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f1)
    MINOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f2)
    PATCH=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f3)

    case "$BUMP" in
        major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
        minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
        patch) PATCH=$((PATCH + 1)) ;;
    esac

    VERSION="v${MAJOR}.${MINOR}.${PATCH}"
    echo "Latest version: $LATEST"
    echo "New version:    $VERSION"
fi
echo ""

if [[ ! -d "$TAP_REPO" ]]; then
    echo "Error: Formula repo not found at $TAP_REPO"
    echo "Expected homebrew-tap as a sibling folder of olive-mail."
    exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: Formula template not found at $TEMPLATE"
    exit 1
fi

TARBALL_URL="https://github.com/nohype-ai/olive-mail/archive/refs/tags/${VERSION}.tar.gz"
ROOT_URL="https://raw.githubusercontent.com/nohype-ai/homebrew-tap/main/Bottles"

echo "=== olive-mail Release: $VERSION ==="
echo ""

# Step 1: Tag the release in the olive-mail repo and push
echo "Step 1: Tagging $VERSION and pushing to GitHub ..."
cd "$REPO_DIR"
git tag "$VERSION"
git push origin "$VERSION"
echo "  Tag $VERSION pushed."
echo ""

# Step 2: Wait for GitHub to create the source tarball, then compute sha256
echo "Step 2: Waiting for GitHub to make the source tarball available ..."
MAX_ATTEMPTS=12
WAIT_SECONDS=5
SHA256=""

for attempt in $(seq 1 $MAX_ATTEMPTS); do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L "$TARBALL_URL")
    if [[ "$HTTP_STATUS" == "200" ]]; then
        echo "  Tarball available (attempt $attempt). Computing sha256 ..."
        SHA256=$(curl -sL "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')
        break
    fi
    echo "  Not ready yet (HTTP $HTTP_STATUS). Waiting ${WAIT_SECONDS}s ... (attempt $attempt/$MAX_ATTEMPTS)"
    sleep "$WAIT_SECONDS"
done

if [[ -z "$SHA256" ]]; then
    echo "Error: Tarball not available after $((MAX_ATTEMPTS * WAIT_SECONDS))s."
    echo "URL: $TARBALL_URL"
    echo "The repo must be public."
    exit 1
fi

echo "  sha256: $SHA256"
echo ""

# Step 3: Generate olive-mail.rb from the template (no bottle yet)
echo "Step 3: Updating Homebrew formula from template ..."
sed -e "s|<VERSION-PLACEHOLDER>|${VERSION}|g" \
    -e "s|<SHA256-PLACEHOLDER>|${SHA256}|g" \
    "$TEMPLATE" > "$FORMULA"
echo "  Formula written to $FORMULA"
echo ""

# Step 4: Build from source and bottle for this Mac
echo "Step 4: Bottling for this Mac ..."
brew tap nohype-ai/tap
BREW_TAP="$(brew --repository nohype-ai/tap)"
mkdir -p "$BREW_TAP/Formula"
cp "$FORMULA" "$BREW_TAP/Formula/olive-mail.rb"

if brew list --formula olive-mail >/dev/null 2>&1; then
    brew reinstall --build-from-source nohype-ai/tap/olive-mail
else
    brew install --build-from-source nohype-ai/tap/olive-mail
fi

BOTTLE_DIR="$(mktemp -d)"
pushd "$BOTTLE_DIR" >/dev/null
brew bottle --no-rebuild --json --root-url="$ROOT_URL" nohype-ai/tap/olive-mail
mkdir -p "$BOTTLES"
python3 - "$BOTTLES" <<'PY'
import glob, json, os, shutil, sys
dest = sys.argv[1]
for path in glob.glob("*.bottle.json"):
    with open(path) as handle:
        data = json.load(handle)
    for spec in data.values():
        for info in spec["bottle"]["tags"].values():
            shutil.copy(info["local_filename"], os.path.join(dest, info["filename"]))
PY
brew bottle --merge --write --no-commit ./*.bottle.json
popd >/dev/null
rm -rf "$BOTTLE_DIR"

cp "$BREW_TAP/Formula/olive-mail.rb" "$FORMULA"
echo "  Bottle written to $BOTTLES"
echo ""

# Step 5: Commit the bottled formula in the homebrew-tap repo
echo "Step 5: Committing formula update ..."
cd "$TAP_REPO"
git add Formula/olive-mail.rb Bottles
git commit -m "Bump olive-mail to $VERSION"
echo "  Committed."
echo ""

# Step 6: Push the formula repo
echo "Step 6: Pushing homebrew-tap ..."
git push
echo "  Pushed."
echo ""

echo "=== Release $VERSION complete! ==="

# Step 7: Install from the bottle
echo ""
echo "Step 7: Installing bottled olive-mail locally ..."
cd "$BREW_TAP" && git pull
brew reinstall nohype-ai/tap/olive-mail
echo "This version of olive-mail is now installed: $(brew list --versions olive-mail)"
