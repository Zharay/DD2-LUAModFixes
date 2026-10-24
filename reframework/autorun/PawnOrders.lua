-- PawnOrders: order a pawn of the party (main pawn, hired pawn 1 or 2) to use one specific equipped skill
-- (buffs on the player, attacks on an enemy).
-- Pad: the player picks the shortcut set in the REFramework menu "Specific Pawn Orders": hold LT +
-- X/Y/B/A/A+X/B+Y, or B + D-pad and LT; each position orders the skill bound to it for the target pawn.
-- Hold LT + D-pad: Left / Up / Right pick the target pawn (main / hired 1 / hired 2), Down cancels its action.
-- Optional "hold LT" mode (menu): the orders open only after LT is held for a set time (0.25 s default, 0-1 s);
-- a shorter press reaches the game as a normal LT tap (sheathe / draw).
-- RB takes priority over LT orders until LT is released; release RB, then press LT again to give orders.
-- Keyboard: one key per position, picked in the same menu (all vocations); the game still sees the key.
-- Action mechanism adapted from "Additional Pawn Commands" by its Nexus author
-- (https://www.nexusmods.com/dragonsdogma2/mods/1020).
-- Skill enum / name / slot calls follow "ThePawnController"
-- (https://www.nexusmods.com/dragonsdogma2/mods/1223).
-- Input filtering on app.UserInput.update follows dd2gether's realtime_menus.lua.

local VERSION = "0.9.43" -- RB/LT arbitration and HUD writes in the native GUI update hooks
-- DEV = test build: full log kept across runs, skill table file, F9-F10 test aids.
-- Release (false): short log recreated each session, no toggles.
local DEV = false
local LOG_FILE = "PawnOrders.log" -- relative = reframework/data/
local CONFIG_FILE = "PawnOrders.json"
local SKILLDB_FILE = "PawnOrders_skills.txt"

local INTERRUPT_WINDOW = 4.0 -- same order again within this many seconds = interrupt now
local AIM = {} -- AI-decides orders (F8): helpers kept in one table (200-local limit)
-- Skill action not seen this long after the order = order dropped. AI-decides orders: the AI may first walk to its
-- target. Our way: test 36 took the old 1.5 s limit out (test 35: 6 orders dropped at 1.5 s while Vortex started
-- at +1.23 s and RockBeat at +1.46 s); hits, cancel, a new order and the out-of-stamina layer still end it sooner.
AIM.START_MAX = 8.0
-- Upper-body cancels and the AI's own next action are blocked from the order until the Cast layer
-- (test 6: HolyGlare charges 4-9 s in Prepare; a 3 s cap let DefaultCancelAction cut it 4 times).
-- Over after ORDER_MAX at most.
-- Test 7: HolyGlare reached Ready at +8.9/+9.4 s and the 12 s cap let the AI cancel it 2.6-3.1 s later
-- (test 6: Cast 0.84 s after Ready). Now the cap is long and a charged skill gets READY_MAX to cast.
local ORDER_MAX = 20.0       -- order counts as over after this long
-- A Cast layer still on after this long = stuck (test 18: with the AI off Job03_CastDivineShot stayed 10 s twice,
-- pawn frozen; normal Cast ~2.2 s then the pack's DrawWeapon step; Firestorm's Cast runs ~4.4 s). The AI is back
-- on at Cast again, so this is only a safety net. Order over, AI back on.
local CAST_STUCK = 8.0
-- release_ai skills: AI back on at Ready so the cast command runs its own charge hold (_Min/_MaxReleaseWaitTimer
-- 2-3 s); with the AI off the pawn always releases 1.00 s after Ready (tests 13-18) = not fully charged (user,
-- Virtuous Bolt). Tests 7/12: the Louvor held 2.6-3.3 s in Ready with the AI on and my caps cut it just before 3 s.
local READY_MAX_AI = 4.5
-- Release: with the AI off the pawn casts on its own 0.83-1.0 s after Ready (test 13). Editing the command's
-- _Min/_MaxReleaseWaitTimer (v0.12-v0.13) changed nothing and was removed. A 2nd send restarts the charge (test 11).
-- in Ready this long without a Cast = order over
local READY_MAX = 3.3
-- AI off during the charge (user, after test 9: AI on lost 4 Firestorm starts to its own actions). Charge =
-- time to Ready (test 9: HolyGlare Ready +8.5 s after start, boon +2.8 s). Least idle time:
--   AI stays off until our Cast (test 12: AI back on in Ready = 2 of 3 Louvors never cast, the AI tried to
--   sheathe; test 11: AI back on mid-charge = Louvor never reached Ready). The pack's own strafe moves her.
--   no Ready by charge / SLOWEST_RATE + CHARGE_SLACK          -> order over
-- (user: not the exact time, a little slack so the cast can finish and she does not stand for nothing)
local CHARGE_SLACK = 0.3
local SLOWEST_RATE = 0.65     -- _AddRateForPreparingSpellWhileRunning (F16): slowest charge while moving
local QUEUE_TIMEOUT = 2.0    -- queued behind an AI action that is not a skill: fires anyway after this long
local QUEUE_BEHIND_OURS = 6.0 -- queued behind our own running skill: fires anyway after this long
local SCAN_PERIOD = 0.5      -- vocation / skills re-read period
local PAD_LOG_CAP = 150      -- max [PAD] lines per run
local PACK_ROOT = "AppSystem\\ai\\actioninterface\\actinterpackdata\\"

-- HumanCustomSkillID -> order.
-- status = player status the order gives (F6, logged only); keys = action layer name parts (lower case)
-- that show the skill is running (test 4 layers: Job03_PrepareFireBoon, JobMagicUser_CastFirestorm,
-- Job03_PrepareHolyGlare then JobMagicUser_StartMagicBarrier); keys of the skills new in v0.5 are guesses,
-- a new Job layer counts as the start too and its name is logged ([START] generic);
-- target = "player" (buffs, decision 5) or "enemy" (decision 15). Decision 17: every Mage skill with a pack.
-- charge = base charge time in s, no buffs: SecPrepare of the skill in Job03Parameter.user.3 (PowerShot uses
-- _PrepareTime); the 3 boons share BoonParameter.SecPrepare. Read by diffing the file against the
-- "Casting Speed Multipliers" mod. No charge (Reraise, DivineShot) = old caps ORDER_MAX / READY_MAX.
local function mage(file) return PACK_ROOT .. "job03_mage\\" .. file .. ".user" end
local ORDERS = {
    [29]  = { name = "FireBoon",    target = "player", charge = 2.5, status = 15, keys = { "fireboon" },    pack = mage("job03_fireboon") },
    [30]  = { name = "IceBoon",     target = "player", charge = 2.5, status = 16, keys = { "iceboon" },     pack = mage("job03_iceboon") },
    [31]  = { name = "ThunderBoon", target = "player", charge = 2.5, status = 17, keys = { "thunderboon" }, pack = mage("job03_thunderboon") },
    [37]  = { name = "HolyGlare",   target = "player", charge = 10.0, keys = { "holyglare", "magicbarrier" }, pack = mage("job03_holyglare") },
    [28]  = { name = "GuardBit",    target = "player", charge = 3.0, keys = { "guardbit" },    pack = mage("job03_guardbit_lv1") },
    [33]  = { name = "CureSpot",    target = "player", charge = 2.5, keys = { "curespot" },    pack = mage("job03_curespot") },
    [34]  = { name = "HasteSpot",   target = "player", charge = 3.0, keys = { "hastespot" },   pack = mage("job03_hastespot") },
    [35]  = { name = "FullRecover", target = "player", charge = 3.5, keys = { "fullrecover" }, pack = mage("job03_fullrecover") },
    [107] = { name = "Reraise",     target = "player", keys = { "reraise" },     pack = mage("job03_reraise") },
    [24]  = { name = "Firestorm",   target = "enemy",  charge = 2.5, keys = { "firestorm" },   pack = mage("job03_firestorm") },
    [25]  = { name = "Levin",       target = "enemy",  charge = 2.5, keys = { "thunderrain", "levin" }, pack = mage("job03_thunderrain") },
    [26]  = { name = "Frigor",      target = "enemy",  charge = 3.0, keys = { "frigor" },      pack = mage("job03_frigor") },
    [32]  = { name = "HolyShine",   target = "enemy",  charge = 3.0, keys = { "holyshine" },   pack = mage("job03_holyshine_attack") },
    [36]  = { name = "SpellBreak",  target = "enemy",  charge = 3.5, keys = { "spellbreak" },  pack = mage("job03_spellbreak") },
    -- Virtuous / Exalted Bolt: buffs the casting Mage only (holy bolts on her basic attack; user, test 16). Aimed at an
    -- enemy, the way it cast 4/4 in test 16. User, test 18: "does not finish charging" -> release_ai (see READY_MAX_AI);
    -- the "channel" idea of test 18 was wrong (Cast ends on its own in ~2.2 s with or without the AI)
    [106] = { name = "DivineShot",  target = "enemy", release_ai = true, keys = { "divineshot" }, pack = mage("job03_divineshot") },
}
-- Launch stance (decision 2; user, after test 12: Fighter and Warrior launches too). Pack and the availability
-- hook from APC (F3/F4): the pawn holds the stance (layer Job01_/Job05_Springboard) until the player is launched
-- or the same order comes again (APC: AI back + NormalLocomotion). AI stays off for the whole stance.
ORDERS[5]  = { name = "FighterLaunch", target = "player", stance = true, keys = { "springboard" },
               pack = PACK_ROOT .. "job01_fighter\\job01_springboard_01.user" }
ORDERS[60] = { name = "WarriorLaunch", target = "player", stance = true, keys = { "springboard" },
               pack = PACK_ROOT .. "job05_warrior\\job05_springboard_01.user" }
-- Non-attack skills of the other pawn vocations (user, after test 14: "Shield Summons too; check every
-- non-attack skill of every pawn vocation"). Archer has none (every skill aims at an enemy). Packs from the
-- DD2 file list; the _targetmember variant (vs _emtarget) and the layer keys are guesses, [START] generic
-- learns the real layer name. Target = player like the Mage buffs.
local function pack(folder, file) return PACK_ROOT .. folder .. "\\" .. file .. ".user" end
ORDERS[6]   = { name = "ShieldSummons", target = "player", keys = { "shieldsummons" },
                pack = pack("job01_fighter", "pawn_job01_shieldsummons_targetmember") }
ORDERS[9]   = { name = "FullMoonGuard", target = "player", keys = { "fullmoonguard" },
                pack = pack("job01_fighter", "job01_fullmoonguard") }
ORDERS[11]  = { name = "DivineDefense", target = "player", keys = { "divinedefense" },
                pack = pack("job01_fighter", "job01_divinedefense") }
ORDERS[56]  = { name = "WarCry",        target = "player", keys = { "warcry" },
                pack = pack("job05_warrior", "job05_warcry_targetmember") }
ORDERS[59]  = { name = "Guts",          target = "player", keys = { "guts" },
                pack = pack("job05_warrior", "job05_guts") }
ORDERS[111] = { name = "ScarletVow",    target = "player", keys = { "scarletvow" },
                pack = pack("job05_warrior", "job05_scarletvow") }
-- Arcane Chest: releases the stocked spell at once (the AI's "instant" Louvor, F15)
ORDERS[27]  = { name = "SpellStockRelease", target = "player", keys = { "spellstock" },
                pack = mage("job03_spellstockrelease") }
-- Every other skill of the pawn vocations (user, after test 25: "free every skill for tests; whether the pawns use
-- them well we check later"). Pack = the plain jobNN_<skill> file of the DD2 file list (not _npc / _spot / combo),
-- else the closest name (my guess: HeavyRain, SmokeScreen, the _01 variants). At fire time the pawn's own AI
-- decision pack for the skill wins when it has one (ai_pack, [PACK] says which). Layer key = the skill name;
-- [START] generic learns the real layer. target "self" = the pawn itself (Thief's blade enchant and cloak).
do -- own block: the main chunk is at Lua's 200-locals limit
local MORE = {
    job01_fighter = {
        { 1, "BlinkStrike", "job01_blinkstrike" }, { 2, "RisingLunge", "job01_risinglunge_standard" },
        { 3, "CymbalAttack", "pawn_job01_cymbalattack" }, { 4, "FullMoonSlash", "job01_fullmoonslash" },
        { 7, "ViolentStab", "job01_violentstab" }, { 8, "HindsightSlash", "job01_hindsightslash" },
        { 10, "ShieldCounter", "job01_shieldcounter" }, { 12, "BravesRaid", "job01_bravesraid" },
        { 102, "RushAttack", "job01_rushattack" }, { 103, "Ascertain", "job01_ascertain" },
    },
    job02_archer = {
        { 13, "ThreefoldArrow", "job02_threefoldarrow" }, { 14, "TriadShot", "job02_triadshot" },
        { 15, "BodyBinder", "job02_bodybinder" }, { 16, "MeteorShot", "job02_meteorshot" },
        { 17, "SpecialAllowBomb", "job02_specialallowbomb_01" }, { 18, "SpecialAllowWater", "job02_specialallowwater_01" },
        { 19, "SpecialAllowOil", "job02_specialallowoil_01" }, { 20, "SpecialAllowPoison", "job02_specialallowpoison_01" },
        { 21, "RandomShot", "job02_randomshot" }, { 22, "WhirlingArrow", "job02_whirlingarrow" },
        { 23, "FullBlast", "job02_fullblast" }, { 104, "FlightShot", "job02_flightshot" },
        { 105, "HeavyRain", "job02_heavyrain_combo3" },
    },
    job04_theif = { -- folder name spelled so in the game files
        { 38, "CuttingWind", "job04_cuttingwind" }, { 39, "Guillotine", "job04_guillotine" },
        { 40, "Attract", "job04_attract_01" }, { 41, "ParryCounter", "job04_parrycounter" },
        { 42, "AbsoluteAvoidance", "job04_absoluteavoidance" }, { 43, "HollowOut", "job04_hollowout_01" },
        { 44, "FlameBlade", "job04_flameblade", "self" }, { 45, "SmokeScreen", "job04_smoke" },
        { 46, "RemoteBomb", "job04_remotebomb_01" }, { 47, "WindWave", "job04_windwave" },
        { 48, "Stealth", "job04_stealth", "self" }, { 49, "Snatch", "job04_snatch" },
        { 101, "FakeMaster", "job04_fakemaster" }, { 108, "AdvancedTrigger", "job04_advancedtrigger" },
        { 109, "CarpetBombing", "job04_carpetbombing" },
    },
    job05_warrior = {
        { 50, "HeavyRunningThrust", "job05_heavyrunningthrust" }, { 51, "HorizontalSlash", "job05_horizontalslash" },
        { 52, "CrescentSlash", "job05_crescentslash" }, { 53, "CycloneSlash", "job05_cycloneslash" },
        { 54, "GroundDrill", "job05_grounddrill" }, { 55, "CounterAttack", "job05_counterattack_01" },
        { 57, "LandSlide", "job05_landslide" }, { 58, "IndomitableLash", "job05_indomitablelash" },
        { 61, "ArcOfObliteration", "job05_arcofobliteration" }, { 110, "DashSlashUp", "job05_dashslashup" },
    },
    job06_sorcerer = {
        { 62, "Salamander", "job06_salamander" }, { 63, "Blizzard", "job06_blizzard" },
        { 64, "MineVolt", "job06_minevolt" }, { 65, "SaintDrain", "job06_saintdrain" },
        { 66, "RockBeat", "job06_rockbeat" }, { 67, "AddFlare", "job06_addflare" },
        { 68, "MeteorFall", "job06_meteorfall" }, { 69, "VortexRage", "job06_vortexrage" },
        { 112, "ThunderWhip", "job06_thunderwhip" }, { 113, "FrozenStorm", "job06_frozenstorm" },
    },
}
for folder, list in pairs(MORE) do
    for _, m in ipairs(list) do
        ORDERS[m[1]] = { name = m[2], target = m[4] or "enemy", keys = { m[2]:lower() }, pack = pack(folder, m[3]),
                         ai_fuzzy = true }
    end
end
-- Test 27: Meteoron's cast was cancelled 0.02 s after the Cast layer (our way); cancels blocked this long after it
ORDERS[68].hold_cast = 1.5
-- Test 27: Meteoron casts 3.00 s after Ready (x2); a fall at +9.7 s pushed one past the 3.3 s Ready cap
ORDERS[68].ready_max = 5.0
-- Test 30: our way never cast these two (7 of 7 failed); when her AI has no decision for them yet (her battle
-- list is not built before she is in battle state) the order waits for it (AIM.WAIT_DECISION) instead.
-- Test 35: those 7 were all out of battle state; Vortex (69) gets the one-press fallback again (menu
-- vortex_our_way) since in test 34 her AI ran nothing ("none") for 5 s with only Vortex on, 0 of 5 cast
ORDERS[68].wait_ai = true
ORDERS[69].wait_ai = true
end
-- Keys read from a real run (test 4); the others also accept the generic start
local KEYS_SEEN = { [29] = true, [30] = true, [31] = true, [37] = true, [24] = true, [25] = true, [106] = true }

-- Test aids (DEV build only, start off). 0.9.39: the approved test switches (F1-F8, F11 and the menu ones: AI
-- guard, hit retry, getPrepareSec deadline, only ours, palette, D-pad labels, AI decides, wait for the decision,
-- one press, Vortex our way, no 1.5 s start limit, stamina %, charge watch) are fixed on and their old paths are
-- gone; F6 (AI stays on during our order, off since v0.10) is gone too.
local TOGGLE_KEYS = DEV and {
    -- F9: the ordered skill's AI cooldown is zeroed. Off = the game's cooldown holds
    -- (user: stamina and cooldown are what keep skills from being spammed)
    [0x78] = "no_cooldown",
    -- F10: attack orders go our way with the pawn herself as the target, so she casts
    -- where she stands instead of walking to an enemy (user: to test only the cast)
    [0x79] = "cast_in_place",
} or {}
local enabled = { no_cooldown = false, cast_in_place = false }

-- Bindings: [pawn slot][vocation id as string][chord "B"/"LT"][button] = HumanCustomSkillID
-- B chord buttons = D-pad directions; LT chord = face buttons and the two pairs, like the player's
-- RB skills (decision 38). Per pawn slot (decision 42: vocations repeat with different skills); a new hired
-- pawn in a slot inherits that slot's bindings (user: set them again, like after a vocation change).
local DPAD = { "Left", "Up", "Right", "Down" }
local BUTTONS = { B = DPAD, LT = { "X", "Y", "B", "A", "A+X", "B+Y" } }
-- Shortcut sets the player picks in the menu (decision 38). B + R3 removed in 0.9 (user: no longer makes sense);
-- a config still on it falls back to LT
local SCHEMES = {
    { id = "LT",   chords = { "LT" },      label = "LT + X/Y/B/A, A+X, B+Y (6 positions)" },
    { id = "B_LT", chords = { "B", "LT" }, label = "B + D-pad and LT + face buttons (10 positions)" },
}
local DEFAULT_SCHEME = "LT"
local DEFAULT_MAIN = { ["3"] = { LT = { X = 29, Y = 30, B = 31 }, B = { Left = 29, Up = 30, Right = 31 } } }
-- Pawn slots: main pawn, then the hired pawns in PawnManager list order. LT + D-pad picks the target.
local SLOTS = { "main", "hired1", "hired2" }
local SLOT_LABEL = { main = "Main pawn", hired1 = "Hired pawn 1", hired2 = "Hired pawn 2" }
local TARGET_DPAD = { Left = "main", Up = "hired1", Right = "hired2" } -- Down = cancel the target's action
-- Keyboard keys for the same four (user, 2026-10-15), saved as config.keys["Target+Left"]...
local TARGET_KEYS = { "Left", "Up", "Right", "Down" }
local TARGET_KEY_LABEL = { Left = "Target main pawn", Up = "Target hired pawn 1", Right = "Target hired pawn 2",
    Down = "Cancel the target's action" }
-- Keyboard keys: [position "B+Left"...] = Windows virtual-key code, same for every vocation (user, 2026-10-14:
-- one key per position, no Ctrl/Shift/Alt combos, pad and keyboard both on). Not hidden from the game.

-- Requests the AI uses to cancel a forced action (same list as APC). value = also blocked after the start;
-- NormalLocomotion only before it, so the pawn can walk while casting (test 4: frozen during Firestorm)
local CANCEL_NODES = {
    DefaultCancelAction = true,
    UpperBodyDefault = true,
    SheatheWeapon = true,
    NormalLocomotion = false,
    -- test 6: the AI sheathed the weapon during DrawWeapon / Prepare and the order never started
    AttackCancelSheatheWeaponFullBody = true,
    AttackCancelSheatheWeaponUpperBody = true,
    FastSheatheWeapon = true,
}
-- Blocked whatever their priority (priority of the sheathe requests not logged yet; [GUARD] shows it)
local CANCEL_ANY_PRIO = {
    AttackCancelSheatheWeaponFullBody = true,
    AttackCancelSheatheWeaponUpperBody = true,
    FastSheatheWeapon = true,
}

-- Actions where the pawn counts as free, so a queued order fires at once
local function is_free_action(name)
    return name == "?" or name:find("Locomotion") or name:find("Idle") or name:find("Default")
end

---------------------------------------------------------------- log

-- Release log keeps what a bug report needs: setup, each order's life, errors and the summary
local RELEASE_TAGS = { ERR = true, WARN = true, BIND = true, JOB = true, PARTY = true, PAWN = true, AI = true,
                       TARGET = true, PACK = true, QUEUE = true, FIRE = true, START = true, READY = true, CAST = true,
                       LANDED = true, END = true, CANCEL = true, AICANCEL = true, AIMODE = true, SUM = true,
                       PREP = true, RETRY = true, HUD = true }
-- Lines are buffered and written once per LOG_FLUSH s (opening the file for every line cost a file open per
-- line; a [DUMP] burst was hundreds in one frame)
local LOG_FLUSH = 1.0
local log_buf, log_t = {}, 0
local function log_flush()
    if #log_buf == 0 then return end
    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(table.concat(log_buf))
        f:close()
    end
    log_buf = {}
end
local function log_line(text)
    if not DEV then
        local tag = text:match("^%[(%w+)%]")
        if tag and not RELEASE_TAGS[tag] then return end
    end
    log_buf[#log_buf + 1] = string.format("%s %.2f %s\n", os.date("%H:%M:%S"), os.clock(), text)
    if text:sub(1, 5) == "[ERR]" then log_flush() end
end

local counters = { chords = 0, queued = 0, interrupts = 0, fired = 0, not_equipped = 0, unbound = 0,
                   no_action = 0, errors = 0, guards = 0, landed = 0, cut = 0, swallowed = 0, lt_hidden = 0,
                   no_target = 0, started = 0, no_start = 0, ended = 0, hud_frames = 0, dpad_frames = 0,
                   ai_blocked = 0, req_seen = 0, keys = 0, target_picks = 0, cancels = 0, ai_mode = 0,
                   retries = 0, prep_seen = 0, fallbacks = 0, watch_end = 0 }

local function err(where, e)
    counters.errors = counters.errors + 1
    log_line("[ERR] " .. where .. ": " .. tostring(e))
end

local function summary()
    local parts = {}
    for k, v in pairs(counters) do parts[#parts + 1] = k .. "=" .. v end
    table.sort(parts)
    log_line("[SUM] " .. table.concat(parts, " "))
end

if not DEV then
    -- one session per file in the release (the test build keeps every run)
    local f = io.open(LOG_FILE, "w")
    if f then f:close() end
end
log_line(string.format("=== RUN %s PawnOrders v%s ===", os.date("%Y-%m-%d %H:%M:%S"), VERSION))

---------------------------------------------------------------- pad buttons

local function enum_value(type_name, field_name)
    local ok, v = pcall(function()
        return tonumber(sdk.find_type_definition(type_name):get_field(field_name):get_data(nil))
    end)
    return ok and v or nil
end

-- via.hid.GamePadButton, Xbox layout: RRight = B, RStickPush = R3
local BTN = {}
for _, n in ipairs({ "LUp", "LDown", "LLeft", "LRight", "RUp", "RDown", "RLeft", "RRight",
                     "LTrigTop", "RTrigTop", "LTrigBottom", "RTrigBottom", "LStickPush", "RStickPush",
                     "CLeft", "CRight" }) do
    BTN[n] = enum_value("via.hid.GamePadButton", n)
end
do
    local parts = {}
    for n, v in pairs(BTN) do parts[#parts + 1] = string.format("%s=0x%X", n, v) end
    table.sort(parts)
    log_line("[PADMAP] via.hid.GamePadButton " .. table.concat(parts, " "))
end

-- dd2gether-fork realtime_menus.lua: D-pad bits in UserInput.PadButton
local DPAD_BITS = 0xF
local DPAD_NAME = { [0x1] = "Up", [0x2] = "Down", [0x4] = "Left", [0x8] = "Right" }
-- LT = LTrigBottom 0x200 (test 20: [LT] down on every LT press; LT raises action flags 0x200001)
local LT_BITS = BTN.LTrigBottom or 0
local FACE_NAME = {} -- pad bit -> "X"/"Y"/"B"/"A" (Xbox layout, F7: B = RRight, X = RLeft)
local FACE_BIT = {}  -- "X"/... -> pad bit
for btn, name in pairs({ RLeft = "X", RUp = "Y", RRight = "B", RDown = "A" }) do
    if BTN[btn] then
        FACE_NAME[BTN[btn]] = name
        FACE_BIT[name] = BTN[btn]
    end
end

-- Two face buttons pressed within this many seconds = the pair (A+X / B+Y), like the player's RB skills
local PAIR_WINDOW = 0.10
-- Optional "hold LT" mode (menu): LT opens the orders only once held this long; a shorter press is given back to
-- the game as an LT tap (sheathe / draw). A face button or D-pad pressed under LT opens them at once.
-- One table for this mode's state: the main chunk is at Lua's 200-locals limit.
local LTH = {
    DEFAULT = 0.25,
    press_t = nil, -- time LT physically went down (nil = up)
    open = false,  -- this LT press opened the orders (always at once outside hold mode)
    tap = nil,     -- { flags, frame } short LT press being replayed to the game
    chord_bits = DPAD_BITS, -- + face buttons below: pressed under LT, they open the orders at once
    blocked = false, -- an RB overlap cancels this entire physical LT press
    rb_prev = false,
}
for bit in pairs(FACE_NAME) do LTH.chord_bits = LTH.chord_bits | bit end
local PAIR = { A = { "X", "A+X" }, X = { "A", "A+X" }, B = { "Y", "B+Y" }, Y = { "B", "B+Y" } }
local PAD_FIELDS = { "PadButton", "PadButtonDown", "PadButtonUp", "PadButtonRepeat" }
local FLAG_FIELDS = { "ButtonOnFlags", "ButtonTriggerFlags", "ButtonRepeatFlags", "ButtonReleaseFlags" }
-- Pawn command action bits (APC reads them in ButtonReleaseFlags: ToMe, Go, Help, Wait)
local PAWN_COMMAND_FLAGS = 131072 | 262144 | 524288 | 1048576

local function bit_names(bits)
    local out = {}
    for n, v in pairs(BTN) do
        if v and bits & v ~= 0 then out[#out + 1] = n end
    end
    table.sort(out)
    return #out > 0 and table.concat(out, "+") or "-"
end

---------------------------------------------------------------- config

local function load_config()
    local c = json.load_file(CONFIG_FILE)
    if type(c) ~= "table" then c = {} end
    local from = CONFIG_FILE
    if type(c.pawns) ~= "table" then
        -- 0.8.x files keep one binding table for the main pawn (`bindings`, left in the file untouched)
        c.pawns = { main = type(c.bindings) == "table" and c.bindings or DEFAULT_MAIN }
        from = type(c.bindings) == "table" and (CONFIG_FILE .. " (0.8 bindings -> main pawn)") or "defaults"
        json.dump_file(CONFIG_FILE, c)
    end
    for _, slot in ipairs(SLOTS) do
        if type(c.pawns[slot]) ~= "table" then c.pawns[slot] = {} end
    end
    if type(c.keys) ~= "table" then c.keys = {} end
    local parts = {}
    for _, slot in ipairs(SLOTS) do
        for job, chords in pairs(c.pawns[slot]) do
            for chord, arrows in pairs(chords) do
                for arrow, id in pairs(arrows) do
                    parts[#parts + 1] = string.format("%s:%s:%s+%s=%s", slot, job, chord, arrow, tostring(id))
                end
            end
        end
    end
    table.sort(parts)
    log_line(string.format("[BIND] loaded %s: %s", from, table.concat(parts, " ")))
    local keys = {}
    for pos, vk in pairs(c.keys) do keys[#keys + 1] = string.format("%s=0x%X", pos, tonumber(vk) or 0) end
    table.sort(keys)
    log_line("[BIND] keys: " .. (#keys > 0 and table.concat(keys, " ") or "-"))
    log_line("[BIND] scheme " .. tostring(c.scheme or DEFAULT_SCHEME))
    return c
end

local config = load_config()

local function save_config()
    json.dump_file(CONFIG_FILE, config)
end

local function scheme()
    for _, sc in ipairs(SCHEMES) do if sc.id == config.scheme then return sc end end
    for _, sc in ipairs(SCHEMES) do if sc.id == DEFAULT_SCHEME then return sc end end
end

local function chord_on(chord)
    for _, c in ipairs(scheme().chords) do if c == chord then return true end end
    return false
end

local function binding(slot, job, chord, arrow)
    local j = config.pawns[slot][tostring(job)]
    local c = j and j[chord]
    return c and tonumber(c[arrow]) or 0
end

local function set_binding(slot, job, chord, arrow, id)
    local key = tostring(job)
    local p = config.pawns[slot]
    p[key] = p[key] or {}
    p[key][chord] = p[key][chord] or {}
    p[key][chord][arrow] = id
    save_config()
    log_line(string.format("[BIND] %s job %s %s+%s = %d", slot, key, chord, arrow, id))
end

---------------------------------------------------------------- keyboard keys

-- Windows virtual-key names (keys not listed show as hex)
local VK_NAMES = {
    [0x04] = "Mouse middle", [0x05] = "Mouse 4", [0x06] = "Mouse 5",
    [0x08] = "Backspace", [0x09] = "Tab", [0x0D] = "Enter", [0x13] = "Pause", [0x14] = "Caps Lock",
    [0x20] = "Space", [0x21] = "Page Up", [0x22] = "Page Down", [0x23] = "End", [0x24] = "Home",
    [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down", [0x2D] = "Insert", [0x2E] = "Delete",
    [0x6A] = "Numpad *", [0x6B] = "Numpad +", [0x6D] = "Numpad -", [0x6E] = "Numpad .", [0x6F] = "Numpad /",
    [0x90] = "Num Lock", [0x91] = "Scroll Lock",
    [0xA0] = "Left Shift", [0xA1] = "Right Shift", [0xA2] = "Left Ctrl", [0xA3] = "Right Ctrl",
    [0xA4] = "Left Alt", [0xA5] = "Right Alt", [0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-",
    [0xBE] = ".", [0xBF] = "/", [0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]", [0xDE] = "'",
}
for i = 0, 9 do
    VK_NAMES[0x30 + i] = tostring(i)
    VK_NAMES[0x60 + i] = "Numpad " .. i
end
for i = 0, 25 do VK_NAMES[0x41 + i] = string.char(65 + i) end
for i = 1, 24 do VK_NAMES[0x6F + i] = "F" .. i end

-- Keys never offered: left/right mouse (menu clicks), Escape (cancels the capture),
-- generic Shift/Ctrl/Alt codes (the left/right codes come with them and would bind twice)
local VK_SKIP = { [0x01] = true, [0x02] = true, [0x1B] = true, [0x10] = true, [0x11] = true, [0x12] = true }

local function vk_name(vk)
    if not vk then return "none" end
    return VK_NAMES[vk] or string.format("key 0x%X", vk)
end

local function key_of(chord, arrow)
    return tonumber(config.keys[chord .. "+" .. arrow])
end

-- vk = nil clears the position; a key bound elsewhere moves here (one key = one position)
local function set_key(chord, arrow, vk)
    local pos = chord .. "+" .. arrow
    if vk then
        for other, v in pairs(config.keys) do
            if other ~= pos and tonumber(v) == vk then
                config.keys[other] = nil
                log_line(string.format("[BIND] key %s moved from %s", vk_name(vk), other))
            end
        end
    end
    config.keys[pos] = vk
    save_config()
    log_line(string.format("[BIND] key %s = %s", pos, vk_name(vk)))
end

---------------------------------------------------------------- skill names (ThePawnController calls)

local function find_method(type_name, sig)
    local td = sdk.find_type_definition(type_name)
    local m = td and td:get_method(sig)
    if not m then log_line("[WARN] method not found: " .. type_name .. "." .. sig) end
    return m
end
local msgGet = find_method("via.gui.message", "get(System.Guid)")
local skillNameMethod = find_method("app.GUIBase", "getCustomSkillName(app.HumanCustomSkillID, app.HumanCustomSkillLevelNo)")
local jobNameMsgMethod = find_method("app.GUIBase", "getJobNameMsgID(app.Character.JobEnum)")
local JOB_FALLBACK = { "Fighter", "Archer", "Mage", "Thief", "Warrior", "Sorcerer",
                       "Mystic Spearhand", "Magick Archer", "Trickster", "Warfarer" }

local function clean_text(s)
    if type(s) ~= "string" or s == "" or s:find("Rejected", 1, true) then return nil end
    s = s:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

local function enum_list(type_name)
    local out = {}
    local td = sdk.find_type_definition(type_name)
    if not td then return out end
    for _, f in ipairs(td:get_fields()) do
        if f:is_static() then
            local ok, v = pcall(f.get_data, f, nil)
            if ok and type(v) == "number" then out[#out + 1] = { name = f:get_name(), id = v } end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- SKILLS[id] = { enum = "Job03_FireBoon", job = 3, name = localized or nil }; JOB_SKILLS[job] = { id, ... }
local SKILLS, JOB_SKILLS = {}, {}
for _, e in ipairs(enum_list("app.HumanCustomSkillID")) do
    local job = e.name:match("^Job(%d%d)_")
    if job and e.id > 0 then
        job = tonumber(job)
        SKILLS[e.id] = { enum = e.name, job = job }
        JOB_SKILLS[job] = JOB_SKILLS[job] or {}
        table.insert(JOB_SKILLS[job], e.id)
    end
end
-- Pawn vocations only (user, after test 25: a pawn cannot be Magick Archer, Mystic Spearhand, Trickster or
-- Warfarer, so those are out of the menu): Fighter 1 .. Sorcerer 6
local JOBS = {}
for _, e in ipairs(enum_list("app.Character.JobEnum")) do
    if e.id > 0 and e.id <= 6 and JOB_SKILLS[e.id] then JOBS[#JOBS + 1] = { id = e.id, enum = e.name } end
end

local names_done, name_tries = false, 0
local job_names = {}

local function resolve_names()
    if names_done then return end
    name_tries = name_tries + 1
    local got, total = 0, 0
    for id, s in pairs(SKILLS) do
        total = total + 1
        if not s.name then
            for _, lv in ipairs({ 1, 0, 2 }) do
                local ok, n = pcall(function() return skillNameMethod:call(nil, id, lv) end)
                n = ok and clean_text(n) or nil
                if n then s.name = n break end
            end
        end
        if s.name then got = got + 1 end
    end
    for _, j in ipairs(JOBS) do
        if not job_names[j.id] then
            local ok, n = pcall(function() return msgGet:call(nil, jobNameMsgMethod:call(nil, j.id)) end)
            job_names[j.id] = ok and clean_text(n) or nil
        end
    end
    if got == total or name_tries >= 600 then
        names_done = true
        local f = DEV and io.open(SKILLDB_FILE, "w")
        if f then
            for _, j in ipairs(JOBS) do
                for _, id in ipairs(JOB_SKILLS[j.id]) do
                    local s = SKILLS[id]
                    f:write(string.format("%d\t%s\t%s\n", id, s.enum, s.name or "?"))
                end
            end
            f:close()
        end
        log_line(string.format("[SKILLDB] %d skills, %d names resolved after %d tries -> %s",
            total, got, name_tries, SKILLDB_FILE))
    end
end

local function skill_label(id)
    local s = SKILLS[id]
    if not s then return tostring(id) end
    return string.format("%s (%d)", s.name or s.enum, id)
end

local function job_label(id)
    return job_names[id] or JOB_FALLBACK[id] or ("Job " .. id)
end

---------------------------------------------------------------- game access

local setExecuteMethod = sdk.find_type_definition("app.AIBlackBoardExtensions")
    :get_method("setBBValuesToExecuteActInter(app.AIBlackBoardController, app.ActInterPackData, app.AITarget)")

-- os.clock on Windows (MSVC CRT) is wall time since process start
local function now()
    return os.clock()
end

local function get_player()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    return cm and cm:get_ManualPlayer()
end

local function get_main_pawn()
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local mp = pm and pm:get_field("_MainPawn")
    return mp and mp:call("get_CachedCharacter")
end

-- Pawn name: name plate text (as DD2gether reads it), else PawnDataContext._Name (as DannaUI reads it),
-- else the GameObject name. Which source answered is logged once per source.
local getNameMethod = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.Character)")
local name_src_logged = {}
local function pawn_name(chara)
    local n, src
    if getNameMethod then pcall(function() n = clean_text(getNameMethod:call(nil, chara)) end) end
    if n then src = "GUIBase.getName" end
    if not n then
        pcall(function()
            n = clean_text(tostring(chara["<Human>k__BackingField"]:call("get_PawnDataContext"):get_field("_Name")))
        end)
        if n then src = "PawnDataContext._Name" end
    end
    if not n then
        local ok, g = pcall(function() return chara:get_GameObject():get_Name() end)
        n, src = ok and tostring(g) or "?", "GameObject"
    end
    if not name_src_logged[src] then
        name_src_logged[src] = true
        log_line(string.format("[PARTY] pawn name from %s ('%s')", src, n))
    end
    return n
end

-- Party pawns by slot: main = PawnManager._MainPawn, hired1 / hired2 = the other members of
-- get_PawnCharacterList in list order (whether the list holds the main pawn is logged: [PARTY] raw)
local last_party_text = nil
local function party_pawns()
    local out = {}
    local main = get_main_pawn()
    local main_addr = main and main:get_address() or 0
    if main then out.main = main end
    local raw = {}
    pcall(function()
        local list = sdk.get_managed_singleton("app.PawnManager"):get_PawnCharacterList()
        local n = 1
        for i = 0, list:get_Count() - 1 do
            local c = list[i]
            if c then
                local is_main = c:get_address() == main_addr
                raw[#raw + 1] = string.format("%d:%s%s", i, pawn_name(c), is_main and "(main)" or "")
                if not is_main and n <= 2 then
                    out["hired" .. n] = c
                    n = n + 1
                end
            end
        end
    end)
    local parts = {}
    for _, slot in ipairs(SLOTS) do
        parts[#parts + 1] = slot .. "=" .. (out[slot] and pawn_name(out[slot]) or "-")
    end
    local text = table.concat(parts, " ") .. "; raw list " .. (#raw > 0 and table.concat(raw, " ") or "empty")
    if text ~= last_party_text then
        last_party_text = text
        log_line("[PARTY] " .. text)
    end
    return out
end

-- Target pawn of the orders (decision 42): picked with LT + D-pad, main pawn at load and when the picked
-- slot is empty (hired pawn dismissed)
local target_slot = "main"
local function get_target()
    local party = party_pawns()
    if not party[target_slot] and target_slot ~= "main" then
        log_line(string.format("[WARN] [PAWN] %s not in the party; target back to the main pawn", SLOT_LABEL[target_slot]))
        target_slot = "main"
    end
    return party[target_slot], target_slot, party
end

local function get_job(chara)
    return chara:get_field("WeaponJob")
end

local function get_equipped(chara, job)
    local ctx = chara["<Human>k__BackingField"]["<SkillContext>k__BackingField"]
    local skills = ctx.EquipedSkills[job].Skills
    local out = {}
    for i = 0, 5 do
        local ok, v = pcall(function() return skills[i].value__ end)
        if not ok then break end
        out[#out + 1] = v
    end
    return out
end

-- Skill in each of the 4 custom slots (U9; ThePawnController: getSkillID(job, slot 0-based))
local function get_slots(chara, job)
    local ctx = chara["<Human>k__BackingField"]["<SkillContext>k__BackingField"]
    local out = {}
    for slot = 0, 3 do
        local ok, v = pcall(function()
            local r = ctx:call("getSkillID", job, slot)
            if type(r) == "number" then return r end
            return tonumber(r:get_field("value__")) or 0
        end)
        out[#out + 1] = ok and v or -1
    end
    return out
end

-- All layers of the pawn's current action list, "a|b|c". 0.9.39: only the indexes the list has (the old read
-- went 0..7 until get_Item threw; each throw was a game ArgumentOutOfRangeException that REFramework writes to
-- re2_framework_log.txt: 34,831 of them in one 0.9.38 session, up to ~50 per second)
local function action_layers(chara)
    local names = {}
    pcall(function()
        local list = chara["<ActionManager>k__BackingField"].CurrentActionList
        for i = 0, math.min(list:call("get_Count"), 8) - 1 do
            local ok, n = pcall(function() return list[i].Name end)
            if not ok then break end
            names[#names + 1] = n and tostring(n) or "nil"
        end
    end)
    return table.concat(names, "|")
end

-- First skill layer in "a|b|c" (Job03_CastAnodyne, JobMagicUser_PrepareMagicTurn...), or nil.
-- Every skill seen in tests 1-4 runs on such a layer, also while layer 0 shows Strafe (U11).
-- Normal attacks are not skills (test 6: JobMagicUser_RapidShot / PrepareNormalShot held the queue)
local NOT_SKILL = { "NormalShot", "RapidShot", "MagicTurn" }
local function skill_layer(layers)
    for n in layers:gmatch("[^|]+") do
        if n:find("^Job%d+_") or n:find("^JobMagicUser_") then
            local skill = true
            for _, s in ipairs(NOT_SKILL) do
                if n:find(s, 1, true) then skill = false break end
            end
            if skill then return n end
        end
    end
    return nil
end

local function current_action(chara)
    local ok, name = pcall(function()
        local list = chara["<ActionManager>k__BackingField"].CurrentActionList
        if list:call("get_Count") < 1 then return nil end -- empty list: [0] would throw in the game (see action_layers)
        return list[0].Name
    end)
    return (ok and name) and tostring(name) or "?"
end

local function create_ai_target(target)
    local t = sdk.create_instance("app.AITargetGameObject", true)
    t["<GameObject>k__BackingField"] = target:get_GameObject()
    t["<Character>k__BackingField"] = target
    t["<Owner>k__BackingField"] = target:get_GameObject()
    t["<OwnerCharacter>k__BackingField"] = target
    t["<ContextHolder>k__BackingField"] = target:get_Context()
    t["<Transform>k__BackingField"] = target:get_Transform()
    return t
end

-- Boon status IDs active on the player -> set {15=true,...}
local function player_boons(player)
    local out = {}
    local ok, e = pcall(function()
        local sc = player:get_StatusConditionCtrl()
        if not sc then return end -- loading / menus (test 3 [ERR] at 289 s)
        for _, id in ipairs({ 15, 16, 17 }) do
            if sc:IsStatusConditionActive(id, false) then out[id] = true end
        end
    end)
    if not ok then err("player_boons", e) end
    return out
end

---------------------------------------------------------------- enemy target (pawn AI target, else nearest to the pawn)

local function chara_name(chara)
    local ok, n = pcall(function() return chara:get_GameObject():get_Name() end)
    return ok and tostring(n) or "?"
end

local function position(chara)
    local p = chara:get_Transform():get_UniversalPosition()
    return p.x, p.y, p.z
end

local function distance(a, b)
    local ax, ay, az = position(a)
    local bx, by, bz = position(b)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

local function is_dead(chara)
    local ok, d = pcall(function() return chara:get_IsDead() end)
    return not ok or d == true
end

-- Alive enemies of EnemyManager
local function alive_enemies()
    local list = {}
    local arr = sdk.get_managed_singleton("app.EnemyManager"):call("getAllEnemies")
    for i = 0, arr:get_Count() - 1 do
        local e = arr[i] and arr[i]:get_field("_Chara")
        if e and not is_dead(e) then
            list[#list + 1] = e
        end
    end
    return list
end

-- Enemy for our-way attacks: the enemy nearest the pawn. No range limit (decision 30; user after test 26: no
-- limit). Test 26: the AI-target path from DD2gether (EnemyCtrl.Ch2._TargetController) does not exist on pawns,
-- removed; the AI's own target is used by AI-decides orders (decision 48).
-- Returns enemy, source text, distance from the pawn, or nil + why.
local function pick_enemy(pawn)
    local ok_list, list = pcall(alive_enemies)
    if not ok_list then return nil, "enemy list failed: " .. tostring(list) end
    local near, near_d
    for _, e in ipairs(list) do
        local okd, d = pcall(distance, pawn, e)
        if okd and (not near_d or d < near_d) then near, near_d = e, d end
    end
    if near then return near, "nearest to the pawn", near_d end
    return nil, "no alive enemy"
end

local function boons_text(b)
    local ids = {}
    for _, id in ipairs({ 15, 16, 17 }) do
        if b[id] then ids[#ids + 1] = tostring(id) end
    end
    return "{" .. table.concat(ids, ",") .. "}"
end

---------------------------------------------------------------- state

local last_scan = -1
local scanned = {}       -- slot -> { job, skills, name, job_text, skills_text, slots_text } of the last scan
local cur_job, cur_skills = nil, {} -- of the target pawn (palette, menu)
local key_was_down = {}
local pending = nil      -- { skill, pawn, slot, t_first, start_action, ai_skill }
local firing = false     -- true while fire() sends our own request (the AI block hook lets it pass)
local active = nil       -- { skill, t_fire, pawn, am_addr, decision, layers, keys, start_layers, t_start, ai_on, ... }
local last_press = {}    -- skill -> time of last accepted press (interrupt window)
local chord_requests = {} -- filled by the input hook, run on the frame
local last_boons_text = nil

-- Test 34: one order and one queue per pawn (test 33: 6 orders lost to an order to another pawn, 2 of them
-- charged). `active` / `pending` hold the pawn AIM.cur (by character address); the other pawns' wait in
-- AIM.ctx. order(), cancel_target() and update() call AIM.use first; the hooks look the order up by address.
AIM.ctx, AIM.cur = {}, nil
function AIM.use(addr)
    if addr == AIM.cur then return end
    if AIM.cur and (active or pending) then AIM.ctx[AIM.cur] = { active = active, pending = pending } end
    local c = addr and AIM.ctx[addr]
    active, pending = c and c.active, c and c.pending
    if addr then AIM.ctx[addr] = nil end
    AIM.cur = addr
end
-- Any order running on any pawn
function AIM.any()
    return active ~= nil or next(AIM.ctx) ~= nil
end
-- The running order whose `field` is `v` (hooks: am_addr, bb_addr, human_addr, skill), or nil
function AIM.find(field, v)
    if active and active[field] == v then return active end
    for _, c in pairs(AIM.ctx) do
        if c.active and c.active[field] == v then return c.active end
    end
end
-- Every pawn's AI back as it was (script reset, frame error)
function AIM.all_off()
    AIM.use(nil)
    for _, c in pairs(AIM.ctx) do
        if c.active then
            pcall(function() c.active.decision:set_Enabled(true) end)
            pcall(AIM.restore_decisions, c.active)
        end
    end
    AIM.ctx = {}
end

-- Vocation and equipped skills of the pawn in `slot` (logged when they change)
local function scan(pawn, slot)
    local s = scanned[slot]
    if not s or s.addr ~= pawn:get_address() then
        s = { addr = pawn:get_address() }
        scanned[slot] = s
    end
    local job = get_job(pawn)
    local skills = get_equipped(pawn, job)
    local text = table.concat(skills, ",")
    s.name = pawn_name(pawn)
    if job ~= s.job then
        log_line(string.format("[JOB] %s %s vocation %s -> %s", slot, s.name, tostring(s.job), tostring(job)))
    end
    if text ~= s.skills_text then
        log_line(string.format("[SKILLS] %s job %s equipped {%s}", slot, tostring(job), text))
        s.skills_text = text
    end
    local slots = get_slots(pawn, job)
    local slots_text = table.concat(slots, ",")
    if names_done and slots_text ~= s.slots_text then
        local parts = {}
        for i, id in ipairs(slots) do parts[#parts + 1] = string.format("%d=%s", i, skill_label(id)) end
        log_line(string.format("[SLOTS] %s job %s %s", slot, tostring(job), table.concat(parts, " ")))
        local extra = {}
        for _, id in ipairs(skills) do extra[#extra + 1] = skill_label(id) end
        log_line(string.format("[SLOTS] %s EquipedSkills = %s", slot, table.concat(extra, ", ")))
        s.slots_text = slots_text
    end
    s.job, s.skills = job, skills
    if slot == target_slot then cur_job, cur_skills = job, skills end
    return job, skills
end

local function has_skill(skills, id)
    for _, v in ipairs(skills) do
        if v == id then return true end
    end
    return false
end

local function has_key(low, keys)
    for _, k in ipairs(keys) do
        if low:find(k, 1, true) then return true end
    end
    return false
end

local function layer_set(layers)
    local s = {}
    for n in layers:gmatch("[^|]+") do s[n] = true end
    return s
end

-- Skills with guessed keys: a Job layer that was not there at the order counts as the start.
-- Returns the layer and its stem ("Job03_PrepareFrigor" -> "frigor"), or nil.
function AIM.layer_stem(n)
    local stem = n:gsub("^Job%w*_", "")
    for _, p in ipairs({ "Prepare", "Ready", "Cast", "Start", "End", "Loop" }) do
        if stem:sub(1, #p) == p and #stem > #p then stem = stem:sub(#p + 1) break end
    end
    return stem:lower()
end

-- Test 26: Job06_CastSaintDrainEnd (the wind-down of the AI's own Saint Drain, running at the order) was taken
-- as the start of an ordered Rock Beat. A layer ending in "End", or of a skill already on at the order, is not ours.
local function new_job_layer(layers, before)
    local before_stems = {}
    for b in pairs(before) do
        if skill_layer(b) then before_stems[AIM.layer_stem(b)] = true end
    end
    for n in layers:gmatch("[^|]+") do
        -- skill_layer skips normal shots and aim turns (test 16: a running RapidShot was taken as the start)
        if not before[n] and skill_layer(n) and not n:find("End$") then
            local stem = AIM.layer_stem(n)
            if not before_stems[stem] and not before_stems[stem:gsub("end$", "")] then return n, stem end
        end
    end
    return nil
end

-- AI back on during our order (the guard keeps blocking cancels until the Cast)
local function ai_back(why)
    if active.ai_on then return end
    pcall(function() active.decision:set_Enabled(true) end)
    active.ai_on = true
    log_line(string.format("[AI] on +%.2fs: %s", now() - active.t_fire, why))
end

-- Packs kept referenced for the whole run (test 12: the Louvor pack was never loaded when fired, `_Pack` nil;
-- a freshly created pack loads later and is freed when nothing holds it)
local pack_cache = {}
local function get_pack(order)
    local u = pack_cache[order.pack]
    if not u then
        u = sdk.create_userdata("app.ActInterPackData", order.pack)
        pack_cache[order.pack] = u
    end
    return u
end

-- The pawn's own AI decisions carry the ActInterPackData each one runs, already loaded (structure read from
-- "Custom Difficulty Tweaks" 2.1.1 by talimity, pawn-ai.lua: AIDecisionMaker.<DecisionModule>
-- .<DecisionPackHandler>.<ActiveDecisionPacks> -> DecisionPack._Decisions[] -> _ActInterPack).
-- Returns { stem = "job03_firestorm", pack = ActInterPackData } for every decision with a pack.
local function ai_decision_packs(pawn)
    local out = {}
    local module = pawn["<AIDecisionMaker>k__BackingField"]:get_field("<DecisionModule>k__BackingField")
    local packs = module:get_field("<DecisionPackHandler>k__BackingField"):get_field("<ActiveDecisionPacks>k__BackingField")
    local items, size = packs:get_field("_items"), packs:get_field("_size") or 0
    for i = 0, size - 1 do
        local dp = items[i]
        local decisions = dp and dp:get_field("_Decisions")
        for j = 0, (decisions and decisions:call("get_Length") or 0) - 1 do
            pcall(function()
                local ap = decisions:call("GetValue(System.Int32)", j):get_field("_ActInterPack")
                local path = ap and ap:call("get_Path")
                local stem = path and path:match("([^/\\]+)%.user[^/\\]*$")
                if stem then out[#out + 1] = { stem = stem:lower(), pack = ap } end
            end)
        end
    end
    return out
end

-- Pack for an order: the pawn's AI pack with the same file name as ours, else (skills added after test 25 only)
-- an AI pack whose name holds the skill name (not an _npc one), else nil = our own file (get_pack).
-- [PACK] says which; [AIPACKS] lists the pawn's AI packs once per pawn and vocation (what her AI can run).
local aipacks_logged = {}
local function ai_pack(pawn, order)
    local ok, list = pcall(ai_decision_packs, pawn)
    if not ok then
        log_line("[PACK] AI decision packs not readable: " .. tostring(list))
        return nil
    end
    -- test 26: the first list (out of combat) had no skills; logged again when the list size changes
    local key = tostring(pawn:get_address()) .. ":" .. tostring(get_job(pawn)) .. ":" .. #list
    if DEV and not aipacks_logged[key] then
        aipacks_logged[key] = true
        local seen, stems = {}, {}
        for _, p in ipairs(list) do
            if not seen[p.stem] then seen[p.stem] = true stems[#stems + 1] = p.stem end
        end
        table.sort(stems)
        log_line(string.format("[AIPACKS] %s job %s: %d packs: %s", pawn_name(pawn), tostring(get_job(pawn)), #stems,
            table.concat(stems, " ")))
    end
    local ours = order.pack:match("([^\\]+)%.user$"):lower()
    for _, p in ipairs(list) do
        if p.stem == ours then
            log_line(string.format("[PACK] %s: AI's own %s", order.name, p.stem))
            return p.pack
        end
    end
    if order.ai_fuzzy then
        local want = order.keys[1]
        for _, p in ipairs(list) do
            if p.stem:find(want, 1, true) and not p.stem:find("npc", 1, true) then
                log_line(string.format("[PACK] %s: AI's %s (ours %s not in her AI)", order.name, p.stem, ours))
                return p.pack
            end
        end
    end
    log_line(string.format("[PACK] %s: our file %s (none in her AI)", order.name, ours))
    return nil
end

-- app.Pawn of a pawn character (PawnManager._PartyPawnList / _MainPawn, matched by get_CachedCharacter;
-- Custom Difficulty Tweaks game-state.lua). Test 26: SkillActionController is not on the character ("?" x17).
function AIM.pawn_object(chara)
    local pm = sdk.get_managed_singleton("app.PawnManager")
    local addr = chara:get_address()
    local function same(p)
        local ok, c = pcall(function() return p:call("get_CachedCharacter") end)
        return ok and c and c:get_address() == addr
    end
    local list = pm:get_field("_PartyPawnList")
    local items, size = list and list:get_field("_items"), list and list:get_field("_size") or 0
    for i = 0, size - 1 do
        if items[i] and same(items[i]) then return items[i] end
    end
    local main = pm:get_field("_MainPawn")
    if main and same(main) then return main end
    return nil
end

-- Skills the pawn's AI may still use this battle (Custom Difficulty Tweaks: app.Pawn SkillActionController
-- _SkillCount used / _MaxSkillCount, rolled once per battle per inclination). "used/max"; reset = count back to 0
-- (user, after test 26: no quota on orders, stamina and cooldown are the limit).
function AIM.skill_budget(chara, reset)
    local ok, s = pcall(function()
        local c = AIM.pawn_object(chara):get_field("<SkillActionController>k__BackingField")
        local text = string.format("%s/%s", tostring(c:get_field("_SkillCount")), tostring(c:get_field("_MaxSkillCount")))
        if reset then
            c:set_field("_SkillCount", 0)
            text = text .. " -> 0"
        end
        return text
    end)
    return ok and s or ("? (" .. tostring(s) .. ")")
end

-- The pawn's runtime AI decisions (DecisionModule <Main/Pre/Post>Decisions, rebuilt from the active
-- DecisionPacks) with the pack stem each runs, matched by UniqueID (Custom Difficulty Tweaks pawn-ai.lua).
function AIM.ai_runtime_decisions(pawn)
    local module = pawn["<AIDecisionMaker>k__BackingField"]:get_field("<DecisionModule>k__BackingField")
    local stem_by_id = {}
    local packs = module:get_field("<DecisionPackHandler>k__BackingField"):get_field("<ActiveDecisionPacks>k__BackingField")
    local items, size = packs:get_field("_items"), packs:get_field("_size") or 0
    for i = 0, size - 1 do
        local decisions = items[i] and items[i]:get_field("_Decisions")
        for j = 0, (decisions and decisions:call("get_Length") or 0) - 1 do
            pcall(function()
                local d = decisions:call("GetValue(System.Int32)", j)
                local ap = d:get_field("_ActInterPack")
                local stem = ap and ap:call("get_Path"):match("([^/\\]+)%.user[^/\\]*$")
                if stem then stem_by_id[d:get_field("_UniqueId"):call("ToString")] = { stem = stem:lower(), data = d } end
            end)
        end
    end
    local out = {}
    for _, ln in ipairs({ "Main", "Pre", "Post" }) do
        local list = module:get_field("<" .. ln .. "Decisions>k__BackingField")
        local li, ls = list and list:get_field("_items"), list and list:get_field("_size") or 0
        for i = 0, ls - 1 do
            local d = li[i]
            if d then
                local ok, id = pcall(function() return d:get_field("<UniqueID>k__BackingField"):call("ToString") end)
                local s = ok and stem_by_id[id]
                if s then out[#out + 1] = { d = d, stem = s.stem, data = s.data, list = ln } end
            end
        end
    end
    return out
end

-- Attack and skill decisions turned off while an AI-decides order waits (moves, heal items, chilling stay on).
-- Test 28: job_magicuser_magicbarrior ("job_" without a number) stayed on and the AI used it during 3 orders.
function AIM.is_attack_stem(stem)
    return stem:find("^job%d") or stem:find("^job_") or stem:find("^pawn_job") or stem:find("^genericjob")
end
AIM.DISABLE_OVERWRITE = 1 -- app.AIDecision.DisableFlags.Overwrite (Custom Difficulty Tweaks)

-- The ordered skill's decisions: its own pack and its variants (test 28 list: job06_meteorfall_multiple,
-- job06_vortexrage_multiple), not the spell-stock release or NPC ones
function AIM.is_ours(stem, ours)
    if stem == ours then return true end
    return stem:sub(1, #ours + 1) == ours .. "_" and not stem:find("spellstock", 1, true) and not stem:find("npc", 1, true)
end

-- Test 31 + decoded packs (F30): the Arcane Stock decision (job06_stockmeteofall etc.) runs the plain cast pack,
-- so it has our stem; it is told apart by its IsStockSpell precondition. Cached by decision data address.
AIM.stock_cache = {}
function AIM.has_stock(data)
    local addr = data:get_address()
    local v = AIM.stock_cache[addr]
    if v == nil then
        v = false
        pcall(function()
            local pre = data:get_field("_Preconditions")
            for i = 0, (pre and pre:call("get_Length") or 0) - 1 do
                local p = pre:call("GetValue(System.Int32)", i):get_field("_Process")
                if p and p:get_type_definition():get_full_name() == "app.decision.condition.IsStockSpell" then
                    v = true
                    break
                end
            end
        end)
        AIM.stock_cache[addr] = v
    end
    return v
end

-- Decision 49 (1): ours = our stem or a variant, minus the Arcane Stock ones and `_multiple` (needs another pawn
-- already charging the same spell, F30)
function AIM.is_mine(e, ours, fuzzy_key)
    local by_stem
    if fuzzy_key then
        by_stem = e.stem:find(fuzzy_key, 1, true) and not e.stem:find("npc", 1, true) and not e.stem:find("spellstock", 1, true)
    else
        by_stem = AIM.is_ours(e.stem, ours)
    end
    return by_stem and not e.stem:find("_multiple", 1, true) and not AIM.has_stock(e.data)
end

-- The ordered skill's decisions in `list` (by decision address -> stem), its pack stem and the fuzzy key used
function AIM.mine_stems(list, order)
    local ours = order.pack:match("([^\\]+)%.user$"):lower()
    local mine = {}
    for _, e in ipairs(list) do
        if AIM.is_mine(e, ours) then mine[e.d:get_address()] = e.stem end
    end
    local fuzzy
    if not next(mine) and order.ai_fuzzy then
        fuzzy = order.keys[1]
        for _, e in ipairs(list) do
            if AIM.is_mine(e, ours, fuzzy) then mine[e.d:get_address()] = e.stem end
        end
    end
    return mine, ours, fuzzy
end
AIM.WAIT_DECISION = 3.0

-- Test 31: the decision her AI runs now (DecisionExecutor.<ExecutingDecision>, an app.DecisionEvaluationResult;
-- its app.AIDecision field is found by type once). Returns the result object and a stem text.
function AIM.executing(pawn, stems)
    local ex = pawn["<AIDecisionMaker>k__BackingField"]:get_field("<DecisionModule>k__BackingField")
        :get_field("<DecisionExecutor>k__BackingField")
    local res = ex:get_field("<ExecutingDecision>k__BackingField")
    if not res then return nil, "none" end
    if AIM.result_field == nil then
        AIM.result_field = false
        for _, f in ipairs(res:get_type_definition():get_fields()) do
            if not f:is_static() and f:get_type():get_full_name() == "app.AIDecision" then
                AIM.result_field = f:get_name()
                log_line("[AIDEC] decision field of DecisionEvaluationResult = " .. AIM.result_field)
                break
            end
        end
    end
    if not AIM.result_field then return res, "?" end
    local d = res:get_field(AIM.result_field)
    if not d then return res, "none" end
    return res, stems and stems[d:get_address()] or ("decision@" .. string.format("%x", d:get_address()))
end

-- Logs each change of her running decision during an AI-decides order (stem map refreshed with the reapply)
function AIM.track(a, t)
    if not a.stem_by_addr or t - (a.t_stems or 0) > 1.0 then
        a.t_stems = t
        a.stem_by_addr = {}
        local ok, list = pcall(AIM.ai_runtime_decisions, a.pawn)
        if ok then
            for _, e in ipairs(list) do a.stem_by_addr[e.d:get_address()] = e.stem end
        end
    end
    local ok, _, text = pcall(AIM.executing, a.pawn, a.stem_by_addr)
    if not ok then text = "? (" .. tostring(_) .. ")" end
    if text ~= a.exec_text then
        log_line(string.format("[AIDEC] +%.2fs running %s (was %s)", t - a.t_fire, text, tostring(a.exec_text)))
        a.exec_text = text
    end
end

-- Test 36: runs the game's own check of each precondition of our decision (test 35 probe: every condition has
-- evaluate(app.decision.condition.ConditionArg)); used by the charge watch. The arg is built by filling its fields
-- by type from her DecisionModule; evaluate is called only if every object field was filled.
-- Test 37: test 36 left <Owner> (app.AITarget) and <Human> (app.Human) empty. Owner = an AITarget of her
-- (built like our order's target), Human = her Human; tcondition <Target> / <TargetHuman> = `target` (the
-- order's enemy, or her running decision's target); <TargetHuman> may stay empty (monsters are not Human).
function AIM.make_arg(tn, a, d, target)
    local td = sdk.find_type_definition(tn)
    if not td then return nil, tn .. " not found" end
    local m = a.pawn["<AIDecisionMaker>k__BackingField"]:get_field("<DecisionModule>k__BackingField")
    local own = m:get_field("<Chara>k__BackingField")
    local own_human = own and own:get_field("<Human>k__BackingField")
    local by_name = {
        ["<Valid>k__BackingField"] = true,
        ["<Owner>k__BackingField"] = own and create_ai_target(own),
        ["<Human>k__BackingField"] = own_human, ["<OwnerHuman>k__BackingField"] = own_human,
        ["<Target>k__BackingField"] = target and create_ai_target(target),
        ["<TargetHuman>k__BackingField"] = target and target:get_field("<Human>k__BackingField"),
    }
    local optional = { ["<TargetHuman>k__BackingField"] = true }
    local by_type = {
        ["app.Character"] = m:get_field("<Chara>k__BackingField"),
        ["app.DecisionEvaluationModule"] = m, ["app.AIDecisionModule"] = m,
        ["app.AIBlackBoardController"] = m:get_field("<Blackboard>k__BackingField"),
        ["via.GameObject"] = m:get_field("<Owner>k__BackingField"),
        ["app.AIDecisionMaker"] = m:get_field("<AIDecisionMaker>k__BackingField"),
        ["app.ActionInterface"] = m:get_field("<ActionInterface>k__BackingField"),
        ["app.Personality"] = m:get_field("<Personality>k__BackingField"),
        ["app.AIDecision"] = d,
    }
    local arg = td:is_value_type() and ValueType.new(td) or sdk.create_instance(tn, true)
    if not arg then return nil, "could not create " .. tn end
    local parts, missing = {}, 0
    local t = td
    while t and t:get_full_name() ~= "System.Object" and t:get_full_name() ~= "System.ValueType" do
        for _, f in ipairs(t:get_fields()) do
            if not f:is_static() then
                local ftd = f:get_type()
                local ftn = ftd:get_full_name()
                local v = by_name[f:get_name()]
                if v == nil then v = by_type[ftn] end
                if v == nil and optional[f:get_name()] then
                    parts[#parts + 1] = f:get_name() .. ":" .. ftn .. "=empty (optional)"
                elseif v ~= nil then
                    arg:set_field(f:get_name(), v)
                    parts[#parts + 1] = f:get_name() .. ":" .. ftn .. "=set"
                elseif ftd:is_value_type() then
                    parts[#parts + 1] = f:get_name() .. ":" .. ftn .. "=default"
                else
                    missing = missing + 1
                    parts[#parts + 1] = f:get_name() .. ":" .. ftn .. "=MISSING"
                end
            end
        end
        t = t:get_parent_type()
    end
    return (missing == 0) and arg or nil, table.concat(parts, ", ")
end
AIM.arg_logged = {}
-- The game's own checks of decision `e` (Preconditions, then TargetPreconditions on `target`): returns a list of
-- { name, ok = true/false/nil (nil = error or not run) }, or nil + why
AIM.COND_LISTS = { { "<Preconditions>k__BackingField", "app.decision.condition.ConditionArg", "" },
                   { "<TargetPreconditions>k__BackingField", "app.decision.tcondition.ConditionArg", "target " } }
function AIM.eval_decision(a, e, target)
    local res = {}
    for _, cl in ipairs(AIM.COND_LISTS) do
        local okm, arg, desc = pcall(AIM.make_arg, cl[2], a, e.d, target)
        if not AIM.arg_logged[cl[2]] then
            AIM.arg_logged[cl[2]] = true
            log_line(string.format("[PROBE] %s fields: %s", cl[2], okm and tostring(desc) or ("error " .. tostring(arg))))
        end
        if okm and arg then
            local c = e.d:get_field(cl[1])
            for k = 0, (c and c:get_field("_size") or 0) - 1 do
                local cond = c:get_field("_items")[k]
                local name = cond:get_type_definition():get_name()
                for _, fld in ipairs({ "_State", "_BattleState" }) do
                    local okf, v = pcall(cond.get_field, cond, fld)
                    if okf and v ~= nil then name = name .. "(" .. tostring(v) .. ")" end
                end
                local okn, neg = pcall(cond.get_field, cond, "_Not")
                if okn and neg then name = "not " .. name end
                local oke, r = pcall(function() return cond:call("evaluate(" .. cl[2] .. ")", arg) end)
                res[#res + 1] = { name = cl[3] .. name, ok = oke and (r == true) or nil, err = not oke and tostring(r) or nil }
            end
        else
            res[#res + 1] = { name = cl[3] .. "(not run: arg not complete)", ok = nil }
        end
    end
    return res
end
function AIM.cond_text(res)
    local parts = {}
    for _, r in ipairs(res) do
        parts[#parts + 1] = string.format("%s=%s", r.name, r.ok == nil and ("? " .. (r.err or "")) or tostring(r.ok))
    end
    return table.concat(parts, ", ")
end
-- Test 37: her running decision's target character (DecisionEvaluationResult field of AITarget type), or nil
function AIM.ai_target(a)
    local ok, chara = pcall(function()
        local res = AIM.executing(a.pawn)
        if not res or type(res) == "string" then return nil end
        if AIM.result_target == nil then
            AIM.result_target = false
            for _, f in ipairs(res:get_type_definition():get_fields()) do
                local ftd = f:get_type()
                if not f:is_static() and (ftd:get_full_name() == "app.AITarget" or ftd:is_a("app.AITarget")) then
                    AIM.result_target = f:get_name()
                    log_line("[AIDEC] target field of DecisionEvaluationResult = " .. AIM.result_target)
                    break
                end
            end
        end
        if not AIM.result_target then return nil end
        local t = res:get_field(AIM.result_target)
        return t and t:get_field("<Character>k__BackingField")
    end)
    return ok and chara or nil
end

-- Test 37 (user picked a + b after test 36: HolyGlare and Meteoron sat in Prepare 16-20 s, the fight was likely
-- over). During the charge (start seen, no Ready yet), every WATCH_EVERY s:
--   (a) enemy orders: the target died, or no enemy is alive within WATCH_RANGE m -> order over at once;
--   (b) AI-decides orders: her decision's own game checks (Preconditions + TargetPreconditions, all logged);
--       a target check or PawnBattleState false for WATCH_HOLD s in a row -> order over (one false read is not
--       enough). Errors / not run never end it.
-- The charge deadline stays as a safety net. Menu: charge_checks.
AIM.WATCH_EVERY = 0.5
AIM.WATCH_HOLD = 1.0
AIM.WATCH_RANGE = 60.0
-- true = order over, why in AIM.charge_watch_why (errors never end it)
function AIM.charge_watch(a, t)
    local ok, why = pcall(AIM.charge_reason, a, t)
    if not ok then
        if not a.watch_err then
            a.watch_err = true
            log_line("[WARN] charge watch: " .. tostring(why))
        end
        return false
    end
    AIM.charge_watch_why = why
    return why ~= nil
end
function AIM.charge_reason(a, t)
    if t - (a.t_watch or 0) < AIM.WATCH_EVERY then return nil end
    a.t_watch = t
    local o = ORDERS[a.skill]
    if o.target == "enemy" then
        local tgt = a.target or (a.mode == "ai" and AIM.ai_target(a)) or nil
        if tgt and is_dead(tgt) then
            return string.format("target %s died during the charge", chara_name(tgt))
        end
        local okl, list = pcall(alive_enemies)
        if okl then
            local near = false
            for _, en in ipairs(list) do
                local okd, d = pcall(distance, a.pawn, en)
                if okd and d <= AIM.WATCH_RANGE then near = true break end
            end
            if not near then return string.format("no enemy alive within %.0fm during the charge", AIM.WATCH_RANGE) end
        end
    end
    if a.mode == "ai" and a.mine then
        local okl, list = pcall(AIM.ai_runtime_decisions, a.pawn)
        if not okl then return nil end
        local tgt = a.target or AIM.ai_target(a)
        for _, e in ipairs(list) do
            if a.mine[e.d:get_address()] then
                local res = AIM.eval_decision(a, e, tgt)
                local text = AIM.cond_text(res)
                if text ~= a.watch_text then
                    a.watch_text = text
                    log_line(string.format("[WATCH] +%.2fs %s game checks: %s", t - a.t_fire, e.stem, text))
                end
                -- only target checks and the battle state end it: the other preconditions gate the start of the
                -- decision and may turn false while she runs it (e.g. "not State 1014"); they are only logged
                local failed = nil
                for _, r in ipairs(res) do
                    if r.ok == false and (r.name:find("^target ") or r.name:find("PawnBattleState", 1, true)) then
                        failed = r.name
                        break
                    end
                end
                if not failed then
                    a.t_fail = nil
                elseif not a.t_fail then
                    a.t_fail = t
                elseif t - a.t_fail >= AIM.WATCH_HOLD then
                    return string.format("game check %s false for %.1fs during the charge", failed, t - a.t_fail)
                end
                return nil
            end
        end
    end
    return nil
end

-- Test 36 (DEV): her stamina at each order and at its end (user: pawns fall tired after many orders; test 35:
-- 3 orders failed while she was in the out-of-stamina animation). StaminaManager read as DD2gether does.
function AIM.stamina_text(chara)
    local ok, s = pcall(function()
        local sm = chara:call("get_StaminaManager")
        local cur, mx = sm:call("get_RemainingAmount"), sm:call("get_MaxValue")
        return string.format("%.0f/%.0f (%.0f%%)", cur, mx, mx > 0 and cur * 100 / mx or 0)
    end)
    return ok and s or "?"
end

-- Test 37: her AI's stamina mode (app.AIStaminaManager.State: 0 None, 1 FullPower, 2 SavedPower, 4 Breaktime;
-- path from Custom Difficulty Tweaks). Logged next to the stamina.
AIM.AI_STAMINA = { [0] = "None", [1] = "FullPower", [2] = "SavedPower", [4] = "Breaktime" }
function AIM.ai_stamina_text(chara)
    local ok, s = pcall(function()
        local st = AIM.pawn_object(chara):get_field("<AIStaminaManager>k__BackingField"):get_field("<State>k__BackingField")
        return AIM.AI_STAMINA[st] or tostring(st)
    end)
    return ok and s or "?"
end

-- Test 37 (user: cost from the game, never by casting each skill and reading the log): stamina cost of a skill.
-- Her action tree (ActionManager.Fsm layers 0/1, walked like Skill Maker does) gives each node's
-- app.ConsumeStaminaAction DataId; CharacterManager.HumanParam.StaminaParam holds the value of each id
-- (JobNNStaminaParameter.user: ID, Type, Value, Rate, MinValue, IsCustomSkill; Job03 Firestorm-like 130-400,
-- Job06 6008 Type 1 = -500 with MinValue -700, and test 36 measured Meteoron ~690 -> Type 1 costs MinValue).
-- A skill's nodes = node names holding its enum stem (or its ORDERS keys); cost = the biggest one-shot cost
-- among them. Not mastered (Level ~= 2) x1.5 (from _NickCore). Read once per character, logged as [COST].
AIM.cost_ids = nil   -- DataId -> { value, type, min, rate, custom }
AIM.cost_nodes = {}  -- character address -> { { node, id, cont } ... }
AIM.cost_skill = {}  -- character address .. ":" .. skill id -> { cost, src } (or false = unknown)
function AIM.stamina_ids()
    if AIM.cost_ids then return AIM.cost_ids end
    local sp = sdk.get_managed_singleton("app.CharacterManager"):get_field("<HumanParam>k__BackingField")
        :get_field("StaminaParam")
    local ids, seen, n = {}, {}, 0
    local function walk(o, depth)
        if not o or depth > 6 then return end
        local okt, td = pcall(o.get_type_definition, o)
        if not okt or not td then return end
        local addr = o:get_address()
        if seen[addr] then return end
        seen[addr] = true
        local tn = td:get_full_name()
        if td:is_a("app.StaminaParameterBase.Parameter") or tn:find("StaminaParameterAdditional$") then
            local okv, rec = pcall(function()
                local okc, custom = pcall(o.get_field, o, "IsCustomSkill")
                return { id = o:get_field("ID"), value = o:get_field("Value"), type = o:get_field("Type"),
                         min = o:get_field("MinValue"), rate = o:get_field("Rate"), custom = okc and custom or nil }
            end)
            if okv and rec.id then
                ids[rec.id] = rec
                n = n + 1
            end
            return
        end
        if td:is_array() then
            for i = 0, o:get_size() - 1 do pcall(walk, o:get_element(i), depth + 1) end
            return
        end
        local items = nil
        pcall(function() items = o:get_field("_items") end)
        if items and tn:find("List`1", 1, true) then
            for i = 0, (o:get_field("_size") or 0) - 1 do pcall(walk, items[i], depth + 1) end
            return
        end
        local t = td
        while t and not t:get_full_name():find("^System%.") do
            for _, f in ipairs(t:get_fields()) do
                if not f:is_static() and not f:get_type():is_value_type() then
                    pcall(function() walk(o:get_field(f:get_name()), depth + 1) end)
                end
            end
            t = t:get_parent_type()
        end
    end
    walk(sp, 0)
    AIM.cost_ids = ids
    log_line(string.format("[COST] StaminaParam: %d stamina ids read", n))
    return ids
end
function AIM.stamina_nodes(chara)
    local addr = chara:get_address()
    if AIM.cost_nodes[addr] then return AIM.cost_nodes[addr] end
    local out = {}
    -- test 37: 0 nodes on all 3 pawns with no error; each step is now logged (tree found, nodes, actions,
    -- stamina-like action types) to see where the walk stops. Calls as Skill Maker writes them.
    local diag = {}
    local okf, fsm = pcall(function() return chara:call("get_ActionManager"):get_field("Fsm") end)
    if not okf or not fsm then
        diag[#diag + 1] = "no Fsm: " .. tostring(fsm)
    else
        for li = 0, 1 do
            local okt, tree = pcall(function() return fsm:getLayer(li):get_tree_object() end)
            if not okt or not tree then
                diag[#diag + 1] = string.format("layer %d: no tree (%s)", li, tostring(tree))
            else
                local n_nodes, n_acts, n_unl, types = 0, 0, 0, {}
                local count = tree:get_node_count()
                for j = 0, count do
                    local okn, node = pcall(tree.get_node, tree, j)
                    if okn and node then
                        n_nodes = n_nodes + 1
                        local acts = node:get_actions()
                        if not acts[1] then
                            acts = node:get_unloaded_actions()
                            if acts[1] then n_unl = n_unl + 1 end
                        end
                        for _, act in ipairs(acts) do
                            n_acts = n_acts + 1
                            local okty, tn = pcall(function() return act:get_type_definition():get_full_name() end)
                            tn = okty and tn or "?"
                            if tn:lower():find("stamina", 1, true) then types[tn] = (types[tn] or 0) + 1 end
                            if tn == "app.ConsumeStaminaAction" then
                                out[#out + 1] = { node = node:get_name():lower(), id = act:get_field("DataId"),
                                                  cont = act:get_field("IsContinuous") }
                            end
                        end
                    end
                end
                local tl = {}
                for tn, c in pairs(types) do tl[#tl + 1] = tn .. " " .. c end
                diag[#diag + 1] = string.format("layer %d: %d/%d nodes, %d actions (%d nodes unloaded), stamina types {%s}",
                    li, n_nodes, count, n_acts, n_unl, table.concat(tl, ", "))
            end
        end
    end
    AIM.cost_nodes[addr] = out
    log_line(string.format("[COST] %s: %d action-tree nodes consume stamina; %s", pawn_name(chara), #out,
        table.concat(diag, "; ")))
    return out
end
-- Cost discounts she carries (user, after BetterBetterItemDescription: rings and augments change the cost):
-- augments 21 (x0.8, Thief) and 49 (Zeal, _NickCore applies it to skills) by their game value
-- (Human.Parameter.AbilityParam:getParam(id).Value), and rings with special effect 13 (Ring of Grit, -25%)
-- from ItemManager:getEquipData(CharacterID) (ThePawnController / _NickCore). Read every 2 s per character;
-- what was found is logged as [COST] mult when it changes.
AIM.COST_AUGMENTS = { [21] = true, [49] = true }
AIM.RING_COST_SPECIAL = 13
AIM.mult_cache = {} -- character address -> { t, mult, text }
function AIM.cost_mult(chara)
    local addr = chara:get_address()
    local c = AIM.mult_cache[addr]
    local t = now()
    if c and t - c.t < 2.0 then return c.mult end
    local mult, parts = 1.0, {}
    pcall(function()
        local human = chara:get_field("<Human>k__BackingField")
        local job = get_job(chara)
        local abilities = human:get_field("<AbilityContext>k__BackingField"):get_field("EquipedAbilities")[job]
            :get_field("Abilities")
        local okn, n = pcall(abilities.get_size, abilities)
        if not okn then n = abilities:call("get_Count") end
        for i = 0, n - 1 do
            local a = abilities[i]
            local aid = type(a) == "number" and a or a:get_field("value__")
            if AIM.COST_AUGMENTS[aid] then
                local p = human:get_field("Parameter"):get_field("AbilityParam"):call("getParam", aid)
                local v = p:get_field("Value")
                if v and v > 0 and v < 1 then
                    mult = mult * v
                    local okc, cm = pcall(p.get_field, p, "Comment")
                    parts[#parts + 1] = string.format("augment %d x%.2f (%s)", aid, v, okc and tostring(cm) or "")
                end
            end
        end
    end)
    pcall(function()
        local im = sdk.get_managed_singleton("app.ItemManager")
        local equips = im:call("getEquipData", chara:get_field("CharacterID")):get_field("Data"):get_field("Equips")
        for i = 0, equips:get_size() - 1 do
            local okr = pcall(function()
                -- _ItemData may be the item's param itself (_Special on it) or hold its id
                local item = equips:get_element(i):get_field("_ItemData")
                local function fld(o, n)
                    local okf, v = pcall(o.get_field, o, n)
                    return okf and v or nil
                end
                local p, iid = nil, nil
                if item and fld(item, "_Special") ~= nil then
                    p, iid = item, fld(item, "_Id")
                else
                    iid = item and (fld(item, "_ItemId") or fld(item, "_ItemID") or fld(item, "_Id"))
                    p = iid and im:call("getItemData", iid)
                end
                if p and fld(p, "_Special") == AIM.RING_COST_SPECIAL then
                    local v = (p:get_field("_SpecialValue") or 0) / 100
                    mult = mult * (1 - v)
                    parts[#parts + 1] = string.format("ring %s -%.0f%%", tostring(iid), v * 100)
                end
            end)
        end
    end)
    local text = #parts > 0 and table.concat(parts, ", ") or "none"
    if not c or c.text ~= text then
        log_line(string.format("[COST] %s mult x%.2f: %s", pawn_name(chara), mult, text))
    end
    AIM.mult_cache[addr] = { t = t, mult = mult, text = text }
    return mult
end
-- One-shot cost of skill `id` for this character (with her discounts), or nil if unknown. Second value = how.
function AIM.skill_cost(chara, id)
    local base, src = AIM.skill_base_cost(chara, id)
    if not base then return nil end
    local m = AIM.cost_mult(chara)
    return base * m, string.format("%s; discounts x%.2f", src, m)
end
function AIM.skill_base_cost(chara, id)
    local key = string.format("%x:%s", chara:get_address(), tostring(id))
    local c = AIM.cost_skill[key]
    if c == nil then
        c = false
        local ok, e = pcall(function()
            local s = SKILLS[id]
            local enum = s and s.enum
            if not enum then return end
            local job = enum:match("^(Job%d%d)_") and enum:match("^(Job%d%d)_"):lower()
            local stems = { (enum:match("_(.+)$") or enum):lower() }
            for _, k in ipairs(ORDERS[id] and ORDERS[id].keys or {}) do stems[#stems + 1] = k end
            local ids = AIM.stamina_ids()
            local best, parts = nil, {}
            for _, nd in ipairs(AIM.stamina_nodes(chara)) do
                local hit = false
                for _, st in ipairs(stems) do
                    if nd.node:find(st, 1, true) and (not job or nd.node:find(job, 1, true)) then hit = true break end
                end
                local p = hit and ids[nd.id]
                if p then
                    local v = (p.type == 1) and math.max(math.abs(p.value), math.abs(p.min)) or math.abs(p.value)
                    parts[#parts + 1] = string.format("%s id %d %s%.0f", nd.node, nd.id, nd.cont and "continuous " or "", v)
                    if not nd.cont and (not best or v > best) then best = v end
                end
            end
            local mult = 1.0
            pcall(function()
                local list = chara:get_field("<Human>k__BackingField"):get_field("<SkillContext>k__BackingField")
                    :get_field("EnabledCustomSkills")
                for i = 0, list:get_Count() - 1 do
                    local sk = list[i]
                    if sk.CustomSkillID == id and sk.Level ~= 2 then mult = 1.5 end
                end
            end)
            if best then c = { cost = best * mult, src = string.format("x%.1f; %s", mult, table.concat(parts, ", ")) } end
            log_line(string.format("[COST] %s %s: %s (%s)", pawn_name(chara), enum,
                best and string.format("%.0f", best * mult) or "unknown", #parts > 0 and c and c.src or "no node"))
        end)
        if not ok then log_line("[COST] " .. tostring(id) .. " failed: " .. tostring(e)) end
        AIM.cost_skill[key] = c
    end
    if c then return c.cost, c.src end
    return nil
end
-- true = her stamina is below the skill's cost, false = enough, nil = cost or stamina unknown
function AIM.short_of_stamina(chara, id)
    local cost = id and AIM.skill_cost(chara, id)
    if not cost then return nil end
    local ok, cur = pcall(function() return chara:call("get_StaminaManager"):call("get_RemainingAmount") end)
    if not ok then return nil end
    return cur < cost
end

-- Test 35 (DEV, user: follow her after the order): 10 s of layer and running-decision changes after each order
-- ends (test 34: a 2nd Meteoron charged by her AI right after ours was not in the log)
AIM.FOLLOW_SEC = 10.0
AIM.follow = {}
function AIM.follow_start(a, why)
    local okaddr, addr = pcall(function() return a.pawn:get_address() end)
    if not okaddr then return end
    AIM.follow[addr] = { pawn = a.pawn, name = ORDERS[a.skill].name, t_end = now(), layers = action_layers(a.pawn),
                         stem_by_addr = a.stem_by_addr, t_stems = a.t_stems, exec_text = a.exec_text }
end
function AIM.follow_step(t)
    for addr, f in pairs(AIM.follow) do
        local busy = (AIM.cur == addr and active) or (AIM.ctx[addr] and AIM.ctx[addr].active)
        if busy then
            AIM.follow[addr] = nil
        elseif t - f.t_end > AIM.FOLLOW_SEC then
            log_line(string.format("[AFTER] %s: %.0fs after the end, last layers %s", f.name, AIM.FOLLOW_SEC, f.layers))
            AIM.follow[addr] = nil
        else
            local ok = pcall(function()
                local layers = action_layers(f.pawn)
                if layers ~= f.layers then
                    log_line(string.format("[AFTER] %s +%.2fs layers %s", f.name, t - f.t_end, layers))
                    f.layers = layers
                end
                if not f.stem_by_addr or t - (f.t_stems or 0) > 1.0 then
                    f.t_stems = t
                    f.stem_by_addr = {}
                    local okl, list = pcall(AIM.ai_runtime_decisions, f.pawn)
                    if okl then
                        for _, e in ipairs(list) do f.stem_by_addr[e.d:get_address()] = e.stem end
                    end
                end
                local oke, _, text = pcall(AIM.executing, f.pawn, f.stem_by_addr)
                if oke and text ~= f.exec_text then
                    log_line(string.format("[AFTER] %s +%.2fs running %s (was %s)", f.name, t - f.t_end, text, tostring(f.exec_text)))
                    f.exec_text = text
                end
            end)
            if not ok then AIM.follow[addr] = nil end
        end
    end
end

-- Puts back the DisableFlag of every decision an AI-decides order changed
function AIM.restore_decisions(a)
    if not a or not a.saved_flags then return end
    local n = 0
    for _, s in ipairs(a.saved_flags) do
        if pcall(function() s.d:set_field("<DisableFlag>k__BackingField", s.flags) end) then n = n + 1 end
    end
    log_line(string.format("[AIMODE] %d decision flags restored", n))
    a.saved_flags = nil
end

-- Sets the flags on every runtime decision not handled yet (a.seen by address): ours on, other attack/skill
-- decisions off, and every other decision too (decision 49: moves, normal attacks, interrupters); saved for the
-- restore. Returns new ours, new others, text per new ours, and the stems of the non-skill decisions turned off
-- (by list) for the log.
function AIM.apply(a, list)
    local n_mine, n_others, texts, extra = 0, 0, {}, {}
    for _, e in ipairs(list) do
        local addr = e.d:get_address()
        local mine = AIM.is_mine(e, a.ours, a.fuzzy)
        local attack = AIM.is_attack_stem(e.stem)
        if not a.seen[addr] then
            a.seen[addr] = true
            local f = e.d:get_field("<DisableFlag>k__BackingField")
            a.saved_flags[#a.saved_flags + 1] = { d = e.d, flags = f }
            if mine then
                if a.mine then a.mine[addr] = e.stem end
                e.d:set_field("<DisableFlag>k__BackingField", f & ~AIM.DISABLE_OVERWRITE)
                -- cooldown in frames at 60 Hz, counts down (test 28: 221.99/300 right after a use); zeroed only with F9
                local cd = string.format("%s/%s", tostring(e.d:get_field("<CooldownTimer>k__BackingField")),
                    tostring(e.d:get_field("<CooldownTime>k__BackingField")))
                if enabled.no_cooldown then
                    e.d:set_field("<CooldownTimer>k__BackingField", 0.0)
                    cd = cd .. " -> 0"
                end
                n_mine = n_mine + 1
                texts[#texts + 1] = string.format("%s flags %s cooldown %s", e.stem, tostring(f), cd)
            else
                e.d:set_field("<DisableFlag>k__BackingField", f | AIM.DISABLE_OVERWRITE)
                n_others = n_others + 1
                if not attack then
                    extra[e.list] = extra[e.list] or {}
                    table.insert(extra[e.list], e.stem)
                end
            end
        end
    end
    return n_mine, n_others, texts, extra
end

-- "Main: a, b; Pre: c" for the log
function AIM.extra_text(extra)
    local parts = {}
    for _, ln in ipairs({ "Main", "Pre", "Post" }) do
        if extra[ln] then parts[#parts + 1] = ln .. ": " .. table.concat(extra[ln], ", ") end
    end
    return #parts > 0 and table.concat(parts, "; ") or "none"
end

-- Test 28: the runtime decisions are rebuilt during a fight (her list went 25 -> 49 -> 47 packs) and the new
-- ones come without our flags: Mine Volt ran during an ordered Meteoron. Re-applied every AIM.REAPPLY s.
AIM.REAPPLY = 0.25
-- Test 35: cheap per-frame look at her runtime lists (list, items array, size, first item); a change = rebuilt.
-- Test 34: Saint Drain ran at the same frame a rebuild was seen (+5.07 s, Vortex order): the AI picked it
-- inside the 0.25 s gap before our flags came back.
function AIM.list_sig(pawn)
    local m = pawn["<AIDecisionMaker>k__BackingField"]:get_field("<DecisionModule>k__BackingField")
    local parts = {}
    for _, ln in ipairs({ "Main", "Pre", "Post" }) do
        local list = m:get_field("<" .. ln .. "Decisions>k__BackingField")
        if list then
            local items = list:get_field("_items")
            local first = items and items[0]
            parts[#parts + 1] = string.format("%x:%x:%d:%x", list:get_address(), items and items:get_address() or 0,
                list:get_field("_size") or 0, first and first:get_address() or 0)
        else
            parts[#parts + 1] = "-"
        end
    end
    return table.concat(parts, ";")
end
function AIM.reapply(a, t)
    local oks, sig = pcall(AIM.list_sig, a.pawn)
    local changed = oks and a.list_sig ~= nil and sig ~= a.list_sig
    if oks then a.list_sig = sig end
    if not changed and t - (a.t_reapply or 0) < AIM.REAPPLY then return end
    a.t_reapply = t
    local ok, list = pcall(AIM.ai_runtime_decisions, a.pawn)
    if not ok then return end
    local ok2, n_mine, n_others, _, extra = pcall(AIM.apply, a, list)
    if ok2 and n_mine + n_others > 0 then
        log_line(string.format("[AIMODE] +%.2fs decisions rebuilt: %d of ours on, %d others off again (non-skill %s)",
            t - a.t_fire, n_mine, n_others, AIM.extra_text(extra)))
    elseif not ok2 and not a.reapply_warned then
        a.reapply_warned = true
        log_line("[WARN] reapply: " .. tostring(n_mine))
    end
end

-- Our order is over: AI back on if still off, log why
local function end_active(why)
    if not active then return end
    if not active.ai_on then pcall(function() active.decision:set_Enabled(true) end) end
    local stance_pawn = ORDERS[active.skill].stance and active.pawn
    log_line(string.format("[END] %s +%.2fs: %s%s", ORDERS[active.skill].name, now() - active.t_fire, why,
        DEV and ("; stamina " .. AIM.stamina_text(active.pawn) .. " AI " .. AIM.ai_stamina_text(active.pawn)) or ""))
    AIM.restore_decisions(active)
    if DEV then pcall(AIM.follow_start, active, why) end
    active = nil
    -- a launch stance is left only by an explicit action (APC); sent after `active` is cleared so the guard
    -- lets it through; harmless if she is already out of it
    if stance_pawn then
        pcall(function() stance_pawn["<ActionManager>k__BackingField"]:requestActionCore(0, "NormalLocomotion", 0) end)
    end
    summary()
end

-- Test 33: hit reaction = Character.get_IsDamage() or a hit layer name. Words from _NickCore's is_stagger_node
-- (Nick, Utils/Motion.lua) minus the ones that match our skill layers ("break" = SpellBreak) or are not a hit
-- ("success", "escape", "balance", "bridge", "cliffgrab", "die"). Until test 33 only "dmg" counted.
-- Returns what showed it, or nil.
AIM.HIT_WORDS = { "dmg", "damage", "blown", "tumble", "wince", "repelled", "caught" }
function AIM.staggered(chara, low)
    -- test 35: layers first (test 34: "IsDamage" was returned while DmgShrinkLLL / StunLocomotion were still on,
    -- so the 1 s IsDamage-alone limit fired the retry mid-stagger 4x)
    local layer = AIM.hit_layer(low)
    if layer then return layer end
    local ok, d = pcall(function() return chara:get_IsDamage() end)
    if ok and d == true then return "IsDamage" end
end
-- A hit layer name in `low` (lower-case layers), or nil
function AIM.hit_layer(low)
    for n in low:gmatch("[^|]+") do
        for _, w in ipairs(AIM.HIT_WORDS) do
            if n:find(w, 1, true) then return "layer " .. n end
        end
        -- test 34: StunLocomotion (hit by a stun) has none of the words
        if n:find("stun", 1, true) then return "layer " .. n end
    end
end

function AIM.human_addr(chara)
    local ok, a = pcall(function() return chara:get_field("<Human>k__BackingField"):get_address() end)
    return ok and a or 0
end

-- Charge used by the no-Ready deadline: the pawn's own getPrepareSec (F3) once seen in this order, else the
-- base table (F16)
function AIM.charge(a, o)
    if a.prep then return a.prep, "measured" end
    return o.charge, "table"
end

-- Retry after a hit (F2): the order goes back to the queue and fires once she has been out of the hit
-- reaction for RETRY_CLEAR s; dropped if the reaction lasts past RETRY_WAIT s. At most RETRY_MAX retries per
-- press (a new press of the player resets the count).
AIM.RETRY_MAX = 2
AIM.RETRY_CLEAR = 0.3
AIM.RETRY_WAIT = 5.0
AIM.retry_n = {} -- pawn address -> { skill, n } of the last retry
-- Test 33: one retry was dropped "still in the hit reaction after 5.0s (IsDamage)" after a DmgShrinkS. When only
-- IsDamage is left (no hit layer) for this long, the reaction counts as over (C).
AIM.ISDMG_MAX = 1.0
function AIM.cut_by_hit(why)
    local a = active
    counters.cut = counters.cut + 1
    end_active(why)
    if ORDERS[a.skill].stance or pending then return end
    -- hit during the Cast: the spell may be out already, sending it again could cast it twice
    if a.casting then return log_line(string.format("[RETRY] %s not sent again: hit after the Cast", ORDERS[a.skill].name)) end
    local addr = a.pawn:get_address()
    local r = AIM.retry_n[addr]
    local n = (r and r.skill == a.skill) and r.n + 1 or 1
    if n > AIM.RETRY_MAX then
        return log_line(string.format("[RETRY] %s not sent again: %d retries already", ORDERS[a.skill].name, AIM.RETRY_MAX))
    end
    AIM.retry_n[addr] = { skill = a.skill, n = n }
    pending = { skill = a.skill, pawn = a.pawn, slot = "retry", t_first = now(), after_hit = true, retry = n }
    counters.queued = counters.queued + 1
    log_line(string.format("[RETRY] %s queued (retry %d of %d): fires %.1fs after the hit reaction ends",
        ORDERS[a.skill].name, n, AIM.RETRY_MAX, AIM.RETRY_CLEAR))
end

-- A new order to the same pawn replaces the running one (2nd press, retry): its life ends with an [END] line like
-- any other (0.9.38 log: 12 of 77 orders had no [END], only a [WARN] "replaces")
function AIM.replaced(order)
    log_line(string.format("[END] %s +%.2fs: replaced by %s (%s)", ORDERS[active.skill].name, now() - active.t_fire,
        order.name, active.t_start and "running" or "not started yet"))
    AIM.restore_decisions(active)
end

-- AI-decides order (F8, user after test 26): the AI keeps running and only the ordered skill's own decision is
-- left among its attack/skill decisions, so it picks target, distance and charge release itself (test 26: our
-- way walked Mine Volt up to the enemy and Vortex / Meteoron never cast). Returns false = not in her AI, our way.
function AIM.fire_ai(pawn, skill, reason)
    local order = ORDERS[skill]
    AIM.last_saved = nil
    local ok, list = pcall(AIM.ai_runtime_decisions, pawn)
    if not ok then
        log_line("[AIMODE] AI decisions not readable: " .. tostring(list))
        return false
    end
    local mine_stems, ours, fuzzy = AIM.mine_stems(list, order)
    if not next(mine_stems) then
        log_line(string.format("[AIMODE] %s: no decision for %s among her %d", order.name, ours, #list))
        return false
    end
    if active then AIM.replaced(order) end
    local a = { saved_flags = {}, seen = {}, ours = ours, fuzzy = fuzzy, mine = mine_stems }
    AIM.last_saved = a.saved_flags -- fire() puts these back if this function fails halfway
    local _, n_off, texts, extra = AIM.apply(a, list)
    local decision = pawn["<AIDecisionMaker>k__BackingField"]
    pcall(function() decision:set_Enabled(true) end)
    local am = pawn["<ActionManager>k__BackingField"]
    local keys = {}
    for i, k in ipairs(order.keys) do keys[i] = k end
    -- bb_addr: test 34 logs the packs her AI asks for during the order ([AIPACK]); mine = our decisions by
    -- address (AIM.apply adds the rebuilt ones), to tell whether hers is running (one press, AIM.ai_free)
    local bb_addr = 0
    pcall(function() bb_addr = pawn:get_AIBlackBoardController():get_address() end)
    active = { skill = skill, t_fire = now(), pawn = pawn, am_addr = am:get_address(), decision = decision,
               bb_addr = bb_addr, pack_addr = 0, mode = "ai", saved_flags = a.saved_flags, seen = a.seen,
               ours = ours, fuzzy = fuzzy, mine = mine_stems, t_reapply = now(),
               layers = action_layers(pawn), keys = keys, t_start = nil, ai_on = true,
               had_status = false, status_seen = false }
    active.start_layers = layer_set(active.layers)
    active.start_dmg = AIM.staggered(pawn, active.layers:lower()) ~= nil
    active.human_addr = AIM.human_addr(pawn)
    counters.fired = counters.fired + 1
    counters.ai_mode = counters.ai_mode + 1
    log_line(string.format("[FIRE] %s (%s) to %s, AI decides: ours %s; %d other decisions off; "
        .. "pawn layers %s; AI skill budget %s", order.name, reason, pawn_name(pawn), table.concat(texts, ", "), n_off,
        active.layers, AIM.skill_budget(pawn, true)))
    log_line("[AIMODE] non-skill off: " .. AIM.extra_text(extra))
    return true
end

local function fire(pawn, skill, reason, no_ai)
    local player = get_player()
    if not player then return log_line("[WARN] fire: no player") end
    local order = ORDERS[skill]
    if DEV then
        local cost, src = AIM.skill_cost(pawn, skill)
        log_line(string.format("[STAMINA] %s %s, AI %s, at the %s order; cost %s", pawn_name(pawn), AIM.stamina_text(pawn),
            AIM.ai_stamina_text(pawn), order.name, cost and string.format("%.0f", cost) or "unknown"))
    end
    if order.target == "enemy" and not enabled.cast_in_place and not order.stance and not no_ai then
        local ok, done = pcall(AIM.fire_ai, pawn, skill, reason)
        if not ok then
            err("AIM.fire_ai", done)
            if active and active.mode == "ai" then end_active("AI-decides order failed") end
            AIM.restore_decisions({ saved_flags = AIM.last_saved })
        elseif done then
            return
        elseif order.wait_ai then
            -- test 31: wait for her decision (update() checks every AIM.REAPPLY s, our way after AIM.WAIT_DECISION)
            pending = { skill = skill, pawn = pawn, slot = "?", t_first = now(), wait_decision = true, reason = reason }
            counters.queued = counters.queued + 1
            return log_line(string.format("[QUEUE] %s waits up to %.1fs for her AI decision (%s)", order.name,
                AIM.WAIT_DECISION, reason))
        end
    end
    if no_ai or (order.target == "enemy" and not enabled.cast_in_place and not order.stance) then
        log_line(string.format("[AIMODE] %s: our way", order.name))
    end
    local target = player
    if order.target == "enemy" and enabled.cast_in_place then
        target = pawn
        log_line(string.format("[TARGET] %s -> the pawn herself (F10 cast in place)", order.name))
    elseif order.target == "enemy" then
        local enemy, src, d = pick_enemy(pawn)
        if not enemy then
            counters.no_target = counters.no_target + 1
            return log_line(string.format("[TARGET] %s not used: %s", order.name, src))
        end
        target = enemy
        log_line(string.format("[TARGET] %s -> %s via %s, %.1fm from the pawn", order.name, chara_name(enemy), src, d))
    elseif order.target == "self" then
        target = pawn
    end
    local udata = ai_pack(pawn, order) or get_pack(order)
    if not udata then return err("fire", "pack not loaded: " .. order.pack) end
    if active then AIM.replaced(order) end
    local bb = pawn:get_AIBlackBoardController()
    -- test 6: with the old order still in `active`, the [AIBLOCK] hook skipped our own 2nd-press request
    firing = true
    local ok, e = pcall(function()
        setExecuteMethod:call(nil, bb, udata, create_ai_target(target))
        bb:set_ReqMainActInterPackData(udata)
    end)
    firing = false
    if not ok then return err("fire", e) end
    local decision = pawn["<AIDecisionMaker>k__BackingField"]
    -- AI paused until Ready / Cast / the charge deadline (v0.10, user after test 9; ai_back turns it on)
    local ai_on = false
    decision:set_Enabled(false)
    local am = pawn["<ActionManager>k__BackingField"]
    local boons = player_boons(player)
    local keys = {}
    for i, k in ipairs(order.keys) do keys[i] = k end
    active = { skill = skill, t_fire = now(), pawn = pawn, am_addr = am:get_address(), decision = decision,
               bb_addr = bb:get_address(), pack_addr = udata:get_address(),
               layers = action_layers(pawn), keys = keys, t_start = nil, ai_on = ai_on,
               had_status = order.status ~= nil and boons[order.status] == true, status_seen = false }
    active.start_layers = layer_set(active.layers)
    active.start_dmg = AIM.staggered(pawn, active.layers:lower()) ~= nil
    active.human_addr = AIM.human_addr(pawn)
    if order.target == "enemy" and target ~= pawn then active.target = target end -- charge watch (a)
    counters.fired = counters.fired + 1
    log_line(string.format("[FIRE] %s (%s) to %s, AI %s; pawn layers %s; player boons %s; AI skill budget %s",
        order.name, reason, pawn_name(pawn), ai_on and "stays on" or "paused", active.layers, boons_text(boons),
        AIM.skill_budget(pawn)))
end

-- v0.9.25-0.9.33: one order at a time across the party (an order to another pawn ended ours on the old one).
-- Test 34: one per pawn (AIM.use).
local function same_pawn(a, b)
    return a and b and a:get_address() == b:get_address()
end

-- chord "B"/"LT", arrow = button of BUTTONS[chord]; via = what the player pressed, for the log
local function order(chord, arrow, via)
    local pawn, slot = get_target()
    local source = string.format("%s %s+%s -> %s", via or "chord", chord, arrow, slot)
    if not pawn then return log_line("[WARN] " .. source .. ": no main pawn") end
    AIM.use(pawn:get_address())
    local job, skills = scan(pawn, slot)
    local skill = binding(slot, job, chord, arrow)
    if skill == 0 then
        counters.unbound = counters.unbound + 1
        return log_line(string.format("[KEY] %s: nothing bound for job %s", source, tostring(job)))
    end
    local o = ORDERS[skill]
    if not o then
        counters.no_action = counters.no_action + 1
        return log_line(string.format("[KEY] %s: %s has no known action yet", source, skill_label(skill)))
    end
    if not has_skill(skills, skill) then
        counters.not_equipped = counters.not_equipped + 1
        return log_line(string.format("[KEY] %s %s ignored: not equipped (job %s)", source, o.name, tostring(job)))
    end
    AIM.retry_n[pawn:get_address()] = nil -- a press of the player: retries after a hit count from 0 again (F2)
    if o.stance and active and active.skill == skill then
        pending = nil
        end_active("stance ended by the same order again")
        return
    end
    local t = now()
    local press_key = slot .. ":" .. skill
    local prev = last_press[press_key]
    last_press[press_key] = t
    if prev and t - prev <= INTERRUPT_WINDOW and ((pending and pending.skill == skill) or active ~= nil) then
        counters.interrupts = counters.interrupts + 1
        -- test 31 (user, option b): a 2nd press while the order waits behind her own action cuts that action
        -- first. Test 30: after a cancel her AI picks its next skill in 0.2-0.5 s; here the fire right after turns
        -- every other skill decision off, so the next pick can only be ours.
        local cut = ""
        if pending and pending.skill == skill and not active then
            local layers = action_layers(pawn)
            local okc, e = pcall(function()
                pawn["<ActionManager>k__BackingField"]:requestActionCore(10, "DefaultCancelAction", 0)
            end)
            cut = okc and (", her action cut (" .. layers .. ")") or (", cut failed: " .. tostring(e))
        end
        pending = nil
        return fire(pawn, skill, string.format("%s, interrupt: 2nd press after %.2fs%s", source, t - prev, cut))
    end
    local action = current_action(pawn)
    local layers = action_layers(pawn)
    local ai_skill = skill_layer(layers)
    if not active and not ai_skill and is_free_action(action) then
        pending = nil
        return fire(pawn, skill, source .. ", pawn free: " .. action)
    end
    counters.queued = counters.queued + 1
    if pending then
        log_line(string.format("[QUEUE] %s replaces queued %s", o.name, ORDERS[pending.skill].name))
    end
    pending = { skill = skill, pawn = pawn, slot = slot, t_first = t, start_action = action }
    log_line(string.format("[QUEUE] %s %s queued; our cast busy=%s; AI skill %s; pawn layers %s",
        source, o.name, tostring(active ~= nil), tostring(ai_skill), layers))
end

-- LT + D-pad Left / Up / Right (decision 42)
local function select_target(slot)
    counters.target_picks = counters.target_picks + 1
    local party = party_pawns()
    if not party[slot] then
        return log_line(string.format("[PAWN] %s picked but not in the party; target stays %s", SLOT_LABEL[slot], target_slot))
    end
    target_slot = slot
    local job = scan(party[slot], slot)
    log_line(string.format("[PAWN] target = %s %s (job %s)", slot, pawn_name(party[slot]), tostring(job)))
end

-- LT + D-pad Down: the target pawn drops what it is doing (our order or the AI's action).
-- DefaultCancelAction priority 10 = the request the AI itself uses to cut a forced action (APC list, U7)
local cancel_check = nil -- { pawn, t, slot } layers logged 0.5 s after a cancel
local function cancel_target()
    counters.cancels = counters.cancels + 1
    local pawn, slot = get_target()
    if not pawn then return log_line("[WARN] [PAWN] cancel: no pawn") end
    AIM.use(pawn:get_address())
    local before = action_layers(pawn)
    if pending and same_pawn(pending.pawn, pawn) then
        log_line(string.format("[QUEUE] queued %s dropped by cancel", ORDERS[pending.skill].name))
        pending = nil
    end
    if active and same_pawn(active.pawn, pawn) then end_active("cancelled (LT + Down)") end
    local ok, e = pcall(function()
        pawn["<ActionManager>k__BackingField"]:requestActionCore(10, "DefaultCancelAction", 0)
    end)
    if not ok then return err("cancel", e) end
    cancel_check = { pawn = pawn, t = now(), slot = slot }
    log_line(string.format("[CANCEL] %s %s; layers before %s", slot, pawn_name(pawn), before))
end

---------------------------------------------------------------- pad input (B + D-pad, LT + face buttons / D-pad)

local player_group = enum_value("app.UserInputManager.Group", "Player")
log_line("[PADMAP] UserInputManager.Group.Player = " .. tostring(player_group))

local held_chord = nil -- "B" while held
local lt_down = false  -- LT physically held with the LT chord on (read by the palette HUD)
local pad_prev = 0
local flags_prev = 0
local pad_lines = 0
local swallowing = 0 -- D-pad bits hidden from the game until released
-- LT chord (decision 37): from LT down until LT and every button pressed under it are released, the game sees
-- neither LT (sheathe) nor any button that went down after it; buttons already held before LT pass
local lt_on = false
local lt_pad_base = 0  -- pad bits held before LT
local lt_flag_mask = 0 -- action flags raised by LT / the buttons under it
local lt_learn = 0     -- frames left to collect raised flags after a hidden button went down
local lt_wait = nil    -- { name, t } face button waiting PAIR_WINDOW for its pair

function LTH.hold_time()
    local v = tonumber(config.lt_hold_time) or LTH.DEFAULT
    return math.max(0.0, math.min(1.0, v))
end

local function lt_request(name)
    chord_requests[#chord_requests + 1] = { chord = "LT", arrow = name }
end

-- a face button went down under LT: pairs with the waiting one, else waits for its own pair
local function lt_face(name, t)
    if lt_wait then
        local w = lt_wait
        lt_wait = nil
        if PAIR[w.name][1] == name then return lt_request(PAIR[w.name][2]) end
        lt_request(w.name)
    end
    lt_wait = { name = name, t = t }
end

local function pad_log(text)
    if not DEV then return end -- [PAD] / [LT] are not release tags (0.9.38: only the "log cap reached" warning got out)
    pad_lines = pad_lines + 1
    if pad_lines == PAD_LOG_CAP then log_line("[WARN] [PAD] log cap reached") end
    if pad_lines < PAD_LOG_CAP then log_line(text) end
end

local function clear_bits(input, fields, mask)
    for _, f in ipairs(fields) do
        local v = input:get_field(f) or 0
        if v & mask ~= 0 then input:set_field(f, v & ~mask) end
    end
end

function LTH.set_bits(input, fields, mask)
    for _, f in ipairs(fields) do
        local v = input:get_field(f) or 0
        if v & mask ~= mask then input:set_field(f, v | mask) end
    end
end

-- hold mode: a short LT press, hidden while undecided, is handed to the game as a tap over the next frames
function LTH.tap_frame(input)
    LTH.tap.frame = LTH.tap.frame + 1
    if LTH.tap.frame < 3 then
        LTH.set_bits(input, { "PadButton" }, LT_BITS)
        LTH.set_bits(input, { "ButtonOnFlags" }, LTH.tap.flags)
    end
    if LTH.tap.frame == 1 then
        LTH.set_bits(input, { "PadButtonDown" }, LT_BITS)
        LTH.set_bits(input, { "ButtonTriggerFlags" }, LTH.tap.flags)
    elseif LTH.tap.frame >= 3 then
        LTH.set_bits(input, { "PadButtonUp" }, LT_BITS)
        LTH.set_bits(input, { "ButtonReleaseFlags" }, LTH.tap.flags)
        LTH.tap = nil
    end
end

local function on_player_input(input)
    local pad = input:get_field("PadButton") or 0
    local down = input:get_field("PadButtonDown") or 0
    local flags = input:get_field("ButtonOnFlags") or 0
    local pad_before, flags_before = pad_prev, flags_prev

    -- measurement: pad buttons (sticks' emulated bits masked out) and action flags
    local pad_low = pad & 0xFFFFF
    if pad_low ~= pad_prev then
        pad_log(string.format("[PAD] pad 0x%X (%s) on=+0x%X off=+0x%X", pad_low, bit_names(pad_low),
            pad_low & ~pad_prev, pad_prev & ~pad_low))
        pad_prev = pad_low
    end
    if flags ~= flags_prev then
        pad_log(string.format("[PAD] actionflags 0x%X on=+0x%X off=+0x%X", flags, flags & ~flags_prev,
            flags_prev & ~flags))
        flags_prev = flags
    end

    local lt_phys = chord_on("LT") and LT_BITS ~= 0 and pad & LT_BITS ~= 0
    AIM.rb_now = (BTN.RTrigTop or 0) ~= 0 and pad & BTN.RTrigTop ~= 0
    if lt_phys and (AIM.rb_now or LTH.rb_prev) then
        if not LTH.blocked then
            log_line("[HUD] RB/LT overlap: player ability priority until LT is released")
            log_flush()
        end
        LTH.blocked = true
    elseif not lt_phys then
        LTH.blocked = false
    end
    LTH.rb_prev = AIM.rb_now
    if LTH.blocked then
        LTH.press_t, LTH.open, LTH.tap = nil, false, nil
        lt_down, lt_on, lt_wait = false, false, nil
        lt_flag_mask, lt_learn = 0, 0
        return -- leave RB, LT and face buttons untouched for the player
    end
    if lt_phys then
        if not LTH.press_t then
            LTH.press_t = now()
            LTH.open = config.lt_hold ~= true
        end
        -- hold mode: held long enough, or a chord button pressed under LT (cannot be a tap any more)
        if not LTH.open and (now() - LTH.press_t >= LTH.hold_time() or down & LTH.chord_bits ~= 0) then
            LTH.open = true
            log_line(string.format("[HUD] orders opened: %s, held %.3f s, down=0x%X",
                down & LTH.chord_bits ~= 0 and "chord" or "hold", now() - LTH.press_t, down))
            log_flush()
            pad_log(string.format("[LT] hold: orders open after %.2f s", now() - LTH.press_t))
        end
    else
        if LTH.press_t and not LTH.open and lt_on then
            -- short press: give the game its LT tap back with the flags LT raised (learned below)
            LTH.tap = { flags = lt_flag_mask, frame = 0 }
            pad_log(string.format("[LT] tap after %.2f s; replayed to the game (flags 0x%X)", now() - LTH.press_t,
                lt_flag_mask))
        end
        LTH.press_t = nil
        LTH.open = false
    end
    local lt_held = lt_phys and LTH.open
    lt_down = lt_held
    if lt_phys and not lt_on then
        lt_on = true
        LTH.tap = nil
        lt_pad_base = pad_before & ~LT_BITS
        lt_flag_mask = 0
        lt_learn = 0
        pad_log(string.format("[LT] down; pad held before passes: 0x%X", lt_pad_base))
    end
    if lt_on then
        local pad_mask = 0xFFFFF & ~lt_pad_base -- LT and every button pressed after it (sticks' bits pass)
        local new_pad = down & pad_mask
        if new_pad ~= 0 then lt_learn = 2 end
        local new_face = lt_held and new_pad or 0
        local t = now()
        for bit, name in pairs(FACE_NAME) do
            if new_face & bit ~= 0 then lt_face(name, t) end
        end
        -- LT + D-pad: pick the target pawn / cancel its action (decision 42); the pawn command flags
        -- (Go/Wait/Help/To me) are hidden with the rest until everything under LT is released
        local new_dpad = new_face & DPAD_BITS
        if new_dpad ~= 0 then
            lt_flag_mask = lt_flag_mask | PAWN_COMMAND_FLAGS
            for bit, dir in pairs(DPAD_NAME) do
                if new_dpad & bit ~= 0 then chord_requests[#chord_requests + 1] = { dpad = dir } end
            end
        end
        -- action flags raised on the frame a hidden button went down (and the next one) are hidden too;
        -- flags from the sticks on other frames pass, so the player keeps moving
        if lt_learn > 0 then
            lt_learn = lt_learn - 1
            local raised = flags & ~flags_before & ~lt_flag_mask
            if raised ~= 0 then
                lt_flag_mask = lt_flag_mask | raised
                pad_log(string.format("[LT] hiding flags +0x%X (now 0x%X)", raised, lt_flag_mask))
            end
        end
        -- hidden this frame even on the release frame (the game may act on release)
        clear_bits(input, PAD_FIELDS, pad_mask)
        clear_bits(input, FLAG_FIELDS, lt_flag_mask)
        counters.lt_hidden = counters.lt_hidden + 1
        if not lt_held and pad_low & pad_mask == 0 then
            lt_on = false
            pad_log("[LT] released; game input back")
        end
    end

    -- the waiting face button orders alone when the pair window ends or it is let go
    if lt_wait and (now() - lt_wait.t >= PAIR_WINDOW or pad & FACE_BIT[lt_wait.name] == 0) then
        lt_request(lt_wait.name)
        lt_wait = nil
    end

    local b_held = chord_on("B") and not lt_on and BTN.RRight and pad & BTN.RRight ~= 0
    held_chord = b_held and "B" or nil
    local new_dpad = down & DPAD_BITS
    if held_chord and new_dpad ~= 0 then
        for bit, arrow in pairs(DPAD_NAME) do
            if new_dpad & bit ~= 0 then
                chord_requests[#chord_requests + 1] = { chord = held_chord, arrow = arrow }
            end
        end
        swallowing = swallowing | new_dpad
    end
    if swallowing ~= 0 then
        local held = pad & swallowing
        local mask = swallowing
        -- keep hiding until the D-pad is released (the game may act on release)
        clear_bits(input, PAD_FIELDS, mask)
        clear_bits(input, FLAG_FIELDS, PAWN_COMMAND_FLAGS)
        counters.swallowed = counters.swallowed + 1
        if held == 0 then swallowing = 0 end
    end
    if LTH.tap and not lt_on then LTH.tap_frame(input) end
end

if player_group ~= nil then
    sdk.hook(sdk.find_type_definition("app.UserInput"):get_method("update"),
        function(args)
            local s = thread.get_hook_storage()
            s.input = nil
            local input = sdk.to_managed_object(args[2])
            if input and input:call("get_Group") == player_group then s.input = input end
        end,
        function(retval)
            local input = thread.get_hook_storage().input
            if input then
                local ok, e = pcall(on_player_input, input)
                if not ok then err("pad", e) end
            end
            return retval
        end)
else
    log_line("[ERR] Player input group unresolved; pad chords off")
end

---------------------------------------------------------------- keyboard poll

local capturing = nil   -- { chord, arrow, was_down } while the menu waits for a key
local kb_was_down = {}  -- vk -> down last frame (bound keys only)

local function poll_capture()
    local c = capturing
    for vk = 1, 0xFE do
        local down = reframework:is_key_down(vk)
        if down and not c.was_down[vk] then
            if vk == 0x1B then
                capturing = nil
                return set_key(c.chord, c.arrow, nil)
            end
            if not VK_SKIP[vk] and not TOGGLE_KEYS[vk] then
                capturing = nil
                kb_was_down[vk] = true -- the press that picked the key does not order
                return set_key(c.chord, c.arrow, vk)
            end
        end
        c.was_down[vk] = down
    end
end

local function poll_keys()
    if capturing then return poll_capture() end
    for _, chord in ipairs(scheme().chords) do
        for _, arrow in ipairs(BUTTONS[chord]) do
            local vk = key_of(chord, arrow)
            if vk then
                local down = reframework:is_key_down(vk)
                if down and not kb_was_down[vk] then
                    counters.keys = counters.keys + 1
                    order(chord, arrow, "key " .. vk_name(vk))
                end
                kb_was_down[vk] = down
            end
        end
    end
    -- same as LT + D-pad: Left / Up / Right pick the target pawn, Down cancels its action
    for _, arrow in ipairs(TARGET_KEYS) do
        local vk = key_of("Target", arrow)
        if vk then
            local down = reframework:is_key_down(vk)
            if down and not kb_was_down[vk] then
                counters.keys = counters.keys + 1
                if TARGET_DPAD[arrow] then select_target(TARGET_DPAD[arrow]) else cancel_target() end
            end
            kb_was_down[vk] = down
        end
    end
end

---------------------------------------------------------------- per frame

local scan_failed = {}

-- Test 34, one press (user: "one press always goes 2nd in line, she only ends what she is doing"):
-- a queued order waits for her own skill up to AIM.QUEUE_PATIENT s (was 2 s), a running skill
-- decision of hers counts as her skill (AIM.busy_decision), and an AI-decides order her AI does not take once she
-- is free for AIM.FREE_WAIT s goes our way (AIM.ai_free; not Meteoron / Vortex, our way never cast them).
AIM.QUEUE_PATIENT = 6.0
AIM.FREE_WAIT = 1.0

-- "decision <stem>" when her running decision is a skill one other than the queued order's, else nil.
-- Read every AIM.REAPPLY s per queued order.
function AIM.busy_decision(pawn, p, t)
    if t - (p.t_dec or 0) < AIM.REAPPLY then return p.dec end
    p.t_dec, p.dec = t, nil
    local ok, list = pcall(AIM.ai_runtime_decisions, pawn)
    if not ok then return nil end
    local stems = {}
    for _, e in ipairs(list) do stems[e.d:get_address()] = e.stem end
    local ok2, _, text = pcall(AIM.executing, pawn, stems)
    if not ok2 or type(text) ~= "string" or not AIM.is_attack_stem(text) then return nil end
    for _, s in pairs((AIM.mine_stems(list, ORDERS[p.skill]))) do
        if s == text then return nil end -- already ours: fire, nothing to wait for
    end
    p.dec = "decision " .. text
    return p.dec
end

-- AI-decides order not started: true once she has been free (no skill layer, our decision not running) for
-- AIM.FREE_WAIT s
function AIM.ai_free(a, t, layers)
    local ok, _, text = pcall(AIM.executing, a.pawn, a.mine)
    local ours = ok and type(text) == "string" and text ~= "none" and text ~= "?" and not text:find("^decision@")
    if ours or skill_layer(layers) then
        a.t_free = nil
        return false
    end
    a.t_free = a.t_free or t
    return t - a.t_free >= AIM.FREE_WAIT
end

-- The order and queue of one pawn (the one AIM.use put in active / pending)
function AIM.step(t, boons)
    if active then
        if active.mode == "ai" then
            AIM.reapply(active, t)
            if DEV then AIM.track(active, t) end
        end
        local layers = action_layers(active.pawn)
        local prev = active.layers
        if layers ~= active.layers then
            log_line(string.format("[ACT] +%.2fs pawn layers %s", t - active.t_fire, layers))
            active.layers = layers
        end
        local prev_set = layer_set(prev:lower())
        local o = ORDERS[active.skill]
        local low = layers:lower()
        local el = t - active.t_fire
        -- boon on the player: logged only (F6), the order's life follows the action layers
        if o.status and not active.status_seen and boons[o.status] and not active.had_status then
            active.status_seen = true
            counters.landed = counters.landed + 1
            log_line(string.format("[LANDED] %s +%.2fs (status seen)", o.name, el))
        end
        local in_skill = has_key(low, active.keys)
        -- test 27: fired behind the AI's own Meteoron (same skill), its Prepare/Ready layers counted as our start
        -- and Ready at +0.01 s, and our 3.3 s Ready cap then ended the order while she charged again. Start = a
        -- skill layer that was not there at the order, or our skill's request seen by the guard hook (a restart
        -- of the same skill keeps the layer name); Ready / Cast count only on the frame their layer appears.
        local in_new = active.req_key and in_skill
        for n in layers:gmatch("[^|]+") do
            if in_new then break end
            if not active.start_layers[n] and has_key(n:lower(), active.keys) then in_new = true end
        end
        -- test 33: a hit reaction already on at the order is not a cut; once it is over, the next one is
        local hit = AIM.staggered(active.pawn, low)
        if active.start_dmg then
            if not hit then active.start_dmg = false end
            hit = nil
        end
        if in_skill and not active.casting and not o.stance then
            -- past Prepare/Ready: the guard lets go so the skill can end on its own (test 4: with the guard
            -- on, Job03_CastIceBoon stayed until the AI came back)
            for n in low:gmatch("[^|]+") do
                local appeared = not prev_set[n]
                if appeared and has_key(n, active.keys) and n:find("ready", 1, true) and not active.t_ready then
                    active.t_ready = t
                    log_line(string.format("[READY] %s +%.2fs charged (%s); %.2fs after start, getPrepareSec %s, table %s",
                        o.name, el, n, active.t_start and t - active.t_start or -1,
                        active.prep and string.format("%.2f", active.prep) or "not seen", tostring(o.charge)))
                    if o.release_ai then ai_back("Ready: the cast command runs its own charge hold") end
                end
                if appeared and has_key(n, active.keys) and not n:find("prepare", 1, true) and not n:find("ready", 1, true) then
                    active.casting = true
                    active.t_cast = t
                    log_line(string.format("[CAST] %s +%.2fs %s, %s, guard off, AI %s", o.name, el, n,
                        active.t_ready and string.format("%.2fs after Ready", t - active.t_ready) or "no Ready seen",
                        active.ai_on and "already on" or "was off"))
                    ai_back("cast")
                    break
                end
            end
        end
        if not active.t_start then
            local generic, stem
            -- test 28: in F8 orders the generic start took the AI's Magic Barrier and Mine Volt as our Meteoron;
            -- there the skill's own name is the only start
            if not in_new and not KEYS_SEEN[active.skill] and active.mode ~= "ai" then
                generic, stem = new_job_layer(layers, active.start_layers)
            end
            if in_new or generic then
                if generic then
                    active.keys[#active.keys + 1] = stem
                    log_line(string.format("[START] %s generic: new layer %s, key '%s' (add to ORDERS)", o.name, generic, stem))
                end
                active.t_start = t
                counters.started = counters.started + 1
                log_line(string.format("[START] %s +%.2fs, AI %s%s (%s)", o.name, el, active.ai_on and "on" or "still off",
                    o.charge and string.format(", order over without Ready by +%.1fs after start",
                        o.charge / SLOWEST_RATE + CHARGE_SLACK) or "", layers))
            elseif hit then
                AIM.cut_by_hit("cut by a hit before it started (" .. hit .. "; " .. layers .. ")")
            elseif active.mode == "ai" and (not o.wait_ai or active.skill == 69) and AIM.ai_free(active, t, layers) then
                -- test 34 (one press): her AI did not take our decision once she was free; our way now
                local p = active
                counters.fallbacks = counters.fallbacks + 1
                end_active(string.format("her AI did not take it %.1fs after she was free (%s), our way now",
                    AIM.FREE_WAIT, layers))
                fire(p.pawn, p.skill, "one press: her AI did not take it", true)
            elseif active.mode ~= "ai" and low:find("outofstamina", 1, true) then
                counters.no_start = counters.no_start + 1
                end_active(string.format("out of stamina before it started (%s)", layers))
            elseif el >= AIM.START_MAX then
                counters.no_start = counters.no_start + 1
                end_active(string.format("did not start in %.1fs, order dropped (%s)", el, layers))
            end
        elseif hit then
            -- test 3: DmgShrinkS cut the Fire Boon, the queue then waited for nothing
            AIM.cut_by_hit("cut by a hit (" .. hit .. "; " .. layers .. ")")
        elseif not in_skill then
            -- test 33: the last request the hook saw on her says who ended it (AI cancel, her next action...)
            counters.ended = counters.ended + 1
            end_active(string.format("skill action over after %.2fs running (%s); last request %s", t - active.t_start,
                layers, active.last_req or "none seen"))
        elseif not active.t_ready and not active.casting and AIM.charge_watch(active, t) then
            counters.watch_end = counters.watch_end + 1
            end_active(AIM.charge_watch_why .. " (" .. layers .. ")")
        elseif active.mode ~= "ai" and o.charge and not active.t_ready and not active.casting
               and t - active.t_start >= AIM.charge(active, o) / SLOWEST_RATE + CHARGE_SLACK then
            local c, src = AIM.charge(active, o)
            end_active(string.format("no Ready %.1fs after the start (charge %.2f %s / %.2f + %.1f), let go (%s)",
                t - active.t_start, c, src, SLOWEST_RATE, CHARGE_SLACK, layers))
        elseif active.mode ~= "ai" and active.t_ready and not active.casting
               and t - active.t_ready >= (o.ready_max or (o.release_ai and READY_MAX_AI or READY_MAX)) then
            end_active(string.format("charged %.1fs without casting, let go (%s)",
                o.ready_max or (o.release_ai and READY_MAX_AI or READY_MAX), layers))
        elseif active.t_cast and t - active.t_cast >= CAST_STUCK then
            end_active(string.format("Cast layer still on %.0fs after Cast, let go (%s)", CAST_STUCK, layers))
        elseif el >= ORDER_MAX then
            end_active(string.format("still running after %.0fs, let go (%s)", ORDER_MAX, layers))
        end
    end

    if pending then
        local pawn = pending.pawn
        local action = current_action(pawn)
        local waited = t - pending.t_first
        local reason
        local ai_skill = not active and skill_layer(action_layers(pawn))
        -- test 34 (one press): a skill decision of hers already running counts as her skill, even before its layer
        -- shows (test 33: 4 AI-decides orders fired while her own Saint Drain / Meteoron / Violent Stab decision
        -- was running; the flags do not stop a running decision and ours never came)
        if not ai_skill and not active and not pending.after_hit and not pending.wait_decision then
            ai_skill = AIM.busy_decision(pawn, pending, t)
        end
        if pending.after_hit then
            -- test 33 (F2): sent again once she has been out of the hit reaction for AIM.RETRY_CLEAR s
            local why = AIM.staggered(pawn, action_layers(pawn):lower())
            -- C: IsDamage alone (no hit layer) for AIM.ISDMG_MAX s counts as over
            if why == "IsDamage" then
                pending.t_isdmg = pending.t_isdmg or t
                if t - pending.t_isdmg >= AIM.ISDMG_MAX then
                    if not pending.isdmg_logged then
                        pending.isdmg_logged = true
                        log_line(string.format("[RETRY] %s: IsDamage still on %.1fs after the hit layers ended (%s), counted as over",
                            ORDERS[pending.skill].name, AIM.ISDMG_MAX, action_layers(pawn)))
                    end
                    why = nil
                end
            else
                pending.t_isdmg = nil
            end
            if active or is_dead(pawn) then
                log_line(string.format("[RETRY] %s dropped: %s", ORDERS[pending.skill].name,
                    active and "another order is running" or "pawn down"))
                pending = nil
            elseif why then
                pending.t_clear = nil
                if waited > AIM.RETRY_WAIT then
                    log_line(string.format("[RETRY] %s dropped: still in the hit reaction after %.1fs (%s)",
                        ORDERS[pending.skill].name, waited, why))
                    pending = nil
                end
            else
                pending.t_clear = pending.t_clear or t
                if t - pending.t_clear >= AIM.RETRY_CLEAR then
                    local p = pending
                    pending = nil
                    counters.retries = counters.retries + 1
                    fire(pawn, p.skill, string.format("retry %d after a hit, %.2fs after the cut, pawn in %s",
                        p.retry, waited, action))
                end
            end
        elseif pending.wait_decision then
            -- test 31: waiting for her AI decision (fire() set this); our way once the wait is over
            if waited > AIM.WAIT_DECISION then
                local p = pending
                pending = nil
                fire(pawn, p.skill, string.format("%s; no AI decision after %.1fs", p.reason, waited), true)
            elseif t - (pending.t_check or 0) >= AIM.REAPPLY then
                pending.t_check = t
                local okl, list = pcall(AIM.ai_runtime_decisions, pawn)
                if okl and next((AIM.mine_stems(list, ORDERS[pending.skill]))) then
                    local p = pending
                    pending = nil
                    fire(pawn, p.skill, string.format("%s; her decision came after %.2fs", p.reason, waited))
                end
            end
        elseif active then
            -- behind our own skill: wait for it to end (U11), not forever
            if waited > QUEUE_BEHIND_OURS then reason = string.format("queue, ours still running after %.1fs", waited) end
        elseif ai_skill then
            -- behind the AI's own skill: wait until it is over; a 2nd press of the same order cuts it
            if ai_skill ~= pending.ai_skill then
                pending.ai_skill = ai_skill
                log_line(string.format("[QUEUE] waiting for AI skill %s (+%.2fs)", ai_skill, waited))
            end
            -- test 34 (one press): she ends her own skill first, up to AIM.QUEUE_PATIENT s (user: one press = next
            -- in line, a 2nd press cuts now)
            if waited > AIM.QUEUE_PATIENT then
                reason = string.format("queue, AI skill %s still on after %.1fs", ai_skill, waited)
            end
        elseif AIM.hit_layer(action_layers(pawn):lower()) and waited <= QUEUE_TIMEOUT then
            -- test 35: she is staggered or down (test 34: Fire Boon fired in DmgDownLoop and never started)
            if not pending.hit_logged then
                pending.hit_logged = true
                log_line(string.format("[QUEUE] %s waits: she is in a hit reaction (%s)", ORDERS[pending.skill].name,
                    action_layers(pawn)))
            end
        elseif pending.ai_skill then
            reason = string.format("queue, AI skill %s over, waited %.2fs, pawn in %s", pending.ai_skill, waited, action)
        elseif action ~= pending.start_action or is_free_action(action) then
            reason = string.format("queue, waited %.2fs, pawn in %s", waited, action)
        elseif waited > QUEUE_TIMEOUT then
            reason = string.format("queue timeout %.1fs, pawn still in %s", QUEUE_TIMEOUT, action)
        end
        if reason then
            local p = pending
            pending = nil
            fire(pawn, p.skill, reason)
        end
    end
end

-- 0.9.39: an order or queue whose pawn is no longer in the party (hired pawn dismissed, party rebuilt by a load)
-- is dropped without touching that pawn; until 0.9.38 it ran on the old object up to ORDER_MAX
function AIM.drop_missing(party)
    local here = {}
    for _, slot in ipairs(SLOTS) do
        if party[slot] then here[party[slot]:get_address()] = true end
    end
    AIM.use(nil)
    for addr, c in pairs(AIM.ctx) do
        if not here[addr] then
            local o = c.active or c.pending
            log_line(string.format("[END] %s: pawn no longer in the party, %s dropped",
                o and ORDERS[o.skill].name or "?", c.active and "order" or "queued order"))
            AIM.ctx[addr] = nil
            AIM.follow[addr] = nil
        end
    end
end

local function update()
    local t = now()

    for vk, name in pairs(TOGGLE_KEYS) do
        local down = reframework:is_key_down(vk)
        if down and not key_was_down[vk] then
            enabled[name] = not enabled[name]
            log_line(string.format("[TOGGLE] %s = %s", name, tostring(enabled[name])))
        end
        key_was_down[vk] = down
    end
    if #chord_requests > 0 then
        local reqs = chord_requests
        chord_requests = {}
        for _, r in ipairs(reqs) do
            if r.dpad then
                if TARGET_DPAD[r.dpad] then select_target(TARGET_DPAD[r.dpad]) else cancel_target() end
            else
                counters.chords = counters.chords + 1
                order(r.chord, r.arrow)
            end
        end
    end
    poll_keys()

    if not get_main_pawn() then return end
    resolve_names()

    if t - last_scan >= SCAN_PERIOD then
        last_scan = t
        local _, _, party = get_target()
        AIM.drop_missing(party)
        for _, slot in ipairs(SLOTS) do
            if party[slot] then
                local ok, e = pcall(scan, party[slot], slot)
                if not ok and not scan_failed[slot] then
                    scan_failed[slot] = true -- once per slot: a hired pawn's skills may not read like the main one's
                    err("scan " .. slot, e)
                end
            elseif scanned[slot] then
                scanned[slot] = nil
            end
        end
    end

    if cancel_check and t - cancel_check.t >= 0.5 then
        log_line(string.format("[CANCEL] %s +0.5s layers %s", cancel_check.slot, action_layers(cancel_check.pawn)))
        cancel_check = nil
    end

    local player = get_player()
    local boons = player and player_boons(player) or {}
    local bt = boons_text(boons)
    if bt ~= last_boons_text then
        log_line("[BUFF] player boons " .. bt)
        last_boons_text = bt
    end

    -- test 34: one order per pawn (AIM.ctx); each pawn's order and queue run in turn in active / pending.
    -- An error drops only that pawn's order.
    local keys = {}
    if AIM.cur then keys[1] = AIM.cur end
    for k in pairs(AIM.ctx) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        AIM.use(k)
        local ok, e = pcall(AIM.step, t, boons)
        if not ok then
            err("order step", e)
            if active then pcall(function() active.decision:set_Enabled(true) end) pcall(AIM.restore_decisions, active) end
            active, pending = nil, nil
        end
    end
    if DEV then
        local ok, e = pcall(AIM.follow_step, t)
        if not ok then err("follow", e) AIM.follow = {} end
    end
end

re.on_frame(function()
    local ok, e = pcall(update)
    if not ok then
        err("update", e)
        AIM.all_off()
    end
    local t = os.clock()
    if t - log_t >= LOG_FLUSH then
        log_t = t
        log_flush()
    end
end)

---------------------------------------------------------------- HUD: pawn skills on the skill palette (decision 40)

-- While LT is held (LT chord on), the button guide that shows the player's skills when RB is held (GUI
-- ui010201) shows the pawn's skill bound to each face button instead; the game's text comes back on release.
-- Element paths and the set_Message / DrawSelf calls follow "Skill Maker" by alphaZomega
-- (https://www.nexusmods.com/dragonsdogma2/mods/691), which writes its own skill names there.
-- Tests 4-8 (old D-pad label idea) never found a label: they searched ui010201, but the D-pad labels live in
-- ui020401 (PNL_Pawncommand/PNL_{Left,Up,Right,Down}key/PNL_txt/mtx_00, same mod) - for later.
-- The game file (pak updated 2026-10-08) has PNL_L00-L04 and PNL_R00-R04; Skill Maker 1.19 (Jan 2025) knows 00-03.
-- L04 / R04 = the A+X / B+Y pairs added by a game update (test 22 log with RB held + user, 2026-10-14: the
-- player's A+X pair showed in L04).
local PALETTE_GUI = "ui010201"
local function pnl(n) return "PNL_top/PNL_" .. n .. "/PNL_txt/mtx_00" end
local PALETTE_TEXT = { X = pnl("L03"), Y = pnl("L02"), B = pnl("R02"), A = pnl("R03"),
                       ["A+X"] = pnl("L04"), ["B+Y"] = pnl("R04") }
local PALETTE_ALL = { "L00", "L01", "L02", "L03", "L04", "R00", "R01", "R02", "R03", "R04" }
local PALETTE_WATCH_CAP = 40
local palette = nil        -- { go, texts = { X = obj... }, all = { L00 = obj... } } found once
local palette_failed = false -- not found once (logged once)
local palette_next_find = 0
local palette_saved = nil  -- during a hold: { draw_self, update_self, texts = { X = msg }, visible = { X = bool } }
local palette_check = nil  -- frames left before the read-back after a restore
local palette_holds = 0
local palette_last = nil   -- last logged texts of the 10 panels
local palette_watch = 0

local function find_palette(gui, quiet)
    local go = gui:call("get_GameObject()")
    local root = gui and gui:get_field("Root")
    if not root then return nil, PALETTE_GUI .. " has no app.GUIBase / Root" end
    local get_obj = sdk.find_type_definition("via.gui.Control"):get_method("getObject(System.String)")
    local function get(path)
        local ok, obj = pcall(get_obj.call, get_obj, root, path)
        return ok and obj or nil
    end
    local p = { go = go, root = root, texts = {}, all = {} }
    local parts = {}
    for button, path in pairs(PALETTE_TEXT) do
        p.texts[button] = get(path)
        parts[#parts + 1] = string.format("%s=%s", button, p.texts[button] and "ok" or "missing")
    end
    for _, n in ipairs(PALETTE_ALL) do p.all[n] = get(pnl(n)) end
    table.sort(parts)
    if not quiet then
        log_line(string.format("[HUD] palette %s found (type %s), texts %s", PALETTE_GUI,
            gui:get_type_definition():get_full_name(), table.concat(parts, " ")))
    end
    return p
end

local function palette_name(id)
    local s = SKILLS[id]
    return (s and (s.name or s.enum)) or (ORDERS[id] and ORDERS[id].name) or "-"
end

-- texts of the 10 panels, logged when they change (RB held = where the game puts the player's skills and pairs)
local function palette_watch_frame()
    if palette_watch >= PALETTE_WATCH_CAP then return end
    local parts = {}
    for _, n in ipairs(PALETTE_ALL) do
        local obj = palette.all[n]
        local msg, vis = "missing", ""
        if obj then
            msg = tostring(obj:call("get_Message"))
            vis = obj:call("get_Visible") and "" or " (hidden)"
        end
        parts[#parts + 1] = n .. "='" .. msg .. "'" .. vis
    end
    local line = table.concat(parts, " ")
    if line ~= palette_last then
        palette_last = line
        palette_watch = palette_watch + 1
        log_line(string.format("[HUD] palette texts%s: %s", lt_down and " (LT held, ours)" or "", line))
    end
end

-- Test 37 colours (user, colour-blind: red is easy to tell, a white/grey shade is not). While LT is held every
-- palette name takes the colour of the X name (user: the B names stood out brighter than the rest), and a skill
-- the target pawn is short of stamina for turns red. The game's colours are put back at release.
-- via.Color = one packed 32-bit value: 0xFF2828FF is red in both RGBA and ABGR byte order.
AIM.RED = 0xFF2828FF
function AIM.color_value(v)
    local td = sdk.find_type_definition("via.Color")
    if not AIM.color_field then
        for _, f in ipairs(td:get_fields()) do
            if not f:is_static() then AIM.color_field = f:get_name() break end
        end
        log_line("[HUD] via.Color field = " .. tostring(AIM.color_field))
    end
    local c = ValueType.new(td)
    c:set_field(AIM.color_field, v)
    return c
end
-- p = the target pawn (read once per frame by palette_frame; 0.9.38 read the whole party once per button per frame)
function AIM.palette_color(button, obj, id, p)
    local ok, e = pcall(function()
        local saved = palette_saved
        local ref = saved.colors.X or saved.colors.Y
        if not AIM.color_field then AIM.color_value(0) end
        if not saved.colors_logged then
            saved.colors_logged = true
            local parts = {}
            for b, c in pairs(saved.colors) do
                parts[#parts + 1] = string.format("%s=0x%08X", b, c:get_field(AIM.color_field) or 0)
            end
            table.sort(parts)
            log_line("[HUD] palette colours before (game): " .. table.concat(parts, " "))
        end
        local short = p and AIM.short_of_stamina(p, id)
        local want = short and AIM.RED or (ref and ref:get_field(AIM.color_field))
        if want and obj:call("get_Color"):get_field(AIM.color_field) ~= want then
            obj:call("set_Color(via.Color)", AIM.color_value(want))
        end
    end)
    if not ok and not AIM.color_warned then
        AIM.color_warned = true
        log_line("[WARN] [HUD] palette colour: " .. tostring(e))
    end
end
function AIM.palette_colors_back(saved)
    for button, c in pairs(saved.colors or {}) do
        palette.texts[button]:call("set_Color(via.Color)", c)
    end
end

-- Restore only in the owning GUI's update hook, never from a general application-entry callback.
local function palette_restore(why)
    local saved = palette_saved
    palette_saved = nil
    for button, msg in pairs(saved.texts) do
        local obj = palette.texts[button]
        if saved.written[button] == obj:call("get_Message") then
            obj:call("set_Message(System.String)", msg)
        end
    end
    AIM.palette_colors_back(saved)
    for _, rec in ipairs(saved.visible) do
        rec.el:call("set_Visible", rec.vis)
    end
    palette.go:call("set_DrawSelf", saved.draw_self)
    palette.go:call("set_UpdateSelf", saved.update_self)
    if palette_holds <= 3 then
        palette_check = 2
        log_line("[HUD] palette restored (" .. why .. ")")
    end
end

local function palette_frame(gui)
    local root = gui:get_field("Root")
    if palette and palette.root ~= root then
        palette, palette_saved, palette_check = nil, nil, nil
        log_line("[HUD] palette root changed; discarded old controls")
    end
    if not palette then
        -- not in the scene yet (title screen / loading): looked for again every 2 s
        local t = now()
        if t < palette_next_find then return end
        palette_next_find = t + 2.0
        local why
        palette, why = find_palette(gui)
        if not palette then
            if not palette_failed then
                palette_failed = true
                log_line("[WARN] [HUD] " .. tostring(why) .. " (looked for again every 2 s)")
            end
            return
        end
    end
    local want = lt_down and cur_job ~= nil and not LTH.blocked and not AIM.rb_now
    if want and not palette_saved then
        -- 0.9.39: looked up again at each LT hold, so a GUI rebuilt by a load (title screen, new game) is never
        -- written through the old objects; the 0.9.38 lookup was once per run
        local p = find_palette(gui, true)
        if not p then return end
        palette = p
    end
    if DEV then palette_watch_frame() end
    if not want then
        if palette_saved then palette_restore("orders closed") end
        if palette_check then
            palette_check = palette_check - 1
            if palette_check == 0 then
                palette_check = nil
                local parts = {}
                for button, obj in pairs(palette.texts) do
                    parts[#parts + 1] = button .. "='" .. tostring(obj:call("get_Message")) .. "'"
                end
                table.sort(parts)
                log_line("[HUD] palette 2 frames after restore: " .. table.concat(parts, " "))
            end
        end
        return
    end
    if not palette_saved then
        palette_holds = palette_holds + 1
        palette_saved = { draw_self = palette.go:call("get_DrawSelf"), update_self = palette.go:call("get_UpdateSelf"),
                          texts = {}, written = {}, visible = {}, logged = palette_holds > 3 }
        local parts = {}
        palette_saved.colors = {}
        for button, obj in pairs(palette.texts) do
            pcall(function() palette_saved.colors[button] = obj:call("get_Color") end)
            palette_saved.texts[button] = obj:call("get_Message")
            parts[#parts + 1] = button .. "='" .. tostring(palette_saved.texts[button]) .. "'"
            do
                -- test 22: text visible but the pair stayed off screen: outside RB the game hides the pair's panel
                -- (PNL_L04 / PNL_R04, with the 5 / 6 square). Test 23: a face button the player left empty has its
                -- text (mtx_00) hidden too (B / R02). Every element from the text up to PNL_top is shown.
                local chain = {}
                local el = obj
                for _ = 1, 6 do
                    if not el then break end
                    local ename = tostring(el:call("get_Name"))
                    local vis = el:call("get_Visible")
                    palette_saved.visible[#palette_saved.visible + 1] = { el = el, vis = vis }
                    local cs = "?"
                    pcall(function() cs = string.format("%.2f", el:call("get_ColorScale").w) end)
                    chain[#chain + 1] = string.format("%s vis=%s alpha=%s", ename, tostring(vis), cs)
                    if ename == "PNL_top" then break end
                    el = el:call("get_Parent")
                end
                if not palette_saved.logged then
                    log_line(string.format("[HUD] %s chain before: %s", button, table.concat(chain, " < ")))
                end
            end
        end
        table.sort(parts)
        if not palette_saved.logged then
            log_line(string.format("[HUD] LT hold %d: DrawSelf %s, UpdateSelf %s, game texts %s", palette_holds,
                tostring(palette_saved.draw_self), tostring(palette_saved.update_self), table.concat(parts, " ")))
        end
    end
    palette.go:call("set_DrawSelf", true)
    palette.go:call("set_UpdateSelf", true)
    local parts = {}
    local okp, party = pcall(party_pawns)
    local tp = okp and party[target_slot] or nil
    for button, obj in pairs(palette.texts) do
        -- keep the game's leading tag (Skill Maker writes <COLOR preset="arrow"></COLOR> before its text)
        local orig = tostring(palette_saved.texts[button] or "")
        local prefix = orig:match("^(<COLOR[^>]*></COLOR>)") or ""
        local id = binding(target_slot, cur_job, "LT", button)
        local name = palette_name(id)
        local text = prefix .. name
        if tostring(obj:call("get_Message")) ~= text then obj:call("set_Message(System.String)", text) end
        palette_saved.written[button] = text
        AIM.palette_color(button, obj, id, tp)
        parts[#parts + 1] = button .. "='" .. tostring(obj:call("get_Message")) .. "'"
    end
    for _, rec in ipairs(palette_saved.visible) do
        if not rec.el:call("get_Visible") then rec.el:call("set_Visible", true) end
    end
    counters.hud_frames = counters.hud_frames + 1
    if not palette_saved.logged then
        palette_saved.logged = true
        table.sort(parts)
        log_line("[HUD] palette set, read back " .. table.concat(parts, " "))
    end
end

---------------------------------------------------------------- HUD: pawn names on the D-pad labels (decision 42)

-- While LT is held, the pawn command labels (GUI ui020401, Go / Wait / Help / To me) show what LT + D-pad does:
-- Left / Up / Right = main / hired 1 / hired 2 pawn name ("> " marks the target), Down = "Cancel: <target>".
-- Paths from Skill Maker (it writes its skill names there in a post-hook of app.ui020401.update); written here
-- in the owning GUI's update hook, with game text saved at LT down and put back at release.
-- in its own block: the main chunk is near Lua's 200-locals limit
local dpad_api = {} -- frame(gui), clear(), saving() = labels currently ours
do
local DPAD_GUI = "ui020401"
local DPAD_TEXT = {}
for _, d in ipairs(DPAD) do DPAD_TEXT[d] = "PNL_Pawncommand/PNL_" .. d .. "key/PNL_txt/mtx_00" end
local dpad_hud = nil        -- { go, texts = { Left = obj... } }
local dpad_failed = false
local dpad_next_find = 0
local dpad_saved = nil      -- during a hold: { draw_self, update_self, texts, visible, logged }
local dpad_holds = 0

local function find_dpad(gui, quiet)
    local go = gui:call("get_GameObject()")
    local root = gui and gui:get_field("Root")
    if not root then return nil, DPAD_GUI .. " has no app.GUIBase / Root" end
    local get_obj = sdk.find_type_definition("via.gui.Control"):get_method("getObject(System.String)")
    local h = { go = go, root = root, texts = {} }
    local parts = {}
    for d, path in pairs(DPAD_TEXT) do
        local ok, obj = pcall(get_obj.call, get_obj, root, path)
        h.texts[d] = ok and obj or nil
        parts[#parts + 1] = d .. "=" .. (h.texts[d] and "ok" or "missing")
    end
    table.sort(parts)
    if not quiet then
        log_line(string.format("[HUD] D-pad %s found (type %s), texts %s", DPAD_GUI,
            gui:get_type_definition():get_full_name(), table.concat(parts, " ")))
    end
    return h
end

local function dpad_label(d)
    if d == "Down" then
        local s = scanned[target_slot]
        return "Cancel: " .. (s and s.name or SLOT_LABEL[target_slot])
    end
    local slot = TARGET_DPAD[d]
    local s = scanned[slot]
    local name = s and s.name or "-"
    return (slot == target_slot and "> " or "") .. name
end

local function dpad_restore(why)
    local saved = dpad_saved
    dpad_saved = nil
    for d, msg in pairs(saved.texts) do
        local obj = dpad_hud.texts[d]
        if saved.written[d] == obj:call("get_Message") then
            obj:call("set_Message(System.String)", msg)
        end
    end
    for _, rec in ipairs(saved.visible) do
        rec.el:call("set_Visible", rec.vis)
    end
    dpad_hud.go:call("set_DrawSelf", saved.draw_self)
    dpad_hud.go:call("set_UpdateSelf", saved.update_self)
    if dpad_holds <= 3 then log_line("[HUD] D-pad labels restored (" .. why .. ")") end
end

local function dpad_frame(gui)
    local root = gui:get_field("Root")
    if dpad_hud and dpad_hud.root ~= root then
        dpad_hud, dpad_saved = nil, nil
        log_line("[HUD] D-pad root changed; discarded old controls")
    end
    if not dpad_hud then
        local t = now()
        if t < dpad_next_find then return end
        dpad_next_find = t + 2.0
        local why
        dpad_hud, why = find_dpad(gui)
        if not dpad_hud then
            if not dpad_failed then
                dpad_failed = true
                log_line("[WARN] [HUD] " .. tostring(why) .. " (looked for again every 2 s)")
            end
            return
        end
    end
    if not lt_down or LTH.blocked or AIM.rb_now then
        if dpad_saved then dpad_restore("orders closed") end
        return
    end
    if not dpad_saved then
        -- 0.9.39: looked up again at each LT hold (see palette_frame)
        local h = find_dpad(gui, true)
        if not h then return end
        dpad_hud = h
        dpad_holds = dpad_holds + 1
        dpad_saved = { draw_self = dpad_hud.go:call("get_DrawSelf"), update_self = dpad_hud.go:call("get_UpdateSelf"),
                       texts = {}, written = {}, visible = {}, logged = dpad_holds > 3 }
        local parts = {}
        for d, obj in pairs(dpad_hud.texts) do
            dpad_saved.texts[d] = obj:call("get_Message")
            parts[#parts + 1] = d .. "='" .. tostring(dpad_saved.texts[d]) .. "'"
            -- every element from the text up to PNL_Pawncommand is shown (the palette needed it, tests 22-23)
            local chain = {}
            local el = obj
            for _ = 1, 6 do
                if not el then break end
                local ename = tostring(el:call("get_Name"))
                local vis = el:call("get_Visible")
                dpad_saved.visible[#dpad_saved.visible + 1] = { el = el, vis = vis }
                local cs = "?"
                pcall(function() cs = string.format("%.2f", el:call("get_ColorScale").w) end)
                chain[#chain + 1] = string.format("%s vis=%s alpha=%s", ename, tostring(vis), cs)
                if ename == "PNL_Pawncommand" then break end
                el = el:call("get_Parent")
            end
            if not dpad_saved.logged then
                log_line(string.format("[HUD] D-pad %s chain before: %s", d, table.concat(chain, " < ")))
            end
        end
        table.sort(parts)
        if not dpad_saved.logged then
            log_line(string.format("[HUD] D-pad LT hold %d: DrawSelf %s, UpdateSelf %s, game texts %s", dpad_holds,
                tostring(dpad_saved.draw_self), tostring(dpad_saved.update_self), table.concat(parts, " ")))
        end
    end
    dpad_hud.go:call("set_DrawSelf", true)
    dpad_hud.go:call("set_UpdateSelf", true)
    local parts = {}
    for d, obj in pairs(dpad_hud.texts) do
        local orig = tostring(dpad_saved.texts[d] or "")
        local prefix = orig:match("^(<COLOR[^>]*></COLOR>)") or ""
        local text = prefix .. dpad_label(d)
        if tostring(obj:call("get_Message")) ~= text then obj:call("set_Message(System.String)", text) end
        dpad_saved.written[d] = text
        parts[#parts + 1] = d .. "='" .. tostring(obj:call("get_Message")) .. "'"
    end
    for _, rec in ipairs(dpad_saved.visible) do
        if not rec.el:call("get_Visible") then rec.el:call("set_Visible", true) end
    end
    counters.dpad_frames = counters.dpad_frames + 1
    local line = table.concat(parts, " ")
    if not dpad_saved.logged or line ~= dpad_saved.last then
        -- read back once per hold and whenever the target changes during it
        dpad_saved.logged = true
        dpad_saved.last = line
        if dpad_holds <= 10 then log_line("[HUD] D-pad labels set, read back " .. line) end
    end
end

dpad_api.frame = dpad_frame
dpad_api.saving = function() return dpad_saved ~= nil end
dpad_api.clear = function()
    dpad_hud, dpad_saved = nil, nil
    dpad_next_find = 0
end
end

do
    local function clear_palette()
        palette, palette_saved, palette_check = nil, nil, nil
        palette_next_find = 0
    end
    local function hook_hud(type_name, signature, frame, clear, saving)
        local update_method = find_method(type_name, signature)
        local destroy_method = find_method(type_name, "onDestroy()")
        if not update_method or not destroy_method then
            err("hud " .. type_name, "required lifecycle hooks missing; labels disabled")
            return
        end
        local failed = false
        sdk.hook(update_method,
            function(args)
                thread.get_hook_storage().pawn_orders_gui = args[2]
            end,
            function(retval)
                if failed or (not DEV and not lt_down and not saving()) then return retval end
                local ok, e = pcall(function()
                    local gui = sdk.to_managed_object(thread.get_hook_storage().pawn_orders_gui)
                    if gui then frame(gui) end
                end)
                if not ok then
                    failed = true
                    clear()
                    err("hud " .. type_name .. " (labels off for this run)", e)
                end
                return retval
            end)
        sdk.hook(destroy_method, function()
            clear() -- native controls must not be touched once destruction starts
        end, function(retval) return retval end)
        log_line("[HUD] hooked " .. type_name .. "." .. signature)
    end
    hook_hud("app.ui010201", "lateUpdate()", palette_frame, clear_palette,
        function() return palette_saved ~= nil or palette_check ~= nil end)
    hook_hud("app.ui020401", "update()", dpad_api.frame, dpad_api.clear, dpad_api.saving)
end

---------------------------------------------------------------- REFramework menu (decision 10)

local menu_failed = false

re.on_draw_ui(function()
    if not imgui.tree_node("Specific Pawn Orders v" .. VERSION) then return end
    local ok, e = pcall(function()
        local sc = scheme()
        local labels, idx = {}, 1
        for i, x in ipairs(SCHEMES) do
            labels[i] = x.label
            if x == sc then idx = i end
        end
        local changed, new_idx = imgui.combo("Pad shortcuts##scheme", idx, labels)
        if changed then
            config.scheme = SCHEMES[new_idx].id
            save_config()
            log_line("[BIND] scheme " .. config.scheme)
            sc = scheme()
        end
        imgui.text("Hold the first button and press the second: the target pawn uses the skill bound there.")
        imgui.text("Hold LT + D-pad: Left = main pawn, Up = hired pawn 1, Right = hired pawn 2 (target), Down = cancel its action.")
        imgui.text("RB takes priority: release LT, then press LT again after releasing RB to give pawn orders.")
        local hold_changed, hold_v = imgui.checkbox("Hold LT to open the orders (a tap keeps LT's game action)##lthold",
            config.lt_hold == true)
        if hold_changed then
            config.lt_hold = hold_v
            save_config()
            log_line("[BIND] hold LT " .. tostring(hold_v))
        end
        if config.lt_hold == true then
            local t_changed, t_v = imgui.slider_float("LT hold time (s)##lthold_t", LTH.hold_time(), 0.0, 1.0, "%.2f")
            if t_changed then
                config.lt_hold_time = math.max(0.0, math.min(1.0, t_v))
                save_config()
            end
            imgui.text("LT released sooner = sheathe / draw as usual. Pressing a face button or D-pad under LT opens the orders at once.")
        end
        imgui.text("Skills and keyboard keys are kept for every set; only the chosen set is shown and used.")
        local ts = scanned[target_slot]
        imgui.text(string.format("Target now: %s%s", SLOT_LABEL[target_slot], ts and (" - " .. ts.name) or ""))
        if DEV and imgui.tree_node("Test switches##toggles") then
            for _, t in ipairs({ { "no_cooldown", "F9: ordered skill's AI cooldown zeroed (AI-decides orders only)" },
                                 { "cast_in_place", "F10: attack orders cast where the pawn stands (our way, no target)" } }) do
                local changed, v = imgui.checkbox(t[2] .. "##tg" .. t[1], enabled[t[1]])
                if changed then
                    enabled[t[1]] = v
                    log_line(string.format("[TOGGLE] %s = %s (menu)", t[1], tostring(v)))
                end
            end
            imgui.tree_pop()
        end
        if imgui.tree_node("Stamina % position (shown while LT is held)##hudpos") then
            for _, k in ipairs({ { "hud_x", "Left <-> right", AIM.HUD_X }, { "hud_y", "Top <-> bottom", AIM.HUD_Y } }) do
                local changed, v = imgui.slider_float(k[2] .. "##" .. k[1], tonumber(config[k[1]]) or k[3], 0.0, 1.0, "%.3f")
                if changed then
                    config[k[1]] = v
                    save_config()
                end
            end
            imgui.tree_pop()
        end
        if imgui.tree_node("Keyboard keys (same for every pawn and vocation)##keys") then
            imgui.text("A key orders the skill of its position for the target pawn's vocation.")
            imgui.text("The game still sees the key: pick one it does not use (numpad, F keys, mouse 4/5).")
            local function key_button(chord, arrow, label)
                local is_cap = capturing and capturing.chord == chord and capturing.arrow == arrow
                local text = is_cap and "press a key... (Esc = none)" or vk_name(key_of(chord, arrow))
                if imgui.button(label .. ": " .. text .. "##key" .. chord .. arrow) then
                    if is_cap then
                        capturing = nil
                    else
                        local was = {}
                        for vk = 1, 0xFE do was[vk] = reframework:is_key_down(vk) end
                        capturing = { chord = chord, arrow = arrow, was_down = was }
                    end
                end
            end
            for _, chord in ipairs(sc.chords) do
                for _, arrow in ipairs(BUTTONS[chord]) do key_button(chord, arrow, chord .. " + " .. arrow) end
            end
            imgui.text("Target pawn (same as LT + D-pad Left / Up / Right, Down = cancel):")
            for _, arrow in ipairs(TARGET_KEYS) do key_button("Target", arrow, TARGET_KEY_LABEL[arrow]) end
            imgui.tree_pop()
        end
        if not names_done then imgui.text("(skill names load once you are in the game)") end
        -- one block per pawn slot (decision 42), each with a block per vocation like 0.8
        for _, slot in ipairs(SLOTS) do
            local s = scanned[slot]
            local head = SLOT_LABEL[slot] .. (s and string.format(" - %s (%s)", s.name, job_label(s.job)) or " (not in the party)")
                .. (slot == target_slot and "  <- target" or "")
            if imgui.tree_node(head .. "##pawn" .. slot) then
                if slot ~= "main" then
                    imgui.text("A new hired pawn in this place keeps these skills: set them again if its skills differ.")
                end
                for _, j in ipairs(JOBS) do
                    local is_cur = s ~= nil and j.id == s.job
                    if imgui.tree_node(job_label(j.id) .. (is_cur and "  <- vocation now" or "") .. "##job" .. slot .. j.id) then
                        local ids = { 0 }
                        local names = { "(nothing)" }
                        for _, id in ipairs(JOB_SKILLS[j.id]) do
                            local tags = {}
                            if is_cur then tags[#tags + 1] = has_skill(s.skills, id) and "equipped" or "not equipped" end
                            if not ORDERS[id] then tags[#tags + 1] = "no known action" end
                            ids[#ids + 1] = id
                            names[#names + 1] = skill_label(id) .. (#tags > 0 and ("  [" .. table.concat(tags, ", ") .. "]") or "")
                        end
                        for _, chord in ipairs(sc.chords) do
                            for _, arrow in ipairs(BUTTONS[chord]) do
                                local cur = binding(slot, j.id, chord, arrow)
                                local idx = 1
                                for i, id in ipairs(ids) do if id == cur then idx = i end end
                                local vk = key_of(chord, arrow)
                                local label = chord .. " + " .. arrow .. (vk and ("  (key " .. vk_name(vk) .. ")") or "")
                                local changed, new_idx = imgui.combo(label .. "##" .. slot .. j.id .. chord .. arrow,
                                    idx, names)
                                if changed then set_binding(slot, j.id, chord, arrow, ids[new_idx]) end
                            end
                        end
                        imgui.tree_pop()
                    end
                end
                imgui.tree_pop()
            end
        end
    end)
    if not ok and not menu_failed then
        menu_failed = true -- log once, the menu is drawn every frame
        err("menu", e)
    end
    imgui.tree_pop()
end)

---------------------------------------------------------------- AI cancel guard

local guard_logged = {}

sdk.hook(
    sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore"),
    function(args)
        -- AI-decides order: the AI owns the skill, only its cancels during Prepare are blocked (F1, test 34; test 27:
        -- blocking its DefaultCancelAction in Ready kept Vortex Rage looping Prepare/Ready 20 s without a cast);
        -- other skills are off by decision flags. Test 34: the order of the pawn whose ActionManager this is.
        local a = AIM.find("am_addr", sdk.to_int64(args[2]))
        if not a then return end
        local prio = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local name = "?"
        pcall(function() name = sdk.to_managed_object(args[4]):call("ToString") end)
        -- test 33: 3rd argument = motion layer (0 full body, 1 upper body; _NickCore Hooks.lua reads it so); it
        -- goes into the log next to the priority (pl = "<priority> L<layer>")
        local layer = sdk.to_int64(args[5]) & 0xFFFFFFFF
        local pl = prio .. " L" .. layer
        a.last_req = string.format("%s p%s +%.2fs", name, pl, now() - a.t_fire)
        -- our skill requested after the order = it (re)starts, even if its layer name was already on
        if not a.req_key and has_key(name:lower(), a.keys) then a.req_key = true end
        if a.mode == "ai" then
            -- test 31: test 30 lost a charged Vortex to her JobMagicUser_SpellStock (stocked instead of cast); the
            -- same block as our way (test 13)
            if name:find("SpellStock", 1, true) and not has_key(name:lower(), a.keys) then
                counters.guards = counters.guards + 1
                if not (a.req_logged and a.req_logged["stock " .. name]) then
                    a.req_logged = a.req_logged or {}
                    a.req_logged["stock " .. name] = true
                    log_line(string.format("[GUARD] +%.2fs blocked %s p%s (AI decides; our order casts, not stocks)",
                        now() - a.t_fire, name, pl))
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            -- test 30: with the AI on nothing was logged; test 28 lost a charging Meteoron to DefaultCancelAction at
            -- +6.55 s. Every request after the start once per order, and a snapshot at the first cancel.
            if a.t_start then
                a.req_logged = a.req_logged or {}
                local key = name .. " p" .. pl
                if not a.req_logged[key] then
                    a.req_logged[key] = true
                    log_line(string.format("[AIREQ] +%.2fs %s priority %s (%.2fs after start; layers %s)",
                        now() - a.t_fire, name, pl, now() - a.t_start, action_layers(a.pawn)))
                end
                if CANCEL_NODES[name] and not a.cancel_dumped then
                    a.cancel_dumped = true
                    local okn, enemy, src, d = pcall(pick_enemy, a.pawn)
                    log_line(string.format("[AICANCEL] +%.2fs %s p%s %.2fs after start; nearest enemy %s; AI skill budget %s",
                        now() - a.t_fire, name, pl, now() - a.t_start,
                        okn and enemy and string.format("%.1fm", d) or tostring(src), AIM.skill_budget(a.pawn)))
                    -- test 31: the running decision says which decision asked for the cancel
                    if DEV then
                        pcall(function()
                            local _, text = AIM.executing(a.pawn, a.stem_by_addr)
                            log_line(string.format("[AICANCEL] running decision %s", text))
                        end)
                    end
                end
            end
            -- test 34 (F1, B): test 33 lost 3 charging Sorcerer spells to her own DefaultCancelAction p10 L0
            -- (+ UpperBodyDefault L1) 0.8-3.2 s into Prepare. Her cancels are blocked from our start until Ready
            -- (not in Ready: test 27, Vortex looped Prepare/Ready 20 s with them blocked there)
            if a.t_start and not a.t_ready and not a.casting and CANCEL_NODES[name]
               and (prio == 10 or CANCEL_ANY_PRIO[name]) then
                counters.guards = counters.guards + 1
                a.ai_guards = (a.ai_guards or 0) + 1
                if a.ai_guards <= 5 then
                    log_line(string.format("[GUARD] +%.2fs AI decides: blocked %s p%s %.2fs into the charge",
                        now() - a.t_fire, name, pl, now() - a.t_start))
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            return
        end
        if a.casting then
            -- test 27: Meteoron's Cast showed for 0.02 s, then DefaultCancelAction ended it as the AI came back on
            -- (twice). hold_cast = seconds after the Cast the cancels stay blocked; other requests only logged.
            local hold = ORDERS[a.skill].hold_cast
            local held = hold and now() - a.t_cast < hold and CANCEL_NODES[name]
            local key = "cast " .. name .. " p" .. pl
            if not guard_logged[key] and counters.req_seen < 40 then
                guard_logged[key] = true
                counters.req_seen = counters.req_seen + 1
                log_line(string.format("[REQ] +%.2fs %s priority %s %s (after cast)", now() - a.t_fire, name, pl,
                    held and "blocked" or "passed"))
            end
            if held then
                counters.guards = counters.guards + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            return
        end
        -- test 10: once back on, the AI asked for its own Job03_PrepareIceBoon 0.17 s into our Ready and
        -- replaced the Louvor (only cancels were blocked). The start of any other skill (its Prepare step) is
        -- blocked from our start until our Cast; other steps pass (our own cast steps may have other names,
        -- e.g. JobMagicUser_StartMagicBarrier for the Louvor, and keys of unseen skills are learned at start).
        if a.t_start and name:find("Prepare", 1, true) and skill_layer(name)
           and not has_key(name:lower(), a.keys) then
            counters.guards = counters.guards + 1
            local key = "skill " .. name .. " p" .. pl
            if not guard_logged[key] then
                guard_logged[key] = true
                log_line(string.format("[GUARD] +%.2fs blocked AI %s", now() - a.t_fire, key))
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        -- test 13: an ordered Louvor reached Ready and went into the Arcane Chest (JobMagicUser_SpellStock) instead
        -- of casting; stocking is blocked during our order
        if name:find("SpellStock", 1, true) and not has_key(name:lower(), a.keys) then
            counters.guards = counters.guards + 1
            local key = "stock " .. name .. " p" .. pl
            if not guard_logged[key] then
                guard_logged[key] = true
                log_line(string.format("[GUARD] +%.2fs blocked %s p%s (our order casts, not stocks)", now() - a.t_fire, name, pl))
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        local after_start = CANCEL_NODES[name]
        if prio ~= 10 and not CANCEL_ANY_PRIO[name] then after_start = nil end
        if after_start == nil then
            -- learn what else reaches our pawn before the cast (test 6: AttackCancelSheatheWeapon* cut 3 orders)
            local key = name .. " p" .. pl
            if not guard_logged[key] and counters.req_seen < 40 then
                guard_logged[key] = true
                counters.req_seen = counters.req_seen + 1
                log_line(string.format("[REQ] +%.2fs %s priority %s passed (%s)", now() - a.t_fire, name, pl,
                    a.t_start and "after start" or "before start"))
            end
            return
        end
        if after_start == true or not a.t_start then
            counters.guards = counters.guards + 1
            local key = name .. " p" .. pl .. (a.t_start and " (after start)" or " (before start)")
            if not guard_logged[key] then
                guard_logged[key] = true
                log_line("[GUARD] blocked AI cancel " .. key)
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
)

---------------------------------------------------------------- AI next-action block

-- Our way, once the AI is back on before the Cast (release_ai skills, at Ready): its decision maker may request
-- its own next action. A different pack requested on our pawn's blackboard is skipped until our Cast. Clears
-- (null) pass: the game may clear the request when it takes it. (Until v0.10 the AI stayed on for the whole
-- order and this blocked from the fire.)
local ai_block_logged = 0
local reqPackMethod = find_method("app.AIBlackBoardController", "set_ReqMainActInterPackData(app.ActInterPackData)")
if reqPackMethod then
    sdk.hook(reqPackMethod,
        function(args)
            if firing or not AIM.any() then return end
            local a = AIM.find("bb_addr", sdk.to_int64(args[2]))
            if not a or a.casting then return end
            local v = sdk.to_int64(args[3])
            if v == 0 or v == a.pack_addr then return end
            local path = "?"
            -- test 34: AI-decides order, logged only: does her AI switch packs when it cancels our charge?
            if a.mode == "ai" then
                if DEV and (a.packs_logged or 0) < 8 then
                    a.packs_logged = (a.packs_logged or 0) + 1
                    pcall(function() path = tostring(sdk.to_managed_object(args[3]):call("get_Path")) end)
                    log_line(string.format("[AIPACK] +%.2fs %s asked for %s (%s)", now() - a.t_fire,
                        ORDERS[a.skill].name, path, a.t_ready and "charged" or a.t_start and "charging" or "before start"))
                end
                return
            end
            if not a.ai_on then return end
            counters.ai_blocked = counters.ai_blocked + 1
            if ai_block_logged < 20 then
                ai_block_logged = ai_block_logged + 1
                pcall(function() path = tostring(sdk.to_managed_object(args[3]):call("get_Path")) end)
                log_line(string.format("[AIBLOCK] +%.2fs AI asked for %s before %s cast", now() - a.t_fire,
                    path, ORDERS[a.skill].name))
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end)
end

---------------------------------------------------------------- charge time (test 33)

-- app.JobPrepareSpell.getPrepareSec() returns the caster's charge time, buffs included (found in Nick's
-- Devtools by Nick, CombatTools.lua; field Human = the caster). Read for the ordered pawn only: the no-Ready
-- deadline uses it when F3 is on (AIM.charge), [PREP] logs it (at most 5 changes per order).
AIM.prepMethod = find_method("app.JobPrepareSpell", "getPrepareSec()")
if AIM.prepMethod then
    sdk.hook(AIM.prepMethod,
        function(args)
            thread.get_hook_storage().this = AIM.any() and args[2] or nil
        end,
        function(retval)
            local this = thread.get_hook_storage().this
            if not this then return retval end
            local ok, e = pcall(function()
                local h = sdk.to_managed_object(this):get_field("Human")
                local a = h and AIM.find("human_addr", h:get_address())
                if not a then return end
                local v = sdk.to_float(retval)
                if a.prep and math.abs(a.prep - v) < 0.01 then return end
                a.prep = v
                a.prep_logs = (a.prep_logs or 0) + 1
                if a.prep_logs == 1 then counters.prep_seen = counters.prep_seen + 1 end
                if a.prep_logs <= 5 then
                    log_line(string.format("[PREP] %s +%.2fs getPrepareSec %.2fs (table %s)", ORDERS[a.skill].name,
                        now() - a.t_fire, v, tostring(ORDERS[a.skill].charge)))
                end
            end)
            if not ok and not AIM.prep_err then
                AIM.prep_err = true -- once per run: the hook runs for every caster
                err("getPrepareSec hook", e)
            end
            return retval
        end)
end

---------------------------------------------------------------- launch availability (APC, F4)

-- The springboard skill is refused without this while the AI is off; only during our launch order
sdk.hook(
    sdk.find_type_definition("app.HumanSkillAvailability"):get_method("isCustomSkillAvailableWithoutItemCondition(app.HumanCustomSkillID)"),
    function(args)
        thread.get_hook_storage().retval = nil
        if not AIM.any() then return end
        local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
        if ORDERS[id] and ORDERS[id].stance and AIM.find("skill", id) then
            thread.get_hook_storage().retval = sdk.to_ptr(true)
        end
    end,
    function(retval)
        return thread.get_hook_storage().retval or retval
    end
)

---------------------------------------------------------------- summary

-- Test 37 (user, after test 36): only while LT is held, only the target pawn, only the percentage (no bar, no
-- name), between the player's health bar and the skill palette (screenshot 2026-10-15: health bar ends at ~70%
-- of the width at ~94% of the height, palette rows start at ~72%). Position = fraction of the screen, menu
-- sliders (config hud_x / hud_y). The palette names turn red when she is short (palette_frame).
AIM.HUD_X, AIM.HUD_Y = 0.700, 0.915
re.on_frame(function()
    if not draw or not lt_down then return end
    pcall(function()
        local p = party_pawns()[target_slot]
        if not p then return end
        local sm = p:call("get_StaminaManager")
        local cur, mx = sm:call("get_RemainingAmount"), sm:call("get_MaxValue")
        local text = string.format("%.0f%%", mx > 0 and cur * 100 / mx or 0)
        local w, h = 1920, 1080
        pcall(function()
            local ds = imgui.get_display_size()
            w, h = ds.x, ds.y
        end)
        local x = math.floor(w * (tonumber(config.hud_x) or AIM.HUD_X))
        local y = math.floor(h * (tonumber(config.hud_y) or AIM.HUD_Y))
        draw.text(text, x + 1, y + 1, 0xFF000000)
        draw.text(text, x, y, 0xFFFFFFFF)
    end)
end)

re.on_script_reset(function()
    AIM.all_off()
    summary()
    log_flush()
end)
