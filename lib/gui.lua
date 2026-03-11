return function(PV)
    function PV.formspec_for(owner, viewer, vault_index, max_count)
        local title = "Displaying vault  #" .. tostring(vault_index) .. "/" .. tostring(max_count)
        if viewer ~= owner then
            title = "Displaying " .. owner .. "'s vault  #" .. tostring(vault_index) .. "/" .. tostring(max_count)
        end

        local fs = {
            "formspec_version[4]",
            "size[12.0,11.2]",
            "label[0.5,0.55;" .. minetest.formspec_escape(title) .. "]",
            "button_exit[10.55,0.30;1.0,0.7;close;Close]",
            "list[detached:playervaults_" .. minetest.formspec_escape(owner) .. "_" .. tostring(vault_index) .. ";main;" .. PV.VAULT_X .. "," .. PV.VAULT_Y .. ";" .. PV.VAULT_W .. "," .. PV.VAULT_ROWS_TOTAL .. ";]",
            "label[1.35,5.55;Inventory]",
            "list[current_player;main;1.0,6.0;8,4;]",
            "listring[]",
        }

        if max_count > 1 then
            if vault_index > 1 then
                fs[#fs + 1] = "button[0.5,4.6;1.3,0.6;pv_vault_prev;< Prev]"
            end
            if vault_index < max_count then
                local next_x = (vault_index > 1) and 2.0 or 0.5
                fs[#fs + 1] = string.format("button[%0.1f,4.6;1.3,0.6;pv_vault_next;Next >]", next_x)
            end
        end

        return table.concat(fs)
    end

    minetest.register_on_player_receive_fields(function(player, formname, fields)
        if not formname:find("^" .. PV.MODNAME .. ":vault:") then
            return false
        end
        local viewer = player:get_player_name()
        local session = PV.open_sessions[viewer]
        if not session then
            return false
        end

        if fields.pv_vault_prev then
            local ok, err = PV.open_vault(viewer, session.owner, session.index - 1)
            if not ok and err ~= "" then
                minetest.chat_send_player(viewer, err)
            end
            return true
        end
        if fields.pv_vault_next then
            local ok, err = PV.open_vault(viewer, session.owner, session.index + 1)
            if not ok and err ~= "" then
                minetest.chat_send_player(viewer, err)
            end
            return true
        end

        if fields.quit or fields.close then
            PV.close_session(viewer)
            return true
        end
        return false
    end)
end
