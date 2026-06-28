/**
 * SwarmForge pi backend extension.
 *
 * Loaded by every pi role via `pi --extension <script-dir>/extensions/swarmforge-pi.ts`.
 * Owns the SwarmForge-specific behaviors pi has no native JSON config for:
 *
 *   1. agent-running marker — touches <cwd>/.swarmforge/agent-running on a user
 *      turn and removes it when the agent goes idle/stops. Restores the Claude
 *      hooks.UserPromptSubmit / hooks.Stop behavior (ADR 0020) for watchdogs.
 *   2. Percentage auto-compaction — triggers compaction when context usage
 *      exceeds a percentage of the window (default 88% of 200000), mirroring
 *      Claude's CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=88 / AUTO_COMPACT_WINDOW=200000.
 *      pi's native compaction uses a fixed token reserve, not a percentage, so
 *      this extension tightens the trigger to the SwarmForge threshold.
 *
 * Config (precedence: env > .pi/settings.json > defaults):
 *   SWARMFORGE_AUTOCOMPACT_PCT     (default 0.88)
 *   SWARMFORGE_AUTOCOMPACT_WINDOW  (default 200000)
 *   .pi/settings.json -> { "swarmforge": { "autoCompactPct": 0.88, "autoCompactWindow": 200000 } }
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const DEFAULT_PCT = 0.88;
const DEFAULT_WINDOW = 200_000;

function readSwarmforgeConfig(cwd: string): { pct: number; window: number } {
	let pct = DEFAULT_PCT;
	let window = DEFAULT_WINDOW;

	const settingsPath = path.join(cwd, ".pi", "settings.json");
	try {
		if (fs.existsSync(settingsPath)) {
			const raw = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
			const sf = raw?.swarmforge;
			if (typeof sf?.autoCompactPct === "number") pct = sf.autoCompactPct;
			if (typeof sf?.autoCompactWindow === "number") window = sf.autoCompactWindow;
		}
	} catch {
		// Malformed settings — fall through to env/defaults.
	}

	const envPct = process.env.SWARMFORGE_AUTOCOMPACT_PCT;
	const envWindow = process.env.SWARMFORGE_AUTOCOMPACT_WINDOW;
	if (envPct) {
		const n = Number(envPct);
		if (!Number.isNaN(n)) pct = n;
	}
	if (envWindow) {
		const n = Number(envWindow);
		if (!Number.isNaN(n)) window = n;
	}

	return { pct, window };
}

function markerPath(cwd: string): string {
	return path.join(cwd, ".swarmforge", "agent-running");
}

function touchMarker(cwd: string): void {
	try {
		fs.mkdirSync(path.dirname(markerPath(cwd)), { recursive: true });
		fs.writeFileSync(markerPath(cwd), String(Date.now()));
	} catch {
		// Best-effort; the marker is for external observability only.
	}
}

function clearMarker(cwd: string): void {
	try {
		fs.rmSync(markerPath(cwd), { force: true });
	} catch {
		// Best-effort.
	}
}

export default function (pi: ExtensionAPI) {
	let previousTokens: number | null | undefined;

	const triggerCompaction = (ctx: ExtensionContext) => {
		ctx.compact({
			onComplete: () => {
				if (ctx.hasUI) ctx.ui.notify("SwarmForge auto-compaction completed", "info");
			},
			onError: (error) => {
				if (ctx.hasUI) ctx.ui.notify(`SwarmForge auto-compaction failed: ${error.message}`, "error");
			},
		});
	};

	// agent-running marker: a user message starts a turn, agent_end/session_shutdown end it.
	pi.on("message_start", (event, ctx) => {
		const role = (event.message as { role?: string }).role;
		if (role === "user") touchMarker(ctx.cwd);
	});

	pi.on("agent_end", (_event, ctx) => {
		clearMarker(ctx.cwd);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		clearMarker(ctx.cwd);
	});

	// Percentage auto-compaction: check after each turn, compact if over threshold.
	pi.on("turn_end", (_event, ctx) => {
		const { pct, window: configuredWindow } = readSwarmforgeConfig(ctx.cwd);
		const usage = ctx.getContextUsage();
		const currentTokens = usage?.tokens ?? null;
		if (currentTokens === null) return;

		const contextWindow = usage?.contextWindow ?? configuredWindow;
		const threshold = Math.floor(contextWindow * pct);

		const crossedThreshold =
			previousTokens !== undefined && previousTokens !== null && previousTokens <= threshold;
		previousTokens = currentTokens;
		if (!crossedThreshold || currentTokens <= threshold) return;

		if (ctx.hasUI) ctx.ui.notify("SwarmForge auto-compaction started", "info");
		triggerCompaction(ctx);
	});
}
