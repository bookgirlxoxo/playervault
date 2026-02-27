return function(PV)
    local function security()
        return prisontest_server
            and prisontest_server.op
            and prisontest_server.op.security
            or nil
    end

    function PV.is_admin(name)
        return minetest.check_player_privs(name, {server = true})
            or minetest.check_player_privs(name, {playervaults_admin = true})
    end

    function PV.trim(s)
        return tostring(s or ""):match("^%s*(.-)%s*$")
    end

    function PV.chat_error(message)
        return false, minetest.colorize("red", message)
    end

    function PV.vault_key(owner, vault_index)
        return "vault:" .. owner .. ":" .. vault_index
    end

    function PV.player_exists(name)
        local handler = minetest.get_auth_handler and minetest.get_auth_handler()
        if not handler or not handler.get_auth then
            return minetest.get_player_by_name(name) ~= nil
        end
        return handler.get_auth(name) ~= nil
    end

    function PV.get_player_priv_table(name)
        local online = minetest.get_player_by_name(name)
        if online then
            return minetest.get_player_privs(name)
        end

        local handler = minetest.get_auth_handler and minetest.get_auth_handler()
        if not handler or not handler.get_auth then
            return {}
        end

        local auth = handler.get_auth(name)
        if not auth or type(auth.privileges) ~= "table" then
            return {}
        end
        return auth.privileges
    end

    function PV.get_max_vault_count(name)
        local max_count = PV.DEFAULT_VAULT_AMOUNT
        local privs = PV.get_player_priv_table(name)
        for priv, granted in pairs(privs) do
            if granted then
                local amount = tonumber(tostring(priv):match("^playervault%.amount%.(%d+)$"))
                if amount and amount > max_count then
                    max_count = amount
                end
            end
        end
        return max_count
    end

    function PV.can_access(owner, actor)
        if not actor or actor == "" then
            return false
        end
        if actor == owner then
            return true
        end
        return PV.is_admin(actor)
    end

    function PV.session_key(owner, vault_index)
        return owner .. "#" .. tostring(vault_index)
    end

    function PV.callback_guard(owner, vault_index, player)
        if player then
            local actor = player:get_player_name()
            local session = PV.open_sessions[actor]
            if not session or session.owner ~= owner or session.index ~= vault_index then
                return false
            end
            return PV.can_access(owner, actor)
        end
        local key = PV.session_key(owner, vault_index)
        local viewer = PV.owner_sessions[key]
        if not viewer then
            return false
        end
        local session = PV.open_sessions[viewer]
        if not session or session.owner ~= owner or session.index ~= vault_index then
            return false
        end
        return PV.can_access(owner, viewer)
    end

    function PV.save_vault(owner, vault_index, inv)
        local list = inv:get_list("main") or {}
        local rows = {}
        for i = 1, PV.VAULT_SIZE do
            local stack = list[i] or ItemStack("")
            if not stack:is_empty() then
                local max = stack:get_stack_max()
                if stack:get_count() > max then
                    stack:set_count(max)
                end
            end
            rows[i] = stack:to_string()
        end
        PV.storage:set_string(PV.vault_key(owner, vault_index), minetest.serialize(rows))
    end

    function PV.canonicalize_special_stacks(inv)
        local sec = security()
        if not sec or type(sec.ensure_stack_meta) ~= "function" then
            return
        end
        local list = inv:get_list("main") or {}
        for i = 1, PV.VAULT_SIZE do
            local stack = list[i] or ItemStack("")
            if not stack:is_empty() then
                local _, changed = sec.ensure_stack_meta(stack)
                if changed then
                    inv:set_stack("main", i, stack)
                end
            end
        end
    end

    function PV.canonicalize_player_main(player)
        if not player or not player:is_player() then
            return
        end
        local inv = player:get_inventory()
        if not inv then
            return
        end
        local sec = security()
        if not sec or type(sec.ensure_stack_meta) ~= "function" then
            return
        end
        local list = inv:get_list("main") or {}
        for i, stack in ipairs(list) do
            if not stack:is_empty() then
                local _, changed = sec.ensure_stack_meta(stack)
                if changed then
                    inv:set_stack("main", i, stack)
                end
            end
        end
    end

    function PV.load_vault(owner, vault_index, inv)
        local current_raw = PV.storage:get_string(PV.vault_key(owner, vault_index))
        local rows = {}
        if current_raw and current_raw ~= "" then
            local ok, decoded = pcall(minetest.deserialize, current_raw)
            if ok and type(decoded) == "table" then
                rows = decoded
            end
        end

        local list = {}
        for i = 1, PV.VAULT_SIZE do
            local stack = ItemStack(rows[i] or "")
            if not stack:is_empty() then
                local max = stack:get_stack_max()
                if stack:get_count() > max then
                    stack:set_count(max)
                end
            end
            list[i] = stack
        end
        inv:set_list("main", list)
        PV.canonicalize_special_stacks(inv)
    end

    function PV.ensure_detached(owner, vault_index)
        local key = PV.session_key(owner, vault_index)
        local name = "playervaults_" .. owner .. "_" .. tostring(vault_index)
        if PV.detached_ready[key] then
            local inv = minetest.get_inventory({type = "detached", name = name})
            if inv then
                inv:set_size("main", PV.VAULT_SIZE)
            end
            return name, inv
        end

        local inv = minetest.create_detached_inventory(name, {
            allow_put = function(_, listname, index, stack, player)
                if listname ~= "main" or index < 1 or index > PV.VAULT_SIZE then
                    return 0
                end
                if not PV.callback_guard(owner, vault_index, player) then
                    return 0
                end
                return stack:get_count()
            end,
            allow_take = function(_, listname, index, stack, player)
                if listname ~= "main" or index < 1 or index > PV.VAULT_SIZE then
                    return 0
                end
                if not PV.callback_guard(owner, vault_index, player) then
                    return 0
                end
                return stack:get_count()
            end,
            allow_move = function(_, from_list, from_index, to_list, to_index, count, player)
                if from_list ~= "main" or to_list ~= "main" then
                    return 0
                end
                if from_index < 1 or from_index > PV.VAULT_SIZE or to_index < 1 or to_index > PV.VAULT_SIZE then
                    return 0
                end
                if not PV.callback_guard(owner, vault_index, player) then
                    return 0
                end
                return count
            end,
            on_put = function(inv_ref)
                PV.canonicalize_special_stacks(inv_ref)
                PV.save_vault(owner, vault_index, inv_ref)
            end,
            on_take = function(inv_ref)
                PV.canonicalize_special_stacks(inv_ref)
                PV.save_vault(owner, vault_index, inv_ref)
            end,
            on_move = function(inv_ref)
                PV.canonicalize_special_stacks(inv_ref)
                PV.save_vault(owner, vault_index, inv_ref)
            end,
        })
        inv:set_size("main", PV.VAULT_SIZE)
        PV.load_vault(owner, vault_index, inv)
        PV.detached_ready[key] = true
        return name, inv
    end

    function PV.close_session(viewer)
        local session = PV.open_sessions[viewer]
        if not session then
            return
        end
        local owner = session.owner
        local vault_index = session.index
        local key = PV.session_key(owner, vault_index)
        PV.open_sessions[viewer] = nil
        if PV.owner_sessions[key] == viewer then
            PV.owner_sessions[key] = nil
        end
        local inv = minetest.get_inventory({
            type = "detached",
            name = "playervaults_" .. owner .. "_" .. tostring(vault_index),
        })
        if inv then
            PV.save_vault(owner, vault_index, inv)
        end
    end

    function PV.open_vault(actor, owner, vault_index)
        owner = PV.trim(owner)
        if owner == "" then
            return PV.chat_error("Usage: /pv <number> [player]")
        end
        if type(vault_index) ~= "number" or vault_index < 1 or vault_index ~= math.floor(vault_index) then
            return PV.chat_error("Vault number must be a positive integer.")
        end

        if owner ~= actor and not PV.player_exists(owner) then
            return PV.chat_error("Player not found.")
        end

        local owner_max_count = PV.get_max_vault_count(owner)
        if vault_index > owner_max_count then
            if owner == actor then
                return PV.chat_error(
                    "You do not have vault #" .. tostring(vault_index) .. ". Max: " .. tostring(owner_max_count) .. "."
                )
            end
            return PV.chat_error(
                owner .. " does not have vault #" .. tostring(vault_index) .. ". Max: " .. tostring(owner_max_count) .. "."
            )
        end
        if not PV.can_access(owner, actor) then
            return PV.chat_error("You do not have permission to open other players' vaults.")
        end

        local key = PV.session_key(owner, vault_index)
        local existing_viewer = PV.owner_sessions[key]
        if existing_viewer and existing_viewer ~= actor then
            return PV.chat_error("That vault is currently open by another player.")
        end

        PV.close_session(actor)

        local _, inv = PV.ensure_detached(owner, vault_index)
        if inv then
            PV.load_vault(owner, vault_index, inv)
        end
        local player = minetest.get_player_by_name(actor)
        if not player then
            return PV.chat_error("Player not found.")
        end
        PV.canonicalize_player_main(player)

        PV.open_sessions[actor] = {
            owner = owner,
            index = vault_index,
            max = owner_max_count,
        }
        PV.owner_sessions[key] = actor
        minetest.show_formspec(
            actor,
            PV.MODNAME .. ":vault:" .. owner .. ":" .. tostring(vault_index),
            PV.formspec_for(owner, actor, vault_index, owner_max_count)
        )
        return true, ""
    end

    minetest.register_on_leaveplayer(function(player)
        PV.close_session(player:get_player_name())
    end)

    minetest.register_on_shutdown(function()
        for viewer, _ in pairs(PV.open_sessions) do
            PV.close_session(viewer)
        end
    end)
end
