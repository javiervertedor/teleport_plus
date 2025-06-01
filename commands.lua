-- Initialize mod storage
local storage = minetest.get_mod_storage()
local integration = dofile(minetest.get_modpath("teleport_plus").."/mods_integration.lua")

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
    description = "List all available teleport groups",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        
        if next(groups) == nil then
            return false, "No groups available"
        end

        local group_list = {}
        for groupname, members in pairs(groups) do
            table.insert(group_list, string.format("%s (%d members)", 
                groupname, 
                #members))
        end
        
        table.sort(group_list)  -- Sort groups alphabetically
        return true, "Available groups: " .. table.concat(group_list, ", ")
    end
})

-- Register the /group command
minetest.register_chatcommand("group", {
    description = "List users in a teleport group",
    params = "<groupname>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local groupname = param:trim()
        if groupname == "" then
            return false, "Usage: /group <groupname>"
        end

        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
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
    privs = { teleport_plus_admin = true },
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
    description = "Set a teleport location with optional protection",
    params = "[pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number]",
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
            return false, "Usage: /setloc [pos] <name> [pvp=on|off] [nobuild=on|off] [radius=number]"
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
        if param_map["pvp"] then
            minetest.log("info", "[teleport_plus] Setting pvp=" .. param_map["pvp"])
            if param_map["pvp"] == "on" then
                pvp = true
            elseif param_map["pvp"] == "off" then
                pvp = false
            else
                return false, "Invalid pvp value. Use 'on' or 'off'"
            end
        end
        if param_map["nobuild"] then
            minetest.log("info", "[teleport_plus] Setting nobuild=" .. param_map["nobuild"])
            if param_map["nobuild"] == "on" then
                nobuild = true
            elseif param_map["nobuild"] == "off" then
                nobuild = false
            else
                return false, "Invalid nobuild value. Use 'on' or 'off'"
            end
        end
        if param_map["radius"] then
            minetest.log("info", "[teleport_plus] Setting radius=" .. param_map["radius"])
            radius = tonumber(param_map["radius"]) or 5
            if radius > 30 then radius = 30 end
            if radius < 0 then radius = 0 end
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
            area_id = area_id
        }
        storage:set_string("teleport_locations", minetest.serialize(locations))

        -- Modify the final success message
        return true, string.format(
            "Location '%s' set at %d,%d,%d with radius=%d%s, pvp=%s, nobuild=%s",
            loc_name,
            math.floor(pos.x),
            math.floor(pos.y),
            math.floor(pos.z),
            radius,
            radius == 30 and " (max radius 30)" or "",
            pvp and "on" or "off",
            nobuild and "on" or "off"
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
        log_action("Location Deleted", name, "Location: " .. loc_name)

        return true, "Deleted location '"..loc_name.."'"
    end
})