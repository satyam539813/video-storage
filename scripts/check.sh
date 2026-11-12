#!/usr/bin/env bash
# Check a video against GitHub's supported formats and size limits.
#
# GitHub supports: .mp4, .mov, .webm (H.264 recommended for compatibility).
# Limits:
#   10 MB   video attachments on a free plan
#   100 MB  video attachments on a paid plan
#   2 GiB   Git LFS / release asset per file (GitHub Free)
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check.sh <file> [--limit MB]

Reports the container, codecs, duration, and size, then checks them against
GitHub's limits. Exit code is 0 if OK, 1 on a hard failure.

Options:
  --limit MB   Check against a custom size limit in MB
  -h, --help   Show this help
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || die "ffprobe is not installed"

FILE=""
LIMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --limit) [ $# -ge 2 ] || die "--limit requires a value"; LIMIT="$2"; shift 2 ;;
    -*) die "Unknown option: $1" ;;
    *) [ -z "$FILE" ] || die "Too many arguments"; FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || { usage >&2; die "No file specified"; }
[ -f "$FILE" ] || die "File not found: $FILE"
if [ -n "$LIMIT" ]; then
  case "$LIMIT" in
    ''|*[!0-9]*) die "--limit must be a positive integer" ;;
  esac
fi

EXT="${FILE##*.}"
EXT="${EXT,,}"
case "$EXT" in
  mp4|mov|webm) ;;
  *) die "Unsupported container: .$EXT (GitHub supports .mp4, .mov, .webm)" ;;
esac

VCODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$FILE")
ACODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$FILE")
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FILE")

if stat -c %s "$FILE" >/dev/null 2>&1; then
  SIZE_BYTES=$(stat -c %s "$FILE")
else
  SIZE_BYTES=$(stat -f %z "$FILE")
fi
SIZE_MB=$(awk -v b="$SIZE_BYTES" 'BEGIN{printf "%.2f", b/1024/1024}')

printf 'File:        %s\n' "$FILE"
printf 'Container:   .%s\n' "$EXT"
printf 'Video codec: %s\n' "${VCODEC:-none}"
printf 'Audio codec: %s\n' "${ACODEC:-none}"
printf 'Duration:    %ss\n' "${DURATION%.*}"
printf 'Size:        %s MB\n' "$SIZE_MB"

STATUS=0

if [ "$EXT" = "mp4" ] && [ "$VCODEC" != "h264" ]; then
  printf 'WARN: GitHub recommends H.264 for MP4 (found: %s)\n' "$VCODEC"
  STATUS=1
fi

if [ -n "$LIMIT" ]; then
  if awk -v b="$SIZE_BYTES" -v l="$LIMIT" 'BEGIN{exit !(b > l*1024*1024)}'; then
    printf 'FAIL: %s MB exceeds the %s MB limit\n' "$SIZE_MB" "$LIMIT"
    STATUS=1
  else
    printf 'OK: within the %s MB limit\n' "$LIMIT"
  fi
else
  if awk -v b="$SIZE_BYTES" 'BEGIN{exit !(b > 2*1024*1024*1024)}'; then
    printf 'FAIL: exceeds 2 GiB (GitHub Free per-file limit)\n'
    STATUS=1
  elif awk -v b="$SIZE_BYTES" 'BEGIN{exit !(b > 100*1024*1024)}'; then
    printf 'WARN: exceeds 100 MB (paid-plan attachment limit); use Releases or Git LFS\n'
  elif awk -v b="$SIZE_BYTES" 'BEGIN{exit !(b > 10*1024*1024)}'; then
    printf 'WARN: exceeds 10 MB (free-plan attachment limit); use Releases or Git LFS\n'
  else
    printf 'OK: within the 10 MB free-plan attachment limit\n'
  fi
fi

exit "$STATUS"
