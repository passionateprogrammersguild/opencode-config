import { Plugin } from "@opencode/plugin";
import * as V1PluginModule from "@mrgray17/opentoken";

// This adapter wraps the V1 opentoken plugin to make it compatible with OpenCode V2

async function setup(ctx) {
  
  // The V1 plugin exports an async function as default
  const V1PluginSetup = V1PluginModule.default || V1PluginModule.plugin_default;
  
  if (typeof V1PluginSetup !== "function") {
    throw new Error("Invalid V1 plugin structure - cannot find plugin setup function");
  }
  
  // Execute the V1 plugin setup to get its hooks
  // We need to capture the hooks it returns
  let pluginHooks = {};
  let cleanupPromises: Promise<void>[] = [];
  
  try {
    // Execute the V1 plugin with a minimal directory structure
    pluginHooks = await V1PluginSetup({
      directory: ctx.location || "."
    });
    
    // Convert the V1 hooks to V2 format and register them
    await registerV1Hooks(ctx, pluginHooks);
    
    // Return cleanup function
    return () => {
      if (cleanupPromises.length > 0) {
        return Promise.allSettled(cleanupPromises);
      }
    };
    
  } catch (error) {
    console.error("Failed to initialize V1 plugin adapter:", error);
    // Return a no-op cleanup
    return () => Promise.resolve();
  }
}

async function registerV1Hooks(ctx, v1Hooks) {
  // Convert V1 plugin hooks to V2 format
  // V1 plugins have a different structure - we need to adapt each hook type
  
  if (!v1Hooks) {
    return;
  }
  
  // Handle tool hooks
  if (v1Hooks.tool && typeof v1Hooks.tool === "object") {
    const toolHooks = v1Hooks.tool;
    
    if (toolHooks.opentoken_stats) {
      await ctx.tool.add("opentoken_stats", async () => {
        // Execute the V1 plugin's opentoken_stats tool
        try {
          const sessionID = getSessionIDFromV1Context(ctx);
          return await toolHooks.opentoken_stats({}, { sessionID, location: ctx.location });
        } catch (error) {
          console.error("V1 plugin opentoken_stats tool error:", error);
          return { output: `Error: ${error.message}` };
        }
      });
    }
    
    if (toolHooks.opentoken_health) {
      await ctx.tool.add("opentoken_health", async () => {
        try {
          const sessionID = getSessionIDFromV1Context(ctx);
          return await toolHooks.opentoken_health({}, { sessionID, location: ctx.location });
        } catch (error) {
          console.error("V1 plugin opentoken_health tool error:", error);
          return { output: `Error: ${error.message}` };
        }
      });
    }
  }
  
  // Handle hook registrations (session, tool, etc.)
  if (v1Hooks["session.created"] && typeof v1Hooks["session.created"] === "function") {
    await ctx.hook.register("session.created", async (input, output) => {
      return await v1Hooks["session.created"](input, output);
    });
  }
  
  if (v1Hooks["session.deleted"] && typeof v1Hooks["session.deleted"] === "function") {
    await ctx.hook.register("session.deleted", async (input, output) => {
      return await v1Hooks["session.deleted"](input, output);
    });
  }
  
  if (v1Hooks["session.idle"] && typeof v1Hooks["session.idle"] === "function") {
    await ctx.hook.register("session.idle", async (input, output) => {
      return await v1Hooks["session.idle"](input, output);
    });
  }
  
  if (v1Hooks["tool.execute.before"] && typeof v1Hooks["tool.execute.before"] === "function") {
    await ctx.hook.register("tool.execute.before", async (input, output) => {
      return await v1Hooks["tool.execute.before"](input, output);
    });
  }
  
  if (v1Hooks["tool.execute.after"] && typeof v1Hooks["tool.execute.after"] === "function") {
    await ctx.hook.register("tool.execute.after", async (input, output) => {
      return await v1Hooks["tool.execute.after"](input, output);
    });
  }
  
  // Handle experimental hooks
  if (v1Hooks["experimental.chat.messages.transform"] && typeof v1Hooks["experimental.chat.messages.transform"] === "function") {
    await ctx.hook.register("experimental.chat.messages.transform", async (input, output) => {
      return await v1Hooks["experimental.chat.messages.transform"](input, output);
    });
  }
  
  if (v1Hooks["experimental.session.compacting"] && typeof v1Hooks["experimental.session.compacting"] === "function") {
    await ctx.hook.register("experimental.session.compacting", async (input, output) => {
      return await v1Hooks["experimental.session.compacting"](input, output);
    });
  }
  
  if (v1Hooks["chat.params"] && typeof v1Hooks["chat.params"] === "function") {
    await ctx.hook.register("chat.params", async (input, output) => {
      return await v1Hooks["chat.params"](input, output);
    });
  }
  
  if (v1Hooks["experimental.text.complete"] && typeof v1Hooks["experimental.text.complete"] === "function") {
    await ctx.hook.register("experimental.text.complete", async (input, output) => {
      return await v1Hooks["experimental.text.complete"](input, output);
    });
  }
  
  if (v1Hooks["experimental.chat.system.transform"] && typeof v1Hooks["experimental.chat.system.transform"] === "function") {
    await ctx.hook.register("experimental.chat.system.transform", async (input, output) => {
      return await v1Hooks["experimental.chat.system.transform"](input, output);
    });
  }
  
  // Save hooks for cleanup
  if (ctx.tool && typeof ctx.tool.hook === "function") {
    cleanupPromises.push(ctx.tool.hook("session.created"));
    cleanupPromises.push(ctx.tool.hook("session.deleted"));
    cleanupPromises.push(ctx.tool.hook("session.idle"));
    cleanupPromises.push(ctx.tool.hook("tool.execute.before"));
    cleanupPromises.push(ctx.tool.hook("tool.execute.after"));
  }
}

function getSessionIDFromV1Context(ctx) {
  // Try to extract session ID from V2 context
  if (ctx.context && ctx.context.session && ctx.context.session.id) {
    return ctx.context.session.id;
  }
  // Generate a session ID if none available
  return `v2-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

export default Plugin.define({
  id: "opentoken-adapter",
  description: "V1 OpenToken plugin adapter for OpenCode V2",
  async setup(ctx) {
    // Execute the V1 plugin adapter setup
    const cleanup = await setup(ctx);
    return cleanup;
  },
});
