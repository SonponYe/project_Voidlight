# VOIDLIGHT

> *You can only see as far as your light allows. But they can hear everything.*

A 2D top-down arena game built in Godot 4.x. Two modes are built and playable today — **Solo** survival (clear a dark, monster-filled arena and reach the exit) and **Versus** (two players, one device, split-screen PvP) — and the active design direction is a **web-based multiplayer arena shooter**: bright, colorful, up to 5 players per match (or 2–3v2–3 teams), each picking one of several unique superpowers, playable in a browser on desktop or mobile. See [Next: Web Multiplayer Arena](#next-web-multiplayer-arena-active-design) for where this is headed.

Developer: **Sonpon Ye-shua Chief** | Engine: **Godot 4.7.x** | Language: **GDScript**
Target Platform: **Web (HTML5)** first — playable in-browser on desktop and mobile — plus Itch.io (Windows secondary)

---

## Table of Contents

- [Concept](#concept)
- [Game Modes](#game-modes)
- [Next: Web Multiplayer Arena (Active Design)](#next-web-multiplayer-arena-active-design)
- [Controls](#controls)
- [Mechanics](#mechanics)
- [Powerups](#powerups)
- [Enemy Types (Solo mode)](#enemy-types-solo-mode)
- [Level Overview](#level-overview)
- [Scene Architecture](#scene-architecture)
- [Systems Checklist](#systems-checklist)
- [Asset Credits](#asset-credits)
- [Status & Roadmap](#status--roadmap)
- [How to Run](#how-to-run)

---

## Concept

VOIDLIGHT started as a solo horror-survival game: you're dropped into a dark arena with nothing but a flashlight and a gun. You can only see what your light touches — everything outside the cone is invisible — but monsters can hear you, especially if you sprint. Turning the light off makes you nearly undetectable, but also blind: no minimap, no maze layout, just your own faint ambient glow to feel your way around.

That same light-vs-detection tension turned out to work just as well **player vs player** — so VOIDLIGHT now also has a local split-screen **Versus** mode: two people on one device, same arena, hunting each other with the same flashlight/stealth mechanics, each with one unique power that can swing a fight.

---

## Game Modes

### Solo
Enter an open arena full of scattered crate cover and AI-controlled monsters. Kill or evade them, use pickups and fireplaces along the way, and reach the exit. The exit is open from the start — the goal is getting out alive, not clearing every monster (though clearing them stops them chasing you).

### Versus (2 Player, Local)
Two players, one device, **no shared camera** — the screen splits top/bottom and each player only ever sees their own surroundings, exactly like they would playing alone. Same arena-with-cover philosophy as Solo, but larger, fully sealed (no entrance/exit — there's nothing to escape, just a fight), and PvP: your bullets hurt the other player, theirs hurt you. Each player gets one unique power on a cooldown (see [Powerups](#powerups)). Last player with HP left wins.

Reachable from the main menu's **Versus (2 Player, Local)** button.

---

## Next: Web Multiplayer Arena (Active Design)

This is the direction the game is actively moving in. It's a significant pivot from everything above, captured here while the details get nailed down — Solo and local Versus stay built and playable regardless of how this develops.

### The core reversal: light stops being the default
The original premise — the whole arena is dark, your flashlight is your only vision — is being **scrapped as the default state**. Matches are now **bright and colorful by default**: you can see the arena, the cover blocks, and other players clearly, all the time. Darkness becomes something that happens *to* a match temporarily, not the baseline.

### Platform: web first, mobile-friendly
- Primary export target becomes **HTML5**, played in a browser — desktop and mobile both.
- Touch controls needed for mobile web play:
  - ✅ Virtual joystick for movement — already built (`virtual_joystick.gd`)
  - ❌ Drag-to-aim (moving your finger to turn/aim your character) — not built yet
  - ❌ On-screen shoot button — not built yet

### Scale & match structure
- **Free-for-all:** up to 5 players per match
- **Team mode:** 2–3 players per team
- Designed to flex beyond those numbers later ("could still take any amount of players")
- A large arena to actually support that many bodies and sightlines at once — bigger than either existing arena
- Players with network trouble should **stay in the match, visually dimmed**, rather than being dropped — the match keeps going around them

### Networking approach
Godot's native multiplayer (ENet, raw UDP) **does not work in a browser** — that's a hard constraint, not a preference. For a web build, the real choice is:

| Approach | How it works | Tradeoff |
|---|---|---|
| **WebSocket, client-server** *(recommended)* | One authoritative server; every browser connects to it over a normal WebSocket, using Godot's existing `SceneMultiplayer` + `WebSocketMultiplayerPeer` | Simple, well-supported, naturally gives you one place to implement "dim out a laggy player," anti-cheat, and room/team logic. Needs a server running somewhere continuously — a real hosting decision with an ongoing cost, not something that gets provisioned automatically. |
| **WebRTC, peer-to-peer** | Players connect more directly via `WebRTCMultiplayerPeer` | Lower latency, but needs a signaling server *and* a TURN relay for players behind strict NATs — more infrastructure, not less, and harder to debug. |

**Recommendation: WebSocket client-server**, built server-authoritative (the server decides actual positions/hits, clients predict locally and get corrected) — the standard pattern for exactly this kind of game, and what makes "smooth with no lag" and "handle a lot of concurrent players" realistic goals rather than hopes.

### The Blackout power (where "the whole room is dark" goes)
Instead of being the default, darkness becomes **one player's temporary power**: for about 15 seconds, the entire arena goes dark for everyone *except* the player who triggered it — only they get a flashlight for that window. Everyone else is suddenly blind in a normally-lit match. This directly reuses the existing `CanvasModulate`/`PointLight2D`/flashlight-cone systems already built for Solo mode — they just flip from "always on" to "one player's temporary ability."

### Superpowers (working names — final terminology still TBD)
Each player picks one superpower before a match starts; it charges up on a cooldown during play, same pattern the existing power-button/powerup-effect system already uses.

| Working name | Effect | Open questions |
|---|---|---|
| **Camouflage** | Disguises as a maze/crate block — other players can't tell it's a player | Can it still move while disguised? Does it take damage if shot while camouflaged? |
| **Bulwark (Shield)** | Projects a shield in front of the player, blocking incoming damage from that direction | Front-facing only, or a brief full-body shield like the existing Invincibility power? |
| **Decoy** | Spawns an AI-controlled clone of the player that actively hunts a chosen target; can be destroyed | Reuses the existing enemy-chase AI pattern (`enemy.gd`'s HUNT state) adapted to target a player instead of always the nearest one |
| **Heavy Gunner (Firepower)** | More damage and/or faster fire rate for a duration | — |
| **Blackout** | Darkens the whole arena except the user, who alone gets a flashlight, for ~15s | Map-wide effect — only one of these should probably be active at a time |
| **6th power — TBD** | — | Waiting on more detail/terminology |

### Open decisions before deeper implementation
These are the things worth pinning down before sinking real time into the networking layer, since getting them wrong costs real rework:
1. **Where does the server run?** (hosting choice + ongoing cost — this doesn't get built around, it gets decided)
2. **The 6th power**, and final names/terminology for all of them
3. **Team-assignment UI** — how players end up on a team vs. FFA before a match starts
4. **Custom art** — once sprite files are provided for how players should look, they slot into the existing placeholder-swap pattern (every visual in this project so far is a flat shape or procedural texture specifically so it can be swapped for real art later — same approach applies here)
5. Whether Solo/local Versus stay as permanent separate offline modes, or eventually fold into the same arena content

---

## Controls

Every action maps to a named input action in `project.godot`, so adding another input scheme later means configuring that action, not touching gameplay code.

**Player 1 (keyboard + mouse):**

| Action | Key |
|---|---|
| Move | `W A S D` or Arrow keys |
| Aim | Mouse position |
| Shoot | `Left Click` |
| Sprint (faster, louder) | `Shift` (hold) |
| Toggle flashlight on/off | `F` or `Right Click` |
| Use unique power | `Q` |
| Pause | `Escape` |
| Debug overlay *(dev only)* | `F1` |

**Player 2 (keyboard, for local Versus matches on one keyboard):**

| Action | Key |
|---|---|
| Move | `I J K L` |
| Shoot | `U` |
| Sprint | `O` |
| Toggle flashlight | `P` |
| Use unique power | `M` |

Player 2 has no mouse to aim with (there's only one on the device), so they — and anyone on a touchscreen — aim by facing whichever direction they're moving, holding the last facing when stationary. Real analog-stick aim is a natural follow-up once there's gamepad hardware to test it against.

**Gamepad:** move/shoot/sprint/toggle-light/power are all bound for two controllers (device 0 = player 1, device 1 = player 2), but there's no dedicated aim input yet — same movement-direction fallback as above applies.

**Touch:** an on-screen virtual joystick (drag to move, releases to center) shows automatically on touchscreens, one per player via `touch_joystick_p1`/`touch_joystick_p2` groups. Shooting/aiming on touch isn't built yet — that's the next touch-control piece.

---

## Mechanics

### Flashlight / Visibility
The flashlight is a `PointLight2D` whose cone texture is generated procedurally at runtime (no art asset needed) — a ~70° cone, range tunable per-player, that rotates to follow aim. `CanvasModulate` darkens everything else to near-black, and walls cast real shadows via `LightOccluder2D`.

On top of that, every player also has a small, **always-on** ambient glow independent of the flashlight toggle — enough to see your immediate surroundings and tell whether you're actually moving, even with the main light off. It has **zero effect on detection or stealth** (that's driven purely by whether the light is toggled on, not by actual rendered brightness) — it exists purely so "light off" means hard-to-detect, not literally unable to see your own feet.

### Minimap
A Control panel (not a camera/viewport) in the top-right of the HUD. It draws the arena's wall layout directly (so it reads as an actual map, not just dots on a blank panel), plus:
- Player dot: white
- Enemy dots: red, removed when the enemy dies
- Fireplace / pickup dots: orange / yellow / pink / purple, removed once collected

**The whole minimap disappears when your flashlight is off** — no layout, no dots, nothing. Light is the only way to see the map, same as it's the only way enemies can really see you.

### Audio as Gameplay
Every sound hook is wired and silent until an actual audio file is assigned (same "drop in a file, it just works" pattern throughout):
- Gunshot, muzzle flash (visual + brief point-light pulse), flashlight toggle click, wall-bump ("you just walked into something"), footsteps (volume naturally increases with proximity via positional audio, no extra code needed), growl while hunting, a one-shot "lock-on" stinger the instant an enemy spots you, a heartbeat loop at 1 HP, and an ambient drone that pitches up as the nearest monster closes in.
- Gunshots alert nearby idle monsters within a radius.

### Ammo & Health
- Starting ammo: **12** (ammo pickups restore **6**)
- Starting HP: **3** in Solo — Versus mode runs a higher pool (**6 HP / 16 ammo** per player) since a 3-HP duel ends on the first exchange
- No regeneration; health pickups restore HP
- Both are **per-player** state (not shared), so two Versus players never fight over one HP/ammo pool

### Fireplaces
Walk into one to ignite it — consumes one of **3 lighter charges** (resets each level) and lights a radius bigger than your own flashlight (and casts real shadows the same way) for **15 seconds**, then goes dark again. It's a second, independent light source: your own flashlight toggle and movement are completely unaffected while one's burning. Unlit fireplaces give off a faint ember glow so they're spottable before you're standing on top of one, and show up on the minimap.

---

## Powerups

One reusable pickup script covers every type — each gets a distinct **shape** (not just color) so its effect is readable at a glance even as a placeholder:

| Powerup | Shape | Effect |
|---|---|---|
| Speed Boost | Lightning bolt | Move speed multiplier for a few seconds |
| Invincibility | Shield | `take_damage()` is a no-op for the duration |
| Light Boost | Sunburst | Flashlight range scales up (also increases how far enemies can spot you — it's a trade-off, not a free buff) |
| Stealth | 4-point star | Completely unnoticeable — even point-blank with your light on — for a few seconds |

In **Versus mode**, each player also has one of these as a built-in **unique power** on a cooldown (`Q`/`M` by default) — the exact same effect system a pickup uses, just button-triggered instead of walked over. Currently Player 1 gets Speed, Player 2 gets Stealth, as a first example of asymmetric powers; swapping which power goes to which player (or letting players choose) is just changing exported values on the scene.

---

## Enemy Types (Solo mode)

### Walker
The standard enemy. Medium speed while AWARE, charges at full speed once it locks onto you.

### Crawler
1.8× Walker's speed once hunting. Harder to escape once spotted.

### Lurker
Teleports to a random nearby spot every few seconds while AWARE — the most unpredictable of the three.

### Detection FSM

```
IDLE ──(hears you, or line-of-sight + close/lit)──► AWARE ──(spotted)──► HUNT
  ▲                                                                        │
  └──────────────── gives up after losing contact for 2.5s ───────────────┘
```

Detection requires an actual unobstructed **line of sight** — a wall between you and an enemy fully hides you, it can't "sense" you through it. With the light **on**, enemies can spot you from a short range in any direction or from further away in your flashlight's own cone; with it **off**, only literally bumping into something or making noise (sprinting, gunshots) gives you away. A **Stealth** powerup suppresses all of this entirely while active. Once hunting, an enemy that genuinely loses track of you (no sight, sound, or proximity) for 2.5 seconds gives up and goes back to idle — it doesn't chase forever off one stale cue.

---

## Level Overview

Only one arena exists per mode right now:

| Mode | Scene | Size | Notes |
|---|---|---|---|
| Solo — Level 1 | `scenes/levels/level_1.tscn` | 960×704 | Open floor plan, scattered crate cover (not a tight maze), 5 Walkers, ammo/health/4 powerup pickups, 1 fireplace, exit open from the start |
| Versus Arena | `scenes/levels/arena_versus.tscn` | 1280×896 | Larger, fully sealed (no entrance/exit), 10 scattered crate blocks for cover, 2 ammo pickups, no AI — pure PvP |

Levels 2–5 and a boss enemy (both mentioned in early planning) are **not built yet**.

---

## Scene Architecture

### Solo level (`level_1.tscn`)

```
World (Node2D, level_manager.gd)
├── CanvasModulate                    ← darkens everything outside lit areas
├── Maze (Node2D, maze.gd)            ← builds floor/walls from a text grid at load
│   └── [Wall instances]              ← per-cell prefab: collision + LightOccluder2D + art
├── NavRegion (NavigationRegion2D)    ← baked at runtime from everything in the "walls" group
├── Player (player.tscn)
│   ├── Flashlight / AmbientGlow (PointLight2D)
│   ├── GunPoint → MuzzleFlash / MuzzleLight
│   └── several AudioStreamPlayer2D hooks (silent until a stream is assigned)
├── Monsters (Node2D) → Walker/Crawler/Lurker instances (enemy.gd FSM base)
├── Pickups (Node2D) → ammo / health / powerup instances
├── Fireplace instances
├── ExitPortal (Area2D)
└── HUD (CanvasLayer, hud.gd)
    ├── Minimap (Control, minimap.gd)  ← draws maze + dots, not a camera/viewport
    └── Joystick (touch, virtual_joystick.gd)
```

### Versus arena (`arena_versus.tscn`)

Split-screen without a shared camera: two `SubViewport`s stacked top/bottom, **sharing one `World2D`** (so it's one real arena, not two disconnected copies) but each with its **own** `Camera2D` locked to one player.

```
VersusArena (Control, versus_manager.gd)
└── VBox
    ├── P1Container (SubViewportContainer)
    │   └── P1Viewport (SubViewport)        ← the "real" world: Maze, both Players, pickups
    │       ├── Player1 (owns_camera = true — its own Camera2D drives this viewport)
    │       ├── Player2 (owns_camera = false — rendered here, but not viewed from here)
    │       └── LocalBulletPool             ← see note below
    ├── Divider
    └── P2Container (SubViewportContainer)
        └── P2Viewport (SubViewport, world_2d shared with P1Viewport)
            └── P2Camera                    ← synced to Player2's position every frame
```

**Why there's a `LocalBulletPool`:** the global `BulletPool` autoload lives in the root window's `World2D`, which is a *different physics space* from anything inside a `SubViewport`. Bullets fired through the autoload would fly straight through players with zero collision. `player.gd` prefers a bullet pool in the scene's own `"local_bullet_pool"` group (living in the same viewport as the players) when one exists, falling back to the global autoload otherwise — so Solo scenes (no SubViewports) are completely unaffected.

### Autoloads (Globals)

| Autoload | Purpose |
|---|---|
| `Globals.gd` | Cross-scene state: current level, score, high score, lighter charges. HP/ammo are now **per-player** (on `player.gd`), mirrored into `Globals.player_hp`/`ammo` for player 1 only so nothing else that reads them breaks. |
| `BulletPool.gd` | Pre-instantiated bullet pool — no runtime instantiate/free. Also usable as a plain (non-autoload) node, which is exactly what `LocalBulletPool` does. |

### Key Scripts

| Script | Responsibility |
|---|---|
| `player.gd` | Movement, aim, shooting, HP/ammo, flashlight + ambient glow, muzzle flash, wall-bump audio, timed-effect system (powerups), the power button, `player_index`-based input resolution (so one script serves both local players) |
| `enemy.gd` | FSM base (IDLE/AWARE/HUNT/DEAD), line-of-sight detection, navmesh pathfinding, contact damage, audio hooks |
| `walker.gd` / `crawler.gd` / `lurker.gd` | Enemy.gd subclasses — speed/teleport overrides only |
| `bullet.gd` / `bullet_pool.gd` | Pooled projectile; damages enemies or a different-team player |
| `maze.gd` | Builds floor/walls from a `PackedStringArray` text grid; also merges wall-run collision to avoid seam-tunneling, and seals an outer boundary so you can't wander off into the void |
| `wall.gd` | Reusable wall prefab — one exported `size`, builds its own collision + occluder + art |
| `powerup.gd` | Generic timed-effect pickup, one script for all 4 effect types |
| `fireplace.gd` | Ignite/extinguish timer, ember glow, lighter-charge consumption |
| `level_manager.gd` | Solo mode: kill tracking, exit, HUD/minimap wiring, navmesh baking |
| `versus_manager.gd` | Versus mode: split-screen world sharing, per-player HUD, win condition, results screen |
| `arena_camera.gd` | A shared-midpoint camera (built, not currently used — Versus uses per-player cameras instead; kept for a possible future co-op mode) |
| `hud.gd` / `minimap.gd` | Solo HUD/minimap — signal-driven, no direct Globals reads |
| `virtual_joystick.gd` | Touch movement input, one instance per player via group membership |

---

## Systems Checklist

### Core (done)
- [x] Project structure, input map, physics layers
- [x] CharacterBody2D movement, mouse/flashlight-direction aim
- [x] Procedural flashlight cone (no art asset needed) + always-on ambient glow
- [x] `CanvasModulate` darkness + `LightOccluder2D` shadows
- [x] Pooled bullets, muzzle flash
- [x] Enemy FSM with line-of-sight detection + "gives up" timer
- [x] `NavigationAgent2D` + runtime-baked `NavigationRegion2D` pathfinding
- [x] Text-grid maze builder with merged wall collision + sealed boundary
- [x] HUD (HP/ammo/kills), Control-based minimap drawing the real layout
- [x] Pause menu
- [x] Ammo/health pickups, save/load high score
- [x] Generic powerup system (speed/invincibility/light-boost/stealth) with distinct shapes
- [x] Fireplaces (temporary big light, limited charges, ember glow, minimap dot)
- [x] Audio hooks for every major event (silent until streams are assigned)
- [x] On-screen virtual joystick for touch
- [x] Local split-screen Versus mode: per-player cameras, PvP damage, unique powers, win/results screen
- [x] `run.bat` — double-click to play, no Godot editor needed

### Not started
- [ ] Levels 2–5
- [ ] Boss enemy
- [ ] Touch aim/shoot controls (joystick covers movement only so far)
- [ ] Gamepad aim (movement-direction fallback works, true analog aim doesn't exist)
- [ ] Input rebinding menu
- [ ] Real art/sound assets (everything is placeholder shapes + silent hooks)
- [ ] HTML5 / Windows exports, Itch.io page
- [ ] Playtesting pass

---

## Asset Credits

| Asset | Source | License |
|---|---|---|
| Dungeon tiles, characters, items (`assets/sprites/dungeon/`) | [Kenney — Scribble Dungeons](https://kenney.nl/assets/scribble-dungeons) | CC0 |
| Placeholder sprites (everything not yet reskinned — player/enemy silhouettes, powerup icons, etc.) | Built procedurally / flat shapes, no external asset | — |
| Sound effects | [freesound.org](https://freesound.org) | Various (log each file) |
| Ambient music | TBD | TBD |

> **Rule:** Every asset used in VOIDLIGHT must be listed here with its license before the game ships. No exceptions.

---

## Status & Roadmap

The original plan was a 3-month, 5-level solo horror game shipping by September 30, 2026. That date has passed, and the scope has grown well beyond the original plan — first with local split-screen Versus, and now with a much bigger pivot toward a **web-based multiplayer arena shooter** (see [Next: Web Multiplayer Arena](#next-web-multiplayer-arena-active-design)). There's no fixed ship date; development is ongoing and scope is still actively being shaped.

**What actually exists today:** a fully playable Solo arena and a fully playable 2-player local Versus arena, both with real mechanics (not just placeholders) — flashlight/darkness, stealth detection, pathfinding, powerups, fireplaces, audio hooks throughout, and mobile-friendly touch *movement*. **What's missing** for those two modes: additional level content (2–5, boss), real art/sound, and export/ship logistics.

**What's next (active design, not yet built):** the web multiplayer arena — real networking (WebSocket client-server, recommended), bright/colorful matches instead of always-dark, up to 5 players FFA or 2–3v2–3 teams, 6 selectable superpowers, touch aim/shoot controls, and graceful handling of laggy/disconnected players. Open decisions before deep implementation starts are listed in that section (server hosting, final power roster, team-assignment UI).

### Other ideas under consideration (not committed)
- A co-op mode (two players vs. AI monsters together) — the shared-midpoint `arena_camera.gd` was built with this in mind
- Procedurally generated levels
- Boss enemy for a later level

---

## How to Run

### Quickest: `run.bat` (no Godot editor needed)
1. Double-click `run.bat` at the project root.
2. First time only: if it can't find a `godot/Godot.exe` next to it, download the standard (non-.NET) Godot 4.x build from [godotengine.org/download](https://godotengine.org/download), rename it to `Godot.exe`, and drop it in a `godot/` folder next to `run.bat`.
3. It launches straight into the game — no editor UI.

### In the Godot Editor
1. Download [Godot 4.x stable](https://godotengine.org/download) (4.7.x is what this project is built/tested against)
2. Clone or download this repository
3. Open Godot → Import Project → select the `project.godot` file
4. Press `F5` to run

### HTML5 / Windows exports
Not set up yet — see [Status & Roadmap](#status--roadmap).

---

*VOIDLIGHT — built in Godot 4.7.x — Chief — 2026*
