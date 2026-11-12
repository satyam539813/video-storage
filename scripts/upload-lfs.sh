#!/usr/bin/env bash
# Store videos in a git repository using Git LFS.
#
# Git LFS keeps large files out of git history and stores them on GitHub's
# LFS servers. Free tier: 1 GB storage, 1 GB bandwidth/month.
# Per-file limit: 2 GB (GitHub Free).
#
# Requires: git-lfs installed (https://git-lfs.com), a git repository, and an
# `origin` remote.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: upload-lfs.sh <file>...

Tracks the given video files with Git LFS, commits, and pushes.

Examples:
  upload-lfs.sh clip.mp4
  upload-lfs.sh *.mp4
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is not installed"
command -v git-lfs >/dev/null 2>&1 || die "git-lfs is not installed. See https://git-lfs.com"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"
git remote get-url origin >/dev/null 2>&1 || die "No 'origin' remote configured"

[ $# -gt 0 ] || { usage >&2; die "No files specified"; }

for f in "$@"; do
  [ -f "$f" ] || die "File not found: $f"
done

git lfs install >/dev/null

# Track video extensions (idempotent).
for ext in mp4 webm mov mkv avi; do
  git lfs track "*.$ext" >/dev/null
done

git add .gitattributes
git add "$@"

if git diff --cached --quiet; then
  echo "Nothing to commit."
  exit 0
fi

git commit -m "Add video files via Git LFS"
git push
echo "Pushed. Note: LFS free tier is 1 GB storage / 1 GB bandwidth per month."
