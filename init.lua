-- teleport_plus/init.lua

local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

-- Require Unified Inventory
if not minetest.get_modpath("unified_inventory") then
	error("[teleport_plus] This mod requires Unified Inventory. Please install it to continue.")
end

-- Register admin privilege
minetest.register_privilege("teleport_plus_admin", {
	description = "Full control over all teleport_plus features (location and group management)",
	give_to_singleplayer = false
})

-- Load core modules with proper returns
local integration = dofile(modpath .. "/mods_integration.lua")
local schedules = dofile(modpath .. "/schedules.lua")
dofile(modpath .. "/commands.lua")

-- Ensure Areas mod is properly loaded with a delay
minetest.after(1, function()
    if integration.has_areas() then
        minetest.log("action", "[teleport_plus] Areas mod integration confirmed")
    else
        minetest.log("warning", "[teleport_plus] Areas mod integration not available - protection will use fallback system")
    end
end)

-- Register protection callbacks after integration module is loaded
if integration then
    -- Primary protection check
    minetest.register_on_protection_violation(integration.protect_node)
    
    -- Additional node-specific protection callbacks
    minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
        if placer and placer:is_player() then
            if integration.protect_node(pos, placer:get_player_name()) then
                minetest.remove_node(pos)
                return true
            end
        end
    end)

    minetest.register_on_punchnode(function(pos, node, puncher, pointed_thing)
        if puncher and puncher:is_player() then
            if integration.protect_node(pos, puncher:get_player_name()) then
                return true  -- Cancel the punch/dig action
            end
        end
    end)

    minetest.register_on_dignode(function(pos, oldnode, digger)
        if digger and digger:is_player() then
            if integration.protect_node(pos, digger:get_player_name()) then
                minetest.set_node(pos, oldnode)  -- Restore the node
                local inv = digger:get_inventory()
                if inv then
                    -- Try to remove any items that might have been added
                    local nodename = oldnode.name
                    if minetest.registered_nodes[nodename] then
                        inv:remove_item("main", nodename)
                    end
                end
                return true
            end
        end
    end)
end

-- Override Unified Inventory's home command to respect tp=on/off restrictions
minetest.after(0, function()
    if integration.has_unified_inventory() then
        -- Override the /home command to include our teleportation restrictions
        minetest.override_chatcommand("home", {
            description = "Go to your home (respects teleport area restrictions)",
            privs = { home = true },
            func = function(name, param)                -- Check teleportation permissions first
                local can_teleport, tp_err = integration.check_home_teleport_permissions(name)
                if not can_teleport then
                    return false, tp_err
                end
                
                -- Get home position
                local pos = integration.get_home_position(name)
                if not pos then
                    return false, "Set a home using /sethome"
                end
                
                -- Get player and teleport (simplified - no safety checks)
                local player = minetest.get_player_by_name(name)
                if not player then
                    return false, "Player not found"
                end
                
                -- Just teleport directly - let the game engine handle any adjustments
                player:set_pos(pos)
                return true, "Teleported to home"
            end
        })
        
        -- Also override /sethome if it exists
        if minetest.registered_chatcommands["sethome"] then
            minetest.override_chatcommand("sethome", {
                description = "Set your home position",
                privs = { home = true },
                func = function(name, param)
                    local player = minetest.get_player_by_name(name)
                    if not player then
                        return false, "Player not found"
                    end
                    
                    local pos = player:get_pos()
                    local success = integration.set_home_position(name, pos)
                    if success then
                        return true, string.format("Home set at %d,%d,%d", 
                            math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
                    else
                        return false, "Failed to set home position"
                    end
                end
            })
        end
    end
end)

minetest.log("action", "[teleport_plus] Loaded successfully with Unified Inventory integration.")
