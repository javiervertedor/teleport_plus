-- Areas mod global declaration
---@type table|nil
areas = areas or nil

local integration = {}
local storage = minetest.get_mod_storage()

-- Check if Areas mod is available and initialized
function integration.has_areas()
    local has_modpath = minetest.get_modpath("areas") ~= nil
    local areas_exists = areas ~= nil
    local areas_func_exists = areas_exists and type(areas.add) == "function" and type(areas.remove) == "function" and type(areas.save) == "function"
    
    if not has_modpath then
        minetest.log("warning", "[teleport_plus] Areas mod files not found")
        return false
    end
    if not areas_exists then
        minetest.log("warning", "[teleport_plus] Areas global table not available")
        return false
    end
    if not areas_func_exists then
        minetest.log("warning", "[teleport_plus] Areas mod API functions not available (add:" .. 
            tostring(areas and type(areas.add)) .. ", remove:" .. 
            tostring(areas and type(areas.remove)) .. ", save:" .. 
            tostring(areas and type(areas.save)) .. ")")
        return false
    end
    
    minetest.log("action", "[teleport_plus] Areas mod is available and properly initialized")
    return true
end

-- Check if Protector mod is available
function integration.has_protector()
    return minetest.get_modpath("protector") and minetest.registered_nodes["protector:protect"] ~= nil
end

-- Check if Whitelist mod is available and whitelist.txt exists
function integration.has_whitelist()
    if not minetest.get_modpath("whitelist") then
        return false
    end
    local whitelist_file = io.open(minetest.get_worldpath().."/whitelist.txt", "r")
    if whitelist_file then
        whitelist_file:close()
        return true
    end
    return false
end

-- Get whitelist entries if available
function integration.get_whitelist()
    if not integration.has_whitelist() then
        return nil
    end
    
    local whitelist = {}
    for line in io.lines(minetest.get_worldpath().."/whitelist.txt") do
        whitelist[line:trim()] = true
    end
    return whitelist
end

-- Check if a position is protected by an area
function integration.check_area_protection(pos, radius)
    if integration.has_areas() then
        local areas_overlap = areas:getAreasIntersecting(
            {x = pos.x - radius, y = pos.y - radius, z = pos.z - radius},
            {x = pos.x + radius, y = pos.y + radius, z = pos.z + radius}
        )
        if next(areas_overlap) then
            return false, "This location overlaps with existing protected areas"
        end
    end
    return true
end

-- Check if a position is protected by a protector block
function integration.check_protector_protection(pos, radius)
    if integration.has_protector() then
        local protector_radius = minetest.settings:get("protector_radius") or 5
        local positions = minetest.find_nodes_in_area(
            {x = pos.x - radius - protector_radius, y = pos.y - radius - protector_radius, z = pos.z - radius - protector_radius},
            {x = pos.x + radius + protector_radius, y = pos.y + radius + protector_radius, z = pos.z + radius + protector_radius},
            {"protector:protect", "protector:protect2"}
        )
        if #positions > 0 then
            return false, "This location is too close to existing protector blocks"
        end
    end
    return true
end

-- Check for valid position and safety
function integration.is_valid_position(pos)
    -- Check if position is within map bounds
    local mapgen_limit = tonumber(minetest.settings:get("mapgen_limit")) or 31000
    if math.abs(pos.x) > mapgen_limit or 
       math.abs(pos.y) > mapgen_limit or 
       math.abs(pos.z) > mapgen_limit then
        return false, "Position is outside map bounds"
    end
    return true
end

-- Check if position is safe for teleportation (basic safety only)
function integration.is_safe_position(pos)
    -- Check if player feet position is safe (not in solid block or lava)
    local feet_node = minetest.get_node(pos)
    local feet_def = minetest.registered_nodes[feet_node.name]
    
    -- Don't teleport into lava or other dangerous liquids
    if feet_def and (feet_def.damage_per_second or 0) > 0 then
        return false, "Position is in dangerous liquid"
    end
    
    -- Don't teleport into solid blocks (but allow air and walkable=false nodes)
    if feet_def and feet_def.walkable and feet_def.walkable ~= false then
        return false, "Position is inside a solid block"
    end
    
    -- Check if there's ground below (within reasonable distance)
    for y_check = 1, 10 do
        local ground_pos = {x = pos.x, y = pos.y - y_check, z = pos.z}
        local ground_node = minetest.get_node(ground_pos)
        local ground_def = minetest.registered_nodes[ground_node.name]
        
        if ground_def and ground_def.walkable then
            return true -- Found solid ground within 10 blocks
        end
    end
    
    return false, "No solid ground found below position"
end

-- Simple function to adjust position if needed (minimal adjustment)
function integration.find_safe_position_near(target_pos, search_radius)
    -- Just try the target position first
    if integration.is_safe_position(target_pos) then
        return target_pos
    end
    
    -- If not safe, just return the original position anyway
    -- Let the game engine handle minor adjustments
    return target_pos
end

-- Check if Unified Inventory mod is available
function integration.has_unified_inventory()
    return minetest.get_modpath("unified_inventory") and unified_inventory ~= nil
end

-- Check and get home position from Unified Inventory
function integration.get_home_position(player_name)
    if not integration.has_unified_inventory() then
        return nil, "Unified Inventory is not available"
    end

    -- Get home position from unified_inventory
    local home = unified_inventory.home_pos[player_name]
    if not home then
        return nil, "No home position set"
    end

    return home
end

-- Set home position in Unified Inventory
function integration.set_home_position(player_name, pos)
    if not integration.has_unified_inventory() then
        return false, "Unified Inventory is not available"
    end

    -- Check if player has home privilege
    if not minetest.check_player_privs(player_name, {home = true}) then
        return false, "No home privilege"
    end

    -- Get player object
    local player = minetest.get_player_by_name(player_name)
    if not player then
        return false, "Player not found"
    end

    -- Set home position in unified_inventory
    unified_inventory.home_pos[player_name] = pos
    -- Save home position with player object
    unified_inventory.set_home(player, pos)

    return true
end

-- Get waypoints from Unified Inventory
function integration.get_unified_inventory_waypoints(player_name)
    -- Check if Unified Inventory is available
    if not integration.has_unified_inventory() then
        minetest.log("warning", "[teleport_plus] Unified Inventory not available")
        return {}
    end

    -- Check if player exists
    local player = minetest.get_player_by_name(player_name)
    if not player then
        minetest.log("warning", "[teleport_plus] Player not found: " .. player_name)
        return {}
    end

    -- Get waypoints directly from player metadata
    local waypoints = {}
    local meta = player:get_meta()
    local data = meta:get("ui_waypoints")
    
    if data and data ~= "" then
        local wp_data = minetest.parse_json(data)
        if wp_data and wp_data.data then
            for i = 1, 5 do  -- Unified Inventory uses 5 waypoints
                local waypoint = wp_data.data[i]
                if waypoint and waypoint.name and waypoint.name ~= "" and waypoint.world_pos then
                    -- Format the waypoint as a teleport_plus location
                    waypoints[waypoint.name] = {
                        pos = waypoint.world_pos,
                        pvp = minetest.settings:get_bool("enable_pvp"),
                        nobuild = false,
                        radius = 0,
                        owner = player_name,
                        is_waypoint = true
                    }
                end
            end
        end
    end

    minetest.log("action", "[teleport_plus] Found " .. #waypoints .. " waypoints for " .. player_name)
    return waypoints
end

-- Protect a location using Areas mod
function integration.protect_location(loc_name, pos, radius, owner)
    if not integration.has_areas() then
        minetest.log("warning", "[teleport_plus] Areas mod not available for protection")
        return false
    end

    -- Calculate positions with floor to ensure integer coordinates
    local pos1 = {
        x = math.floor(pos.x - radius),
        y = math.floor(pos.y - radius),
        z = math.floor(pos.z - radius)
    }
    local pos2 = {
        x = math.floor(pos.x + radius),
        y = math.floor(pos.y + radius),
        z = math.floor(pos.z + radius)
    }
    
    minetest.log("action", string.format("[teleport_plus] Creating area '%s' for owner '%s' from %s to %s", 
        loc_name, owner, minetest.pos_to_string(pos1), minetest.pos_to_string(pos2)))
    
    -- Add the area protection
    local area_id = areas:add(owner, loc_name, pos1, pos2, nil)  -- nil = no parent area

    if area_id then
        areas:save()
        minetest.log("action", "[teleport_plus] Successfully created area " .. area_id .. " for location " .. loc_name)
        return true, area_id
    else
        minetest.log("error", "[teleport_plus] Failed to create area for location " .. loc_name)
    end

    return false
end

-- Remove protection
function integration.remove_location_protection(area_id, owner)
    if not integration.has_areas() then
        minetest.log("warning", "[teleport_plus] Areas mod not available for removal")
        return false
    end

    if not area_id then
        minetest.log("warning", "[teleport_plus] No area_id provided for removal")
        return false
    end

    -- Check if the area exists before trying to remove it
    if areas.areas and areas.areas[area_id] then
        -- Remove the area directly using the Areas API
        areas:remove(area_id)
        
        -- Save changes
        areas:save()
        
        minetest.log("action", "[teleport_plus] Successfully removed area " .. area_id)
        return true
    else
        minetest.log("warning", "[teleport_plus] Area " .. area_id .. " does not exist, may have been already removed")
        return true  -- Consider it successful since the area doesn't exist
    end
end

-- Check if a position is protected by teleport locations
function integration.protect_node(pos, name)
    -- Skip our protection check if Areas mod is available
    if integration.has_areas() then
        return false  -- Let Areas mod handle it
    end

    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    
    for loc_name, location in pairs(locations) do
        if location.nobuild and not location.area_id then  -- Only check if using internal protection
            local loc_pos = location.pos
            local radius = location.radius
            
            -- Check if position is within protected area
            if pos.x >= (loc_pos.x - radius) and pos.x <= (loc_pos.x + radius) and
               pos.y >= (loc_pos.y - radius) and pos.y <= (loc_pos.y + radius) and
               pos.z >= (loc_pos.z - radius) and pos.z <= (loc_pos.z + radius) then
                -- Allow owner and players with teleport_plus_admin privilege to build
                if name == location.owner or minetest.check_player_privs(name, {teleport_plus_admin = true}) then
                    return false
                end
                minetest.chat_send_player(name, "This area is protected (Location: " .. loc_name .. ")")
                return true
            end
        end
    end
    
    return false
end

-- Check teleportation permissions for home teleports
function integration.check_home_teleport_permissions(player_name)
    local is_admin = minetest.check_player_privs(player_name, {server = true}) or 
                     minetest.check_player_privs(player_name, {teleport_plus_admin = true})
    
    -- Admins can always teleport
    if is_admin then
        return true
    end
    
    local player = minetest.get_player_by_name(player_name)
    if not player then
        return false, "Player not found"
    end
    
    local player_pos = player:get_pos()
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    
    -- Check if player is in any location area with teleportation disabled
    for loc_name, location_data in pairs(locations) do
        if location_data.pos and location_data.radius then
            local loc_pos = location_data.pos
            local radius = location_data.radius or 5
            
            -- Check if player is within the location area
            if player_pos.x >= (loc_pos.x - radius) and player_pos.x <= (loc_pos.x + radius) and
               player_pos.y >= (loc_pos.y - radius) and player_pos.y <= (loc_pos.y + radius) and
               player_pos.z >= (loc_pos.z - radius) and player_pos.z <= (loc_pos.z + radius) then
                -- Check if teleportation is disabled for this location (default to enabled for backward compatibility)
                local tp_enabled = location_data.tp_enabled
                if tp_enabled == nil then
                    tp_enabled = true  -- Default for backward compatibility
                end
                
                if not tp_enabled then
                    return false, string.format("Teleportation is disabled in location '%s'", loc_name)
                end
            end
        end
    end
    
    return true
end

-- Add after the protect_node function but before return integration
function integration.check_pvp_protection(pos, player_name)
    local locations = minetest.deserialize(storage:get_string("teleport_locations")) or {}
    
    for _, location in pairs(locations) do
        -- Always treat nil as true for pvp (default: PVP enabled)
        local pvp = location.pvp
        if pvp == nil then pvp = true end
        if not pvp then  -- Check areas where PVP is disabled
            local loc_pos = location.pos
            local radius = location.radius
            if pos.x >= (loc_pos.x - radius) and pos.x <= (loc_pos.x + radius) and
               pos.y >= (loc_pos.y - radius) and pos.y <= (loc_pos.y + radius) and
               pos.z >= (loc_pos.z - radius) and pos.z <= (loc_pos.z + radius) then
                minetest.chat_send_player(player_name, "PVP is disabled in this area")
                return true  -- Cancel the punch
            end
        end
    end
    
    return false  -- Allow the punch
end

-- Register the punch callback
minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if not hitter:is_player() then
        return false  -- Let non-player damage through
    end

    local pos = player:get_pos()
    local hitter_name = hitter:get_player_name()
    
    -- Check if punch occurred in a no-PVP zone
    if integration.check_pvp_protection(pos, hitter_name) then
        return true  -- Cancel the punch
    end
    
    return false  -- Allow the punch
end)

return integration

