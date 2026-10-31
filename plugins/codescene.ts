import { Plugin } from "@opencode/plugin";
import { execSync } from "node:child_process";

interface CodeSceneFinding {
  category: string;
  "change-type": string;
  "new-pp": number;
  threshold?: number;
  "change-details": Array<{
    description: string;
    value?: number;
    locations?: Array<{
      function: string;
      "start-line": number;
      "end-line": number;
    }>;
  }>;
}

interface CodeSceneFileReport {
  name: string;
  findings: CodeSceneFinding[];
  "new-score": number;
}

export default Plugin.define({
  id: "codescene-delta-plugin",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", async (event) => {
      const toolName = String(event.tool ?? "").toLowerCase();

      // Trigger check on execution boundaries (like running shell or build commands)
      if (toolName === "bash" || toolName === "shell") {
        try {
          console.log("\n--- [CodeScene Delta Analysis vs 'main'] ---");

          // Run the correct CodeScene CLI command
          const stdout = execSync("cs delta main --output-format json", {
            encoding: "utf-8",
            cwd: process.cwd(),
          });

          const reports: CodeSceneFileReport[] = JSON.parse(stdout);
          let hasRegressions = false;

          for (const file of reports) {
            console.log(`\n📁 File: ${file.name} (Code Health: ${file["new-score"]})`);

            for (const finding of file.findings) {
              console.log(`  ⚠️ [${finding.category}] (+${finding["new-pp"]} penalty points)`);

              for (const detail of finding["change-details"]) {
                console.log(`     - ${detail.description}`);
                if (detail.locations) {
                  for (const loc of detail.locations) {
                    console.log(`       📍 Function '${loc.function}' (Lines ${loc["start-line"]}-${loc["end-line"]})`);
                  }
                }
              }
            }

            // Flag files whose health dropped below acceptable thresholds
            if (file["new-score"] < 8.0) {
              hasRegressions = true;
            }
          }

          console.log("\n-------------------------------------------");

          if (hasRegressions) {
            console.warn("⚠️ CodeScene Guardrail: Code health regressions detected relative to main.");
            // Optional: throw new Error("Blocked by CodeScene: Introduced code smells exceed limits.");
          }

        } catch (error: any) {
          console.error("[CodeScene Plugin] Execution failed:", error.message);
        }
      }
    });
  },
});
