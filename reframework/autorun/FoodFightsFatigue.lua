local config = json.load_file("FoodFightsFatigue_config.json") or {}
if config.base == nil then config.base = 20 end
if config.foodmult == nil then config.foodmult = 0.1 end
if config.driedmult == nil then config.driedmult = 0.2 end
if config.roborantmult == nil then config.roborantmult = 0.05 end

local foodtable = {[1]=1,[2]=1,[4]=1,[5]=1,[7]=1,[8]=1,[10]=1,[11]=1,[13]=1,[14]=1,[16]=1,[17]=1,[19]=1,[20]=1,[22]=1,[23]=1,[25]=1,[26]=1,[28]=1,[29]=1,[31]=1,[32]=1,[34]=1,[35]=1,[49]=1,[50]=1,[52]=1,[53]=1,[185]=1,[505]=1,[510]=1,[37]=2,[41]=2,[45]=2,[55]=2,[114]=2,[115]=2,[116]=2,[501]=2,[38]=3,[39]=3,[42]=3,[43]=3,[46]=3,[47]=3,[56]=3,[57]=3,[502]=3,[503]=3,[504]=3}
-- 1. Food
-- 2. Dried Food
-- 3. Roborant

local useEffect = sdk.find_type_definition("app.ItemUseEffect")
local healEffect = useEffect:get_field("Heal"):get_data(nil)
local staminaEffect = useEffect:get_field("RecoverStamina"):get_data(nil)
local originals = {}

local function apply_item(item, category)
	local original = originals[item._Id]
	if original == nil then
		original = {
			item = item,
			whiteHp = item._HealWhiteHp,
			blackHp = item._HealBlackHp,
			useEffect = item._UseEffect,
		}
		originals[item._Id] = original
	end
	item._HealWhiteHp = original.whiteHp
	if category == 1 then -- BlackHpGain = base + itemHP * foodmult | WhiteHPGain = 0 | TotalHPGain = base + itemHP * foodmult
		item._HealBlackHp = config.base + item._HealWhiteHp * config.foodmult
		item._HealWhiteHp = 0
		item._UseEffect = staminaEffect
	elseif category == 2 then -- BlackHpGain = base + itemHP * driedmult | WhiteHPGain = (itemHP * (1-driedmult) - base) | TotalHPGain = itemHP (or at least: base)
		if item._HealWhiteHp > 0 then
			item._HealBlackHp = config.base + item._HealWhiteHp * config.driedmult
			item._HealWhiteHp = item._HealWhiteHp * (1 - config.driedmult) - config.base
		else
			item._HealBlackHp = config.base
		end
		item._UseEffect = healEffect
	elseif category == 3 then -- BlackHpGain = base + itemHP * roborantmult | WhiteHPGain = itemHP (or at least: base) | TotalHPGain = base + itemHP * (1 + roborantmult) (or at least: 2*base)
		if item._HealWhiteHp > 0 then
			item._HealBlackHp = config.base + item._HealWhiteHp * config.roborantmult
		else
			item._HealBlackHp = config.base
			item._HealWhiteHp = config.base
		end
		item._UseEffect = healEffect
	end
end

local function apply_items()
	local itemManager = sdk.get_managed_singleton("app.ItemManager")
	if itemManager == nil or itemManager._ItemDataDict == nil
		or itemManager._ItemDataDict:get_Count() == 0 then
		return false
	end

	local count = 0
	-- Avoid value-type enumerators: recent REFramework builds can return an invalid struct.
	for id, category in pairs(foodtable) do
		local item = itemManager:call("getItemData(System.Int32)", id)
		if item == nil then
			log.warn("[FoodFightsFatigue] Item ID " .. id .. " is missing from the item database.")
		else
			apply_item(item, category)
			count = count + 1
		end
	end
	log.info("[FoodFightsFatigue] Applied healing changes to " .. count .. " items.")
	return true
end

local applied = apply_items()
if not applied then
	log.info("[FoodFightsFatigue] Waiting for the item database.")
end

re.on_application_entry("UpdateBehavior", function()
	if applied then return end
	local ok, result = pcall(apply_items)
	if not ok then
		applied = true
		log.error("[FoodFightsFatigue] Applying settings failed; retries stopped: " .. tostring(result))
		return
	end
	applied = result
end)

local function save_config()
	local ok, result = pcall(json.dump_file, "FoodFightsFatigue_config.json", config)
	if not ok or result == false then
		log.error("[FoodFightsFatigue] Could not save settings: " .. tostring(result))
	end
end

re.on_config_save(save_config)
re.on_draw_ui(function()
	if not imgui.tree_node("Food Fights Fatigue") then return end
	local settingsChanged = imgui.button("Reset to defaults")
	if settingsChanged then
		config.base = 20
		config.foodmult = 0.1
		config.driedmult = 0.2
		config.roborantmult = 0.05
	end
	imgui.text("Changes apply live and save automatically.")
	imgui.text("Note: Descriptions may not update immediately after changes.")
	local changed, value = imgui.slider_int("Base recovery", config.base, 0, 100)
	settingsChanged = settingsChanged or changed
	if changed then config.base = value end
	changed, value = imgui.slider_float("Food multiplier", config.foodmult, 0.00, 2.00, "%.2f")
	if changed then config.foodmult = value end
	settingsChanged = settingsChanged or changed
	changed, value = imgui.slider_float("Dried food multiplier", config.driedmult, 0.00, 2.00, "%.2f")
	if changed then config.driedmult = value end
	settingsChanged = settingsChanged or changed
	changed, value = imgui.slider_float("Roborant multiplier", config.roborantmult, 0.00, 2.00, "%.2f")
	if changed then config.roborantmult = value end
	settingsChanged = settingsChanged or changed
	imgui.tree_pop()
	if settingsChanged then
		applied = false
		save_config()
	end
end)

-- Restore the baseline before scripts reload so it is not captured from modified data.
re.on_script_reset(function()
	for _, original in pairs(originals) do
		original.item._HealWhiteHp = original.whiteHp
		original.item._HealBlackHp = original.blackHp
		original.item._UseEffect = original.useEffect
	end
end)

-- Rysel