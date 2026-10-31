# voice-dictation (OpenCode CLI/TUI plugin)

Push-to-talk dictation with **fully local** whisper.cpp — no cloud calls.

## Usage (after a TUI restart or `/reload`)

| Action | Command | Default key |
| --- | --- | --- |
| Start / stop recording | `/voice` (or command palette) | `alt+v` |
| Stop and **submit** straight to the session | `/voice-submit` | `alt+shift+v` |
| Cancel recording | `/voice-cancel` (palette only, while recording) | — |

Default flow: press `alt+v`, talk, press `alt+v` again → transcript is copied to the
clipboard → press `ctrl+v` in the composer to paste (review-before-send). `alt+shift+v`
skips the clipboard and submits directly to the current session.

## Requirements

- `rec` (SoX): `brew install sox`
- `whisper-cli` (whisper.cpp v1.9.5): installed at `~/.opencode/bin/whisper-cli`
  (built from source; `brew install simdutf` currently fails on this Intel Mac,
  so the brew formula can't complete — see `~/.cache/opencode-voice/whisper.cpp`)
- Whisper model: `~/.cache/opencode-voice/ggml-tiny.en.bin` (default, 77 MB,
  ~1× realtime on this Intel Mac — a 10 s take transcribes in ~10–20 s). Set
  `options.model` to `~/.cache/opencode-voice/ggml-base.en.bin` or
  `ggml-small.en.bin` for better accuracy at a large speed cost.

## Configuration (optional)

Auto-discovered from `~/.config/opencode/plugins/`, so it loads with defaults. To pass
options instead, register it in `~/.config/opencode/cli.json` (and remove it from the
plugin discovery directory so it doesn't load twice):

```json
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "plugins": [
    {
      "package": "/Users/mmann2943/.config/opencode/plugins/voice-dictation",
      "options": {
        "bind": "alt+v",
        "bindSubmit": "alt+shift+v",
        "model": "/Users/mmann2943/.cache/opencode-voice/ggml-base.en.bin",
        "language": "en"
      }
    }
  ]
}
```

- `bind` / `bindSubmit` — if your terminal doesn't transmit `alt` (Option) keys
  (e.g. stock Terminal.app), pick something else, e.g. `"ctrl+g"`.
- `model` — any ggml `.bin` (e.g. `ggml-small.en` for accuracy, `ggml-tiny.en` for speed).
- `language` — whisper language code; with an `.en` model use `en`.

## Design notes

- Recording uses `rec -r 16000 -c 1`, transcoding-free for whisper-cli input.
- Sox finalizes the WAV header on `SIGINT`; the plugin sends `SIGINT` first, with a
  `SIGKILL` fallback after 3 s.
- Near-silence hallucinations ("Thanks for watching"…) from whisper's subtitle
  training data are filtered out and reported as "No speech detected".
- Composer injection is clipboard-based because the CLI-plugin API doesn't expose a
  direct "insert into the prompt" surface; clipboard + `ctrl+v` is the documented,
  reliable bridge (same pattern used by community plugins).
