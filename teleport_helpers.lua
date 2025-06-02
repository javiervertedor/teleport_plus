-- teleport_helpers.lua: shared teleport helper functions

local M = {}

-- Helper to strip both single and double quotes from a string
function M.strip_quotes(str)
    if not str then return str end
    str = str:gsub('^"(.-)"$', '%1')
    str = str:gsub("^'(.-)'$", '%1')
    return str
end

-- Helper to parse and validate targets (copied from commands.lua)
function M.parse_targets(target_str, storage, minetest)
    if not target_str or target_str == "" then
        return nil
    end
    local strip_quotes = M.strip_quotes
    local unquoted_str = strip_quotes(target_str:trim())
    if unquoted_str == "me" then
        return { type = "player", players = { "me" } }
    elseif unquoted_str == "all" then
        return { type = "all", players = {} }
    end
    local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
    if groups[unquoted_str] then
        return { type = "group", players = groups[unquoted_str] }
    end
    local players = {}
    for player in unquoted_str:gmatch("[^,]+") do
        local trimmed = strip_quotes(player:trim())
        if trimmed ~= "" then
            table.insert(players, trimmed)
        end
    end
    if #players > 0 then
        return { type = "player", players = players }
    end
    return nil
end

return M
