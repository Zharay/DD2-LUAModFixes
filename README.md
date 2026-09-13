![DD2 LUA Mod Fixes](./DD2.jpg)

# DD2 LUA Mod Fixes
A collection of Dragon's Dogma 2 REFramework LUA mods that I fixed. Use at your own risk.

## Fixed Mods 

### [Shut Up Pawns](https://www.nexusmods.com/dragonsdogma2/mods/248)
- Fixed errors involving  PopStyleColor() and TreePop()
- Fixed possible `nil` access values when it tries to obtain `app_MessageManager`
- It will now try to reobtain the `app_MessageManager` if it is never loaded

### [Hide Helmets Out of Combat](https://www.nexusmods.com/dragonsdogma2/mods/961)
- Now checks if we are in combat every 15 frames instead of every frame, reducing performance impact.
- Fixed equipment errors and updated to latest REFramework method calls

### [Mark Important NPCs](https://www.nexusmods.com/dragonsdogma2/mods/433)
- Fixed ImgGUI call errors
- Added new option to show an exclaimation (!) to mark important NPCs
- Added new config variables to customize its color and size
- Added new config variable to set how often the mod searches for important NPCs to reduce performance impact

### [Carry It For Me](https://www.nexusmods.com/dragonsdogma2/mods/284)
- Fixed GetItem calls to use the updated signatures
- GetItemOption.EventType is now being used instead
- Fixed a bug pertaining to event items never being filtered correctly
- Fixed equipment not being passed to pawns