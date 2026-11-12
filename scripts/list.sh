#!/usr/bin/env bash
# List releases and their video assets for a GitHub repository.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: list.sh --repo OWNER/NAME [--tag TAG]

Lists releases, or the assets of a specific release.

Options:
  --repo OWNER/NAME   Repository (e.g. satyam539813/video-storage)
  --tag TAG           Show assets for this release tag
  -h, --help          Show this help
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

REPO=""
TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --repo) [ $# -ge 2 ] || die "--repo requires a value"; REPO="$2"; shift 2 ;;
    --tag) [ $# -ge 2 ] || die "--tag requires a value"; TAG="$2"; shift 2 ;;
    -*) die "Unknown option: $1" ;;
    *) die "Unexpected argument: $1" ;;
  esac
done

[ -n "$REPO" ] || die "--repo is required"

if [ -n "$TAG" ]; then
  gh release view "$TAG" --repo "$REPO" --json tagName,assets \
    --jq '"Release: \(.tagName)", (.assets[] | "  \(.name)\t\(.size) bytes\t\(.apiUrl)")'
else
  gh release list --repo "$REPO"
fi
