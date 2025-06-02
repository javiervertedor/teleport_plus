-- Security model:
-- Each schedule executes using the permissions and identity of its creator.
-- This ensures that schedules cannot be used to escalate privileges, and
-- that all actions respect the creator's permissions at execution time.
-- If the creator loses required privileges, their schedules will fail.

-- Initialize storage for schedules
local storage = minetest.get_mod_storage()
local integration = assert(loadfile(minetest.get_modpath("teleport_plus") .. "/mods_integration.lua"))()
local schedules = minetest.deserialize(storage:get_string("teleport_schedules")) or {}
local next_schedule_id = (minetest.deserialize(storage:get_string("next_schedule_id")) or 1)

local teleport_helpers = dofile(minetest.get_modpath("teleport_plus") .. "/teleport_helpers.lua")

-- Convert time string to minutes since midnight
local function time_to_minutes(time_str)
    local hours, minutes = time_str:match("^(%d+):(%d+)$")
    if not hours or not minutes then return nil end
    hours, minutes = tonumber(hours), tonumber(minutes)
    if not hours or not minutes or hours > 23 or minutes > 59 then return nil end
    return hours * 60 + minutes
end

-- Convert days string to table of day numbers (1 = Monday, 7 = Sunday)
local function parse_days(days_str)
    if not days_str or days_str:trim() == "" then
        -- If no days specified, return all days
        return {1, 2, 3, 4, 5, 6, 7}
    end

    local days = {}
    local day_names = {
        ["monday"] = 1, ["mon"] = 1,
        ["tuesday"] = 2, ["tue"] = 2,
        ["wednesday"] = 3, ["wed"] = 3,
        ["thursday"] = 4, ["thu"] = 4,
        ["friday"] = 5, ["fri"] = 5,
        ["saturday"] = 6, ["sat"] = 6,
        ["sunday"] = 7, ["sun"] = 7
    }
    
    for day in days_str:lower():gmatch("([^,]+)") do
        day = day:trim()
        local day_num = day_names[day]
        if day_num then
            table.insert(days, day_num)
        end
    end
    
    table.sort(days)
    return #days > 0 and days or {1, 2, 3, 4, 5, 6, 7} -- Return all days if parsing failed
end

-- Get next available schedule ID
local function get_next_schedule_name()
    -- First try to find a gap in existing schedule IDs
    for i = 1, 99 do  -- Limit to 99 schedules
        local schedule_name = string.format("Schedule%02d", i)
        if not schedules[schedule_name] then
            -- Found a gap, use this ID
            return schedule_name
        end
    end

    -- If no gaps found (unlikely), create a new one
    repeat
        local schedule_name = string.format("Schedule%02d", next_schedule_id)
        next_schedule_id = next_schedule_id + 1
        -- Reset ID if it gets too large
        if next_schedule_id > 99 then
            next_schedule_id = 1
        end
        -- Keep looking until we find an unused ID
        if not schedules[schedule_name] then
            storage:set_string("next_schedule_id", minetest.serialize(next_schedule_id))
            return schedule_name
        end
    until false  -- Continue until we find an unused ID
end

-- Save schedules to storage
local function save_schedules()
    storage:set_string("teleport_schedules", minetest.serialize(schedules))
end

-- Check if a schedule should run now
local function check_schedule(schedule)
    local current_time = os.time()
    local time_table = os.date("*t", current_time)
    local current_wday = time_table.wday == 1 and 7 or time_table.wday - 1
    local current_minutes = time_table.hour * 60 + time_table.min
    
    -- Check if today is a scheduled day
    local is_scheduled_day = false
    for _, day in ipairs(schedule.days) do
        if day == current_wday then
            is_scheduled_day = true
            break
        end
    end
    
    if not is_scheduled_day then return false end
    
    -- Check if it's time to run
    if current_minutes == schedule.time then
        -- If non-repeating schedule has run, delete it
        if not schedule.repeat_schedule and schedule.last_run then
            return false
        end
        -- Check if we haven't run yet today
        if not schedule.last_run or os.date("%Y-%m-%d", schedule.last_run) ~= os.date("%Y-%m-%d", current_time) then
            return true
        end
    end
    
    return false
end

-- Helper function to validate location exists and creator has access
local function validate_location(creator_name, location_name)
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    local waypoints = integration.get_unified_inventory_waypoints(creator_name)
    -- Always strip quotes and trim whitespace for location_name
    local clean_location = teleport_helpers.strip_quotes(location_name:trim())
    -- Check if location exists in either storage
    local loc_exists = false
    if locations[clean_location] then
        loc_exists = true
        -- For stored locations, validate owner
        if locations[clean_location].owner ~= creator_name and 
           not minetest.check_player_privs(creator_name, {teleport_plus_admin = true}) then
            return false, "No permission to use this location"
        end
    elseif waypoints then
        for wp_name, wp in pairs(waypoints) do
            if wp_name == clean_location or (wp.name and wp.name == clean_location) then
                loc_exists = true
                break
            end
        end
    end
    if not loc_exists then
        return false, "Location does not exist"
    end
    return true
end

-- Helper function to validate targets exist and creator has permission to teleport them
local function validate_targets(creator_name, target_str)
    -- Parse target specification
    local targets = teleport_helpers.parse_targets(target_str, storage, minetest)
    if not targets then
        return false, "Invalid target specification"
    end
    
    -- Non-admins can only teleport themselves
    if not minetest.check_player_privs(creator_name, {teleport_plus_admin = true}) then
        if targets.type == "player" then
            if targets.players[1] ~= "me" and targets.players[1] ~= creator_name then
                return false, "No permission to teleport other players"
            end
        elseif targets.type == "group" then
            return false, "No permission to teleport groups"
        end
    end
    
    -- Validate that target players exist (for both player and group types)
    if targets.type == "player" then
        for _, player_name in ipairs(targets.players) do
            if player_name ~= "me" and not minetest.get_auth_handler().get_auth(player_name) then
                return false, "Target player does not exist: " .. player_name
            end
        end
    elseif targets.type == "group" then
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        local group_name = teleport_helpers.strip_quotes(target_str:trim())
        if not groups[group_name] then
            return false, "Group '"..group_name.."' does not exist"
        end
        for _, player_name in ipairs(groups[group_name]) do
            if not minetest.get_auth_handler().get_auth(player_name) then
                return false, "Group contains non-existent player: " .. player_name
            end
        end
    end
    
    return true
end

local function execute_schedule(schedule_name)
    local schedule = schedules[schedule_name]
    if not schedule then return end

    schedule.last_run = os.time()
    save_schedules()

    local function broadcast_message(msg)
        minetest.chat_send_all(minetest.colorize("#ffff00", "[Schedule] " .. msg))
    end

    -- Properly strip existing quotes first
    local clean_target = schedule.target:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1'):trim()
    local clean_location = schedule.location:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1'):trim()
    
    -- Use the schedule creator's name and their actual privileges
    local creator_name = schedule.created_by or "schedules"
    local creator_privs = minetest.get_player_privs(creator_name)
    
    -- Verify the creator still has required privileges
    if not creator_privs.teleport_plus_admin then
        broadcast_message(string.format("%s: teleport failed - Schedule creator no longer has required privileges", schedule_name))
        return
    end
    
    -- Validate location
    local loc_valid, loc_err = validate_location(creator_name, clean_location)
    if not loc_valid then
        broadcast_message(string.format("%s: teleport failed - %s", schedule_name, loc_err))
        return
    end
    
    -- Validate targets
    local targets_valid, targets_err = validate_targets(creator_name, clean_target)
    if not targets_valid then
        broadcast_message(string.format("%s: teleport failed - %s", schedule_name, targets_err))
        return
    end

    broadcast_message(string.format("%s: teleporting %s to %s...", 
        schedule_name, clean_target, clean_location))

    -- Just pass target and location to tp command, owner parameter has been removed
    local params = clean_target .. " " .. clean_location

    -- Execute tp command as the schedule creator
    local success, result = minetest.registered_chatcommands["tp"].func(creator_name, params)

    if not success then
        broadcast_message(string.format("%s: teleport failed - %s", schedule_name, result))
        return
    end

    broadcast_message(string.format("%s: teleport completed - %s", schedule_name, result))
end

-- Register a globalstep to check schedules
local schedule_check_timer = 0
local NORMAL_CHECK_INTERVAL = 15  -- Check every 15 seconds normally
local PRECISE_CHECK_INTERVAL = 1  -- Check every second when close to schedule time
local PRECISE_CHECK_WINDOW = 30   -- Start precise checking 30 seconds before schedule

minetest.register_globalstep(function(dtime)
    schedule_check_timer = schedule_check_timer + dtime
    
    -- Get current time
    local current_time = os.time()
    local time_table = os.date("*t", current_time)
    local current_minutes = time_table.hour * 60 + time_table.min
    
    -- Determine if we need precise checking
    local need_precise_check = false
    for _, schedule in pairs(schedules) do
        -- Calculate how many minutes until this schedule
        local minutes_until = schedule.time - current_minutes
        if minutes_until < 0 then
            minutes_until = minutes_until + (24 * 60)  -- Add 24 hours if it's for tomorrow
        end
        
        -- If we're within the precise check window of any schedule
        if minutes_until * 60 <= PRECISE_CHECK_WINDOW then
            need_precise_check = true
            break
        end
    end
    
    -- Check if enough time has elapsed based on check mode
    local check_interval = need_precise_check and PRECISE_CHECK_INTERVAL or NORMAL_CHECK_INTERVAL
    if schedule_check_timer < check_interval then return end
    schedule_check_timer = 0
    
    -- Check all schedules
    for name, schedule in pairs(schedules) do
        if check_schedule(schedule) then
            execute_schedule(name)
        end
    end
end)

-- Helper function to strip both single and double quotes
local function strip_all_quotes(str)
    -- First strip double quotes
    str = str:gsub('^"(.-)"$', '%1')
    -- Then strip single quotes
    str = str:gsub("^'(.-)'$", '%1')
    return str
end

-- Export validate_targets and validate_location for use in commands.lua
return {
    schedules = schedules,
    save_schedules = save_schedules,
    get_next_schedule_name = get_next_schedule_name,
    time_to_minutes = time_to_minutes,
    parse_days = parse_days,
    execute_schedule = execute_schedule,
    reload = function()
        local new_schedules = minetest.deserialize(storage:get_string("teleport_schedules")) or {}
        -- Clear and repopulate the schedules table in-place
        for k in pairs(schedules) do schedules[k] = nil end
        for k, v in pairs(new_schedules) do schedules[k] = v end
        return schedules
    end,
    validate_targets = validate_targets,
    validate_location = validate_location
}
