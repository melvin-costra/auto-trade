# AGENTS.md

Single-file MoonLoader Lua script for SA-MP (Samp-Rp) trade automation. `auto_trade.lua` is the only tracked source; `readme.md` is Russian user documentation.

## Verify changes

- No build, test, lint, or CI setup — and no Lua runtime is available in this repo. Do not try to run the script standalone: it needs GTA:SA + MoonLoader + SAMPFUNCS and only works in-game (`/atrade`, `/itrade`, textdraw UI).
- `lib/` is gitignored vendored MoonLoader/SAMPFUNCS libraries plus `moonloader_reference.txt`, used only for editor stubs. Never commit or edit it.
- The README download link serves `auto_trade.lua` directly, so it must stay self-contained. Only built-in modules are allowed (`samp.events`, `imgui`, `vkeys`, `encoding`); don't add project-local `require`s.
- Shipped code lives on the `release` branch. `main` currently lags behind (old CP1251 version, old page-switching code) — check the branch before diffing or porting.

## Script structure

- MoonLoader calls `main()`; the UI is drawn from global `imgui.OnDrawFrame()`; `/atrade` toggles it, `onWindowMessage` closes it with ESC.
- SAMP event handlers are fields on `ev = require "samp.events"`: `onServerMessage`, `onShowTextDraw`, `onShowDialog`. Returning `false` from `onShowDialog` suppresses default dialog handling — that is required for automated responses.
- Trade flow: `onShowTextDraw` detects the "accept" textdraw and snapshots selected items → `main()` loop runs `autoTrade()` (click item slots, enter amounts) → `sendSubmit()` accepts or resets.

## Encoding

- Source and literals are UTF-8; the game uses CP1251 (`encoding.default`). Decode incoming event text with `u8(text)`. Outgoing `sampSendChat`/`sampAddChatMessage` are wrapped by `wrapToGame`, which converts UTF-8 → CP1251; just pass UTF-8 literals and use `printMessage()` for chat output.
- User docs/chat messages are Russian; GUI labels are English.

## Config and UI coupling

- Runtime config is `moonloader/config/auto-trade.json` (relative to the GTA:SA directory), created on first run and rewritten on every widget change.
- Widget state lives in the local `ui` table, declared once at file scope: `ui.settings.*` mirrors `cfg.settings`, and `ui.items[name]` holds the GUI `label` plus `isSelected`/`amount`/`limit` widget values. The config JSON is loaded at file scope before `ui` is declared, so the widgets are created with the saved values. The "Trade values"/"Limits" sections loop over `cfg.items`, so adding an item needs an entry in `cfg.items` defaults plus a matching `ui.items[name]` entry with a label.
- Config `version` (and the `version` variable in the script) replaces `checkSavedCFG`: on load, the JSON is used only if `fileCFG.version` matches `cfg.version`; otherwise the code defaults are used and saved over the file. Bump `version` when defaults change.
- Timing is milliseconds via `os.clock() * 1000`, throttled by `settings.delay`. Textdraw clicks depend on hardcoded Samp-Rp UI positions/colors: `slots_inventory`, `emptySlotId = 19478`, `darkSlotColor`, and the `accept` textdraw text. Server UI changes require recalibrating these constants.
- Item `limit` is the minimum amount to leave in inventory, not the amount to trade; `amount` is the requested transfer size.

## Style

- 4-space indentation, no tabs (`.vscode/settings.json`). Keep the existing single-file, global-function style; MoonLoader entrypoints and event handlers must remain globals.
