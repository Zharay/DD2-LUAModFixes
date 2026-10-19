local default_settings = {
    isDungeon = {
      normalEnemies = 72,
      bossEnemies = 96
    },
    isNotDungeon = {
      normalEnemies = 168,
      bossEnemies = 336
    }
  }

local function recurse_def_settings(tbl, defaults_tbl)
  for key, value in pairs(defaults_tbl) do
      if type(tbl[key]) ~= type(value) then 
          if type(value) == "table" then
              tbl[key] = recurse_def_settings({}, value)
          else
              tbl[key] = value
          end
      elseif type(value) == "table" then
          tbl[key] = recurse_def_settings(tbl[key], value)
      end
  end
  return tbl
end

local settings = recurse_def_settings(json.load_file("safer_roads/mysettings.json") or {}, default_settings)

local function save_settings()
    json.dump_file("safer_roads/mysettings.json", settings)
    applySettings()
end

local function applySettings()
    local genManager = sdk.get_managed_singleton("app.GenerateManager")
    local genDefaultParam = genManager._GenerateDefaultParam
    local deadCharaTime = genDefaultParam._DeadCharaTime
    local dungeonDeadCharaTime = genDefaultParam._DungeonDeadCharaTime

    deadCharaTime._NormalCharaTIme = settings.isNotDungeon.normalEnemies
    deadCharaTime._BossCharaTime = settings.isNotDungeon.bossEnemies
    dungeonDeadCharaTime._NormalCharaTIme = settings.isDungeon.normalEnemies
    dungeonDeadCharaTime._BossCharaTime = settings.isDungeon.bossEnemies
end


re.on_draw_ui(function ()
  if imgui.tree_node("Safer Roads") then
    _, settings.isNotDungeon.normalEnemies = imgui.drag_int("Normal Enemy Respawn Time [In Hours]", settings.isNotDungeon.normalEnemies, 1, 0, 2016)
    _, settings.isNotDungeon.bossEnemies = imgui.drag_int("Boss Enemy Respawn Time [In Hours]", settings.isNotDungeon.bossEnemies, 1, 0, 2016)
    _, settings.isDungeon.normalEnemies = imgui.drag_int("Normal Dungeon Enemy Respawn Time [In Hours]", settings.isDungeon.normalEnemies, 1, 0, 2016)
    _, settings.isDungeon.bossEnemies = imgui.drag_int("Boss Dungeon Enemy Respawn Time [In Hours]", settings.isDungeon.bossEnemies, 1, 0, 2016)
    if imgui.button("Save and Apply Settings") then
        save_settings()
    end
    if imgui.button("Restore Default Settings") then
        settings = recurse_def_settings({}, default_settings)
        save_settings()
    end
    imgui.tree_pop()
  end
end)

applySettings()
