# Akira

> *You can only see as far as your light allows. But they can hear everything.*

A 2D top-down arena game built in Godot 4.x. Two modes are built and playable today — **Solo** survival (clear a dark, monster-filled arena and reach the exit) and **Versus** (two players, one device, split-screen PvP) — and the active design direction is a **web-based multiplayer tactical/psychological arena shooter**: bright, colorful, up to 5 players per match (or 2–3v2–3 teams), limited vision range (you can't just see every enemy on sight), each player picking one unique **Gen** (short for the engineered abilities that replace the old "superpower" idea), playable in a browser on desktop or mobile. The fight is as much about reading, baiting, and bluffing opponents as it is about aim. See [Next: Web Multiplayer Arena](#next-web-multiplayer-arena-active-design) for where this is headed.

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

Akira started as a solo horror-survival game: you're dropped into a dark arena with nothing but a flashlight and a gun. You can only see what your light touches — everything outside the cone is invisible — but monsters can hear you, especially if you sprint. Turning the light off makes you nearly undetectable, but also blind: no minimap, no maze layout, just your own faint ambient glow to feel your way around.

That same light-vs-detection tension turned out to work just as well **player vs player** — so Akira now also has a local split-screen **Versus** mode: two people on one device, same arena, hunting each other with the same flashlight/stealth mechanics, each with one unique power (soon to be called a **Gen**, see below) that can swing a fight.

---

## Game Modes

### Solo
Enter an open arena full of scattered crate cover and AI-controlled monsters. Kill or evade them, use pickups and fireplaces along the way, and reach the exit. The exit is open from the start — the goal is getting out alive, not clearing every monster (though clearing them stops them chasing you).

### Versus (2 Player, Local)
Two players, one device, **no shared camera** — the screen splits top/bottom and each player only ever sees their own surroundings, exactly like they would playing alone. Same arena-with-cover philosophy as Solo, but larger, fully sealed (no entrance/exit — there's nothing to escape, just a fight), and PvP: your bullets hurt the other player, theirs hurt you. Each player gets one unique power on a cooldown (see [Powerups](#powerups)). Last player with HP left wins.

Reachable from the main menu's **Versus (2 Player, Local)** button.

### Online (first playable version)
Reachable from the main menu's **Online (Multiplayer)** button. With a game server set up (see *Running a dedicated server*), the host picks a **4-character room code** (letters and digits, checked against every room open so no two games share one) and friends type it to join; without one, one player hosts on their own computer and the others join by the host's IP or an 8-character address code, everyone waits in a room showing who's in (names, chosen Gen, team, host tag, up to 5 players), picks a Gen from a pop-out ring, and the host starts the match. The host chooses **Free-For-All** or **Teams**: in team mode players are dealt onto Team A / Team B **at random, in balanced halves** (the leader can Shuffle; nobody picks a side; the smaller side of an uneven split, e.g. 2 v 1 or 3 v 2, gets +40% health), teammates always see each other on the map, there's no friendly fire (your own bomb can still hurt *you*), A spawns down the left edge and B down the right, and the last team standing wins. There are **five arenas** and one is **picked at random each time a match starts** (never the same one twice in a row; the host chooses and tells everyone, so all players load the same one; its name shows when the match begins): the **Ruined District** (42×28, below), **The Colosseum** (an oval with a gated fortress in the middle), **The Cathedral** (a cross-shaped hall with four corner chapels), **The Pinwheel** (a round field with four spiralling diagonal walls) and **The Bunker** (rooms, side rooms and corridors). The four newer ones are built to be mirror or rotation symmetric, so teams start fairly. The Ruined District is a large (42×28 cells, 2688×1792), deliberately **asymmetric ruined war zone**: irregular shot-up buildings with doorways and blown-out breaches, sandbag lines, wooden crate stacks, burnt-out vehicle wrecks, barrels, craters and rubble, on cracked, stained, bullet-scarred ground with a dark vignette. A camera follows you and a corner **minimap** shows the layout, you, your teammates, an enemy you're haunting with Poltergeist, and your own bombs — never other enemies. Enemies are only visible under the limited-vision rule above. All six Gens are live (Camouflage, Shield, Poltergeist, Blackout, Bomb Voyage, Decoy — see the Gen table). Your own movement is predicted locally and reconciled against the host; players who lag are dimmed and tagged, and a dropped connection leaves a dimmed avatar in the match for a grace period instead of vanishing. The winner is announced to everyone, eliminated players spectate, and the host can send the whole room back to the lobby for another round without anyone reconnecting. Mobile touch controls (joystick, aim pad, shoot, Gen, and a detonate button for Bomb Voyage) are wired in.

**Voice chat.** Press `T` (or the on-screen Mic button) to mute/unmute; the mic is voice-activated, so you only transmit while actually speaking. Who hears whom is decided by the server: **in team mode only your own team hears you; in free-for-all (including 1v1) everybody does** — open taunting. **Dead players are heard only by other dead players**, since a spectator sees the whole map and could otherwise narrate enemy positions to a living friend (`DEAD_HEARD_BY_LIVING` in `voice_chat.gd` flips it). A small green dot shows over a talking player's head, only while that avatar is visible, so hearing an enemy never reveals where they are. Voice rides the same server connection as everything else (8 kHz G.711 µ-law, about 8 KB/s per active speaker, nothing when silent; the server caps packet size and per-player bandwidth). The lobby shows `[talking]` next to names.

**Room leader & dedicated server.** Start, the FFA/Teams switch and "Return to Lobby" belong to the **room leader** — whoever has been in the room longest (the host, in a normal hosted game). The role passes to the next-longest player automatically if the leader leaves, and the host re-validates every leader request, so a client can't start a match it isn't entitled to. That makes a **dedicated server** possible: `--server` runs a headless process with no avatar and no roster entry of its own, where the first player to join is the leader. It resets itself when the last player leaves.

---

## Next: Web Multiplayer Arena (Active Design)

This is the direction the game is actively moving in. It's a significant pivot from everything above, captured here while the details get nailed down — Solo and local Versus stay built and playable regardless of how this develops.

### The core reversal: light stops being the default
The original premise — the whole arena is dark, your flashlight is your only vision — is being **scrapped as the default state**. Matches are now **bright and colorful by default**: you can see the arena, the cover blocks, and other players clearly, all the time. Darkness becomes something that happens *to* a match temporarily, not the baseline.

### Platform: web first, mobile-friendly
- Primary export target becomes **HTML5**, played in a browser — desktop and mobile both.
- Touch controls needed for mobile web play:
  - ✅ Virtual joystick for movement — built (`virtual_joystick.gd`)
  - ✅ Drag-to-aim — built (`touch_aim_pad.gd`): drag anywhere on the right side of the screen to aim; releasing holds the last direction instead of snapping to zero
  - ✅ On-screen shoot button — built (`touch_shoot_button.gd`)
  - All three are wired into the Solo HUD today (the live testbed, since the real multiplayer arena doesn't exist yet) and drop straight into that arena once it's built

### Scale & match structure
- **Free-for-all:** up to 5 players per match
- **Team mode:** 2–3 players per team
- Designed to flex beyond those numbers later ("could still take any amount of players")
- A large arena to actually support that many bodies and sightlines at once — bigger than either existing arena
- Players with network trouble should **stay in the match, visually dimmed**, rather than being dropped — the match keeps going around them

### Identity: a tactical, psychological arena shooter
Akira isn't trying to be another twitch-reflex shooter — the identity is **tactical and psychological**. The core tension isn't just "can you aim," it's "do you know where anyone actually is, and do they know where you are." You can win a fight by going loud and burning your Gen outright, or you can win by baiting an enemy into revealing themselves, wasting their Gen, or walking into a read you set up two minutes earlier. Every match is a running information game as much as a shootout.

**Vision is limited, not global.** Players always see the arena layout (map/terrain), but *not* other players by default — only enemies that are close enough or inside your actual view/vision cone are visible, same as a normal line-of-sight shooter. There's no free long-range or minimap tracking of other players. The one deliberate exception is the **Poltergeist** Gen (see below), which pierces this rule for a single tagged target.

✅ **Built (online arena):** an enemy is visible when they're within 180px in any direction, or within 420px inside your 80° forward cone, *and* nothing solid is between you. Firing reveals the shooter to everyone for half a second. Eliminated players spectate with full vision. Faint guide lines around your own avatar show the ring and the cone. This is currently client-side culling (the server still sends every position), so it's a presentation rule, not yet an anti-cheat one. Exact numbers are first-pass and need playtesting.

### Networking approach
Godot's native multiplayer (ENet, raw UDP) **does not work in a browser** — that's a hard constraint, not a preference. For a web build, the real choice is:

| Approach | How it works | Tradeoff |
|---|---|---|
| **WebSocket, client-server** *(recommended)* | One authoritative server; every browser connects to it over a normal WebSocket, using Godot's existing `SceneMultiplayer` + `WebSocketMultiplayerPeer` | Simple, well-supported, naturally gives you one place to implement "dim out a laggy player," anti-cheat, and room/team logic. Needs a server running somewhere continuously — a real hosting decision with an ongoing cost, not something that gets provisioned automatically. |
| **WebRTC, peer-to-peer** | Players connect more directly via `WebRTCMultiplayerPeer` | Lower latency, but needs a signaling server *and* a TURN relay for players behind strict NATs — more infrastructure, not less, and harder to debug. |

**Recommendation: WebSocket client-server**, built server-authoritative (the server decides actual positions/hits, clients predict locally and get corrected) — the standard pattern for exactly this kind of game, and what makes "smooth with no lag" and "handle a lot of concurrent players" realistic goals rather than hopes.

### The Blackout Gen (where "the whole room is dark" goes)
Instead of being the default, darkness becomes **one player's temporary Gen**: for **30 seconds**, the entire arena goes dark for everyone *except* the player who triggered it. The caster doesn't just get a flashlight back — they get a distinct **night-vision look** (a different visual read on the dark arena and everyone in it, not a lit cone), while everyone else is suddenly blind in a normally-lit match. This directly reuses the existing `CanvasModulate`/`PointLight2D` darkness systems already built for Solo mode, but the caster's own view needs a new night-vision presentation rather than reusing the flashlight-cone look as-is.

### Gens — the renamed, reworked power system (5 of 6 implemented)
"Superpowers" is retired as the term — these are now called **Gens**. Each player picks one Gen in a lobby before a match starts (`power_select.gd`/`.tscn`); it charges up on a cooldown during play, the same pattern the pre-existing power-button/effect system already used. `Globals.POWER_DEFS` is the single source of truth for each Gen's duration/strength/cooldown, read by both the lobby and the match. The reworked mechanics below are **design decisions made, not yet implemented in code** — the table marks each one's actual build status separately from its design.

The online versions live in `scripts/net/gens.gd` (`Gens.DEFS`) and `net_player.gd`; the local Versus mode keeps its original effects untouched. Numbers below are first-pass and need playtesting.

| Gen | Design (current direction) | Online build status |
|---|---|---|
| **Camouflage** | Disguises as a crate for up to **60 seconds**. Can move/reposition/scout freely while disguised — but **cannot attack** in that state, and is still fully killable. To attack, the player must **manually drop the disguise first** (press the Gen key again) — a deliberate, player-initiated action, not an automatic cancel-into-shoot — creating a real exposed beat before they can fire. | ✅ Built — crate sprite, name tag hidden, shooting blocked server-side, Q again to drop, 20s cooldown |
| **Shield** *(renamed from Bulwark)* | A 360° shield around the player, lasting up to **30 seconds**, that degrades as it absorbs incoming damage and breaks/drops once it's taken enough | ✅ Built — soaks 4 hits (bombs count as 3), the breaking hit is fully absorbed, visible ring fades with remaining strength, 25s cooldown |
| **Decoy** | Spawns an AI clone that locks onto and hunts one specific opposing player | ✅ Built in local Versus · ✅ Online: a clone wearing the caster's color and name tag (enemies can't tell it from a player; the caster and team see a faint ring) hunts the nearest enemy through the maze via grid pathfinding, deals 20 damage per 0.8s on contact, has 3 HP, dies to any enemy's shots, and expires after 20s; 25s cooldown |
| **Poltergeist** *(renamed from Heavy Gunner)* | Tags one enemy player with a tracking mark — for the Gen's duration, the caster can always see that tagged player's position, piercing the normal limited-vision rule | ✅ Built — haunts the nearest living enemy for 20s, caster sees them anywhere with a purple marker, 25s cooldown |
| **Blackout** | Darkens the whole arena for everyone *except* the caster for **30 seconds** — the caster alone gets a **night-vision view** of the dark arena | ✅ Built — everyone who isn't casting gets a near-black world with only a small personal glow (walls cast real shadows) and their vision shrinks to 70px with no cone; each caster keeps normal vision through a clear green night-goggle view (tinted world, soft dark-green edges). **Blackouts overlap safely:** if a second player casts during yours, your view and your countdown are untouched; they stay in the dark until they cast, then get their own goggles on their own timer. The world stays dark until the last Blackout ends; 40s cooldown |
| **Bomb Voyage** | Drop up to **5 bombs**. Each bomb is set, per-drop, to one of two trigger modes: **proximity** (auto-detonates when an enemy player gets close enough) or **manual** (caster detonates it on command). The caster can always see their own dropped bombs' locations on the map, regardless of range — enemies never see them | ✅ Built — tap Q: proximity (48px trigger), hold Q: manual, E: detonate all manual bombs; 90px blast for 60 damage (three shots' worth), hits the owner too; 1s between drops |

### Health, ammo, medical stations and what the dead leave behind (online)
- **Health** is out of 100 and a shot takes 20, so the bar counts down the remainder (100 → 80 → 60 …) and slides smoothly. A bomb blast takes 60. A shield still counts in hits (4, a bomb counts as 3).
- **Low health (under 40%):** the bar turns red and blinks, the screen edges go red and pulse, the pulse and a heartbeat speed up as health falls, the ambient wind swells about 5 dB, and a low drone fades in. All of it eases in and out and stops when you heal or die.
- **Ammo:** you start with 30 rounds (max 60), one per shot, no reloading. Out of ammo you get a dry click and a hint. **Ammo crates** (9, +20 rounds, back 30s after being emptied) sit around the map; walk over one. Press **H** to put 10 of your rounds on the floor for a teammate (you can't scoop them back for 1.5s; anyone else who walks over them can).
- **Medical stations** (6, shown as green crosses on the minimap): stand beside one for 2.5s and it heals **40%** of full health, then recharges for 45s. Walking away loses the progress. (They heal — they don't bring back a dead player.)
- **When someone dies** they leave their remaining ammo and each Gen they carried on the floor. A dropped Gen shows as a glowing orb with its name (and on the minimap). Walk up and press **F**: it becomes your **second Gen** if you have a free slot; with both slots full it replaces the active one, which is left on the floor in its place. **V** always replaces the active Gen. You can't take one you already carry. Dropped items vanish after 90s.
- **Two Gens:** **R** swaps the active and the spare one (not while the active one is running). The spare keeps recharging in the background; the Gen card shows it. A new Gen starts ready.
- Crates and stations are placed from a fixed seed, so each arena has the same layout of them every match. The numbers (rounds, heal amount, timers) are first guesses and live as constants at the top of `net_pickups.gd` and `net_player.gd`.
- **Touch:** on a touchscreen the pause-menu key list is replaced by buttons — SWAP (shown only with a spare Gen), TAKE (shown only next to a dropped Gen) and DROP AMMO. Replacing your active Gen without a free slot (V) is keyboard-only. The buttons are built but untested on a real phone.

### Gen selection
**Online:** each player picks their Gen in the waiting room (buttons built from `Gens.DEFS`, a one-line blurb for the selected one); the choice syncs to everyone's roster and locks when the host starts the match. **Local Versus:** the pre-match lobby reachable from the **Versus** button picks from the older local effect table, plus an FFA/Team toggle — Team is disabled there since local 2-player can't represent 2–3-per-team. Both are deliberately just the *selection logic*: plain buttons with a simple highlight, not the "press something, a ring of options pops out" visual that's planned as a separate pass.

### Open decisions before deeper implementation
These are the things worth pinning down before sinking real time into the networking layer, since getting them wrong costs real rework:
1. **Where does the server run?** (The server build now exists — see *Running a dedicated server*; what's left is actually deploying it.) Researched: free hosting tiers that sleep-on-idle (Render, Railway) or have been discontinued don't work for an always-on game server. **Oracle Cloud's "Always Free" tier** is the one genuinely-permanent free option found — recommended starting point once the networking layer is ready to deploy.
2. **Gen tuning** — every duration, cooldown, radius and damage number above is a first guess that needs real matches (the online Decoy in particular kills a stationary player in ~4 seconds)
3. **Team/Gen picker visual** — built as the pop-out ring (`radial_picker.gd`) in the online lobby; art/animation polish is a later pass
4. **Custom art** — once sprite files are provided for how players should look, they slot into the existing placeholder-swap pattern (every visual in this project so far is a flat shape or procedural texture specifically so it can be swapped for real art later — same approach applies here)
5. Whether Solo/local Versus stay as permanent separate offline modes, or eventually fold into the same arena content — **decided for now: they stay separate**, untouched while work focuses on the web multiplayer pivot
6. **Limited vision range tuning** — exact vision cone/radius numbers for the new "can't see other players by default" rule aren't picked yet; needs playtesting once it's implemented

---

## Story & words

The game is meant to hold people with its premise and mood rather than effects, so its words live in one editable file: **`assets/story/story.json`**. Each list is picked from at random, so write as many lines as you like; an empty list keeps the game's default wording. `{name}` becomes a player's (or team's) name where noted. Save and restart to see changes.

| Key | Where it shows |
|---|---|
| `lobby` | one line under the ONLINE title in the lobby |
| `match_start` | the banner when a match begins (default: *Fight!*) |
| `eliminated` | the message when a player dies; `{name}` (default: *{name} was eliminated*) |
| `win` | the winner headline on the results screen; `{name}` (default: *{name} wins!*) |
| `epilogue` | a line under the winner headline |
| `gens` | one line of lore per Gen, shown under its description when picking it |

The host makes each pick and sends it, so every player sees the same line. The file ships empty on purpose — nothing is invented for you.

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
| Use Gen | `Q` (online Bomb Voyage: tap = proximity bomb, hold = manual bomb) |
| Detonate manual bombs (online, Bomb Voyage) | `E` |
| Swap to your spare Gen (online) | `R` |
| Take a dropped Gen as a second Gen — or swap it for yours if both slots are full (online) | `F` |
| Replace your active Gen with a dropped one (online) | `V` |
| Drop 10 rounds of ammo for a teammate (online) | `H` |
| Pause (solo/versus) — or, online, open the match menu (**the match keeps going**; you can still be hit) | `Escape` |
| Debug overlay *(dev only)* | `F1` |

**Player 2 (keyboard, for local Versus matches on one keyboard):**

| Action | Key |
|---|---|
| Move | `I J K L` |
| Shoot | `U` |
| Sprint | `O` |
| Toggle flashlight | `P` |
| Use unique power | `M` |

Player 2 has no mouse to aim with (there's only one on the device), so they aim by facing whichever direction they're moving, holding the last facing when stationary, unless a touch aim pad is active for them (see below). Real analog-stick aim is a natural follow-up once there's gamepad hardware to test it against.

**Gamepad:** move/shoot/sprint/toggle-light/power are all bound for two controllers (device 0 = player 1, device 1 = player 2), but there's no dedicated aim input yet — same movement-direction fallback as above applies.

**Touch:** three on-screen controls show automatically on touchscreens, one set per player via `touch_joystick_p1`/`touch_joystick_p2` and `touch_aim_p1`/`touch_aim_p2` group membership:
- **Virtual joystick** (bottom-left) — drag to move, releases to center
- **Aim pad** (drag anywhere on the right side of the screen) — sets aim direction; unlike the joystick, releasing does *not* reset to zero, it holds the last direction, since a player's facing can't be "undefined"
- **Shoot button** (bottom-right) — fires while held, same as a mouse click or key

Aim priority in `player.gd` is: a visible touch aim pad first, then mouse (player 1, desktop), then movement-direction facing (everyone else, or touch with no aim pad).

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

### Online sound
The online game's sounds come from the `Sfx` autoload (`scripts/autoload/sfx.gd`) and the files in `assets/audio/sfx/`. `Sfx.play(name)` plays a sound the same everywhere (interface, your own Gens); `Sfx.play_at(name, position)` plays it *from* a spot — louder near, panned left/right, silent far away. Everything the game reacts to:

| Heard by | Sounds |
|---|---|
| Everyone, from where it happened | gunshots, shots hitting a wall, someone being hit, someone dying, a shield breaking, bomb explosions, footsteps (short range, and a Decoy's footsteps sound exactly like a player's) |
| Everyone | the lights going out / coming back (Blackout), match start, victory / defeat |
| Only the player using it | Shield on, Camouflage on/off, Poltergeist, Decoy, placing a bomb, being hit (a heavier thump) — so Gens give nothing away |
| Interface | a click on every button in the game (confirm / back variants by button name) |
| The world | a quiet looping wind bed, and a far-off thud every 20–50 seconds |

A camouflaged player makes no footsteps. Your own gunshot plays the instant you click (it isn't kept waiting for the host's reply on a slow connection; the host's reply is then silent for that shot). The waiting room has the same wind, quieter. The **Esc** menu also lists the keys. A **Sound** slider in the in-match menu (Esc) sets the volume and is remembered. A dedicated (headless) server skips all of it.

The game's sounds are layered, pitched and filtered from the CC0 packs by `tools/build_sfx.py` (needs `pip install numpy soundfile` and the packs' zips in the project root; the finished `.ogg` files are committed, so nobody needs either just to play). To change how something sounds, edit its recipe there and re-run it, or change the file names / volumes in the `SOUNDS` table at the top of `sfx.gd`. A name with a missing file is simply silent.

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

In **Versus mode**, each player also has one unique Gen on a cooldown (`Q`/`M` by default) — the exact same effect system a pickup uses, just button-triggered instead of walked over. These are the 5 Gens from the [web multiplayer design](#next-web-multiplayer-arena-active-design) (Camouflage, Shield, Decoy, Poltergeist/Heavy Gunner, Blackout), picked per-player in the pre-match lobby (`power_select.gd`/`.tscn`) rather than hardcoded — defaults apply if the arena is loaded directly, skipping the lobby. The code/scripts still use "power" in names (`power_select.gd`, `POWER_DEFS`, etc.) — that's an internal naming detail, not a player-facing term; "Gen" is the in-game word.

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
    ├── Joystick (touch, virtual_joystick.gd)    ← movement
    ├── AimPad (touch, touch_aim_pad.gd)         ← drag-to-aim
    └── ShootButton (touch, touch_shoot_button.gd)
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
| `Globals.gd` | Cross-scene state: current level, score, high score, lighter charges. HP/ammo are now **per-player** (on `player.gd`), mirrored into `Globals.player_hp`/`ammo` for player 1 only so nothing else that reads them breaks. Also holds `POWER_DEFS` (the superpower duration/strength/cooldown table) and the lobby's selections (`match_mode`, `selected_power_p1`/`p2`). |
| `Sfx` (`sfx.gd`) | Online-game sound effects: positional and flat playback, button clicks, ambient bed, volume setting (see "Online sound"). |
| `BulletPool.gd` | Pre-instantiated bullet pool — no runtime instantiate/free. Also usable as a plain (non-autoload) node, which is exactly what `LocalBulletPool` does. |

### Key Scripts

| Script | Responsibility |
|---|---|
| `player.gd` | Movement, aim, shooting, HP/ammo, flashlight + ambient glow, muzzle flash, wall-bump audio, timed-effect system (powerups + the 5 Gens), the power button, `player_index`-based input resolution (so one script serves both local players) |
| `enemy.gd` | FSM base (IDLE/AWARE/HUNT/DEAD), line-of-sight detection, navmesh pathfinding, contact damage, audio hooks |
| `walker.gd` / `crawler.gd` / `lurker.gd` | Enemy.gd subclasses — speed/teleport overrides only |
| `decoy.gd` | Enemy.gd subclass for the Decoy Gen — locks onto one chosen player instead of the nearest, expires after a lifespan |
| `bullet.gd` / `bullet_pool.gd` | Pooled projectile; damages enemies or a different-team player |
| `maze.gd` | Builds floor/walls from a `PackedStringArray` text grid; also merges wall-run collision to avoid seam-tunneling, and seals an outer boundary so you can't wander off into the void |
| `wall.gd` | Reusable wall prefab — one exported `size`, builds its own collision + occluder + art |
| `powerup.gd` | Generic timed-effect pickup, one script for all 4 solo-mode effect types |
| `fireplace.gd` | Ignite/extinguish timer, ember glow, lighter-charge consumption |
| `level_manager.gd` | Solo mode: kill tracking, exit, HUD/minimap wiring, navmesh baking |
| `versus_manager.gd` | Versus mode: split-screen world sharing, per-player HUD, win condition, results screen, applies each player's lobby-selected Gen |
| `power_select.gd` | Pre-match lobby: FFA/Team toggle, per-player Gen picker built from `Globals.POWER_DEFS`, writes the selections `versus_manager.gd` reads |
| `arena_camera.gd` | A shared-midpoint camera (built, not currently used — Versus uses per-player cameras instead; kept for a possible future co-op mode) |
| `hud.gd` / `minimap.gd` | Solo HUD/minimap — signal-driven, no direct Globals reads |
| `virtual_joystick.gd` | Touch movement input, one instance per player via group membership |
| `touch_aim_pad.gd` | Touch-drag aim input; holds last direction on release instead of resetting to zero |
| `touch_shoot_button.gd` | On-screen fire button; raw touch handling (not engine `TouchScreenButton`) so it can use the same anchor-based layout as the rest of the HUD |
| `matchmaker.gd` *(child of `Network`)* | Short room codes. On the server (`--matchmaker`) it keeps the list of codes in use, starts one headless room process per code (`--server --once`, ports from a range) and answers create/join; on a client it asks the server for a code and then joins the room's port. Where the server is: `--matchmaker-url=` or `assets/config/online.json` |
| `network_manager.gd` *(autoload: `Network`)* | Owns the WebSocket connection (`WebSocketMultiplayerPeer`), host/join/leave, the named roster (synced server → clients), the 5-player cap with a rejection reason, and the scene-level match RPCs (start match, arena-ready handshake, return to lobby), the room-leader rules, and dedicated-server mode (`--server`: no avatar of its own, resets when empty). Those RPCs live here because the autoload is the one node at the same path on every peer regardless of scene |
| `net_lobby.gd` | Online lobby: name + host-IP form, host/join, waiting room with the live roster, host-only Start. Lands straight back in the room after a match since the connection stays up |
| `net_arena.gd` | The online match (host-authoritative): waits for every client to report its arena loaded before spawning anyone (a spawn sent to a peer without the arena is lost, not queued), spawns players and bombs via `MultiplayerSpawner`s, runs the vision rule, Blackout darkness and bomb triggers/blasts, tracks eliminations/leavers, declares the winner, broadcasts status/announcements, and despawns cleanly before sending everyone back to the lobby |
| `net_player.gd` *(`NetPlayer`)* | Server-authoritative networked player: server simulates remote movement from received input, owns hit detection (its own position, not a client-supplied one; server-enforced fire cooldown) and the whole Gen state machine (ready → active → cooldown, with camouflage/shield/haunt/bomb state replicated); the owning client predicts its own movement locally (no reconciliation yet — corrections can snap). Mouse or touch-pad aim, tracers, name tag, per-player color, crate disguise, shield ring, haunt marker, Blackout glow light, dimmed death state |
| `gens.gd` *(`Gens`)* | The online Gen table — labels, durations, cooldowns, per-Gen numbers, availability — read by the lobby, the HUD and the server logic |
| `voice_chat.gd` *(autoload: `Voice`)* | Voice chat: mic capture → 8 kHz µ-law → server → team/FFA/dead-aware routing → per-speaker playback. `recipients_for()` is the single rule table; `ingest_pcm()` is the same path the mic uses, so it can be driven by tests |
| `net_pickups.gd` *(`NetPickups`)* / `net_pickup.gd` *(`NetPickup`)* | Everything on the arena floor: the host places ammo crates and medical stations from a fixed seed, runs pickup / healing / respawn rules and the drops a dead player leaves; a `MultiplayerSpawner` shows them to everyone, which only draw them (a station's progress ring is replicated) |
| `net_decoy.gd` *(`NetDecoy`)* | The online Decoy: host-simulated clone that paths through the maze (A* grid built in `net_arena.gd` from the Maze layout), hits on contact, takes damage from enemy shots, expires; clients just glide it to the replicated position |
| `radial_picker.gd` *(`RadialPicker`)* | Reusable pop-out picker: a hub button that fans its options into a ring (tweened, overlays neighbouring UI). Used for Gen selection in the online lobby |
| `net_bomb.gd` *(`NetBomb`)* | A placed Bomb Voyage bomb: static marker carrying owner + trigger mode; the arena decides when it blows |
| `arena_catalog.gd` *(`ArenaCatalog`)* | Every online arena as a text grid, plus the random pick (`pick()`, which avoids repeating the last one). `Network.map_id` holds the current one |
| `net_map.gd` *(`NetMap`)* | The online map for `Network.map_id`: parses the layout text (walls, cover, wrecks, barrels, decor, spawn markers), merges solids into the fewest rectangles with colliders and light occluders, exposes spawn positions, and shows the pre-baked picture of the map (falls back to painting it at runtime if that picture is missing) |
| `net_map_painter.gd` | Paints the ruins (ground, grime, damage, props) from a fixed seed. Used by the bake tool to make the shipped picture, and as a slow runtime fallback — painted at match start it froze the game for 8.5 s on an Intel HD 520 |
| `scripts/tools/bake_map.tscn` | Developer tool: renders each arena's picture once into `assets/maps/` — run it windowed whenever the layout changes |
| `walk_cycle.gd` *(`WalkCycle`)* | Procedural walk animation for the still character sprites — shoulder sway, step bob and squash, stepping boots, breathing, gun kick — driven by real movement so it plays identically for local, remote and Decoy characters |
| `story.gd` *(`Story`)* | Reads `assets/story/story.json` and hands out the game's words with fallbacks; the host picks so everyone sees the same line |
| `net_minimap.gd` | Corner minimap: layout always, players only if you're allowed to know where they are |
| `net_hud.gd` | Online HUD: HP, alive count, Gen state + contextual hint, status line, timed announcements, the touch controls (incl. Gen and detonate buttons), Blackout night-vision tint, and the end-of-match overlay |

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
- [x] On-screen virtual joystick for touch (movement)
- [x] Touch-drag aim pad + on-screen shoot button
- [x] Local split-screen Versus mode: per-player cameras, PvP damage, unique Gens, win/results screen
- [x] Local Versus Gens (original effects): Camouflage, Shield (placeholder), Decoy, Heavy Gunner, Blackout — the redesigned versions live in the online mode
- [x] Gen-selection lobby (FFA/Team toggle + per-player Gen picker) wired in from the main menu
- [x] Real WebSocket client-server networking (`Network` autoload, `NetPlayer`/`NetArena`) — server-authoritative movement + hit detection
- [x] First playable online match: host/join lobby with named roster and 5-player cap, arena-ready handshake, eliminations → winner → results → back to lobby, net HUD with touch controls — verified end-to-end across three separate processes (host + 2 clients)
- [x] `run.bat` — double-click to play, no Godot editor needed

### Not started
- [ ] Levels 2–5
- [ ] Boss enemy
- [ ] Gen balance pass — every number is a first guess until real matches happen
- [x] Limited player vision online (ring + forward cone + line of sight, firing reveals you) — first-pass numbers, client-side
- [x] Online Gens: Camouflage, Shield, Poltergeist, Blackout, Bomb Voyage — picked in the online lobby, server-authoritative, verified host + 2 clients
- [x] Online team mode: host toggles FFA/Teams, teams dealt at random and balanced (sizes within one; leader can Shuffle; late joiners fill the smaller side; start is blocked if lopsided), teammates always visible, no friendly fire, team spawns, last team standing wins — verified host + 2 clients
- [x] All six Gens online, including the Decoy port (clone + A* pathfinding on the Maze grid)
- [x] Online movement smoothing: your own avatar reconciles against the host (snap only on real drift, ease together once stopped), others' avatars glide to the replicated position; verified over loopback only — real-latency behaviour needs the real-build test
- [x] Laggy/dropped players stay in, dimmed: 3s of silence marks you lagging, a dropped connection leaves a dimmed killable avatar for a grace period, a deliberate Leave removes you at once
- [x] Fixed: the Online screen used to open on an empty room (hiding the Host/Join form) because Godot's default offline peer reports itself as a connected server — everything now asks `Network.has_peer()` instead
- [x] Dedicated server mode (`--server`, plus Linux x86_64/arm64 export presets and `export_server.bat`): headless host with no player of its own, room leader = longest-present player with host-validated Start/mode/Return, auto-reset when empty — verified with a server + 2 clients on one PC; not yet run on a real Linux server
- [x] Voice chat (team-only in team mode, open in free-for-all, dead→dead only, voice-activated, mute key/button, talking indicators) — the routing, codec, limiter and full send→server→receive→decode path are verified with a server + 3 clients using synthetic audio; **the real microphone, the browser's permission prompt, and how it actually sounds are untested** (no audio hardware here). Likely needs a noise-threshold tweak and possibly push-to-talk once tried with real mics
- [x] TLS (`wss://`) support on the server and in clients (`--tls-cert`/`--tls-key`, `wss://` join addresses, forced `wss://` from `https://` browser pages) — verified with a self-signed certificate; still untested with a real certificate/domain/browser
- [x] Room codes, two kinds: an 8-character checksummed encoding of a host's address (same Wi-Fi / direct), and **4-character matchmaker codes** — the host picks one, the matchmaker rejects a code already in use, starts a room for it and frees the code when the room empties. Verified on one PC with a real matchmaker process and separate client processes (create, join, taken code with a suggestion, missing code, bad characters, three simultaneous rooms, server-full, unreachable server, idle room closing itself, reusing a freed code, the lobby screens). **Not** yet run on a real server, over the internet, with TLS, or from a browser
- [x] Balanced random teams with Shuffle; the outnumbered team gets +40% health (`SMALL_TEAM_HP_BONUS`)
- [ ] A public room list (browse open rooms) — the matchmaker knows them, nothing shows them yet
- [ ] Confirming the earlier intermittent WebSocket disconnect is gone — it did not appear in any of this session's three-process runs, but still needs a check on real exported builds
- [x] Pop-out radial picker for Gen in the online lobby (placeholder styling)
- [ ] Gamepad aim (movement-direction fallback works, true analog aim doesn't exist)
- [ ] Input rebinding menu
- [x] Online sound effects (shots, hits, deaths, every Gen, bombs, footsteps, UI clicks, match start/end, wind + distant thuds, volume slider) — **wired and verified to trigger, but not listened to by me: how each one actually sounds is untested**; swapping a sound is a one-line change (see "Online sound")
- [x] Sound for solo and local versus (shot, hurt, death, pickups, power-ups, monster growl / stinger / footsteps / hit / death, bullet impacts, fireplace, wind, win / game over) from the same set via `Sfx.fill` — wired and verified to trigger, **not listened to**
- [ ] Music (decided: none during matches — it would mask footsteps and voices)
- [ ] Final art (the online map and players are real art now; everything else is placeholder shapes)
- [x] HTML5 / Windows export presets + one-click `export_windows.bat` / `export_web.bat`
- [ ] Itch.io page
- [ ] Playtesting pass

---

## Asset Credits

| Asset | Source | License |
|---|---|---|
| Dungeon tiles, characters, items (`assets/sprites/dungeon/`) | [Kenney — Scribble Dungeons](https://kenney.nl/assets/scribble-dungeons) | CC0 |
| Player characters (`assets/sprites/player/`) — Man Blue, Robot 1, Hitman 1, Man Brown, Soldier 1 | [Kenney — Top-down Shooter](https://kenney.nl/assets/top-down-shooter) | CC0 |
| Touch-control pad, nub, buttons and icons (`assets/sprites/ui/mobile/`) — Style A | [Kenney — Mobile Controls](https://kenney.nl/assets/mobile-controls) | CC0 |
| Placeholder sprites (everything not yet reskinned — enemy silhouettes, powerup icons, etc.; online players now use the Kenney characters above) | Built procedurally / flat shapes, no external asset | — |
| Sound effects (`assets/audio/sfx/`, built by `tools/build_sfx.py`) — samples from "100 CC0 SFX", "80 CC0 RPG SFX", "80 CC0 creature SFX #2" and "SFX 100 v2" | CC0 sound packs on [OpenGameArt](https://opengameart.org). The creature packs are confirmed as **rubberduck**'s ([80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx), [#2](https://opengameart.org/content/80-cc0-creture-sfx-2)); the other two are probably the same author (they sit in his collection) but I couldn't confirm it — check each pack's page and correct this line. The heartbeat and low drone are generated by the build script, not sampled | CC0 |
| Any other sound effects | [freesound.org](https://freesound.org) | Various (log each file) |
| Ambient music | TBD | TBD |

> **Rule:** Every asset used in Akira must be listed here with its license before the game ships. No exceptions.

---

## Status & Roadmap

The original plan was a 3-month, 5-level solo horror game shipping by September 30, 2026. That date has passed, and the scope has grown well beyond the original plan — first with local split-screen Versus, and now with a much bigger pivot toward a **web-based multiplayer arena shooter** (see [Next: Web Multiplayer Arena](#next-web-multiplayer-arena-active-design)). There's no fixed ship date; development is ongoing and scope is still actively being shaped.

**What actually exists today:** a fully playable Solo arena and a fully playable 2-player local Versus arena, both with real mechanics (not just placeholders) — flashlight/darkness, stealth detection, pathfinding, powerups, fireplaces, audio hooks throughout, and full mobile touch controls (movement, aim, shoot). Versus mode now has 5 of the 6 planned Gens implemented (Camouflage, Shield, Decoy, Heavy Gunner/Poltergeist, Blackout — some with reworked designs not yet coded, see [Gens](#gens--the-renamed-reworked-power-system-5-of-6-implemented)) and a working pre-match lobby to pick them. **What's missing** for those two modes: additional level content (2–5, boss), real art/sound, and export/ship logistics.

**Online play has its first playable version:** a real WebSocket client-server layer (`Network` autoload + `NetPlayer`/`NetArena`) with a host/join lobby, a named roster, a 5-player cap, a full match loop (spawn, eliminations, winner announced, results screen, back to the lobby for another round) and a HUD with touch controls — all verified end-to-end across three genuinely separate OS processes (a host and two clients), not just in-editor. It's deliberately a bare, lit, cover-free box so the loop could be proven solid before the design layers on. The intermittent disconnect seen in earlier prototype testing did not reappear in any of this session's runs, but it still needs confirming on real exported builds.

**The online game now has its design in it:** the maze arena with cover, the limited-vision rule, all six Gens (Camouflage, Shield, Poltergeist, Blackout, Bomb Voyage, Decoy), FFA/Team modes, smoothed movement, lag/disconnect handling, pop-out pickers and room codes, all running server-authoritatively and verified across three real processes. **What's next:** testing on real exported builds (the Phase 1 check for the old intermittent disconnect), real matchmaking (needs the hosted server), and then a proper balance pass on every Gen number once people have actually played. Open decisions are listed in that section (server hosting — Oracle Cloud Always Free recommended — and tuning).

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

### Changing the online map
Each arena is a text grid in **`scripts/net/arena_catalog.gd`** (`#` wall, `c` cover, `v` wreck, `B` barrel, `S` free-for-all spawn, `1`/`2` team spawns, `k`/`d`/`x` decoration, `_` darkness beyond the arena, which lets an arena be any shape). **To add an arena:** add its rows, list it in `MAPS`, and give it at least 5 `S` and 3 each of `1` and `2` (all floor connected, or someone can't reach someone). Its look is a **pre-rendered picture** in `assets/maps/baked_<number>.webp`, named after a fingerprint of the layout. After adding or editing an arena, run `godot --path . res://scripts/tools/bake_map.tscn` **windowed** (it needs a real renderer; takes a few seconds), (it bakes every arena that has no picture yet), then commit the new `.webp` files and their `.import`s. If you forget, the game still works — it paints the map itself at match start — but with a long freeze on weak graphics hardware, and it prints a warning.

### If a build shows black levels
Two causes were found and fixed, but know the symptom: an exported game showing **no floor or walls**. (1) An `@export` `PackedStringArray` declared with a `= []` initializer loses its saved value in an export — never declare map data that way (`maze.gd` and `net_map.gd` don't). (2) The exporter caches converted scenes in `.godot/exported/`, which can serve a stale copy after a script change; if a fix doesn't seem to reach your build, close the editor, delete that folder (it's regenerated), and export again.

### Building & testing online play
Export presets for **Windows Desktop** and **Web** are committed in `export_presets.cfg`. One-time setup: open the project in the editor once and go to **Editor → Manage Export Templates → Download and Install** (the engine's export templates aren't part of the repo).

1. Double-click **`export_windows.bat`** → `builds/windows/Akira.exe` (self-contained, no `.pck` beside it).
2. **Same PC:** run two copies. In one: Online → Host. In the other: Online → Host IP `127.0.0.1` → Join.
3. **Same Wi-Fi:** the host's room shows `Friends on your Wi-Fi join with: 192.168.x.x or code XXXX-XXXX` — the other machine types either into the Host IP / code box (a code is just that address in a short checksummed form; `ip:port` also works for a non-default port). If Windows pops a firewall prompt the first time you host, allow it.
4. **Web:** `export_web.bat` → `builds/web/`. A browser can't open it from the folder — serve it (`cd builds/web` then `python -m http.server 8000`, open `http://localhost:8000`). Browsers can only *join*; the host must be the desktop build (a browser page can't listen for connections). Over plain `http://` the game connects with `ws://`, which is fine on a LAN.
5. **Internet:** run the matchmaker somewhere reachable (below) and put its address in `assets/config/online.json` (or start the game with `--matchmaker-url=host:9040`); players then just pick and type 4-character codes. The old alternative is for the host to port-forward TCP 9050 and give friends their address.

### Running a dedicated server
- **The matchmaker (what the Oracle machine runs):** `godot --headless --path . -- --matchmaker` (options `--port=9040`, `--room-port-base=9100`, `--max-rooms=8`, plus `--tls-cert/--tls-key` which it hands to every room). Each room it opens is its own `--server --once` process (it quits when empty, or after `--idle-timeout=` seconds if nobody joins), so rooms are fully separate. Try it on one PC with `--matchmaker-url=127.0.0.1:9040` on the game.
- **A single fixed room (no matchmaker):** `godot --headless --path . -- --server` (optionally `--port=9051`). It prints `[server] ...` lines as people join, matches start and rooms reset. Then join it from game windows like any host (`127.0.0.1`).
- **For a Linux box (e.g. Oracle Cloud Always Free):** double-click **`export_server.bat`** (needs the export templates, as above) to build `builds/server/akira_server.x86_64` and `.arm64` — pick the one matching the server's CPU (Oracle's free ARM machines are arm64). Copy it over, then `chmod +x` it and run `./akira_server.x86_64 --headless -- --matchmaker`. Open TCP 9040 and the room ports 9100-9105 in the server's firewall *and* in the cloud provider's network rules.
- **TLS (`wss://`), for browsers and for privacy:** give the server a certificate with `--tls-cert=<fullchain.pem> --tls-key=<privkey.pem>` (a Let's Encrypt certificate for your domain works) and it speaks `wss://` instead of `ws://`. Players then join by typing `wss://yourdomain` (port 443 is assumed; `wss://yourdomain:9050` for another port) — or just `yourdomain:443`, since port 443 implies TLS. A browser build served from an `https://` page **always** uses `wss://` (browsers refuse plain `ws://` from a secure page), so for browser play the server needs a real domain and certificate. For local testing with a self-signed certificate, start a desktop client with `--tls-trust=<server.crt>` (dev only — it relaxes name checking). **Verified locally with a self-signed certificate** (plain `ws://` is refused by a TLS server, an untrusted certificate is refused, a trusted one connects and plays); **not yet tried** with a real domain, a Let's Encrypt certificate, or an actual browser.
- **Step-by-step deployment to Oracle Cloud:** see [`deploy/ORACLE_GUIDE.md`](deploy/ORACLE_GUIDE.md) — it comes with a ready-made service file (`deploy/akira-server.service`, which runs the matchmaker), a one-time setup script (`deploy/setup_server.sh`) and a certificate-renewal hook (`deploy/renew-hook.sh`). Untested on a real machine until someone follows it.
- The server has not been run on a real Linux machine yet — only as a headless process on Windows with two real clients.

The first real-build test to run is simply: host, join, play a round, play a second round from the same room. That's the check for the intermittent disconnect seen in early headless testing.

---

*Akira — built in Godot 4.7.x — Chief — 2026*
