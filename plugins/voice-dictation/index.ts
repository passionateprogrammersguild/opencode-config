// Server-side entry point (required by the plugin layout).
// Dictation runs entirely in the TUI plugin below; nothing to do on the server.
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "voice-dictation",
  setup() {},
})
