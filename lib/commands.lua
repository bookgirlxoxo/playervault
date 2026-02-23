return function(PV)
    minetest.register_privilege("playervaults_admin", {
        description = "Can open and edit other players' vaults.",
        give_to_singleplayer = true,
    })

    for i = 1, PV.MAX_GRANT_AMOUNT do
        minetest.register_privilege("playervault.amount." .. tostring(i), {
            description = "Allows access to up to " .. tostring(i) .. " player vault(s).",
            give_to_singleplayer = false,
        })
    end

    minetest.register_chatcommand("pv", {
        params = "<number> [player]",
        description = "Open vault number for yourself, or for another player if admin.",
        func = function(name, param)
            local cleaned = PV.trim(param)
            if cleaned == "" then
                local max_count = PV.get_max_vault_count(name)
                return PV.chat_error("Usage: /pv <number>, you have " .. tostring(max_count) .. " of vaults!")
            end

            local args = {}
            for token in cleaned:gmatch("%S+") do
                args[#args + 1] = token
            end
            if #args < 1 or #args > 2 then
                return PV.chat_error("Usage: /pv <number> [player]")
            end

            local vault_index = tonumber(args[1])
            if type(vault_index) ~= "number" or vault_index < 1 or vault_index ~= math.floor(vault_index) then
                return PV.chat_error("Vault number must be a positive integer.")
            end

            local target = (#args == 2) and args[2] or name
            return PV.open_vault(name, target, vault_index)
        end,
    })
end
