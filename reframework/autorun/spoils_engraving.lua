-- Spoils Engraving: menus on Jiera's appraisal screen (app.ui042001), opened from her "Spoils Engraving" dialogue option.
-- Fit skill: owned Spoils weapons (step 1), then the skill materials that fit the chosen weapon (step 2); a full weapon
-- adds step 3, which skill to replace. Dismantle: owned Spoils weapons (step 1), then that weapon's skills (step 4),
-- each kept or dropped, confirmed with the bottom button. Both end in yes/no confirms.
-- Prices and checks come from the crafting core (reframework/autorun/spoils_engraving). The core writes to the save only
-- while the game version matches a known write fingerprint; otherwise confirms are test runs. Every native screen
-- action that moves items stays blocked on the armed screen.
local VERSION = 'Spoils Engraving 1.0.5'
local OUT = 'spoils_engraving_report.json'
-- The report is written only from the Troubleshooting button unless DEBUG is on.
local DEBUG = false
local SCREEN = 'app.ui042001'
local GRID = 'app.ui042001.AppraisalResultItemGridPanel'
local COMPARE = 'app.GUIBase.EquipmentAbilityCompareWindowRef'
local RESULT = 'app.GUIAppraisalResultData'
local SLOT = 'app.GUIAppraisalResultData.ResultSlot'
local INFO = 'app.ItemAppraisalManager.ResultItemInfo'
local MANAGER = 'app.ItemAppraisalManager'
local LIST_INFO = 'System.Collections.Generic.List`1<app.ItemAppraisalManager.ResultItemInfo>'
local LIST_INT = 'System.Collections.Generic.List`1<System.Int32>'
local LIST_CMD = 'System.Collections.Generic.List`1<app.GUIBase.Pulldown2Ref.ListInfo>'
local MASTER = 'app.ItemManager.StorageMasterData'
local MAX_ROWS, MAX_PREVIEWS, MAX_EVENTS, MAX_SAMPLES = 1000, 30, 2000, 400
local FLOW = {display_order = 2, fade_in_result = 4, display_result = 5, select_action = 6, exec_all = 12, fade_out_result = 8, fade_out = 31, ['end'] = 32}
local CMD = {first = 0, second = 1, cancel = 5}
-- Command labels per menu and step. They are written only when the step changes, never while a row is selected.
local LABELS = {
    fit = {[1] = {[0] = 'Imbue a skill here', [5] = 'Cancel'}, [2] = {[0] = 'Imbue this skill', [5] = 'Cancel'},
        [3] = {[0] = 'Replace this skill', [5] = 'Cancel'}},
    dismantle = {[1] = {[0] = 'Dismantle this', [5] = 'Cancel'}, [4] = {[0] = 'Dismantle', [5] = 'Cancel'}}}
local TITLES = {fit = 'Imbue Skill', dismantle = 'Dismantle Gear'}
local HINTS = {fit = {[1] = 'Choose gear', [2] = 'Choose a skill to imbue', [3] = 'Choose the skill to replace'},
    dismantle = {[1] = 'Choose gear to dismantle', [4] = 'A keeps a skill; A on a kept skill dismantles'}}
local DIALOG_YES = 1
-- Inventories the core may write. Gear in the others is not listed.
local WRITE_SCOPES = {player = true, storage = true}

-- Skill names and material item IDs from core/data/catalog.json and definitions.json.
local SKILLS = {
    [1] = "Cloudfall Strike", [2] = "Plenilune Slash", [3] = "Eviscerating Skewer", [4] = "Punishing Counter",
    [5] = "Tornadic Strike", [6] = "Myriad Shot", [7] = "Stampede Shot", [8] = "Corkscrew Arrow",
    [9] = "Cataract Shot", [10] = "Eagle Arrow", [11] = "Elemental Pact", [12] = "Grand Halidom",
    [13] = "Argent Solace", [14] = "Grand Spellhold", [15] = "Deific Bolt", [16] = "Shearing Wind",
    [17] = "Effortless Kill", [18] = "Detonate and Dash", [19] = "Powder Barrage", [20] = "Fanged Rupture",
    [21] = "Ravening Coil", [22] = "Razing Ruin", [23] = "Diluvian Tremor", [24] = "Tidal Rage",
    [25] = "Titanic Cleave", [26] = "Grand Salamander", [27] = "Grand Hagol", [28] = "Grand Decanter",
    [29] = "Grand Seism", [30] = "Grand Brontide", [31] = "Dragoun's Pounce", [32] = "Skiedragoun's Edacite",
    [33] = "Seching Flete", [34] = "Magike Sperebaliste", [35] = "Bataille Lich", [36] = "Glacial Bolt",
    [37] = "Shockchain Stake", [38] = "Fortifying Arrow", [39] = "Sagittate Whiteout", [40] = "Shadesnare Bolt",
    [41] = "Figmental Facade", [42] = "Beguiling Bridge", [43] = "Dwelling Effigy", [44] = "Pungent Alarum",
    [45] = "Gliding Gauze", [47] = "Frosted Edge", [48] = "Aggressive Recovery", [49] = "Battle Frenzy I",
    [50] = "Battle Frenzy II", [51] = "Battle Frenzy III", [52] = "Battle Frenzy IV", [53] = "Blighting Strike",
    [54] = "Knockout Strike", [55] = "Enduring Defense", [56] = "Deflected Impact", [57] = "Thawing Shield",
    [58] = "Battering Shield", [59] = "Demon Counter I", [60] = "Demon Counter II", [61] = "Demon Counter III",
    [62] = "Abomination Counter I", [63] = "Abomination Counter II", [64] = "Abomination Counter III",
    [65] = "Humanoid Counter I", [66] = "Humanoid Counter II", [67] = "Beast Counter I", [68] = "Beast Counter II",
    [69] = "Winged Beast Counter I", [70] = "Winged Beast Counter II", [71] = "Saurian Counter I",
    [72] = "Saurian Counter II", [73] = "Spirit Counter I", [74] = "Spirit Counter II", [75] = "Gigantus's Vim",
    [76] = "Enhanced Jump", [77] = "Spectral Feint", [78] = "Snatching-Beast's Foil", [79] = "Ice Elemental",
    [80] = "Frozen Soul", [81] = "Frozen Soul", [82] = "Frozen Soul", [83] = "Frozen Soul", [84] = "Frozen Soul",
    [85] = "Frozen Soul", [86] = "Wicked Knight", [87] = "Wicked Knight", [88] = "Wicked Knight",
    [89] = "Wicked Knight", [90] = "Wicked Knight", [91] = "Wicked Knight", [92] = "Wicked Knight",
    [93] = "Wicked Knight", [94] = "Wicked Knight", [95] = "Molten Spirit", [96] = "Cushioned Fall",
    [97] = "Desperate Evasion", [98] = "Adventurous Appetite", [99] = "Fiendish Ward I",
    [100] = "Fiendish Ward II", [101] = "Fiendish Ward III", [102] = "Improved Efficacy",
    [103] = "Bolstered Outset", [104] = "Relic Hunter", [105] = "Carnivore", [106] = "Provoking Aura",
    [107] = "Arcane Wisdom", [108] = "Moribund Recovery", [109] = "Precipitate Revival", [110] = "Prone Defense",
    [111] = "Imperiled Reflexes", [112] = "Blighted Retort", [113] = "Siege Hardened", [114] = "Hailproof",
    [115] = "Resilient", [116] = "Intact Fortitude", [117] = "Climber's Agility", [118] = "Shadowbound",
    [119] = "Full Thermal", [120] = "Animated Recovery", [121] = "Hill Strider", [122] = "Enduring Grip",
    [123] = "Wind Rider", [124] = "Endless Caper", [125] = "Leaping Strike", [126] = "Health Boost I",
    [127] = "Health Boost II", [128] = "Health Boost III", [129] = "Stamina Boost I", [130] = "Stamina Boost II",
    [131] = "Stamina Boost III", [132] = "Slashing Resistance I", [133] = "Slashing Resistance II",
    [134] = "Striking Resistance I", [135] = "Striking Resistance II", [136] = "Fire Resistance I",
    [137] = "Fire Resistance II", [138] = "Lightning Resistance I", [139] = "Lightning Resistance II",
    [140] = "Ice Resistance I", [141] = "Ice Resistance II", [142] = "Extended Dash", [143] = "Chaotic Strike",
    [144] = "Riotous Magick", [145] = "Swift Strike I", [146] = "Swift Strike II",
    [147] = "Corrupted Foe Counter I", [148] = "Corrupted Foe Counter II", [149] = "Corrupted Foe Counter III",
    [150] = "Deflect Strike", [151] = "Breakneck Toss", [152] = "Improved Empale", [153] = "Critical Shot",
    [154] = "Full Bend", [155] = "Fortified Invocation", [156] = "Extended Recovery", [157] = "Enhanced Burst",
    [158] = "Nimble Tread", [159] = "Piercing Escalade", [160] = "Mighty Chain", [161] = "Extended Burst",
    [162] = "Vertiginous Strike", [163] = "Restorative Bolts", [164] = "Debilitating Bolts",
    [165] = "Phantasmal Tome", [166] = "Perdurable Illusion", [167] = "Equanimity", [168] = "Moribund Frenzy",
    [169] = "Survival Instinct", [170] = "Elusive", [171] = "Breath Resistance", [172] = "Improved Odds",
    [173] = "Airborne Reflexes", [174] = "Homing Instinct", [175] = "Forceful Strikes"}
local MATERIALS = {
    [60230] = 23, [60234] = 21, [61001] = 1, [61002] = 2, [61003] = 3, [61004] = 4, [61005] = 5, [61006] = 6,
    [61007] = 7, [61008] = 8, [61009] = 9, [61010] = 10, [61011] = 11, [61012] = 12, [61013] = 13, [61014] = 14,
    [61015] = 15, [61016] = 16, [61017] = 17, [61018] = 18, [61019] = 19, [61020] = 20, [61022] = 22, [61024] = 24,
    [61025] = 25, [61026] = 26, [61027] = 27, [61028] = 28, [61029] = 29, [61030] = 30, [61031] = 31, [61032] = 32,
    [61033] = 33, [61034] = 34, [61035] = 35, [61036] = 36, [61037] = 37, [61038] = 38, [61039] = 39, [61040] = 40,
    [61041] = 41, [61042] = 42, [61043] = 43, [61044] = 44, [61045] = 45, [61047] = 47, [61048] = 48, [61049] = 49,
    [61050] = 50, [61051] = 51, [61052] = 52, [61053] = 53, [61054] = 54, [61055] = 55, [61056] = 56, [61057] = 57,
    [61058] = 58, [61059] = 59, [61060] = 60, [61061] = 61, [61062] = 62, [61063] = 63, [61064] = 64, [61065] = 65,
    [61066] = 66, [61067] = 67, [61068] = 68, [61069] = 69, [61070] = 70, [61071] = 71, [61072] = 72, [61073] = 73,
    [61074] = 74, [61075] = 75, [61076] = 76, [61077] = 77, [61078] = 78, [61079] = 79, [61080] = 80, [61081] = 81,
    [61082] = 82, [61083] = 83, [61084] = 84, [61085] = 85, [61086] = 86, [61087] = 87, [61088] = 88, [61089] = 89,
    [61090] = 90, [61091] = 91, [61092] = 92, [61093] = 93, [61094] = 94, [61095] = 95, [61096] = 96, [61097] = 97,
    [61098] = 98, [61099] = 99, [61100] = 100, [61101] = 101, [61102] = 102, [61103] = 103, [61104] = 104,
    [61105] = 105, [61106] = 106, [61107] = 107, [61108] = 108, [61109] = 109, [61110] = 110, [61111] = 111,
    [61112] = 112, [61113] = 113, [61114] = 114, [61115] = 115, [61116] = 116, [61117] = 117, [61118] = 118,
    [61119] = 119, [61120] = 120, [61121] = 121, [61122] = 122, [61123] = 123, [61124] = 124, [61125] = 125,
    [61126] = 126, [61127] = 127, [61128] = 128, [61129] = 129, [61130] = 130, [61131] = 131, [61132] = 132,
    [61133] = 133, [61134] = 134, [61135] = 135, [61136] = 136, [61137] = 137, [61138] = 138, [61139] = 139,
    [61140] = 140, [61141] = 141, [61142] = 142, [61143] = 143, [61144] = 144, [61145] = 145, [61146] = 146,
    [61147] = 147, [61148] = 148, [61149] = 149, [61150] = 150, [61151] = 151, [61152] = 152, [61153] = 153,
    [61154] = 154, [61155] = 155, [61156] = 156, [61157] = 157, [61158] = 158, [61159] = 159, [61160] = 160,
    [61161] = 161, [61162] = 162, [61163] = 163, [61164] = 164, [61165] = 165, [61166] = 166, [61167] = 167,
    [61168] = 168, [61169] = 169, [61170] = 170, [61171] = 171, [61172] = 172, [61173] = 173, [61174] = 174,
    [61175] = 175}

local R = {schema = VERSION, tdb = sdk.get_tdb_version(), bindings = {}, missing = {}, fired = {}, errors = {},
    events = {}, dropped = 0, flow_trace = {}, sessions = {}, injections = {}, transits = {}, labels = {},
    commands = {}, blocked = {}, compare = {}, dialogs = {}, counts = {}, manager = {}, selection = {}, tick_sources = {}}
local S = {armed = false, screen = false, grid = false, compare = false, stage = 0, rows = {}, previews = {},
    keymap = {}, queue = {}, frame = 0, dirty = true, last_write = 0, strings = 0, keep = {},
    pulldown = false, dialog = false, sel_key = false, applying = false, allow_cancel = false,
    last_flow = false, transit = false, session = false, holder = false, held = {}, label_count = 0}
local B = {}
-- Material rows show the material item; the weapon rows of step 3 show the weapon.
local function is_mat(r) return type(r) == 'table' and r.material ~= nil and r.item_id == r.material end
local function mode() return S.session and S.session.mode or 'fit' end
local function label_for(stage, cmd)
    local l = LABELS[mode()][stage]
    return l and l[cmd]
end

local function now() return os.clock and os.clock() or 0 end
local function err(where, e)
    local k = where .. ': ' .. tostring(e)
    R.errors[k] = (R.errors[k] or 0) + 1
    S.dirty = true
end
local flat
local TRAIL = {}
-- Menu events also go to the REFramework log, which is written line by line and so survives a crash.
local function event(kind, data)
    data = data or {}
    local line = ((os and os.date and os.date('!%H:%M:%S') or tostring(S.frame)) .. ' ' .. kind .. ' ' .. flat(data)):sub(1, 400)
    if DEBUG then
        if log and log.info then pcall(log.info, '[SpoilsEngraving] ' .. line) end
        -- The last 40 events are also kept in a small file, written at once, for finding where a crash happened.
        TRAIL[#TRAIL + 1] = line
        if #TRAIL > 40 then table.remove(TRAIL, 1) end
        pcall(json.dump_file, 'spoils_engraving_trail.json', TRAIL)
    end
    if #R.events >= MAX_EVENTS then R.dropped = R.dropped + 1 return end
    data.kind, data.t, data.frame = kind, now(), S.frame
    R.events[#R.events + 1] = data
    S.dirty = true
end
function flat(v)
    if type(v) ~= 'table' then return tostring(v) end
    local ks, out = {}, {}
    for k in pairs(v) do ks[#ks + 1] = tostring(k) end
    table.sort(ks)
    for _, k in ipairs(ks) do out[#out + 1] = k .. '=' .. flat(v[k] ~= nil and v[k] or v[tonumber(k)]) end
    return '{' .. table.concat(out, ',') .. '}'
end
local function push(list, v, cap) if #list < (cap or MAX_SAMPLES) then list[#list + 1] = v end S.dirty = true end
-- Skips an entry identical to the previous one in the same list.
local last_sig = {}
local function log(list, v, cap)
    local sig = flat(v)
    if last_sig[list] == sig then return end
    last_sig[list] = sig
    push(list, v, cap)
end
local function int(v)
    local n = math.tointeger(v)
    if n == nil then error('not an integer: ' .. tostring(v), 0) end
    return n
end
local function u32(v) return sdk.to_int64(v) & 0xffffffff end
local function i32(v) local n = u32(v) if n >= 0x80000000 then n = n - 0x100000000 end return n end
local function num(v)
    if type(v) == 'number' then return v end
    if type(v) == 'boolean' then return v and 1 or 0 end
    if type(v) == 'userdata' or type(v) == 'table' then
        local ok, n = pcall(function() return v:get_field('value__') end)
        if ok and type(n) == 'number' then return n end
    end
    return nil
end
local function managed(ptr)
    local ok, o = pcall(sdk.to_managed_object, ptr)
    if ok and o and sdk.is_managed_object(o) then return o end
    return nil
end
local function tname(o) local ok, n = pcall(function() return o:get_type_definition():get_full_name() end) return ok and n or false end
local function addr(o) local ok, n = pcall(function() return math.tointeger(o:get_address()) end) return ok and n or false end
local function call(o, sig, ...) local ok, v = pcall(o.call, o, sig, ...) if ok then return v end return nil end
local function text(v)
    if type(v) == 'string' then return v end
    if v and (type(v) == 'userdata' or type(v) == 'table') then return call(v, 'ToString()') end
    return nil
end
-- A new string for every use, held permanently: the game releases strings it is given, so a shared one gets freed
-- while still cached (v12 crash: set_Message on a freed string, then heap corruption).
local function mstr(s)
    local o = sdk.create_managed_string(s)
    if not pcall(function() o:add_ref_permanent() end) then pcall(function() o = o:add_ref() or o end) end
    S.strings = (S.strings or 0) + 1
    return o
end
local function pointer(v) return type(v) ~= 'nil' and sdk.to_int64(v) or 0 end
local function plausible(p) return p > 0x10000 and p < 0x7fffffffff00 end

-- Bindings: exact owner and signature, or one method by name and parameter count for generic lists.
local function bind(owner, sig, key)
    key = key or (owner .. '.' .. sig)
    local td = sdk.find_type_definition(owner)
    local m = td and td:get_method(sig)
    local fn = m and m:get_function()
    if not (m and fn and m:get_declaring_type():get_full_name() == owner) then
        R.missing[#R.missing + 1] = key
        return nil
    end
    R.bindings[key] = tostring(fn)
    return m
end
local function by_name(owner, name, n)
    local td = sdk.find_type_definition(owner)
    if td then
        local found = nil
        for _, m in ipairs(td:get_methods()) do
            if m:get_name() == name and m:get_num_params() == n then found = m break end
        end
        if not found then
            local m = td:get_method(name)
            if m and m:get_num_params() == n then found = m end
        end
        if found then
            R.bindings[owner .. '.' .. name .. '/' .. n] = tostring(found:get_function())
            return found
        end
    end
    R.missing[#R.missing + 1] = owner .. '.' .. name .. '/' .. n
    return nil
end
local function offset(owner, field, want)
    local td = sdk.find_type_definition(owner)
    local f = td and td:get_field(field)
    local o = f and f:get_offset_from_base()
    if not (o and o > 0 and (want == nil or o == want)) then
        R.missing[#R.missing + 1] = owner .. '.' .. field .. ' offset ' .. tostring(o)
        return nil
    end
    return o
end

-- A hook's guard decides SKIP_ORIGINAL on its own. If the guard fails on the armed screen, the call is skipped.
-- Return value for a skipped method that returns one.
local SKIP_RET = {}
local function hook(role, owner, sig, guard, pre, post)
    local m = bind(owner, sig)
    if not m then return nil end
    R.fired[role] = 0
    local last = nil
    local ok, e = pcall(sdk.hook, m, function(args)
        R.fired[role] = R.fired[role] + 1
        last = {}
        for i = 1, 6 do
            local okc, v = pcall(sdk.to_int64, args[i])
            last[i] = okc and v or 0
        end
        last.obj = managed(args[2])
        local skip = false
        if guard then
            local ok2, v = pcall(guard, args)
            if ok2 then skip = v == true else skip = S.session ~= false err(role .. '/guard', v) end
        end
        if pre then local ok2, e2 = pcall(pre, args, skip) if not ok2 then err(role, e2) end end
        last.skip = skip
        if skip then
            R.blocked[role] = (R.blocked[role] or 0) + 1
            S.dirty = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        return sdk.PreHookResult.CALL_ORIGINAL
    end, function(retval)
        if last and last.skip and SKIP_RET[role] ~= nil then retval = SKIP_RET[role] end
        if post then local ok2, e2 = pcall(post, retval, last) if not ok2 then err(role .. '/post', e2) end end
        last = nil
        return retval
    end)
    if not ok then err('hook ' .. role, e) return nil end
    B[role] = m
    return m
end

-- Methods called directly.
B.clear = bind(RESULT, 'clear()', 'direct ' .. RESULT .. '.clear()')
B.slot_list = bind(RESULT, 'getResultSlotList()')
B.slot_count = bind(RESULT, 'getResultSlotCount()')
B.result_ctor = bind(RESULT, '.ctor()')
B.slot_key = bind(SLOT, 'get_Key()')
B.slot_storage = bind(SLOT, 'get_Storage()')
B.info_ctor = bind(INFO, '.ctor()')
B.list_info_ctor, B.list_info_add = by_name(LIST_INFO, '.ctor', 0), by_name(LIST_INFO, 'Add', 1)
B.list_int_ctor, B.list_int_add = by_name(LIST_INT, '.ctor', 0), by_name(LIST_INT, 'Add', 1)
B.cmd_count, B.cmd_item, B.cmd_remove = by_name(LIST_CMD, 'get_Count', 0), by_name(LIST_CMD, 'get_Item', 1), by_name(LIST_CMD, 'RemoveAt', 1)
B.transit = bind(SCREEN, 'transitFlow(app.ui042001.FlowId)')
B.anim_request = bind('app.ui042001.AnimStateController', 'request(app.ui042001.AnimStateController.Transit)')
B.selected = bind(GRID, 'get_SelectedInfo()')
B.pd_active = bind(GRID, 'get_PulldownActive()')
B.animating = bind(GRID, 'get_IsAnimating()')
B.sel_index = bind(GRID, 'get_SelectedIndex()')
B.info_key = bind('app.ui042001.AppraisalResultItemGridPanel.AppraisalItemGridInfo', 'get_SlotKey()')
B.storage_list = bind('app.ItemManager', 'getStorageMasterList(app.CharacterID)')
B.item_data = bind('app.ItemManager', 'getItemData(System.Int32)')
B.gold = bind('app.ItemManager', 'get_Version()')
B.source = bind('app.ItemDefine', 'getSourceAppraisalItemIdFromExtensionValue(System.Int32)')
B.favorite = bind('app.ItemDefine', 'getFavoriteMarkFromExtensionValue(System.Int32)')
B.equip_source = bind('app.GUIAppraisalDefine', 'isEquipAppraisalItem(System.Int32)')
B.item_name = bind('app.GUIBase', 'getItemName(System.Int32)')
B.valid = bind('app.EquipmentAbilityUtil', 'getValidAbilityIDs(System.Int32)')
B.contains = by_name('System.Collections.Generic.HashSet`1<app.EquipmentAbilityID>', 'Contains', 1)
B.results = bind(MANAGER, 'get_ResultDatasList()')
B.temps = bind(MANAGER, 'get_TempStorageDataList()')
B.dialog = bind('app.GuiManager', 'requestDialog(System.String, System.String, System.String, System.String, System.String, System.Boolean, System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)')
B.dialog_state = bind('app.GuiManager', 'getDialogState()')
local AB = offset(INFO, 'Ability')
local SLOT_STORAGE = offset(SLOT, '_Storage')
local MASTER_BASE = offset(MASTER, '_Param', 16)
do
    local td = sdk.find_type_definition(MASTER)
    if not (td and td:get_size() == 96) then R.missing[#R.missing + 1] = MASTER .. ' size 96' end
    local it = sdk.find_type_definition(INFO)
    if not (AB and it and it:get_size() >= AB + 20) then R.missing[#R.missing + 1] = INFO .. ' ability extent' end
end

local function gold()
    local im = sdk.get_managed_singleton('app.ItemManager')
    return im and B.gold and num(B.gold:call(im)) or false
end
local function owners()
    local out = {}
    local cm = sdk.get_managed_singleton('app.CharacterManager')
    local p = cm and call(cm, 'get_ManualPlayer()')
    if p then out[#out + 1] = {'player', num(call(p, 'get_CharaID()'))} end
    local pm = sdk.get_managed_singleton('app.PawnManager')
    local pawn = pm and call(pm, 'get_MainPawn()')
    local pc = pawn and call(pawn, 'get_CachedCharacter()')
    if pc then out[#out + 1] = {'main_pawn', num(call(pc, 'get_CharaID()'))} end
    local td = sdk.find_type_definition('app.ItemDefine')
    local f = td and td:get_field('WarehouseCharaId')
    local w = f and f:get_data(nil)
    if w then out[#out + 1] = {'storage', num(w)} end
    return out
end
local function lists()
    local im = sdk.get_managed_singleton('app.ItemManager')
    local out = {}
    if not (im and B.storage_list) then return out end
    for _, o in ipairs(owners()) do
        if o[2] then
            local l = B.storage_list:call(im, int(o[2]))
            if l then out[#out + 1] = {label = o[1], chara = o[2], list = l, count = num(call(l, 'get_Count()')) or 0} end
        end
    end
    return out
end
local function counts(label)
    local c = {label = label, gold = gold(), frame = S.frame}
    for _, l in ipairs(lists()) do c[l.label] = l.count end
    push(R.counts, c)
    return c
end
local function manager_pending()
    local m = sdk.get_managed_singleton(MANAGER)
    if not m then return {available = false} end
    local r = B.results and B.results:call(m)
    local t = B.temps and B.temps:call(m)
    return {available = true, results = r and num(call(r, 'get_Count()')) or false, temps = t and num(call(t, 'get_Count()')) or false}
end
local function item_name(id)
    if B.item_name then
        local ok, v = pcall(B.item_name.call, B.item_name, nil, int(id))
        local s = ok and text(v)
        if s and s ~= '' and not s:find('<REF') then return s end
    end
    return 'item ' .. tostring(id)
end
local function skill_name(a) return SKILLS[a] or ('skill ' .. tostring(a)) end
local function money(n)
    local s = tostring(math.tointeger(n) or n)
    while true do
        local r, k = s:gsub('^(%d+)(%d%d%d)', '%1,%2')
        s = r
        if k == 0 then return s end
    end
end

-- Crafting core, composed when Relic mode is armed (it needs a loaded save). Writes stay off until the player allows
-- real crafting, which records this game version's write-method fingerprint in FP_FILE.
-- Data files of builds named Relic Gear are copied once to the new names, so settings and any open journal carry over.
do
    local names = {'settings', 'save_slot', 'write_fingerprint'}
    for _, k in ipairs({'a', 'b'}) do
        names[#names + 1] = 'journal_' .. k
        for i = 0, 14 do names[#names + 1] = 'journal_' .. i .. '_' .. k end
    end
    for _, n in ipairs(names) do
        local new = 'spoils_engraving_' .. n .. '.json'
        local ok, cur = pcall(json.load_file, new)
        if not (ok and cur ~= nil) then
            local ok2, old = pcall(json.load_file, 'relic_gear_' .. n .. '.json')
            if ok2 and type(old) == 'table' then pcall(json.dump_file, new, old) end
        end
    end
end
local FP_FILE = 'spoils_engraving_write_fingerprint.json'
local FEES = {revision = 'fees-default-1', currency = 'gold', extraction = 20000, installation = 10000,
    replacement = 10000, factors = {1, 3, 6, 10}, allow_free = false, keep_gear = false}
local CORE = {ok = false, error = false, real = false, epoch = 0, active = false}
-- The save slot last loaded (0-14), so each save keeps its own crafting journal. -1 is the game's system data.
local SAVE = {slot = nil}
do
    -- After a script reset no load is seen, so the last slot is kept on disk.
    local ok, v = pcall(json.load_file, 'spoils_engraving_save_slot.json')
    local n = ok and type(v) == 'table' and math.tointeger(v.slot)
    if n and n >= 0 and n <= 14 then SAVE.slot = n end
    local td = sdk.find_type_definition('app.SaveDataManager')
    local m = td and td:get_method('requestLoad(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])')
    if m then
        sdk.hook(m, function(args)
            local v = sdk.to_int64(args[3]) & 0xffffffff
            if v >= 0x80000000 then v = v - 0x100000000 end
            if v >= 0 and v <= 14 and v ~= SAVE.slot then
                SAVE.slot = v
                pcall(json.dump_file, 'spoils_engraving_save_slot.json', {slot = v})
            end
        end, function(ret) return ret end)
    end
end
local KNOWN_FP = {schema = 'relic-write-fingerprint-1', tdb = 83, methods = {
    fee = {offset = 0, head = '4157415641554154565755534883EC584489CB4489C74989D64889CE8A8424C0'},
    grant = {offset = 3836976, head = '4157415641554154565755534881EC880000004489CE4489C74889D34989CE48'},
    gear = {offset = 21241664, head = '4157415641554154565755534881ECE80000004D89C64889D748895424284889'},
    consume = {offset = 21252576, head = '4157415641554154565755534883EC484489CE4489C74989D64889CB488B050D'},
    donor = {offset = 21254976, head = '41574156415541545657534881ECE00000004889CB488B05B48714074831E048'}}}
-- Fit and replace on the same weapon get dearer: the nth piece of work on a weapon costs LADDER[n], the last step
-- repeating. The count is kept on the weapon itself, in bits 23-29 of its _ExtensionValue, which the game leaves unused
-- and keeps in the save, so it follows the weapon between inventories and saves.
local LADDER = {10000, 50000, 150000, 500000}
-- Fees the player can change in the REFramework menu, kept in SETTINGS_FILE.
local SETTINGS_FILE = 'spoils_engraving_settings.json'
local FEE_MAX = 999999999
local function fee_ok(v) return math.type(v) == 'integer' and v >= 1 and v <= FEE_MAX end
local fp_ok, saved_fp = pcall(json.load_file, FP_FILE)
local ALLOW_VERSION = fp_ok and type(saved_fp) == 'table' and saved_fp.schema == 'relic-write-fingerprint-1'
do
    local ok, v = pcall(json.load_file, SETTINGS_FILE)
    if ok and type(v) == 'table' and v.schema == 'relic-settings-1' then
        if fee_ok(math.tointeger(v.extraction)) then FEES.extraction = math.tointeger(v.extraction) end
        if type(v.keep_gear) == 'boolean' then FEES.keep_gear = v.keep_gear end
        if type(v.allow_version) == 'boolean' then ALLOW_VERSION = v.allow_version end
        if type(v.ladder) == 'table' then
            for i = 1, #LADDER do local n = math.tointeger(v.ladder[i]) if fee_ok(n) then LADDER[i] = n end end
        end
    end
end
local function save_settings()
    return json.dump_file(SETTINGS_FILE, {schema = 'relic-settings-1', extraction = FEES.extraction, ladder = LADDER,
        keep_gear = FEES.keep_gear, allow_version = ALLOW_VERSION}) ~= false
end
local WORK_SHIFT, WORK_MASK = 23, 0x7F
local function ext_count(ext) return ((math.tointeger(ext or 0) or 0) & 0xffffffff) >> WORK_SHIFT & WORK_MASK end
local function work_done(w) return ext_count(w.ext) end
local function fit_fee(w) return LADDER[math.min(work_done(w) + 1, #LADDER)] end
local function fit_config(w)
    local cfg = {}
    for k, v in pairs(FEES) do cfg[k] = v end
    local fee = fit_fee(w)
    cfg.installation, cfg.replacement, cfg.revision = fee, fee, FEES.revision .. '-work' .. work_done(w)
    return cfg
end
local function find_master(owner, sid)
    for _, l in ipairs(lists()) do
        if l.label == owner then
            for i = 0, math.min(l.count, 8192) - 1 do
                local m = call(l.list, 'get_Item(System.Int32)', int(i))
                if m and tname(m) == MASTER and m:read_dword(MASTER_BASE + 20) == sid then return m end
            end
        end
    end
    return nil
end
-- After a fit, the weapon's count goes one higher, written into its current _ExtensionValue.
local function work_record(w)
    local n = math.min(work_done(w) + 1, WORK_MASK)
    local m = find_master(w.owner, w.storage_id)
    if not m then return false end
    local ext = m:read_dword(MASTER_BASE + 60)
    local want = ext & ~(WORK_MASK << WORK_SHIFT) | n << WORK_SHIFT
    local ok = pcall(function() m:call('set_ExtensionValue(System.Int32)', int(want >= 0x80000000 and want - 0x100000000 or want)) end)
    if not ok or m:read_dword(MASTER_BASE + 60) ~= want then return false end
    return n
end
local DIALOGUE = {ok = false, error = false}
R.core = {ok = false, quotes = {}, crafts = {}, refreshes = {}, events = {}}
local function exists(p) local ok, v = pcall(json.load_file, p) return ok and v ~= nil end
local function build_info()
    local b = CORE.native and CORE.native.build
    return b and {ok = b.ok, code = b.code, reason = b.reason or nil, error = b.error or nil} or false
end
-- REFramework's package.path does not include the autorun folder, and additions to it do not last past the
-- script's load, so every core module is registered in package.preload, which does last.
local CORE_MODULES = {'actor', 'build_check', 'capacity', 'capture', 'catalog', 'codec', 'controller', 'coordinator',
    'definitions', 'deltas', 'eligibility', 'eligibility_preview', 'fees', 'inventory_profile', 'inventory_reader',
    'item_names', 'journal', 'live_preview', 'load_observer', 'load_profile', 'material_planner', 'native',
    'preview_rejection', 'profile', 'records', 'resolver', 'rules', 'service', 'stock', 'transport', 'weapon_actions'}
local CORE_DIRS = {'reframework/autorun/spoils_engraving/'}
do
    local root = package.path:match('([^;]-)[\\/]lua[\\/]%?%.lua')
    if root then table.insert(CORE_DIRS, 1, root .. '\\reframework\\autorun\\spoils_engraving\\') end
end
local function core_path()
    local missing = {}
    for _, m in ipairs(CORE_MODULES) do
        local name = 'spoils_engraving/' .. m
        if not package.preload[name] and not package.loaded[name] then
            local chunk, why
            for _, d in ipairs(CORE_DIRS) do
                chunk, why = loadfile(d .. m .. '.lua')
                if chunk then break end
            end
            if chunk then package.preload[name] = chunk else missing[#missing + 1] = m .. ': ' .. tostring(why) end
        end
    end
    if #missing > 0 then error('Core files not loaded: ' .. table.concat(missing, '; '), 0) end
end
-- Set by the skill material registration below.
local ITEM_DB
local function compose()
    core_path()
    local profile = require('spoils_engraving/profile')
    local cfg = {}
    for k, v in pairs(profile) do cfg[k] = v end
    local fp = ALLOW_VERSION and json.load_file(FP_FILE) or nil
    cfg.write_fingerprint = type(fp) == 'table' and fp.schema == 'relic-write-fingerprint-1' and fp or KNOWN_FP
    local reader = require('spoils_engraving/inventory_reader').new(sdk, require('spoils_engraving/inventory_profile'))
    local actor = require('spoils_engraving/actor').new(sdk, cfg)
    assert(ITEM_DB, 'skill material registry missing')
    CORE.native = require('spoils_engraving/native').new(sdk, reader, actor, cfg, require('spoils_engraving/definitions'), ITEM_DB,
        function() return CORE.active end, function() return CORE.epoch end, WRITE_SCOPES)
    local service = require('spoils_engraving/service').new(require('spoils_engraving/rules'), require('spoils_engraving/catalog'))
    local J = require('spoils_engraving/journal')
    -- A journal from before slots were used is finished first; until it is empty it stays in use.
    local slot = SAVE.slot
    local old = J.new(json, profile.revision, exists)
    if slot and exists(old:path(1)) then
        local ok, st = pcall(old.load, old)
        if not ok or st then slot = nil end
    end
    local journal = J.new(json, profile.revision, exists, slot, DEBUG)
    CORE.slot = SAVE.slot
    CORE.c = require('spoils_engraving/controller').new(CORE.native, service, journal, FEES, function() return CORE.real end,
        profile.revision)
    CORE.ok = true
    -- Crafting is on whenever the game version matches.
    CORE.real = CORE.native.build.ok == true
end
do
    local ok, e = pcall(core_path)
    R.core.files = ok or tostring(e):sub(1, 600)
    R.core.dirs = CORE_DIRS
end
-- Skill materials are our own items. Each is added to the game's item table before any save loads, so held
-- materials survive loading; their names and descriptions come through the game's text getters.
local ITEMS = {ok = false, error = false, count = 0, adopted = 0, conflicts = {}, hooks = {}, missing = {}}
R.items = ITEMS
do
local ITEM_DEFS = {}
do
    local ok, d = pcall(require, 'spoils_engraving/definitions')
    if ok and type(d) == 'table' then ITEM_DEFS = d else ITEMS.error = 'definitions: ' .. tostring(d) end
end
local ITEM_OBJ = {}
-- Each material shows our own icon for its kind of skill: after the game sets up an item icon for one of ours, the icon
-- texture is switched to our icon sheet.
local ABILITY = {}
do
    local ok, cat = pcall(require, 'spoils_engraving/catalog')
    for id, e in pairs(ok and type(cat) == 'table' and cat.entries or {}) do ABILITY[id] = e.ability_id end
end
-- Which icon a material shows: EX, weapon passive or armor passive, read from the ability table.
local ABILITY_KIND = {}
do
    local ok, r = pcall(require, 'spoils_engraving/rules')
    for id, a in pairs(ok and type(r) == 'table' and r.abilities or {}) do
        if a.kind == 'ex' then ABILITY_KIND[id] = 0 elseif a.kind == 'passive' then ABILITY_KIND[id] = a.weapon == true and 1 or 2 end
    end
end
-- Game dictionaries are used the way Content Editor uses them (method names through REFramework's object syntax),
-- with plain calls as a fallback.
local function try(f) local ok, v = pcall(f) if ok then return v end return nil end
local function dcount(d)
    return num(try(function() return d:getCount() end)) or num(try(function() return d:get_Count() end))
        or num(call(d, 'get_Count')) or 0
end
local function dhas(d, id)
    local v = try(function() return d:ContainsKey(id) end)
    if v == nil then v = call(d, 'ContainsKey', id) end
    return v == true
end
local function dget(d, id)
    local v = try(function() return d[id] end)
    if type(v) ~= 'userdata' and type(v) ~= 'table' then v = call(d, 'get_Item', id) end
    return v
end
local function dset(d, id, o)
    if not pcall(function() d[id] = o end) or not dhas(d, id) then call(d, 'set_Item', id, o) end
end
local function quest_data_ready()
    local qm = sdk.get_managed_singleton('app.QuestManager')
    if not qm then return true end
    local d = qm:get_field('QuestCatalogDict')
    return d ~= nil and dcount(d) > 0
end
local function same_fields(o, data)
    for k, v in pairs(data) do
        if k ~= '$type' then
            local ok, cur = pcall(o.get_field, o, k)
            if type(cur) == 'boolean' then cur = cur and 1 or 0 end
            if not ok or num(cur) ~= v then return false, k end
        end
    end
    return true
end
local function register_items()
    if ITEMS.ok then return true end
    if not next(ITEM_DEFS) then ITEMS.ok = not ITEMS.error return ITEMS.ok end
    local im = sdk.get_managed_singleton('app.ItemManager')
    local dict = im and im:get_field('_ItemDataDict')
    if not dict or dcount(dict) == 0 or not quest_data_ready() then return false end
    local ok, e = pcall(function()
        local n, adopted, conflicts = 0, 0, {}
        for id, spec in pairs(ITEM_DEFS) do
            local data = spec.entity.data
            local o = dhas(dict, int(id)) and dget(dict, int(id)) or nil
            -- An existing entry is reused only when it looks like one of ours (an older Content Editor bundle);
            -- anything else is another mod's item and is left alone.
            local function ours(x)
                local ok2, v = pcall(function() return num(x:get_field('_Attr')) == data._Attr
                    and num(x:get_field('_StackNum')) == data._StackNum and num(x:get_field('_Category')) == data._Category end)
                return ok2 and v
            end
            if o and (tname(o) ~= data['$type'] or not ours(o)) then
                conflicts[#conflicts + 1] = {id = id, type = tname(o)}
                o = false
            elseif o then
                adopted = adopted + 1
            else
                o = sdk.create_instance(data['$type'])
                o = o and (o:add_ref_permanent() or o)
                if not o then error('could not create item ' .. id, 0) end
            end
            if o then
                for k, v in pairs(data) do if k ~= '$type' then o:set_field(k, v) end end
                local same, k = same_fields(o, data)
                if not same then error('item ' .. id .. ' field ' .. k .. ' did not read back', 0) end
                if not dhas(dict, int(id)) then dset(dict, int(id), o) end
                if addr(dget(dict, int(id))) ~= addr(o) then
                    error('item ' .. id .. ' did not register', 0)
                end
                ITEM_OBJ[id] = o
                n = n + 1
            end
        end
        ITEMS.count, ITEMS.adopted, ITEMS.conflicts = n, adopted, conflicts
    end)
    ITEMS.ok, ITEMS.error = ok, not ok and tostring(e) or false
    ITEMS.frame = S.frame
    event('items_registered', {ok = ok, error = ITEMS.error or nil, count = ITEMS.count, adopted = ITEMS.adopted,
        conflicts = #ITEMS.conflicts, missing_hooks = #ITEMS.missing})
    S.dirty = true
    return ok
end
local function our_item(id) return ITEM_OBJ[id] ~= nil end
local function hook_storage() return thread and thread.get_hook_storage and thread.get_hook_storage() or ITEMS end
local function item_hook(owner, sig, pre, post)
    local td = sdk.find_type_definition(owner)
    local m = td and td:get_method(sig)
    if not m then ITEMS.missing[#ITEMS.missing + 1] = owner .. '.' .. sig return end
    local ok, e = pcall(sdk.hook, m, pre, post)
    ITEMS.hooks[#ITEMS.hooks + 1] = {sig = owner .. '.' .. sig, ok = ok, error = not ok and tostring(e) or nil}
end
-- The name string is made in the post-hook, so nothing can collect it between the two hooks.
local function name_pre(id) hook_storage().name = our_item(id) and ITEM_DEFS[id].entity.name or nil end
-- The detail box squeezes a long line instead of wrapping it, so descriptions are broken into lines like the
-- game's own (about 40 characters).
local WRAPPED = {}
local function wrap(t)
    if WRAPPED[t] then return WRAPPED[t] end
    local lines, cur = {}, ''
    for w in t:gmatch('%S+') do
        if cur ~= '' and #cur + 1 + #w > 40 then lines[#lines + 1] = cur cur = w
        else cur = cur == '' and w or cur .. ' ' .. w end
    end
    if cur ~= '' then lines[#lines + 1] = cur end
    WRAPPED[t] = table.concat(lines, '\n')
    return WRAPPED[t]
end
local function detail_pre(id) hook_storage().name = our_item(id) and wrap(ITEM_DEFS[id].entity.description) or nil end
local function name_post(ret)
    local n = hook_storage().name
    return n and sdk.to_ptr(sdk.create_managed_string(n)) or ret
end
local function key_id(s) return type(s) == 'string' and math.tointeger(tonumber(s:match('(%d+)$'))) or nil end
local function arg_id(a) return sdk.to_int64(a) & 0xffffffff end
local function storage_id_of(a)
    local ok, v = pcall(sdk.to_valuetype, a, 'app.ItemDefine.StorageData')
    return ok and v and num(v:get_field('_ItemId')) or 0
end
local function string_arg(a)
    local o = sdk.to_managed_object(a)
    return o and call(o, 'ToString()') or nil
end
local PTR_TRUE = sdk.to_ptr(1)
item_hook('app.ItemIDUtil', 'isValidItem(System.Int32)', function(args)
    local hs = hook_storage()
    hs.valid = our_item(arg_id(args[2])) or nil
    if hs.valid then return sdk.PreHookResult.SKIP_ORIGINAL end
end, function(ret) return hook_storage().valid and PTR_TRUE or ret end)
item_hook('app.GUIBase', 'getElfItemName(System.Int32, System.Boolean)', function(args) name_pre(arg_id(args[2])) end, name_post)
item_hook('app.GUIBase', 'getItemName(System.Int32)', function(args) name_pre(arg_id(args[2])) end, name_post)
item_hook('app.GUIBase', 'getItemName(app.ItemDefine.StorageData, System.Boolean)', function(args) name_pre(storage_id_of(args[2])) end, name_post)
item_hook('app.GUIBase', 'getElfItemName(app.ItemDefine.StorageData, System.Boolean)', function(args) name_pre(storage_id_of(args[2])) end, name_post)
item_hook('app.GUIBase', 'getElfMsg(System.String, System.Boolean)', function(args) name_pre(key_id(string_arg(args[2]))) end, name_post)
item_hook('app.GUIBase', 'getItemDetail(System.Int32)', function(args) detail_pre(arg_id(args[2])) end, name_post)
item_hook('app.GUIBase', 'getElfItemDetail(System.Int32, System.Boolean)', function(args) detail_pre(arg_id(args[2])) end, name_post)
item_hook('app.GUIBase', 'getItemDetail(app.ItemDefine.StorageData)', function(args) detail_pre(storage_id_of(args[2])) end, name_post)
item_hook('app.ui023301.Notice', 'setupText()', function(args)
    local hs = hook_storage()
    local this = sdk.to_managed_object(args[2])
    local d = this and this:get_field('Data')
    local id = d and num(d:get_field('ItemId'))
    hs.notice = id and our_item(id) and {elem = this:get_field('TxtName'), name = ITEM_DEFS[id].entity.name} or nil
end, function(ret)
    local n = hook_storage().notice
    if n and n.elem then pcall(n.elem.call, n.elem, 'set_Message(System.String)', n.name) end
    return ret
end)
item_hook('app.GUIBase.ItemWindowRef', 'setup(app.ItemCommonParam, System.Int32, System.Boolean, System.Boolean)', function(args)
    local hs = hook_storage()
    local d = sdk.to_managed_object(args[3])
    local id = d and num(d:get_field('_Id'))
    hs.window = id and our_item(id) and {this = sdk.to_managed_object(args[2]), text = wrap(ITEM_DEFS[id].entity.description)} or nil
end, function(ret)
    local w = hook_storage().window
    local t = w and w.this and w.this:get_field('_TxtInfo')
    if t then pcall(t.call, t, 'set_Message(System.String)', w.text) end
    return ret
end)
local ICONS = {swapped = {}, ability_icon = {}, stack = {}}
ITEMS.icons = ICONS
local function load_atlas(path)
    local ok, h = pcall(function()
        local r = sdk.create_resource('via.uvsequence.UVSequenceResource', path)
        return r and r:create_holder('via.uvsequence.UVSequenceResourceHolder'):add_ref()
    end)
    return ok and h or nil
end
-- Our own icon sheet, shipped as loose files under natives/stm/spoils_engraving (tools/icons/make_sheet.py): one
-- sequence; patterns 0-9 are the ability icons, 10-109 the skill icons by the skill's icon number, in 120px cells.
ICONS.path = 'spoils_engraving/skill_icons.uvs'
local ICON_KIND = {EX = 0, Passive = 1, Armor = 2}
local function icon_no(id)
    local c = ICONS.ability_icon[id]
    if c ~= nil then return c or nil end
    local kind = ABILITY[id] and ABILITY_KIND[ABILITY[id]]
    ICONS.ability_icon[id] = kind ~= nil and kind or false
    return kind
end
local SKILL_BASE, SKILL_COUNT = 10, 100
local function game_icon_no(id)
    local ab = ABILITY[id]
    if not ab then return nil end
    local gm = sdk.get_managed_singleton('app.GuiManager')
    local t = gm and gm:get_field('EquipmentAbilityParamTable')
    local p = t and dhas(t, ab) and dget(t, ab)
    return p and num(try(function() return p:get_field('_IconNo') end))
end
local function restore_icon(k)
    local s = ICONS.swapped[k]
    if s then
        pcall(s.tex.call, s.tex, 'set_UVSequence', s.orig)
        ICONS.swapped[k] = nil
    end
end
-- true: our icon was drawn on tex
local function draw_skill_icon(tex, id)
    local n = icon_no(id)
    if not n then return false end
    if ICONS.atlas == nil then
        ICONS.atlas = load_atlas(ICONS.path) or false
        if not ICONS.atlas then ICONS.error = 'could not load ' .. ICONS.path event('icon_error', {error = ICONS.error}) end
    end
    if not ICONS.atlas then return false end
    local k = addr(tex)
    if not k then return false end
    local ok, e = pcall(function()
        if not ICONS.swapped[k] then
            local orig = tex:call('get_UVSequence')
            ICONS.swapped[k] = {tex = tex:add_ref(), orig = orig and orig:add_ref()}
        end
        if not ICONS.numbers_logged then
            -- Icon numbers of every material's skill, by kind, for building the final sheet.
            ICONS.numbers_logged = true
            local by = {}
            for mid in pairs(ITEM_DEFS) do
                local k, gi = icon_no(mid), game_icon_no(mid)
                if k and gi then
                    by[k] = by[k] or {}
                    by[k][gi] = (by[k][gi] or 0) + 1
                end
            end
            event('icon_numbers', by)
        end
        if n ~= ICON_KIND.EX then
            -- Our sheet holds the game's ability icons 0-9 with a transparent margin, so they sit at item-icon size.
            local g = game_icon_no(id)
            if g and g < 10 then
                tex:call('set_UVSequence', ICONS.atlas)
                tex:call('set_UVSequenceNo', 0)
                tex:call('set_UVPatternNo', g)
                ICONS.logged = ICONS.logged or {}
                if not ICONS.logged[n] then
                    ICONS.logged[n] = true
                    event('game_icon', {id = id, kind = n, icon = g})
                end
                return
            end
        end
        -- EX skills: the skill's own icon from our copy of the game's skill sheet.
        local g = n == ICON_KIND.EX and game_icon_no(id)
        local pat = g and g >= 0 and g < SKILL_COUNT and SKILL_BASE + g or n
        tex:call('set_UVSequence', ICONS.atlas)
        tex:call('set_UVSequenceNo', 0)
        tex:call('set_UVPatternNo', pat)
        if n == ICON_KIND.EX and not ICONS.ex_logged then
            ICONS.ex_logged = true
            event('ex_icon', {id = id, icon = g or false, pattern = pat})
        end
    end)
    if not ok then
        restore_icon(k)
        ICONS.error = tostring(e)
        event('icon_error', {error = ICONS.error})
    end
    return ok
end
local function seen(sig)
    ICONS.calls = ICONS.calls or {}
    local n = (ICONS.calls[sig] or 0) + 1
    ICONS.calls[sig] = n
    if n == 1 then event('icon_hook', {sig = sig}) end
end
-- Icon owners whose texture is reset before the game draws into it and switched after, when the item is ours.
local function icon_owner(owner, sig, field, id_of)
    item_hook(owner, sig, function(args)
        -- A stack, since one setup overload may call another.
        local this = sdk.to_managed_object(args[2])
        local tex = this and try(function() return this:get_field(field) end)
        local i = false
        if tex then
            local k = addr(tex)
            if k and ICONS.swapped[k] then restore_icon(k) end
            local id = try(function() return id_of(args) end)
            if id and our_item(id) then i = {tex = tex, id = id} seen(owner .. '.' .. sig) end
        end
        ICONS.stack[#ICONS.stack + 1] = i
    end, function(ret)
        local i = table.remove(ICONS.stack)
        if i then
            local ok = draw_skill_icon(i.tex, i.id)
            if not ICONS.first then
                ICONS.first = true
                event('icon_draw', {ok = ok, id = i.id, error = ICONS.error or nil})
            end
        end
        return ret
    end)
end
local function a_int(n) return function(args) return arg_id(args[n]) end end
local function a_storage(n) return function(args) return storage_id_of(args[n]) end end
local function a_param(n) return function(args)
    local d = sdk.to_managed_object(args[n])
    return d and num(d:get_field('_Id'))
end end
local I3, IW = 'app.GUIBase.ItemIcon3Ref', 'app.GUIBase.ItemWindowRef'
icon_owner(I3, 'setup(System.Int32, System.Int32, System.Boolean)', 'TexIcon', a_int(3))
icon_owner(I3, 'setup(System.Int32, app.ItemDefine.StorageData, System.Int32, System.Boolean)', 'TexIcon', a_storage(4))
icon_owner(I3, 'setup(app.ItemCommonParam, System.Int32, System.Boolean, System.Boolean, System.Boolean, System.Boolean, app.ItemDefine.StorageData)', 'TexIcon', a_param(3))
icon_owner(I3, 'setup(app.ItemDefine.StorageData, System.Boolean, System.Boolean, System.Int32, System.Boolean, System.Boolean, System.Boolean, System.Int32)', 'TexIcon', a_storage(3))
icon_owner(IW, 'setup(System.Int32, System.Int32, System.Boolean)', '_TexIcon', a_int(3))
icon_owner(IW, 'setup(app.ItemDefine.StorageData, System.Int32, System.Boolean, System.Boolean)', '_TexIcon', a_storage(3))
icon_owner(IW, 'setup(app.ItemDefine.StorageData)', '_TexIcon', a_storage(3))
-- Other screens (the item-get notices) draw through the static GUIBase.setItemIconUV(texture, item[, storage]).
for _, x in ipairs({{sig = 'setItemIconUV(via.gui.Texture, System.UInt32)'},
        {sig = 'setItemIconUV(via.gui.Texture, System.UInt32, app.ItemDefine.StorageData)', storage = true}}) do
    item_hook('app.GUIBase', x.sig, function(args)
        local tex = sdk.to_managed_object(args[2])
        local i = false
        if tex then
            local k = addr(tex)
            if k and ICONS.swapped[k] then restore_icon(k) end
            local id = arg_id(args[3])
            if x.storage and not our_item(id) then id = try(function() return storage_id_of(args[4]) end) end
            if not ICONS.uv_logged then ICONS.uv_logged = 0 end
            if ICONS.uv_logged < 5 then ICONS.uv_logged = ICONS.uv_logged + 1 event('icon_uv', {sig = x.sig, id = id, ours = id and our_item(id) or false}) end
            if id and our_item(id) then i = {tex = tex, id = id} end
        end
        ICONS.stack[#ICONS.stack + 1] = i
    end, function(ret)
        local i = table.remove(ICONS.stack)
        if i then draw_skill_icon(i.tex, i.id) end
        return ret
    end)
end
re.on_script_reset(function() for k in pairs(ICONS.swapped) do restore_icon(k) end end)
-- Registration also runs just before a save loads, in case the title screen was skipped.
item_hook('app.SaveDataManager', 'loadGame', function() register_items() end, function(ret) return ret end)
re.on_frame(function() if not ITEMS.ok and not ITEMS.error then register_items() end end)
-- The crafting core checks materials through this, in place of Content Editor's database.
ITEM_DB = {
    is_ready = function() return ITEMS.ok end,
    get_entity = function(_, id)
        local spec = ITEM_DEFS[id]
        return spec and ITEM_OBJ[id] and {id = id, name = spec.entity.name, description = spec.entity.description,
            runtime_instance = ITEM_OBJ[id]} or nil
    end,
    get_all_entity_bundles = function(e) return {ITEM_DEFS[e.id].bundle} end,
    name_of = function(id) local d = ITEM_DEFS[id] return d and d.entity.name or nil end,
}
end
local function ensure_core()
    -- Another save was loaded: compose again so its own journal is used.
    if CORE.ok and CORE.slot ~= SAVE.slot then CORE.ok = false event('save_slot', {from = CORE.slot, to = SAVE.slot}) end
    if CORE.ok then return true end
    local t0 = now()
    local ok, e = pcall(compose)
    CORE.error = not ok and tostring(e) or false
    R.core.ok, R.core.error, R.core.build = CORE.ok, CORE.error or nil, build_info()
    R.core.events[#R.core.events + 1] = {kind = 'compose', ok = ok, error = CORE.error or nil, ms = math.floor((now() - t0) * 1000)}
    S.dirty = true
    return CORE.ok
end
-- Records the observed fingerprint, so this game version is accepted until the write methods change.
local function allow_real()
    local b = CORE.native.build
    if type(b.observed) ~= 'table' then error(b.reason or 'The game version could not be checked.', 0) end
    if json.dump_file(FP_FILE, b.observed) == false then error('The fingerprint file was not written.', 0) end
    CORE.native.build = require('spoils_engraving/build_check').verify(sdk, json.load_file(FP_FILE))
    if not CORE.native.build.ok then error(CORE.native.build.reason or 'The game version could not be verified.', 0) end
    CORE.real = CORE.native.build.ok == true
    R.core.build, R.core.real_allowed = build_info(), CORE.real or R.core.real_allowed
    R.core.events[#R.core.events + 1] = {kind = 'allow_real', code = b.code, ok = CORE.real, frame = S.frame}
    S.dirty = true
end
local function disallow_real()
    CORE.native.build = require('spoils_engraving/build_check').verify(sdk, KNOWN_FP)
    CORE.real = CORE.native.build.ok == true
    R.core.build, R.core.real_allowed = build_info(), CORE.real
    R.core.events[#R.core.events + 1] = {kind = 'disallow_real', ok = CORE.real, frame = S.frame}
    S.dirty = true
end
local function plain(e)
    e = tostring(e):gsub('^[^\n]-%.lua:%d+: ', '')
    if e:find('not enabled yet', 1, true) then return "Move the gear and its skill material out of the pawn's inventory first." end
    return e
end
local function timed(kind, fn)
    local t0 = now()
    local ok, v = pcall(fn)
    return ok, v, {kind = kind, ok = ok, error = not ok and tostring(v) or nil, ms = math.floor((now() - t0) * 1000), frame = S.frame}
end
local function refresh_core()
    local ok, _, entry = timed('refresh', function() CORE.c:refresh() end)
    if not ok then CORE.c.captured = false end
    push(R.core.refreshes, entry)
    return ok
end
-- Prices one action. Without real crafting the core's write checks run as a dry run, with the version check skipped.
local function quote(kind, r)
    local c = CORE.c
    local ok, e, entry = timed('quote ' .. kind, function()
        if not c.captured then c:refresh() end
        c.operation = kind == 'dismantle' and 'extract' or kind == 'repair' and 'repair' or 'fit'
        c.configuration = kind == 'fit' and fit_config(r.w) or FEES
        c:select(r.w.owner, int(r.w.storage_id))
        if kind == 'dismantle' then
            for _, p in ipairs(r.keep) do c.positions[p] = true end
        else
            c.material_id, c.position = int(r.material), r.slot
        end
        c:preview()
    end)
    entry.weapon, entry.scope, entry.real = r.w.item_id, r.w.owner, CORE.real
    if ok then
        local p = c.quote.plan
        entry.fee, entry.grants, entry.patch = p.fee, #(p.grants or {}), p.patch
        entry.material_scope = p.material_consumption and p.material_consumption.scope or nil
        if not CORE.real then
            local saved = CORE.native.build
            CORE.native.build = {ok = true}
            local ok2, e2 = pcall(CORE.native.preflight, CORE.native, c.quote)
            CORE.native.build = saved
            entry.preflight, entry.preflight_error = ok2, not ok2 and tostring(e2) or nil
        end
    end
    push(R.core.quotes, entry)
    if not ok then return nil, plain(e) end
    if entry.preflight == false then return nil, 'Check failed: ' .. plain(entry.preflight_error) end
    return c.quote
end
-- Runs the confirmed quote. The core journals each step, verifies it against a fresh read and charges gold last.
local function craft(kind)
    local c = CORE.c
    local before = counts('before ' .. kind)
    local fee = c.quote and c.quote.plan.fee
    c.enabled, c.confirmed = true, true
    local ok, v, entry = timed('craft ' .. kind, function() return c:confirm(true) end)
    c.enabled, c.confirmed = false, false
    entry.done = ok and v ~= false
    entry.fee, entry.status, entry.before = fee, c.status, before
    entry.locked, entry.lock_reason = c.coordinator.locked, c.coordinator.reason or nil
    entry.after = counts('after ' .. kind)
    if before.gold and entry.after.gold then entry.gold_spent = before.gold - entry.after.gold end
    push(R.core.crafts, entry)
    if entry.done then S.session.crafted = (S.session.crafted or 0) + 1 end
    if not ok then
        return false, (entry.locked and 'Crafting stopped and is locked: ' or 'Crafting stopped: ') .. plain(v)
    end
    if v == false then return false, 'Your inventory changed before crafting. Nothing was charged. Try again.' end
    return true
end

-- Inventory scan: appraised Spoils weapons and armor from base records only; equipped ones are listed but blocked. Reads bounded primitives from live masters.
local GEAR_TYPES = {['app.ItemWeaponParam'] = 'weapon', ['app.ItemArmorParam'] = 'armor'}
local gear_cache = {}
local function gear_info(item)
    if gear_cache[item] == nil then
        local im = sdk.get_managed_singleton('app.ItemManager')
        local d = im and B.item_data and B.item_data:call(im, int(item))
        local kind = d ~= nil and GEAR_TYPES[tname(d)] or false
        local function field(k) local ok, v = pcall(d.get_field, d, k) return ok and num(v) or nil end
        gear_cache[item] = kind and {kind = kind, cat = field('_EquipCategory') or -1, job = field('_Job') or 0} or false
    end
    return gear_cache[item]
end
local function gear_kind(item) local g = gear_info(item) return g and g.kind or false end
local function scan()
    local rows, held, skipped = {}, {}, {expanded = 0, equipped = 0, not_spoils = 0, not_gear = 0, other_inventory = 0, over_limit = 0}
    for _, l in ipairs(lists()) do
        for i = 0, math.min(l.count, 8192) - 1 do
            local m = call(l.list, 'get_Item(System.Int32)', int(i))
            local t = m and tname(m)
            if t == MASTER then
                local item = m:read_short(MASTER_BASE + 32)
                local ability = MATERIALS[item]
                if ability then held[ability] = (held[ability] or 0) + m:read_short(MASTER_BASE + 34)
                elseif m:read_byte(MASTER_BASE + 44) == 1 and #rows >= MAX_ROWS then skipped.over_limit = skipped.over_limit + 1
                elseif m:read_byte(MASTER_BASE + 44) == 1 then
                    local equipped = m:read_byte(MASTER_BASE + 37) ~= 0
                    if not gear_kind(item) then skipped.not_gear = skipped.not_gear + 1
                    else
                        local ext = m:read_dword(MASTER_BASE + 60)
                        if ext >= 0x80000000 then ext = ext - 0x100000000 end
                        local src = B.source and num(B.source:call(nil, int(ext))) or 0
                        local spoils = src > 0 and (not B.equip_source or B.equip_source:call(nil, int(src)) == true)
                        if not spoils then skipped.not_spoils = skipped.not_spoils + 1
                        else
                            local ab = {}
                            for k = 0, 19 do ab[k] = m:read_byte(MASTER_BASE + 40 + k) end
                            local sid = m:read_dword(MASTER_BASE + 20)
                            if WRITE_SCOPES[l.label] then
                                local g = gear_info(item)
                                local fav = (num(B.favorite:call(nil, int(ext))) or 0) ~= 0
                                rows[#rows + 1] = {owner = l.label, chara = l.chara, storage_id = sid, item_id = item, source = src, ab = ab,
                                    kind = g.kind, cat = g.cat, job = g.job, favorite = fav, equipped = equipped or nil, ext = ext}
                                if equipped then skipped.equipped = skipped.equipped + 1 end
                            else skipped.other_inventory = skipped.other_inventory + 1 end
                        end
                    end
                end
            elseif t then
                skipped.expanded = skipped.expanded + 1
            end
        end
    end
    return rows, held, skipped
end
local function slots(ab) return {ab[0], ab[1], ab[2], ab[3]} end
local function copy(ab) local c = {} for k = 0, 19 do c[k] = ab[k] end return c end
local function has(ab, a) for k = 0, 3 do if ab[k] == a then return true end end return false end
local function valid_set(item)
    if not (B.valid and B.contains) then return nil end
    local ok, set = pcall(B.valid.call, B.valid, nil, int(item))
    return ok and set or nil
end
local MATERIAL_OF = {}
for m, a in pairs(MATERIALS) do MATERIAL_OF[a] = m end
local ZERO = {}
for k = 0, 19 do ZERO[k] = 0 end
-- Skill slots per ItemEquipCategory (GUIAppraisalDefine.MaxEquipSlotCount): Main, Sub, Head, Upper, Lower.
local MAX_SLOTS = {[0] = 4, [1] = 2, [2] = 3, [3] = 4, [4] = 3}
local function free_slot(w) for k = 0, (MAX_SLOTS[w.cat] or 4) - 1 do if w.ab[k] == 0 then return k end end return nil end
local function fits(set, a)
    if not set then return true end
    local ok, v = pcall(B.contains.call, B.contains, set, int(a))
    return not (ok and v == false)
end
local function armor_skill(a) return a >= 75 and a <= 142 or a >= 167 and a <= 174 end
-- Step 2 rows: held skill materials that fit the gear. Armor takes any armor passive (the core checks the rest);
-- weapons follow the game's valid-skill set.
local function materials(w)
    local armor = w.kind == 'armor'
    local out, set, pool, simulated = {}, not armor and valid_set(w.item_id) or nil, {}, false
    for a, n in pairs(S.held) do if n > 0 then pool[a] = n end end
    local ids = {}
    for a in pairs(pool) do ids[#ids + 1] = a end
    table.sort(ids)
    local free = free_slot(w)
    for _, a in ipairs(ids) do
        local m = MATERIAL_OF[a]
        if #out < MAX_PREVIEWS and m and not has(w.ab, a) and armor_skill(a) == armor and fits(set, a) then
            local after = false
            if free then after = copy(w.ab) after[free] = a end
            out[#out + 1] = {w = w, skill = a, material = m, count = pool[a], item_id = m, source_item = w.source,
                ab = copy(ZERO), after = after, slot = free and free + 1 or false}
        end
    end
    return out, set ~= nil, simulated
end
-- The core's refusal when gear already holds as many EX skills as its level allows.
local EX_FULL = 'This gear cannot hold another weapon skill.'
local function is_ex(a)
    local n = ITEM_DB.name_of(MATERIAL_OF[a])
    return n ~= nil and n:match('^Relic Skill %(EX%)') ~= nil
end
-- Step 3 rows: the weapon with each of its skills replaced by the material's skill; with ex_only, only its EX skills.
local function replacements(m, ex_only)
    local out = {}
    for k = 0, 3 do
        local old = m.w.ab[k]
        if old ~= 0 and (not ex_only or is_ex(old)) then
            local ab = copy(m.w.ab)
            ab[k] = m.skill
            out[#out + 1] = {w = m.w, skill = m.skill, material = m.material, slot = k + 1, replaces = old,
                item_id = m.w.item_id, source_item = m.w.source, ab = ab}
        end
    end
    return out
end

-- Result rows go through the screen's own GUIAppraisalResultData and grid.
local function new_list(ctor, td)
    local l = sdk.create_instance(td, true)
    l = l:add_ref() or l
    ctor:call(l)
    return l
end
local function build_lists(rows)
    local li, lb = new_list(B.list_info_ctor, LIST_INFO), new_list(B.list_int_ctor, LIST_INT)
    for _, r in ipairs(rows) do
        local o = sdk.create_instance(INFO, true)
        o = o:add_ref() or o
        B.info_ctor:call(o)
        o:set_field('ItemId', int(r.item_id))
        o:set_field('ItemCount', int(r.count or 1))
        for k = 0, 19 do o:write_byte(AB + k, int(r.ab[k])) end
        for k = 0, 19 do if o:read_byte(AB + k) ~= r.ab[k] then error('ability write did not read back', 0) end end
        if num(o:get_field('ItemId')) ~= r.item_id then error('item id did not read back', 0) end
        B.list_info_add:call(li, o)
        B.list_int_add:call(lb, int(r.source_item or r.source))
        S.keep[#S.keep + 1] = o
    end
    S.keep[#S.keep + 1], S.keep[#S.keep + 2] = li, lb
    return li, lb
end
local function each_slot(result, fn)
    local arr = B.slot_list:call(result)
    if not arr then return 0 end
    local n = 0
    local ok, sz = pcall(arr.get_size, arr)
    if not (ok and type(sz) == 'number') then sz = num(call(arr, 'get_Length()')) or 0 end
    for i = 0, sz - 1 do
        local s = call(arr, 'Get(System.Int32)', int(i))
        if s == nil then local ok2, v = pcall(function() return arr[i] end) s = ok2 and v or nil end
        if s then n = n + 1 fn(s) end
    end
    return n
end
local function storage_of(s)
    local v = B.slot_storage:call(s)
    if not v then return nil end
    local ab = {}
    for k = 0, 19 do ab[k] = v:read_byte(40 + k) end
    return {item_id = v:read_short(32), ab = ab, ext = v:read_dword(60), storage_id = v:read_dword(20)}
end
local function same(a, b) for k = 0, 19 do if a[k] ~= b[k] then return false end end return true end
local function map_keys(result, rows)
    local used, keymap, unmatched = {}, {}, 0
    local n = each_slot(result, function(s)
        local key, st = num(B.slot_key:call(s)), storage_of(s)
        local hit = nil
        for i, r in ipairs(rows) do
            if not used[i] and st and st.item_id == r.item_id and same(st.ab, r.ab) then hit = i break end
        end
        if hit then used[hit] = true keymap[key] = rows[hit] else unmatched = unmatched + 1 end
    end)
    return keymap, n, unmatched
end
local function apply(screen, rows, stage)
    local result = screen:get_field('Result')
    local grid = screen:get_field('AppraisalItemGridPanel')
    if not grid then error('screen grid missing', 0) end
    if not result then
        result = sdk.create_instance(RESULT, true)
        result = result:add_ref() or result
        B.result_ctor:call(result)
        screen:set_field('Result', result)
        if addr(screen:get_field('Result')) ~= addr(result) then error('screen Result did not read back', 0) end
        S.keep[#S.keep + 1] = result
        event('result_created', {})
    end
    S.step = 'build_lists' event('step', {name = 'build_lists', stage = stage})
    local li, lb = build_lists(rows)
    local prev = S.lists
    S.lists = {li, lb}
    S.applying, S.apply_stage = true, stage
    local ok, e = pcall(function()
        S.step = 'clear' event('step', {name = 'clear', stage = stage})
        B.clear:call(result)
        S.step = 'applyResultInfo' event('step', {name = 'applyResultInfo', stage = stage})
        B.applyResultInfo:call(result, li, lb)
        -- Rows are drawn inside setAppraisalItemInfo, so the row lookup for drawing exists before it.
        S.draw_map = map_keys(result, rows)
        S.step = 'setAppraisalItemInfo' event('step', {name = 'setAppraisalItemInfo', stage = stage})
        pcall(function() grid:call('set_StopAnimation(System.Boolean)', true) end)
        B.setAppraisalItemInfo:call(grid, result)
    end)
    if not ok and prev then
        -- Put the previous step's rows back so the grid and Result stay in step.
        local ok2, e2 = pcall(function()
            B.clear:call(result)
            B.applyResultInfo:call(result, prev[1], prev[2])
            B.setAppraisalItemInfo:call(grid, result)
        end)
        S.lists = prev
        event('apply_restored', {ok = ok2, error = not ok2 and tostring(e2) or nil})
    end
    S.applying = false
    -- The reveal sound plays a few frames after the rows go in; see SOUND.
    S.mute_until = S.frame + 20
    if not ok then error(e, 0) end
    S.step = 'map_keys'
    local keymap, n, unmatched = map_keys(result, rows)
    S.keymap, S.stage, S.result, S.cur_rows = keymap, stage, addr(result), rows
    local inj = {stage = stage, rows = #rows, slots = n, unmatched = unmatched, count = num(B.slot_count:call(result)),
        flow = num(screen:get_field('CurrFlowId')), filtered = false}
    local fl = grid:get_field('FilteredInfoList')
    inj.filtered = fl and num(call(fl, 'get_Count()')) or false
    -- Every row starts as already revealed, so the reveal has nothing to play.
    local ended = 0
    for i = 0, (inj.filtered or 0) - 1 do
        local info = call(fl, 'get_Item(System.Int32)', i)
        if info and pcall(function() info:call('set_IsEndedAnimation(System.Boolean)', true) end) then ended = ended + 1 end
    end
    inj.ended = ended
    -- The grid's own switch for the reveal, off on our screens.
    inj.stop_anim = pcall(function() grid:call('set_StopAnimation(System.Boolean)', true) end) and call(grid, 'get_StopAnimation()') == true
    -- The hold-to-equip list is off on our screens; its decide hook cannot be placed on this build.
    inj.arisen_select_off = pcall(function() grid:call('set_IsEnableArisenEquipSelect(System.Boolean)', false) end)
        and call(grid, 'get_IsEnableArisenEquipSelect()') == false
    push(R.injections, inj)
    S.draw_logged = false
    event('inject', inj)
    return inj
end
-- Gear-type filters, added to the screen's own Sort list (G). Ids sit above the game's sort ids.
local FILTER_BASE = 9000
-- Picking the active filter again turns it off.
local FILTERS = {{id = FILTER_BASE + 1, label = 'Weapons', kind = 'weapon'}, {id = FILTER_BASE + 2, label = 'Armor', kind = 'armor'}}
local function filter_list() return FILTERS end
local function passes(r, f) return not f or r.kind == f.kind end
-- Gear that is listed with the "can't equip" mark, with the reason shown when it is picked.
local function blocked(r)
    if not r or r.slot or r.material or not r.kind then return nil end
    if r.equipped then return 'Unequip this gear first.' end
    if r.favorite and mode() == 'dismantle' then return 'Favorite gear cannot be dismantled. Remove the favorite mark first.' end
    return nil
end
-- The gear list shows one inventory at a time; LT/RT switches between the player and storage. Blocked gear goes last.
local function gear_rows()
    local out, late = {}, {}
    for _, r in ipairs(S.rows) do
        if (S.view == 'all' or r.owner == (S.view or 'player')) and passes(r, S.filter) then
            local t = blocked(r) and late or out
            t[#t + 1] = r
        end
    end
    for _, r in ipairs(late) do out[#out + 1] = r end
    local rc = S.recent
    for i, r in ipairs(rc and out or {}) do
        if r.owner == rc.owner and r.storage_id == rc.storage_id then table.insert(out, 1, table.remove(out, i)) break end
    end
    return out
end
-- The screen's LT/RT switcher gets two entries: the player and Storage. Every entry holds a real character, because
-- the screen reads the selected character on each switch and v17 crashed with the warehouse ID there. The Storage
-- entry is the player again; its CharaData carries the warehouse ID only while its row is drawn, so the switcher
-- draws its own warehouse icon.
local CC_ITEM = 'app.GUIBase.CharaChangeRef.ListItem'
local CHARA_ID = '<CharaId>k__BackingField'
local function unswap()
    local w = S.swap
    if not w then return end
    S.swap = false
    w.d:set_field(CHARA_ID, w.id)
end
local function swap(info)
    local d = info and info:get_field('Data')
    local id = d and num(d:get_field(CHARA_ID))
    if not (id and S.wh_id) then return false end
    S.swap = {d = d, id = id}
    d:set_field(CHARA_ID, S.wh_id)
    return true
end
local function item_state(item)
    local out = {uv = num(item:get_field('WarehouseIconUVNo'))}
    for _, k in ipairs({'TexSelect', 'TexDefault'}) do
        local t = item:get_field(k)
        out[k] = t and {visible = call(t, 'get_Visible()'), uv = num(call(t, 'get_UVSequenceNo()'))} or false
    end
    return out
end
local function elem(arr, i)
    if not (arr and i) then return nil end
    local ok, x = pcall(function() return arr:get_element(i) end)
    if ok and x then return x end
    ok, x = pcall(function() return arr[i] end)
    return ok and x or nil
end
local function tab_item(lc, tab)
    local info = call(lc, 'getInfo(System.Int32)', tab)
    return info, info and elem(lc:get_field('ItemList'), num(info:get_field('ItemIndex')))
end
local function draw_storage(cc)
    local lc = cc:get_field('_ListCtrl')
    if not lc then return {ok = false, why = 'no list'} end
    local info, item = tab_item(lc, S.tab_of.storage)
    if not (info and item) then return {ok = false, info = info ~= nil, item = item ~= nil} end
    S.storage_info = addr(info)
    local ok, e = pcall(function()
        if not swap(info) then error('no CharaData') end
        item:call('updateDisp(app.GUIBase.CharaChangeRef.ListInfo)', info)
    end)
    unswap()
    local _, pitem = tab_item(lc, S.tab_of.player)
    return {ok = ok, error = not ok and tostring(e) or nil, storage = item_state(item), player = pitem and item_state(pitem) or false}
end
local function setup_views(screen)
    S.view_ids, S.tab_of, S.storage_info, S.view = nil, nil, false, 'all'
    local cc = screen:get_field('CharaChange')
    if not cc then event('views', {ok = false, why = 'no CharaChange'}) return end
    local ids = {}
    for _, o in ipairs(owners()) do ids[o[1]] = o[2] end
    S.wh_id = ids.storage
    if not (ids.player and ids.storage) then event('views', {ok = false, why = 'ids'}) return end
    local arr = sdk.create_managed_array('app.CharacterID', 2)
    arr = arr:add_ref() or arr
    S.keep[#S.keep + 1] = arr
    arr[0], arr[1] = int(ids.player), int(ids.player)
    local ok, e = pcall(function() cc:call('setup(app.CharacterID[], System.Int32, System.Boolean)', arr, 0, S.cc_flag or false) end)
    local count = num(call(cc, 'get_Count()'))
    S.session.views = {ok = ok, error = not ok and tostring(e) or nil, count = count, flag = S.cc_flag, pawn = ids.main_pawn ~= nil, view = S.view}
    if not (ok and count == 2) then event('views', S.session.views) return end
    S.view_ids = {[0] = 'player', [1] = 'storage'}
    S.tab_of = {player = 0, storage = 1}
    S.view = 'player'
    S.session.views.view = S.view
    local okd, d = pcall(draw_storage, cc)
    S.session.views.icon = okd and d or {ok = false, error = tostring(d)}
    event('views', {count = count, view = S.view, icon = S.session.views.icon.ok})
end
-- The view follows the switcher's selected entry.
local function tab_view(cc)
    local lc = cc and cc:get_field('_ListCtrl')
    local i = lc and num(call(lc, 'get_SelectedIndex()'))
    return i and S.view_ids and S.view_ids[i], i
end
local function holder_for(w)
    local h = sdk.create_instance(RESULT, true)
    h = h:add_ref() or h
    B.result_ctor:call(h)
    local li, lb = build_lists({w})
    S.applying = true
    local ok, e = pcall(B.applyResultInfo.call, B.applyResultInfo, h, li, lb)
    S.applying = false
    if not ok then error(e, 0) end
    local p = false
    each_slot(h, function(s)
        local st = storage_of(s)
        if st and st.item_id == w.item_id and same(st.ab, w.ab) then
            p = addr(s) + SLOT_STORAGE
            S.keep[#S.keep + 1] = s
        end
    end)
    S.keep[#S.keep + 1] = h
    return p
end

-- Command rows: Send to Storage, Sell and Favorite are removed. Labels follow the step.
local function relabel(grid)
    local out = {}
    for _, fname in ipairs({'EquipDefaultPulldownCommandList', 'ItemDefaultPulldownCommandList'}) do
        local l = grid:get_field(fname)
        local rows = {}
        if l then
            for i = num(B.cmd_count:call(l)) - 1, 0, -1 do
                local info = B.cmd_item:call(l, int(i))
                local c = info and num(info:get_field('CommandId'))
                if c == 3 or c == 4 or c == 6 then B.cmd_remove:call(l, int(i)) end
            end
            for i = 0, num(B.cmd_count:call(l)) - 1 do
                local info = B.cmd_item:call(l, int(i))
                rows[#rows + 1] = {command = num(info:get_field('CommandId')), msg = text(info:get_field('Msg'))}
            end
        end
        out[fname] = rows
    end
    return out
end
local function set_labels(grid, stage)
    S.step = 'labels'
    local out = {}
    for _, fname in ipairs({'EquipDefaultPulldownCommandList', 'ItemDefaultPulldownCommandList'}) do
        local l = grid:get_field(fname)
        if l then
            for i = 0, num(B.cmd_count:call(l)) - 1 do
                local info = B.cmd_item:call(l, int(i))
                local label = label_for(stage, num(info:get_field('CommandId')))
                if label then
                    local ok, e = pcall(info.set_field, info, 'Msg', mstr(label))
                    out[#out + 1] = {list = fname, label = label, read_back = ok and text(info:get_field('Msg')) == label, error = not ok and tostring(e) or nil}
                end
            end
        end
    end
    push(R.labels, {stage = stage, rows = out})
end

-- Yes/no dialog with the argument set the game used for its Sell confirm.
local function ask(kind, msg, data)
    local gm = sdk.get_managed_singleton('app.GuiManager')
    if not (gm and B.dialog) then error('dialog unavailable', 0) end
    local d = {kind = kind, msg = msg, data = data, frame = S.frame, values = {}}
    push(R.dialogs, d)
    local info = kind == 'info' or kind == 'none'
    B.dialog:call(gm, mstr(msg), mstr(info and 'OK' or 'Yes'), mstr(info and 'Back' or 'No'), mstr(''), mstr(''), false, 0, false, 40, 0, -1, nil,
        true, false, false, false, true, -1.0, false, false, false)
    d.requested = true
    S.dialog = d
    event('dialog', {kind = kind})
end
local function row_info(r)
    return {owner = r.owner, storage_id = r.storage_id, item_id = r.item_id, name = item_name(r.item_id), slots = slots(r.ab)}
end
local function test_note() return (CORE.ok and CORE.real) and '' or ' Test run: nothing will change.' end
-- Step 4 rows: one row per skill of the weapon that has a material. Checked rows (the grid's own Select Multiple) are kept.
local function keep_rows(w)
    local out = {}
    for k = 0, 3 do
        local a = w.ab[k]
        local m = a ~= 0 and MATERIAL_OF[a]
        if m then
            out[#out + 1] = {w = w, skill = a, material = m, item_id = m, count = 1, source_item = w.source,
                ab = copy(ZERO), pos = k + 1}
        end
    end
    return out
end
-- Rows the player checked on step 4, read from the grid's infos.
local function checked(screen)
    local out = {}
    local g = screen and screen:get_field('AppraisalItemGridPanel')
    local fl = g and g:get_field('FilteredInfoList')
    local n = fl and num(call(fl, 'get_Count()')) or 0
    for i = 0, n - 1 do
        local info = call(fl, 'get_Item(System.Int32)', i)
        if info and call(info, 'get_IsChecked()') == true then
            local r = S.keymap[num(B.info_key:call(info))]
            if r then out[#out + 1] = r end
        end
    end
    return out
end
local function kept(screen)
    if S.stage ~= 4 then return 0 end
    local ok, rows = pcall(checked, screen)
    return ok and #rows or 0
end
local function clear_checks(screen)
    local g = screen:get_field('AppraisalItemGridPanel')
    event('clear_checks', {})
    local ok, e = pcall(function() g:call('clearCheckedGridInfo()') end)
    if not ok then err('clear checks', e) end
end
-- app.EquipmentAbilityBonus flags, by bit.
local BONUS_NAMES = {'slot 1 boost', 'slot 2 boost', 'slot 3 boost', 'slot 4 boost', 'Fire element', 'Ice element',
    'Thunder element', 'Holy element', 'Strength bonus', 'Magick bonus', 'Knockdown bonus', 'Slash Defense bonus', 'Strike Defense bonus'}
local function bonus_names(mask)
    local out = {}
    for i, n in ipairs(BONUS_NAMES) do if mask & (1 << (i - 1)) ~= 0 then out[#out + 1] = n end end
    if #out == 0 then out[1] = 'boost' end
    return out
end
-- Boosted gear the game no longer allows (made by 1.0.0 or 1.0.1) is offered a free repair before imbuing.
local function ask_repair(w)
    local bonus = w.ab[16] | w.ab[17] << 8 | w.ab[18] << 16 | w.ab[19] << 24
    if bonus == 0 or not CORE.ok then return false end
    local q, why = quote('repair', {w = w})
    if not q then
        if why and not why:find('already valid', 1, true) then event('repair_unavailable', {why = why}) end
        return false
    end
    local info = row_info(w)
    info.bonus_lost = bonus_names(q.plan.bonus_lost)
    local n = #info.bonus_lost
    ask('repair', "The game does not allow this gear's " ..table.concat(info.bonus_lost, ' and ') .. '. Your pawn may not appear in the rift. Remove '
        .. (n > 1 and 'them' or 'it') .. ' for free?' .. test_note(), info)
    return true
end
-- Fit and replace confirms. The price comes from the core; without it the default fee is shown.
local function ask_fit(r)
    local info = row_info(r.w)
    info.skill, info.skill_name, info.slot, info.replaces, info.material = r.skill, skill_name(r.skill), r.slot, r.replaces or 0, r.material
    local fee = fit_fee(r.w)
    local after = copy(r.w.ab)
    if r.slot then after[r.slot - 1] = r.skill end
    S.pending_fit = {w = r.w, after = after}
    info.work = work_done(r.w)
    if CORE.ok then
        local q, why = quote('fit', r)
        if not q then ask('info', why, info) return end
        fee = q.plan.fee
    end
    local what = r.replaces and ('Replace ' .. skill_name(r.replaces) .. ' with ' .. skill_name(r.skill) .. ' on ' .. info.name)
        or ('Imbue ' .. skill_name(r.skill) .. ' into ' .. info.name)
    info.fee, info.what = fee, what
    local lost = CORE.ok and CORE.c.quote and CORE.c.quote.plan.bonus_lost or 0
    local warn = ''
    if lost ~= 0 then
        info.bonus_lost = bonus_names(lost)
        warn = ' This removes the gear\'s ' .. table.concat(info.bonus_lost, ' and ') .. '. The game does not allow '
            .. (#info.bonus_lost > 1 and 'them' or 'it') .. ' after this change.'
    end
    ask('fit', (r.replaces and 'Confirm replace for ' or 'Confirm imbue for ') .. money(fee) .. ' G?' .. warn .. test_note(), info)
end
-- Keeps the checked rows; with none checked, the row the pulldown was opened on.
local function ask_dismantle(screen, w, fallback)
    local rows = checked(screen)
    S.session.keep_checked = math.max(S.session.keep_checked or 0, #rows)
    if #rows == 0 and fallback then rows = {fallback} end
    table.sort(rows, function(a, b) return a.pos < b.pos end)
    local keep, names = {}, {}
    for _, x in ipairs(rows) do keep[#keep + 1] = x.pos names[#names + 1] = skill_name(x.skill) end
    local info = row_info(w)
    info.keep, info.kept_names = keep, names
    if #keep == 0 then ask('info', 'Select the skills to keep first.', info) return end
    local fee = FEES.extraction * FEES.factors[#keep]
    if CORE.ok then
        local q, why = quote('dismantle', {w = w, keep = keep})
        if not q then ask('info', why, info) return end
        fee = q.plan.fee
    end
    info.fee, info.lost = fee, #(S.keeps or {}) - #keep
    info.keep_gear = FEES.keep_gear
    ask('dismantle', 'Confirm dismantle for ' .. money(fee) .. ' G?' .. (FEES.keep_gear and ' The gear is kept.' or '') .. test_note(), info)
end

-- Actions run from the armed screen's own update.
local function grid_state(screen)
    local g = screen:get_field('AppraisalItemGridPanel')
    if not g then return {} end
    local function get(m) if not m then return nil end local ok, v = pcall(m.call, m, g) if ok then return v end return 'error' end
    local st = {pulldown = get(B.pd_active), animating = get(B.animating), index = get(B.sel_index),
        flow = num(screen:get_field('CurrFlowId'))}
    if type(st.index) ~= 'string' then st.index = num(st.index) end
    return st
end
-- Results reveal animation: skipAnimation is re-sent like a held skip button until the reveal ends by itself.
-- endAnimation leaves the grid without input, so it runs only after ANIM_HARD seconds. Times are seconds, not frames.
local ANIM_RESKIP, ANIM_HARD = 0.25, 10
local function skip_anim(g, why, hard)
    local name = hard and 'endAnimation()' or 'skipAnimation()'
    local ok, e = pcall(function() g:call(name) end)
    S.anim_skips = (S.anim_skips or 0) + 1
    if S.session then S.session.anim_skips = S.anim_skips S.session.anim_hard = hard or S.session.anim_hard end
    local rec = {at = 'anim_skip', why = why, call = name, ok = ok, error = not ok and tostring(e) or nil, frame = S.frame, t = now()}
    -- After a forced end, the grid control's input and cursor are switched back on, as a finished reveal leaves them.
    if hard then
        local c = g:get_field('ItemGridCtrl')
        rec.before = c and {select = c:get_field('IsSelectEnable'), decide = c:get_field('IsDecideInputEnable')} or false
        rec.repaired = c ~= nil and pcall(function() c:call('setInputEnable(System.Boolean, System.Boolean)', true, true) c:call('dispCursor()') end)
        rec.after = c and {select = c:get_field('IsSelectEnable'), decide = c:get_field('IsDecideInputEnable')} or false
    end
    if why ~= 'held' or not ok then push(R.selection, rec) end
end
-- The results action button (Receive Selected) is relabelled by walking its panel's text nodes: Close, or on the
-- Dismantle skills step, Dismantle with the number of kept skills. The title board shows the menu and step.
local function panel_texts(root)
    local out, n = {}, 0
    local function walk(c, depth)
        while c and n < 300 and depth < 12 do
            n = n + 1
            local t = tname(c)
            if t == 'via.gui.Text' then out[#out + 1] = c end
            walk(call(c, 'get_Child()'), depth + 1)
            c = call(c, 'get_Next()')
        end
    end
    walk(call(root, 'get_Child()'), 0)
    return out
end
-- A text that refuses a message is left alone after 3 tries.
local function set_text(t, want)
    local a = addr(t)
    S.text_fail = S.text_fail or {}
    if (S.text_fail[a] or 0) >= 3 then return false end
    if text(call(t, 'get_Message()')) == want then return true end
    local ok = pcall(function() t:call('set_Message(System.String)', mstr(want)) end)
    ok = ok and text(call(t, 'get_Message()')) == want
    if not ok then S.text_fail[a] = (S.text_fail[a] or 0) + 1 event('text_refused', {want = want, tries = S.text_fail[a]}) end
    return ok
end
-- Storage view: the switcher reads Storage and its vocation icon (TexJob) is hidden; the entry above shows the
-- warehouse icon. updateName redraws both on each switch, so this runs every frame.
local function view_name(screen)
    local cc = screen:get_field('CharaChange')
    local tj = cc and cc:get_field('TexJob')
    local storage = S.view == 'storage'
    if tj and (storage or S.job_hidden) and call(tj, 'get_Visible()') == storage then
        local ok = pcall(function() tj:call('set_Visible(System.Boolean)', not storage) end)
        S.job_hidden = storage and ok
        if storage and S.session then S.session.job_hidden = ok end
    end
    if not storage then return end
    local t = cc and cc:get_field('TxtName')
    if t then S.session.view_named = set_text(t, 'Storage') end
end
local function title(screen)
    local tb = screen:get_field('TitleBoard')
    if not tb then return end
    local name, sub = tb:get_field('TxtName'), tb:get_field('TxtSubName')
    if not S.session.title_was then
        S.session.title_was = {name = name and text(call(name, 'get_Message()')) or false, sub = sub and text(call(sub, 'get_Message()')) or false}
    end
    local hint = HINTS[mode()][S.stage] or ''
    if S.stage == 3 and S.ex_only then hint = 'EX skill limit reached: choose an EX skill to replace' end
    if S.stage == 1 and S.filter then hint = hint .. ' (' .. S.filter.label .. ')' end
    if name then S.session.title = set_text(name, TITLES[mode()]) end
    if sub then S.session.hint = set_text(sub, hint) end
end
local function close_label(screen)
    if not S.close_texts then
        local ap = screen:get_field('ActionListPanel')
        local root = ap and ap:get_field('PnlRoot')
        S.close_texts = root and panel_texts(root) or {}
        S.session.close_texts = #S.close_texts
        local was = {}
        for _, t in ipairs(S.close_texts) do was[#was + 1] = text(call(t, 'get_Message()')) or false end
        S.session.close_was = was
    end
    local n = S.stage == 4 and kept(screen) or 0
    local want = S.stage ~= 4 and 'Close' or n == 0 and 'Dismantle (keep 0)'
        or ('Dismantle (keep ' .. n .. '): ' .. money(FEES.extraction * FEES.factors[n]) .. ' G')
    for _, t in ipairs(S.close_texts) do
        if set_text(t, want) then S.session.close_label = want end
    end
end
local function sort_open(screen)
    local g = screen:get_field('AppraisalItemGridPanel')
    return g ~= nil and (call(g, 'get_SortListActive()') == true
        or call(g:get_field('SortFilterUI') or g, 'get_IsOpenFilterGUI()') == true)
end
local function grid_busy(screen)
    local st = grid_state(screen)
    return st.pulldown == true or st.animating == true
end
-- The screen opens on the stock order view; it stays hidden until our results view shows.
local HIDE_MAX = 600
-- Both the view and the GUI object's drawing are switched (confirmed in game, probe1).
local function set_shown(o, v)
    local ok = pcall(function() o:get_field('Root'):call('set_Visible(System.Boolean)', v) end)
    local ok2 = pcall(function() o:get_field('CachedGUI'):call('get_GameObject()'):call('set_DrawSelf(System.Boolean)', v) end)
    S.hidden = not v and (ok or ok2) and S.frame or false
    event(v and 'shown' or 'hidden', {ok = ok, draw_ok = ok2})
end
local function act(screen, a)
    S.step = 'act ' .. a.kind
    if a.kind == 'enter' then
        S.rows, S.held, S.skipped = scan()
        S.session.rows = #S.rows
        S.session.skipped = S.skipped
        local fav = 0
        for _, r in ipairs(S.rows) do if r.favorite then fav = fav + 1 end end
        S.session.favorites = fav
        local h = 0
        for _ in pairs(S.held) do h = h + 1 end
        S.session.held_materials = h
        local full = 0
        for _, r in ipairs(S.rows) do if not r.equipped and not free_slot(r) then full = full + 1 end end
        S.session.full_weapons = full
        if #S.rows == 0 then event('no_rows', {}) set_shown(screen, true) return end
        if CORE.ok then S.session.core_refresh = refresh_core() end
        S.relabelled = relabel(screen:get_field('AppraisalItemGridPanel'))
        R.commands[#R.commands + 1] = S.relabelled
        set_labels(screen:get_field('AppraisalItemGridPanel'), 1)
        local okv, ev = pcall(setup_views, screen)
        if not okv then err('views', ev) S.view = 'player' end
        apply(screen, gear_rows(), 1)
        S.transit = {to = FLOW.fade_in_result, frames = 0, tries = {FLOW.fade_in_result, FLOW.display_result}, i = 1}
        B.transit:call(screen, FLOW.fade_in_result)
        push(R.transits, {to = FLOW.fade_in_result, from = num(screen:get_field('CurrFlowId')), auto = true})
    elseif a.kind == 'transit' then
        if a.anim and B.anim_request then
            local ac = screen:get_field('AnimCtrl')
            if ac then B.anim_request:call(ac, int(a.anim)) end
        end
        if a.next then screen:set_field('NextFlowId', int(a.to)) else B.transit:call(screen, int(a.to)) end
        push(R.transits, {to = a.to, anim = a.anim, next = a.next, from = num(screen:get_field('CurrFlowId')), auto = false})
        S.transit = {to = a.to, frames = 0, tries = {a.to}, i = 1}
    elseif a.kind == 'command' then
        local key = a.key
        local r = key and S.keymap[key]
        event('command', {stage = S.stage, cmd = a.cmd, key = key, item = r and r.item_id})
        push(R.selection, {at = 'action', stage = S.stage, command = a.cmd, key = key, matched = r ~= nil, via = a.via})
        if not r then event('action_without_row', {cmd = a.cmd, key = key}) return end
        if S.stage == 1 and a.cmd == CMD.first and blocked(r) then ask('info', blocked(r), row_info(r)) return end
        if S.stage == 1 and a.cmd == CMD.first and mode() == 'fit' and ask_repair(r) then return end
        if S.stage == 1 and a.cmd == CMD.first and mode() == 'fit' then
            local mats, filtered, simulated = materials(r)
            S.chosen, S.mats = r, mats
            push(R.selection, {at = 'materials', weapon = row_info(r), count = #mats, compat_filter = filtered, simulated = simulated})
            S.session.simulated = simulated
            if #mats == 0 then
                ask('none', 'None of your skill materials fit this ' .. (r.kind == 'armor' and 'armor' or 'weapon') .. '.', row_info(r))
                return
            end
            S.holder = holder_for(r)
            set_labels(screen:get_field('AppraisalItemGridPanel'), 2)
            apply(screen, mats, 2)
        elseif S.stage == 1 and a.cmd == CMD.first then
            local rows = keep_rows(r)
            if #rows == 0 then ask('info', 'This ' .. (r.kind == 'armor' and 'armor' or 'weapon') .. ' has no skills to keep.', row_info(r)) return end
            S.chosen, S.keeps = r, rows
            clear_checks(screen)
            set_labels(screen:get_field('AppraisalItemGridPanel'), 4)
            apply(screen, rows, 4)
        elseif S.stage == 2 and a.cmd == CMD.first then
            -- At the EX limit a free slot cannot take the skill, so an EX skill on the gear is offered for replacing.
            local full = false
            if r.slot and CORE.ok and is_ex(r.skill) then
                local q, why = quote('fit', r)
                full = not q and why == EX_FULL
            end
            if r.slot and not full then
                ask_fit(r)
            else
                local rows = replacements(r, full)
                if #rows == 0 then ask('info', EX_FULL, row_info(r.w)) return end
                S.material, S.ex_only = r, full
                set_labels(screen:get_field('AppraisalItemGridPanel'), 3)
                apply(screen, rows, 3)
            end
        elseif S.stage == 3 and a.cmd == CMD.first then
            ask_fit(r)
        elseif S.stage == 4 and a.cmd == CMD.first then
            ask_dismantle(screen, S.chosen, r)
        elseif a.cmd == CMD.second then
            act(screen, {kind = 'back'})
        end
    elseif a.kind == 'back' then
        local to = a.to or (S.stage == 3 and 2 or 1)
        if S.stage == 4 then clear_checks(screen) end
        set_labels(screen:get_field('AppraisalItemGridPanel'), to)
        if to == 2 then apply(screen, S.mats, 2)
        else apply(screen, gear_rows(), 1) S.holder = false end
    elseif a.kind == 'filter' then
        if a.id ~= S.filter_id then return end
        S.session.filters_used = (S.session.filters_used or 0) + 1
        event('filter', {id = a.id, label = S.filter and S.filter.label or 'none', stage = S.stage})
        if S.stage == 1 then apply(screen, gear_rows(), 1) end
    elseif a.kind == 'view' then
        if a.view ~= S.view then return end
        S.session.view_switches = (S.session.view_switches or 0) + 1
        if S.stage == 1 then apply(screen, gear_rows(), 1) end
    elseif a.kind == 'keep_tap' then
        if S.stage ~= 4 then return end
        local g = screen:get_field('AppraisalItemGridPanel')
        local info = call(g, 'get_SelectedInfo()')
        local key = info and num(B.info_key:call(info))
        if key ~= a.key then event('keep_tap_moved', {key = key, was = a.key}) return end
        if a.checked then ask_dismantle(screen, S.chosen) return end
        local ok, e = pcall(function() g:call('setCheckedGridInfo(System.Boolean)', true) end)
        local how = 'setCheckedGridInfo'
        if not (ok and call(info, 'get_IsChecked()') == true) then
            how = 'set_IsChecked'
            pcall(function() info:call('set_IsChecked(System.Boolean)', true) end)
        end
        S.session.keep_checked = math.max(S.session.keep_checked or 0, #checked(screen))
        event('keep_tap', {key = key, how = how, ok = call(info, 'get_IsChecked()') == true, error = not ok and tostring(e) or nil,
            list = num(call(g:get_field('CheckedSlotKeyList'), 'get_Count()'))})
    elseif a.kind == 'checked_action' then
        if S.stage == 4 then ask_dismantle(screen, S.chosen) else clear_checks(screen) end
    elseif a.kind == 'confirm_dismantle' then
        if S.stage == 4 and S.chosen then ask_dismantle(screen, S.chosen) end
    elseif a.kind == 'craft' then
        local ok, why = true, nil
        event('craft_start', {what = a.what})
        if CORE.ok and CORE.real then ok, why = craft(a.what) end
        event('craft_end', {what = a.what, ok = ok, why = why})
        if ok and a.what == 'fit' and S.pending_fit and CORE.ok and CORE.real then
            S.session.work_after = work_record(S.pending_fit.w)
            -- The fitted item goes to the top of the list, where the cursor starts.
            S.recent = {owner = S.pending_fit.w.owner, storage_id = S.pending_fit.w.storage_id}
        end
        S.pending_fit = false
        S.rows, S.held, S.skipped = scan()
        if S.stage == 4 then clear_checks(screen) end
        set_labels(screen:get_field('AppraisalItemGridPanel'), 1)
        apply(screen, gear_rows(), 1)
        S.holder, S.keeps = false, false
        if not ok then ask('info', why or 'Crafting stopped.', {kind = a.what}) else S.success_at = S.frame + 25 end
    elseif a.kind == 'exit' then
        apply(screen, {}, 1)
        event('exit_cleared', {})
        if a.cancel then
            -- Close with the screen's final fade-out, skipping its leftover-items menu and the order view.
            B.transit:call(screen, FLOW.fade_out)
            S.closing = {frames = 0, at_order = 0, route = 'fade_out'}
            push(R.transits, {to = FLOW.fade_out, from = num(screen:get_field('CurrFlowId')), auto = true, reason = 'close'})
        end
        S.session.cleared = true
    elseif a.kind == 'leave' then
        if S.stage > 0 then apply(screen, {}, 1) end
        S.session.left_mode = true
        S.left = true
        event('left_mode', {})
    end
end

local function mine(p) return S.screen and addr(managed(p) or {}) == S.screen end
local function armed(p) return S.session and not S.left and mine(p) end
local function trace(o)
    local f = num(o:get_field('CurrFlowId'))
    local nx = num(o:get_field('NextFlowId'))
    local ac = o:get_field('AnimCtrl')
    local sub = ac and num(ac:get_field('<CurrSubState>k__BackingField')) or false
    local k = tostring(f) .. '/' .. tostring(nx) .. '/' .. tostring(sub)
    if k ~= S.last_flow then
        S.last_flow = k
        push(R.flow_trace, {flow = f, next = nx, sub = sub, armed = S.session ~= false, stage = S.stage, frame = S.frame}, 600)
    end
    return f
end

-- Sounds. The appraisal reveal sound comes through the static GUIBase.callExSe(id) while our rows are put on the grid
-- (U8): those calls are dropped while we apply rows and for a few frames after. The first dropped ID is replayed after
-- a successful craft as its success sound (U7).
local SOUND = {logged = 0}
do
    local td = sdk.find_type_definition('app.GUIBase')
    for _, m in ipairs(td and td:get_methods() or {}) do
        local name = m:get_name()
        if name == 'callExSe' or name == 'callSe' or name == 'callPadSe' then
            local params = {}
            for _, t in ipairs(m:get_param_types() or {}) do params[#params + 1] = t:get_full_name() end
            local okst, st = pcall(m.is_static, m)
            st = okst and st == true
            local sig = name .. '(' .. table.concat(params, ',') .. ')'
            if st and sig == 'callExSe(System.UInt32)' then SOUND.play = m end
            pcall(sdk.hook, m, function(args)
                if SOUND.playing or not S.session or S.left then return end
                if not (S.applying or (S.mute_until and S.frame <= S.mute_until)) then return end
                local id = params[#params] == 'System.UInt32' and (sdk.to_int64(args[st and #params + 1 or #params + 2]) & 0xffffffff) or nil
                if id and not SOUND.id then SOUND.id = id end
                if SOUND.logged < 20 then
                    SOUND.logged = SOUND.logged + 1
                    event('se_muted', {m = sig, static = st, id = id, applying = S.applying or nil})
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end, function(ret) return ret end)
        end
    end
end
local function success_sound()
    if not (SOUND.play and SOUND.id) then event('se_success', {played = false, id = SOUND.id}) return end
    SOUND.playing = true
    local ok, e = pcall(SOUND.play.call, SOUND.play, nil, SOUND.id)
    SOUND.playing = false
    event('se_success', {played = ok, id = SOUND.id, error = not ok and tostring(e) or nil})
end

local arm
-- The per-frame step and its limits: seconds before a silent dialog lets go, and before the screen update takes over.
local TICK = {give_up = 60, stall = 0.5, gui = 0, seen = -1}
-- Screen lifetime and the update that carries every change.
-- The hook's argument table is not valid in post callbacks, so screen setup runs on the screen's first update.
local function start_screen(o)
    if S.screen == addr(o) then event('initialize_again', {session = S.session ~= false}) return end
    -- A Jiera pick made this frame arms before the screen takes it.
    if S.pick then
        local p = S.pick
        S.pick = false
        if not (S.armed and S.armed.mode == p.mode) then
            local ok, e = pcall(arm, p.mode, p.via)
            if not ok then err('arm', e) end
        end
    end
    S.screen, S.stage, S.keymap, S.queue, S.last_flow, S.left, S.entered = addr(o), 0, {}, {}, false, false, false
    S.recent, S.success_at = false, false
    S.closing, S.allow_actions, S.anim_frames, S.anim_skips, S.anim, S.close_texts = false, false, 0, 0, false, false
    S.text_fail, S.view_ids, S.storage_info, S.job_hidden = {}, nil, false, false
    S.filter, S.filter_id, S.filters = nil, nil, nil
    unswap()
    local g, c = o:get_field('AppraisalItemGridPanel'), o:get_field('SlotInfoListPanel')
    S.grid, S.compare = g and addr(g) or false, c and addr(c) or false
    if S.armed then
        S.session = {started = S.frame, pending = manager_pending(), before = counts('before'), shop = num(o:get_field('CurrentShopId')),
            mode = S.armed.mode, via = S.armed.via}
        S.armed = false
        CORE.epoch, CORE.active = CORE.epoch + 1, true
        set_shown(o, false)
        R.sessions[#R.sessions + 1] = S.session
        S.wait = 0
        event('session', {shop = S.session.shop, mode = S.session.mode, via = S.session.via})
    else
        S.session = false
        event('normal_screen', {})
    end
end
hook('Initialize', SCREEN, 'Initialize()', nil, function(a)
    local o = managed(a[2])
    if o and tname(o) == SCREEN then S.init = addr(o) event('initialize', {}) end
end)
hook('update', SCREEN, 'update()', nil, function(a)
    local o = managed(a[2])
    if not o then return end
    -- Last resort when neither per-frame source runs: the screen's own update keeps the menu alive.
    if now() - (S.last_tick or 0) > TICK.stall then TICK.run('screen') end
    if S.init and addr(o) == S.init then
        S.init = false
        start_screen(o)
    end
    if not (S.screen and addr(o) == S.screen) then return end
    if S.swap then unswap() event('unswapped', {}) end
    local f = trace(o)
    if S.hidden and (not S.session or S.left or S.closing or S.session.result_view or S.session.transit_failed
        or S.frame - S.hidden > HIDE_MAX) then set_shown(o, true) end
    if not S.session or S.left then return end
    if S.stage == 0 and not S.entered then
        S.wait = f == FLOW.display_order and (S.wait or 0) + 1 or 0
        if S.wait >= 10 then
            S.entered = true
            S.queue[#S.queue + 1] = {kind = 'enter'}
        end
    end
    if S.transit then
        S.transit.frames = S.transit.frames + 1
        if f == FLOW.display_result then
            S.session.result_view = true
            S.transit = false
        elseif S.transit.frames > 120 then
            local t = S.transit
            push(R.transits, {timeout = t.tries[t.i], flow = f})
            t.i = t.i + 1
            if t.tries[t.i] then
                t.frames = 0
                B.transit:call(o, int(t.tries[t.i]))
                push(R.transits, {to = t.tries[t.i], from = f, auto = true})
            else
                S.transit = false
                S.session.transit_failed = true
                event('transit_failed', {flow = f})
            end
        end
    end
    if S.stage > 0 and not S.closing and not S.allow_actions then
        local g = o:get_field('AppraisalItemGridPanel')
        local busy = g and call(g, 'get_IsAnimating()') == true
        if busy then
            local t = now()
            S.anim_frames = (S.anim_frames or 0) + 1
            S.session.anim_frames = S.anim_frames
            if not S.anim then
                S.anim = {start = t, reskip = t, hard = false}
                skip_anim(g, 'start')
            elseif not S.anim.hard and t - S.anim.start >= ANIM_HARD then
                S.anim.hard = true
                skip_anim(g, 'still running', true)
            elseif not S.anim.hard and t - S.anim.reskip >= ANIM_RESKIP then
                S.anim.reskip = t
                skip_anim(g, 'held')
            end
            if S.anim_frames <= 60 or S.anim_frames % 60 == 0 then
                local c = g:get_field('ItemGridCtrl')
                local it = c and call(c, 'get_SelectedItem()')
                push(R.selection, {at = 'anim', n = S.anim_frames, t = t - S.anim.start, target = num(g:get_field('AnimationTargetIndex')),
                    input = c and c:get_field('IsSelectEnable'), item_anim = it and call(it, 'get_Animating()'),
                    skipped = g:get_field('IsSkipped'), popup = g:get_field('IsSkippedNextPopupTarget'), active = num(g:get_field('ActiveItemCount'))})
            end
        elseif S.anim then
            S.session.anim_done_at = S.anim_frames
            S.session.anim_secs = now() - S.anim.start
            S.anim = false
        end
        local ok, e = pcall(close_label, o)
        if not ok then err('close label', e) end
        ok, e = pcall(title, o)
        if not ok then err('title', e) end
        if S.view_ids then ok, e = pcall(view_name, o) if not ok then err('view name', e) end end
        -- Pressing the action button heads for ExecAllItemAction. On the Dismantle skills step the screen is sent back
        -- to the results view and the dismantle confirm opens; elsewhere the button closes the screen.
        local nx = num(o:get_field('NextFlowId'))
        if S.tap_frame and S.frame - S.tap_frame <= 3 and nx == FLOW.select_action then
            o:set_field('NextFlowId', 0)
            event('select_action_cancelled', {after = S.frame - S.tap_frame})
            nx = 0
        end
        if S.stage ~= 4 and not S.dialog and #S.queue == 0 and not grid_busy(o) then
            local g = o:get_field('AppraisalItemGridPanel')
            local l = g and g:get_field('CheckedSlotKeyList')
            if l and (num(call(l, 'get_Count()')) or 0) > 0 then clear_checks(o) event('checks_cleared', {stage = S.stage}) end
        end
        if (nx == FLOW.exec_all or f == FLOW.exec_all) and #S.queue == 0 and not S.dialog then
            if S.stage == 4 then
                if f == FLOW.exec_all then B.transit:call(o, FLOW.display_result) else o:set_field('NextFlowId', FLOW.display_result) end
                event('dismantle_button', {flow = f, next = nx})
                S.queue[#S.queue + 1] = {kind = 'confirm_dismantle'}
            else
                S.session.closed_by_button = true
                event('close_button', {flow = f, next = nx})
                S.queue[#S.queue + 1] = {kind = 'exit', cancel = true}
            end
        end
    end
    if S.closing then
        local c, f = S.closing, num(o:get_field('CurrFlowId'))
        c.frames = c.frames + 1
        if f == FLOW.display_order then
            c.at_order = c.at_order + 1
            if c.at_order == 1 then B.transit:call(o, FLOW.fade_out) push(R.transits, {to = FLOW.fade_out, from = f, auto = true, reason = 'close'}) end
        elseif c.frames == 30 and c.route == 'fade_out' and f ~= FLOW.fade_out and f ~= FLOW['end'] then
            -- The direct fade-out did not take: use the results fade-out, then fade out from the order view.
            c.route, c.frames = 'fade_out_result', 0
            S.session.close_route = 'fade_out_result'
            B.transit:call(o, FLOW.fade_out_result)
            push(R.transits, {to = FLOW.fade_out_result, from = f, auto = true, reason = 'close'})
        elseif c.frames == 90 and f ~= FLOW.fade_out_result and f ~= FLOW.fade_out and f ~= FLOW['end'] then
            -- The fade-out did not start: fall back to the screen's own cancel.
            S.closing = false
            S.allow_actions = true
            S.session.close_fallback = true
            event('close_fallback', {flow = f})
            if B.onCancelItemGrid then
                S.allow_cancel = true
                local ok, e = pcall(B.onCancelItemGrid.call, B.onCancelItemGrid, o)
                S.allow_cancel = false
                if not ok then err('exit cancel', e) end
            end
        end
    end
    if S.pulldown and not S.pulldown.done and S.frame - S.pulldown.frame > 20 then
        S.pulldown.done = true
        if S.pulldown.cmd ~= CMD.cancel then S.queue[#S.queue + 1] = {kind = 'command', cmd = S.pulldown.cmd, key = S.pulldown.key, via = 'pulldown'} end
    end
    while #S.queue > 0 do
        local q = S.queue[1]
        -- Grid changes wait until the action menu has closed and the grid has stopped animating.
        if ((q.kind == 'command' or q.kind == 'back') and (q.waited or 0) < 90 and grid_busy(o))
            or (q.kind == 'filter' and (q.waited or 0) < 1800 and (grid_busy(o) or sort_open(o))) then
            q.waited = (q.waited or 0) + 1
            break
        end
        table.remove(S.queue, 1)
        local before = grid_state(o)
        before.waited = q.waited or 0
        local ok, e = pcall(act, o, q)
        if not ok then
            err('act ' .. q.kind .. ' at ' .. tostring(S.step), e)
            event('act_failed', {kind = q.kind, step = S.step, stage = S.stage, error = tostring(e), grid = before, after = grid_state(o)})
        elseif before.waited > 0 then
            push(R.selection, {at = 'waited', kind = q.kind, frames = before.waited})
        end
    end
end)
hook('onDestroy', SCREEN, 'onDestroy()', nil, function(a)
    if not mine(a[2]) then return end
    if S.session then
        S.session.destroyed = S.frame
        S.after_at = S.frame + 30
    end
    S.screen, S.grid, S.compare, S.stage, S.closing = false, false, false, 0, false
    CORE.active = false
    event('destroy', {})
end)

-- Result data: after the game's own apply on the armed screen's Result, the current step's rows replace it.
hook('applyResultInfo', RESULT, 'applyResultInfo(System.Collections.Generic.List`1<app.ItemAppraisalManager.ResultItemInfo>, System.Collections.Generic.List`1<System.Int32>)', nil, nil, function(_, a)
    if S.applying or not (a and S.session and not S.left and S.screen and S.lists and S.result) then return end
    local result = a.obj
    if not (result and addr(result) == S.result) then return end
    S.applying = true
    local ok, e = pcall(function()
        B.clear:call(result)
        B.applyResultInfo:call(result, S.lists[1], S.lists[2])
    end)
    S.applying = false
    if not ok then err('reapply', e) return end
    local keymap, n, unmatched = map_keys(result, S.cur_rows)
    S.keymap = keymap
    S.session.game_applies = (S.session.game_applies or 0) + 1
    event('game_apply_replaced', {slots = n, unmatched = unmatched})
end)
hook('clear', RESULT, 'clear()', nil, nil, function(_, a)
    if S.applying or not (a and S.session and not S.left and S.lists and S.result and S.cur_rows and #S.cur_rows > 0) then return end
    local result = a.obj
    if not (result and addr(result) == S.result) then return end
    S.applying = true
    local ok, e = pcall(B.applyResultInfo.call, B.applyResultInfo, result, S.lists[1], S.lists[2])
    S.applying = false
    if not ok then err('refill', e) return end
    S.keymap = map_keys(result, S.cur_rows)
    S.session.game_clears = (S.session.game_clears or 0) + 1
    event('game_clear_refilled', {})
end)
hook('setAppraisalItemInfo', GRID, 'setAppraisalItemInfo(app.GUIAppraisalResultData)', nil, function(a)
    if S.session and S.grid and addr(managed(a[2]) or {}) == S.grid and not S.applying then event('game_set_info', {}) end
end)

-- Commands.
hook('setCommandMsg', GRID, 'setCommandMsg(app.ui042001.ResultItemCommand, System.String)', nil, function(a)
    if not (S.session and not S.left and S.stage > 0 and S.grid and addr(managed(a[2]) or {}) == S.grid) then return end
    local label = label_for(S.stage, i32(a[3]))
    if label then
        a[4] = sdk.to_ptr(addr(mstr(label)))
        S.label_count = S.label_count + 1
    end
end)
hook('onSelectionChangedGrid', SCREEN, 'onSelectionChangedGrid(app.ui042001.AppraisalResultItemGridPanel.AppraisalItemGridInfo)', nil, function(a)
    if not armed(a[2]) then return end
    local i = managed(a[3])
    S.sel_key = i and num(B.info_key:call(i)) or false
    S.grid_logs = (S.grid_logs or 0) + 1
    if S.grid_logs <= 60 then log(R.selection, {at = 'grid', stage = S.stage, key = S.sel_key, matched = S.sel_key ~= false and S.keymap[S.sel_key] ~= nil}) end
end)
hook('onSelectPullDownAction', SCREEN, 'onSelectPullDownAction(app.ui042001.ResultItemCommand)', nil, function(a)
    if not (armed(a[2]) and S.stage > 0) then return end
    local cmd = i32(a[3])
    S.pulldown = {cmd = cmd, sent = cmd, key = S.sel_key, frame = S.frame}
    -- Take (command 0) makes the game check inventory space after executeCommand is skipped and show "Maximum capacity reached".
    -- The game is given command 1 instead, whose route returns to the results view; our action still uses the chosen command.
    -- Material rows have no command 1, so for them the game is given Cancel; the 20-frame fallback then runs our action.
    if cmd == CMD.first then
        S.pulldown.sent = is_mat(S.sel_key and S.keymap[S.sel_key]) and CMD.cancel or CMD.second
        a[3] = sdk.to_ptr(S.pulldown.sent)
    end
    push(R.selection, {at = 'pulldown', stage = S.stage, command = cmd, sent = S.pulldown.sent, key = S.sel_key})
end)
hook('executeCommand', SCREEN, 'executeCommand(app.ui042001.ResultItemCommand, System.Boolean, System.Int32)', function(a)
    if not armed(a[2]) then return false end
    return S.stage > 0 and next(S.keymap) ~= nil
end, function(a, skip)
    if not armed(a[2]) then return end
    local cmd = i32(a[3])
    push(R.selection, {at = 'executeCommand', stage = S.stage, command = cmd, skipped = skip})
    local p = S.pulldown
    if skip and p and p.sent == cmd and S.frame - p.frame < 600 then
        if not p.done and p.cmd ~= CMD.cancel then S.queue[#S.queue + 1] = {kind = 'command', cmd = p.cmd, key = p.key, via = 'executeCommand'} end
        p.done = true
    elseif skip then
        S.queue[#S.queue + 1] = {kind = 'exit', cancel = false}
        event('exit_by_command', {cmd = cmd})
    end
end)
hook('onCancelItemGrid', SCREEN, 'onCancelItemGrid()', function(a)
    return armed(a[2]) and not S.allow_cancel and (S.stage >= 2 or S.stage == 1 and next(S.keymap) ~= nil)
end, function(a, skip)
    if not skip then return end
    if S.stage >= 2 then S.queue[#S.queue + 1] = {kind = 'back'}
    else S.queue[#S.queue + 1] = {kind = 'exit', cancel = true} end
end)
-- The results action button (Receive Selected) becomes Close, which closes the screen like Back on the gear list.
hook('onSelectAction', SCREEN, 'onSelectAction(app.ui042001.ResultItemCommand)', function(a)
    return armed(a[2]) and S.stage > 0 and not S.allow_actions
end, function(a, skip)
    if not armed(a[2]) then return end
    push(R.selection, {at = 'onSelectAction', stage = S.stage, command = i32(a[3]), skipped = skip})
    if skip and not S.closing and S.stage == 4 then
        S.queue[#S.queue + 1] = {kind = 'confirm_dismantle'}
    elseif skip and not S.closing then
        S.session.closed_by_button = true
        S.queue[#S.queue + 1] = {kind = 'exit', cancel = true}
    end
end)

-- The stock screen's own switcher setup, for its Boolean.
hook('cc_setup', 'app.GUIBase.CharaChangeRef', 'setup(app.CharacterID[], System.Int32, System.Boolean)', nil, function(a)
    if not S.session then local ok, v = pcall(sdk.to_int64, a[5]) if ok then S.cc_flag = (v & 1) == 1 end end
end)
-- Whenever the switcher redraws the Storage entry, it is drawn as the warehouse.
hook('cc_draw', CC_ITEM, 'updateDisp(app.GUIBase.CharaChangeRef.ListInfo)', nil, function(a)
    if not S.storage_info or S.swap then return end
    local info = managed(a[3])
    if info and addr(info) == S.storage_info and swap(info) and S.session then S.session.storage_draws = (S.session.storage_draws or 0) + 1 end
end, function() unswap() end)
-- Grid rows: no price under our rows. Skipping a row's startResultEffect left the grid animating with no input (v21).
local GRID_ITEM = GRID .. '.AppraisalItemGridItem'
local function our_item(it)
    local par = it and it:get_field('Parent')
    return S.session and not S.left and (S.stage > 0 or S.applying) and par and addr(par) == S.screen and it or nil
end
-- Before a row is drawn: it is already revealed with no reveal panels (to keep the reveal quiet). The "can't equip"
-- mark only shows on gear rows that cannot be picked (equipped, or a favorite in Dismantle); the stock vocation and
-- pawn marks are cleared.
hook('row_draw', GRID_ITEM, 'updateDisp(' .. GRID .. '.AppraisalItemGridInfo)', nil, function(a)
    if not our_item(managed(a[2])) then return end
    local info = managed(a[3])
    if not info then return end
    pcall(function()
        info:call('set_IsEndedAnimation(System.Boolean)', true)
        info:call('set_IsDispAnimPanels(System.Boolean)', false)
    end)
    if S.applying and S.draw_logged ~= S.apply_stage then
        S.draw_logged = S.apply_stage
        event('first_row_draw', {stage = S.apply_stage})
    end
    local key = (S.applying and S.apply_stage or S.stage) == 1 and num(B.info_key:call(info))
    -- While rows are applied the new keys are in draw_map; later redraws use the live keymap.
    local no = key and blocked(((S.applying and S.draw_map or S.keymap) or {})[key]) and true or false
    if pcall(function()
        info:call('set_IsEnableEquip(System.Boolean)', not no)
        info:call('set_IsDisableEquipOfficialPawn(System.Boolean)', false)
        info:call('set_IsDisableEquipSubPawn(System.Boolean)', false)
    end) and no then S.session.marked = (S.session.marked or 0) + 1 end
end, function(_, last)
    local it = our_item(last.obj)
    local icon = it and it:get_field('ItemIcon')
    local pnl = icon and icon:get_field('PnlPrice')
    if pnl and pcall(function() pnl:call('set_Visible(System.Boolean)', false) end) then S.session.prices_hidden = (S.session.prices_hidden or 0) + 1 end
end)
-- Skill detail: the screen's ability info shows the movie panel for weapon skills only. For a passive (no display
-- entry of its own) the small title and description panel is shown instead.
local EQ_INFO = SCREEN .. '.EquipmentAbilityInfo'
local function msg(t) local v = t and call(t, 'get_Message()') return v and tostring(v) or nil end
hook('ability_info', EQ_INFO, 'setInfo(app.EquipmentAbilityID, System.Boolean)', nil, nil, function(_, last)
    local o, id, flag = last.obj, last[3] & 0xFFFFFFFF, (last[4] & 0xFF) ~= 0
    if not (o and S.session and not S.left) then return end
    local small, detail = o:get_field('AbilityInfo'), o:get_field('DetailInfoPanel')
    local list, own = o:get_field('CurrDisplayInfo'), false
    local okn, n = pcall(function() return list:get_size() end)
    n = okn and n or 0
    for i = 0, n - 1 do
        local okd, d = pcall(function() return list:get_element(i) end)
        if okd and d and num(call(d, 'get_AbilityId()')) == id then own = true end
    end
    local rec = {at = 'ability_info', id = id, flag = flag, entries = n, own = own,
        small = small and call(small, 'get_Visible()'), detail = detail and call(detail, 'get_Visible()'),
        text = small and msg(small:get_field('TxtDescription'))}
    if small and not own and id ~= 0 and rec.small ~= true then
        rec.shown = pcall(function()
            small:call('setInfo(app.EquipmentAbilityID, System.Boolean)', id, flag)
            small:call('set_Visible(System.Boolean)', true)
        end)
        rec.text_after = msg(small:get_field('TxtDescription'))
        if rec.shown then S.session.passive_info = (S.session.passive_info or 0) + 1 end
    end
    push(R.selection, rec)
end)
-- LT/RT: the switcher moved; the list follows it instead of the game's equip preview for that character.
hook('selectionChangedResultCharacter', SCREEN, 'selectionChangedResultCharacter()', function(a)
    return armed(a[2]) and S.stage > 0 and S.view_ids ~= nil
end, function(a, skip)
    if not skip then return end
    local o = managed(a[2])
    local cc = o and o:get_field('CharaChange')
    local v, i = tab_view(cc)
    event('view_switch', {index = i, view = v or false, stage = S.stage})
    if v and v ~= S.view then
        S.view = v
        S.queue[#S.queue + 1] = {kind = 'view', view = v}
    end
end)
-- Step 4: A on a skill keeps it instead of opening the command list; A on a kept skill opens the confirm.
SKIP_RET.setupPullDown = sdk.to_ptr(0)
hook('setupPullDown', GRID, 'setupPullDown()', function(a)
    return S.session ~= false and not S.left and S.stage == 4 and S.grid ~= false and addr(managed(a[2]) or {}) == S.grid
end, function(a, skip)
    if not skip then return end
    local g = managed(a[2])
    local info = call(g, 'get_SelectedInfo()')
    if not info then return end
    S.tap_frame = S.frame
    S.queue[#S.queue + 1] = {kind = 'keep_tap', key = num(B.info_key:call(info)), checked = call(info, 'get_IsChecked()') == true}
end)
-- G panel Sort list: the gear-type filters are added below the game's sorts on the gear step.
local SORT_INFO = 'app.ui01360601.MainControlPanel.Sort.ListInfo'
B.sort_info_ctor = bind(SORT_INFO, '.ctor()')
B.msg_ctor = bind('app.GUIMessageData', '.ctor(System.String)')
B.sort_list_insert = by_name('System.Collections.Generic.List`1<' .. SORT_INFO .. '>', 'Insert', 2)
local function our_sort_ui(ui)
    if not (ui and S.session and not S.left and S.grid) then return false end
    local g = managed(S.grid)
    local mine_ui = g and g:get_field('SortFilterUI')
    return mine_ui ~= nil and addr(mine_ui) == addr(ui)
end
hook('sort_setup', 'app.ui01360601', 'setupSort(System.Collections.Generic.List`1<' .. SORT_INFO .. '>, System.Int32)', nil, function(a)
    local ui, list = managed(a[2]), managed(a[3])
    local stage = S.applying and S.apply_stage or S.stage
    if not (list and stage == 1 and our_sort_ui(ui)) then return end
    if not (B.sort_info_ctor and B.msg_ctor and B.sort_list_insert) then return end
    local n = num(call(list, 'get_Count()')) or 0
    for i = 0, n - 1 do
        local li = call(list, 'get_Item(System.Int32)', int(i))
        if li and (num(call(li, 'get_SortId()')) or 0) > FILTER_BASE then return end
    end
    S.filters = filter_list()
    -- Our rows go right under the first sort (Optimized); the selected index moves down past them.
    local at = math.min(1, n)
    local sel = sdk.to_int64(a[4]) & 0xFFFFFFFF
    if sel >= at and sel < n then a[4] = sdk.to_ptr(sel + #S.filters) end
    for k, f in ipairs(S.filters) do
        local li = sdk.create_instance(SORT_INFO, true)
        li = li:add_ref() or li
        B.sort_info_ctor:call(li)
        local m = sdk.create_instance('app.GUIMessageData', true)
        m = m:add_ref() or m
        B.msg_ctor:call(m, mstr(f.label))
        li:call('set_SortId(System.Int32)', int(f.id))
        li:call('set_LabelMessage(app.GUIMessageData)', m)
        B.sort_list_insert:call(list, int(at + k - 1), li)
        S.keep[#S.keep + 1], S.keep[#S.keep + 2] = li, m
    end
    S.session.filter_rows = #S.filters
    event('filters_added', {count = #S.filters, before = n, at = at, selected = sel})
end)
-- The list draws labels from message ids only, so our rows get their text directly.
hook('sort_row', 'app.ui01360601.MainControlPanel.Sort.ListItem', 'updateDisp(' .. SORT_INFO .. ')', nil, nil, function(_, last)
    local info = managed(last[3])
    local id = info and num(call(info, 'get_SortId()')) or 0
    if id <= FILTER_BASE then return end
    local t = last.obj and last.obj:get_field('TxtLabel')
    for _, f in ipairs(FILTERS) do
        if f.id == id and t then t:call('set_Message(System.String)', mstr(f.label)) end
    end
end)
-- Picking one of our filters applies it instead of the game's sort.
hook('sort_pick', GRID, 'onSelectedSortID(System.Int32, System.String)', function(a)
    if not (S.session and not S.left and S.grid and addr(managed(a[2]) or {}) == S.grid) then return false end
    return (sdk.to_int64(a[3]) & 0xFFFFFFFF) > FILTER_BASE
end, function(a, skip)
    if not skip then return end
    local id = sdk.to_int64(a[3]) & 0xFFFFFFFF
    local f = nil
    for _, v in ipairs(S.filters or {}) do if v.id == id then f = v end end
    if id == S.filter_id then id, f = FILTER_BASE, nil end
    S.filter_id, S.filter = id, f
    S.queue[#S.queue + 1] = {kind = 'filter', id = id}
end)
-- The game's own action dialog for checked items: on step 4 it opens the dismantle confirm, elsewhere checks are cleared.
hook('onRequestedCheckedItemAction', SCREEN, 'onRequestedCheckedItemAction()', function(a)
    return armed(a[2]) and S.stage > 0
end, function(a, skip)
    if skip then S.queue[#S.queue + 1] = {kind = 'checked_action'} end
end)

-- Blocked on the armed screen: anything that moves, equips or appraises items.
for role, sig in pairs({reserveItem = 'reserveItem(app.GUIAppraisalResultData.ResultSlot, app.CharacterID, System.Int32)',
    executeEquip = 'executeEquip()', swapArisenEquip = 'swapArisenEquip()', onExecArisenEquipChange = 'onExecArisenEquipChange(System.Int32)',
    onDecideArisenEquipChangeList = 'onDecideArisenEquipChangeList(System.Int32)', successAppraisalAction = 'successAppraisalAction()'}) do
    hook(role, SCREEN, sig, function(a) return S.session ~= false and mine(a[2]) end)
end
for role, sig in pairs({executeAppraisal = 'executeAppraisal()', addAppraisalItem = 'addAppraisalItem(app.ItemIDEnum, app.Character.JobEnum, app.CharacterID)',
    removeAppraisalItem = 'removeAppraisalItem(app.ItemIDEnum)', cancelAppraisal = 'cancelAppraisal()', clearResult = 'clearResult()'}) do
    hook('manager.' .. role, MANAGER, sig, function() return S.session ~= false and S.screen ~= false end)
end
-- Input gate while our dialog is open.
for role, sig in pairs({updateInputDisplayResult = 'updateInputDisplayResult()', updateInputSelectAction = 'updateInputSelectAction()'}) do
    hook(role, SCREEN, sig, function(a) return (S.dialog ~= false or S.frame < (S.gate_until or 0)) and armed(a[2]) end)
end

-- Compare panel: on step 2 the equipped side shows the weapon as it is now.
local function decode(p)
    if not plausible(p) then return nil end
    local v = sdk.to_valuetype(p, 'app.ItemDefine.StorageData')
    local ab = {}
    for k = 0, 19 do ab[k] = v:read_byte(40 + k) end
    return {item_id = v:read_short(32), ab = ab, storage_id = v:read_dword(20)}
end
hook('compare.setup', COMPARE, 'setup(app.ItemDefine.StorageData, app.ItemDefine.StorageData)', nil, function(a)
    if not (S.session and not S.left and S.compare and addr(managed(a[2]) or {}) == S.compare) then return end
    local x, y = decode(pointer(a[3])), decode(pointer(a[4]))
    local e = {stage = S.stage, a = x and {item = x.item_id, slots = slots(x.ab), sid = x.storage_id} or false,
        b = y and {item = y.item_id, slots = slots(y.ab), sid = y.storage_id} or false, key = S.sel_key}
    local r = S.sel_key and S.keymap[S.sel_key]
    if r then
        local ma = x and x.item_id == r.item_id and same(x.ab, r.ab)
        local mb = y and y.item_id == r.item_id and same(y.ab, r.ab)
        e.selected_is = ma and not mb and 'a' or mb and not ma and 'b' or (ma and 'both' or 'neither')
        if S.stage == 3 and S.holder and plausible(S.holder) then
            if e.selected_is == 'b' then a[3] = sdk.to_ptr(S.holder) e.substituted = 'a'
            elseif e.selected_is == 'a' then a[4] = sdk.to_ptr(S.holder) e.substituted = 'b' end
            if e.substituted then S.subs = (S.subs or 0) + 1 end
        elseif S.stage == 2 and r.material and S.holder and plausible(S.holder) then
            -- A material row: before is the weapon now, after is the weapon with the skill in its free slot.
            a[3] = sdk.to_ptr(S.holder)
            e.substituted = 'a'
            if r.after then
                r.after_holder = r.after_holder or holder_for({item_id = r.w.item_id, ab = r.after, source = r.w.source})
                if r.after_holder and plausible(r.after_holder) then a[4] = sdk.to_ptr(r.after_holder) e.substituted = 'both' end
            end
            S.subs2 = (S.subs2 or 0) + 1
        end
    end
    log(R.compare, e)
end)

-- Dialog answer, read only.
local function poll_dialog()
    local d = S.dialog
    if not d then return end
    local gm = sdk.get_managed_singleton('app.GuiManager')
    local v = gm and B.dialog_state and num(B.dialog_state:call(gm))
    if v ~= d.last then
        d.last = v
        d.values[#d.values + 1] = {frame = S.frame, value = v}
        S.dirty = true
        if v ~= 0 and d.answer == nil then d.answer = v d.answered_at = S.frame end
    end
    d.frames = (d.frames or 0) + 1
    d.t0 = d.t0 or now()
    if d.answer ~= nil and (v == 0 or S.frame - d.answered_at > 30) then
        d.yes = d.answer == DIALOG_YES
        S.dialog = false
        S.gate_until = S.frame + 10
        event('dialog_answer', {kind = d.kind, value = d.answer})
        if (d.kind == 'fit' or d.kind == 'dismantle' or d.kind == 'repair') and d.yes then S.queue[#S.queue + 1] = {kind = 'craft', what = d.kind} end
    elseif now() - d.t0 > TICK.give_up then
        d.result = 'stopped polling after ' .. TICK.give_up .. ' seconds'
        S.dialog = false
        event('dialog_given_up', {kind = d.kind})
    end
end

local function write(force)
    if not DEBUG and force ~= 'manual' then return end
    if not (S.dirty or force) then return end
    if not force and now() - S.last_write < 2 then return end
    R.written, R.label_substitutions = now(), S.label_count
    if DIALOGUE.ok then R.dialogue.state = DIALOGUE.d:report() end
    R.strings_made = S.strings
    if CORE.ok then
        R.core.locked, R.core.lock_reason, R.core.status = CORE.c.coordinator.locked, CORE.c.coordinator.reason or nil, CORE.c.status
        R.core.real, R.core.build = CORE.real, build_info()
    end
    local ok, e = pcall(json.dump_file, OUT, R)
    if not ok then err('write', e) end
    S.write_ok = ok and e ~= false
    S.dirty, S.last_write = false, now()
end

-- One menu step per game frame. UpdateGUI drives it; on_frame and the screen's update stand in if it stops.
function TICK.run(src)
    S.frame = S.frame + 1
    S.last_tick = now()
    if src ~= S.tick_src then
        S.tick_src = src
        push(R.tick_sources, {src = src, frame = S.frame, t = S.last_tick}, 40)
    end
    if S.success_at and S.frame >= S.success_at then
        S.success_at = false
        pcall(success_sound)
    end
    local ok, e = pcall(poll_dialog)
    if not ok then err('poll', e) S.dialog = false end
    if S.after_at and S.frame >= S.after_at then
        S.after_at = false
        local s = S.session
        local ok2, e2 = pcall(function()
            local c = counts('after')
            s.after = c
            s.unchanged = c.gold == s.before.gold and c.player == s.before.player and c.main_pawn == s.before.main_pawn and c.storage == s.before.storage
        end)
        if not ok2 then err('after counts', e2) end
        S.session, S.entered, S.transit, S.dialog, S.pulldown = false, false, false, false, false
        write(true)
    end
    if S.pick then
        local p = S.pick
        S.pick = false
        if not (S.armed and S.armed.mode == p.mode) then
            local ok4, e4 = pcall(arm, p.mode, p.via)
            if not ok4 then err('arm', e4) end
        end
    end
    if DIALOGUE.ok then
        local ok3, e3 = pcall(DIALOGUE.d.step, DIALOGUE.d)
        if not ok3 then err('dialogue', e3) end
    end
    write(false)
end
re.on_pre_application_entry('UpdateGUI', function()
    TICK.gui = TICK.gui + 1
    TICK.run('gui')
end)
re.on_frame(function()
    if TICK.gui ~= TICK.seen then TICK.seen = TICK.gui return end
    TICK.run('frame')
end)

-- Arms the next appraisal screen as the Fit or Dismantle menu.
function arm(m, via)
    local p = manager_pending()
    R.manager[#R.manager + 1] = {frame = S.frame, pending = p, mode = m, via = via}
    local fail
    if #R.missing > 0 then fail = 'Cannot arm: bindings missing.'
    elseif not p.available then fail = 'Cannot arm: load a save first.'
    -- Material rows of unregistered items crash the grid, so the menus stay closed until registration worked.
    elseif not ITEMS.ok then fail = 'Cannot open Spoils Engraving: skill materials are not loaded (' .. tostring(ITEMS.error or 'pending') .. ').'
    elseif p.results ~= 0 or p.temps ~= 0 then fail = 'Cannot open Spoils Engraving: take your pending appraisal from Jiera first.'
    elseif S.screen then fail = 'Cannot arm while the appraisal screen is open.' end
    if fail then S.arm_msg = fail event('arm_refused', {mode = m, via = via, reason = fail}) return false end
    ensure_core()
    S.armed, S.arm_msg = {mode = m, via = via}, false
    event('armed', {mode = m, via = via})
    write(true)
    return true
end

-- Jiera's dialogue option. Its modules are registered at load, like the core's.
do
    local dirs = {}
    for i = 1, #CORE_DIRS do dirs[i] = (CORE_DIRS[i]:gsub('spoils_engraving([\\/])$', 'spoils_engraving_menu%1')) end
    local ok, e = pcall(function()
        local mods = {}
        for _, m in ipairs({'dialogue', 'branches'}) do
            local chunk, why
            for _, d in ipairs(dirs) do
                chunk, why = loadfile(d .. m .. '.lua')
                if chunk then break end
            end
            mods[m] = assert(chunk, m .. ': ' .. tostring(why))()
        end
        -- The optional Guild Contracts patch is one settings file; without it nothing changes.
        for _, d in ipairs(dirs) do
            local chunk, why = loadfile(d .. 'compat_guild_contracts.lua')
            if chunk then
                local okc, opts = pcall(chunk)
                if okc and type(opts) == 'table' then DIALOGUE.compat = opts else DIALOGUE.compat_error = tostring(opts) end
                break
            elseif why and not tostring(why):find('cannot open', 1, true) then DIALOGUE.compat_error = tostring(why) break end
        end
        DIALOGUE.d = mods.dialogue.new(sdk, mods.branches, function(key, hex, where)
            -- Arming runs on the next frame, outside the dialogue's own call.
            if key == 'fit' or key == 'dismantle' then
                S.pick = {mode = key, via = 'jiera ' .. where}
            elseif key == false and S.armed and S.armed.via ~= 'imgui' then
                -- A stock choice (Appraise and the rest) cancels a dialogue arm that was not used.
                S.armed, S.pick = false, false
                event('disarmed', {hex = hex})
            end
            S.dirty = true
        end, DIALOGUE.compat)
        DIALOGUE.ok = true
    end)
    DIALOGUE.error = not ok and tostring(e) or false
    R.dialogue = {ok = DIALOGUE.ok, error = DIALOGUE.error or nil, dirs = dirs,
        compat = DIALOGUE.compat and (DIALOGUE.compat.name or true) or nil, compat_error = DIALOGUE.compat_error}
end

local items_notice = true
re.on_frame(function()
    if not (items_notice and (ITEMS.error or #ITEMS.conflicts > 0)) then return end
    local open = imgui.begin_window('Spoils Engraving', true, 64)
    imgui.text(ITEMS.error and 'Spoils Engraving could not add its skill materials. Do not save: held materials may be lost.'
        or #ITEMS.conflicts .. ' skill material IDs are taken by another mod. Those materials will not work.')
    if imgui.button('OK') or open == false then items_notice = false end
    imgui.end_window()
end)

re.on_draw_ui(function()
    if not imgui.tree_node('Spoils Engraving') then return end
    imgui.text(VERSION)
    if ITEMS.error then imgui.text('Skill materials failed to load: ' .. tostring(ITEMS.error)) end
    if #ITEMS.conflicts > 0 then imgui.text(#ITEMS.conflicts .. ' skill material IDs are taken by another mod.') end
    if imgui.tree_node('Settings') then
        local changed = false
        local c, v = imgui.drag_int('Dismantle, per kept skill (x1, x3, x6, x10)', FEES.extraction, 1000, 1, FEE_MAX)
        if c and fee_ok(math.tointeger(v)) then FEES.extraction, changed = math.tointeger(v), true end
        local names = {'1st imbue or replace on an item', '2nd', '3rd', '4th and later'}
        for i = 1, #LADDER do
            c, v = imgui.drag_int(names[i], LADDER[i], 1000, 1, FEE_MAX)
            if c and fee_ok(math.tointeger(v)) then LADDER[i], changed = math.tointeger(v), true end
        end
        c, v = imgui.checkbox('Dismantling keeps the gear', FEES.keep_gear)
        if c and type(v) == 'boolean' then FEES.keep_gear, changed = v, true end
        -- Presets scale the standard fees; Free charges 1 G because a fee of 0 is refused.
        for _, p in ipairs({{'Standard', 1}, {'Cheap', 0.1}, {'Hardcore', 3}, {'Free', 0}}) do
            if imgui.button(p[1]) then
                local function f(n) return math.max(1, math.tointeger(n * p[2] // 1) or 1) end
                FEES.extraction, LADDER[1], LADDER[2], LADDER[3], LADDER[4], changed = f(20000), f(10000), f(50000), f(150000), f(500000), true
            end
            imgui.same_line()
        end
        imgui.text('fee presets')
        if changed then S.settings_saved = save_settings() end
        if S.settings_saved == false then imgui.text('The fee settings could not be saved.') end
        imgui.tree_pop()
    end
    if #R.missing > 0 then imgui.text('This game version is not supported: ' .. #R.missing .. ' game functions not found.') end
    if not DIALOGUE.ok then imgui.text('Jiera\'s option failed to load: ' .. tostring(DIALOGUE.error)) end
    if DIALOGUE.compat then imgui.text('Guild Contracts patch is active.') end
    if DIALOGUE.compat_error then imgui.text('Guild Contracts patch failed to load: ' .. DIALOGUE.compat_error) end
    if S.arm_msg and not S.session then imgui.text(S.arm_msg) end
    if CORE.ok then
        local b = CORE.native.build
        if CORE.c.coordinator.locked then
            imgui.text('CRAFTING LOCKED: ' .. tostring(CORE.c.coordinator.reason))
            if imgui.button('Diagnose the interrupted crafting') then
                local ok, e = pcall(CORE.c.diagnose, CORE.c)
                R.core.events[#R.core.events + 1] = {kind = 'diagnose', ok = ok, error = not ok and tostring(e) or nil, diagnosis = CORE.c.diagnosis or nil}
                S.dirty = true
            end
            if imgui.button('Acknowledge and unlock') then
                local ok, e = pcall(CORE.c.acknowledge, CORE.c)
                R.core.events[#R.core.events + 1] = {kind = 'acknowledge', ok = ok, error = not ok and tostring(e) or nil}
                S.dirty = true
            end
        elseif not CORE.real or ALLOW_VERSION then
            imgui.text_colored('TEST RUN ONLY: Version mismatch. Confirmations make no changes.', 0xFF00FFFF)
            local changed, value = imgui.checkbox('Allow crafting on this game version', ALLOW_VERSION)
            if changed and type(value) == 'boolean' then
                S.real_msg = false
                ALLOW_VERSION = value
                local ok, e = pcall(value and allow_real or disallow_real)
                if not ok then
                    ALLOW_VERSION = not value
                    S.real_msg = tostring(e)
                else
                    S.settings_saved = save_settings()
                end
            end
            if S.real_msg then imgui.text(S.real_msg) end
            if S.settings_saved == false then imgui.text('The version setting could not be saved.') end
        end
    elseif CORE.error then
        imgui.text('Crafting failed to load: ' .. CORE.error)
    elseif R.core.files ~= true then
        imgui.text('Mod files missing: ' .. tostring(R.core.files))
    end
    if imgui.tree_node('Troubleshooting') then
        local errs = 0
        for _ in pairs(R.errors) do errs = errs + 1 end
        imgui.text('Script errors: ' .. errs)
        if imgui.button('Write diagnostic report') then write('manual') end
        if S.write_ok then imgui.text('Written to reframework/data/' .. OUT) end
        imgui.tree_pop()
    end
    imgui.tree_pop()
end)

re.on_script_reset(function() write(true) end)
if DEBUG then write(true) end
