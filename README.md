# MathArena

MathArena is a Roblox game project built around competitive and engaging mathematics gameplay.

This repository contains the source-controlled development project for MathArena.

---

## Play Mode Architecture (Multi-Place Difficulty Routing)

Play Mode's five difficulties each run on their own isolated Roblox Place/server, containing only that difficulty's map. This is a "true multi-Place" architecture (as opposed to a single-Place reserved-server approach) - a deliberate choice, made explicitly aware of its cost, over a lighter-weight alternative. See git history / prior session notes for the tradeoff discussion.

**The Places:**

| Difficulty (GameplayConfig.QUEUE_TIERS id) | Map | Rojo project file |
| --- | --- | --- |
| 1 - Easy Mode | Futuristic | `place.futuristic.project.json` |
| 2 - Medium Mode | Under the Sea | `place.underwater.project.json` |
| 3 - Hard Mode | Ice Age (Tundra) | `place.tundra.project.json` |
| 4 - Expert Mode | Lava (Volcano) | `place.volcano.project.json` |
| 5 - Master Mode | Space | `place.space.project.json` |

Plus the **Hub** - this repo's original `default.project.json` - the single shared, multi-map exploration lobby every player starts in. The Hub is NOT one of the five difficulty destinations.

**How it works:**

- Every one of the six project files (Hub + 5 difficulty Places) points at the exact same `src/` tree via Rojo `$path` - there is only ONE copy of every script anywhere in this repo. Nothing is duplicated. Only the declared `Workspace` map folders differ per project file, and even those are just empty Rojo-owned containers - all map geometry is built procedurally at server start by `LobbyBuilder`/`ArenaBuilder`, identically everywhere.
- `src/ReplicatedStorage/Modules/DifficultyPlacesConfig.lua` is the routing table: difficulty tier id -> real Roblox `placeId`. **The `placeId` values start as placeholder `0`s** and must be filled in once the five destination Places actually exist (see "Setup still required" below) - see that file's doc comment for exactly how it fails closed until then.
- `src/ServerScriptService/Main.server.lua` looks up `game.PlaceId` in `DifficultyPlacesConfig` at server start: on a difficulty Place it builds ONLY that Place's one assigned map (`LobbyBuilder.Build(mapDef)`); on the Hub (or an unconfigured Place) it builds every map as before (`LobbyBuilder.BuildAllMaps()`).
- `src/ServerScriptService/PlaceTeleportSystem/init.lua` is the server-authoritative router. Play Mode's tier-select popup fires `RequestPlayDifficulty(tierId)` (never a raw destination) - the server validates/clamps the tier id, and either joins the local queue (already on the right Place) or teleports the player via `TeleportService:TeleportAsync` to the correct Place, passing the tier id as TeleportData so the destination auto-joins that queue on arrival. A failed teleport fires `PlayTeleportFailed` back to the client - the player stays put, free to retry, never soft-locked.
- **Practice Mode never touches any of this.** `PracticeSystem.lua` calls `MatchSystem.TryJoinQueue`/`LeaveQueue` directly as plain function calls and never fires `RequestPlayDifficulty` - practice difficulty changes always stay on the player's current server/map, on every Place, by construction (there is no shared code path to accidentally invoke the teleport system from).

**Setup still required (manual, cannot be done from this pipeline):**

1. In Roblox Studio, create five new empty Places inside the MathArena experience (Game Settings > Places, or the Game Explorer's Places list) - one per row in the table above. Suggested names match the `displayName` values already in `DifficultyPlacesConfig.lua`.
2. Open each new Place in Studio (or check its entry in Game Settings > Places) and note its real Place id.
3. Fill in the matching `placeId` field in `DifficultyPlacesConfig.lua` (replacing the placeholder `0`), then republish/re-sync so every server picks it up.
4. Connect Rojo to each of the five new Places using its matching `place.<name>.project.json` (in addition to the Hub, which keeps using `default.project.json`), and publish each once so a real server exists for `TeleportService` to send players to.
5. Repeat step 4's publish whenever a shared system (anything under `src/ServerScriptService` or `src/ReplicatedStorage`) changes - all six Places must be republished to stay in sync, since Roblox does not share code between Places automatically.

Until steps 1-4 are done, `PlayTeleportFailed` fires for every difficulty (fails closed, never errors or teleports to an invalid Place) and the game behaves exactly as it did before this system existed.

---

## 1. Project Source of Truth

The local MathArena repository is the **source of truth for project code and configuration**.

Project root:

```text
MathArena/
├── .git/
├── README.md
├── default.project.json
└── src/
```

Do not create duplicate MathArena project folders.

Do not use a second local clone as the active development project.

The intended development flow is:

```text
Local MathArena files
        ↓
       Rojo
        ↓
Roblox Studio
```

Git provides version control and GitHub provides remote backup.

---

## 2. Development Architecture

The primary development pipeline is:

```text
                    Claude
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
   Local Filesystem          Roblox Studio MCP
          │                       │
          ▼                       ▼
      MathArena              Roblox Studio
          │
          ▼
         Rojo
          │
          ▼
    Roblox Studio
          │
          ▼
       Testing
```

Git/GitHub provides version control:

```text
MathArena
    │
    ▼
   Git
    │
    ▼
 GitHub
```

### Source-of-truth rule

For code, the local MathArena repository should normally be edited first.

Code should not be created directly in Roblox Studio when the corresponding source-controlled file should exist in the repository.

Roblox Studio MCP should be used when Studio interaction is actually required, including inspecting the live game, manipulating appropriate instances, testing, debugging, and working with game objects that are intentionally Studio-managed.

---

# 3. Project Structure

The intended project structure is:

```text
MathArena/
│
├── .git/
│
├── README.md
│
├── default.project.json
│
└── src/
    │
    ├── ServerScriptService/
    │   └── Systems/
    │
    ├── ReplicatedStorage/
    │   ├── Shared/
    │   └── Remotes/
    │
    ├── StarterGui/
    │
    ├── StarterPlayer/
    │   └── StarterPlayerScripts/
    │
    └── Workspace/
```

The exact contents of these directories may evolve as the game is developed.

Do not create folders simply to match this document if they are not currently needed.

The architecture should evolve deliberately rather than through unnecessary duplication.

### `tools/` — developer tooling, not game code

`tools/` sits outside `src/` and is deliberately never synced by Rojo into
any Place. It holds things that run on a developer's machine rather than
inside the game.

`tools/StudioPlugins/` contains this project's Roblox Studio plugins plus
per-platform install scripts. A Studio plugin runs inside Studio in Edit
mode, so Roblox loads it from a fixed per-user folder on disk — it can never
arrive through Rojo or through publishing, which is why each developer runs
the install script once after cloning (and again whenever a plugin changes).

See `tools/StudioPlugins/README.md` for install commands and for what
`MathArenaAutoBuild.lua` does — in short, it keeps a Place's world in Edit
mode matching what the builder code currently produces, since ordinary
`Script`s never run in Edit mode and so `Main.server.lua` never builds
there.

### Build staleness: `ReplicatedStorage/Modules/BuildVersion.lua`

`LobbyBuilder`/`ArenaBuilder` skip rebuilding anything already marked
`MathArenaBuilt`, and that attribute is saved into each published place
file — so without a staleness signal, a Place's world stays frozen at
whatever the code produced the day it was first built, no matter how many
times the code is edited and republished.

`BuildVersion.CURRENT` is that signal for **live servers and Play tests**:
both builders stamp it alongside `MathArenaBuilt` and regenerate
automatically when the stored value is older. **Increment it whenever you
change what the builders produce** (any builder module, or the
theme/map/config values feeding them). Bumping it unnecessarily is harmless —
it just costs one regeneration per Place.

In **Edit mode** the `MathArenaAutoBuild` plugin detects change directly, by
fingerprinting script sources and built geometry, so no bump is needed there.

---

# 4. Rojo

Rojo synchronizes the local MathArena project into Roblox Studio.

The project configuration is defined by:

```text
default.project.json
```

The source files are located under:

```text
src/
```

The normal workflow is:

```text
Edit local file
      ↓
Save
      ↓
Rojo
      ↓
Roblox Studio
```

### Rojo rules

* Preserve `default.project.json` unless a legitimate architecture change requires modifying it.
* Do not create duplicate Rojo project configurations without a clear reason.
* Do not manually recreate source-controlled scripts in Studio when they should exist in `src`.
* If a Studio-only object is intentionally created through Roblox Studio MCP, determine whether it should also have a source-controlled representation.
* After significant Rojo changes, verify that the expected instances appear correctly in Studio.

---

# 5. Roblox Studio MCP

Roblox Studio MCP provides Claude with the ability to inspect and interact with Roblox Studio.

Claude may use Roblox Studio MCP to:

* Inspect the game hierarchy.
* Inspect existing instances.
* Inspect relevant scripts or properties.
* Create appropriate Roblox instances.
* Modify appropriate Roblox instances.
* Test game behavior.
* Inspect runtime state.
* Diagnose errors.
* Fix problems.
* Verify that implemented features work.

### Studio source-of-truth rule

For source-controlled code:

```text
Local file → Rojo → Studio
```

should generally be preferred over:

```text
Claude → Studio → code exists only in Studio
```

Claude must not claim that a local source file exists merely because an equivalent Studio instance exists.

When a requested change involves a local source file, verify the actual file exists in the MathArena repository.

---

# 6. Claude Development Permissions

Claude is intended to be the primary development agent for MathArena.

Claude has broad permission to work on the MathArena project.

### Claude may perform without additional approval

* Read project files.
* Inspect project structure.
* Create files.
* Create folders.
* Edit code.
* Refactor code.
* Modify project configuration when necessary.
* Create and modify Roblox game systems.
* Create and modify appropriate Roblox instances.
* Inspect Roblox Studio.
* Test the game.
* Diagnose errors.
* Fix errors.
* Run Git status.
* Run Git diff.
* Inspect repository history when useful.
* Work with Rojo.
* Update documentation.
* Update README.md when architecture or development procedures materially change.

Claude should make reasonable changes autonomously when they are clearly required by the user's request.

---

# 7. Actions Requiring User Approval

Claude should ask for confirmation before performing important or potentially destructive actions.

## Important file deletion

Before deleting an important file or system, Claude should explain:

1. What will be deleted.
2. Why it is necessary.
3. What functionality could be affected.
4. What alternative exists, if applicable.

Then wait for approval.

Minor temporary files may be removed when their purpose is clear and removal is directly required by the task.

---

## Destructive Roblox Studio changes

Claude should ask before performing major destructive changes such as:

* Deleting major game systems.
* Deleting significant areas of the map.
* Replacing large portions of existing functionality.
* Removing important data/configuration.
* Making irreversible changes whose consequences are unclear.

Normal creation and modification of requested game features does not require approval for every individual object.

---

## Git commits

Claude may inspect Git status and Git diff without approval.

Before creating a commit, Claude should summarize:

```text
Files changed:
What changed:
Why:
Potential concerns:
```

Then ask for approval to commit.

---

## GitHub pushes

Claude must ask for approval before pushing changes to GitHub.

The normal sequence is:

```text
Make changes
    ↓
Review
    ↓
git status
    ↓
git diff
    ↓
User approval
    ↓
git commit
    ↓
User approval
    ↓
git push
```

---

# 8. Git Safety Rules

Git is used to maintain recoverable versions of the project.

Claude may inspect:

```text
git status
git diff
git log
```

when useful.

Claude must not automatically perform destructive Git operations.

## Never perform these without explicit user instruction

```text
git push --force
git reset --hard
git clean -fd
history rewriting
force-pushing rewritten history
```

If a destructive Git operation appears necessary, explain the situation and request explicit approval.

Do not hide, discard, or overwrite user work.

---

# 9. GitHub

GitHub is the remote backup repository for MathArena.

The local repository is connected to GitHub through Git.

The GitHub repository should reflect stable, intentionally committed versions of MathArena.

GitHub is not a replacement for the local project.

The local repository remains the primary working environment.

### Backup principle

```text
Local project
     ↓
Git commit
     ↓
GitHub push
     ↓
Remote backup
```

Regularly push stable checkpoints to GitHub.

---

# 10. Coding Workflow

When given a development request, Claude should generally follow this process:

### Step 1 — Inspect

Inspect:

* Existing project structure.
* Relevant scripts.
* Existing systems.
* Configuration.
* Related modules.
* Roblox Studio state when relevant.

Do not assume that a requested file or system does not exist without checking.

### Step 2 — Plan

For small changes, proceed directly.

For substantial changes, briefly explain:

* What will change.
* Which files will be affected.
* Which systems interact with the change.
* Any important risks or dependencies.

### Step 3 — Implement

Create or modify the smallest appropriate set of files.

Follow the existing architecture and conventions.

Avoid unnecessary rewrites.

### Step 4 — Verify

Check:

* Files exist.
* Syntax is valid.
* References are correct.
* Rojo synchronization works when relevant.
* Roblox Studio receives the expected changes.
* Runtime behavior is correct when testing is possible.

### Step 5 — Fix

If errors appear, diagnose them and make reasonable fixes.

Do not stop at the first error if the issue can be safely resolved.

### Step 6 — Report

Clearly summarize:

```text
What changed
Files created
Files modified
Studio changes
Tests performed
Known issues
Next steps
```

Never claim success without verification.

---

# 11. Coding Principles

MathArena should prioritize:

* Readability.
* Maintainability.
* Modular architecture.
* Clear responsibilities.
* Reusable systems.
* Server-authoritative gameplay where appropriate.
* Secure server/client communication.
* Performance.
* Error handling.
* Testability.
* Consistent naming.
* Minimal unnecessary complexity.

Avoid:

* Giant monolithic scripts.
* Duplicate systems.
* Copy-pasted functionality when a reusable module is appropriate.
* Hardcoded values that belong in configuration.
* Unnecessary global state.
* Unexplained architectural changes.
* Temporary debugging code left in production systems.

---

# 12. Server and Client Responsibilities

Server code should control authoritative game state and important gameplay decisions.

Client code should primarily handle:

* Input.
* Presentation.
* UI.
* Effects.
* Local responsiveness.

Do not trust the client for important game-state decisions.

RemoteEvents and RemoteFunctions should be designed with server-side validation.

When creating a new remote, consider:

* Who sends it?
* Who receives it?
* What data is sent?
* What validation is required?
* Could a malicious client abuse it?

---

# 13. Configuration

Shared configuration should be centralized when practical.

Avoid scattering important gameplay constants throughout many scripts.

When adding configurable values, prefer an appropriate shared configuration module rather than duplicating constants.

---

# 14. Testing

Testing is part of development, not an optional final step.

For gameplay changes, Claude should test the relevant behavior whenever practical.

Useful checks include:

* Studio output.
* Runtime errors.
* Server behavior.
* Client behavior.
* Remote communication.
* UI behavior.
* Player interactions.
* Match flow.
* Edge cases.

When a test cannot be performed, Claude should say so rather than claiming that it passed.

---

# 15. Temporary Test Files

Temporary files such as:

```text
TestPipeline.server.lua
```

may be created when necessary for testing.

After testing, remove temporary files if they are no longer needed.

Do not leave experimental scripts in production without a reason.

---

# 16. Documentation

README.md should be updated when major development procedures or architecture change.

Documentation should explain important decisions rather than documenting every trivial code change.

When introducing a major system, consider documenting:

* Purpose.
* Location.
* Responsibilities.
* Dependencies.
* Important assumptions.
* How it interacts with other systems.

---

# 17. Change Management

Prefer incremental development.

Do not rewrite large portions of the project when a smaller change is sufficient.

When a change affects multiple systems, identify those dependencies before modifying them.

Preserve working functionality unless the user's request specifically requires changing it.

If an existing system appears incorrect, explain the issue before making a major replacement.

---

# 18. Handling Ambiguity

If a request is clear and the implementation is straightforward, proceed.

If multiple reasonable implementations exist but the choice is low-risk, choose the implementation that best fits the existing architecture.

If a decision could substantially affect:

* Game architecture.
* Player progression.
* Saved data.
* Economy.
* Security.
* Major UI.
* Existing gameplay.
* Git history.
* Large amounts of existing work.

explain the options and ask before making the irreversible choice.

---

# 19. Never Misrepresent Work

Claude must accurately distinguish between:

```text
Created local file
```

and:

```text
Created Roblox Studio instance
```

These are not automatically the same thing.

Claude must verify changes using the appropriate tool before claiming they exist.

If a tool is unavailable, say so.

If a requested action cannot be performed because of permissions or missing tools, explain the limitation rather than pretending it succeeded.

---

# 20. Project Safety

The goal is to give Claude broad development autonomy while keeping the project recoverable.

The preferred philosophy is:

```text
High autonomy
+
Clear architecture
+
Incremental changes
+
Git checkpoints
+
User approval for risky operations
=
Safe autonomous development
```

Claude should be proactive about building and fixing MathArena while remaining transparent about consequential actions.

---

# 21. Current Development Environment

The intended environment consists of:

```text
VS Code
    ↓
MathArena local repository
    ↓
Git
    ↓
GitHub
```

and:

```text
MathArena local repository
    ↓
Rojo
    ↓
Roblox Studio
```

Claude has access to the MathArena project through the configured filesystem tools and can interact with Roblox Studio through the configured Roblox Studio MCP.

The Git installation itself is an external development dependency and is not part of the MathArena source tree.

---

# 22. Primary Rule

When working on MathArena:

> **Inspect first. Build deliberately. Keep source-controlled code in the local project. Use Rojo to synchronize code into Studio. Use Roblox Studio MCP when Studio interaction is necessary. Verify changes. Protect existing work. Keep GitHub as a recoverable backup. Ask before consequential or destructive actions.**
