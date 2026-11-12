#!/usr/bin/env bash
# Convert a video to GitHub-supported, browser-playable formats.
#
# GitHub supports .mp4, .mov, and .webm for inline playback in issues,
# pull requests, and comments. H.264 is recommended for compatibility.
#
# Outputs:
#   <name>.github.mp4   H.264 + AAC, yuv420p, faststart (recommended)
#   <name>.github.webm  VP9 + Opus
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: convert.sh <input> [output-dir] [options]

Options:
  --max-size MB   Target maximum output size in MB (video bitrate budget)
  --no-webm       Skip the WebM output
  --no-mp4        Skip the MP4 output
  -h, --help      Show this help

Examples:
  convert.sh myvideo.mkv
  convert.sh myvideo.mkv ./out --max-size 10
  convert.sh myvideo.mkv --no-webm
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is not installed"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe is not installed"

INPUT=""
OUTDIR=""
MAX_SIZE=""
MP4=1
WEBM=1

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --max-size)
      [ $# -ge 2 ] || die "--max-size requires a value"
      MAX_SIZE="$2"
      shift 2
      ;;
    --no-webm) WEBM=0; shift ;;
    --no-mp4) MP4=0; shift ;;
    -*) die "Unknown option: $1" ;;
    *)
      if [ -z "$INPUT" ]; then
        INPUT="$1"
      elif [ -z "$OUTDIR" ]; then
        OUTDIR="$1"
      else
        die "Too many arguments"
      fi
      shift
      ;;
  esac
done

[ -n "$INPUT" ] || { usage >&2; die "No input file specified"; }
[ -f "$INPUT" ] || die "Input file not found: $INPUT"
{ [ "$MP4" -eq 1 ] || [ "$WEBM" -eq 1 ]; } || die "Both MP4 and WebM are disabled; nothing to do"

if [ -n "$MAX_SIZE" ]; then
  case "$MAX_SIZE" in
    ''|*[!0-9]*) die "--max-size must be a positive integer" ;;
  esac
fi

OUTDIR="${OUTDIR:-$(dirname "$INPUT")}"
mkdir -p "$OUTDIR"

BASE="$(basename "$INPUT")"
BASE="${BASE%.*}"

DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
DURATION_INT=${DURATION%.*}
{ [ -n "$DURATION_INT" ] && [ "$DURATION_INT" -gt 0 ] 2>/dev/null; } || die "Could not determine video duration"

HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$INPUT" | head -n 1)

# Video bitrate budget for --max-size, with a 5% safety margin for container
# overhead. Audio is assumed to be 128 kbps.
VBR=""
if [ -n "$MAX_SIZE" ]; then
  BITS=$(( MAX_SIZE * 1024 * 1024 * 8 * 95 / 100 ))
  VBR=$(( BITS / DURATION_INT - 128000 ))
  [ "$VBR" -gt 100000 ] || VBR=100000
  printf 'Target: %s MB -> video bitrate %s bps\n' "$MAX_SIZE" "$VBR"
fi

MP4_RATE=()
WEBM_RATE=(-crf 30 -b:v 0)
if [ -n "$VBR" ]; then
  MP4_RATE=(-b:v "$VBR")
  WEBM_RATE=(-b:v "$VBR")
fi

if [ "$MP4" -eq 1 ]; then
  OUT="$OUTDIR/$BASE.github.mp4"
  AUDIO_ARGS=(-c:a aac -b:a 128k)
  [ "$HAS_AUDIO" = "audio" ] || AUDIO_ARGS=(-an)
  ffmpeg -y -hide_banner -loglevel error -i "$INPUT" \
    -c:v libx264 -preset medium -profile:v high -level 4.0 \
    -pix_fmt yuv420p -movflags +faststart \
    "${MP4_RATE[@]}" \
    "${AUDIO_ARGS[@]}" \
    "$OUT"
  printf 'MP4:  %s\n' "$OUT"
fi

if [ "$WEBM" -eq 1 ]; then
  OUT="$OUTDIR/$BASE.github.webm"
  AUDIO_ARGS=(-c:a libopus -b:a 128k)
  [ "$HAS_AUDIO" = "audio" ] || AUDIO_ARGS=(-an)
  ffmpeg -y -hide_banner -loglevel error -i "$INPUT" \
    -c:v libvpx-vp9 -row-mt 1 \
    "${WEBM_RATE[@]}" \
    "${AUDIO_ARGS[@]}" \
    "$OUT"
  printf 'WebM: %s\n' "$OUT"
fi
