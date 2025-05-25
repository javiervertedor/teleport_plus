-- teleport_plus/init.lua

local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

-- Require Unified Inventory
if not minetest.get_modpath("unified_inventory") then
	error("[teleport_plus] This mod requires Unified Inventory. Please install it to continue.")
end

-- Register privileges
minetest.register_privilege("teleport_plus_admin", {
	description = "Full control over all teleport_plus features",
	give_to_singleplayer = false
})

minetest.register_privilege("teleport_plus_user", {
	description = "Access to teleport_plus basic teleportation (home and 5 waypoints)",
	give_to_singleplayer = false
})

-- Load core modules
dofile(modpath .. "/data.lua")
dofile(modpath .. "/utils.lua")
dofile(modpath .. "/commands.lua")
dofile(modpath .. "/integration_unified_inventory.lua")

minetest.log("action", "[teleport_plus] Loaded successfully with Unified Inventory integration.")
