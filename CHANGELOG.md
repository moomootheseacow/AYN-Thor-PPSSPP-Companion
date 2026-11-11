# Changelog

## 0.1.0 (2026-11-11), the initial build

The first public version: PPSSPP v1.20.4 plus the Thor companion for Monster Hunter Freedom Unite (FUComplete,
`ULJM05500`).

- A live companion on the AYN Thor's bottom screen, running next to the game on the top screen.
- Monster Hunter Freedom Unite hunt HUD on the bottom screen: health and stamina, sharpness and weapon gauges,
  quest timer, area map, item bar, gunner ammo and coatings, status buffs with countdowns, Felyne plates, quest goals.
- Two layouts: Immersive (the default) and Custom, a grid you arrange yourself in the village (Blademaster and
  Gunner layouts kept apart).
- The game's own HUD can be hidden on the top screen, so it stays clean while the bottom screen shows everything.
- Minimize the bottom screen, with a floating button to bring it back.
- An in-app Logs screen, with a Copy button for bug reports.
- Experimental, work in progress: the Meowtfitter, a cat NPC in Pokke Village with his own lines, and per-piece
  armour looks (transmog). See the README for its current state.

## Development history (before 0.1.0)

Grouped by milestone, in the order they were built and tested on a Thor.

1. **Proof of concept.** PPSSPP builds for the Thor with a second window on the bottom screen.
2. **Bottom-screen drawing and touch.** GPU drawing on the bottom screen, touch input, a smooth 60 fps redraw only
   when something changes.
3. **Lua packages.** Each game gets its own package of Lua scripts that reads the running game's memory; the first is
   Monster Hunter Freedom Unite.
4. **The hunt HUD.** The top row (clock, health, stamina, sharpness, weapon gauges), the area map, the left column
   (Felyne plates, status buffs with live countdowns, the quest box), the item bar with item names and counts, gunner
   ammo and coatings, the Logs screen, and hiding the game's own HUD.
5. **Parity with the earlier HTML companion.** Everything the browser-based companion did, now built in.
6. **Polish.** Item icons, area maps, the item bar and ammo flows, long-play checks (hours of play without slowing down).
7. **Layouts and the MHFU look.**
   - Immersive and Custom layouts, an editor for Custom (place, resize and remove panels), panel sizes, Quick use
     panels that use an item, Blademaster and Gunner layouts.
   - The game's own red X on items that can't be used right now.
   - Gather spots on the map.
   - Minimize the bottom screen.
   - The whole bottom screen in a Monster Hunter-style menu frame.
   - The quest panel shows each goal, and a tap opens a quest card.
   - Hints and wording polish.
8. **The Meowtfitter and transmog (work in progress).**
   - A Melynx-style cat NPC who stands in Pokke Village and comes back after quests, save states and restarts.
   - His own greeting and goodbye in the game's text box.
   - Per-piece armour looks: pick a look for each armour piece, re-equip any piece at your item box, and your
     hunter wears the look while keeping the real armour's stats.
   - Purple-black Melynx fur, only on him.
   - Being worked on: he is not drawn yet (you can talk to him, but not see him), and looks only show after a
     re-equip.
