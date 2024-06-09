obs = obslua
os = require("os")
bit = require("bit")
ffi = require("ffi")
APP = {
    SHOW = 1; HIDE = 2; QK = 50; VF = 1; NR = 100; STEPS = 10
}
local __settings__ = nil
local animation_list = {
    {id = "lr";name = "From left to right"},
    {id = "rl";name = "From right to left"},
    {id = "tb";name = "From top to bottom"},
    {id = "bt";name = "From bottom to top"}
}
source = {}
source.id = "hns-filter-iixisii"
source.type = obs.OBS_SOURCE_TYPE_FILTER
source.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO)
__TIMER_CALLBACK__ = nil
source.get_name = function(data)
    return "Hide2Show"
end
source.file_is_active = true
source.get_width = function(_source_filter)
    if _source_filter == nil then
        return 0
    end
    return _source_filter.width
end
source.get_height = function(_source_filter)
    if _source_filter == nil then
        return 0
    end
    return _source_filter.height
end
source.get_properties = function(settings)
    local p = obs.obs_properties_create()
    local p_group = obs.obs_properties_create()
    local group = obs.obs_properties_add_group(p, "op_group","Action", obs.OBS_GROUP_NORMAL, p_group)
    obs.obs_properties_add_int(p_group, "hide_time", "Hide time:", 1, 100000000, 1)
    obs.obs_properties_add_bool(p_group, "hide_time_random", "Random")
    obs.obs_properties_add_int(p_group, "show_time", "Show time:", 1 , 100000000,1)
    obs.obs_properties_add_bool(p_group, "show_time_random", "Random")
    -- animation
    local p_anime_group = obs.obs_properties_create()
    obs.obs_properties_add_group(p, "anime_group", "Animation", obs.OBS_GROUP_NORMAL, p_anime_group)
    local anime_opt = obs.obs_properties_add_list(p_anime_group, "anime_opt", "", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(anime_opt, "Select animation(optional)", "def")
    for _, iter in pairs(animation_list) do
        obs.obs_property_list_add_string(anime_opt, iter.name, iter.id)
    end
    obs.obs_property_set_modified_callback(anime_opt, function(pros, property, settings)
        local _settings = PairStack(settings, nil, true)
        local opt = _settings.get_str("anime_opt")
        local tim = obs.obs_properties_get(pros, "anime_tim")
        local steps = obs.obs_properties_get(pros, "anime_steps")
        local stat = false
        if opt == nil or opt == "def" then
            stat = false
        else
            stat = true
        end
        if tim ~= nil then
            obs.obs_property_set_visible(tim, stat)
            obs.obs_property_set_visible(steps, stat)
        end
        return true
    end)

    -- time
    local anime_tim = obs.obs_properties_add_list(p_anime_group, "anime_tim", "", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(anime_tim, "Select timing(default normal)", "def")
    obs.obs_property_list_add_string(anime_tim, "Normal", "nr")
    obs.obs_property_list_add_string(anime_tim, "Quick", "qk")
    obs.obs_property_list_add_string(anime_tim, "Very Fast", "vf")
    obs.obs_property_set_visible(anime_tim, false)

    -- steps
    local anime_steps = obs.obs_properties_add_int_slider(p_anime_group, "anime_steps","Velocity", 1, 100, 1)
    obs.obs_property_set_visible(anime_steps, false)
    return p
end
source.get_defaults = function(settings)
    local _settings = PairStack(settings, nil,true)
    _settings.str("anime_opt", "def", true)
    _settings.str("anime_tim", "def", true)
    _settings.int("hide_time", 1, true)
    _settings.int("show_time", 1, true)
    _settings.int("anime_steps", 10)
end
source.create = function(settings, _source)
    local _source_filter = {}
    _source_filter.source = _source
    -- get width, and height
    update_source_size(_source_filter)
    --local _er = ffi.new("char*[1]")
    --_er[0] = ffi.cast("char*", err)
    obs.obs_enter_graphics()
    _source_filter.effect = obs.gs_effect_create(shader, nil, nil)
    obs.obs_leave_graphics()
   -- ffi.C.free(_er[0])
    if _source_filter.effect ~= nil then
        _source_filter.params = {}
        _source_filter.params.width = obs.gs_effect_get_param_by_name(_source_filter.effect, "width")
        _source_filter.params.height = obs.gs_effect_get_param_by_name(_source_filter.effect, "height")
    else
        source.destroy(_source_filter)
        return
    end
    _source_filter.settings = PairStack(settings, nil, true)
    _source_filter.currTime = os.time()
    _source_filter.action = APP.HIDE
    _source_filter.init = false
    source.update(_source_filter, settings)
    return _source_filter
end
source.update = function(_source_filter, settings)
    if __TIMER_CALLBACK__ ~= nil and type(__TIMER_CALLBACK__) == "function" then
        obs.timer_remove(__TIMER_CALLBACK__)
        __TIMER_CALLBACK__ = nil
    end
    _source_filter.hide_time_max = _source_filter.settings.get_int("hide_time")
    _source_filter.hide_time = _source_filter.settings.get_int("hide_time")
    _source_filter.hide_time_random = _source_filter.settings.get_bul("hide_time_random")
    _source_filter.steps = _source_filter.settings.get_int("anime_steps")
    _source_filter.show_time_max = _source_filter.settings.get_int("show_time")
    _source_filter.show_time = _source_filter.settings.get_int("show_time")
    _source_filter.show_time_random = _source_filter.settings.get_bul("show_time_random")
    _source_filter.anime_opt = _source_filter.settings.get_str("anime_opt")
    _source_filter.anime_tim = _source_filter.settings.get_str("anime_tim")
    local defPos = _source_filter.settings.get_obj("defPos")
    if defPos.data ~= nil then
        _source_filter.defPos = obs.vec2()
        _source_filter.defPos.x = defPos.get_int("x")
        _source_filter.defPos.y = defPos.get_int("y")
        if _source_filter.sceneitem ~= nil and _source_filter.sceneitem.data ~= nil then
            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, _source_filter.defPos)
        end
    end
    defPos.free()
    _source_filter.is_loading = false
    if _source_filter.source == nil then
        return
    end
    update_source_size(_source_filter)
end
source.destroy = function(_source_filter)
    scheduler().clear()
    -- set to default
    if _source_filter.sceneitem ~=nil and _source_filter.sceneitem.data ~= nil then
        if _source_filter.defPos ~= nil then
            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, _source_filter.defPos)
        end
        if _source_filter.defAction == APP.HIDE then
            obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, false)
        elseif _source_filter.defAction == APP.SHOW then
            obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
        end
        _source_filter.sceneitem.free()
    end
    if _source_filter.effect ~= nil then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(_source_filter.effect)
        obs.obs_leave_graphics()
    end
    -- do stuff
    _source_filter = nil
end
source.video_render = function(_source_filter)
    -- do stufff...
    if _source_filter == nil then
        return
    end
    if not obs.obs_source_process_filter_begin(_source_filter.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING) then
        obs.obs_source_skip_video_filter(_source_filter.source)
        return
    end
    if _source_filter.params == nil then
        return
    end

    obs.gs_effect_set_int(_source_filter.params.width, _source_filter.width)
    obs.gs_effect_set_int(_source_filter.params.height, _source_filter.height)
    obs.gs_blend_state_push()
	obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_INVSRCALPHA)
    obs.obs_source_process_filter_end(_source_filter.source, _source_filter.effect,  _source_filter.width, _source_filter.height)
    obs.gs_blend_state_pop()
end
source.video_tick = function(_source_filter, fps)
    -- do stuff ..
    if _source_filter.source ~= nil and not obs.obs_source_enabled(_source_filter.source) then
        if not _source_filter.enabled_checked then
            _source_filter.enabled_checked = true
            if __TIMER_CALLBACK__ ~= nil then
                obs.timer_remove(__TIMER_CALLBACK__)
                __TIMER_CALLBACK__ = nil
            end
            if _source_filter.sceneitem ~= nil and _source_filter.sceneitem.data ~= nil then
                if _source_filter.defPos ~= nil then
                    obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, _source_filter.defPos)
                end
                if _source_filter.defAction == APP.HIDE then
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, false)
                elseif _source_filter.defAction == APP.SHOW then
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                end
                _source_filter.sceneitem.free()
                _source_filter.sceneitem = nil
            end
            _source_filter.is_loading = false
            _source_filter.defPos = nil
            _source_filter.init = false 
        end
        return
    else
        _source_filter.enabled_checked = false
    end
    if not _source_filter.init then
        _source_filter.init = true
        local source_target = obs.obs_filter_get_target(_source_filter.source)
        if source_target ~= nil then
            local n = obs.obs_source_get_name(source_target)
            local _scene_source = obs_wrap_source(obs.obs_frontend_get_current_scene(), OBS_SRC_TYPE)
            local scene = obs.obs_scene_from_source(_scene_source.data)
            if scene ~= nil then
                _source_filter.sceneitem = obs_wrap_source(
                    obs.obs_scene_sceneitem_from_source(scene, source_target),
                    OBS_SCENEITEM_TYPE
                )
                if _source_filter.sceneitem.data ~= nil then
                    _source_filter.currTime = os.time()
                    if obs.obs_sceneitem_visible(_source_filter.sceneitem.data) then
                        _source_filter.action = APP.HIDE
                        _source_filter.defAction = APP.SHOW
                    else
                        _source_filter.action = APP.SHOW
                        _source_filter.defAction = APP.HIDE
                    end
                    if _source_filter.defPos == nil then
                        _source_filter.defPos = obs.vec2()
                        obs.obs_sceneitem_get_pos(_source_filter.sceneitem.data, _source_filter.defPos)
                        local defPos = PairStack()
                        defPos.int("x",_source_filter.defPos.x)
                        defPos.int('y', _source_filter.defPos.y)
                        _source_filter.settings.obj("defPos",defPos.data)
                        defPos.free()
                    end
                end
            end
            _source_filter.base_width = obs.obs_source_get_base_width(_scene_source.data)
            _source_filter.base_height = obs.obs_source_get_base_height(_scene_source.data)
            _scene_source.free()
        end
    end
    if not _source_filter.is_loading then
        -- performs hide
        if _source_filter.action == APP.HIDE and os.time() - _source_filter.currTime >= _source_filter.hide_time then
            local function init_hide()
                obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, false)
                _source_filter.currTime = os.time()
                _source_filter.action = APP.SHOW
                if _source_filter.hide_time_random == true then
                    _source_filter.hide_time = math.random(1, _source_filter.hide_time_max)
                end
            end

            if _source_filter.anime_opt ~= nil and _source_filter.anime_opt ~= "def" then
                _source_filter.is_loading = true
            
                local pos = obs.vec2()
                obs.obs_sceneitem_get_pos(_source_filter.sceneitem.data, pos)
                local oldPos = obs.vec2()
                oldPos.x = pos.x;oldPos.y = pos.y
                local anime_config = nil
                __TIMER_CALLBACK__ = function() end
                if _source_filter.anime_opt == "lr" then -- left to right
                    __TIMER_CALLBACK__ = function()
                        if pos.x >= _source_filter.base_width + _source_filter.width then
                            init_hide()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.x = pos.x + _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                elseif _source_filter.anime_opt == "rl" then -- right to left
                    __TIMER_CALLBACK__ = function()
                        if pos.x <= -(_source_filter.width * 2) then
                            init_hide()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.x = pos.x - _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                elseif _source_filter.anime_opt == "tb" then
                    __TIMER_CALLBACK__ = function()
                        if pos.y >= _source_filter.base_height + _source_filter.height then
                            init_hide()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.y = pos.y + _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                elseif _source_filter.anime_opt == "bt" then
                    __TIMER_CALLBACK__ = function()
                        if pos.y <= -(_source_filter.height * 2) then
                            init_hide()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.y = pos.y - _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                end
                if _source_filter.anime_tim == "qk" then
                    obs.timer_add(__TIMER_CALLBACK__, APP.QK)
                elseif _source_filter.anime_tim == "vf" then
                    obs.timer_add(__TIMER_CALLBACK__, APP.VF)
                else
                    obs.timer_add(__TIMER_CALLBACK__, APP.NR)
                end
            else
                init_hide()
            end

        -- perfom the show
        elseif _source_filter.action == APP.SHOW and os.time() - _source_filter.currTime >= _source_filter.show_time then
            local function init_show()
                obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                _source_filter.currTime = os.time()
                _source_filter.action = APP.HIDE
                if _source_filter.show_time_random == true then
                    _source_filter.show_time = math.random(1, _source_filter.show_time_max)
                end
            end
            if _source_filter.anime_opt ~= nil and _source_filter.anime_opt ~= "def" then
                _source_filter.is_loading = true
                local pos = obs.vec2()
                obs.obs_sceneitem_get_pos(_source_filter.sceneitem.data, pos)
                __TIMER_CALLBACK__ = function() end
                if _source_filter.anime_opt == "lr" then -- left to right
                    pos.x = -(_source_filter.width * 2)
                    obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                    __TIMER_CALLBACK__ = function()
                        if pos.x >= _source_filter.defPos.x then
                            init_show()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.x = pos.x + _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                elseif _source_filter.anime_opt == "rl" then -- right to left
                    pos.x = (_source_filter.width + _source_filter.base_width)
                    obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                    __TIMER_CALLBACK__ = function()
                        if pos.x <= _source_filter.defPos.x then
                            init_show()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.x = pos.x - _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                elseif _source_filter.anime_opt == "tb" then
                    pos.y = -(_source_filter.height)
                    obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                    __TIMER_CALLBACK__ = function()
                        if pos.y >= _source_filter.defPos.y then
                            init_show()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.y = pos.y + _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end


                elseif _source_filter.anime_opt == "bt" then
                    pos.y = (_source_filter.base_height)
                    obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                    obs.obs_sceneitem_set_visible(_source_filter.sceneitem.data, true)
                    __TIMER_CALLBACK__ = function()
                        if pos.y <= _source_filter.defPos.y then
                            init_show()
                            _source_filter.is_loading = false
                            return obs.timer_remove(__TIMER_CALLBACK__)
                        else
                            pos.y = pos.y - _source_filter.steps
                            obs.obs_sceneitem_set_pos(_source_filter.sceneitem.data, pos)
                        end
                    end
                end
                if _source_filter.anime_tim == "qk" then
                    obs.timer_add(__TIMER_CALLBACK__, APP.QK)
                elseif _source_filter.anime_tim == "vf" then
                    obs.timer_add(__TIMER_CALLBACK__, APP.VF)
                else
                    obs.timer_add(__TIMER_CALLBACK__, APP.NR)
                end
            else
                init_show()
            end
        end
    end
    update_source_size(_source_filter)
end
function update_source_size(_source_filter)
    local target = obs.obs_filter_get_target(_source_filter.source)
    local w = 0;
    local h = 0;
    if target ~= nil then
        w = obs.obs_source_get_base_width(target)
        h = obs.obs_source_get_base_height(target)
    end
    _source_filter.width = w; _source_filter.height = h
end



function IndexPage()
    return [[
        <pre>Select a source and add a filter called 'Hide2Show'.</pre>
        <ul style='padding:0;margin:0'>
            <li>Hide Time</li>
            <ul style='padding:0;margin:0'>
                <pre>The time to hide a source in seconds.</pre>
            </ul>
            <li>Show Time</li>
            <ul style='padding:0;margin:0'>
                <pre>The time to show a source in seconds.</pre>
            </ul>

            <li>Random</li>
            <ul style='padding:0;margin:0'>
                <pre>When enabled, it will randomize the time it takes to hide/show</pre>
            </ul>
            <li>Animation</li>
            <ul style='padding:0;margin:0'>
                <pre>You can animate hide/show, by default it is disabled.</pre>
            </ul>
        </ul>
    ]]
end

function script_properties()
    local p = obs.obs_properties_create()
    obs.obs_properties_add_text(p, "hns_label", IndexPage(), obs.OBS_TEXT_INFO)
    return p;
end
function script_load(settings)
    source.file_is_active = true
    obs.obs_register_source(source)
end
function script_unload() 
    source.file_is_active = false
    obs.timer_remove(__TIMER_CALLBACK__)
end
function script_defaults(settings) end
function welcomeIndex()
	return [[<center><h1 style = "color:#eee;padding:0;margin:0">HIDE & SHOW</h3><h5 style = 'color:#ddd'><i>Ver. 5.0.0 - Made by iixisii</i></h5></center>
		<center>
			<p>You can learn more about this script <a href = 'https://github.com/iixisii/Hide2Show'>here</a> or watch a tutorial <a href = 'https://youtu.be/lr-Z2jqADsQ'>video</a></p>
		</center>
		<hr/>
	]]
end
function script_description()
    return welcomeIndex()
end

-- [[ utils ]]
-- table stuff
function GetTableLen(ta)
	local count = 0
	for _, iter in pairs(ta) do
		count = count + 1
	end
	return count;
end
function GetNameFromTableByIndex(ta, index)
	if GetTableLen(ta) > 0 then
		local start = 1
		for targetName, iter in pairs(ta) do
			if start == index then
				return targetName
			end
			start = start + 1
		end
	end
	return nil
end
function display_has_scene(sceneName)
	local _scenes = obs_wrap_source(obs.obs_frontend_get_scenes(), OBS_SRC_LIST_TYPE)
	for _, _scene_source in ipairs(_scenes.data) do
		local loaded_name = obs.obs_source_get_name(_scene_source);
		if sceneName == loaded_name then
			_scenes.free()
			return true
		end
	end
	_scenes.free()
	return false
end

-- schedule an event
scheduled_events = {}
function scheduler(timeout)
    -- if type(timeout) ~= "number" or timeout < 0 then
    --     return obs.script_log(obslua.LOG_ERROR, "[Scheduler] invalid timeout value")
    -- end
    local scheduler_callback = nil
    local function interval()
        obs.timer_remove(interval)
        if type(scheduler_callback) ~= "function" then
            return
        end
        return scheduler_callback(scheduler_callback)
    end
    
    local self = nil; self = {
        after = function(callback)
            if type(callback) == "function" or type(timeout) ~= "number" or timeout < 0 then
                scheduler_callback = callback
            else
                obs.script_log(obslua.LOG_ERROR, "[Scheduler] invalid callback/timeout " .. type(callback))
                return false
            end
            obs.timer_add(interval, timeout)
        end;push = function(callback)
            if callback == nil or type(callback) ~= "function" then
                obs.script_log(obslua.LOG_WARNING, "[Scheduler] invalid callback at {push} " .. type(callback))
                return false
            end
            obs.timer_add(callback, timeout)
            table.insert(scheduled_events, callback)
            return {
                clear = function()
                    if callback == nil or type(callback) ~= "function" then
                        return nil
                    end
                    return obs.timer_remove(callback)
                end;
            }
        end; clear = function()
            if scheduler_callback ~= nil then
                obs.timer_remove(scheduler_callback)
            end
            for _, clb in pairs(scheduled_events) do
                obs.timer_remove(clb)
            end
            scheduled_events = {}; scheduler_callback = nil
        end
    }
    return self
end
OBS_SCENEITEM_TYPE = 1;OBS_SRC_TYPE = 2;OBS_OBJ_TYPE = 3
OBS_ARR_TYPE = 4;OBS_SCENE_TYPE = 5;OBS_SCENEITEM_LIST_TYPE = 6
OBS_SRC_LIST_TYPE = 7;OBS_UN_IN_TYPE = -1
obs_wrap_source = {}
function obs_wrap_source(object, object_type)
	local self = nil
	self = {
		type = object_type, data = object;free = function()
			if self.type == OBS_SCENE_TYPE then
				obs.obs_scene_release(self.data)
			elseif self.type == OBS_SRC_TYPE then
				obs.obs_source_release(self.data)
			elseif self.type == OBS_ARR_TYPE then
				obs.obs_data_array_release(self.data)
			elseif self.type == OBS_OBJ_TYPE then
				obs.obs_data_release(self.data)
			elseif self.type == OBS_SCENEITEM_TYPE then
				obs.obs_sceneitem_release(self.data)
			elseif self.type == OBS_SCENEITEM_LIST_TYPE then
				obs.sceneitem_list_release(self.data)
			elseif self.type == OBS_SRC_LIST_TYPE then
				obs.source_list_release(self.data)
			elseif self.type == OBS_UN_IN_TYPE then
                self.data = nil
                return
			else
                self.data = nil
			end
		end
	}
	table.insert(error_wrapper, self)
	return self
end
error_freed = 0
error_wrapper = {};function error_wrapper_handler (callback)
	return function(...)
		local args = {...}
		local data = nil
		local caller = ""
		for i, v in ipairs(args) do
			if caller ~= "" then
				caller = caller .. ","
			end
			caller = caller .. "args[" .. tostring(i) .. "]"
		end
		caller = "return function(callback,args) return callback(" .. caller .. ") end";
		local run = loadstring(caller)
		local success, result = pcall(function()
			data = run()(callback, args)
		end)
		if not success then
			error_freed = 0
			for _, iter in pairs(error_wrapper) do
				if iter and type(iter.free) == "function" then
					local s, r = pcall(function()
						iter.free()
					end)
					if s then
						error_freed = error_freed + 1
					end
				end
			end
			obs.script_log(obs.LOG_ERROR, "[ErrorWrapper ERROR] => " .. tostring(result))
		end
		return data
	end
end
-- array handle
function ArrayStack(stack, name, ignoreStack)
	if not ignoreStack then 
		if type(stack) ~= "userdata" then
			stack = nil
		elseif stack and (type(name) ~= "string" or name == "")then
			stack = nil
			obs.script_log(obs.LOG_ERROR, "FAILED TO LOAD AN [ArrayStack] INVALID NAME GIVEN")
			return nil
		end
	end
	local self = nil
	self = {
		index = 0;get = function(index)
			if type(index) ~= "number" or index < 0 then
				return nil
			end
			if index > self.size() then
				return nil
			end
			return obs_wrap_source(obs.obs_data_array_item(self.data, index),OBS_OBJ_TYPE)
		end;next = function()
			if type(self.index) ~= "number" or self.index < 0 or self.index > self.size() then
				return nil
			end
			local temp = self.index;self.index = self.index + 1
			return PairStack(obs.obs_data_array_item(self.data, temp), nil, true)
		end;free = function()
			if self.data == nil then
				return false
			end
			obs.obs_data_array_release(self.data)
			self.data = nil
			return true
		end;insert = error_wrapper_handler(function(value)
			if value == nil or type(value) ~= "userdata" then
				obs.script_log("FAILED TO INSERT OBJECT INTO [ArrayStack]")
				return false
			end
			obs.obs_data_array_push_back(self.data, value)
		end); size = error_wrapper_handler(function()
			
			if self.data == nil then
				return 0
			end
			return obs.obs_data_array_count(self.data);
		end);
	}
	if not ignoreStack then
		if stack and name then
			self.data = obs.obs_data_get_array(stack, name)
		else
			self.data = obs.obs_data_array_create()
		end
	else
		self.data = stack
	end
	table.insert(error_wrapper, self)
	return self
end
-- pair stack used to manage memory stuff :)
function PairStack(stack, name, ignoreStack)
	if not ignoreStack then
		if type(stack) ~= "userdata" then
			stack = nil
		elseif stack and (type(name) ~= "string" or name == "")then
			stack = nil
			obs.script_log(obs.LOG_ERROR, "FAILED TO LOAD AN [PairStack] INVALID NAME GIVEN")
			return nil
		end
	end
	local self = nil; self = {
		free = function()
			if self.data == nil then
				return false
			end
			obs.obs_data_release(self.data)
			self.data = nil
			return true
		end; str = error_wrapper_handler(function(name, value, def)

			if (name == nil or type(name) ~= "string" or name == "") or (self.data == nil or type(self.data) ~= "userdata") or (value == nil or type(value) ~="string") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT STR INTO [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_string(self.data, name, value)
            else
                obs.obs_data_set_string(self.data, name, value)
            end
		end);int = error_wrapper_handler(function(name, value, def)
			if (name == nil or type(name) ~= "string" or name == "") or (self.data == nil or type(self.data) ~= "userdata") or (value == nil or type(value) ~="number") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT INT INTO [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_int(self.data, name, value)
            else
			    obs.obs_data_set_int(self.data, name, value)
            end
		end);dbl=error_wrapper_handler(function(name, value, def)
			if (name == nil or type(name) ~= "string" or name == "") or (self.data == nil or type(self.data) ~= "userdata") or (value == nil or type(value) ~="number") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT INT INTO [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_double(self.data, name, value)
            else
			    obs.obs_data_set_double(self.data, name, value)
            end
		end);bul = error_wrapper_handler(function(name, value, def)
			if (name == nil or type(name) ~= "string" or name == "") or (self.data == nil or type(self.data) ~= "userdata") or (type(value) == "nil" or type(value) ~="boolean") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT BUL [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_bool(self.data, name, value)
            else
			    obs.obs_data_set_bool(self.data, name, value)
            end
		end); arr = error_wrapper_handler(function(name, value, def)
			if (name == nil or type(name) ~= "string" or name == "") or (self.data == nil or type(self.data) ~= "userdata") or (type(value) ~="userdata") then
				
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT ARR INTO [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_array(self.data, name, value)
            else
			    obs.obs_data_set_array(self.data, name, value)
            end
		end); obj = error_wrapper_handler(function(name, value, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata") or (type(value) ~="userdata") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO INSERT OBJ INTO [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if def then
                obs.obs_data_set_default_obj(self.data, name, value)
            else
			    obs.obs_data_set_obj(self.data, name, value)
            end
		end);
		-- getter
		get_str = error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata")then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET STR FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return obs.obs_data_get_string(self.data, name)
            else
                return obs.obs_data_get_default_string(self.data, name)
            end
		end);get_int = error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata")then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET INT FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return obs.obs_data_get_int(self.data, name)
            else
                return obs.obs_data_get_default_int(self.data, name)
            end
		end);get_dbl = error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata")then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET DBL FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return obs.obs_data_get_double(self.data, name)
            else
                return obs.obs_data_get_default_double(self.data, name)
            end
		end);get_obj = error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata")then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET OBJ FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return PairStack(obs.obs_data_get_obj(self.data, name), nil, true)
            else
                return PairStack(obs.obs_data_get_default_obj(self.data, name), nil, true)
            end
		end);get_arr =error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata")then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET ARR FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return ArrayStack(obs.obs_data_get_array(self.data, name), nil, true)
            else
                return ArrayStack(obs.obs_data_get_default_array(self.data, name), nil, true)
            end
		end);get_bul = error_wrapper_handler(function(name, def)
			if (name == nil or type(name) ~= "string" or name == "") or (type(self.data) ~= "userdata") then
				obs.script_log(obs.LOG_ERROR,"FAILED TO GET BUL FROM [PairStack] " .. "FOR [" .. tostring(name) .. "] " .. " OF VALUE [" .. tostring(value) .. "] TYPE: " .. tostring(type(value)))
				return false
			end
            if not def then
			    return obs.obs_data_get_bool(self.data, name)
            else
                return obs.obs_data_get_default_bool(self.data, name)
            end
		end);
	}
	if not ignoreStack then
		if stack and name then
			self.data = obs.obs_data_get_obj(stack, name)
		else
			self.data = obs.obs_data_create()
		end
	else
		self.data = stack
	end
	table.insert(error_wrapper, self)
	return self
end

-- [[ shader thing ]]


shader = [[
uniform float4x4 ViewProj;
uniform texture2d image;
uniform int width;
uniform int height;

sampler_state textureSampler {
    Filter    = Linear; //Anisotropy;
    AddressU  = Border;
    AddressV  = Border;
    BorderColor = 00000000;
};
struct VertData 
{
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};
float4 ps_get(VertData v_in) : TARGET 
{
    return image.Sample(textureSampler, v_in.uv.xy);
}
VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}
technique Draw
{
    pass
    {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = ps_get(v_in);
    }
}
]]