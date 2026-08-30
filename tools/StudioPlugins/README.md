# MathArena Studio Plugins

Studio plugins for this project, kept in the repo so every developer runs
the same version.

## Why these can't be synced through Rojo

Everything under `src/` is game code: it lives inside the place, and Rojo
syncs it in. A Studio **plugin** is different — it runs inside Studio
itself, in Edit mode, *before and outside* any running game. Roblox loads
plugins from a fixed per-user folder on disk, so a plugin can never arrive
through Rojo or through publishing. Each developer needs a copy on their
own machine.

That's what the install scripts here are for.

## Install (each developer, once after cloning)

**Windows**

```powershell
powershell -ExecutionPolicy Bypass -File tools\StudioPlugins\install.ps1
```

**macOS**

```bash
./tools/StudioPlugins/install.sh
```

Both copy every `.lua` file in this folder into the local Studio Plugins
folder (`%LOCALAPPDATA%\Roblox\Plugins` on Windows,
`~/Documents/Roblox/Plugins` on macOS), creating it if needed. Re-run the
same command whenever a plugin changes — it overwrites in place. Restart
Studio if it doesn't hot-load.

Neither script touches the repo or the game. Add `-WhatIf` (Windows) or
`--dry-run` (macOS) to preview.

## Alternative: publish once, auto-update for everyone

Copying files works, but every developer has to re-run the script after each
plugin change. If that becomes a nuisance, publish the plugin to Roblox as a
**private** plugin instead:

1. In Studio, put the plugin's code in a `Script` under `ServerStorage`.
2. Right-click it → **Publish as Plugin**.
3. Set it to private, then share access with the team.

Each developer installs it once from the Creator Store and receives updates
automatically. The tradeoff: the published copy becomes the real source, so
this folder would need to stay in sync with it deliberately — worth it for a
larger team, overkill for one or two people.

## What's here

### `MathArenaAutoBuild.lua`

Rebuilds the open Place's world in **Edit mode** whenever the builder code
or the built geometry has changed, so a Place never shows an empty baseplate
or stale models.

It exists because Roblox never runs ordinary `Script`s in Edit mode — only
in Play mode and on live servers — so `Main.server.lua`'s build calls never
execute there. This plugin makes the same calls, through the same functions,
so there is no second copy of build logic to drift.

**How it detects change:** it fingerprints the `.Source` of every script
under `ServerScriptService.LobbyBuilder`, `ServerScriptService.ArenaBuilder`
and `ReplicatedStorage.Modules`, plus a signature of the built geometry
(part names, rounded positions and sizes, counts). A difference in either —
a code edit, or a part someone moved by hand — marks that folder stale and
rebuilds it. Reading `.Source` needs no `require()`, which is what makes the
check immune to Studio's module cache.

**Toolbar:** `Rebuild Now` forces a full regenerate. `Auto-Build` toggles
automatic rebuilding for the current place (persisted per place).

**Two behaviors worth knowing:**

- *Hand edits are discarded on rebuild.* Geometry is code-owned in this
  project, so a hand-moved part counts as drift to correct. Every rebuild is
  a single `ChangeHistoryService` recording, so `Ctrl+Z` restores it, and
  `Auto-Build` can be switched off while experimenting by hand.
- *Code changed mid-session rebuilds on the next open, not immediately.*
  Studio caches `require()` per session keyed by instance, and Rojo patches
  `.Source` on those same instances — so after a sync, the modules already
  required are still the old ones. Rather than rebuild from stale code, the
  plugin clears the stored fingerprints and tells you to reopen the place,
  which gives it a fresh VM and a genuinely current `require`.

Live servers can't read `.Source`, so they rely on
`ReplicatedStorage/Modules/BuildVersion.lua` instead — bump
`BuildVersion.CURRENT` when builder output changes and every Place
regenerates on its next server start.
