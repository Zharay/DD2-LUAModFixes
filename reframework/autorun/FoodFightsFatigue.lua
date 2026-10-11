local config = json.load_file("FoodFightsFatigue_config.json") or {}
if config.base == nil then config.base = 20 end
if config.foodmult == nil then config.foodmult = 0.1 end
if config.driedmult == nil then config.driedmult = 0.2 end
if config.roborantmult == nil then config.roborantmult = 0.05 end

local foodtable = {[1]=1,[2]=1,[4]=1,[5]=1,[7]=1,[8]=1,[10]=1,[11]=1,[13]=1,[14]=1,[16]=1,[17]=1,[19]=1,[20]=1,[22]=1,[23]=1,[25]=1,[26]=1,[28]=1,[29]=1,[31]=1,[32]=1,[34]=1,[35]=1,[49]=1,[50]=1,[52]=1,[53]=1,[185]=1,[505]=1,[510]=1,[37]=2,[41]=2,[45]=2,[55]=2,[114]=2,[115]=2,[116]=2,[501]=2,[38]=3,[39]=3,[42]=3,[43]=3,[46]=3,[47]=3,[56]=3,[57]=3,[502]=3,[503]=3,[504]=3}
-- 1. Food
-- 2. Dried Food
-- 3. Roborant

local itemManager = sdk.get_managed_singleton("app.ItemManager")
local iter = itemManager._ItemDataDict:GetEnumerator()

while iter:MoveNext() do
	local item = iter:get_Current():get_Value()
	if foodtable[item._Id] == 1 then -- BlackHpGain = base + itemHP * foodmult | WhiteHPGain = 0 | TotalHPGain = base + itemHP * foodmult
		item._HealBlackHp = config.base + item._HealWhiteHp * config.foodmult
		item._HealWhiteHp = 0
		item._UseEffect = 2
	elseif foodtable[item._Id] == 2 then -- BlackHpGain = base + itemHP * driedmult | WhiteHPGain = (itemHP * (1-driedmult) - base) | TotalHPGain = itemHP (or at least: base)
		if item._HealWhiteHp > 0 then
			item._HealBlackHp = config.base + item._HealWhiteHp * config.driedmult
			item._HealWhiteHp = item._HealWhiteHp * (1 - config.driedmult) - config.base
		else
			item._HealBlackHp = config.base
		end
		item._UseEffect = 1
	elseif foodtable[item._Id] == 3 then -- BlackHpGain = base + itemHP * roborantmult | WhiteHPGain = itemHP (or at least: base) | TotalHPGain = base + itemHP * (1 + roborantmult) (or at least: 2*base)
		if item._HealWhiteHp > 0 then
			item._HealBlackHp = config.base + item._HealWhiteHp * config.roborantmult
		else
			item._HealBlackHp = config.base
			item._HealWhiteHp = config.base
		end
		item._UseEffect = 1
	end
end

-- Rysel