# VOIDLIGHT

> *You can only see as far as your light allows. But they can hear everything.*

A 2D top-down horror survival game built in Godot 4.x.  
Developer: **Sonpon Ye-shua Chief** | Engine: **Godot 4.x** | Language: **GDScript**  
Target Platform: **Itch.io (HTML5 + Windows)**

---

## Table of Contents

- [Concept](#concept)
- [Core Loop](#core-loop)
- [Controls](#controls)
- [Mechanics](#mechanics)
- [Enemy Types](#enemy-types)
- [Level Overview](#level-overview)
- [Scene Architecture](#scene-architecture)
- [Systems Checklist](#systems-checklist)
- [Asset Credits](#asset-credits)
- [Development Roadmap](#development-roadmap)
- [How to Run](#how-to-run)

---

## Concept

VOIDLIGHT is a 2D top-down horror survival game. The player is trapped inside a dark, labyrinthine facility armed with nothing but a flashlight and a gun. The core tension: **you can only see as far as your light reaches**, but monsters navigate by sound. Every footstep you take is information they can use.

Each level is a self-contained map. Your objective is simple — **kill every monster and get out alive**. The minimap in the top-right corner shows you the full layout and every enemy position. But knowing where they are and surviving long enough to reach them are very different things.

---

## Core Loop

```
Spawn → Explore in darkness → Hear monsters approaching
→ Locate via sound + minimap → Engage in flashlight cone
→ Kill all monsters → Exit portal unlocks → Next level
```

**The four pillars of VOIDLIGHT:**

| Pillar | Description |
|---|---|
| **Tension** | You hear them before you see them |
| **Information Asymmetry** | Minimap sees all. Your flashlight sees little. |
| **Decision Making** | When to move, when to stay still, when to shoot |
| **Escalation** | Every level is harder than the last |

---

## Controls

VOIDLIGHT is designed to play identically on **desktop, browser, gamepad, and touch**. Every action maps to a named input action in `project.godot`, so all four schemes drive the same code paths — no separate mobile build.

| Action | Keyboard + Mouse | Gamepad | Touch (mobile / tablet) |
|---|---|---|---|
| **Move** | `W A S D` / Arrow keys | Left stick | Left virtual joystick |
| **Aim flashlight** | Mouse position | Right stick | Drag anywhere on the right half of the screen |
| **Shoot** | `Left Click` | `RT` / `R2` | Fire button (bottom-right), or tap on the right half |
| **Sprint** | `Shift` (hold) | `LT` / `L2` (hold) | Sprint toggle above the fire button |
| **Pause** | `Escape` | `Start` | Pause icon (top-left of HUD) |
| **Debug overlay** *(dev only)* | `F1` | `Select` / `Back` | — (disabled in release builds) |

### Input notes

- **Aim priority:** on hybrid devices the last-used input wins — moving the mouse, nudging the right stick, or dragging on screen each take over aiming instantly.
- **Sprint = risk:** sprinting is faster but roughly doubles your noise radius. Monsters in AWARE state path toward your last noise source. On touch, sprint is a **toggle** so you never need a third thumb.
- **Touch layout:** the virtual joystick, aim zone, and buttons only appear when a touchscreen is detected (`DisplayServer.is_touchscreen_available()`), and their positions/opacity are adjustable in the pause menu.
- **Rebinding:** keyboard and gamepad bindings are remappable from the options menu; changes are saved with `FileAccess` alongside the high score.
- **Safe areas:** HUD and touch controls respect device notches / rounded corners so nothing critical sits under the bezel.

---

## Mechanics

### Flashlight / Visibility

The flashlight is a `PointLight2D` node attached to the player. The world is covered by a `CanvasModulate` set to near-black — the flashlight cuts through it in a cone.

- Cone angle: ~70 degrees
- Walls and objects cast real shadows via `LightOccluder2D`
- The cone rotates to follow the mouse cursor at all times
- Everything outside the cone is effectively invisible

### Minimap

A `SubViewport` renders a second camera positioned high above the level. Displayed as a panel in the top-right corner of the HUD.

- Player dot: **white**
- Enemy dots: **red** — visible even in darkness
- Map layout fully visible
- Enemy dots are removed when the enemy is killed

### Audio as Gameplay

Monsters emit positional `AudioStreamPlayer2D` audio. This is not just atmosphere — **it is information**.

- Footstep volume increases as monster approaches
- In HUNT state: growling/breathing intensifies
- Gunshots alert nearby IDLE monsters within a radius
- Ambient drone pitch shifts based on nearest monster distance

### Ammo

The player starts each level with limited ammo. Pickups are scattered across the map.

- Default starting ammo: **12 rounds**
- Pickup restores: **6 rounds**
- When ammo = 0, shooting is disabled
- Ammo count displayed on HUD at all times

### Player Health

- Default HP: **3 hits**
- HP bar displayed on HUD
- No natural regeneration
- Health pickups available on harder levels

---

## Enemy Types

### Walker *(introduced Level 1)*
The standard enemy. Moves at medium speed in AWARE state, charges in HUNT state. Predictable — but dangerous in groups.

### Crawler *(introduced Level 2)*
Faster than the Walker in HUNT state (1.8× speed multiplier). Low to the ground with a different animation profile. Harder to see in tight corridors.

### Lurker *(introduced Level 3)*
Teleports to a random nearby position every 4 seconds while in AWARE state. Unpredictable positioning makes it the most dangerous enemy type in the game.

### Enemy FSM

Every enemy runs a Finite State Machine with four states:

```
IDLE ──(enters sound radius)──► AWARE ──(very close / in flashlight)──► HUNT
                                                                           │
                                                                      (shot)
                                                                           │
                                                                         DEAD
```

| State | Behaviour |
|---|---|
| `IDLE` | Wanders slowly in random directions |
| `AWARE` | Moves toward last known player position at medium speed |
| `HUNT` | Charges at full speed — attacks on contact |
| `DEAD` | Plays death animation, disables collision, removes from scene |

---

## Level Overview

| Level | Monsters | Enemy Types | Map Size | New Element |
|---|---|---|---|---|
| 1 | 5 | Walker | Small | Tutorial — open layout, clear sightlines |
| 2 | 8 | Walker, Crawler | Medium | Tighter corridors, Crawler speed threat |
| 3 | 12 | Walker, Crawler, Lurker | Large | Lurker teleportation, scarce ammo |
| 4 | 15 | All types | Large | Multiple threats at once, resource pressure |
| 5 | 20 + Boss | All types + Boss | XL | Boss requires 5 hits to kill |

---

## Scene Architecture

### Scene Tree

```
World (Node2D)
├── TileMap                          ← level geometry + colliders + occluders
├── CanvasModulate                   ← full-screen darkness layer
├── NavigationRegion2D               ← walkable area for enemy pathfinding
├── Player (CharacterBody2D)
│   ├── CollisionShape2D
│   ├── AnimatedSprite2D
│   ├── Flashlight (PointLight2D)
│   ├── GunPoint (Marker2D)          ← bullet spawn position
│   ├── AudioStreamPlayer2D          ← gunshot, footsteps
│   └── GunRayCast (RayCast2D)
├── Monsters (Node2D)                ← container for all enemies
│   └── [Enemy] (CharacterBody2D)
│       ├── CollisionShape2D
│       ├── AnimatedSprite2D
│       ├── NavigationAgent2D
│       └── AudioStreamPlayer2D      ← footsteps, growl
├── Pickups (Node2D)
│   ├── AmmoPickup (Area2D)
│   └── HealthPickup (Area2D)
└── HUD (CanvasLayer)
    ├── KillCounter (Label)
    ├── AmmoDisplay (Label)
    ├── HPBar (TextureProgressBar)
    ├── PauseMenu (Control)
    └── Minimap (SubViewportContainer)
        └── SubViewport
            └── MinimapCamera (Camera2D)
```

### Autoloads (Globals)

| Autoload | Purpose |
|---|---|
| `Globals.gd` | Current level, player HP, ammo, score, total kills |
| `BulletPool.gd` | Pre-instantiated bullet pool — no runtime instantiate/free |

### Key Scripts

| Script | Node | Responsibility |
|---|---|---|
| `player.gd` | Player | Movement, rotation, shooting, HP, signals |
| `enemy.gd` | Enemy (base) | FSM, navigation, audio, death |
| `walker.gd` | Walker | Extends enemy.gd |
| `crawler.gd` | Crawler | Extends enemy.gd, modified HUNT speed |
| `lurker.gd` | Lurker | Extends enemy.gd, teleport behaviour |
| `hud.gd` | HUD | Connects signals, updates all UI elements |
| `minimap.gd` | Minimap | Syncs dot positions to world coordinates |
| `level_manager.gd` | World | Tracks kill count, triggers exit portal, loads next scene |

---

## Systems Checklist

Track build progress here. Check off as each system is completed.

### Month 1 — Foundations
- [ ] Godot editor and project structure set up
- [ ] GDScript fundamentals — variables, functions, loops, signals
- [ ] CharacterBody2D player movement (WASD)
- [ ] Mouse rotation — flashlight arm follows cursor
- [ ] TileMap walls with collision
- [ ] Bullet scene — instantiated on click, destroys on wall contact
- [ ] Enemy hit detection via Area2D signals
- [ ] Scene transitions — Menu → Level → Level Complete → Game Over
- [ ] HUD — HP bar + kill counter (CanvasLayer)
- [ ] Ammo system + pause menu
- [ ] Save/load high score with FileAccess

### Month 2 — Core Systems
- [ ] CanvasModulate full-screen darkness
- [ ] PointLight2D flashlight cone
- [ ] LightOccluder2D shadow casting on walls
- [ ] NavigationRegion2D + NavigationAgent2D enemy pathfinding
- [ ] Enemy FSM — IDLE / AWARE / HUNT / DEAD
- [ ] Positional AudioStreamPlayer2D on enemies
- [ ] Ambient drone + SFX bus layout
- [ ] SubViewport minimap with player + enemy dots
- [ ] Screen shake on hit (Tween + Camera2D offset)
- [ ] Vignette overlay
- [ ] AnimatedSprite2D — walk / idle / death for player + enemies
- [ ] CPUParticles2D — muzzle flash + death burst
- [ ] Full SFX implementation

### Month 3 — Polish & Ship
- [ ] Globals.gd autoload — persistent state across scenes
- [ ] Level 1 complete and playable
- [ ] Level 2 complete and playable
- [ ] Level 3 complete and playable
- [ ] Crawler enemy type
- [ ] Lurker enemy type
- [ ] Godot profiler audit — 60fps stable on Level 3
- [ ] Bullet object pool (BulletPool.gd)
- [ ] Debug overlay (F1 toggle)
- [ ] Zero critical bugs across all levels
- [ ] HTML5 export — runs in browser
- [ ] Windows export — .exe builds
- [ ] Itch.io page live
- [ ] Playtest with 3+ real users
- [ ] Top playtest fixes implemented
- [ ] Title screen art
- [ ] Win screen + credits
- [ ] Post-mortem written
- [ ] **v1.0 shipped**

---

## Asset Credits

*Update this section as assets are sourced.*

| Asset | Source | License |
|---|---|---|
| Dungeon tiles, characters, items (`assets/sprites/dungeon/`) | [Kenney — Scribble Dungeons](https://kenney.nl/assets/scribble-dungeons) | CC0 |
| Placeholder sprites (everything not yet reskinned) | [Kenney.nl](https://kenney.nl) | CC0 |
| Sound effects | [freesound.org](https://freesound.org) | Various (log each file) |
| Ambient music | TBD | TBD |

> **Rule:** Every asset used in VOIDLIGHT must be listed here with its license before the game ships. No exceptions.

---

## Development Roadmap

```
Jul 08 ──► Aug 04    Month 1: Foundations
Aug 05 ──► Sep 01    Month 2: Core Systems  
Sep 02 ──► Sep 30    Month 3: Polish & Ship

Target ship date: September 30, 2026
Platform: Itch.io (HTML5 primary, Windows secondary)
Version: v1.0
```

### Post-v1.0 Ideas *(do not touch until v1.0 is shipped)*
- Boss enemy for Level 5
- Flashlight battery mechanic (horror difficulty modifier)
- Procedurally generated levels
- Simple controller support
- Mobile port (touch controls)

---

## How to Run

### In the Editor
1. Download [Godot 4.x stable](https://godotengine.org/download)
2. Clone or download this repository
3. Open Godot → Import Project → select the `project.godot` file
4. Press `F5` to run

### HTML5 (Browser)
1. Export via **Project → Export → HTML5**
2. Serve locally: `python -m http.server` inside the export folder
3. Open `http://localhost:8000` in browser

### Windows
1. Export via **Project → Export → Windows Desktop**
2. Run `VOIDLIGHT.exe`

---

*VOIDLIGHT — built in Godot 4.x — Chief — 2026*
