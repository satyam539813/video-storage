#!/usr/bin/env bash
# Upload video files to a GitHub release.
#
# GitHub releases allow up to 1000 assets per release, each under 2 GiB,
# with no total size limit and no bandwidth limit. This is the best path
# for storing and sharing videos on GitHub without Git LFS.
#
# Requires: gh (GitHub CLI) authenticated with the `repo` scope.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: upload-release.sh --repo OWNER/NAME --tag TAG [options] <file>...

Options:
  --repo OWNER/NAME   Repository (e.g. satyam539813/video-storage)
  --tag TAG           Release tag (e.g. v1). Created if it does not exist.
  --title TITLE       Release title (default: TAG)
  --notes NOTES       Release notes (default: "Video storage")
  --clobber           Replace existing assets with the same name
  -h, --help          Show this help

Examples:
  upload-release.sh --repo me/video-storage --tag v1 --title "My videos" clip.mp4
  upload-release.sh --repo me/video-storage --tag v2 --clobber *.mp4
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

REPO=""
TAG=""
TITLE=""
NOTES=""
CLOBBER=0
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --repo) [ $# -ge 2 ] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --tag) [ $# -ge 2 ] || die "--tag requires a value"; TAG="$2"; shift 2 ;;
    --title) [ $# -ge 2 ] || die "--title requires a value"; TITLE="$2"; shift 2 ;;
    --notes) [ $# -ge 2 ] || die "--notes requires a value"; NOTES="$2"; shift 2 ;;
    --clobber) CLOBBER=1; shift ;;
    --) shift; FILES+=("$@"); break ;;
    -*) die "Unknown option: $1" ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[ -n "$REPO" ] || die "--repo is required"
[ -n "$TAG" ] || die "--tag is required"
[ ${#FILES[@]} -gt 0 ] || die "No files specified"

for f in "${FILES[@]}"; do
  [ -f "$f" ] || die "File not found: $f"
  if stat -c %s "$f" >/dev/null 2>&1; then
    SIZE=$(stat -c %s "$f")
  else
    SIZE=$(stat -f %z "$f")
  fi
  [ "$SIZE" -lt $((2*1024*1024*1024)) ] || die "File exceeds the 2 GiB GitHub limit: $f"
done

# Create the release if it does not already exist.
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  TITLE="${TITLE:-$TAG}"
  printf 'Creating release %s in %s ...\n' "$TAG" "$REPO"
  gh release create "$TAG" --repo "$REPO" --title "$TITLE" --notes "${NOTES:-Video storage}"
fi

UPLOAD_ARGS=(upload "$TAG" "${FILES[@]}" --repo "$REPO")
[ "$CLOBBER" -eq 1 ] && UPLOAD_ARGS+=(--clobber)

printf 'Uploading %s file(s) to %s@%s ...\n' "${#FILES[@]}" "$REPO" "$TAG"
gh "${UPLOAD_ARGS[@]}"
printf 'Done. View: https://github.com/%s/releases/tag/%s\n' "$REPO" "$TAG"
