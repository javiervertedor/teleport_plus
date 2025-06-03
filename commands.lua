-- Initialize mod storage
local storage = minetest.get_mod_storage()
local integration = dofile(minetest.get_modpath("teleport_plus").."/mods_integration.lua")
-- Use the validate_targets and validate_location from the schedules module
local schedule_module = dofile(minetest.get_modpath("teleport_plus").."/schedules.lua")
local schedules = schedule_module.schedules  -- properly point to actual data
local teleport_helpers = dofile(minetest.get_modpath("teleport_plus") .. "/teleport_helpers.lua")

-- String handling utility functions
local function strip_quotes(str)
    return str:match('^"(.-)"$') or str:match("^'(.-)'$") or str
end

local function split_quoted(str, sep)
    local result = {}
    local current = ""
    local in_quotes = false
    local quote_char = nil
    
    for i = 1, #str do
        local c = str:sub(i,i)
        if (c == '"' or c == "'") and not in_quotes then
            in_quotes = true
            quote_char = c
        elseif c == quote_char and in_quotes then
            in_quotes = false
            quote_char = nil
        elseif (c == sep or c == " ") and not in_quotes then
            if current ~= "" then
                table.insert(result, current)
                current = ""
            end
        else
            current = current .. c
        end
    end
    
    if current ~= "" then
        table.insert(result, current)
    end
    
    return result
end

-- Teleport history tracking
local teleport_history = {}

-- Shared teleport functions
local function validate_target_permissions(name, targets, target_str)    local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
    
    -- Admins can teleport anyone
    if is_admin then
        return true
    end
    
    -- Get the user's groups
    local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
    local user_groups = {}
    for group_name, members in pairs(groups) do
        for _, member in ipairs(members) do
            if member == name then
                user_groups[group_name] = members
                break
            end
        end
    end
    
    if targets.type == "player" then
        -- Allow 'me' or their own name
        if targets.players[1] == "me" or targets.players[1] == name then
            return true
        end
        
        -- Check if target is in one of user's groups
        for _, members in pairs(user_groups) do
            for _, member in ipairs(members) do
                if member == targets.players[1] then
                    return true
                end
            end
        end
        
        return false, "You can only teleport yourself or members of your groups"
    elseif targets.type == "group" then
        -- Check if user is member of the target group
        if user_groups[targets.groupname] then
            return true
        end
        return false, "You can only teleport groups that you are a member of"
    elseif targets.type == "all" then
        -- Non-admins cannot teleport everyone
        return false, "Only admins can teleport all players"
    end
    
    return false, "You don't have permission to teleport these players"
end

local function validate_location_permissions(name, targets, loc_name)
    local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
    
    -- First check if we're dealing with admin
    -- Admins can use any location
    if is_admin then
        return true
    end
    
    -- Check if location exists as a waypoint or location
    local waypoints = integration.get_unified_inventory_waypoints(name)
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    
    -- Check if trying to teleport to home
    if loc_name:lower() == "home" then
        -- Only allow teleporting self to home
        if targets.type == "player" and (targets.players[1] == "me" or targets.players[1] == name) then
            if minetest.check_player_privs(name, {home = true}) then
                return true
            else
                return false, "You need the 'home' privilege to teleport to your home"
            end
        else
            return false, "You cannot teleport others to your home location"
        end
    end
      -- Check all waypoints first
    for wp_name, wp_data in pairs(waypoints) do
        if wp_name:lower() == loc_name:lower() then
            -- Allow only if it's their own waypoint
            if wp_data.owner == name then
                return true
            end
            return false, "You don't have permission to use this waypoint"
        end
    end
    
    -- Then check locations
    if locations[loc_name] then
        -- Allow only if it's their own location
        if locations[loc_name].owner == name then
            return true
        end
        return false, string.format("You don't have permission to use location '%s'", loc_name)
    end
    
    return false, string.format("Location '%s' does not exist or you don't have permission to use it", loc_name)
end

local function validate_group_exists(target_str, groups)
    -- Strip quotes from group name
    local group_name = strip_quotes(target_str:trim())
    
    if not groups[group_name] then
        return false, "Group '"..group_name.."' does not exist"
    end

    -- Validate all players in the group exist
    local invalid_players = {}
    for _, player_name in ipairs(groups[group_name]) do
        if not minetest.player_exists(player_name) then
            table.insert(invalid_players, player_name)
        end
    end

    if #invalid_players > 0 then
        return false, string.format(
            "The following players in group '%s' do not exist: %s",
            group_name,
            table.concat(invalid_players, ", ")
        )
    end

    -- Group exists and all players are valid
    return true
end

-- Helper function to get location position
local function get_location_pos(loc_name, owner_name)
    -- Always fully strip quotes and whitespace
    local unquoted_name = loc_name:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1'):trim()    local is_admin = minetest.check_player_privs(owner_name, {teleport_plus_admin = true})
    
    -- First check custom locations
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    if locations[unquoted_name] then
        -- For non-admins, only return location if they own it
        if is_admin or locations[unquoted_name].owner == owner_name then
            return locations[unquoted_name].pos
        end
    end

    -- Check Unified Inventory waypoints - only for owner or admin
    local waypoints = integration.get_unified_inventory_waypoints(owner_name)
    for wp_name, wp_data in pairs(waypoints) do
        if wp_name:lower() == unquoted_name:lower() then
            -- Allow admins and waypoint owners
            if is_admin or wp_data.owner == owner_name then
                return wp_data.pos
            end
        end
    end

    -- Finally check if it's "home"
    if unquoted_name:lower() == "home" then
        return integration.get_home_position(owner_name)
    end

    return nil
end

-- Helper function to calculate a grid of safe positions
local function get_safe_grid_positions(center_pos, player_count)
    local positions = {}
    local unsafe_spots = {}
    local grid_size = math.ceil(math.sqrt(player_count))
    local spacing = 2 -- Distance between players
    local start_x = center_pos.x - math.floor(grid_size/2) * spacing
    local start_z = center_pos.z - math.floor(grid_size/2) * spacing

    for row = 0, grid_size-1 do
        for col = 0, grid_size-1 do
            if #positions < player_count then
                local pos = {
                    x = start_x + (col * spacing),
                    y = center_pos.y,
                    z = start_z + (row * spacing)
                }
                
                -- Check if position is safe
                local safe_pos, safety_msg = integration.is_safe_position(pos)
                if safe_pos then
                    table.insert(positions, pos)
                else
                    table.insert(unsafe_spots, {
                        pos = pos,
                        reason = safety_msg
                    })
                end
            end
        end
    end

    return positions, unsafe_spots
end

-- Helper function to validate and filter online players
local function get_online_players(targets, caller_name)
    local online = {}
    local offline = {}
    local invalid = {}
    
    if not targets then
        return online, offline, invalid
    end

    -- Get all currently online players
    local all_online = {}
    for _, player in ipairs(minetest.get_connected_players()) do
        all_online[player:get_player_name()] = true
    end

    -- Get whitelist if available
    local whitelist = integration.has_whitelist() and integration.get_whitelist()

    -- Handle special cases
    if targets.type == "all" then
        for name, _ in pairs(all_online) do
            if not whitelist or whitelist[name] then
                table.insert(online, name)
            end
        end
        return online, offline, invalid
    end

    local target_players = {}
    if targets.type == "player" then
        if targets.players[1] == "me" then
            target_players = {caller_name}
        else
            target_players = targets.players
        end
    elseif targets.type == "group" then
        target_players = targets.players
    end

    for _, name in ipairs(target_players) do
        if not minetest.get_auth_handler().get_auth(name) then
            table.insert(invalid, name)
        elseif whitelist and not whitelist[name] then
            table.insert(invalid, name)
        elseif all_online[name] then
            table.insert(online, name)
        else
            table.insert(offline, name)
        end
    end
    
    return online, offline, invalid
end

-- HUD management
local player_huds = {}

local function update_location_hud(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return end

    -- Remove existing HUDs for this player
    if player_huds[player_name] then
        for _, id in ipairs(player_huds[player_name]) do
            player:hud_remove(id)
        end
    end
    player_huds[player_name] = {}

    -- Get locations
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    
    -- Add HUD for each location with HUD enabled
    for loc_name, loc_data in pairs(locations) do
        if loc_data.show_hud then            local hud_id = player:hud_add({
                type = "waypoint",
                name = loc_name,
                text = "m",
                number = 0xFFFFFF,
                world_pos = loc_data.pos
            })
            table.insert(player_huds[player_name], hud_id)
        end
    end
end

-- Update HUDs when players join
minetest.register_on_joinplayer(function(player)
    minetest.after(1, update_location_hud, player:get_player_name())
end)

-- Remove HUDs when players leave
minetest.register_on_leaveplayer(function(player)
    player_huds[player:get_player_name()] = nil
end)

-- Logging helper function
local function log_action(action, name, message)
    minetest.log("action", string.format("[teleport_plus] %s by %s: %s", action, name, message))
end

-- GROUP MANAGEMENT COMMANDS
-- Register the /setgroup command
minetest.register_chatcommand("setgroup", {
    description = "Create or update a teleport group",
    params = "<groupname> <member1> <member2> ...",
    privs = { teleport_plus_admin = true },  -- Require teleport_plus_admin privilege
    func = function(name, param)
        -- Split parameters
        local params = param:split(" ")
        if #params < 2 then
            return false, "Usage: /setgroup <groupname> <member1> <member2> ..."
        end

        local groupname = params[1]
        table.remove(params, 1)
        local members = {}
        for _, param in ipairs(params) do
            for member in param:gmatch("([^,]+)") do
                table.insert(members, member:trim())
            end
        end

        if integration.has_whitelist() then
            local whitelist = integration.get_whitelist()
            for _, member in ipairs(members) do
                if not whitelist[member] then
                    log_action("setgroup failed", name, "Player "..member.." not whitelisted")
                    return false, "Player "..member.." is not whitelisted"
                end
            end
        else
            for _, member in ipairs(members) do
                if not minetest.get_auth_handler().get_auth(member) then
                    log_action("setgroup failed", name, "Player "..member.." not registered")
                    return false, "Player "..member.." is not registered"
                end
            end
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        groups[groupname] = members
        storage:set_string("teleport_groups", minetest.serialize(groups))

        log_action("setgroup success", name, "Created/updated group '"..groupname.."' with "..#members.." members")
        return true, "Teleport group '"..groupname.."' has been created/updated"
    end
})

-- Register the /groupadd command
minetest.register_chatcommand("groupadd", {
    description = "Add users to an existing teleport group",
    params = "<groupname> <user1> <user2> ...",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local params = param:split(" ")
        if #params < 2 then
            return false, "Usage: /groupadd <groupname> <user1> <user2> ..."
        end

        local groupname = params[1]
        table.remove(params, 1)
        -- Split remaining parameters by both spaces and commas
        local new_members = {}
        for _, param in ipairs(params) do
            for member in param:gmatch("([^,]+)") do
                table.insert(new_members, member:trim())
            end
        end

        -- Remove local storage declaration since we use global
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Check whitelist/registration for new members
        if integration.has_whitelist() then
            local whitelist = integration.get_whitelist()
            for _, member in ipairs(new_members) do
                if not whitelist[member] then
                    return false, "Player "..member.." is not whitelisted"
                end
            end
        else
            for _, member in ipairs(new_members) do
                if not minetest.get_auth_handler().get_auth(member) then
                    return false, "Player "..member.." is not registered"
                end
            end
        end

        -- Check for duplicates and add new members
        local added_users = {}
        local duplicates = {}
        for _, member in ipairs(new_members) do
            local is_duplicate = false
            for _, existing in ipairs(groups[groupname]) do
                if member == existing then
                    table.insert(duplicates, member)
                    is_duplicate = true
                    break
                end
            end
            if not is_duplicate then
                table.insert(groups[groupname], member)
                table.insert(added_users, member)
            end
        end

        -- If we found only duplicates
        if #added_users == 0 then
            local member_list = table.concat(groups[groupname], ", ")
            return false, "User(s) "..table.concat(duplicates, ", ").." already in group '"..groupname.."'. Users: "..member_list
        end

        -- If we found some duplicates but added others
        storage:set_string("teleport_groups", minetest.serialize(groups))
        local member_list = table.concat(groups[groupname], ", ")
        local message = "User(s) "..table.concat(added_users, ", ").." added to group '"..groupname.."'"
        if #duplicates > 0 then
            message = message.." (Skipped: "..table.concat(duplicates, ", ").." - already in group)"
        end
        message = message..". Users: "..member_list
        log_action("Users Added to Group", name, "Group: " .. groupname .. ", Added: " .. table.concat(added_users, ", ") .. ", Duplicates: " .. table.concat(duplicates, ", "))

        return true, message
    end
})

-- Register the /groupremove command
minetest.register_chatcommand("groupremove", {
    description = "Remove users from a teleport group",
    params = "<groupname> <user1> <user2> ...",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local params = param:split(" ")
        if #params < 2 then
            return false, "Usage: /groupremove <groupname> <user1> <user2> ..."
        end

        local groupname = params[1]
        table.remove(params, 1)
        -- Split remaining parameters by both spaces and commas
        local remove_members = {}
        for _, param in ipairs(params) do
            for member in param:gmatch("([^,]+)") do
                table.insert(remove_members, member:trim())
            end
        end

        -- Remove local storage declaration
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Remove members
        local removed_users = {}
        local new_members = {}
        for _, member in ipairs(groups[groupname]) do
            local should_keep = true
            for _, remove_member in ipairs(remove_members) do
                if member == remove_member then
                    should_keep = false
                    table.insert(removed_users, member)
                    break
                end
            end
            if should_keep then
                table.insert(new_members, member)
            end
        end

        groups[groupname] = new_members
        storage:set_string("teleport_groups", minetest.serialize(groups))
        local member_list = table.concat(new_members, ", ")
        log_action("Users Removed from Group", name, "Group: " .. groupname .. ", Removed: " .. table.concat(removed_users, ", "))

        return true, "User(s) "..table.concat(removed_users, ", ").." removed from group '"..groupname.."'. Users: "..member_list
    end
})

-- Register the /delgroup command
minetest.register_chatcommand("delgroup", {
    description = "Delete a teleport group",
    params = "<groupname>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local groupname = param:trim()
        if groupname == "" then
            return false, "Usage: /delgroup <groupname>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            log_action("delgroup failed", name, "Group '"..groupname.."' does not exist")
            return false, "Group '"..groupname.."' does not exist"
        end

        local member_count = #groups[groupname]
        groups[groupname] = nil
        storage:set_string("teleport_groups", minetest.serialize(groups))
        
        log_action("delgroup success", name, "Deleted group '"..groupname.."' with "..member_count.." members")
        return true, "Deleted group '"..groupname.."'"
    end
})

-- Register the /listgroups command
minetest.register_chatcommand("listgroups", {
    description = "List available teleport groups (all groups for admins, only your groups for regular users)",
    privs = {},  -- No special privileges required
    func = function(name, param)
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        
        if next(groups) == nil then
            return false, "No groups available"
        end

        local group_list = {}
        for groupname, members in pairs(groups) do
            -- For regular users, only show groups they belong to
            local is_member = false
            if not is_admin then
                for _, member in ipairs(members) do
                    if member == name then
                        is_member = true
                        break
                    end
                end
            end
            
            if is_admin or is_member then
                table.insert(group_list, string.format("%s (%d members)", 
                    groupname, 
                    #members))
            end
        end
        
        if #group_list == 0 then
            return false, "You don't belong to any groups"
        end
        
        table.sort(group_list)  -- Sort groups alphabetically
        return true, "Available groups: " .. table.concat(group_list, ", ")
    end
})

-- Register the /group command
minetest.register_chatcommand("group", {
    description = "List users in a teleport group",
    params = "<groupname>",
    privs = {},  -- No special privileges required
    func = function(name, param)
        local groupname = param:trim()
        if groupname == "" then
            return false, "Usage: /group <groupname>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Check if user is in the group or is an admin
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local is_member = false
        for _, member in ipairs(groups[groupname]) do
            if member == name then
                is_member = true
                break
            end
        end

        if not (is_admin or is_member) then
            return false, "You must be a member of the group to view its members"
        end

        local member_list = table.concat(groups[groupname], ", ")
        return true, "Members in group '"..groupname.."': "..member_list
    end
})

-- Register the /givegroup command
minetest.register_chatcommand("givegroup", {
    description = "Give an item to all online users in a group (max 99)",
    params = "<groupname> <itemname> [count]",
    privs = { give = true },
    func = function(name, param)
        local params = param:split(" ")
        if #params < 2 then
            return false, "Usage: /givegroup <groupname> <itemname> [count]"
        end

        local groupname = params[1]
        local itemname = params[2]
        local count = tonumber(params[3]) or 1
        count = math.min(count, 99)

        if not minetest.registered_items[itemname] then
            log_action("givegroup failed", name, "Invalid item '"..itemname.."'")
            return false, "Item '"..itemname.."' does not exist"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            log_action("givegroup failed", name, "Group '"..groupname.."' does not exist")
            return false, "Group '"..groupname.."' does not exist"
        end

        local online_players = {}
        for _, player in ipairs(minetest.get_connected_players()) do
            local player_name = player:get_player_name()
            for _, member in ipairs(groups[groupname]) do
                if player_name == member then
                    table.insert(online_players, player_name)
                    break
                end
            end
        end

        if #online_players == 0 then
            log_action("givegroup failed", name, "No online users in group '"..groupname.."'")
            return false, "No online users found in group '"..groupname.."'"
        end

        -- Give the item to each online player in the group
        for _, player_name in ipairs(online_players) do
            local inv = minetest.get_inventory({type="player", name=player_name})
            if inv and inv:room_for_item("main", ItemStack(itemname.." "..count)) then
                inv:add_item("main", ItemStack(itemname.." "..count))
            end
        end

        log_action("givegroup success", name, string.format("Gave %dx %s to %d online players in group '%s'", 
            count, itemname, #online_players, groupname))
        return true, string.format("Gave %dx %s to %d online players", count, itemname, #online_players)
    end
})

-- Register the /groupmsg command
minetest.register_chatcommand("groupmsg", {
    description = "Send a private message to all online users in a group",
    params = "<groupname> <message>",
    privs = {},  -- No special privileges required
    func = function(name, param)
        -- Split first word (groupname) from the rest (message)
        local groupname, message = param:match("^(%S+)%s+(.+)$")
        
        if not groupname or not message then
            return false, "Usage: /groupmsg <groupname> <message>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Check if user is in the group or is an admin
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local is_member = false
        for _, member in ipairs(groups[groupname]) do
            if member == name then
                is_member = true
                break
            end
        end

        if not (is_admin or is_member) then
            return false, "You must be a member of the group to send messages to its members"
        end

        -- Get online players in the group
        local online_players = {}
        for _, player in ipairs(minetest.get_connected_players()) do
            local player_name = player:get_player_name()
            for _, member in ipairs(groups[groupname]) do
                if player_name == member then
                    table.insert(online_players, player_name)
                    break
                end
            end
        end

        if #online_players == 0 then
            return false, "No online users found in group '"..groupname.."'"
        end

        -- Send message to each online player
        for _, player_name in ipairs(online_players) do
            minetest.chat_send_player(player_name, "Message from "..name..": "..message)
        end

        return true, "Message sent to online users: "..table.concat(online_players, ", ")
    end
})

-- LOCATION COMMANDS
-- Register the /setloc command
minetest.register_chatcommand("setloc", {
    description = "Set a teleport location with optional protection and HUD",
    params = "[pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number] [HUD=on|off]",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        -- Get stored locations first
        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
        
        -- Get current waypoints to check for name conflicts
        local waypoints = integration.get_unified_inventory_waypoints(name)
        
        local params = {}
        for param in param:gmatch("%S+") do
            table.insert(params, param)
        end

        if #params < 1 then
            return false, "Usage: /setloc [pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number] [HUD=on|off]"
        end

        local pos
        local param_offset = 0

        -- Check if first parameter is a position
        if minetest.string_to_pos(params[1]) then
            pos = minetest.string_to_pos(params[1])
            param_offset = 1
        else
            -- Use current position
            local player = minetest.get_player_by_name(name)
            if not player then
                return false, "Player not found"
            end
            pos = player:get_pos()
            param_offset = 0
        end

        -- Improved parameter parsing: collect name until first key=value, then parse key=val pairs
        local name_parts = {}
        local param_map = {}
        local found_param = false
        for _, token in ipairs(params) do
            if not found_param and token:find("^") then
                local k, v = token:match("^(%w+)%=(.+)$")
                if k and v then
                    found_param = true
                    param_map[k:lower()] = v:lower()
                else
                    table.insert(name_parts, token)
                end
            elseif found_param then
                local k, v = token:match("^(%w+)%=(.+)$")
                if k and v then
                    param_map[k:lower()] = v:lower()
                else
                    minetest.log("warning", "[teleport_plus] Ignored unrecognized parameter: "..token)
                end
            else
                table.insert(name_parts, token)
            end
        end
        local loc_name = table.concat(name_parts, " "):gsub("%s+$", "")
        if not loc_name or loc_name == "" then
            return false, "Location name is required"
        end

        -- Check for name conflicts with waypoints
        for wp_name, _ in pairs(waypoints) do
            if wp_name:lower() == loc_name:lower() then
                return false, "Location name conflicts with an existing waypoint"
            end
        end

        -- Check for 'home' location
        if loc_name:lower() == "home" then
            local has_home_priv = minetest.check_player_privs(name, {home = true})
            if has_home_priv then
                -- Check if trying to set home at different location
                if minetest.string_to_pos(params[1]) then
                    return false, "Home can only be set at your current location. Use /sethome to set your home"
                end
                -- If any additional parameters were provided
                if #params > (1 + param_offset) then
                    return false, "Use /sethome to set your home location"
                end

                -- Try setting home in both systems: Luanti and unified_inventory
                local success = false
                local unified_set, _ = integration.set_home_position(name, pos)
                local luanti_set = false

                if minetest.registered_chatcommands["sethome"] then
                    minetest.registered_chatcommands["sethome"].func(name, "")
                    luanti_set = true
                end

                if unified_set or luanti_set then
                    return true, string.format("Home set at %d,%d,%d", 
                        math.floor(pos.x),
                        math.floor(pos.y),
                        math.floor(pos.z))
                else
                    return false, "Home system is not available"
                end
            else
                return false, "You don't have permission to set 'home' location"
            end
        end

        -- Check if position is valid and safe
        local valid_pos, pos_msg = integration.is_valid_position(pos)
        if not valid_pos then
            return false, pos_msg
        end

        local safe_pos, safety_msg = integration.is_safe_position(pos)
        if not safe_pos then
            return false, safety_msg
        end

        -- Parse parameters
        local pvp = true
        local nobuild = false
        local radius = 5
        local show_hud = true -- Default HUD to on
        if param_map["pvp"] then
            if param_map["pvp"] == "on" then
                pvp = true
            elseif param_map["pvp"] == "off" then
                pvp = false
            else
                return false, "Invalid pvp value. Use 'on' or 'off'"
            end
        end
        if param_map["nobuild"] then
            if param_map["nobuild"] == "on" then
                nobuild = true
            elseif param_map["nobuild"] == "off" then
                nobuild = false
            else
                return false, "Invalid nobuild value. Use 'on' or 'off'"
            end
        end
        if param_map["radius"] then
            radius = tonumber(param_map["radius"]) or 5
            if radius > 30 then radius = 30 end
            if radius < 0 then radius = 0 end
        end
        if param_map["hud"] then
            if param_map["hud"] == "on" then
                show_hud = true
            elseif param_map["hud"] == "off" then
                show_hud = false
            else
                return false, "Invalid HUD value. Use 'on' or 'off'"
            end
        end

        minetest.log("action", string.format("[teleport_plus] /setloc parsed params: name='%s', pvp=%s, nobuild=%s, radius=%d", 
            loc_name, tostring(pvp), tostring(nobuild), radius))        -- Handle area protection changes
        local area_id = nil
        local existing_location = locations[loc_name]
        
        -- If location exists and has an area, check if we need to remove it
        if existing_location and existing_location.area_id then
            if not nobuild or -- Protection turned off
               pos.x ~= existing_location.pos.x or -- Position changed
               pos.y ~= existing_location.pos.y or
               pos.z ~= existing_location.pos.z or
               radius ~= existing_location.radius then -- Radius changed
                minetest.log("info", "[teleport_plus] Removing old area due to changes")
                integration.remove_location_protection(existing_location.area_id, name)
            end
        end
        
        -- Create or update area if protection is enabled
        if nobuild then
            minetest.log("info", "[teleport_plus] nobuild is true, checking if Areas mod is available...")
            if integration.has_areas() then
                minetest.log("info", "[teleport_plus] Areas mod is available, attempting to create protection...")
                local success, id = integration.protect_location(loc_name, pos, radius, name)
                if success then
                    area_id = id
                    minetest.log("action", "[teleport_plus] Successfully created area " .. id)
                else
                    minetest.log("error", "[teleport_plus] Failed to create area protection")
                    return false, "Failed to create protected area"
                end
            else
                minetest.log("warning", "[teleport_plus] Areas mod not available, using fallback protection")
            end
        else
            minetest.log("info", "[teleport_plus] nobuild is false, skipping area protection")
        end

        -- Store location with correct values (always set booleans)
        locations[loc_name] = {
            pos = pos,
            pvp = pvp == true,
            nobuild = nobuild == true,
            radius = radius,
            owner = name,
            area_id = area_id,
            show_hud = show_hud == true
        }
        storage:set_string("teleport_locations", minetest.serialize(locations))

        -- Update HUD for all players
        for _, player in ipairs(minetest.get_connected_players()) do
            update_location_hud(player:get_player_name())
        end

        -- Modify the final success message
        return true, string.format(
            "Location '%s' set at %d,%d,%d with radius=%d%s, pvp=%s, nobuild=%s, HUD=%s",
            loc_name,
            math.floor(pos.x),
            math.floor(pos.y),
            math.floor(pos.z),
            radius,
            radius == 30 and " (max radius 30)" or "",
            pvp and "on" or "off",
            nobuild and "on" or "off",
            show_hud and "on" or "off"
        )
    end
})

-- Register the /listloc command
minetest.register_chatcommand("listloc", {
    description = "List all teleport locations and waypoints",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        -- Get stored locations
        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
        
        -- Always get fresh waypoint data
        local waypoints = integration.get_unified_inventory_waypoints(name)
        
        -- Merge locations with fresh waypoints
        for wp_name, wp_data in pairs(waypoints) do
            locations["wp_" .. wp_name] = wp_data
        end
        
        if next(locations) == nil then
            return false, "No locations available"
        end

        local location_list = {}
        for loc_name, data in pairs(locations) do
            local prefix = data.is_waypoint and "[WP] " or ""
            local flags = {}
            if not data.is_waypoint then
                if data.nobuild then table.insert(flags, "no-build") end
                if not data.pvp then table.insert(flags, "no-pvp") end
                if data.show_hud then table.insert(flags, "hud") end
            end
            local flags_str = #flags > 0 and " (" .. table.concat(flags, ", ") .. ")" or ""
            
            table.insert(location_list, string.format("%s%s (%d,%d,%d)%s", 
                prefix,
                loc_name:gsub("^wp_", ""),  -- Remove wp_ prefix for display
                math.floor(data.pos.x),
                math.floor(data.pos.y),
                math.floor(data.pos.z),
                flags_str))
        end
        
        table.sort(location_list)  -- Sort locations alphabetically
        return true, "Available locations: " .. table.concat(location_list, ", ")
    end
})

-- Register the /delloc command
minetest.register_chatcommand("delloc", {
    description = "Delete a teleport location",
    params = "<name>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local loc_name = param:trim()
        if loc_name == "" then
            return false, "Usage: /delloc <name>"
        end

        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}

        -- Check if location exists
        if not locations[loc_name] then
            return false, "Location '"..loc_name.."' does not exist"
        end

        local location = locations[loc_name]

        -- Check if attempting to delete a waypoint
        local waypoints = integration.get_unified_inventory_waypoints(name)
        for wp_name, _ in pairs(waypoints) do
            if wp_name:lower() == loc_name:lower() then
                return false, "Cannot delete waypoint '"..loc_name.."'. Use Unified Inventory to manage waypoints"
            end
        end

        -- Remove area protection if it exists
        if location.area_id then
            local removed = integration.remove_location_protection(location.area_id)
            if not removed then
                minetest.log("warning", "[teleport_plus] Failed to remove area protection for " .. loc_name)
            end
        end

        locations[loc_name] = nil
        storage:set_string("teleport_locations", minetest.serialize(locations))

        -- Update HUD for all players after location deletion
        for _, player in ipairs(minetest.get_connected_players()) do
            update_location_hud(player:get_player_name())
        end

        log_action("Location Deleted", name, "Location: " .. loc_name)
        return true, "Deleted location '"..loc_name.."'"
    end
})

-- Register the /tp command
minetest.register_chatcommand("tp", {
    description = "Teleport players to a location",
    params = "<target> <location>",
    privs = {},  -- No special privileges required for basic use
    func = function(name, param)
        -- Parse parameters - support both quoted and unquoted names
        local target_str, loc_name
        
        -- First try to parse as quoted strings
        if param:match('^".-"') or param:match("^'.-'") then
            target_str = param:match('^"([^"]+)"') or param:match("^'([^']+')")
            local rest = param:sub((target_str and #target_str + 3) or 0):match("^%s*(.+)$")
            if rest then
                loc_name = rest:match('^"([^"]+)"$') or rest:match("^'([^']+)'$") or rest:match("^(%S.*)$")
            end
        else
            -- If no quotes, try simple space split
            target_str, loc_name = param:match("^(%S+)%s+(%S.*)$")
        end

        if not target_str or not loc_name then
            return false, "Usage: /tp <target> <location>"
        end

        -- Validate target permissions
        local targets = teleport_helpers.parse_targets(target_str, storage, minetest)
        local valid, err = validate_target_permissions(name, targets, target_str)
        if not valid then
            return false, err
        end

        -- Validate location permissions using the command caller's permissions
        local loc_valid, loc_err = validate_location_permissions(name, targets, loc_name)
        if not loc_valid then
            return false, loc_err
        end

        -- Get and validate destination using caller's permissions
        local dest_pos = get_location_pos(loc_name, name)
        if not dest_pos then
            -- Don't add quotes to the error message
            return false, "Location "..loc_name.." does not exist"
        end

        -- Check if destination is safe
        local safe_pos, safety_msg = integration.is_safe_position(dest_pos)
        if not safe_pos then
            return false, "Destination is not safe: "..safety_msg
        end

        -- Get online players and track invalid/offline players
        local online_players, offline_players, invalid_players = get_online_players(targets, name)

        if #online_players == 0 then
            return false, "No valid online players to teleport"
        end

        -- Calculate grid positions for all players
        local safe_positions, unsafe_spots = get_safe_grid_positions(dest_pos, #online_players)
        
        if #safe_positions == 0 then
            return false, "No safe positions available around destination"
        end

        -- Teleport each online player
        local teleported = {}
        local unsafe_players = {}
        local pos_index = 1

        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            if player then
                -- Only store the original position if not already stored
                if not teleport_history[player_name] then
                    teleport_history[player_name] = player:get_pos()
                end
            end
        end

        -- Try to find a safe position for each player
        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            if player then
                -- Store current position in history
                local current_pos = player:get_pos()
                if not teleport_history[player_name] then
                    teleport_history[player_name] = {}
                end
                table.insert(teleport_history[player_name], current_pos)
                
                -- Try to find a safe position
                local found_safe_pos = false
                while pos_index <= #safe_positions do
                    local target_pos = safe_positions[pos_index]
                    -- Double check if position is still safe
                    local is_safe, _ = integration.is_safe_position(target_pos)
                    if is_safe then
                        player:set_pos(target_pos)
                        table.insert(teleported, player_name)
                        found_safe_pos = true
                        pos_index = pos_index + 1
                        break
                    end
                    pos_index = pos_index + 1 -- Try next position
                end
                
                if not found_safe_pos then
                    table.insert(unsafe_players, player_name)
                end
            end
        end        -- Prepare result message
        local message = "Teleport results:\n"
        if #teleported > 0 then
            message = message.."✓ Successfully teleported: "..table.concat(teleported, ", ").."\n"
        end
        if #unsafe_players > 0 then
            message = message.."⚠ Could not find safe positions for: "..table.concat(unsafe_players, ", ").."\n"
        end
        if #offline_players > 0 then
            message = message.."ⓘ Offline players skipped: "..table.concat(offline_players, ", ").."\n"
        end
        if #invalid_players > 0 then
            message = message.."✗ Invalid player names: "..table.concat(invalid_players, ", ").."\n"
        end
        if #unsafe_spots > 0 then
            message = message.."⚠ "..#unsafe_spots.." grid positions were unsafe and skipped"
        end

        return true, message
    end
})

-- Register the /tprestore command
minetest.register_chatcommand("tprestore", {
    description = "Return players to their previous location",
    params = "<targets>",
    privs = {},  -- No special privileges required for basic use
    func = function(name, param)
        if not param or param:trim() == "" then
            return false, "Usage: /tprestore <targets> (targets can be: me, groupname, or player name)"
        end

        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local targets = teleport_helpers.parse_targets(param:trim(), storage, minetest)
        if not targets then
            return false, "Invalid targets."
        end

        -- Permission check: allow self, group members, or admin
        if not is_admin then
            local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
            local user_groups = {}
            for group_name, members in pairs(groups) do
                for _, member in ipairs(members) do
                    if member == name then
                        user_groups[group_name] = members
                        break
                    end
                end
            end
            if targets.type == "player" then
                if not (targets.players[1] == "me" or targets.players[1] == name) then
                    local allowed = false
                    for _, members in pairs(user_groups) do
                        for _, member in ipairs(members) do
                            if member == targets.players[1] then
                                allowed = true
                                break
                            end
                        end
                        if allowed then break end
                    end
                    if not allowed then
                        return false, "You can only restore yourself or members of your groups."
                    end
                end
            elseif targets.type == "group" then
                if not user_groups[ param:trim() ] then
                    return false, "You can only restore groups that you are a member of."
                end
            elseif targets.type == "all" then
                return false, "Only admins can restore all players."
            end
        end

        -- Get online players and track invalid/offline players
        local online_players, offline_players, invalid_players = get_online_players(targets, name)

        if #online_players == 0 then
            return false, "No valid online players to restore"
        end

        -- Restore each online player
        local restored = {}
        local no_history = {}
        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            local last_pos = teleport_history[player_name]
            if player and last_pos then
                local safe_pos, _ = integration.is_safe_position(last_pos)
                if safe_pos then
                    player:set_pos(last_pos)
                    table.insert(restored, player_name)
                    teleport_history[player_name] = nil
                else
                    table.insert(no_history, player_name.." (unsafe return position)")
                end
            else
                table.insert(no_history, player_name)
            end
        end

        -- Prepare result message
        local result_msg = string.format("Restored %d player(s) to previous location", #restored)
        -- Add warnings about offline/invalid/no-history players if any
        local warnings = {}
        if #no_history > 0 then
            table.insert(warnings, #no_history.." player(s) with no valid history: "..table.concat(no_history, ", "))
        end
        if #offline_players > 0 then
            table.insert(warnings, #offline_players.." player(s) offline: "..table.concat(offline_players, ", "))
        end
        if #invalid_players > 0 then
            table.insert(warnings, #invalid_players.." invalid player(s): "..table.concat(invalid_players, ", "))
        end
        if #warnings > 0 then
            result_msg = result_msg .. " ("..table.concat(warnings, "; ")..")"
        end
        log_action("Teleport Restore", name, string.format("Restored %s to previous locations", table.concat(restored, ", ")))
        return true, result_msg
    end
})

-- SCHEDULE COMMANDS
-- Register the /tpschedule command
minetest.register_chatcommand("tpschedule", {
    description = "Schedule teleportation of players",
    params = "<targets> <location> <day1,day2> <HH:MM> [name=<namestring>] [repeat=on/off]",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        -- First extract custom name parameter if it exists (can be quoted)
        local name_param
        param = param:gsub('name="([^"]+)"', function(p) name_param = p; return "" end)
        param = param:gsub("name='([^']+)'", function(p) name_param = p; return "" end)
        param = param:gsub('name=([^%s]+)', function(p) name_param = p; return "" end)
        param = param:gsub("%s+", " "):trim()

        -- Parse target - support for quoted names
        local target_str, rest
        if param:match('^".-"') or param:match("^'.-'") then
            target_str = param:match('^"([^"]+)"') or param:match("^'([^']+')")
            rest = param:sub(#target_str + 3):match("^%s*(.+)$")
        else
            target_str, rest = param:match("^(%S+)%s+(.+)$")
        end

        if not target_str or not rest then
            return false, "Usage: /tpschedule <targets> <location> [day1,day2] <HH:MM> [name=<namestring>] [repeat=on/off]"
        end        -- Robust parsing for location
        local loc_name, remaining

        -- Helper function to extract quoted or unquoted string and return remaining text
        local function extract_quoted_or_unquoted(input)
            input = input:trim()
            local first_char = input:sub(1,1)
            if first_char == '"' or first_char == "'" then
                local pattern = "^" .. first_char .. "(.-)" .. first_char .. "%s*(.*)$"
                local quoted, rem = input:match(pattern)
                return quoted, rem
            else
                local unquoted, rem = input:match("^(%S+)%s*(.*)$")
                return unquoted, rem
            end
        end

        -- Extract location and remaining parameters correctly
        loc_name, remaining = extract_quoted_or_unquoted(rest)

        if not loc_name or not remaining then
            return false, "Invalid location name or missing parameters"
        end

        -- Extract time and optional params
        local time_str = remaining:match("(%d+:%d+)")
        if not time_str then
            return false, "Time format must be HH:MM in 24-hour format"
        end

        -- Extract days (text before the time)
        local days_str = remaining:match("^(.-)%d+:%d+") or ""
        days_str = days_str:gsub("^%s+", ""):gsub("%s+$", "")

        -- Extract repeat parameter
        local repeat_str = remaining:match("repeat=(%w+)")
        local repeat_schedule = repeat_str and repeat_str:match("repeat=(%w+)") == "on"

        -- Parse and validate targets first
        local targets = teleport_helpers.parse_targets(target_str, storage, minetest)
        local targets_valid, targets_err = schedule_module.validate_targets(name, target_str)
        if not targets_valid then
            return false, targets_err
        end
        
        -- Validate location
        local loc_valid, loc_err = schedule_module.validate_location(name, loc_name)
        if not loc_valid then
            return false, loc_err
        end

        -- Check if destination is safe
        local dest_pos = get_location_pos(loc_name, name)
        local safe_pos, safety_msg = integration.is_safe_position(dest_pos)
        if not safe_pos then
            return false, "Destination is not safe: "..safety_msg
        end        -- Parse and validate time
        local minutes = schedule_module.time_to_minutes(time_str)
        if not minutes then
            return false, "Invalid time format. Use HH:MM in 24-hour format (00:00 - 23:59)"
        end
        
        -- Parse and validate days
        local days = schedule_module.parse_days(days_str)
        if not days then
            return false, "Invalid days. Use day names separated by commas (e.g., mon,wed,fri)"
        end
          -- Generate or use provided schedule name
        local schedule_name
        if name_param then            -- Validate custom name doesn't already exist
            if schedule_module.schedules[name_param] then
                return false, "A schedule with the name '"..name_param.."' already exists"
            end
            schedule_name = name_param
        else
            schedule_name = schedule_module.get_next_schedule_name()
        end        -- Create or update schedule
        schedule_module.schedules[schedule_name] = {
            target = strip_quotes(target_str):trim(),  -- Always store target without quotes
            target_type = targets.type,
            location = strip_quotes(loc_name):trim(),  -- Always store location without quotes (CRITICAL)
            time = minutes,
            days = days,
            repeat_schedule = repeat_schedule,
            created_by = name,
            created_at = os.time(),
            last_run = nil
        }
        
        -- Properly persist immediately
        schedule_module.save_schedules()
          -- Create success message
        local days_description
        -- Always check the actual days array since it might be all days even with a days_str
        local days_sorted = {}
        for _, day in ipairs(days) do
            table.insert(days_sorted, day)
        end
        table.sort(days_sorted)
        local sorted_days = table.concat(days_sorted)
        
        if sorted_days == "12345" then
            days_description = "weekdays"
        elseif sorted_days == "67" then
            days_description = "weekends"
        elseif sorted_days == "1234567" then
            days_description = "all days"
        else
            -- If days were specified, use the original days_str
            days_description = days_str ~= "" and days_str or "all days"
        end        local repeat_text = repeat_schedule and "repeating" or "one-time"
        -- Format time string to ensure 24-hour format
        local formatted_time = string.format("%02d:%02d", 
            math.floor(minutes / 60),
            minutes % 60)
        return true, string.format(
            "Created %s schedule '%s' to teleport %s to %s at %s on %s",
            repeat_text,
            schedule_name,
            target_str,
            loc_name,
            formatted_time,
            days_description
        )
    end
})

-- Register the /delschedule command
minetest.register_chatcommand("delschedule", {
    description = "Delete a teleport schedule",
    params = "<name>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local schedules = schedule_module.reload()
        local schedule_name = param:match("^%s*(.-)%s*$")
        if not schedule_name or schedule_name == "" then
            return false, "Usage: /delschedule <name>"
        end
        if not schedules[schedule_name] then
            return false, "Schedule '"..schedule_name.."' does not exist"
        end
        schedules[schedule_name] = nil
        schedule_module.save_schedules()
        return true, "Deleted schedule '"..schedule_name.."'"
    end
})

-- Register the /listschedules command
minetest.register_chatcommand("listschedules", {
    description = "List all teleport schedules",
    privs = { teleport_plus_admin = true },    
    func = function(name, param)        
        if not next(schedule_module.schedules) then
            return false, "No schedules exist"
        end
          
        local schedule_list = {}
        for schedule_name, schedule in pairs(schedule_module.schedules) do
            -- Format time string ensuring 24-hour format
            local hours = math.floor(schedule.time / 60)
            local minutes = schedule.time % 60
            local time_str = string.format("%02d:%02d", hours, minutes)
            
            -- Get day names for display
            local day_names = {
                [1] = "Monday", [2] = "Tuesday", [3] = "Wednesday",
                [4] = "Thursday", [5] = "Friday", [6] = "Saturday", [7] = "Sunday"
            }
            
            -- Sort days for pattern detection
            local days_sorted = {}
            for _, day in ipairs(schedule.days) do
                table.insert(days_sorted, day)
            end
            table.sort(days_sorted)
            local sorted_days = table.concat(days_sorted)
            
            -- Format days string based on patterns
            local days_str
            if #days_sorted == 7 then
                days_str = "every day"
            elseif sorted_days == "12345" then
                days_str = "weekdays"
            elseif sorted_days == "67" then
                days_str = "weekends"
            else
                -- List specific days
                local days = {}
                for _, day in ipairs(schedule.days) do
                    table.insert(days, day_names[day])
                end
                days_str = table.concat(days, ", ")
            end
            
            -- Format schedule entry
            table.insert(schedule_list, string.format(
                "%s: %s → %s at %s on %s (%s)",
                schedule_name,
                schedule.target,
                schedule.location,
                time_str,
                days_str,
                schedule.repeat_schedule and "repeating" or "one-time"
            ))
        end
        
        table.sort(schedule_list)
        return true, "Schedules:\n" .. table.concat(schedule_list, "\n")
    end
})

-- Register the /servertime command
minetest.register_chatcommand("servertime", {
    description = "Show current server time and day",
    func = function(name, param)
        local current_time = os.time()
        local time_table = os.date("*t", current_time)
        
        -- Convert wday (1=Sunday) to our format (1=Monday)
        local current_wday = time_table.wday == 1 and 7 or time_table.wday - 1
        
        -- Get day name
        local day_names = {
            [1] = "Monday",
            [2] = "Tuesday",
            [3] = "Wednesday",
            [4] = "Thursday",
            [5] = "Friday",
            [6] = "Saturday",
            [7] = "Sunday"
        }
        
        local day_name = day_names[current_wday]
        local time_str = string.format("%02d:%02d", time_table.hour, time_table.min)
        
        return true, string.format("Current server time: %s (%s)", time_str, day_name)
    end
})

-- Register the /schedules command (alias for /listschedules)
minetest.register_chatcommand("schedules", {
    description = "List all teleport schedules",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local schedules = schedule_module.reload()
        if not next(schedules) then
            return false, "No schedules exist"
        end
        
        local schedule_list = {}
        for schedule_name, schedule in pairs(schedules) do
            local hours = math.floor(schedule.time / 60)
            local minutes = schedule.time % 60
            local time_str = string.format("%02d:%02d", hours, minutes)
            
            -- Get day names for display
            local day_names = {
                [1] = "Monday", [2] = "Tuesday", [3] = "Wednesday",
                [4] = "Thursday", [5] = "Friday", [6] = "Saturday", [7] = "Sunday"
            }
            
            -- Sort days for pattern detection
            local days_sorted = {}
            for _, day in ipairs(schedule.days) do
                table.insert(days_sorted, day)
            end
            table.sort(days_sorted)
            local sorted_days = table.concat(days_sorted)
            
            -- Format days string based on patterns
            local days_str
            if #days_sorted == 7 then
                days_str = "every day"
            elseif sorted_days == "12345" then
                days_str = "weekdays"
            elseif sorted_days == "67" then
                days_str = "weekends"
            else
                -- List specific days
                local days = {}
                for _, day in ipairs(schedule.days) do
                    table.insert(days, day_names[day])
                end
                days_str = table.concat(days, ", ")
            end
            
            table.insert(schedule_list, string.format(
                "%s: %s → %s at %s on %s (%s)",
                schedule_name,
                schedule.target,
                schedule.location,
                time_str,
                days_str,
                schedule.repeat_schedule and "repeating" or "one-time"
            ))
        end
        
        table.sort(schedule_list)
        return true, "Schedules:\n" .. table.concat(schedule_list, "\n")
    end
})

-- Helper function to get groups a user belongs to
local function get_user_groups(name, groups)
    local user_groups = {}
    for group_name, members in pairs(groups) do
        for _, member in ipairs(members) do
            if member == name then
                user_groups[group_name] = members
                break
            end
        end
    end
    return user_groups
end

-- Register the /listgroups command
minetest.register_chatcommand("listgroups", {
    description = "List available teleport groups (all groups for admins, only your groups for regular users)",
    privs = {},  -- No special privileges required
    func = function(name, param)
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        
        if next(groups) == nil then
            return false, "No groups available"
        end

        local group_list = {}
        for groupname, members in pairs(groups) do
            -- For regular users, only show groups they belong to
            local is_member = false
            if not is_admin then
                for _, member in ipairs(members) do
                    if member == name then
                        is_member = true
                        break
                    end
                end
            end
            
            if is_admin or is_member then
                table.insert(group_list, string.format("%s (%d members)", 
                    groupname, 
                    #members))
            end
        end
        
        if #group_list == 0 then
            return false, "You don't belong to any groups"
        end
        
        table.sort(group_list)  -- Sort groups alphabetically
        return true, "Available groups: " .. table.concat(group_list, ", ")
    end
})

-- Register the /group command
minetest.register_chatcommand("group", {
    description = "List users in a teleport group",
    params = "<groupname>",
    privs = {},  -- No special privileges required
    func = function(name, param)
        local groupname = param:trim()
        if groupname == "" then
            return false, "Usage: /group <groupname>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Check if user is in the group or is an admin
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local is_member = false
        for _, member in ipairs(groups[groupname]) do
            if member == name then
                is_member = true
                break
            end
        end

        if not (is_admin or is_member) then
            return false, "You must be a member of the group to view its members"
        end

        local member_list = table.concat(groups[groupname], ", ")
        return true, "Members in group '"..groupname.."': "..member_list
    end
})

-- Register the /givegroup command
minetest.register_chatcommand("givegroup", {
    description = "Give an item to all online users in a group (max 99)",
    params = "<groupname> <itemname> [count]",
    privs = { give = true },
    func = function(name, param)
        local params = param:split(" ")
        if #params < 2 then
            return false, "Usage: /givegroup <groupname> <itemname> [count]"
        end

        local groupname = params[1]
        local itemname = params[2]
        local count = tonumber(params[3]) or 1
        count = math.min(count, 99)

        if not minetest.registered_items[itemname] then
            log_action("givegroup failed", name, "Invalid item '"..itemname.."'")
            return false, "Item '"..itemname.."' does not exist"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            log_action("givegroup failed", name, "Group '"..groupname.."' does not exist")
            return false, "Group '"..groupname.."' does not exist"
        end

        local online_players = {}
        for _, player in ipairs(minetest.get_connected_players()) do
            local player_name = player:get_player_name()
            for _, member in ipairs(groups[groupname]) do
                if player_name == member then
                    table.insert(online_players, player_name)
                    break
                end
            end
        end

        if #online_players == 0 then
            log_action("givegroup failed", name, "No online users in group '"..groupname.."'")
            return false, "No online users found in group '"..groupname.."'"
        end

        -- Give the item to each online player in the group
        for _, player_name in ipairs(online_players) do
            local inv = minetest.get_inventory({type="player", name=player_name})
            if inv and inv:room_for_item("main", ItemStack(itemname.." "..count)) then
                inv:add_item("main", ItemStack(itemname.." "..count))
            end
        end

        log_action("givegroup success", name, string.format("Gave %dx %s to %d online players in group '%s'", 
            count, itemname, #online_players, groupname))
        return true, string.format("Gave %dx %s to %d online players", count, itemname, #online_players)
    end
})

-- Register the /groupmsg command
minetest.register_chatcommand("groupmsg", {
    description = "Send a private message to all online users in a group",
    params = "<groupname> <message>",
    privs = {},  -- No special privileges required
    func = function(name, param)
        -- Split first word (groupname) from the rest (message)
        local groupname, message = param:match("^(%S+)%s+(.+)$")
        
        if not groupname or not message then
            return false, "Usage: /groupmsg <groupname> <message>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        -- Check if user is in the group or is an admin
        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local is_member = false
        for _, member in ipairs(groups[groupname]) do
            if member == name then
                is_member = true
                break
            end
        end

        if not (is_admin or is_member) then
            return false, "You must be a member of the group to send messages to its members"
        end

        -- Get online players in the group
        local online_players = {}
        for _, player in ipairs(minetest.get_connected_players()) do
            local player_name = player:get_player_name()
            for _, member in ipairs(groups[groupname]) do
                if player_name == member then
                    table.insert(online_players, player_name)
                    break
                end
            end
        end

        if #online_players == 0 then
            return false, "No online users found in group '"..groupname.."'"
        end

        -- Send message to each online player
        for _, player_name in ipairs(online_players) do
            minetest.chat_send_player(player_name, "Message from "..name..": "..message)
        end

        return true, "Message sent to online users: "..table.concat(online_players, ", ")
    end
})

-- LOCATION COMMANDS
-- Register the /setloc command
minetest.register_chatcommand("setloc", {
    description = "Set a teleport location with optional protection and HUD",
    params = "[pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number] [HUD=on|off]",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        -- Get stored locations first
        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
        
        -- Get current waypoints to check for name conflicts
        local waypoints = integration.get_unified_inventory_waypoints(name)
        
        local params = {}
        for param in param:gmatch("%S+") do
            table.insert(params, param)
        end

        if #params < 1 then
            return false, "Usage: /setloc [pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number] [HUD=on|off]"
        end

        local pos
        local param_offset = 0

        -- Check if first parameter is a position
        if minetest.string_to_pos(params[1]) then
            pos = minetest.string_to_pos(params[1])
            param_offset = 1
        else
            -- Use current position
            local player = minetest.get_player_by_name(name)
            if not player then
                return false, "Player not found"
            end
            pos = player:get_pos()
            param_offset = 0
        end

        -- Improved parameter parsing: collect name until first key=value, then parse key=val pairs
        local name_parts = {}
        local param_map = {}
        local found_param = false
        for _, token in ipairs(params) do
            if not found_param and token:find("^") then
                local k, v = token:match("^(%w+)%=(.+)$")
                if k and v then
                    found_param = true
                    param_map[k:lower()] = v:lower()
                else
                    table.insert(name_parts, token)
                end
            elseif found_param then
                local k, v = token:match("^(%w+)%=(.+)$")
                if k and v then
                    param_map[k:lower()] = v:lower()
                else
                    minetest.log("warning", "[teleport_plus] Ignored unrecognized parameter: "..token)
                end
            else
                table.insert(name_parts, token)
            end
        end
        local loc_name = table.concat(name_parts, " "):gsub("%s+$", "")
        if not loc_name or loc_name == "" then
            return false, "Location name is required"
        end

        -- Check for name conflicts with waypoints
        for wp_name, _ in pairs(waypoints) do
            if wp_name:lower() == loc_name:lower() then
                return false, "Location name conflicts with an existing waypoint"
            end
        end

        -- Check for 'home' location
        if loc_name:lower() == "home" then
            local has_home_priv = minetest.check_player_privs(name, {home = true})
            if has_home_priv then
                -- Check if trying to set home at different location
                if minetest.string_to_pos(params[1]) then
                    return false, "Home can only be set at your current location. Use /sethome to set your home"
                end
                -- If any additional parameters were provided
                if #params > (1 + param_offset) then
                    return false, "Use /sethome to set your home location"
                end

                -- Try setting home in both systems: Luanti and unified_inventory
                local success = false
                local unified_set, _ = integration.set_home_position(name, pos)
                local luanti_set = false

                if minetest.registered_chatcommands["sethome"] then
                    minetest.registered_chatcommands["sethome"].func(name, "")
                    luanti_set = true
                end

                if unified_set or luanti_set then
                    return true, string.format("Home set at %d,%d,%d", 
                        math.floor(pos.x),
                        math.floor(pos.y),
                        math.floor(pos.z))
                else
                    return false, "Home system is not available"
                end
            else
                return false, "You don't have permission to set 'home' location"
            end
        end

        -- Check if position is valid and safe
        local valid_pos, pos_msg = integration.is_valid_position(pos)
        if not valid_pos then
            return false, pos_msg
        end

        local safe_pos, safety_msg = integration.is_safe_position(pos)
        if not safe_pos then
            return false, safety_msg
        end

        -- Parse parameters
        local pvp = true
        local nobuild = false
        local radius = 5
        local show_hud = true -- Default HUD to on
        if param_map["pvp"] then
            if param_map["pvp"] == "on" then
                pvp = true
            elseif param_map["pvp"] == "off" then
                pvp = false
            else
                return false, "Invalid pvp value. Use 'on' or 'off'"
            end
        end
        if param_map["nobuild"] then
            if param_map["nobuild"] == "on" then
                nobuild = true
            elseif param_map["nobuild"] == "off" then
                nobuild = false
            else
                return false, "Invalid nobuild value. Use 'on' or 'off'"
            end
        end
        if param_map["radius"] then
            radius = tonumber(param_map["radius"]) or 5
            if radius > 30 then radius = 30 end
            if radius < 0 then radius = 0 end
        end
        if param_map["hud"] then
            if param_map["hud"] == "on" then
                show_hud = true
            elseif param_map["hud"] == "off" then
                show_hud = false
            else
                return false, "Invalid HUD value. Use 'on' or 'off'"
            end
        end

        minetest.log("action", string.format("[teleport_plus] /setloc parsed params: name='%s', pvp=%s, nobuild=%s, radius=%d", 
            loc_name, tostring(pvp), tostring(nobuild), radius))        -- Handle area protection changes
        local area_id = nil
        local existing_location = locations[loc_name]
        
        -- If location exists and has an area, check if we need to remove it
        if existing_location and existing_location.area_id then
            if not nobuild or -- Protection turned off
               pos.x ~= existing_location.pos.x or -- Position changed
               pos.y ~= existing_location.pos.y or
               pos.z ~= existing_location.pos.z or
               radius ~= existing_location.radius then -- Radius changed
                minetest.log("info", "[teleport_plus] Removing old area due to changes")
                integration.remove_location_protection(existing_location.area_id, name)
            end
        end
        
        -- Create or update area if protection is enabled
        if nobuild then
            minetest.log("info", "[teleport_plus] nobuild is true, checking if Areas mod is available...")
            if integration.has_areas() then
                minetest.log("info", "[teleport_plus] Areas mod is available, attempting to create protection...")
                local success, id = integration.protect_location(loc_name, pos, radius, name)
                if success then
                    area_id = id
                    minetest.log("action", "[teleport_plus] Successfully created area " .. id)
                else
                    minetest.log("error", "[teleport_plus] Failed to create area protection")
                    return false, "Failed to create protected area"
                end
            else
                minetest.log("warning", "[teleport_plus] Areas mod not available, using fallback protection")
            end
        else
            minetest.log("info", "[teleport_plus] nobuild is false, skipping area protection")
        end

        -- Store location with correct values (always set booleans)
        locations[loc_name] = {
            pos = pos,
            pvp = pvp == true,
            nobuild = nobuild == true,
            radius = radius,
            owner = name,
            area_id = area_id,
            show_hud = show_hud == true
        }
        storage:set_string("teleport_locations", minetest.serialize(locations))

        -- Update HUD for all players
        for _, player in ipairs(minetest.get_connected_players()) do
            update_location_hud(player:get_player_name())
        end

        -- Modify the final success message
        return true, string.format(
            "Location '%s' set at %d,%d,%d with radius=%d%s, pvp=%s, nobuild=%s, HUD=%s",
            loc_name,
            math.floor(pos.x),
            math.floor(pos.y),
            math.floor(pos.z),
            radius,
            radius == 30 and " (max radius 30)" or "",
            pvp and "on" or "off",
            nobuild and "on" or "off",
            show_hud and "on" or "off"
        )
    end
})

-- Register the /listloc command
minetest.register_chatcommand("listloc", {
    description = "List all teleport locations and waypoints",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        -- Get stored locations
        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
        
        -- Always get fresh waypoint data
        local waypoints = integration.get_unified_inventory_waypoints(name)
        
        -- Merge locations with fresh waypoints
        for wp_name, wp_data in pairs(waypoints) do
            locations["wp_" .. wp_name] = wp_data
        end
        
        if next(locations) == nil then
            return false, "No locations available"
        end

        local location_list = {}
        for loc_name, data in pairs(locations) do
            local prefix = data.is_waypoint and "[WP] " or ""
            local flags = {}
            if not data.is_waypoint then
                if data.nobuild then table.insert(flags, "no-build") end
                if not data.pvp then table.insert(flags, "no-pvp") end
                if data.show_hud then table.insert(flags, "hud") end
            end
            local flags_str = #flags > 0 and " (" .. table.concat(flags, ", ") .. ")" or ""
            
            table.insert(location_list, string.format("%s%s (%d,%d,%d)%s", 
                prefix,
                loc_name:gsub("^wp_", ""),  -- Remove wp_ prefix for display
                math.floor(data.pos.x),
                math.floor(data.pos.y),
                math.floor(data.pos.z),
                flags_str))
        end
        
        table.sort(location_list)  -- Sort locations alphabetically
        return true, "Available locations: " .. table.concat(location_list, ", ")
    end
})

-- Register the /delloc command
minetest.register_chatcommand("delloc", {
    description = "Delete a teleport location",
    params = "<name>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local loc_name = param:trim()
        if loc_name == "" then
            return false, "Usage: /delloc <name>"
        end

        local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}

        -- Check if location exists
        if not locations[loc_name] then
            return false, "Location '"..loc_name.."' does not exist"
        end

        local location = locations[loc_name]

        -- Check if attempting to delete a waypoint
        local waypoints = integration.get_unified_inventory_waypoints(name)
        for wp_name, _ in pairs(waypoints) do
            if wp_name:lower() == loc_name:lower() then
                return false, "Cannot delete waypoint '"..loc_name.."'. Use Unified Inventory to manage waypoints"
            end
        end

        -- Remove area protection if it exists
        if location.area_id then
            local removed = integration.remove_location_protection(location.area_id)
            if not removed then
                minetest.log("warning", "[teleport_plus] Failed to remove area protection for " .. loc_name)
            end
        end

        locations[loc_name] = nil
        storage:set_string("teleport_locations", minetest.serialize(locations))

        -- Update HUD for all players after location deletion
        for _, player in ipairs(minetest.get_connected_players()) do
            update_location_hud(player:get_player_name())
        end

        log_action("Location Deleted", name, "Location: " .. loc_name)
        return true, "Deleted location '"..loc_name.."'"
    end
})

-- Register the /tp command
minetest.register_chatcommand("tp", {
    description = "Teleport players to a location",
    params = "<target> <location>",
    privs = {},  -- No special privileges required for basic use
    func = function(name, param)
        -- Parse parameters - support both quoted and unquoted names
        local target_str, loc_name
        
        -- First try to parse as quoted strings
        if param:match('^".-"') or param:match("^'.-'") then
            target_str = param:match('^"([^"]+)"') or param:match("^'([^']+')")
            local rest = param:sub((target_str and #target_str + 3) or 0):match("^%s*(.+)$")
            if rest then
                loc_name = rest:match('^"([^"]+)"$') or rest:match("^'([^']+)'$") or rest:match("^(%S.*)$")
            end
        else
            -- If no quotes, try simple space split
            target_str, loc_name = param:match("^(%S+)%s+(%S.*)$")
        end

        if not target_str or not loc_name then
            return false, "Usage: /tp <target> <location>"
        end

        -- Validate target permissions
        local targets = teleport_helpers.parse_targets(target_str, storage, minetest)
        local valid, err = validate_target_permissions(name, targets, target_str)
        if not valid then
            return false, err
        end

        -- Validate location permissions using the command caller's permissions
        local loc_valid, loc_err = validate_location_permissions(name, targets, loc_name)
        if not loc_valid then
            return false, loc_err
        end

        -- Get and validate destination using caller's permissions
        local dest_pos = get_location_pos(loc_name, name)
        if not dest_pos then
            -- Don't add quotes to the error message
            return false, "Location "..loc_name.." does not exist"
        end

        -- Check if destination is safe
        local safe_pos, safety_msg = integration.is_safe_position(dest_pos)
        if not safe_pos then
            return false, "Destination is not safe: "..safety_msg
        end

        -- Get online players and track invalid/offline players
        local online_players, offline_players, invalid_players = get_online_players(targets, name)

        if #online_players == 0 then
            return false, "No valid online players to teleport"
        end

        -- Calculate grid positions for all players
        local safe_positions, unsafe_spots = get_safe_grid_positions(dest_pos, #online_players)
        
        if #safe_positions == 0 then
            return false, "No safe positions available around destination"
        end

        -- Teleport each online player
        local teleported = {}
        local unsafe_players = {}
        local pos_index = 1

        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            if player then
                -- Only store the original position if not already stored
                if not teleport_history[player_name] then
                    teleport_history[player_name] = player:get_pos()
                end
            end
        end

        -- Try to find a safe position for each player
        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            if player then
                -- Store current position in history
                local current_pos = player:get_pos()
                if not teleport_history[player_name] then
                    teleport_history[player_name] = {}
                end
                table.insert(teleport_history[player_name], current_pos)
                
                -- Try to find a safe position
                local found_safe_pos = false
                while pos_index <= #safe_positions do
                    local target_pos = safe_positions[pos_index]
                    -- Double check if position is still safe
                    local is_safe, _ = integration.is_safe_position(target_pos)
                    if is_safe then
                        player:set_pos(target_pos)
                        table.insert(teleported, player_name)
                        found_safe_pos = true
                        pos_index = pos_index + 1
                        break
                    end
                    pos_index = pos_index + 1 -- Try next position
                end
                
                if not found_safe_pos then
                    table.insert(unsafe_players, player_name)
                end
            end
        end        -- Prepare result message
        local message = "Teleport results:\n"
        if #teleported > 0 then
            message = message.."✓ Successfully teleported: "..table.concat(teleported, ", ").."\n"
        end
        if #unsafe_players > 0 then
            message = message.."⚠ Could not find safe positions for: "..table.concat(unsafe_players, ", ").."\n"
        end
        if #offline_players > 0 then
            message = message.."ⓘ Offline players skipped: "..table.concat(offline_players, ", ").."\n"
        end
        if #invalid_players > 0 then
            message = message.."✗ Invalid player names: "..table.concat(invalid_players, ", ").."\n"
        end
        if #unsafe_spots > 0 then
            message = message.."⚠ "..#unsafe_spots.." grid positions were unsafe and skipped"
        end

        return true, message
    end
})

-- Register the /tprestore command
minetest.register_chatcommand("tprestore", {
    description = "Return players to their previous location",
    params = "<targets>",
    privs = {},  -- No special privileges required for basic use
    func = function(name, param)
        if not param or param:trim() == "" then
            return false, "Usage: /tprestore <targets> (targets can be: me, groupname, or player name)"
        end

        local is_admin = minetest.check_player_privs(name, {teleport_plus_admin = true})
        local targets = teleport_helpers.parse_targets(param:trim(), storage, minetest)
        if not targets then
            return false, "Invalid targets."
        end

        -- Permission check: allow self, group members, or admin
        if not is_admin then
            local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
            local user_groups = {}
            for group_name, members in pairs(groups) do
                for _, member in ipairs(members) do
                    if member == name then
                        user_groups[group_name] = members
                        break
                    end
                end
            end
            if targets.type == "player" then
                if not (targets.players[1] == "me" or targets.players[1] == name) then
                    local allowed = false
                    for _, members in pairs(user_groups) do
                        for _, member in ipairs(members) do
                            if member == targets.players[1] then
                                allowed = true
                                break
                            end
                        end
                        if allowed then break end
                    end
                    if not allowed then
                        return false, "You can only restore yourself or members of your groups."
                    end
                end
            elseif targets.type == "group" then
                if not user_groups[ param:trim() ] then
                    return false, "You can only restore groups that you are a member of."
                end
            elseif targets.type == "all" then
                return false, "Only admins can restore all players."
            end
        end

        -- Get online players and track invalid/offline players
        local online_players, offline_players, invalid_players = get_online_players(targets, name)

        if #online_players == 0 then
            return false, "No valid online players to restore"
        end

        -- Restore each online player
        local restored = {}
        local no_history = {}
        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            local last_pos = teleport_history[player_name]
            if player and last_pos then
                local safe_pos, _ = integration.is_safe_position(last_pos)
                if safe_pos then
                    player:set_pos(last_pos)
                    table.insert(restored, player_name)
                    teleport_history[player_name] = nil
                else
                    table.insert(no_history, player_name.." (unsafe return position)")
                end
            else
                table.insert(no_history, player_name)
            end
        end

        -- Prepare result message
        local result_msg = string.format("Restored %d player(s) to previous location", #restored)
        -- Add warnings about offline/invalid/no-history players if any
        local warnings = {}
        if #no_history > 0 then
            table.insert(warnings, #no_history.." player(s) with no valid history: "..table.concat(no_history, ", "))
        end
        if #offline_players > 0 then
            table.insert(warnings, #offline_players.." player(s) offline: "..table.concat(offline_players, ", "))
        end
        if #invalid_players > 0 then
            table.insert(warnings, #invalid_players.." invalid player(s): "..table.concat(invalid_players, ", "))
        end
        if #warnings > 0 then
            result_msg = result_msg .. " ("..table.concat(warnings, "; ")..")"
        end
        log_action("Teleport Restore", name, string.format("Restored %s to previous locations", table.concat(restored, ", ")))
        return true, result_msg
    end
})