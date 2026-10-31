/**
 * llama-bridge plugin — opencode 2.0 compatible.
 * 
 * This plugin does NOT register command hooks (opencode 2.0 plugin API
 * is minimal / defensive). Instead it provides module-level information
 * and links to the working command-based bridge:
 * 
 *   /llama-switch    — switch server model + sync opencode.json
 *   /llama-sync      — rebuild model list from ~/models/*.gguf  
 *   /llama-evaluate  — validate server vs config
 *   /llama-chat      — direct curl prompt (bypasses provider package)
 * 
 * Root cause fixed in opencode.json: OpenCode V2 requires the `package`
 * field (@opencode/ai/providers/openai-compatible). The V1 `npm` field with
 * @ai-sdk/* names raises UnsupportedPackageError in V2. Also `settings`
 * (not `options`) and `capabilities` (not `modalities`).
 */
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "llama-bridge",
  setup() {
    // Bridge is implemented via command files:
    // /llama-switch.md, /llama-sync.md, /llama-evaluate.md, /llama-chat.md
    // Plugin exists to document integration and provide future hooks.
  },
})
