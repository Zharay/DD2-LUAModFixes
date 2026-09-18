local modname = "MarkImportantNpcs"
local configfile = modname .. ".json"
log.info("[" .. modname .. "]" .. " Start")

local _config = {
	{name = "disable_in_cutscene", type = "bool", default=true},
	{name = "show_names", type = "bool", default=false},
	{name = "show_circle", type = "bool", default=true},
    {name = "font_size", type = "float", default = 30},
	{name = "circle_size", type = "float", default=.05, min=0.05, max=0.2},
	{name = "y", type = "float", default = 2},
	{name = "name_color", type = "rgba32", default = 0xffa6e0dd},
	{name = "circle_color", type = "rgba32", default = 0xffe19b46},
	{name = "show_icon", type = "bool", default=false},
	{name = "icon_color", type = "rgba32", default = 0xff3b30ff},
	{name = "icon_size", type = "float", default = 40, min = 10, max = 120},
	{name = "scan_interval", type = "int", default = 4, min = 0, max = 60}
}

local myapi = require("_XYZApi/_XYZApi")
local config = myapi.InitFromFile(_config, configfile)

local font = imgui.load_font("MarkImportantNpcs.otf",config.font_size)

local cam_mgr = sdk.get_managed_singleton("app.CameraManager")
local chr_mgr = sdk.get_managed_singleton("app.CharacterManager")
local player_list_holder = sdk.get_managed_singleton("app.CharacterListHolder")
local npc_manager = sdk.get_managed_singleton("app.NPCManager")
local demoMediator = sdk.get_managed_singleton("app.DemoMediator")
local camera
local cam_matrix
local contact_pt_td = sdk.find_type_definition("via.physics.ContactPoint")
local ray_result = sdk.create_instance("via.physics.CastRayResult"):add_ref()
local via_physics_system = sdk.get_native_singleton("via.physics.System")
local physics_system_td = sdk.find_type_definition("via.physics.System")
-- newer game versions require a via.Scene argument on castRay
local ray_method = physics_system_td:get_method("castRay(via.Scene, via.physics.CastRayQuery, via.physics.CastRayResult)")
local ray_method_arity = ray_method and 3 or 2
if not ray_method then
	ray_method = physics_system_td:get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
end
local scene_manager = sdk.get_native_singleton("via.SceneManager")
local scene_manager_td = sdk.find_type_definition("via.SceneManager")
local get_current_scene_method = scene_manager_td:get_method("get_CurrentScene")
local ray_query = sdk.create_instance("via.physics.CastRayQuery"):add_ref()
ray_query:clearOptions()
ray_query:enableAllHits()
ray_query:enableNearSort()
local set_ray_method = sdk.find_type_definition("via.physics.CastRayQuery"):get_method("setRay(via.vec3, via.vec3)")
local filter_info = ray_query:get_FilterInfo()
filter_info:set_Group(0)
local shape_cast_result = sdk.create_instance("via.physics.ShapeCastResult"):add_ref()
local shape_ray_method = sdk.find_type_definition("via.physics.System"):get_method("castSphere(via.Sphere, via.vec3, via.vec3, System.UInt32, via.physics.FilterInfo, via.physics.ShapeCastResult)")
local shape_ray_method2 = sdk.find_type_definition("via.physics.System"):get_method("castShape(via.physics.ShapeCastQuery, via.physics.ShapeCastResult)")
local shape_cast_result = sdk.create_instance("via.physics.ShapeCastResult"):add_ref()
local sphere = ValueType.new(sdk.find_type_definition("via.Sphere"))
local box = ValueType.new(sdk.find_type_definition("via.physics.BoxShape"))
box:set_UserData(sdk.create_instance("via.physics.UserData"):add_ref())
local shape_cast_query = sdk.create_instance("via.physics.ShapeCastQuery"):add_ref()
shape_cast_query:set_Shape(box)
shape_cast_query:set_FilterInfo(filter_info)
local ray_size = 30.0

-- getContactPoint/getContactCollidable live on different result types depending on ray vs shape cast
local ray_result_td = sdk.find_type_definition("via.physics.CastRayResult")
local shape_result_td = sdk.find_type_definition("via.physics.ShapeCastResult")
local get_contact_point_method_ray = ray_result_td:get_method("getContactPoint(System.UInt32)")
local get_contact_collidable_method_ray = ray_result_td:get_method("getContactCollidable(System.UInt32)")
local get_contact_point_method_shape = shape_result_td:get_method("getContactPoint(System.UInt32)")
local get_contact_collidable_method_shape = shape_result_td:get_method("getContactCollidable(System.UInt32)")
local get_manual_player_method = sdk.find_type_definition("app.CharacterManager"):get_method("get_ManualPlayer")

local function cast_ray(start_position, end_position, layer, maskbits, shape_radius, options, do_reverse)
	local result = {}
	local result_obj = shape_radius and shape_cast_result or ray_result
	local get_contact_point_method = shape_radius and get_contact_point_method_shape or get_contact_point_method_ray
	local get_contact_collidable_method = shape_radius and get_contact_collidable_method_shape or get_contact_collidable_method_ray
	filter_info:set_Layer(layer)
	filter_info:set_MaskBits(maskbits)
	result_obj:clear()
	if shape_radius then
		sphere:set_Radius(shape_radius)
		shape_ray_method:call(nil, sphere, start_position, end_position, options or 1, filter_info, result_obj)
	else
		set_ray_method:call(ray_query, start_position, end_position)
		if ray_method_arity == 3 then
			local scene = get_current_scene_method:call(scene_manager)
			ray_method:call(via_physics_system, scene, ray_query, result_obj)
		else
			ray_method:call(via_physics_system, ray_query, result_obj)
		end
	end
	local num_contact_pts = result_obj:get_NumContactPoints()
	if num_contact_pts > 0 then
		for i=1, num_contact_pts do
			local new_contactpoint = get_contact_point_method:call(result_obj, i-1)
			local new_collidable = get_contact_collidable_method:call(result_obj, i-1)
			local contact_pos = sdk.get_native_field(new_contactpoint, contact_pt_td, "Position")
			local game_object = new_collidable:call("get_GameObject")
			if do_reverse then
				table.insert(result, 1, {game_object, contact_pos})
			else
				table.insert(result, {game_object, contact_pos})
			end
		end
	end
	return result
end

local function is_obscured(position, start_mat, ray_layer, ray_maskbits, leeway)
	start_mat = start_mat or cam_matrix
	local ray_results = cast_ray(start_mat[3], position, ray_layer or 2, ray_maskbits or 0)
	return ray_results[1] and (start_mat[3] - ray_results[1][2]):length() + (leeway or 0.25) < (start_mat[3] - position):length()
end

local te_manager = sdk.get_managed_singleton("app.TalkEventManager")
local function is_quest_npc(npc_chara_id)
	if te_manager:isQuestTalkEventInteractableCharacter(npc_chara_id) or npc_manager:isNPCQuestLayer(npc_chara_id) then
		return true
	end
end

local frame_counter = 0
local cached_draws = {}

re.on_frame(function()
	if not config.show_names and not config.show_circle and not config.show_icon then
		return
	end
	imgui.push_font(font)
	local player = get_manual_player_method:call(chr_mgr)
	camera = sdk.get_primary_camera()
	-- camera can be mid-transition (cutscene/load) and throw on get_GameObject, so guard it
	local ok, cam_go = pcall(function() return camera and camera:get_GameObject() end)
	cam_matrix = ok and cam_go and cam_go:get_Transform():get_WorldMatrix()
	if not cam_matrix then
		imgui.pop_font()
		return
	end

	local should_scan = config.scan_interval <= 0 or frame_counter % config.scan_interval == 0
	frame_counter = frame_counter + 1

	local in_cutscene = false
	if should_scan and config.disable_in_cutscene then
		if demoMediator == nil then
			demoMediator = sdk.get_managed_singleton("app.DemoMediator")
		end
		in_cutscene = demoMediator ~= nil and demoMediator:get_IsPlayingDemo()
		if in_cutscene then
			cached_draws = {}
		end
	end

	if should_scan and not in_cutscene and player and player_list_holder and npc_manager then
		local results = cast_ray(cam_matrix[3] + cam_matrix[2] * -(ray_size), cam_matrix[3] + cam_matrix[2], 3, 1, ray_size)
		-- first hit per game object wins, matching the old break-on-first-match behavior
		local contact_pos_by_gameobject = {}
		for _, result in ipairs(results) do
			if contact_pos_by_gameobject[result[1]] == nil then
				contact_pos_by_gameobject[result[1]] = result[2]
			end
		end

		local new_draws = {}
		local all_chars = player_list_holder:getAllCharacters()
		local char_count = all_chars:get_Count()
		for i = 0, char_count - 1 do
			local char = all_chars:get_Item(i)
			if char ~= player and is_quest_npc(char:get_CharaID()) then
				-- a character can despawn/detach mid-scan and throw on get_GameObject, so guard it
				local ok, char_game_object = pcall(function() return char:get_GameObject() end)
				local contact_pos = ok and char_game_object and contact_pos_by_gameobject[char_game_object]
				if contact_pos and not is_obscured(contact_pos) then
					local pos = char_game_object:get_Transform():get_Position()
					local text_pos = Vector3f.new(pos.x, pos.y+config.y, pos.z)
					local name
					if config.show_names then
						local npc_data = npc_manager:getNPCData(char:get_CharaID())
						name = npc_data and npc_data:get_Name()
					end
					table.insert(new_draws, {pos = text_pos, name = name})
				end
			end
		end
		cached_draws = new_draws
	end

	for _, draw_info in ipairs(cached_draws) do
		if config.show_circle then draw.sphere(draw_info.pos, config.circle_size, config.circle_color, true) end
		if config.show_names and draw_info.name then draw.world_text(draw_info.name, draw_info.pos, config.name_color) end
		if config.show_icon then
			imgui.push_font_size(config.icon_size)
			draw.world_text("!", draw_info.pos, config.icon_color)
			imgui.pop_font_size()
		end
	end
	imgui.pop_font()
end)
myapi.DrawIt(modname, configfile, _config, config, nil, true)
