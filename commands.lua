-- Initialize mod storage
local storage = minetest.get_mod_storage()

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
        table.remove(params, 1)  -- Remove groupname from params
        -- Split remaining parameters by both spaces and commas
        local members = {}
        for _, param in ipairs(params) do
            for member in param:gmatch("([^,]+)") do
                table.insert(members, member:trim())
            end
        end

        -- Check if whitelist mod is enabled
        local whitelist_file = io.open(minetest.get_worldpath().."/whitelist.txt", "r")
        local use_whitelist = whitelist_file ~= nil
        
        if use_whitelist then
            whitelist_file:close()
            -- Read whitelist
            local whitelist = {}
            for line in io.lines(minetest.get_worldpath().."/whitelist.txt") do
                whitelist[line:trim()] = true  -- Trim whitespace from whitelist entries
            end
            
            -- Check if all members are whitelisted
            for _, member in ipairs(members) do
                if not whitelist[member] then
                    return false, "Player "..member.." is not whitelisted"
                end
            end
        else
            -- Check if all members are registered in Luanti DB
            for _, member in ipairs(members) do
                if not minetest.get_auth_handler().get_auth(member) then
                    return false, "Player "..member.." is not registered"
                end
            end
        end

        -- Use the global storage variable, not a new local one
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}
        
        groups[groupname] = members
        storage:set_string("teleport_groups", minetest.serialize(groups))

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
        local whitelist_file = io.open(minetest.get_worldpath().."/whitelist.txt", "r")
        local use_whitelist = whitelist_file ~= nil

        if use_whitelist then
            whitelist_file:close()
            local whitelist = {}
            for line in io.lines(minetest.get_worldpath().."/whitelist.txt") do
                whitelist[line] = true
            end
            
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

        -- Add new members
        local added_users = {}
        for _, member in ipairs(new_members) do
            table.insert(groups[groupname], member)
            table.insert(added_users, member)
        end

        storage:set_string("teleport_groups", minetest.serialize(groups))
        local member_list = table.concat(groups[groupname], ", ")
        return true, "User(s) "..table.concat(added_users, ", ").." added to group '"..groupname.."'. Users: "..member_list
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
        return true, "User(s) "..table.concat(removed_users, ", ").." removed from group '"..groupname.."'. Users: "..member_list
    end
})

-- Register the /deletegroup command
minetest.register_chatcommand("deletegroup", {
    description = "Delete a teleport group",
    params = "<groupname>",
    privs = { teleport_plus_admin = true },
    func = function(name, param)
        local groupname = param:trim()
        if groupname == "" then
            return false, "Usage: /deletegroup <groupname>"
        end

        -- Remove local storage declaration
        local groups = minetest.deserialize(storage:get_string("teleport_groups")) or {}

        if not groups[groupname] then
            return false, "Group '"..groupname.."' does not exist"
        end

        groups[groupname] = nil
        storage:set_string("teleport_groups", minetest.serialize(groups))
        return true, "Deleted group '"..groupname.."'"
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
        -- Limit count to 99
        count = math.min(count, 99)

        -- Check if the item exists
        if not minetest.registered_items[itemname] then
            return false, "Item '"..itemname.."' does not exist"
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

        -- Give the item to each online player in the group
        for _, player_name in ipairs(online_players) do
            local player = minetest.get_player_by_name(player_name)
            if player then
                local inv = player:get_inventory()
                if inv then
                    inv:add_item("main", ItemStack(itemname.." "..count))
                end
            end
        end

        return true, "Gave "..count.." "..itemname.." to online users: "..table.concat(online_players, ", ")
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