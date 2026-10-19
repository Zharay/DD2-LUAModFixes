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

local apply_pending = true
local apply_status
local save_error

local function wait_for_game(message)
    if apply_status ~= message then
        log.warn("[Safer Roads] " .. message)
    end
    apply_status = message
end

local function applySettings()
    local genManager = sdk.get_managed_singleton("app.GenerateManager")
    if not genManager then
        wait_for_game("Waiting for GenerateManager; settings will apply automatically.")
        return
    end
    local genDefaultParam = genManager:get_field("_GenerateDefaultParam")
    if not genDefaultParam then
        wait_for_game("Waiting for generation parameters; settings will apply automatically.")
        return
    end
    local deadCharaTime = genDefaultParam:get_field("_DeadCharaTime")
    local dungeonDeadCharaTime = genDefaultParam:get_field("_DungeonDeadCharaTime")
    if not deadCharaTime or not dungeonDeadCharaTime then
        wait_for_game("Waiting for respawn parameters; settings will apply automatically.")
        return
    end

    -- The current SDK spells the normal-enemy field with a capital I in TIme.
    deadCharaTime:set_field("_NormalCharaTIme", settings.isNotDungeon.normalEnemies)
    deadCharaTime:set_field("_BossCharaTime", settings.isNotDungeon.bossEnemies)
    dungeonDeadCharaTime:set_field("_NormalCharaTIme", settings.isDungeon.normalEnemies)
    dungeonDeadCharaTime:set_field("_BossCharaTime", settings.isDungeon.bossEnemies)
    apply_pending = false
    apply_status = nil
end

local function save_settings()
    if not json.dump_file("safer_roads/mysettings.json", settings) then
        save_error = "Unable to save settings; settings were not applied."
        log.error("[Safer Roads] " .. save_error)
        return
    end
    save_error = nil
    apply_pending = true
    applySettings()
end

-- Autorun can execute before the game's generation parameters are initialized.
re.on_frame(function ()
    if apply_pending then
        applySettings()
    end
end)

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
    if save_error then
        imgui.text(save_error)
    end
    if apply_status then
        imgui.text(apply_status)
    end
    imgui.tree_pop()
  end
end)

applySettings()
