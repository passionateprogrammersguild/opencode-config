// OpenCode TUI plugin: push-to-talk dictation with local whisper.cpp.
//
// - Start/stop recording with one key (default: alt+v) or /voice
// - Records with ffmpeg's AVFoundation input (macOS); SoX `rec` as fallback
// - Transcribes locally with whisper-cli (whisper.cpp) — no cloud calls
// - Puts the transcript on the clipboard: press ctrl+v to paste into the
//   composer (review-before-send alt+shift+v submits straight to the session)
// - /voice-mic lists and selects the audio input device (persisted)
//
// Configure (optional) in cli.json:
//   "plugins": [{ "package": "<absolute-path-to-this-dir>", "options": {...} }]
// Options: bind, bindSubmit, model (absolute .bin path), language, inputDevice

import { spawn, spawnSync } from "child_process"
import { existsSync, mkdirSync, statSync, unlinkSync } from "fs"
import { homedir, tmpdir } from "os"
import { join } from "path"
import { Plugin } from "@opencode/plugin/tui"

const MODEL_URL_BASE = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
const MODEL_DIR = join(homedir(), ".cache", "opencode-voice")
const DEFAULT_MODEL = join(MODEL_DIR, "ggml-tiny.en.bin")

// Whisper hallucination artifacts for near-silence input (subtitle training data)
const HALLUCINATIONS = [
  "thanks for watching",
  "thank you for watching",
  "please subscribe",
  "subscribe to my channel",
  "amara.org",
  "subtitles by",
  "please like and subscribe",
]

// AVFoundation loopback/virtual devices that should never be auto-selected
const LOOPBACK_HINTS = ["microsoft teams audio", "loopback", "aggregate", "blackhole", "soundflower"]

interface ChildLike {
  kill(signal?: string): boolean
  stdin: { end(data?: string): void } | null
  on(event: "exit", listener: (code: number | null) => void): void
  once(event: "exit", listener: (code: number | null) => void): void
  pid?: number
}

function waitExit(child: any): Promise<number | null> {
  return new Promise((resolve) => {
    if (child.exitCode !== null) return resolve(child.exitCode)
    child.once("exit", (code: number | null) => resolve(code))
  })
}

/** Run a command capturing stdout as text, with a hard timeout. */
function readOutChild(
  cmd: string,
  args: string[],
  timeoutMs: number,
): Promise<{ code: number; text: string }> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "ignore"] } as any)
    let text = ""
    child.stdout!.setEncoding("utf8")
    child.stdout!.on("data", (chunk: string) => (text += chunk))
    const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs)
    child.on("exit", (code: number | null) => {
      clearTimeout(timer)
      resolve({ code: code ?? -1, text })
    })
    child.on("error", () => {
      clearTimeout(timer)
      resolve({ code: -1, text })
    })
  })
}

function runQuiet(cmd: string, args: string[], timeoutMs = 300_000): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { stdio: "ignore" } as any)
    const timer = setTimeout(() => {
      child.kill("SIGKILL")
      resolve(-1)
    }, timeoutMs)
    child.on("exit", (code: number | null) => {
      clearTimeout(timer)
      resolve(code ?? -1)
    })
    child.on("error", () => {
      clearTimeout(timer)
      resolve(-1)
    })
  })
}

function toolAvailable(tool: string): boolean {
  const res = spawnSync("which", [tool], { encoding: "utf8" })
  return res.status === 0 && (res.stdout ?? "").trim() !== ""
}

/** List AVFoundation audio capture devices as { index, name }. */
function listAudioDevices(): Promise<{ index: number; name: string }[]> {
  return new Promise((resolve) => {
    const child = spawn("ffmpeg", ["-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""], {
      stdio: ["ignore", "pipe", "pipe"],
    } as any)
    let out = ""
    child.stdout!.on("data", (c: string) => (out += c))
    child.stderr!.on("data", (c: string) => (out += c))
    const timer = setTimeout(() => child.kill("SIGKILL"), 10_000)
    child.on("exit", () => {
      clearTimeout(timer)
      const devices: { index: number; name: string }[] = []
      for (const line of out.split("\n")) {
        const m = line.match(/\[(\d+)\]\s+(.+?)\s+\[uid:/)
        if (m) devices.push({ index: Number(m[1]), name: m[2].trim() })
      }
      resolve(devices)
    })
    child.on("error", () => {
      clearTimeout(timer)
      resolve([])
    })
  })
}

async function copyToClipboard(text: string): Promise<boolean> {
  const tool = toolAvailable("pbcopy")
    ? "pbcopy"
    : toolAvailable("wl-copy")
      ? "wl-copy"
      : toolAvailable("xclip")
        ? "xclip"
        : null
  if (!tool) return false
  return new Promise((resolve) => {
    try {
      const args = tool === "xclip" ? ["-selection", "clipboard"] : []
      const p = spawn(tool, args, { stdio: ["pipe", "ignore", "ignore"] } as any)
      p.stdin!.end(text)
      p.stdin!.on("error", () => resolve(false))
      p.on("exit", () => resolve(true))
      return
    } catch {
      resolve(false)
    }
  })
}

function cleanTranscript(raw: string): string {
  const text = raw
    .replace(/\r/g, "")
    .split(/\n+/)
    .map((l) => l.trim())
    .filter(Boolean)
    .join(" ")
    .trim()
    .replace(/^[...…,\s]+/, "")
    .replace(/[...…]+$/, "")
  const lowered = text.toLowerCase()
  for (const h of HALLUCINATIONS) {
    if (lowered === h.replace(/[.!]+$/, "")) return ""
    if (lowered.startsWith(h) && lowered.length <= h.length + 5) return ""
  }
  return text
}

async function ensureModel(model: string, toast: any): Promise<boolean> {
  if (existsSync(model)) return true
  mkdirSync(MODEL_DIR, { recursive: true })
  const fileName = model.split("/").pop() ?? "ggml-tiny.en.bin"
  const approxMB = fileName.includes("base") ? 148 : fileName.includes("small") ? 466 : 77
  toast.show({ title: "Voice", message: `Downloading whisper model (~${approxMB} MB)…`, duration: 15_000 })
  const url = MODEL_URL_BASE + fileName
  const code = await runQuiet("curl", ["-fL", "--retry", "2", "-o", model, url], 900_000)
  const ok = code === 0 && existsSync(model) && statSync(model).size > 50_000_000
  if (!ok) {
    try { unlinkSync(model) } catch {}
  }
  return ok
}

export default Plugin.define({
  id: "voice-dictation",
  setup(context: any) {
    const opts = (context.options ?? {}) as Record<string, unknown>
    const bind = typeof opts.bind === "string" ? opts.bind : "alt+v"
    const bindSubmit = typeof opts.bindSubmit === "string" ? opts.bindSubmit : "alt+shift+v"
    const model = typeof opts.model === "string" ? opts.model : DEFAULT_MODEL
    const language = typeof opts.language === "string" ? opts.language : "en"

    const toast = context.ui.toast

    // Persisted device preference: index + human name (index can shift after reconnects).
    let [settings, updateSettings] = context.storage.store("settings", {
      initial: { deviceIndex: -1, deviceName: "" } as { deviceIndex: number; deviceName: string },
    })
    const readSettings = () => (typeof settings === "function" ? settings() : settings) as {
      deviceIndex: number
      deviceName: string
    }

    type State = "idle" | "recording" | "busy"
    let state: State = "idle"
    let child: ChildLike | null = null
    let wav: string | null = null
    let recordError = ""

    const fail = (message: string) => toast.show({ title: "Voice", message, variant: "error" })
    const say = (message: string, variant: string, duration = 5000) =>
      toast.show({ title: "Voice", message, variant: variant as any, duration })

    function currentSessionID(): string | undefined {
      try {
        const route = context.ui.router.current() as any
        if (route?.type === "session" && route.sessionID) return String(route.sessionID)
      } catch {}
      return undefined
    }

    /** Resolve the avfoundation audio index to record from. */
    async function resolveDevice(): Promise<number | undefined> {
      const stored = readSettings()
      const configured = typeof opts.inputDevice === "number" ? opts.inputDevice : undefined
      if (configured !== undefined && configured >= 0) return configured
      const devices = await listAudioDevices()
      if (!devices.length) return undefined
      // Prefer the previously chosen name, then a non-loopback first device.
      if (stored.deviceName) {
        const match = devices.find((d) => d.name === stored.deviceName)
        if (match) return match.index
      }
      const usable = devices.find(
        (d) => !LOOPBACK_HINTS.some((hint) => d.name.toLowerCase().includes(hint)),
      )
      return (usable ?? devices[0]).index
    }

    async function pickMic() {
      const devices = await listAudioDevices()
      if (!devices.length) {
        fail("No audio input devices found (check Bluetooth connection / macOS mic permission).")
        return
      }
      const currentIdx = await resolveDevice()
      const device = await context.ui.dialog.select({
        title: "Microphone",
        current: devices.find((d) => d.index === currentIdx)?.name,
        options: devices.map((d) => ({
          title: d.name,
          value: String(d.index),
          description: LOOPBACK_HINTS.some((hint) => d.name.toLowerCase().includes(hint))
            ? "virtual / loopback device"
            : undefined,
        })),
      })
      if (device === undefined) return
      const chosen = devices.find((d) => d.index === Number(device))
      if (!chosen) return
      await updateSettings((draft: any) => {
        draft.deviceIndex = chosen.index
        draft.deviceName = chosen.name
      })
      say(`Microphone: ${chosen.name}`, "success", 4000)
    }

    async function startRecording(autoSubmit: boolean) {
      const useFfmpeg = toolAvailable("ffmpeg")
      if (!useFfmpeg && !toolAvailable("rec")) {
        fail("Missing recorder: install ffmpeg (recommended) or sox.")
        return
      }
      if (!toolAvailable("whisper-cli")) {
        fail("Missing whisper-cli — see plugins/voice-dictation/README.md.")
        return
      }
      if (!(await ensureModel(model, toast))) {
        fail("Whisper model download failed. Set options.model to an existing ggml .bin file.")
        return
      }

      wav = join(tmpdir(), `opencode-voice-${process.pid}-${Date.now()}.wav`)
      recordError = ""
      try {
        let p: ChildLike
        if (useFfmpeg) {
          const device = await resolveDevice()
          if (device === undefined) {
            fail("No microphone found. Connect your headset or run /voice-mic.")
            wav = null
            return
          }
          say(`🎙 Recording (mic ${device}) — same key again to stop`, "info", 60_000)
          p = spawn(
            "ffmpeg",
            [
              "-hide_banner",
              "-loglevel", "error",
              "-f", "avfoundation",
              "-i", `:${device}`,
              "-ac", "1",
              "-ar", "16000",
              "-y", wav,
            ],
            { stdio: ["ignore", "ignore", "pipe"] } as any,
          ) as ChildLike
          // Capture stderr so a failed open (permissions, busy device) is reportable.
          ;(p as any).stderr?.setEncoding?.("utf8")
          ;(p as any).stderr?.on?.("data", (chunk: string) => {
            recordError = (recordError + chunk).slice(-2000)
          })
        } else {
          say("🎙 Recording (sox) — same key again to stop", "info", 60_000)
          p = spawn("rec", ["-q", "-r", "16000", "-c", "1", wav], { stdio: "ignore" } as any) as ChildLike
        }

        p.on("exit", (code: number | null) => {
          // Failed to even open the device: ffmpeg exits while we think we're recording.
          if (state === "recording" && code !== 0) {
            state = "idle"
            child = null
            if (wav) {
              try { unlinkSync(wav) } catch {}
              wav = null
            }
            const detail = recordError.trim().split("\n").slice(-2).join(" ") || `exit ${code}`
            fail(`Recorder failed: ${detail}`)
          }
        })
        child = p
        state = "recording"
      } catch (e: any) {
        state = "idle"
        wav = null
        fail(`Could not start recording: ${e?.message ?? e}`)
      }
    }

    async function stopRecording(autoSubmit: boolean) {
      if (!child || !wav) return
      const proc = child
      child = null
      state = "busy"
      // ffmpeg and sox both finalize the WAV on SIGINT
      proc.kill("SIGINT")
      const timer = setTimeout(() => proc.kill("SIGKILL"), 3000)
      await waitExit(proc)
      clearTimeout(timer)
      try {
        if (!existsSync(wav) || statSync(wav).size < 1024) {
          fail(recordError.trim() ? `Recording failed: ${recordError.trim().split("\n").slice(-2).join(" ")}` : "Recording was empty.")
          state = "idle"
          return
        }
        const res = await readOutChild(
          "whisper-cli",
          ["-m", model, "-f", wav, "-l", language, "-nt", "-np"],
          120_000,
        )
        const text = cleanTranscript(res.text)
        if (!text) {
          fail("No speech detected — check the mic is unmuted and macOS mic permission is granted.")
          state = "idle"
          return
        }

        if (autoSubmit) {
          const sessionID = currentSessionID()
          if (sessionID) {
            try {
              await context.client.session.prompt({ sessionID, text })
              say(`🎙 Submitted: ${text.length > 60 ? text.slice(0, 60) + "…" : text}`, "success")
              state = "idle"
              return
            } catch (e: any) {
              fail(`Submit failed (${e?.message ?? e}); copying to clipboard instead.`)
            }
          } else {
            fail("No active session — copy to clipboard instead (open a session tab first).")
          }
        }

        const copied = await copyToClipboard(text)
        say(
          copied
            ? `🎙 Ready: ${text.length > 60 ? text.slice(0, 60) + "…" : text} — ctrl+v to paste`
            : text,
          copied ? "success" : "info",
          10_000,
        )
        state = "idle"
      } catch (e: any) {
        fail(`Transcription failed: ${e?.message ?? e}`)
        state = "idle"
      } finally {
        try { unlinkSync(wav) } catch {}
        wav = null
      }
    }

    function cancelRecording() {
      if (!child) return
      const proc = child
      child = null
      state = "idle"
      proc.kill("SIGKILL")
      if (wav) {
        try { unlinkSync(wav) } catch {}
        wav = null
      }
      say("Recording cancelled", "info", 4000)
    }

    async function toggle(autoSubmit: boolean) {
      if (state === "idle") return startRecording(autoSubmit)
      if (state === "recording") return stopRecording(autoSubmit)
      say("Still transcribing the previous take…", "info", 4000)
    }

    context.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "voice.toggle",
          title: "Voice: start / stop dictation",
          group: "Voice",
          bind,
          palette: true,
          slash: { name: "voice" },
          run: () => toggle(false),
        },
        {
          id: "voice.submit",
          title: "Voice: stop & submit transcript",
          group: "Voice",
          bind: bindSubmit,
          palette: true,
          slash: { name: "voice-submit" },
          run: () => toggle(true),
        },
        {
          id: "voice.mic",
          title: "Voice: select microphone",
          group: "Voice",
          palette: true,
          slash: { name: "voice-mic" },
          run: pickMic,
        },
        {
          id: "voice.cancel",
          title: "Voice: cancel recording",
          group: "Voice",
          palette: true,
          slash: { name: "voice-cancel" },
          enabled: () => state === "recording",
          run: cancelRecording,
        },
      ],
    }))

    // Kill any live recording when the plugin unloads.
    return () => {
      if (child) {
        child.kill("SIGKILL")
        child = null
      }
      if (wav) {
        try { unlinkSync(wav) } catch {}
        wav = null
      }
    }
  },
})
