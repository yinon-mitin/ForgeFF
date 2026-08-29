#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_root/script/forgeff"
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

fake_open="$temp_root/open"
log="$temp_root/open.log"
file_a="$temp_root/a.mp4"
file_b="$temp_root/b.mkv"
touch "$file_a" "$file_b"

cat > "$fake_open" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FORGEFF_TEST_LOG"
EOF
chmod +x "$fake_open"

if "$cli" --help >/dev/null 2>&1; then :; else
    printf 'help command failed\n' >&2
    exit 1
fi

if "$cli" add >/dev/null 2>&1; then
    printf 'missing argument was accepted\n' >&2
    exit 1
fi

if FORGEFF_OPEN_BINARY="$fake_open" FORGEFF_TEST_LOG="$log" "$cli" add "$file_a" "$file_b"; then :; else
    printf 'add command failed\n' >&2
    exit 1
fi

expected=$'-a ForgeFF '"$file_a"$'\n-a ForgeFF '"$file_b"
actual="$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).read_text(), end="")' "$log")"
if [[ "$actual" != "$expected" ]]; then
    printf 'unexpected open invocation:\n%s\n' "$actual" >&2
    exit 1
fi

if FORGEFF_OPEN_BINARY="$fake_open" FORGEFF_TEST_LOG="$log" "$cli" add "$temp_root/missing.mp4" >/dev/null 2>&1; then
    printf 'missing file was accepted\n' >&2
    exit 1
fi

fake_ffmpeg="$temp_root/ffmpeg"
ffmpeg_log="$temp_root/ffmpeg.log"
cat > "$fake_ffmpeg" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FORGEFF_TEST_FFMPEG_LOG"
touch "${!#}"
EOF
chmod +x "$fake_ffmpeg"

if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_a" --preset telegram --output-dir "$temp_root/out" --overwrite; then :; else
    printf 'convert command failed\n' >&2
    exit 1
fi

if ! python3 -c 'import pathlib,sys; text=pathlib.Path(sys.argv[1]).read_text(); assert "-c:v libx264" in text and "-c:a aac" in text and "-movflags +faststart" in text' "$ffmpeg_log"; then
    printf 'convert did not build telegram arguments\n' >&2
    exit 1
fi

external="$temp_root/voice track.wav"
subtitle="$temp_root/subtitles.srt"
touch "$external"
printf '1\n00:00:00,000 --> 00:00:01,000\nHello\n' > "$subtitle"
: > "$ffmpeg_log"
if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_b" --preset efficient-hevc --external-audio "$external" --subtitle "$subtitle" --output-dir "$temp_root/out2" --overwrite; then :; else
    printf 'external media convert failed\n' >&2
    exit 1
fi
if ! python3 -c 'import pathlib,sys; text=pathlib.Path(sys.argv[1]).read_text(); assert "libx265" in text and "-map 1:a:0?" in text and "-map 2:0" in text and "-c:s mov_text" in text' "$ffmpeg_log"; then
    printf 'convert did not build external media arguments\n' >&2
    exit 1
fi

custom_output="$temp_root/custom-output.mkv"
: > "$ffmpeg_log"
if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_a" --output "$custom_output" --video-preset slow --crf 18 --audio-bitrate 128k --audio-channels 1 --overwrite; then :; else
    printf 'custom conversion options failed\n' >&2
    exit 1
fi
if ! python3 -c 'import pathlib,sys; text=pathlib.Path(sys.argv[1]).read_text(); assert "-preset slow" in text and "-crf 18" in text and "-b:a 128k" in text and "-ac 1" in text and text.rstrip().endswith(sys.argv[2])' "$ffmpeg_log" "$custom_output"; then
    printf 'custom conversion arguments were not applied\n' >&2
    exit 1
fi

if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_a" --resolution 1280x720 --frame-rate 30 --remove-subtitles --dry-run >"$temp_root/image-options.txt"; then :; else
    printf 'image options failed\n' >&2
    exit 1
fi
if ! python3 -c 'import pathlib,sys; text=pathlib.Path(sys.argv[1]).read_text(); assert "-vf scale=1280:720" in text and "-r 30" in text and "-sn" in text' "$temp_root/image-options.txt"; then
    printf 'image options were not applied\n' >&2
    exit 1
fi

if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_a" --video-bitrate 2500k --sample-rate 48000 --metadata remove --web-optimization --progress --dry-run >"$temp_root/advanced-options.txt"; then :; else
    printf 'advanced options failed\n' >&2
    exit 1
fi
if ! python3 -c 'import pathlib,sys; text=pathlib.Path(sys.argv[1]).read_text(); assert "-b:v 2500k" in text and "-ar 48000" in text and "-map_metadata -1" in text and "-map_chapters -1" in text and "-movflags +faststart" in text and "-progress pipe:1" in text' "$temp_root/advanced-options.txt"; then
    printf 'advanced options were not applied\n' >&2
    exit 1
fi

if FORGEFF_FFMPEG_BINARY="$fake_ffmpeg" FORGEFF_TEST_FFMPEG_LOG="$ffmpeg_log" "$cli" convert "$file_a" --container avi >/dev/null 2>&1; then
    printf 'unsupported container was accepted\n' >&2
    exit 1
fi

printf 'CLI tests passed\n'
