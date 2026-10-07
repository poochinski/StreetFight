# Dungeon Crawler — native Godot edition

## Combat refinement build — October 7, 2026

This copy starts from the supplied 3D city version, using its original Knight, Rogue and Mage. The experimental modular characters and dressing room are set aside and are not loaded here. Double-click **Play This Folder.bat** to play this build.

- Melee has a quick opening cut, a returning cut and a heavier overhead finisher. Damage, the imported character pose and blade trails use the same simulation timeline. Weapon attack speed scales contact and recovery together.
- The old free-floating slash graphic is replaced by a short 3D ribbon sampled from the blade's actual path. The ribbon is resampled between frames so it remains curved at lower frame rates.
- Attacking while moving keeps a running leg cycle instead of sliding with frozen feet. Dodge interrupts sword windups and unreleased gunshots/spells. A held mouse attack follows the clicked enemy after knockback; WASD overrides that pursuit.
- Hit pauses are shorter (12 ms on ordinary melee contact; 35 ms on the finisher), hold the character animation too, and consume only their actual duration rather than discarding a whole frame. Enemy animation advances on the simulation clock as well.
- Guns and spells have a brief visible release phase, matching their projectile timing. The Gunslinger holds a compact revolver with a muzzle pulse; the Mage has a forked crystal staff. The eight existing melee weapon types now produce different equipped 3D shapes, including their item colors. Inventory portraits show the equipped weapon.
- Melee reach is closer to the visible weapon. Ground effects project onto the actual 3D floor. Barrage's first impact lands at the targeted point before the remaining impacts scatter.

Controls remain click/hold to move or attack, Shift-click to attack in place, WASD for optional movement, Space to dodge, right-click/1–4 for skills, and R to heal. Sound remains controlled by the speaker button.

Validation: existing gameplay checks pass, plus focused checks for contact at 0.8×/1×/2.5× attack speed, single-hit enforcement, melee/ranged cancellation, frozen contact pose, firing direction and held-target pursuit. A three-second held-combo test produced nine attacks at each of 15/30/60/144 FPS. A short warmed-up city rendering sample measured about 60 FPS on this computer's Intel Iris Xe; this is not a worst-case performance guarantee. Contact, finisher, dodge and firing screenshots are in `previews/combat-polish/`.

This build saves separately under `%APPDATA%/Godot/app_userdata/Dungeon Crawler Combat/`. Earlier game copies and saves remain available. The older general feature notes below describe the base game; the combat notes above supersede their attack-animation and hero-weapon descriptions.

This is a **native Godot 4 / GDScript action RPG** set in a ruined, post-apocalyptic 1980s city, with an interface styled as dungeon stone crossed with an 80s vaporwave sunset. The world is rendered in 3D (animated 3D heroes and skeleton enemies, lit 3D streets and buildings) with the HUD, loot and effects drawn over it in 2D. It runs in a desktop window without a browser, web server, web view, or network connection.

## Open and play

- Double-click **Play This Folder.bat** to play the game in this folder.
- Double-click **Edit This Folder.bat** to open this folder in the Godot editor.
- Or import **project.godot** in the Godot Project Manager, then press **F5**.

The .bat launchers always open the folder they sit in and use the Godot 4.7.2 installation in Downloads. The older .lnk shortcuts point at a different copy of the game and should not be used. If Godot is moved, import `project.godot` from its new installation. A separately exported Windows executable is not included; the native game currently runs through the installed Godot engine.

## Controls

| Input | Action |
| --- | --- |
| Left click ground / hold | Walk there (around walls); hold to keep following the cursor |
| Left click enemy / hold | Attack it, running over first if it is out of reach |
| Shift + left click | Attack in place |
| Right click or 1 | First class skill |
| 2, 3, 4 | The other class skills, once learned |
| Click a loot name | Walk to the item and pick it up |
| WASD / arrows | Move in screen directions (optional) |
| J / hold | Chain attacks, aiming at a nearby enemy |
| Space | Dodge immediately, cancelling the current attack; brief invulnerability |
| R | Healing potion |
| E | Open a footlocker / take the subway down |
| C | Character page (stats and stat points) |
| I or B | Equipment and bag |
| M | Minimap |
| Escape | Close the pages / pause / resume |

On the equipment page: click an item to pick it up and click a slot to put it down or swap; right-click to equip or unequip; Shift-click a bag item to salvage it for gold; click the world while holding an item to drop it. To socket a gem, pick it up and click an item with an empty socket. On the character page, + spends one stat point and Shift + spends five.

The mouse works like Diablo or Torchlight: click to move and click enemies to attack; WASD also moves. Heavy hits freeze the action for a few hundredths of a second so they land with weight. Sound starts muted, matching the browser version. Click the speaker button to enable synthesized combat, healing, loot, and level-up effects.

Movement now accelerates quickly, stops promptly, slides along walls, and travels at the same visible speed horizontally, vertically, and diagonally. The camera follows smoothly. The hero has a walking gait and animated sword swings. Clicking an enemy's visible body assists aim, and a click near the end of attack recovery queues the next strike. Hold attack for two quick cuts and a stronger third strike. Attacks remain usable while moving. Dodge can cancel a swing immediately and recovers in 1.2 seconds. Hits briefly stagger and push enemies back; attacks cannot connect through walls.

Enemies notice the hero only with a clear line of sight, alert nearby allies, and walk around walls to reach the hero. Every enemy telegraphs its attack: imps and brutes flush red and mark their reach on the floor, casters charge their staff, and the Ash Warden shows its slam ring. Step out of reach or dodge before the wind-up ends. Hitting an imp or caster interrupts its wind-up; brutes and the Warden power through. Ember Nova and gold pickups no longer pass through walls, enemies no longer stand inside the hero, and melee reaches the edge of large enemies' bodies.

## Sound and music

Everything you hear is synthesized, in an 80s analog synth style. Sound is on when the game starts; the speaker button turns effects and music off and on together.

- **Effects** are built in code from two slightly detuned oscillators, a sub-bass, a noise click on hits and a filter that closes as the note fades. Swings and impacts are punchy bass hits, menus and footsteps are soft square plucks, and loot, level ups and magic are bright FM bells. A short reverb puts them in the street.
- **Music:** a 100 BPM synthwave loop on the city floors (A minor, gated snare, saw bass, arpeggio and lead) and a faster, darker 124 BPM boss track on the final floor.
- The tracks are rendered by `tools/synthwave.py` (Python with numpy) into `assets/audio/`. Change a chord, melody or tempo there and run `python tools/synthwave.py` to make new ones.

## Classes

A new game starts on the class screen. Each class has its own starting attributes, basic attack and four skills, learned at levels 1, 2, 4 and 6. Leveling is slower than before: about level 3 by the end of the first floor and level 6 near the Warden.

- **Street Samurai** (melee, Strength): Slash combo; Ember Nova, Dash Strike (lunge through foes), Whirlwind (spin while moving), Ground Slam (heavy area hit that stuns).
- **Gunslinger** (ranged, Dexterity): Revolver Shot; Scattershot (cone of pellets), Frag Grenade (lobbed at the cursor), Fan the Hammer (six quick shots), Neon Barrage (rain of tracer fire).
- **Synth Mage** (caster, Focus): Laser Bolt (pierces one foe); Arc Lightning (jumps between foes), Frost Grid (chilling field), Ember Nova, Meteor (delayed heavy blast). Spells scale with Focus.

## Interface

The screen follows a classic action RPG layout:

- **Bottom:** a health orb (left) and a mana orb (right) with moving liquid, the hotbar between them (basic attack, four class skills, Dodge, Potions) with key labels, cooldown sweeps, mana costs and the level each locked skill is learned at, and the experience bar. Hover a hotbar slot for its details.
- **Top left:** a portrait with level badge, health and mana bars, and buttons for the character page, equipment and minimap. A green ! appears when stat points are waiting.
- **Top right:** the floor name, a round minimap in the isometric view (streets, sidewalks, plazas and shop floors, the hero's facing, the subway entrance, nearby enemies, footlockers and loot by rarity color) and the active quest.
- **Top center:** the name and health of the enemy under the cursor, or the Ash Warden's boss bar.
- **Messages:** a pickup feed in the lower left, notices, the E prompt, and a large LEVEL UP! banner.
- **Character page (C):** Strength, Dexterity, Focus and Vitality with what each drives, + buttons for stat points, and a full list of combat details. Hover a stat for an explanation.
- **Equipment page (I):** the hero on a sunset stage between nine equipment slots (helmet, chest, gloves, belt, amulet, two rings, boots, weapon), a 40-slot bag, gold and potions, and a Sort button.
- **Tooltips:** item name in its rarity color, type and item level, damage per second, damage and attack speed or armor, affixes, sockets and gems, flavor text, level requirement and sell price, and an "If equipped" list of exactly how your stats would change. The equipped item it would replace is shown beside it.

## Elite packs, health bars and knockback

- **Champion packs** (blue): every member is tougher and shares one or two traits.
- **Rare packs** (gold): a named leader such as "Voltjaw the Hungry" with two or three traits, plus tougher minions. Rare leaders always drop a Rare or better item.
- **Traits:** Turbo (much faster), Molten (sets you on fire, and explodes when it dies: step out of the red ring), Vampiric (heals when it hits you), Chrome Plated (takes 40% less damage), Overcharged (hitting it can arc lightning back at you), Juggernaut (extra health, no knockback or stagger).
- Elites glow in their colour with a ring of light at their feet. Their name and traits float above them and show on the target bar at the top of the screen.
- **Health bars** float over every enemy that is hurt or fighting.
- **Knockback:** the combo finisher, Ember Nova, Ground Slam, Dash Strike, grenades and meteors shove enemies back and break light enemies' wind-ups. Brutes resist, elites resist more, and the boss and Juggernauts don't budge.
- Elite traits and knockback live in `scripts/elites.gd`.

## Loot and items

- **Five tiers:** Common (white), Uncommon (green), Rare (blue), Epic (purple) and Legendary (gold). The color marks the item everywhere: name plate, slot frame, tooltip and the beam of light over it on the ground.
- **On the ground:** items fly out of enemies and chests and land under a beam of light that grows taller and brighter with rarity; Epic and Legendary items add a turning ring and rising sparks. Every drop has a readable name plate, and plates stack so they never overlap. A green arrow on a plate marks an upgrade and a red arrow a downgrade. Hover a plate for the full tooltip and comparison; click it to walk over and pick it up. Walking over loot also picks it up, and items you drop yourself stay put.
- **Gear:** eight weapon types (short sword, cleaver, leafblade, saber, greatsword, axe, mace, katana), each with its own damage range and attack speed, plus helmets, chest armor, gloves, boots, belts, rings and amulets. Item level sets the power and the level needed to equip it.
- **Armor bases:** 50 of them (11 helmets, 12 chest pieces, 9 gloves, 10 boots, 8 belts), from Hockey Mask and Varsity Jacket to Tire-Tread O-Yoroi and Neon Trench. Better bases only drop from their item level on, and each has a built-in stat that grows with item level, shown above the affixes. Many bases favor one class: that class gets 15% more base armor from them, and the tooltip shows "Favored: <class>" in the class color. Items from older checkpoints keep their old base names and still load.
- **Affixes:** stats, health, armor, fire, ice, shock and poison damage, attack speed, critical chance and damage, gold found, health per kill, mana regeneration, nova damage and movement speed. Names come from the affixes (for example "Keen Katana of Static"); Epic items get two-word names and Legendary items are named uniques with flavor text.
- **Elements:** fire burns over time, poison sickens over time, ice chills and halves enemy speed, and shock can arc to a nearby enemy. A weapon's glow, swing trail and sparks take the color of its strongest element.
- **Gems:** Ruby, Sapphire, Emerald, Amethyst and Topaz in Chipped, Polished and Radiant grades. Each gives one bonus in a weapon and another in armor or jewelry.
- **Stats:** each level gives 5 stat points and 20 health. Strength raises weapon and critical damage, Dexterity raises critical and evade chance, Focus raises Ember Nova damage and mana, and Vitality raises health. Armor reduces damage taken. Ember Nova costs 25 mana.
- **What you wear is what you see:** in 3D, every equipped armor piece is built onto the hero's skeleton from simple shapes (`scripts/gear_models.gd`), and the character page portrait shows it too. Rarity adds trim, studs and glow (Epic pulses, Legendary also casts light), and the item's tier tints the metal. With nothing in a slot the hero wears plain class-colored clothes, and a Coif puts the Rogue's hood back on the Gunslinger. In the 2D view helmets, body armor colors, gloves, boots, belt and the weapon are drawn on the hero.
- **Gear gallery:** `godot --path . --rendering-driver opengl3 -- --gear-gallery` renders every armor base at every rarity, a contact sheet per slot and full sets worn by each class into `previews/gear/` (add `--only=helmet|chest|gloves|boots|belt|worn` for one part).

## 3D view

- `scripts/world3d.gd` builds the level in 3D from the same generated map: streets, sidewalks, shop floors, buildings with lit storefronts and windows, neon signs with real light, street markings, props and the subway entrance. A night environment adds moonlight shadows, fog and glow. The camera looks down the same diagonal as the original 2D view, so movement keys and click-to-move behave the same.
- `scripts/models.gd` places the 3D models and picks their animations from the game state: idle, run, combo attacks, shooting, spellcasting, whirlwind, dodge, hit reactions and deaths. Enemy attacks are timed so the blow lands when the wind-up ends.
- Classes: the Street Samurai is the Knight with a greatsword, the Gunslinger the Rogue with a crossbow (the hood is now the Coif look, so other helmets can replace it), and the Synth Mage the Mage with a staff. Enemies: imps are skeleton minions with blades, brutes skeleton warriors with axe and shield, casters skeleton mages, and the Ash Warden a giant skeleton warrior with burning eyes.
- City props (cars, streetlights, traffic lights, hydrants, dumpsters, benches, crates, trash, rooftop water towers) are KayKit models; the rest are built from simple shapes.
- 3D models are by Kay Lousberg (KayKit), CC0 public domain; see `assets/models/CREDITS.txt`.
- Run with `-- --2d` to use the original 2D art instead. The smoke test always runs on the 2D path.

## 2D art (the --2d path)

The world is drawn 1.4× closer than the HUD so characters read clearly.

- **Hero:** the Wayfarer with pauldrons, tabard and cloak; equipped gear changes the head, plate, trim, cloak, hands and boots. The walk cycle has a knee-bending stride, arm swing, a trailing cloak and plume, and idle breathing. The hero shows a back view when facing away, and tumbles during a dodge roll.
- **Weapons:** every weapon type has its own shape: the arming sword, the broad cleaver, the leaf-shaped blade, the curved saber, the rune-lit greatsword, the axe, the spiked mace and the katana. Blades brighten with item level, Epic blades darken and Legendary blades turn gold. Swing trails and hit sparks take the weapon's color.
- **Enemies:** imps are horned, tailed and clawed and skitter on digitigrade legs. Brutes are tusked, wear an iron pauldron and raise a spiked club overhead when winding up. Casters are hooded and robed, with a staff orb that charges and a rune circle at their feet. The Ash Warden is a horned, armored giant with glowing lava seams, an ember core, and a hammer it lifts before the slam.
- **Effects:** impact flashes and sparks, shockwaves with scorched ground for Ember Nova and the Warden's slam, dodge afterimages, enemies collapsing into ash, a level-up light pillar, a red flash when the hero is hurt, and glowing trails on caster bolts.

## The city

Every floor is a newly generated district of a city that burned in 1989.

- **Layout:** a grid of wide streets (six to eight cells across, with sidewalks and curbs) and crossings. Some street segments are closed off each time, so blocks merge and every floor has its own shape and loops. Between the streets, blocks become solid buildings, burned-out shops you can walk into, plazas, parking lots, survivor camps or collapsed lots.
- **Walk-in shops:** arcades (cabinets with glowing screens on 80s carpet), diners (checkered floor, counter and stools, booths, a jukebox), video stores (shelves of tapes), laundromats (rows of washers) and warehouses (columns, crates and drums). Each has doors or a smashed storefront onto its streets, and some are split by an inner wall.
- **Outdoors:** parks with palms and a dry fountain, parking lots with painted bays and wrecks, camps with tents, mattresses, a campfire and a pile of flickering TVs, and collapsed lots with rubble mounds, broken brick walls and scorch marks.
- **Streets:** streetlights (some flickering), blinking traffic lights, abandoned and burned-out cars, concrete barriers and sandbag barricades with a way through, dumpsters, payphones, hydrants, newspaper boxes, cones, tires, garbage bags, litter, manholes (steaming in the rain), potholes, puddles, oil stains, lane markings and zebra crossings.
- **Scale and placement:** the hero is a person-sized figure: a shop's ground floor is about one and a half times their height, a door a bit taller than them, and a full building front two storeys. Everything is placed by rule, not at random: streetlights stand at the curb at even spacing and clear of the corners, traffic lights sit on opposite corners of a crossing, cars park nose to tail in the curb lane, dumpsters sit against walls with bags beside them, hydrants stand at the curb near block ends, and barricades go near the end of a street. Inside, machines and cabinets line the walls in rows with back-to-back islands in bigger rooms, the footlocker is tucked into a corner, and nothing sits against a wall on the camera's side, where it would look stuck on top of the wall. Props cast shadows the shape of their footprint, and puddles, stains and scorch marks are irregular patches, only out on the street.
- **Buildings:** two-storey fronts in brick, pastel stucco, concrete, glass and warehouse metal, with shop windows (some lit, some smashed), doors, roll-up shutters, striped awnings, lit, dark, broken and boarded windows, fire escapes, AC units, vines, and rooftop antennas and water tanks. Neon signs (ARCADE, VIDEO, MOTEL, DINER...) and vertical blade signs light the street below; some flicker or have a dead letter. Walls in front of open ground are cut down so they never hide the hero or an enemy.
- **The way down:** a subway entrance with railings, globe lamps and a SUBWAY sign, in the outdoor spot farthest from the start. Floor 3 opens a whole block into Sunset Plaza, a vaporwave sun laid in tiles and ringed by neon palms and fire barrels, where the Ash Warden waits.
- **Floors:**
  - Neon Row: rain, wet asphalt and pink and cyan neon.
  - The Burnt Mile: falling ash and embers, scorched streets, burning wrecks and dead palms.
  - Sunset Plaza: a dusk-purple mall district with pink lane lines and neon palms.
- **Lighting:** the dark closes in away from the hero, while streetlights, fires, neon signs, arcade screens and TVs throw colored pools of light.

Three randomly generated city floors, melee and ranged enemies, a boss with a telegraphed area attack, chests, breakable crates, gold, potions, five tiers of loot, gems, stat points, leveling, map discovery, pause, victory/defeat, and local floor checkpoints.

Heading down into the subway toward the next street heals 35% of maximum health and buys potions up to three for 15 gold each. Shift-click spare items in the bag to salvage them for gold. Defeat the Ash Warden in Sunset Plaza to win. Move outside its red attack ring or dodge when the slam lands.

The game saves each time you enter a place, to Godot's local user-data folder (`%APPDATA%/Godot/app_userdata/Dungeon Crawler/descent.json`). Continue puts you back where you entered, with your stats, stat points, equipment, bag, stash, side quests and the places you have found. Checkpoints from before the city zones load on their floor's street. Defeat and victory remove the checkpoint.

## Places in the city

The streets are the spine of the city: Neon Row, The Burnt Mile and Sunset Plaza. Side areas open off them through ordinary doorways, and the subway runs between them. Press **E** at a doorway, gate or stairway to go through. You can go back to any place you have been; it is built the same way every visit (from the run's seed), but its enemies come back.

- **Subway stations:** the subway entrance on each street leads down to a station: platforms either side of the tracks, tiled pillars, a stalled train, a token booth and a maintenance room. The stairs at the far end come up at the start of the next street; the stairs at the start of a street go back down.
- **Starlight Mall** (Neon Row, through the STARLIGHT MALL doors): a long concourse with planters and benches, and burned-out shops off it: arcades, video stores, laundromats, a diner and clothes boutiques with racks and mannequins. The mall rats hold the shops.
- **The food court** (inside the mall) is the town hub and a safe zone: no enemies come in, nobody can attack or be hurt there, and enemies chase you again as soon as you step out.
  - **Ray's Pawn** sells twelve pieces of gear, restocked every visit. Click to buy. Right-click a bag item, or drop it on the shop, to sell it.
  - **Juice Bar** sells health potions.
  - **Stash:** forty slots that stay with you for the whole run. Right-click moves items between the bag and the stash.
  - **Transit map:** fast travel to any street, station or side area you have already visited, and back to the food court. There is a transit map on each station platform too.
- **Liberty Park** (Neon Row, through the iron gate): a grimy 80s city park inside a ring of buildings. A paved promenade, a dirt loop path, the fountain plaza, a pond, a homeless camp, a playground and the bandshell, with trees everywhere.
- **Warehouse 13** (The Burnt Mile): the dungeon. Storage halls of columns, crates and drums, offices with desks and TVs, loading bays stacked with pallets and a cold room, joined by corridors.
- **Side quests:** each side area has a gang boss to put down: Static Sally at the park's bandshell (Turf War), Joystick Joe in the mall (Mall Rats) and The Foreman in the warehouse (Graveyard Shift). You take the quest when you walk in, and it is done when the boss falls, for an Epic or Legendary item and a bag of gold. A finished boss stays gone.
- The quest tracker shows the main quest, the side quest of the place you are in, and how many others are still open. The minimap marks doorways in pink, stairs in cyan and vendors in green.

## Project structure

- `project.godot`: project settings and native startup scene.
- `scenes/main.tscn`: main scene.
- `scripts/ember_depths.gd`: game state, input, the hero, combat and the simulation loop.
- `scripts/data.gd`: names, colors and per-enemy tuning (health, speed, damage, wind-up, reach, size).
- `scripts/dungeon_generator.gd`: the city layout (streets, blocks, shops, plazas), set dressing, neon sign placement, spawns and the enemy pathfinding grid.
- `scripts/enemy_ai.gd`: enemy awareness, pathfinding, telegraphed attacks and body spacing.
- `scripts/world3d.gd`: the 3D view: camera, lighting, the city meshes, signs, props, and projection between the map, the 3D scene and the screen.
- `scripts/models.gd`: 3D heroes, enemies and props, and their animations.
- `scripts/gear_models.gd`: builds equipped armor onto the 3D heroes from primitive meshes, with rarity trim, tier tints and cached meshes and materials.
- `assets/models/`: KayKit 3D models (characters, weapons, city props) and their credits.
- `scripts/world_view.gd`: draw order of the city, characters and effects, the weather and the darkness around the hero.
- `scripts/city_art.gd`: streets, sidewalks and shop floors, building fronts, neon signs, ground markings, light pools, every prop and the subway entrance.
- `scripts/city_layer.gd`: cached pieces of the city drawing, redrawn only when part of the map is revealed.
- `scripts/characters.gd`: hero, weapon and enemy art, walk cycles and attack poses.
- `scripts/effects.gd`: sparks, shockwaves, scorch marks, afterimages, deaths and level-up light.
- `scripts/items.gd`: item bases, rarity tiers, affixes, gems, names, hero stats and item comparison.
- `scripts/inventory.gd`: bag and equipment rules (equip, swap, socket, salvage, sort, drop).
- `scripts/hud_view.gd` and `scripts/hud_canvas.gd`: the HUD, title screen and menus, drawn on a screen-space layer above the zoomed world.
- `scripts/inventory_view.gd`: the character page, equipment and bag page, and item tooltips.
- `scripts/loot_view.gd`: loot beams on the ground and loot name plates.
- `scripts/item_art.gd`: item icons.
- `scripts/ui_kit.gd`: the interface look: panels, chrome lettering, neon buttons, slots, bars, suns and grids.
- `scripts/painter.gd`: shared drawing primitives, fonts and gradients.
- `scripts/zones.gd`: the places in the city, how they connect, fast-travel destinations and side quests.
- `scripts/zone_generator.gd`: the mall and food court, the park, the warehouse and the subway stations.
- `scripts/synth.gd`: synthesized sound effects, the audio buses and music playback.
- `assets/audio/`: the synthwave music loops.
- `tools/synthwave.py`: renders the music loops.
- `scripts/save_game.gd`: floor checkpoints.
- `scripts/tests/`: the smoke test, the preview renderer and the gear gallery (`gear_gallery.gd`).
- `archive/3d-prototype/`: the earlier 3D experiment, kept for reference. Godot ignores this folder.
- `icon.svg`: original project icon.
- `previews/`: rendered previews of the actual native game, including title, gameplay, the subway entrance, each floor, a zoomed-out view of each district (district1-3), loot, the character and equipment pages, tooltips, combat and pause.

This is still a prototype. A town hub, vendors, pets, skill trees, campaign quests, multiplayer, and a standalone exported build are not included yet. The interface uses the Bahnschrift and Georgia fonts that come with Windows, with local fallbacks.

## Validation

The project was tested with Godot 4.7.2. Native checks cover 60 generated city floors (every street at least six cells wide, every cell reachable, props never walling anything off, an open subway entrance, no enemies at the start, neon signs on the buildings), equal speed in eight directions, motion at 15/30/60/144 FPS, stopping and reversing, swept wall collision, wall sliding, body-target aiming, swing timing, queued combos, finisher damage, held attacks, single hits per swing, dodge cancellation, obstruction checks, enemy line of sight, pathfinding, wind-ups and spacing, walled Ember Nova and its mana cost, every class's basic attack and four skills (locked until their level, then hitting and going on cooldown), click-to-move around walls and click-to-chase, the leveling pace, progression and stat points, item generation, the 50 armor bases (drop levels, built-in stats, favored armor and tooltip, a 3D look at every rarity, older checkpoint items), equipping, swapping, sockets, salvage, sorting, dropping and picking up loot, elemental effects, saves, menus, synthesized sound waveforms, that both music tracks load and loop, and the city zones (every side area and station fully reachable with reachable exits and enemies, quest bosses, street doorways, the same place on every visit, arriving back outside the doorway you left by, the food court's safety, the Pawn Shop, Juice Bar, stash and transit map, side quests, and saving and continuing in a side area, including older checkpoints):

`godot --headless --path . -- --smoke-test`

Smoke tests use a separate test checkpoint and do not overwrite normal game progress.

`godot --path . -- --render-check` renders previews from the actual game in 3D, checks that clicks map back to the right ground point, and exits. It also uses a separate test checkpoint.
