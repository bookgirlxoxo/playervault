-- incase they used the version before multiple vaults
return function(PV)
    local legacy = {}

    local function legacy_vault_key(owner)
        return "vault:" .. owner
    end

    function legacy.decode_rows(raw)
        if not raw or raw == "" then
            return {}
        end
        local ok, data = pcall(minetest.deserialize, raw)
        if ok and type(data) == "table" then
            return data
        end
        return {}
    end

    function legacy.rows_have_items(rows, vault_size)
        for i = 1, vault_size do
            local stack = ItemStack(rows[i] or "")
            if not stack:is_empty() then
                return true
            end
        end
        return false
    end

    function legacy.apply_slot_one_fallback(owner, rows)
        if legacy.rows_have_items(rows, PV.VAULT_SIZE) then
            return rows
        end

        local legacy_raw = PV.storage:get_string(legacy_vault_key(owner))
        local legacy_rows = legacy.decode_rows(legacy_raw)
        if not legacy.rows_have_items(legacy_rows, PV.VAULT_SIZE) then
            return rows
        end

        PV.storage:set_string(PV.vault_key(owner, 1), minetest.serialize(legacy_rows))
        return legacy_rows
    end

    PV.legacy = legacy
end
