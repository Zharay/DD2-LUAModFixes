![DD2 LUA Mod Fixes](./DD2.jpg)

# DD2 LUA Mod Fixes
A collection of Dragon's Dogma 2 REFramework LUA mods that I fixed. Use at your own risk.

## Fixed Mods 

### [Shut Up Pawns](https://www.nexusmods.com/dragonsdogma2/mods/248)
- Completely gutted the old ID system to use exact messages instead (IDs are no longer used in DD2)
- Fixed errors involving PopStyleColor() and TreePop()
- Fixed possible `nil` access values when it tries to obtain `app_MessageManager`
- It will now try to reobtain the `app_MessageManager` if it is never loaded
- Fixed presets always re-applying themselves when you had none selected

### [Hide Helmets Out of Combat](https://www.nexusmods.com/dragonsdogma2/mods/961)
- Now checks if we are in combat every 15 frames instead of every frame, reducing performance impact.
- Fixed equipment errors and updated to latest REFramework method calls

### [Mark Important NPCs](https://www.nexusmods.com/dragonsdogma2/mods/433)
- Fixed ImgGUI call errors
- Added new option to show an exclaimation (!) to mark important NPCs
- Added new config variables to customize its color and size
- Added new config variable to set how often the mod searches for important NPCs to reduce performance impact
- Added options to (properly) disable itself during cutscenes and while in menus

### [Carry It For Me](https://www.nexusmods.com/dragonsdogma2/mods/284)
- Fixed GetItem calls to use the updated signatures
- GetItemOption.EventType is now being used instead
- Fixed a bug pertaining to event items never being filtered correctly
- Fixed equipment not being passed to pawns
- Now uses a proper round-robin distribution, spreading out the load until everyone else is full

### [Better Better Item Desccription](https://www.nexusmods.com/dragonsdogma2/mods/338)
This mod broke after Dark Arisen but I was already making changes to it. I was getting sick and tired of this thing spamming my logs and how it'd just break when debugging other things. So I fixed it for my needs.

- Fixed it to work with Dark Arisn expansion
- Now initializes correctly and not only when a player loads a save game
- Logging is back to just being info logs instead of error logs (_NickCore for some reason defaults to error type logs)
- Fixed naming/cache name misspelling
- Cleaned up logging 

## Working but Optimized Mods
These are mods that are working but have issues that irked me to hell.

### [Clock](https://www.nexusmods.com/dragonsdogma2/mods/150)
This mod is technically working but by the brine does it eat up resources at high FPS. It accounts for 10% of the game's tick cycle alone! Now its more like 1%.

- Optimized the heck out of it.
- Got rid of seconds. It was never needed.
- We peg TimeManager every 0.5 second (4x per in-game minute) instead of every frame
- The display string is now cached. We only update once every in-game minute (2 seconds real world)
- Any changes to settings updates the cache immediately.
- Changing font size no longer requires a restart
- Added ability to disable the clock during cutscenes (tho what the game counts as cutscenes is spotty)
  - This check is done every 0.5 sec as it is costly otherwise
