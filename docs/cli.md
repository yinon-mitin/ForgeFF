# ForgeFF CLI

ForgeFF supports terminal arguments in addition to the main macOS GUI. The GUI remains the primary interface for queue management, presets, interactive settings, Apple HDR-to-SDR conversion, and diagnostics.

The helper is available at `script/forgeff` from the repository root.

## Commands

### Send files to the GUI

```bash
./script/forgeff add FILE [FILE ...]
```

This sends one or more files to the running or newly launched ForgeFF application through macOS Open With handling. The GUI then analyzes and queues the files using its current settings.

### Headless conversion

```bash
./script/forgeff convert INPUT [OPTIONS]
```

The headless path invokes the configured FFmpeg executable directly. It is intended for automation and shell workflows.

## Complete option index

| Option | Values | Default | Description |
|---|---|---|---|
| `--preset NAME` | `telegram`, `efficient-hevc` | `telegram` | Select a built-in CLI preset. |
| `--output FILE` | filesystem path | generated name | Write to an exact output path. Overrides `--output-dir`. |
| `--output-dir DIRECTORY` | filesystem path | directory of input | Create and use the output directory. |
| `--container FORMAT` | `mp4`, `mov`, `mkv` | preset-dependent | Select the output container. |
| `--video-preset PRESET` | `veryfast`, `faster`, `fast`, `medium`, `slow`, `slower`, `veryslow`, `placebo` | `medium` | Override the FFmpeg video encoder preset. |
| `--crf VALUE` | non-negative integer | preset-dependent | Override the video CRF value. |
| `--audio-bitrate RATE` | e.g. `128k`, `1M` | preset-dependent | Override the audio bitrate. |
| `--audio-channels COUNT` | positive integer | source/default | Request a specific number of output audio channels. |
| `--video-bitrate RATE` | e.g. `2500k`, `1M` | preset-dependent | Override video bitrate. |
| `--sample-rate RATE` | positive integer | source/default | Override audio sample rate. |
| `--metadata MODE` | `keep`, `remove` | `keep` | Keep or remove metadata and chapters. |
| `--web-optimization` | flag | off | Enable fast-start output for MP4/MOV. |
| `--progress` | flag | off | Emit FFmpeg progress records on stdout. |
| `--resolution WIDTHxHEIGHT` | positive dimensions | source dimensions | Scale video to the requested dimensions. |
| `--frame-rate RATE` | positive number | source frame rate | Override the output video frame rate. |
| `--remove-subtitles` | flag | off | Remove embedded and external subtitle streams. |
| `--video-codec CODEC` | `h264`, `hevc`, `vp9`, `av1`, `prores` | preset-dependent | Select the video encoder. |
| `--audio-codec CODEC` | `copy`, `aac`, `mp3` | preset-dependent | Select the audio encoder. |
| `--external-audio FILE` | readable file path | none | Add an external audio stream. Repeat for multiple tracks; order is preserved. |
| `--subtitle FILE` | readable SRT path | none | Add an external subtitle stream. Repeat for multiple files. |
| `--audio-only` | flag | off | Omit video and produce an audio-only output. |
| `--overwrite` | flag | off | Replace an existing output instead of refusing to overwrite it. |
| `--dry-run` | flag | off | Print the generated FFmpeg command without executing it. |
| `--help`, `-h` | flag | — | Print command help. |

The output name is derived from the input name as `<input-basename>_<preset>.<container>`.

## Examples

```bash
./script/forgeff convert ~/Movies/source.mkv \
  --preset telegram \
  --output-dir ~/Movies/converted

./script/forgeff convert ~/Movies/source.mkv \
  --preset efficient-hevc \
  --external-audio ~/Audio/commentary.wav \
  --external-audio ~/Audio/translation.mp3 \
  --subtitle ~/Subtitles/en.srt \
  --output-dir ~/Movies/converted \
  --overwrite

./script/forgeff convert ~/Recordings/voice.mp3 \
  --audio-only \
  --audio-codec aac \
  --container mp4 \
  --dry-run
```

## Runtime requirements

- macOS shell environment;
- an executable FFmpeg, normally `/opt/homebrew/bin/ffmpeg`;
- readable input and attachment files;
- an output directory that can be created or written.

For another FFmpeg location, set `FORGEFF_FFMPEG_BINARY`:

```bash
FORGEFF_FFMPEG_BINARY=/path/to/ffmpeg \
  ./script/forgeff convert input.mkv --preset telegram
```

## Scope and limitations

- CLI conversion currently exposes a deliberately smaller option set than the GUI.
- The CLI does not yet share the Swift conversion engine with the GUI; both paths use explicit FFmpeg operations but are maintained separately.
- Apple `avconvert` HDR-to-SDR processing is currently available through the GUI pipeline, not through `forgeff convert`.
- Unsupported codecs, containers, missing files, and unavailable FFmpeg executables fail with a non-zero exit status and a diagnostic on stderr.
