local MODNAME = minetest.get_current_modname()
local storage = minetest.get_mod_storage()

local VAULT_W = 9
local VAULT_ROWS_TOTAL = 3
local VAULT_SIZE = VAULT_W * VAULT_ROWS_TOTAL
local VAULT_X = 0.5
local VAULT_Y = 1.05
local INV_X = 1
local INV_Y = 5.25

local open_sessions = {}
local owner_sessions = {}
local detached_ready = {}

local function is_admin(name)
    return minetest.check_player_privs(name, {server = true})
        or minetest.check_player_privs(name, {playervaults_admin = true})
end

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function vault_key(owner)
    return "vault:" .. owner
end

local function has_vault_data(owner)
    local raw = storage:get_string(vault_key(owner))
    return raw ~= nil and raw ~= ""
end

local function player_exists(name)
    local handler = minetest.get_auth_handler and minetest.get_auth_handler()
    if not handler or not handler.get_auth then
        return minetest.get_player_by_name(name) ~= nil
    end
    return handler.get_auth(name) ~= nil
end

local function save_vault(owner, inv)
    local list = inv:get_list("main") or {}
    local rows = {}
    for i = 1, VAULT_SIZE do
        local stack = list[i] or ItemStack("")
        if not stack:is_empty() then
            local max = stack:get_stack_max()
            if stack:get_count() > max then
                stack:set_count(max)
            end
        end
        rows[i] = stack:to_string()
    end
    storage:set_string(vault_key(owner), minetest.serialize(rows))
end

local function load_vault(owner, inv)
    local raw = storage:get_string(vault_key(owner))
    local rows = {}
    if raw and raw ~= "" then
        local ok, data = pcall(minetest.deserialize, raw)
        if ok and type(data) == "table" then
            rows = data
        end
    end

    local list = {}
    for i = 1, VAULT_SIZE do
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
end

local function can_access(owner, actor)
    if not actor or actor == "" then
        return false
    end
    if actor == owner then
        return true
    end
    return is_admin(actor)
end

local function callback_guard(owner, player)
    local actor = player and player:get_player_name() or ""
    if open_sessions[actor] ~= owner then
        return false
    end
    return can_access(owner, actor)
end

local function formspec_for(owner)
    return table.concat({
        "formspec_version[4]",
        "size[12.0,10.6]",
        "bgcolor[#0f0f15dd;true]",
        "listcolors[#00000099;#3a3a3a;#111111;#000000;#ffffff]",
        "box[0.2,0.2;11.6,10.2;#1a1a24cc]",
        "label[0.8,0.55;Player Vault: " .. minetest.formspec_escape(owner) .. "]",
        "list[detached:playervaults_" .. minetest.formspec_escape(owner) .. ";main;" .. VAULT_X .. "," .. VAULT_Y .. ";" .. VAULT_W .. "," .. VAULT_ROWS_TOTAL .. ";]",
        "label[1.35,4.8;Inventory]",
        "list[current_player;main;" .. INV_X .. "," .. INV_Y .. ";8,4;]",
        "listring[]",
    })
end

local function ensure_detached(owner)
    local name = "playervaults_" .. owner
    if detached_ready[owner] then
        local inv = minetest.get_inventory({type = "detached", name = name})
        if inv then
            inv:set_size("main", VAULT_SIZE)
        end
        return name, inv
    end

    local inv = minetest.create_detached_inventory(name, {
        allow_put = function(_, listname, index, stack, player)
            if listname ~= "main" or index < 1 or index > VAULT_SIZE then
                return 0
            end
            if not callback_guard(owner, player) then
                return 0
            end
            return stack:get_count()
        end,
        allow_take = function(_, listname, index, stack, player)
            if listname ~= "main" or index < 1 or index > VAULT_SIZE then
                return 0
            end
            if not callback_guard(owner, player) then
                return 0
            end
            return stack:get_count()
        end,
        allow_move = function(_, from_list, from_index, to_list, to_index, count, player)
            if from_list ~= "main" or to_list ~= "main" then
                return 0
            end
            if from_index < 1 or from_index > VAULT_SIZE or to_index < 1 or to_index > VAULT_SIZE then
                return 0
            end
            if not callback_guard(owner, player) then
                return 0
            end
            return count
        end,
        on_put = function(inv_ref)
            save_vault(owner, inv_ref)
        end,
        on_take = function(inv_ref)
            save_vault(owner, inv_ref)
        end,
        on_move = function(inv_ref)
            save_vault(owner, inv_ref)
        end,
    })
    inv:set_size("main", VAULT_SIZE)
    load_vault(owner, inv)
    detached_ready[owner] = true
    return name, inv
end

local function close_session(viewer)
    local owner = open_sessions[viewer]
    if not owner then
        return
    end
    open_sessions[viewer] = nil
    if owner_sessions[owner] == viewer then
        owner_sessions[owner] = nil
    end
    local inv = minetest.get_inventory({type = "detached", name = "playervaults_" .. owner})
    if inv then
        save_vault(owner, inv)
    end
end

local function open_vault(actor, owner)
    owner = trim(owner)
    if owner == "" then
        return false, "Usage: /pv [player]"
    end
    if not can_access(owner, actor) then
        return false, "You do not have permission to open other players' vaults."
    end
    if owner ~= actor then
        if not player_exists(owner) then
            return false, "Player not found."
        end
        if not has_vault_data(owner) then
            return false, "That player does not have a vault yet."
        end
    end

    local existing_viewer = owner_sessions[owner]
    if existing_viewer and existing_viewer ~= actor then
        return false, "That vault is currently open by another player."
    end

    close_session(actor)

    local _, inv = ensure_detached(owner)
    if inv then
        load_vault(owner, inv)
    end
    local player = minetest.get_player_by_name(actor)
    if not player then
        return false, "Player not found."
    end

    open_sessions[actor] = owner
    owner_sessions[owner] = actor
    minetest.show_formspec(actor, MODNAME .. ":vault:" .. owner, formspec_for(owner))
    return true, ""
end

minetest.register_privilege("playervaults_admin", {
    description = "Can open and edit other players' vaults.",
    give_to_singleplayer = true,
})

minetest.register_chatcommand("pv", {
    params = "[player]",
    description = "Open your vault or, for admins, another player's vault.",
    func = function(name, param)
        local cleaned = trim(param)
        local target = (cleaned ~= "") and cleaned or name
        return open_vault(name, target)
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if not formname:find("^" .. MODNAME .. ":vault:") then
        return false
    end
    local viewer = player:get_player_name()
    local owner = open_sessions[viewer]
    if not owner then
        return false
    end

    if fields.quit then
        close_session(viewer)
    end
    return false
end)

minetest.register_on_leaveplayer(function(player)
    close_session(player:get_player_name())
end)

minetest.register_on_shutdown(function()
    for viewer, _ in pairs(open_sessions) do
        close_session(viewer)
    end
end)
