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
dofile(modpath .. "/commands.lua")

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

minetest.log("action", "[teleport_plus] Loaded successfully with Unified Inventory integration.")
