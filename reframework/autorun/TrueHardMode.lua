-- True Hard Mode
-- Dragon's Dogma 2 - REFramework script
-- After the first visit to Norgan (or at once with "Activate now"), base-game enemies get much more HP,
-- hit harder, are harder to stagger and give better rewards. Three difficulties: Normal, New Game Plus, Cock and Ball Torture.
-- Enemies that belong to the Norgan area, animals and non-enemies are never touched.
-- Credit: the idea of hooking ExpDispenser.addExpAndJobPoint and HitController.calcDamageValue comes from the
-- Bestiary mod by NickCore (no code copied).

local DEBUG = false   -- true = write log / diagnostic json files into reframework/data

local CFG_FILE = "TrueHardMode.json"
local VERSION = "Beta 0.8"

-- Factory settings of the three difficulties (these are also what "Fine-Tuning" starts with).
local DEFAULT_STAGES = {
    ["1"] = {
        armor_share = 0.6, attack_mult = 1.0, blocked_mult = 2.0, boss_curve = 0.5, boss_knee = 250000.0, boss_min_hp = 200000.0,
        burst_cooldown = 0.0, cyclops_mult = 1.2, dmg_large_cap = 35.285, dmg_large_max = 20.0, dmg_large_min = 15.0, dmg_med_max = 15.0,
        dmg_med_min = 10.0, dmg_mult_chance = 0.0, dmg_mult_max = 3.0, dmg_mult_min = 1.0, dmg_small_max = 7.0, dmg_small_min = 4.0,
        exp_curve = 0.85, exp_follow = 0.702, exp_mult = 1.0, exp_per_hp = 0.15, exp_ref_hp = 20000.0, hp_curve = 0.8,
        hp_curve2 = 0.25, hp_knee = 30500.0, hp_knee2 = 35500.0, large_above = 30000.0, large_bonus_min_dmg = 251.445, large_factor = 3.0,
        loss_mult = 0.7, max_hp_cap = 600000.0, medium_bonus_min_dmg = 0.0, medium_factor = 11.0, medium_min_hp = 15500.0, small_below = 3000.0,
        small_bonus_min_dmg = 0.0, small_factor = 5.0, small_hp_curve = 0.8, small_hp_curve2 = 0.25, small_hp_knee = 20000.0, small_hp_knee2 = 25000.0,
        small_min_hp = 0.0, stagger_follow = 1.0
    },
    ["2"] = {
        armor_share = 0.501, attack_mult = 1.307, blocked_mult = 1.499, boss_curve = 0.301, boss_knee = 340000.0, boss_min_hp = 235000.0,
        burst_cooldown = 0.0, cyclops_mult = 1.2, dmg_large_cap = 40.298, dmg_large_max = 25.341, dmg_large_min = 20.0, dmg_med_max = 14.376,
        dmg_med_min = 10.079, dmg_mult_chance = 0.0, dmg_mult_max = 3.0, dmg_mult_min = 1.5, dmg_small_max = 10.0, dmg_small_min = 6.0,
        exp_curve = 0.85, exp_follow = 0.751, exp_mult = 1.0, exp_per_hp = 0.402, exp_ref_hp = 20000.0, hp_curve = 0.506,
        hp_curve2 = 0.2, hp_knee = 40000.0, hp_knee2 = 50000.0, large_above = 29900.0, large_bonus_min_dmg = 136.691, large_factor = 4.5,
        loss_mult = 0.8, max_hp_cap = 750000.0, medium_bonus_min_dmg = 10.929, medium_factor = 16.0, medium_min_hp = 36500.0, small_below = 3000.0,
        small_bonus_min_dmg = 20.352, small_factor = 14.009, small_hp_curve = 0.604, small_hp_curve2 = 0.198, small_hp_knee = 30000.0, small_hp_knee2 = 35000.0,
        small_min_hp = 18000.0, stagger_follow = 1.2
    },
    ["3"] = {
        armor_share = 0.2, attack_mult = 1.0, blocked_mult = 2.0, boss_curve = 0.5, boss_knee = 0.0, boss_min_hp = 340000.0,
        burst_cooldown = 0.0, cyclops_mult = 1.2, dmg_large_cap = 100.0, dmg_large_max = 40.0, dmg_large_min = 28.0, dmg_med_max = 28.0,
        dmg_med_min = 18.0, dmg_mult_chance = 0.0, dmg_mult_max = 4.0, dmg_mult_min = 2.0, dmg_small_max = 14.0, dmg_small_min = 8.0,
        exp_curve = 1.0, exp_follow = 0.7, exp_mult = 1.0, exp_per_hp = 0.15, exp_ref_hp = 20000.0, hp_curve = 0.8,
        hp_curve2 = 0.25, hp_knee = 0.0, hp_knee2 = 0.0, large_above = 30000.0, large_bonus_min_dmg = 251.445, large_factor = 6.0,
        loss_mult = 1.0, max_hp_cap = 2000000.0, medium_bonus_min_dmg = 0.0, medium_factor = 25.0, medium_min_hp = 68000.0, small_below = 3000.0,
        small_bonus_min_dmg = 0.0, small_factor = 12.0, small_hp_curve = 0.8, small_hp_curve2 = 0.25, small_hp_knee = 0.0, small_hp_knee2 = 0.0,
        small_min_hp = 25000.0, stagger_follow = 1.4
    }
}

local cfg = {
    enabled = true,
    norgan_visited = false,
    level_pct = 10.0,         -- normal enemies: +10 % per step (x2.0 at level 50)
    level_pct_boss = 5.0,     -- bosses: +5 % per step (x1.5 at level 50)
    level_every = 5,
    level_max = 50,
    small_factor = 5.0,
    medium_factor = 11.0,
    large_factor = 3.0,
    small_below = 3000.0,     -- original max HP below this = small
    large_above = 30000.0,    -- original max HP above this = large/boss
    skip_animals = true,
    cfg_version = "",
    repair_enabled = false,   -- only for cleaning up enemies broken by earlier test versions; a real boss above the cap would be shrunk!
    repair_hp = 25000.0,      -- max HP given to an enemy that already has absurdly high HP (above the cap) and whose real value is unknown
    exp_follow = 1.0,         -- 0 = rewards unchanged, 1 = rewards grow by the same factor as the enemy HP
    exp_per_hp = 0.15,        -- reward per max HP of the scaled enemy (Norgan gives about 0.27); 0 = use the HP factor instead
    hp_knee = 35000.0,        -- medium enemies (small enemies: small_hp_*): diminishing returns for HP, everything above this value is flattened
    hp_knee2 = 45000.0,       -- second, much stronger flattening starts here (0 = off)
    hp_curve2 = 0.25,         -- exponent above the second knee
    hp_curve = 0.7,           -- 1 = no flattening, lower = flatter above the knee
    stagger_follow = 1.0,     -- stagger/reaction build-up is divided by (HP factor ^ this); 0 = off, 1 = full compensation
    exp_curve = 0.85,         -- diminishing returns: 1 = reward grows linearly with HP, lower = flatter for high-HP enemies and bosses
    exp_ref_hp = 20000.0,     -- at this max HP the reward is exactly "reward per max HP" x HP
    exp_mult = 1.0,           -- multiplies the experience/discipline reward of base-game enemies while the mod is active
    dmg_small_min = 4.0, dmg_small_max = 7.0,     -- bonus damage per hit of a small enemy: random percent of the target's max HP, added on top of the normal damage
    dmg_med_min = 10.0, dmg_med_max = 15.0,       -- same for medium enemies
    dmg_large_min = 15.0, dmg_large_max = 20.0,   -- same for large enemies / bosses
    dmg_mult_min = 1.0, dmg_mult_max = 3.0, dmg_mult_chance = 0.0,  -- every hit rolls: normal damage x dmg_mult_min, or (with this chance in %) x dmg_mult_max
    burst_cooldown = 0.0,                         -- seconds after a percent bonus during which the same target gets no further percent bonus (burst protection)
    blocked_mult = 2.0,                           -- base damage multiplier for hits that get no percent bonus because of burst protection
    loss_mult = 0.5,                              -- how much max HP the player loses per hit compared to the base game (0.5 = half)
    large_bonus_min_dmg = 500.0,  -- large enemies / bosses: the percent bonus only counts for hits with at least this much base damage
    small_bonus_min_dmg = 0.0,    -- same for small enemies (0 = every hit)
    medium_bonus_min_dmg = 0.0,   -- same for medium enemies (0 = every hit)
    show_hp_window = false,       -- small window: current / max HP of the enemies around you
    hp_window_radius = 40.0,      -- only enemies within this many metres are listed
    hp_window_rows = 8,
    show_dmg_window = false,      -- small window: live list of the hits you just took
    dmg_window_rows = 10,
    dmg_large_cap = 60.0,     -- a single hit of a large enemy / boss can never take more than this percent of the target's max HP (0 = off)
    attack_mult = 1.0,        -- damage multiplier for hits that base-game enemies deal to the player and pawns
    armor_share = 0.6,        -- how much of your armor counts against the percent bonus: 1 = fully, 0.5 = half, 0 = armor ignored
    small_min_hp = 0.0,       -- every small enemy has at least this much max HP (0 = off)
    medium_min_hp = 0.0,      -- every medium enemy has at least this much max HP (0 = off)
    dyn_stagger = true,       -- stagger susceptibility follows the enemy's remaining HP (everywhere, Norgan included)
    stag_full = 0.8,          -- reaction rate multiplier at 100% HP (0.8 = 20% harder to knock down)
    stag_curve = 1.0,         -- 1 = even (linear) rise, higher = stays low longer and then escalates
    stag_empty = 2.0,         -- reaction rate multiplier at 0% HP (2.0 = double susceptibility)
    cyclops_mult = 1.2,       -- extra HP factor for Cyclops only (ids ch250000_*), on top of the difficulty
    stage = 1,                -- selected difficulty stage (1..3)
    stages = {},              -- saved parameter sets of the three stages
    learned = {},             -- character id -> original max HP seen on an untouched enemy
    boss_knee = 600000.0,     -- bosses: diminishing returns start here (0 = off)
    boss_curve = 0.5,         -- boss exponent above that (1 = no flattening)
    max_hp_cap = 2000000.0,    -- hard upper limit for the final max HP of any enemy
    drops_enabled = true,      -- bosses drop Spoils (identifiable artifacts) according to their Guild Contracts category
    drops_ancient = true,      -- also allow the "Ancient ..." spoils variants in the random pool
    bonus_armor = true,        -- the percent bonus damage is reduced by your armor like the normal hit (physical and magical)
    meal_reset = true,         -- a camp meal resets the loss gauge (lost max HP) of you and your pawns, like resting overnight
    debug_ferrystone = false,  -- debug: the game's "may a Ferrystone be used here?" check always says yes
    drop_slots = {},           -- category -> list of { lvl = spoils level 1-5, chance = %, count = pieces }
    mig_noburst = 0, mig_bossmin = 0, mig_cap = false, mig_stag = false, mig_knee = false, mig_tier = false,   -- one-time migrations already done (must be loaded, or they run again on every start)
}

for k, v in pairs(DEFAULT_STAGES["1"]) do cfg[k] = v end   -- stage 1 = the factory defaults

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function managed_elements(arr)
    if not arr then return {} end
    local elements = safe(function() return arr:get_elements() end)
    local count = elements and safe(function() return #elements end)
    if type(count) ~= "number" then return {} end
    local out = {}
    for i = 1, count do
        local element = safe(function() return elements[i] end)
        if element and safe(sdk.is_managed_object, element) == true then
            out[#out + 1] = element
        end
    end
    return out
end

-- Optional language pack: reframework/data/TrueHardMode_lang.json = { font = "file in reframework/fonts", strings = { English = translation } }.
-- Without that file everything stays English and no extra font is loaded.
local lang = safe(json.load_file, "TrueHardMode_lang.json")
local lang_strings = type(lang) == "table" and type(lang.strings) == "table" and lang.strings or nil
local lang_font = nil
if lang_strings and type(lang.font) == "string" then
    lang_font = safe(imgui.load_font, lang.font, imgui.get_default_font_size() + 2,
        { 0x0020, 0x00FF, 0x2000, 0x206F, 0x3000, 0x30FF, 0x4E00, 0x9FFF, 0xFF00, 0xFFEF, 0 })
end
local lang_cache = {}
local function T(s)
    if not lang_strings then return s end
    local r = lang_cache[s]
    if r then return r end
    local base, id = string.match(s, "^(.-)(##.*)$")     -- the part after ## is only imgui's id, it is never shown
    r = (lang_strings[base or s] or base or s) .. (id or "")
    lang_cache[s] = r
    return r
end
local function with_lang_font(fn)
    if lang_font and pcall(imgui.push_font, lang_font) then
        local ok, err = pcall(fn)
        imgui.pop_font()
        if not ok then error(err) end
    else
        fn()
    end
end

local had_cfg = false   -- false on a fresh install
local function load_cfg()
    local t = safe(json.load_file, CFG_FILE)
    if type(t) == "table" then
        had_cfg = true
        for k, v in pairs(cfg) do
            if t[k] ~= nil and type(t[k]) == type(v) then cfg[k] = t[k] end
        end
    end
end
local STAGE_KEYS = { "max_hp_cap", "small_factor", "medium_factor", "large_factor", "small_below", "large_above",
    "hp_knee", "hp_curve", "hp_knee2", "hp_curve2", "stagger_follow",
    "exp_per_hp", "exp_curve", "exp_ref_hp", "exp_mult", "exp_follow", "attack_mult", "dmg_small_min", "dmg_small_max", "dmg_med_min", "dmg_med_max", "dmg_large_min", "dmg_large_max", "dmg_large_cap", "loss_mult", "boss_min_hp", "armor_share", "small_min_hp", "medium_min_hp", "burst_cooldown", "blocked_mult", "dmg_mult_min", "dmg_mult_max", "dmg_mult_chance", "boss_knee", "boss_curve",
    "small_hp_knee", "small_hp_curve", "small_hp_knee2", "small_hp_curve2", "small_bonus_min_dmg", "medium_bonus_min_dmg", "large_bonus_min_dmg", "cyclops_mult" }
local STAGE_NAMES = { "Normal", "New Game Plus", "Cock and Ball Torture" }
local STAGE_INFO = {
    "Enemies have roughly 3x to 11x HP, hit for 4-20% of your max HP on top of their normal damage, are much harder to stagger and give better rewards.",
    "More HP, harder hits (up to 25% of your max HP), tougher stagger resistance and bigger rewards.",
    "No diminishing returns on enemy HP, brutal hits and very high stagger resistance. Not meant to be fair.",
}
local stage_changed = false

local function save_cfg()
    -- keep the selected stage's saved parameter set in sync with the live values
    local st = cfg.stages[tostring(math.floor(cfg.stage))]
    if st then for _, k in ipairs(STAGE_KEYS) do st[k] = cfg[k] end end
    safe(json.dump_file, CFG_FILE, cfg)
end

local function apply_stage(n)
    local st = cfg.stages[tostring(math.floor(n))]
    if not st then return end
    cfg.stage = math.floor(n)
    for _, k in ipairs(STAGE_KEYS) do if st[k] ~= nil then cfg[k] = st[k] end end
    stage_changed = true
end

local function build_stages()
    cfg.stages = {}
    for n, def in pairs(DEFAULT_STAGES) do
        local t = {}
        for k, v in pairs(def) do t[k] = v end
        cfg.stages[n] = t
    end
end

load_cfg()

-- Boss spoils: default slots per category (placeholders, editable in the menu)
local DROP_CATS = { "standard", "veteran", "elite", "legendary", "mythical", "norgan" }
local DROP_CAT_NAMES = { standard = "Standard (Iron)", veteran = "Veteran (Steel)", elite = "Elite (Silver)",
    legendary = "Legendary (Gold)", mythical = "Mythical (Platinum)", norgan = "Norgan" }
local DEFAULT_DROP_SLOTS = {
    standard = { { lvl = 1, chance = 100.0, count = 2 }, { lvl = 2, chance = 50.18, count = 1 } },
    veteran = { { lvl = 2, chance = 100.0, count = 3 }, { lvl = 3, chance = 50.0, count = 2 } },
    elite = { { lvl = 3, chance = 100.0, count = 2 }, { lvl = 4, chance = 80.0, count = 2 }, { lvl = 4, chance = 30.0, count = 2 } },
    legendary = { { lvl = 4, chance = 100.0, count = 2 }, { lvl = 5, chance = 75.467, count = 1 }, { lvl = 5, chance = 40.773, count = 2 }, { lvl = 5, chance = 24.99, count = 1 } },
    mythical = { { lvl = 5, chance = 100.0, count = 3 }, { lvl = 5, chance = 80.328, count = 2 }, { lvl = 5, chance = 60.852, count = 2 }, { lvl = 5, chance = 20.765, count = 2 }, { lvl = 5, chance = 10.284, count = 2 } },
    norgan = { { lvl = 3, chance = 100.0, count = 2 }, { lvl = 4, chance = 50.0, count = 1 } },
}
local function copy_slots(t)
    local r = {}
    for i, sl in ipairs(t) do r[i] = { lvl = sl.lvl, chance = sl.chance, count = sl.count } end
    return r
end
if type(cfg.drop_slots) ~= "table" then cfg.drop_slots = {} end
for _, c in ipairs(DROP_CATS) do
    if type(cfg.drop_slots[c]) ~= "table" then cfg.drop_slots[c] = copy_slots(DEFAULT_DROP_SLOTS[c]) end
end
if type(cfg.stages) ~= "table" or not cfg.stages["1"] then build_stages() end
for n, def in pairs(DEFAULT_STAGES) do   -- options added in later versions start with their factory value; saved values are never overwritten
    if type(cfg.stages[n]) ~= "table" then cfg.stages[n] = {} end
    for k, v in pairs(def) do
        if cfg.stages[n][k] == nil then cfg.stages[n][k] = v end
    end
end
if not had_cfg then   -- nothing to migrate: the factory values above already are the current ones
    cfg.mig_noburst, cfg.mig_bossmin = 2, 2
    cfg.mig_cap, cfg.mig_stag, cfg.mig_knee, cfg.mig_tier = true, true, true, true
end
-- one-time migration: burst protection is off now (armor already reduces the hits); armor share per stage 60 / 40 / 20 %
if cfg.mig_noburst ~= 2 then
    local shares = { ["1"] = 0.6, ["2"] = 0.4, ["3"] = 0.2 }
    for n, st in pairs(cfg.stages) do
        st.burst_cooldown = 0.0
        if shares[n] then st.armor_share = shares[n] end
    end
    cfg.mig_noburst = 2
end
-- one-time migration: lower boss minimum HP per stage (220k / 260k / 340k)
if cfg.mig_bossmin ~= 2 then
    local mins = { ["1"] = 220000.0, ["2"] = 260000.0, ["3"] = 340000.0 }
    for n, st in pairs(cfg.stages) do if mins[n] then st.boss_min_hp = mins[n] end end
    cfg.mig_bossmin = 2
end
-- one-time migration: HP cap per stage (Normal 600,000, others 2,000,000) and Cyclops factor 1.2
if not cfg.mig_cap then
    local caps = { ["1"] = 600000.0, ["2"] = 2000000.0, ["3"] = 2000000.0 }
    for n, st in pairs(cfg.stages) do if caps[n] then st.max_hp_cap = caps[n] end end
    cfg.cyclops_mult = 1.2
    cfg.mig_cap = true
end
-- one-time migration: HP-dependent stagger linear, 0.8 at full HP, 2.0 at 0% HP
if not cfg.mig_stag then
    cfg.stag_full, cfg.stag_empty, cfg.stag_curve = 0.8, 2.0, 1.0
    cfg.mig_stag = true
end
-- one-time migration: Normal boss diminishing returns start at 300,000
if not cfg.mig_knee then
    if cfg.stages["1"] then cfg.stages["1"].boss_knee = 300000.0 end
    cfg.mig_knee = true
end
-- one-time migration: small enemies get their own diminishing returns (starting from the shared values);
-- minimum damage for the percent bonus and the Cyclops factor become per-difficulty values (keeping what was set)
if not cfg.mig_tier then
    for _, st in pairs(cfg.stages) do
        st.small_hp_knee, st.small_hp_curve = st.hp_knee, st.hp_curve
        st.small_hp_knee2, st.small_hp_curve2 = st.hp_knee2, st.hp_curve2
        st.small_bonus_min_dmg = cfg.small_bonus_min_dmg
        st.medium_bonus_min_dmg = cfg.medium_bonus_min_dmg
        st.large_bonus_min_dmg = cfg.large_bonus_min_dmg
        st.cyclops_mult = cfg.cyclops_mult
    end
    cfg.mig_tier = true
end
apply_stage(cfg.stage >= 1 and cfg.stage <= 3 and cfg.stage or 1)
stage_changed = false
if cfg.cfg_version ~= VERSION then
    cfg.cfg_version = VERSION
    save_cfg()
end

local framework_log = log
local log_lines = {}
local function log(s)
    log_lines[#log_lines + 1] = s
    if #log_lines > 12 then table.remove(log_lines, 1) end
    if DEBUG then safe(json.dump_file, "TrueHardMode_log.json", log_lines) end
end

local recheck = {}   -- { hit, t, id }

local done = {}       -- address -> true

local function get_player()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return nil end
    return safe(function() return cm:call("get_ManualPlayer") end)
end

local function player_in_norgan()
    local p = get_player()
    if not p then return false end
    return safe(function() return p:call("IsInNRDArea") end) == true
end

local function is_active()
    return cfg.enabled and cfg.norgan_visited
end

-- Level bonus (only while the main mod is not active yet): every 5 player levels +10 % HP for normal enemies, +5 % for bosses, up to level 50.
local function level_bonus_mult(is_boss)
    if not cfg.enabled or is_active() then return 1.0 end
    local p = get_player()
    local ctx = p and safe(function() return p:call("get_Context") end)
    local lvl = ctx and safe(function() return ctx:call("get_Level") end)
    if type(lvl) ~= "number" then return 1.0 end
    local steps = math.floor(math.min(lvl, cfg.level_max) / math.max(cfg.level_every, 1))
    return 1.0 + steps * (is_boss and cfg.level_pct_boss or cfg.level_pct) / 100.0
end

local function tier_factor(base)
    if base < cfg.small_below then return cfg.small_factor, "small" end
    if base >= cfg.large_above then return cfg.large_factor, "large" end
    return cfg.medium_factor, "medium"
end

-- Returns a short result string.
local type_cache = {}
local function type_of(tname)
    local t = type_cache[tname]
    if not t then
        t = safe(sdk.typeof, tname)
        type_cache[tname] = t
    end
    return t
end

local function comp(obj, tname)
    local go = safe(function() return obj:call("get_GameObject") end)
    local t = type_of(tname)
    if not (go and t) then return nil end
    return safe(function() return go:call("getComponent(System.Type)", t) end)
end

local health_notices = {}
local function health_unavailable(reason)
    if not health_notices[reason] then
        health_notices[reason] = true
        framework_log.info("[TrueHardMode] HP access skipped: " .. reason)
    end
    return nil, reason
end

local function health_state(hit, expected_character)
    if not hit or safe(sdk.is_managed_object, hit) ~= true
        or safe(function() return hit:call("get_Valid") end) ~= true then
        return health_unavailable("invalid HitController")
    end
    local ch = safe(function() return hit:get_field("<CachedCharacter>k__BackingField") end)
    if not ch or safe(sdk.is_managed_object, ch) ~= true
        or safe(function() return ch:call("get_Valid") end) ~= true then
        return health_unavailable("HitController character unavailable")
    end
    if expected_character then
        local expected_addr = safe(function() return expected_character:get_address() end)
        if not expected_addr or safe(function() return ch:get_address() end) ~= expected_addr then
            return health_unavailable("HitController character mismatch")
        end
    end
    -- get_Valid and CachedCharacter can survive teardown. Native HP getters dereference
    -- RegionData without a null check; pcall cannot prevent REFramework's native exception log.
    local regions = safe(function() return hit:get_field("RegionData") end)
    if not regions or safe(sdk.is_managed_object, regions) ~= true then
        return health_unavailable("RegionData unavailable")
    end
    local count = safe(function() return regions:get_field("_size") end)
    local items = safe(function() return regions:get_field("_items") end)
    local capacity = items and safe(function() return items:get_size() end)
    if type(count) ~= "number" or count < 1 or type(capacity) ~= "number" or count > capacity then
        return health_unavailable("RegionData not initialized")
    end
    for i = 0, count - 1 do
        local region = safe(function() return items:get_element(i) end)
        if not region or safe(sdk.is_managed_object, region) ~= true then
            return health_unavailable("RegionData contains an unavailable region")
        end
    end
    local context = safe(function() return hit:get_field("<HitContext>k__BackingField") end)
    if not context or safe(sdk.is_managed_object, context) ~= true then
        return health_unavailable("HitContext unavailable")
    end
    local ok, hp, maximum, reduced = pcall(function()
        return hit:call("get_Hp"), hit:call("get_OriginalMaxHp"), hit:call("get_ReducedMaxHp")
    end)
    if not ok then return health_unavailable("health read failed: " .. tostring(hp)) end
    for i = 1, 3 do
        local value = select(i, hp, maximum, reduced)
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
            return health_unavailable("invalid health values")
        end
    end
    if maximum <= 0 then
        return health_unavailable("health not initialized")
    end
    return { hp = hp, max = maximum, reduced = reduced, regions = count }
end

local stag_base = {}   -- address -> { base = reaction rate before the HP-dependent multiplier, last = value we wrote, seen = time }
local orig_hp = {}   -- address -> original max HP, remembered so the target is always absolute
local pre_existing = {}   -- enemies that were already there when the script started (their scaling state is unknown)
local variant_addr = {}   -- address -> true for boss variants that share their id with a normal enemy
local scan_started = false
local spawn_base = {}   -- address -> original max HP of THIS enemy when first seen (used to tell boss variants from normal enemies with the same id)

-- Enemies spawned by the DD2 Rifts mod are left completely alone: no HP, damage, stagger, reward, loss gauge or spoils changes.
-- That mod keeps a list of everything it spawned. Without it installed this does nothing.
local rift_mod, rift_mod_tried = nil, false
local rift_addr = {}   -- character address -> last time it was on the mod's list (kept a moment longer for kills and late hits)
local rift_ctl = nil   -- the rift mod's state: "idle", "armed" (announced) or "active" (waves are running)
local rift_running = false   -- while waves are running this mod is paused for every enemy, not only the listed ones
local function sync_rift_enemies(now)
    if not rift_mod_tried then
        rift_mod_tried = true
        local ok, m = pcall(require, "DD2Rifts/spawn_enemy")
        if ok and type(m) == "table" then rift_mod = m end
        local ok2, r = pcall(require, "DD2Rifts/rift")
        if ok2 and type(r) == "table" then rift_ctl = r end
    end
    rift_running = rift_ctl ~= nil and rift_ctl.state == "active"
    if not rift_mod or type(rift_mod.tracked) ~= "table" then return end
    for _, s in ipairs(rift_mod.tracked) do
        local a = s.chara and safe(function() return s.chara:get_address() end)
        if a then rift_addr[a] = now end
        -- a Chimera's goat and snake are characters of their own that the rift mod does not list
        if a and string.sub(tostring(s.id), 1, 5) == "ch254" then
            local ch2 = safe(function() return s.chara.EnemyCtrl.Ch2 end)
            for _, part in ipairs({ "G", "S" }) do
                local c = ch2 and safe(function() return ch2["<Ch254_" .. part .. ">k__BackingField"]._Chara end)
                local pa = c and safe(function() return c:get_address() end)
                if pa then rift_addr[pa] = now end
            end
        end
    end
    for a, t in pairs(rift_addr) do
        if now - t > 30 then rift_addr[a] = nil end
    end
end
local function is_rift_enemy(ch)
    local a = ch and safe(function() return ch:get_address() end)
    return a ~= nil and rift_addr[a] ~= nil
end
local function left_alone(ch)
    return rift_running or is_rift_enemy(ch)
end

local function scale_enemy(en, force)
    local ch = comp(en, "app.Character") or en
    if is_rift_enemy(ch) then return "skipped (rift enemy)" end
    local id = safe(function() return ch:call("get_CharaIDString") end) or "?"
    if not force then
        if not string.find(id, "^ch2") then return id .. ": skipped (not an enemy)" end
        if cfg.skip_animals and string.find(id, "^ch299") then return id .. ": skipped (animal)" end
    end
    if safe(function() return ch:call("get_IsNRDAreaEnemy") end) == true then
        return id .. ": skipped (Norgan enemy)"
    end
    local hit = comp(en, "app.HitController") or safe(function() return en:call("get_Hit") end)
    local health, reason = health_state(hit, ch)
    if not health then return id .. ": skipped (" .. reason .. ")", true end
    local base, hp = health.max, health.hp
    if hp <= 0 then return id .. ": skipped (dead)" end
    -- Stateless and absolute: the original max HP is learned per character id (lowest value ever seen),
    -- the target is always original x factor, so scaling the same enemy twice changes nothing.
    local repaired = false
    local cur_base = base
    local sa = safe(function() return en:get_address() end)
    local fresh = sa and not pre_existing[sa]          -- seen by us before any scaling happened
    if fresh and not spawn_base[sa] then spawn_base[sa] = base end
    -- A boss variant shares its id with a normal enemy (e.g. Giant Saurian / Saurian). Recognised by its own
    -- original max HP: at or above the "large" threshold while the id's normal value is below it.
    local lid = id
    if sa and (variant_addr[sa] or (fresh and base >= cfg.large_above and cfg.learned[id] and cfg.learned[id] < cfg.large_above)) then
        variant_addr[sa] = true
        lid = id .. "#boss"
    end
    local o = cfg.learned[lid]
    if not o or base < o then
        if cfg.max_hp_cap > 0 and base >= cfg.max_hp_cap * 0.999 and not o and cfg.repair_enabled then
            o = cfg.repair_hp          -- unknown original and absurdly high: use the repair value
            repaired = true
        else
            o = base
            cfg.learned[lid] = o
            save_cfg()
        end
    end
    base = o
    local f, tier = tier_factor(base)
    if not is_active() then       -- before Norgan: only the level bonus, for every enemy
        f = level_bonus_mult(tier == "large"); tier = "level"
        if f <= 1.0 then return id .. ": no level bonus" end
    end
    if repaired and not cfg.learned[lid] then f = 1.0; tier = "repair" end   -- repair value is the final value
    if f == 1.0 and not repaired then return id .. ": factor 1" end
    -- hard cap: never push the max HP above the limit (also makes repeated scaling harmless)
    if cfg.max_hp_cap > 0 then
        if base >= cfg.max_hp_cap then return id .. ": already at/above cap" end
    end
    local target = base * f
    -- diminishing returns for normal enemies: whatever would end up above the knee is flattened
    -- (not for the large/boss tier: bosses keep their plain factor)
    local k1, c1, k2, c2 = cfg.hp_knee, cfg.hp_curve, cfg.hp_knee2, cfg.hp_curve2
    if tier == "small" then k1, c1, k2, c2 = cfg.small_hp_knee, cfg.small_hp_curve, cfg.small_hp_knee2, cfg.small_hp_curve2 end
    if tier ~= "large" and tier ~= "level" and k1 > 0 and target > k1 then
        local raw = target
        if k2 > k1 and raw > k2 then
            local at_k2 = k1 * ((k2 / k1) ^ c1)
            target = at_k2 * ((raw / k2) ^ c2)
        else
            target = k1 * ((raw / k1) ^ c1)
        end
    end
    if tier == "large" and cfg.boss_knee > 0 and target > cfg.boss_knee then
        target = cfg.boss_knee * ((target / cfg.boss_knee) ^ cfg.boss_curve)
    end
    if tier ~= "level" and string.find(id, "^ch250000") then target = target * cfg.cyclops_mult end   -- Cyclops: extra HP
    if tier == "large" and target < cfg.boss_min_hp then target = cfg.boss_min_hp end   -- every boss has at least this much HP
    if tier == "small" and target < cfg.small_min_hp then target = cfg.small_min_hp end   -- same for small and medium enemies
    if tier == "medium" and target < cfg.medium_min_hp then target = cfg.medium_min_hp end
    if cfg.max_hp_cap > 0 and target > cfg.max_hp_cap then target = cfg.max_hp_cap end
    f = target / base
    -- Stagger: more HP but the same stagger thresholds would mean far more staggering per HP.
    -- Reaction damage is divided by (HP factor ^ stagger_follow), set as an absolute value (never compounds).
    local stag = ""
    if cfg.stagger_follow > 0 and tier ~= "level" then
        local sb = sa and stag_base[sa]     -- take our HP-dependent multiplier off first, the stage value is absolute
        if sb then pcall(function() hit:call("set_BaseReactionDamageRate", sb.base) end); stag_base[sa] = nil end
        local rr = safe(function() return hit:call("get_BaseReactionDamageRate") end)
        local want = 1.0 / ((target / base) ^ cfg.stagger_follow)
        if rr and rr <= 1.001 and rr >= 0.05 then
            if pcall(function() hit:call("set_BaseReactionDamageRate", want) end) then
                stag = string.format(", stagger x%.2f", want)
            end
        else
            stag = string.format(", stagger rate untouched (%s)", tostring(rr))
        end
    end
    if math.abs(cur_base - target) < 1 then return id .. ": already at target " .. string.format("%.0f", target) end
    local k = target / cur_base      -- factor relative to what the enemy has right now
    local n = health.regions
    local ratio = hp / cur_base
    local wrote = 0
    for i = 0, n - 1 do
        local rmax = safe(function() return hit:call("getRegionOriginalMaxHp", i) end)
        if rmax and rmax > 0 then
            if pcall(function() hit:call("setRegionOriginalMaxHp", rmax * k, i, false) end) then wrote = wrote + 1 end
        end
    end
    health, reason = health_state(hit, ch)
    if not health then return id .. ": scaling interrupted (" .. reason .. ")", true end
    local nmax = health.max
    if DEBUG then
        recheck[#recheck + 1] = { ch = ch, hit_addr = hit:get_address(), t = os.clock(), id = id }
    end
    -- the reduced max HP caps the current HP, so it has to be raised too
    local red = health.reduced
    if red and red > 0 then
        local newred = red * k
        if not pcall(function() hit:call("setReducedMaxHpValue", newred) end) then
            pcall(function() hit:call("set_ReducedMaxHp", newred) end)
        end
        health, reason = health_state(hit, ch)
        if not health then return id .. ": scaling interrupted (" .. reason .. ")", true end
        if health.reduced < newred * 0.99 then
            pcall(function() hit:call("set_ReducedMaxHp", newred) end)
        end
    end
    -- keep the current HP ratio (enemy starts full, so this is a full health bar)
    pcall(function() hit:call("setHpValue", nmax * ratio, false) end)
    health, reason = health_state(hit, ch)
    if not health then return id .. ": scaling interrupted (" .. reason .. ")", true end
    local nhp = health.hp
    return string.format("%s [%s x%.1f]: max %.0f -> %.0f, hp %.0f -> %.0f (regions %d/%d)",
        id .. (repaired and " (REPAIRED)" or ""), tier, f, base, nmax, hp, nhp, wrote, n) .. stag
end

-- Enemy damage: after the game has calculated a hit, multiply it when a base-game enemy hits the player/pawns.
math.randomseed(os.time())
local dmg_events = 0
local dbg = { calls = 0, applied = 0, blocked = 0, reason = "-", reasons = {}, events = {} }
local function char_of(go, tname)
    if not go then return nil end
    local t = type_of(tname)
    return t and safe(function() return go:call("getComponent(System.Type)", t) end)
end

local bonus_until = {}   -- attacker instance + receiver id -> os.clock() until which no further percent bonus is given

-- Armor estimate per receiver (you / each pawn): the game has already applied armor to every hit, so
-- final damage / raw damage shows how much gets through. Single hits vary (partial hits of a combo, element damage,
-- resistances), so the most common value of the last hits is used. It follows armor changes by itself.
local armor_estimate = {}   -- receiver id -> { list = {ratios}, value = 0.6 }
local ARMOR_WINDOW = 24
local function raw_damage(di)
    local function fld(n) return safe(function() return di:get_field(n) end) or 0 end
    return fld("SlashDamage") + fld("BlowDamage") + fld("ShootDamage") + fld("MagicDamage") + fld("EnchantDamage") * fld("EnchantRate")
end
local function sample_armor(di, dmg, rid)
    local raw = raw_damage(di)
    if raw <= 0 or dmg <= 0 then return nil, 0 end
    local ratio = dmg / raw
    local shown = ratio
    if ratio < 0.05 or ratio > 1.2 then return raw, shown end   -- far outliers (element boosts etc.) say nothing about the armor
    if ratio > 1.0 then ratio = 1.0 end
    local e = armor_estimate[rid]
    if not e then e = { list = {}, value = 1.0 }; armor_estimate[rid] = e end
    e.list[#e.list + 1] = ratio
    if #e.list > ARMOR_WINDOW then table.remove(e.list, 1) end
    local buckets, best, bestn = {}, 1.0, 0
    for _, r in ipairs(e.list) do
        local k = math.floor(r * 20 + 0.5) / 20            -- buckets of 0.05
        buckets[k] = (buckets[k] or 0) + 1
    end
    for k, n in pairs(buckets) do
        if n > bestn or (n == bestn and k > best) then best, bestn = k, n end
    end
    e.value = best                                           -- learns from the very first hit and follows changes
    return raw, shown
end

local hit_info = nil   -- what apply_damage_mult did with the current hit (shown in the damage window)
local function apply_damage_mult(di)
    local atk_go = safe(function() return di:get_field("<AttackOwnerObject>k__BackingField") end)
    local rcv_go = safe(function() return di:get_field("<DamageGameObject>k__BackingField") end)
    local atk = char_of(atk_go, "app.Character")
    local rcv = char_of(rcv_go, "app.Character")
    if not atk or not rcv then
        local an = atk_go and safe(function() return atk_go:call("get_Name") end)
        local rn = rcv_go and safe(function() return rcv_go:call("get_Name") end)
        dbg.reason = string.format("no component: attackerObj=%s receiverObj=%s", tostring(an), tostring(rn))
        return
    end
    local aid = safe(function() return atk:call("get_CharaIDString") end) or ""
    local rid = safe(function() return rcv:call("get_CharaIDString") end) or ""
    if not string.find(aid, "^ch2") then dbg.reason = "attacker not an enemy: " .. aid; return end
    if left_alone(atk) then dbg.reason = "rift"; hit_info = { note = T("rift: no change") }; return end
    if string.find(rid, "^ch2") or string.find(rid, "^ch3") then dbg.reason = "receiver is an enemy: " .. rid; return end
    if cfg.skip_animals and string.find(aid, "^ch299") then dbg.reason = "animal"; return end
    if safe(function() return atk:call("get_IsNRDAreaEnemy") end) == true then dbg.reason = "Norgan attacker"; return end
    -- no change for fall, poison and other non-attack damage
    local dtype = safe(function() return di:get_field("DamageType") end)
    local direct = safe(function() return di:get_field("IsDirectDamage") end)
    if direct == true and (dtype == -1 or dtype == 14 or dtype == 15) then dbg.reason = "fall/poison/fire damage (" .. aid .. ")"; return end
    local dmg = safe(function() return di:get_field("Damage") end)
    if not dmg then dbg.reason = "no Damage field"; return end
    if dmg <= 0 then dbg.reason = "zero damage"; return end
    local raw_dmg, raw_ratio = sample_armor(di, dmg, rid)
    local roll_mult = (math.random() * 100.0 < cfg.dmg_mult_chance) and cfg.dmg_mult_max or cfg.dmg_mult_min
    local newdmg = dmg * cfg.attack_mult * roll_mult
    -- bonus damage: random percent of the target's max HP, depending on the size of the attacker
    local rh = char_of(rcv_go, "app.HitController")
    local receiver_health, reason = health_state(rh, rcv)
    if not receiver_health then dbg.reason = "receiver health unavailable: " .. reason; return end
    local maxhp = receiver_health.max
    local abase = cfg.learned[aid]
    if not abase then
        local attacker_health
        attacker_health, reason = health_state(char_of(atk_go, "app.HitController"), atk)
        if not attacker_health then dbg.reason = "attacker health unavailable: " .. reason; return end
        abase = attacker_health.max
    end
    local lo, hi, min_dmg
    local is_large = abase >= cfg.large_above
    if abase < cfg.small_below then lo, hi, min_dmg = cfg.dmg_small_min, cfg.dmg_small_max, cfg.small_bonus_min_dmg
    elseif abase >= cfg.large_above then lo, hi, min_dmg = cfg.dmg_large_min, cfg.dmg_large_max, cfg.large_bonus_min_dmg or 500
    else lo, hi, min_dmg = cfg.dmg_med_min, cfg.dmg_med_max, cfg.medium_bonus_min_dmg end
    local nowc = os.clock()
    local ev_bonus, ev_through, ev_full = nil, nil, nil
    hit_info = {}
    if maxhp and maxhp > 0 and hi > 0 then
        local akey = tostring(safe(function() return atk:get_address() end) or aid) .. ">" .. rid
        if dmg < min_dmg then
            ev_bonus = nil                             -- weak hit (below the minimum base damage): no percent bonus
            hit_info.note = string.format(T("below %.0f: no bonus"), min_dmg)
        elseif (bonus_until[akey] or 0) > nowc then
            newdmg = newdmg * cfg.blocked_mult         -- no percent bonus: the base hit hits harder instead
            dbg.blocked = (dbg.blocked or 0) + 1      -- burst protection: this enemy already gave this target a percent hit
            hit_info.note = T("burst protection: no bonus")
        else
            local pct = lo + math.random() * math.max(hi - lo, 0)
            local bonus = maxhp * pct / 100.0
            if cfg.bonus_armor then
                local full = armor_estimate[rid] and armor_estimate[rid].value or 1.0
                local through = 1.0 - cfg.armor_share * (1.0 - full)     -- armor_share 1 = full armor effect, 0.5 = half of it
                ev_bonus = bonus; ev_through = through; ev_full = full
                bonus = bonus * through
                dbg.last_through = through
            end
            newdmg = newdmg + bonus
            hit_info.note = string.format(T("bonus +%.0f (%.1f%%)"), bonus, pct)
            bonus_until[akey] = nowc + math.max(cfg.burst_cooldown, 0)
        end
    end
    -- boss hits are capped: never more than a set percent of the target's max HP in one blow
    if is_large and cfg.dmg_large_cap > 0 and maxhp and maxhp > 0 then
        newdmg = math.min(newdmg, maxhp * cfg.dmg_large_cap / 100.0)
    end
    if math.abs(newdmg - dmg) < 0.01 then dbg.reason = "unchanged"; return end
    di:set_field("Damage", newdmg)
    dbg.applied = dbg.applied + 1
    dbg.reason = "ok"
    dbg.events[#dbg.events + 1] = string.format("%s -> %s: %.1f becomes %.1f%s", aid, rid, dmg, newdmg,
        ev_bonus and string.format(" | raw %.1f ratio %.2f | percent bonus %.1f x armor %.2f (measured %.2f) = %.1f", raw_dmg or 0, raw_ratio or 0, ev_bonus, ev_through, ev_full, ev_bonus * ev_through) or "")
    if #dbg.events > 60 then table.remove(dbg.events, 1) end
    dmg_events = dmg_events + 1
    if dmg_events <= 6 then log(string.format("DAMAGE %s -> %s: %.1f becomes %.1f", aid, rid, dmg, newdmg)) end
end

-- Damage window: every hit an enemy lands on the player, newest first. "before" is the game's own damage, before the mod touched it.
local dmg_rows = {}
local function record_hit(di, before)
    if before <= 0 then return end
    local rcv = char_of(di:get_field("<DamageGameObject>k__BackingField"), "app.Character")
    if not rcv or rcv:call("get_CharaIDString") ~= "ch000000_00" then return end
    local atk = char_of(di:get_field("<AttackOwnerObject>k__BackingField"), "app.Character")
    local aid = atk and atk:call("get_CharaIDString")
    if type(aid) ~= "string" or not string.find(aid, "^ch2") then return end
    local name = safe(function() return atk:call("get_CharaName") end)
    table.insert(dmg_rows, 1, {
        time = os.date("%H:%M:%S"),
        name = (type(name) == "string" and name ~= "") and name or aid,
        base = before, raw = raw_damage(di), total = di:get_field("Damage"),
        note = hit_info and hit_info.note or T("no bonus"),
    })
    if #dmg_rows > 30 then table.remove(dmg_rows) end
end

local hc_td = sdk.find_type_definition("app.HitController")
local cdv = hc_td and hc_td:get_method("calcDamageValue(app.HitController.DamageInfo)")
if cdv then
    sdk.hook(cdv, function(args)
        local st = thread.get_hook_storage()
        st.di = safe(sdk.to_managed_object, args[3])
    end, function(rv)
        local st = thread.get_hook_storage()
        local di = st.di
        dbg.calls = dbg.calls + 1
        local before = di and cfg.show_dmg_window and safe(function() return di:get_field("Damage") end)
        hit_info = nil
        if not di then dbg.reason = "no DamageInfo"
        elseif cfg.enabled and is_active() and (cfg.attack_mult ~= 1.0 or cfg.blocked_mult ~= 1.0 or cfg.dmg_mult_max ~= 1.0 or cfg.dmg_small_max > 0 or cfg.dmg_med_max > 0 or cfg.dmg_large_max > 0) then
            dbg.reason = "-"
            local ok, err = pcall(apply_damage_mult, di)
            if not ok then dbg.reason = "error: " .. tostring(err) end
        else dbg.reason = "mod inactive" end
        if before then pcall(record_hit, di, before) end
        dbg.reasons[dbg.reason] = (dbg.reasons[dbg.reason] or 0) + 1
        return rv
    end)
else
    dbg.reason = "hook target calcDamageValue not found"
end

-- Max HP loss ("loss gauge"): the game takes about 5 % of every hit's damage away from the player's max HP.
-- Our enemies hit much harder, so the loss is scaled down: after the game has applied a hit (updateDamage) the
-- loss of that hit is multiplied by loss_mult (1 = base game).
local loss_dbg = { calls = 0, changed = 0, events = {}, last = "-" }
local loss_m = hc_td and hc_td:get_method("updateDamage(app.HitController.DamageInfo, System.UInt32, System.Single, System.Boolean)")
if loss_m then
    sdk.hook(loss_m, function(args)
        local st = thread.get_hook_storage()
        st.before = nil
        st.loss_hit, st.loss_character = nil, nil
        if not cfg.enabled or not cfg.norgan_visited or cfg.loss_mult >= 0.999 then return end
        local player = get_player()
        if not player then return end
        local this = safe(sdk.to_managed_object, args[2])
        local character = this and safe(function() return this:get_field("<CachedCharacter>k__BackingField") end)
        if not character or safe(function() return character:get_address() end) ~= safe(function() return player:get_address() end) then return end
        local di = safe(sdk.to_managed_object, args[3])
        local atk_go = di and safe(function() return di:get_field("<AttackOwnerObject>k__BackingField") end)
        if left_alone(char_of(atk_go, "app.Character")) then return end   -- rift: base game loss
        local health = health_state(this, player)
        if not health then return end
        st.before, st.loss_hit, st.loss_character = health.reduced, this, player
    end, function(rv)
        local st = thread.get_hook_storage()
        local before = st.before
        local hit, character = st.loss_hit, st.loss_character
        st.before, st.loss_hit, st.loss_character = nil, nil, nil
        if not before or not hit then return rv end
        local health, reason = health_state(hit, character)
        if not health then loss_dbg.last = "skipped: " .. reason; return rv end
        loss_dbg.calls = loss_dbg.calls + 1
        local after = health.reduced
        if after >= before - 0.001 then return rv end        -- no loss from this hit
        local newv = before - (before - after) * cfg.loss_mult
        if not pcall(function() hit:call("setReducedMaxHp", newv) end) then
            pcall(function() hit:call("setReducedMaxHpValue", newv) end)
        end
        health, reason = health_state(hit, character)
        if not health then loss_dbg.last = "verification unavailable: " .. reason; return rv end
        local chk = health.reduced
        loss_dbg.changed = loss_dbg.changed + 1
        loss_dbg.last = string.format("lost %.1f -> %.1f (now %s)", before - after, before - newv, tostring(chk))
        return rv
    end)
else
    loss_dbg.last = "hook target updateDamage not found"
end

-- Spawn detection: scan the scene for enemies; scale each one once, after it has existed for a moment.
local first_seen = {}   -- address -> time first seen
local scan_t = 0

local function scene_enemies_of(tname)
    local scene = safe(function()
        return sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    end)
    local t = safe(sdk.typeof, tname)
    if not (scene and t) then return {} end
    local arr = safe(function() return scene:call("findComponents(System.Type)", t) end)
    return managed_elements(arr)
end
local function scene_enemies()
    return scene_enemies_of("app.Ch200000")
end

local last_seen = {}

-- Experience / discipline reward: record every kill so base game and Norgan values can be compared.
local exp_log = {}
local exp_td = sdk.find_type_definition("app.ExpDispenser")
local exp_m = exp_td and exp_td:get_method("addExpAndJobPoint(app.CharacterID, System.Int32, app.Character, app.HitController.DamageInfo)")
if exp_m then
    -- static method: real parameters start at args[2]
    sdk.hook(exp_m, function(args)
        local exp = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local di = safe(sdk.to_managed_object, args[5])
        local go = di and safe(function() return di:get_field("<DamageGameObject>k__BackingField") end)
        local ch
        if go then
            local t = safe(sdk.typeof, "app.Character")
            ch = t and safe(function() return go:call("getComponent(System.Type)", t) end)
        end
        local id = ch and safe(function() return ch:call("get_CharaIDString") end) or "?"
        local nrd = ch and safe(function() return ch:call("get_IsNRDAreaEnemy") end)
        local hit
        if go then
            local t = safe(sdk.typeof, "app.HitController")
            hit = t and safe(function() return go:call("getComponent(System.Type)", t) end)
        end
        local health = health_state(hit, ch)
        local maxhp = health and health.max
        local entry = { id = id, norgan_enemy = nrd, exp_original = exp, max_hp_now = maxhp, time = os.date("%H:%M:%S") }
        local lo = cfg.learned[id]
        local hpf = (maxhp and lo and lo > 0) and (maxhp / lo) or 1.0
        entry.hp_factor = hpf
        if maxhp and is_active() and nrd ~= true and not left_alone(ch) and string.find(id, "^ch2") and (cfg.exp_follow > 0 or cfg.exp_mult ~= 1.0 or cfg.exp_per_hp > 0) then
            local newexp
            if cfg.exp_per_hp > 0 and maxhp and hpf > 1.0 then
                local ref = math.max(cfg.exp_ref_hp, 1.0)
                local base_reward = cfg.exp_per_hp * ref * ((maxhp / ref) ^ cfg.exp_curve)
                newexp = math.floor(base_reward * cfg.exp_mult + 0.5)
            else
                local m = (hpf > 1.0 and hpf ^ cfg.exp_follow or 1.0) * cfg.exp_mult
                newexp = math.floor(exp * m + 0.5)
            end
            args[3] = sdk.to_ptr(newexp)
            entry.exp_given = newexp
        end
        exp_log[#exp_log + 1] = entry
        if #exp_log > 80 then table.remove(exp_log, 1) end
        if DEBUG then safe(json.dump_file, "TrueHardMode_exp.json", exp_log) end
    end)
end
local last_sig = ""
local function scan(now)
    if rift_running then return end      -- paused during a rift: enemies that outlive it are scaled afterwards
    local sig = tostring(is_active()) .. ":" .. tostring(level_bonus_mult(false)) .. ":" .. tostring(level_bonus_mult(true))   -- mode or level bonus changed: look at everybody again
    if sig ~= last_sig then last_sig = sig; stage_changed = true end
    if stage_changed then stage_changed = false; done = {}; first_seen = {} end
    local list = scene_enemies()
    if #list == 0 then return end        -- a failed/empty scan must never forget anything
    if not scan_started then             -- everything that exists at the first scan after (re)loading the script: scaling state unknown
        scan_started = true
        for _, e in ipairs(list) do
            local a = safe(function() return e:get_address() end)
            if a then pre_existing[a] = true end
        end
    end
    for _, e in ipairs(list) do
        local a = safe(function() return e:get_address() end)
        if a then
            last_seen[a] = now
            if not done[a] then
                local t0 = first_seen[a]
                if not t0 then
                    first_seen[a] = now
                elseif now - t0 >= 0.7 then
                    local result, retry = scale_enemy(e, false)
                    if not retry then done[a] = true end
                    log(result)
                end
            end
        end
    end
    -- forget enemies that have been gone for a long time (addresses can be reused)
    for a, t in pairs(last_seen) do
        if now - t > 30 then last_seen[a] = nil; done[a] = nil; first_seen[a] = nil; orig_hp[a] = nil; spawn_base[a] = nil; variant_addr[a] = nil; pre_existing[a] = nil end
    end
end

local last_poll, last_n = 0, 0
-- HP-dependent stagger: the less HP an enemy has left, the easier it is to stagger / knock down.
-- Works on the reaction rate that is in place after the difficulty scaling; Norgan enemies and bosses included.
local dyn_t = 0
local function dyn_stagger(now)
    local list = scene_enemies()
    for _, e in ipairs(list) do
        local a = safe(function() return e:get_address() end)
        local ch = a and comp(e, "app.Character")
        local id = ch and safe(function() return ch:call("get_CharaIDString") end)
        if type(id) == "string" and string.find(id, "^ch2") and not left_alone(ch) and not (cfg.skip_animals and string.find(id, "^ch299")) then
            local hit = comp(e, "app.HitController")
            local health = health_state(hit, ch)
            local rr = health and safe(function() return hit:call("get_BaseReactionDamageRate") end)
            if health and rr and health.hp > 0 then
                local hp, mx = health.hp, health.max
                local st = stag_base[a]
                if not st or math.abs(rr - st.last) > 0.002 then
                    st = { base = rr, last = rr }          -- new enemy, or the rate was set by someone else: start from there
                    stag_base[a] = st
                end
                st.seen = now
                local frac = math.min(math.max(hp / mx, 0.0), 1.0)
                local m = cfg.stag_full + (cfg.stag_empty - cfg.stag_full) * ((1.0 - frac) ^ math.max(cfg.stag_curve, 0.1))
                local want = st.base * m
                if math.abs(want - rr) > 0.003 then
                    if pcall(function() hit:call("set_BaseReactionDamageRate", want) end) then
                        st.last = safe(function() return hit:call("get_BaseReactionDamageRate") end) or want
                    end
                end
            end
        end
    end
    for a, st in pairs(stag_base) do if now - (st.seen or 0) > 30 then stag_base[a] = nil end end
end
-- Camp meal: restores the lost max HP (loss gauge) of the player and the pawns, like a night's rest.
local meal_reset_at = nil
local meal_last = "-"
local function restore_loss_gauge(hc, ch)
    local health = health_state(hc, ch)
    if not health then return false end
    local orig, red = health.max, health.reduced
    if red >= orig - 0.001 then return false end
    if not pcall(function() hc:call("setReducedMaxHp", orig) end) then
        if not pcall(function() hc:call("setReducedMaxHpValue", orig) end) then return false end
    end
    return true
end
local function do_meal_reset()
    local n, total, seen = 0, 0, {}
    local list = {}
    local pl = get_player()
    if pl then list[#list + 1] = pl end
    for _, tn in ipairs({ "app.Character", "app.Ch100000" }) do
        for _, e in ipairs(scene_enemies_of(tn)) do list[#list + 1] = e end
    end
    for _, ch in ipairs(list) do
        local addr = safe(function() return ch:get_address() end)
        local id = safe(function() return ch:call("get_CharaIDString") end)
        if addr and not seen[addr] and type(id) == "string" and (id == "ch000000_00" or string.find(id, "^ch1")) then
            seen[addr] = true
            local hit = comp(ch, "app.HitController")
            if hit then
                total = total + 1
                if restore_loss_gauge(hit, ch) then n = n + 1 end
            end
        end
    end
    meal_last = string.format(T("%s: loss gauge restored for %d of %d party members"), os.date("%H:%M:%S"), n, total)
end
local camp_td = sdk.find_type_definition("app.CampManager")
local meal_m = camp_td and camp_td:get_method("requestMeal")
if meal_m then
    sdk.hook(meal_m, function() end, function(rv)
        if cfg.enabled and cfg.meal_reset then meal_reset_at = os.clock() + 1.5 end
        return rv
    end)
else
    meal_last = T("camp meal hook not found")
end

-- Debug: Ferrystone everywhere. The game asks QuestManager.isUseFerrystone before a teleport; with the box ticked the answer is always yes.
local ferry_hooks, ferry_forced = 0, 0
local qm_td = sdk.find_type_definition("app.QuestManager")
for _, sig in ipairs({ "isUseFerrystone()", "isUseFerrystone(via.Position)" }) do
    local m = qm_td and qm_td:get_method(sig)
    if m then
        ferry_hooks = ferry_hooks + 1
        sdk.hook(m, function() end, function(rv)
            if not cfg.debug_ferrystone then return rv end
            if safe(function() return sdk.to_int64(rv) & 1 end) == 0 then ferry_forced = ferry_forced + 1 end
            return sdk.to_ptr(1)
        end)
    end
end

re.on_frame(function()
    local now = os.clock()
    if now - last_poll < 0.25 then return end
    last_poll = now
    safe(sync_rift_enemies, now)

    if meal_reset_at and now >= meal_reset_at then meal_reset_at = nil; safe(do_meal_reset) end

    if not cfg.norgan_visited and now - last_n > 1.0 then
        last_n = now
        if player_in_norgan() then
            cfg.norgan_visited = true
            save_cfg()
            log("First Norgan visit remembered.")
        end
    end

    for k = #recheck, 1, -1 do
        local r = recheck[k]
        if now - r.t >= 1.5 then
            table.remove(recheck, k)
            local valid = safe(function() return r.ch:call("get_Valid") end) == true
            local hit = valid and comp(r.ch, "app.HitController")
            if hit and safe(function() return hit:get_address() end) == r.hit_addr then
                local health, reason = health_state(hit, r.ch)
                if health then
                    local br = safe(function() return hit:call("get_BaseReactionDamageRate") end)
                    local rc = safe(function() return hit:call("get_ReactionDamageRateCalc") end)
                    log(string.format("RECHECK %s after 1.5s: max %s, reducedMax %s, hp %s, reactionBase %s, reactionCalc %s", r.id, tostring(health.max), tostring(health.reduced), tostring(health.hp), tostring(br), tostring(rc)))
                else
                    log("RECHECK " .. r.id .. " skipped: " .. reason)
                end
            else
                log("RECHECK " .. r.id .. " skipped: character unloaded or controller replaced")
            end
        end
    end

    if DEBUG and now - (dbg.saved or 0) >= 2.0 then
        dbg.saved = now
        safe(json.dump_file, "TrueHardMode_damage.json", { calls = dbg.calls, applied = dbg.applied, bonus_blocked = dbg.blocked, last = dbg.reason, reasons = dbg.reasons, events = dbg.events, loss = loss_dbg })
    end
    if cfg.enabled and cfg.dyn_stagger and now - dyn_t >= 1.0 then
        dyn_t = now
        safe(dyn_stagger, now)
    elseif cfg.enabled and now - scan_t >= 1.0 then      -- never both in the same frame
        scan_t = now
        scan(now)
    end
end)

-- Info windows: enemy HP around the player and the hits the player just took.
local function pos_of(component)
    local go = safe(function() return component:call("get_GameObject") end)
    local tr = go and safe(function() return go:call("get_Transform") end)
    return tr and safe(function() return tr:call("get_Position") end)
end

local hp_rows, hp_t = {}, -10
local function refresh_hp_rows(now)
    hp_t = now
    hp_rows = {}
    local p = get_player()
    local ppos = p and pos_of(p)
    if not ppos then return end
    for _, e in ipairs(scene_enemies()) do
        local ch = comp(e, "app.Character")
        local id = ch and safe(function() return ch:call("get_CharaIDString") end)
        if type(id) == "string" and string.find(id, "^ch2") and not string.find(id, "^ch299") then
            local epos = pos_of(e)
            local d = epos and math.sqrt((epos.x - ppos.x) ^ 2 + (epos.y - ppos.y) ^ 2 + (epos.z - ppos.z) ^ 2)
            if d and d <= cfg.hp_window_radius then      -- far enemies may not be fully loaded
                local hit = comp(e, "app.HitController")
                local health = health_state(hit, ch)
                if health and health.hp > 0 and health.reduced > 0 then
                    local hp, mx = health.hp, health.reduced
                    local name = safe(function() return ch:call("get_CharaName") end)
                    local a = safe(function() return e:get_address() end)
                    local tier = "boss"
                    if not (a and variant_addr[a]) then
                        local _, t = tier_factor(cfg.learned[id] or mx)
                        tier = t == "large" and "boss" or t
                    end
                    if is_rift_enemy(ch) then tier = "rift" end
                    hp_rows[#hp_rows + 1] = { name = (type(name) == "string" and name ~= "") and name or id, tier = tier, hp = hp, max = mx, d = d }
                end
            end
        end
    end
    table.sort(hp_rows, function(x, y) return x.d < y.d end)
end

local function draw_windows()
    if cfg.show_hp_window then
        local now = os.clock()
        if now - hp_t >= 1.0 then safe(refresh_hp_rows, now) end
        imgui.set_next_window_pos(Vector2f.new(20, 380), 4)    -- first use only
        imgui.set_next_window_size(Vector2f.new(360, 170), 4)
        cfg.show_hp_window = imgui.begin_window(T("True Hard Mode - Enemy HP"), cfg.show_hp_window, 0)
        if cfg.show_hp_window then
            if #hp_rows == 0 then imgui.text(T("No enemies nearby.")) end
            for i = 1, math.min(#hp_rows, math.floor(cfg.hp_window_rows)) do
                local r = hp_rows[i]
                imgui.text(string.format(T("%s [%s]  %.0f / %.0f  (%.0f%%)  %.0fm"), r.name, r.tier, r.hp, r.max, r.hp / r.max * 100.0, r.d))
            end
            imgui.end_window()
        else
            save_cfg()
        end
    end
    if cfg.show_dmg_window then
        imgui.set_next_window_pos(Vector2f.new(20, 560), 4)    -- first use only
        imgui.set_next_window_size(Vector2f.new(560, 220), 4)
        cfg.show_dmg_window = imgui.begin_window(T("True Hard Mode - Damage taken"), cfg.show_dmg_window, 0)
        if cfg.show_dmg_window then
            imgui.text(T("Base = after armor (used by the minimum damage sliders), raw = before armor."))
            if #dmg_rows == 0 then imgui.text(T("No hits taken yet.")) end
            for i = 1, math.min(#dmg_rows, math.floor(cfg.dmg_window_rows)) do
                local r = dmg_rows[i]
                imgui.text(string.format(T("%s  %s  base %.1f (raw %.0f)  %s  total %.0f"), r.time, r.name, r.base, r.raw, r.note, r.total))
            end
            imgui.end_window()
        else
            save_cfg()
        end
    end
end
re.on_frame(function() with_lang_font(draw_windows) end)

-- ============================================================================
-- Boss spoils: bosses drop Spoils (items 50000+) according to their Guild Contracts category.
-- Every slot rolls once (chance %), then drops `count` pieces, each a random type of the chosen level.
-- ============================================================================
local BOSS_CATEGORY = {
    ch221000_00 = "standard", ch221001_00 = "veteran", ch221004_00 = "elite",
    ch223004_00 = "norgan", ch226003_00 = "veteran", ch227000_00 = "elite", ch227001_00 = "veteran",
    ch229000_00 = "legendary",
    ch250001_00 = "norgan", ch250002_00 = "norgan",
    ch251000_00 = "standard", ch251001_00 = "elite", ch251002_00 = "norgan",
    ch252000_00 = "standard", ch252000_01 = "veteran", ch252000_02 = "elite", ch252000_03 = "legendary",
    ch253000_00 = "veteran", ch253000_60 = "norgan", ch253012_00 = "norgan",
    ch254000_00 = "elite", ch254001_00 = "legendary", ch255000_01 = "mythical",
    ch256000_00 = "standard", ch256001_00 = "elite",
    ch257000_00 = "legendary", ch257001_00 = "mythical", ch257003_00 = "norgan",
    ch260000_00 = "veteran", ch261000_00 = "norgan",
}
-- Cyclops: the first digit after the underscore is the armor level, the second one only the look.
-- ch250000_0x = no armor, ch250000_1x = Armored Cyclops, ch250000_2x = Fully Armored Cyclops.
-- ch250000_5x = Corrupted Cyclops, counted like the plain Cyclops.
local CYCLOPS_BY_ARMOR = { ["0"] = "standard", ["1"] = "veteran", ["2"] = "elite", ["5"] = "standard" }
-- Bestiary variants share their id with the normal enemy, so they are told apart by their variant name.
-- Same categories as in the Guild Contracts mod. Without Bestiary this table is simply never used.
local VARIANT_CATEGORY = {
    GiantSaurian = "standard", SulfuricAsp = "veteran",
    SerpentSage = "elite", ColossalCyclops10 = "elite", ColossalCyclops11 = "elite", ColossalCyclops12 = "elite",
    DireGarm = "elite", SkeletonOverlord = "elite", SanguineSuccubus = "elite", OniOgre = "elite",
    TemperedCyclops = "legendary", BlackGriffin = "legendary", BazelMinotaur = "legendary", Wyrm = "legendary", Wyvern = "legendary",
    HallowedChimera = "mythical", BlackDragon = "mythical", Frostfoot = "norgan",
}
local SPOILS_BASE, SPOILS_PER_LEVEL = 50000, 21   -- per level: 7 normal types, then 14 "Ancient" types

local ISSUE_TYPE = "app.ItemDropLottery.ItemResult"
local drop_ctx = {}       -- thread hash -> { id, enemy, hits, is_death, applied, in_all }
local drop_states = {}    -- gather address -> { enemy, native, hits, index }
local drop_last = "-"

local variant_mod, variant_mod_tried = nil, false
local function bestiary_variant(en)
    if not variant_mod_tried then
        variant_mod_tried = true
        local ok, m = pcall(require, "Bestiary/Utils/Variant")
        if ok and type(m) == "table" and m.get_variant_params then variant_mod = m end
    end
    if not variant_mod then return nil end
    local _, name = variant_mod.get_variant_params(en)
    return name
end

-- Which spoils category an enemy belongs to: variant name first, then its id. Returns category, variant name.
local function drop_category(id, en)
    local vname = safe(bestiary_variant, en)
    if vname and VARIANT_CATEGORY[vname] then return VARIANT_CATEGORY[vname], vname end
    if BOSS_CATEGORY[id] then return BOSS_CATEGORY[id], nil end
    local armor = string.match(id, "^ch250000_(%d)%d$")
    if armor then return CYCLOPS_BY_ARMOR[armor], nil end
    -- other forms of a known boss: _4x and _5x = corrupted (same category as the normal one), _6x = Norgan form
    local stem, form = string.match(id, "^(ch%d+)_([456])%d$")
    local normal = stem and BOSS_CATEGORY[stem .. "_00"]
    if not normal then return nil, nil end
    return form == "6" and "norgan" or normal, nil
end

local function roll_spoils(c)
    local cat = c.cat
    local slots = cat and cfg.drop_slots[cat]
    local hits = {}
    if not slots then return hits end
    local per = cfg.drops_ancient and SPOILS_PER_LEVEL or 7
    for _, sl in ipairs(slots) do
        if math.random() * 100 < (tonumber(sl.chance) or 0) then
            local lvl = math.max(1, math.min(5, math.floor(tonumber(sl.lvl) or 1)))
            for _ = 1, math.max(1, math.floor(tonumber(sl.count) or 1)) do
                hits[#hits + 1] = SPOILS_BASE + SPOILS_PER_LEVEL * (lvl - 1) + math.random(0, per - 1)
            end
        end
    end
    drop_last = string.format(T("%s%s, %s: %d spoils"), c.id, c.vname and (" (" .. c.vname .. ")") or "", T(DROP_CAT_NAMES[cat] or "?"), #hits)
    return hits
end

local function drop_enemy_info(args)
    local en = sdk.to_managed_object(args[2])
    if not en or left_alone(en) then return nil end
    local id = safe(function() return en:call("get_CharaIDString") end)
    if type(id) ~= "string" then return nil end
    local cat, vname = drop_category(id, en)
    if not cat then return nil end
    -- only real bosses: this enemy's own original max HP must be at or above the "large" threshold
    -- (normal Saurians share the id with boss Saurians, so the id alone is not enough)
    local base = spawn_base[safe(function() return en:get_address() end) or 0] or cfg.learned[id]
    -- Golems are always real bosses, even though the normal Golem has fewer original HP than the boss threshold
    if not string.find(id, "^ch252") and (type(base) ~= "number" or base < cfg.large_above) then return nil end
    if not safe(function() return en:call("get_EnemyController") end) then return nil end
    return { id = id, enemy = en, applied = false, cat = cat, vname = vname }
end

local function drop_begin(is_death)
    return function(args)
        if not cfg.enabled or not cfg.drops_enabled then return end
        local st = thread.get_hook_storage()
        local key = thread.get_hash()
        st.thm_prev = drop_ctx[key]
        local c = safe(drop_enemy_info, args)
        if c then c.is_death = is_death end
        drop_ctx[key] = c
    end
end
local function drop_end(retval)
    local key = thread.get_hash()
    local c = drop_ctx[key]
    local prev = thread.get_hook_storage().thm_prev
    if c and c.applied and prev and prev.enemy == c.enemy then prev.applied = true end
    drop_ctx[key] = prev
    return retval
end

local ch_td = sdk.find_type_definition("app.Character")
local lot_td = sdk.find_type_definition("app.ItemDropLottery")
local res_td = sdk.find_type_definition(ISSUE_TYPE)
local d_prepare = ch_td and ch_td:get_method("prepareCharacterFumbleLotNum(System.Boolean)")
local d_dead = ch_td and ch_td:get_method("setDeadDropItemNum()")
local d_all = lot_td and lot_td:get_method("processCharacterFumbleLotItemAll()")
local d_prep_lot = lot_td and lot_td:get_method("prepareCharacterFumbleLotNum(app.GatherContext, app.CharacterExtendedGatherContext, System.Boolean)")
local d_item = lot_td and lot_td:get_method("processCharacterFumbleLotItem(app.GatherContext, app.CharacterExtendedGatherContext, System.Int32, System.Boolean, System.Boolean)")

if d_prepare and d_dead and d_all and d_prep_lot and d_item and res_td and res_td:get_valuetype_size() == 12 then
    sdk.hook(d_prepare, drop_begin(false), drop_end)
    sdk.hook(d_dead, drop_begin(true), drop_end)

    -- Path 1: the game builds a whole result array at once -> append our items to it
    sdk.hook(d_all, function()
        local c = drop_ctx[thread.get_hash()]
        thread.get_hook_storage().thm_c = c
        if c then c.in_all = true end
    end, function(retval)
        local c = thread.get_hook_storage().thm_c
        if not c then return retval end
        c.in_all = nil
        if c.applied then return retval end
        c.applied = true
        local ok, res = pcall(function()
            local hits = roll_spoils(c)
            if #hits == 0 then return nil end
            local orig = sdk.to_managed_object(retval)
            local n = orig and orig:get_size() or 0
            local arr = sdk.create_managed_array(ISSUE_TYPE, n + #hits)
            if not arr then return nil end
            arr = arr:add_ref()
            for i = 0, n - 1 do arr:call("SetValue(System.Object, System.Int32)", orig:get_element(i), i) end
            for i, item in ipairs(hits) do
                local e = sdk.create_instance(ISSUE_TYPE) or sdk.create_instance(ISSUE_TYPE, true)
                if not e then return nil end
                e = e:add_ref()
                e:set_field("Id", item); e:set_field("Num", 1); e:set_field("ExtensionValue", 0)
                arr:call("SetValue(System.Object, System.Int32)", e, n + i - 1)
            end
            return arr
        end)
        if ok and res then return sdk.to_ptr(res) end
        return retval
    end)

    -- Path 2: the game draws item by item from a gather counter -> raise the counter and feed our items first
    sdk.hook(d_prep_lot, function(args)
        local st = thread.get_hook_storage()
        st.thm_gather = sdk.to_managed_object(args[3])
        st.thm_pc = drop_ctx[thread.get_hash()]
        local g = st.thm_gather
        if g and g:call("get_Num") == -1 then drop_states[g:get_address()] = nil end
    end, function(retval)
        local st = thread.get_hook_storage()
        local c, g = st.thm_pc, st.thm_gather
        pcall(function()
            if not c or not g or not c.is_death or c.in_all or c.applied then return end
            local key = g:get_address()
            local prev = drop_states[key]
            if prev and prev.enemy == c.enemy then return end
            local n = g:call("get_Num")
            if type(n) ~= "number" or n < 0 or n > 127 then return end
            local hits = roll_spoils(c)
            drop_states[key] = { enemy = c.enemy, gather = g, native = n, hits = hits, index = 1 }
            c.applied = true
            if #hits > 0 then
                g:call("set_Num(System.Int32)", n + #hits)
            end
        end)
        return retval
    end)
    sdk.hook(d_item, function(args)
        if not cfg.enabled or not cfg.drops_enabled then return end
        local st = thread.get_hook_storage()
        local ok, skip = pcall(function()
            if not sdk.is_managed_object(args[4]) then return end
            local g = sdk.to_managed_object(args[4])
            local state = drop_states[g:get_address()]
            local item = state and state.hits[state.index]
            if not item then return end
            local n = g:call("get_Num")
            if n <= state.native then return end
            sdk.set_native_field(args[1], res_td, "Id", item)
            sdk.set_native_field(args[1], res_td, "Num", 1)
            sdk.set_native_field(args[1], res_td, "ExtensionValue", 0)
            g:call("set_Num(System.Int32)", n - 1)
            state.index = state.index + 1
            st.thm_item_result = args[1]
            return true
        end)
        if ok and skip then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(retval)
        return thread.get_hook_storage().thm_item_result or retval
    end)
else
    drop_last = T("hooks not available - spoils drops disabled")
end

re.on_script_reset(function() drop_ctx = {}; drop_states = {} end)
re.on_script_reset(function() pcall(save_cfg) end)      -- every setting is written once more when the scripts are reset
re.on_config_save(function() pcall(save_cfg) end)    -- and whenever REFramework saves its own config

re.on_script_reset(function() done = {}; first_seen = {}; last_seen = {} end)

local stage_names_list = nil
local function stage_names_shown()
    if not stage_names_list then
        stage_names_list = {}
        for i, n in ipairs(STAGE_NAMES) do stage_names_list[i] = T(n) end
    end
    return stage_names_list
end

local function draw_menu()
    if not imgui.tree_node("True Hard Mode " .. VERSION) then return end
    local ch, v
    ch, v = imgui.checkbox(T("Enabled"), cfg.enabled); if ch then cfg.enabled = v; save_cfg() end
    if is_active() then
        imgui.text_colored(T("Active - enemies use the full difficulty settings"), 0xFF66DD66)
    else
        imgui.text_colored(T("Not active yet - waiting for your first visit to Norgan"), 0xFF4499FF)
        imgui.text(T("Until then enemy HP only grows with your level (+10% per 5 levels, bosses +5%, up to level 50)."))
    end
    if rift_running then imgui.text_colored(T("Paused - a rift is running"), 0xFF4499FF) end
    if cfg.norgan_visited then
        if imgui.button(T("Reset to pre-Norgan strength")) then cfg.norgan_visited = false; save_cfg() end
        imgui.text(T("For when Norgan is too hard: enemies drop back to the level-based bonus. The full difficulty"))
        imgui.text(T("returns as soon as you enter Norgan again. Press it outside of Norgan, or it switches right back."))
    end
    imgui.spacing()
    local sc, sv = imgui.combo(T("Difficulty"), cfg.stage, stage_names_shown())
    if sc then apply_stage(sv); save_cfg() end
    imgui.text(T(STAGE_INFO[cfg.stage] or ""))
    imgui.text(T("Changes apply to enemies within a few seconds."))
    imgui.spacing()
    ch, v = imgui.checkbox(T("Camp meals reset the loss gauge (you and your pawns)"), cfg.meal_reset); if ch then cfg.meal_reset = v; save_cfg() end
    imgui.text(T("Last meal reset: ") .. meal_last)
    ch, v = imgui.checkbox(T("Enemies get easier to stagger as they lose HP (everywhere, Norgan too)"), cfg.dyn_stagger); if ch then cfg.dyn_stagger = v; save_cfg() end
    ch, v = imgui.checkbox(T("Bosses drop Spoils (untick if another mod handles boss loot)"), cfg.drops_enabled); if ch then cfg.drops_enabled = v; save_cfg() end
    ch, v = imgui.checkbox(T("Show enemy HP window"), cfg.show_hp_window); if ch then cfg.show_hp_window = v; save_cfg() end
    ch, v = imgui.checkbox(T("Show damage taken window"), cfg.show_dmg_window); if ch then cfg.show_dmg_window = v; save_cfg() end
    if imgui.tree_node(T("Info window settings")) then
        ch, v = imgui.slider_float(T("Enemy HP window: radius (m)"), cfg.hp_window_radius, 5.0, 150.0); if ch then cfg.hp_window_radius = v; save_cfg() end
        ch, v = imgui.slider_int(T("Enemy HP window: max rows"), math.floor(cfg.hp_window_rows), 1, 20); if ch then cfg.hp_window_rows = v; save_cfg() end
        ch, v = imgui.slider_int(T("Damage window: max rows"), math.floor(cfg.dmg_window_rows), 1, 30); if ch then cfg.dmg_window_rows = v; save_cfg() end
        imgui.tree_pop()
    end
    if imgui.tree_node(T("Boss spoils drops")) then
        ch, v = imgui.checkbox(T("Include 'Ancient' spoils types"), cfg.drops_ancient); if ch then cfg.drops_ancient = v; save_cfg() end
        imgui.text(T("Each slot rolls once. On success it drops 'pieces' random spoils of that level."))
        imgui.text(T("Last drop: ") .. drop_last)
        for _, c in ipairs(DROP_CATS) do
            if imgui.tree_node(T(DROP_CAT_NAMES[c]) .. "##drops_" .. c) then
                local slots = cfg.drop_slots[c]
                local remove
                for i, sl in ipairs(slots) do
                    local id = "##" .. c .. i
                    imgui.push_id(c .. i)
                    local c1, nv
                    c1, nv = imgui.slider_int(T("Spoils level"), math.floor(sl.lvl), 1, 5); if c1 then sl.lvl = nv; save_cfg() end
                    c1, nv = imgui.slider_float(T("Chance %"), sl.chance + 0.0, 0.0, 100.0); if c1 then sl.chance = nv; save_cfg() end
                    c1, nv = imgui.slider_int(T("Pieces"), math.floor(sl.count), 1, 5); if c1 then sl.count = nv; save_cfg() end
                    if imgui.button(T("Remove slot")) then remove = i end
                    imgui.separator()
                    imgui.pop_id()
                end
                if remove then table.remove(slots, remove); save_cfg() end
                if #slots < 8 and imgui.button(T("Add slot##") .. c) then slots[#slots + 1] = { lvl = 1, chance = 50, count = 1 }; save_cfg() end
                if imgui.button(T("Reset this category##") .. c) then cfg.drop_slots[c] = copy_slots(DEFAULT_DROP_SLOTS[c]); save_cfg() end
                imgui.tree_pop()
            end
        end
        imgui.tree_pop()
    end
    if imgui.tree_node(T("Debug")) then
        ch, v = imgui.checkbox(T("Ferrystone works everywhere"), cfg.debug_ferrystone); if ch then cfg.debug_ferrystone = v; save_cfg() end
        imgui.text(T("Also ignores quests that block Ferrystones, which can break those quests."))
        imgui.text(string.format(T("Game checks found: %d of 2 | blocked teleports allowed so far: %d"), ferry_hooks, ferry_forced))
        imgui.tree_pop()
    end
    if imgui.tree_node(T("Fine-Tuning")) then
        imgui.text(T("Changes the selected difficulty, unless a section says 'all difficulties'."))
        imgui.text(T("HP changes apply to enemies that spawn afterwards, or to all after switching difficulty."))
        if imgui.tree_node(T("Small Enemies")) then
            if imgui.tree_node(T("HP##small")) then
                ch, v = imgui.slider_float(T("HP multiplier x"), cfg.small_factor, 1.0, 30.0); if ch then cfg.small_factor = v; save_cfg() end
                ch, v = imgui.drag_float(T("Minimum HP (0 = off)"), cfg.small_min_hp, 500.0, 0.0, 1000000.0); if ch then cfg.small_min_hp = v; save_cfg() end
                ch, v = imgui.drag_float(T("Diminishing returns start at HP (0 = off)"), cfg.small_hp_knee, 500.0, 0.0, 1000000.0); if ch then cfg.small_hp_knee = v; save_cfg() end
                ch, v = imgui.slider_float(T("Exponent above that (1 = no flattening)"), cfg.small_hp_curve, 0.3, 1.0); if ch then cfg.small_hp_curve = v; save_cfg() end
                ch, v = imgui.drag_float(T("Strong flattening starts at HP (0 = off)"), cfg.small_hp_knee2, 500.0, 0.0, 1000000.0); if ch then cfg.small_hp_knee2 = v; save_cfg() end
                ch, v = imgui.slider_float(T("Exponent above that (lower = flatter)"), cfg.small_hp_curve2, 0.05, 1.0); if ch then cfg.small_hp_curve2 = v; save_cfg() end
                ch, v = imgui.drag_float(T("Counts as small if original HP is below"), cfg.small_below, 50.0, 100.0, 100000.0); if ch then cfg.small_below = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Damage##small")) then
                ch, v = imgui.slider_float(T("Bonus % of max HP: from"), cfg.dmg_small_min, 0.0, 50.0); if ch then cfg.dmg_small_min = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % of max HP: to"), cfg.dmg_small_max, 0.0, 50.0); if ch then cfg.dmg_small_max = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % only from this base damage"), cfg.small_bonus_min_dmg, 0.0, 500.0); if ch then cfg.small_bonus_min_dmg = v; save_cfg() end
                imgui.tree_pop()
            end
            imgui.tree_pop()
        end
        if imgui.tree_node(T("Medium Enemies")) then
            imgui.text(string.format(T("Medium = original HP from %.0f to %.0f (set under Small Enemies and Bosses)."), cfg.small_below, cfg.large_above))
            if imgui.tree_node(T("HP##medium")) then
                ch, v = imgui.slider_float(T("HP multiplier x"), cfg.medium_factor, 1.0, 30.0); if ch then cfg.medium_factor = v; save_cfg() end
                ch, v = imgui.drag_float(T("Minimum HP (0 = off)"), cfg.medium_min_hp, 500.0, 0.0, 1000000.0); if ch then cfg.medium_min_hp = v; save_cfg() end
                ch, v = imgui.drag_float(T("Diminishing returns start at HP (0 = off)"), cfg.hp_knee, 500.0, 0.0, 1000000.0); if ch then cfg.hp_knee = v; save_cfg() end
                ch, v = imgui.slider_float(T("Exponent above that (1 = no flattening)"), cfg.hp_curve, 0.3, 1.0); if ch then cfg.hp_curve = v; save_cfg() end
                ch, v = imgui.drag_float(T("Strong flattening starts at HP (0 = off)"), cfg.hp_knee2, 500.0, 0.0, 1000000.0); if ch then cfg.hp_knee2 = v; save_cfg() end
                ch, v = imgui.slider_float(T("Exponent above that (lower = flatter)"), cfg.hp_curve2, 0.05, 1.0); if ch then cfg.hp_curve2 = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Damage##medium")) then
                ch, v = imgui.slider_float(T("Bonus % of max HP: from"), cfg.dmg_med_min, 0.0, 50.0); if ch then cfg.dmg_med_min = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % of max HP: to"), cfg.dmg_med_max, 0.0, 50.0); if ch then cfg.dmg_med_max = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % only from this base damage"), cfg.medium_bonus_min_dmg, 0.0, 1000.0); if ch then cfg.medium_bonus_min_dmg = v; save_cfg() end
                imgui.tree_pop()
            end
            imgui.tree_pop()
        end
        if imgui.tree_node(T("Bosses")) then
            if imgui.tree_node(T("HP##boss")) then
                ch, v = imgui.slider_float(T("HP multiplier x"), cfg.large_factor, 1.0, 30.0); if ch then cfg.large_factor = v; save_cfg() end
                ch, v = imgui.drag_float(T("Minimum HP"), cfg.boss_min_hp, 1000.0, 0.0, 2000000.0); if ch then cfg.boss_min_hp = v; save_cfg() end
                ch, v = imgui.drag_float(T("Diminishing returns start at HP (0 = off)"), cfg.boss_knee, 1000.0, 0.0, 5000000.0); if ch then cfg.boss_knee = v; save_cfg() end
                ch, v = imgui.slider_float(T("Exponent above that (lower = flatter)"), cfg.boss_curve, 0.1, 1.0); if ch then cfg.boss_curve = v; save_cfg() end
                ch, v = imgui.slider_float(T("Cyclops extra HP multiplier x"), cfg.cyclops_mult, 1.0, 5.0); if ch then cfg.cyclops_mult = v; save_cfg() end
                ch, v = imgui.drag_float(T("Counts as boss if original HP is above"), cfg.large_above, 100.0, 1000.0, 1000000.0); if ch then cfg.large_above = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Damage##boss")) then
                ch, v = imgui.slider_float(T("Bonus % of max HP: from"), cfg.dmg_large_min, 0.0, 60.0); if ch then cfg.dmg_large_min = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % of max HP: to"), cfg.dmg_large_max, 0.0, 60.0); if ch then cfg.dmg_large_max = v; save_cfg() end
                ch, v = imgui.slider_float(T("Bonus % only from this base damage"), cfg.large_bonus_min_dmg or 500, 0.0, 3000.0); if ch then cfg.large_bonus_min_dmg = v; save_cfg() end
                ch, v = imgui.slider_float(T("One hit never takes more than % of max HP (0 = off)"), cfg.dmg_large_cap, 0.0, 100.0); if ch then cfg.dmg_large_cap = v; save_cfg() end
                imgui.tree_pop()
            end
            imgui.tree_pop()
        end
        if imgui.tree_node(T("All Enemies")) then
            if imgui.tree_node(T("HP##all")) then
                ch, v = imgui.drag_float(T("Hard cap for max HP (0 = off)"), cfg.max_hp_cap, 1000.0, 0.0, 10000000.0); if ch then cfg.max_hp_cap = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Damage##all")) then
                ch, v = imgui.slider_float(T("Enemy damage multiplier x"), cfg.attack_mult, 0.5, 5.0); if ch then cfg.attack_mult = v; save_cfg() end
                ch, v = imgui.slider_float(T("Weak hit: normal damage x"), cfg.dmg_mult_min, 1.0, 10.0); if ch then cfg.dmg_mult_min = v; save_cfg() end
                ch, v = imgui.slider_float(T("Strong hit: normal damage x"), cfg.dmg_mult_max, 1.0, 10.0); if ch then cfg.dmg_mult_max = v; save_cfg() end
                ch, v = imgui.slider_float(T("Chance of a strong hit %"), cfg.dmg_mult_chance, 0.0, 100.0); if ch then cfg.dmg_mult_chance = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Armor")) then
                ch, v = imgui.checkbox(T("Percent bonus is reduced by your armor (all difficulties)"), cfg.bonus_armor); if ch then cfg.bonus_armor = v; save_cfg() end
                ch, v = imgui.slider_float(T("Share of your armor that counts (1 = all, 0 = none)"), cfg.armor_share, 0.0, 1.0); if ch then cfg.armor_share = v; save_cfg() end
                local ae = armor_estimate["ch000000_00"]
                imgui.text(string.format(T("Armor factor in use for you: %s (before the share above is applied)"), ae and ae.value < 1.0 and string.format("%.2f", ae.value) or T("1.00 - no data yet")))
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Burst protection")) then
                ch, v = imgui.slider_float(T("Seconds between percent bonuses per enemy"), cfg.burst_cooldown, 0.0, 5.0); if ch then cfg.burst_cooldown = v; save_cfg() end
                ch, v = imgui.slider_float(T("Hit without percent bonus (blocked): normal damage x"), cfg.blocked_mult, 1.0, 5.0); if ch then cfg.blocked_mult = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Max HP loss")) then
                ch, v = imgui.slider_float(T("Max HP loss speed (1 = base game, 0.5 = half)"), cfg.loss_mult, 0.0, 1.0); if ch then cfg.loss_mult = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Stagger")) then
                ch, v = imgui.slider_float(T("Stagger resistance follows HP (0 = off, 1 = full, up to 2)"), cfg.stagger_follow, 0.0, 2.0); if ch then cfg.stagger_follow = v; save_cfg() end
                imgui.text(T("HP-dependent stagger (all difficulties):"))
                ch, v = imgui.slider_float(T("Multiplier at full HP (0.8 = 20% harder to stagger)"), cfg.stag_full, 0.3, 1.5); if ch then cfg.stag_full = v; save_cfg() end
                ch, v = imgui.slider_float(T("Multiplier at 0% HP (2 = double susceptibility)"), cfg.stag_empty, 1.0, 4.0); if ch then cfg.stag_empty = v; save_cfg() end
                ch, v = imgui.slider_float(T("Curve (1 = linear, 2 = escalates late, 3 = very late)"), cfg.stag_curve, 1.0, 4.0); if ch then cfg.stag_curve = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Rewards")) then
                ch, v = imgui.slider_float(T("Reward per max HP (Norgan ~0.27, 0 = off)"), cfg.exp_per_hp, 0.0, 0.6); if ch then cfg.exp_per_hp = v; save_cfg() end
                ch, v = imgui.slider_float(T("Diminishing returns (1 = linear, lower = flatter)"), cfg.exp_curve, 0.4, 1.0); if ch then cfg.exp_curve = v; save_cfg() end
                ch, v = imgui.drag_float(T("Reference HP for the curve"), cfg.exp_ref_hp, 100.0, 1000.0, 1000000.0); if ch then cfg.exp_ref_hp = v; save_cfg() end
                ch, v = imgui.slider_float(T("Rewards follow HP factor (0 = off, 1 = full)"), cfg.exp_follow, 0.0, 1.0); if ch then cfg.exp_follow = v; save_cfg() end
                ch, v = imgui.slider_float(T("Extra reward multiplier x"), cfg.exp_mult, 0.5, 20.0); if ch then cfg.exp_mult = v; save_cfg() end
                imgui.tree_pop()
            end
            if imgui.tree_node(T("Level bonus before Norgan (all difficulties)")) then
                ch, v = imgui.slider_float(T("Per 5 levels: small and medium enemies %"), cfg.level_pct, 0.0, 30.0); if ch then cfg.level_pct = v; save_cfg() end
                ch, v = imgui.slider_float(T("Per 5 levels: bosses %"), cfg.level_pct_boss, 0.0, 30.0); if ch then cfg.level_pct_boss = v; save_cfg() end
                imgui.tree_pop()
            end
            ch, v = imgui.checkbox(T("Skip animals (all difficulties)"), cfg.skip_animals); if ch then cfg.skip_animals = v; save_cfg() end
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
    imgui.tree_pop()
end
re.on_draw_ui(function() with_lang_font(draw_menu) end)
