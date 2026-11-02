# AGENTS.md

Single-file MoonLoader Lua script for SA-MP (Samp-Rp) trade automation. `auto_trade.lua` is the only tracked source; `readme.md` is Russian user documentation.

## Verify changes

- No build, test, lint, or CI setup is present, and no Lua runtime is available. Do not run the script standalone: it needs GTA:SA, MoonLoader, SAMPFUNCS, and the in-game Samp-Rp trade UI.
- `lib/` is gitignored vendored MoonLoader/SAMPFUNCS libraries plus `moonloader_reference.txt`, used only for editor stubs. Never commit or edit it.
- The README download link serves the script directly, so `auto_trade.lua` must remain self-contained. Its runtime dependencies are `samp.events`, `mimgui`, `vkeys`, and `encoding`; do not add project-local `require`s.
- Shipped code lives on `main` may lag behind. Check the current branch before diffing or porting.

## Script behavior

- MoonLoader calls global `main()`. `/atrade` toggles the mimgui window, and `onWindowMessage` closes it with ESC.
- The main loop detects the configured cancellation key during an active trade, unless chat or a dialog is open. The UI lets the user select a key; ESC or Enter exits key-picking mode.
- Hold the right mouse button and press Q to request a trade with the targeted player via `/itrade <id>`.
- `ev.onShowTextDraw` records the `accept` and next-page textdraw IDs. On an accept textdraw, when `isActivated` is enabled, it snapshots the selected item IDs, amounts, and limits and enters `trading` state.
- `autoTrade()` searches the fixed inventory slot coordinates and matching textdraw models. It reads quantities from nearby quantity textdraws, clicks matching items, and answers their amount dialogs through `ev.onShowDialog`. If needed, it clicks the next-page control once, waits for the page to render (up to the render timeout), then continues.
- After item handling, the flow enters `submitting`. With `auto_press_accept` enabled, it clicks the accept textdraw; matching trade dialogs are also answered automatically. Otherwise it resets. `onServerMessage` resets on the handled trade errors, sends `/accept invtrade` for detected invitations when enabled, and starts submitting after detecting the other party's acceptance when auto-accept is enabled.
- Returning `false` from `ev.onShowDialog` suppresses normal dialog handling for scripted quantity responses and matching submission dialogs.

## Encoding

- `encoding.default` is CP1251 and `u8` is used to convert incoming event text before matching it. `wrapToGame` converts string arguments to `sampAddChatMessage` and `sampSendChat` from UTF-8 to the game encoding. Use `printMessage()` for script chat output and pass it UTF-8 text.
- GUI labels and several Russian literals are currently stored as mojibake-looking text in the source; inspect actual displayed behavior before changing those strings or describing their wording.

## Config and UI coupling

- Runtime config is `moonloader/config/auto-trade.json` under the GTA:SA directory. It is created at startup if absent and saved on widget changes.
- `cfg` defaults are declared before `ui`; `loadCFG()` loads a saved file only when `fileCFG.version` matches `cfg.version`, then creates `ui.items[name]` widgets for each configured item. When adding an item, update both `cfg.items` and corresponding UI assumptions. Bump `version` when defaults or config shape changes so old config is replaced with defaults.
- UI settings map to `cfg.settings`: `isActivated`, `accept_trade_request`, `auto_press_accept`, `delay`, and `cancel_key`. Delay is clamped to 200–2000 ms. Item `amount` is transfer size; `limit` is the minimum inventory amount to retain. If the requested transfer would cross the limit, the actual transfer is reduced; items already at/below the limit are skipped.
- Timing uses `os.clock() * 1000`; `settings.delay` throttles textdraw clicks. Inventory detection depends on hardcoded `slots_inventory`, `emptySlotId = 19478`, `darkSlotColor`, quantity offsets, accept/next-page text and coordinates, and page-render timeout. Samp-Rp UI changes may require recalibrating these values.
- The script scans textdraws up to `MAX_TEXTDRAWS`, and allows at most one next-page switch per trade. Reset paths clear pending trade, page, and state data.

## Style

- 4-space indentation, no tabs (`.vscode/settings.json`). Keep the existing single-file, global-function style; MoonLoader entrypoints and event handlers must remain globals.
