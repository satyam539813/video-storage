# GitHub Video Storage

A practical toolkit for converting, validating, and storing videos on GitHub
using GitHub's officially supported formats and upload paths.

> **Reality check.** GitHub is a code host, not a video locker or backup
> service. GitHub's Acceptable Use Policy (Section 9) reserves the right to
> throttle or delete repositories for "significantly excessive" bandwidth or
> infrastructure strain, and GitHub's own docs state: *"Git is not designed to
> serve as a backup tool."* Keep local copies of anything important.

## GitHub-supported video formats

GitHub plays videos inline in issues, pull requests, and comments.

| Container | Video codec | Audio codec | Notes |
|---|---|---|---|
| `.mp4` | H.264 (AVC) | AAC | **Recommended** — best browser compatibility |
| `.webm` | VP9 | Opus | Good, but not every encoding plays in every browser |
| `.mov` | H.264 | AAC | Supported, but MP4 is more portable |

GitHub recommends **H.264** for greatest compatibility.

## Upload paths and limits

| Path | Max per file | Total cap | Bandwidth | Use for |
|---|---|---|---|---|
| **Releases** | 2 GiB | None | None (AUP applies) | Storing / sharing video files |
| **Git LFS** | 2 GiB | 1 GB free | 1 GB free / month | Versioned files inside a repo |
| **Attachments** | 10 MB (free) / 100 MB (paid) | — | — | Small clips in issues / PRs |

Rules of thumb:

- **< 10 MB** → attach directly to an issue / PR comment (free plan).
- **10 MB – 2 GB** → **GitHub Releases** (best) or Git LFS.
- **> 2 GB** → split the video, or use a different service.

## Quick start

```bash
# 1. Convert a video to GitHub-compatible MP4 + WebM
./scripts/convert.sh myvideo.mkv

# 2. Validate the result against GitHub's limits
./scripts/check.sh myvideo.github.mp4

# 3a. Upload to a GitHub release (recommended; up to 2 GiB per file)
./scripts/upload-release.sh --repo <owner>/<repo> --tag v1 myvideo.github.mp4

# 3b. Or store in a repo with Git LFS (1 GB free tier)
./scripts/upload-lfs.sh myvideo.github.mp4
```

## Scripts

| Script | Purpose |
|---|---|
| `scripts/convert.sh` | Convert any video to GitHub-compatible MP4 / WebM |
| `scripts/check.sh` | Validate container, codec, and size against GitHub limits |
| `scripts/upload-release.sh` | Upload files to a GitHub release (no Git LFS needed) |
| `scripts/upload-lfs.sh` | Track and push videos with Git LFS |
| `scripts/list.sh` | List releases and their video assets |

## `convert.sh` — make any video GitHub-compatible

```bash
./scripts/convert.sh <input> [output-dir] [options]
```

Options:

- `--max-size MB` — target a maximum file size (video bitrate budget). Useful
  for hitting the 10 MB attachment limit.
- `--no-webm` / `--no-mp4` — skip one output.
- `-h`, `--help` — show help.

Outputs:

- `<name>.github.mp4` — H.264 + AAC, `yuv420p`, `+faststart`
- `<name>.github.webm` — VP9 + Opus

`+faststart` moves the MP4 index (`moov` atom) to the front of the file so
playback can begin before the whole file is downloaded — important for
streaming.

Examples:

```bash
./scripts/convert.sh myvideo.mkv                  # MP4 + WebM
./scripts/convert.sh myvideo.mkv ./out --max-size 10   # target 10 MB
./scripts/convert.sh myvideo.mkv --no-webm        # MP4 only
```

## `check.sh` — validate against GitHub's limits

```bash
./scripts/check.sh <file> [--limit MB]
```

Reports the container, video/audio codecs, duration, and size, then checks it
against GitHub's limits. Without `--limit`, it checks the 10 MB / 100 MB /
2 GiB thresholds. With `--limit`, it checks a custom threshold in MB.

Exit code is `0` if OK, `1` if it fails a hard check.

## `upload-release.sh` — the recommended path

GitHub Releases allow up to **1000 assets per release**, each under **2 GiB**,
with **no total size limit and no bandwidth limit**. This is the best way to
store video files on GitHub without Git LFS.

```bash
./scripts/upload-release.sh --repo OWNER/NAME --tag TAG [--title TITLE] \
    [--notes NOTES] [--clobber] <file>...
```

- The release is created automatically if the tag does not exist.
- `--clobber` replaces existing assets with the same name.

Requires the GitHub CLI (`gh`) authenticated with the `repo` scope.

Example:

```bash
./scripts/upload-release.sh \
  --repo satyam539813/video-storage \
  --tag v1 \
  --title "My videos" \
  clip.github.mp4
```

Download URL format:

```
https://github.com/OWNER/REPO/releases/download/TAG/FILENAME
```

## `upload-lfs.sh` — versioned storage in a repo

Git LFS keeps large files out of git history and stores them on GitHub's LFS
servers. Free tier: **1 GB storage, 1 GB bandwidth per month**.

```bash
./scripts/upload-lfs.sh <file>...
```

Requires `git-lfs` installed and a git repo with an `origin` remote.

## `list.sh` — inspect releases

```bash
./scripts/list.sh --repo OWNER/NAME            # list releases
./scripts/list.sh --repo OWNER/NAME --tag v1   # list assets in a release
```

## Caveats

- **Private repos:** release assets and LFS files are only accessible to
  people with repo access (or via an authenticated API token). Public repos
  expose assets to everyone.
- **Bandwidth:** no hard cap on Releases, but GitHub can act on "significantly
  excessive" usage (AUP Section 9). Don't hotlink release assets as a CDN.
- **Not a backup:** keep a local copy. GitHub can remove content under its
  policies.
- **Inline playback size:** attaching a video to an issue/PR is capped at
  10 MB on the free plan (100 MB on paid), regardless of repo size.
- **Repository size:** keep repos under ~1 GB ideally, under 5 GB at most.
