return function(PV)
    function PV.formspec_for(owner, viewer, vault_index, max_count)
        local title = "Displaying vault  #" .. tostring(vault_index) .. "/" .. tostring(max_count)
        if viewer ~= owner then
            title = "Displaying " .. owner .. "'s vault  #" .. tostring(vault_index) .. "/" .. tostring(max_count)
        end

        return table.concat({
            "formspec_version[4]",
            "size[12.0,10.6]",
            "bgcolor[#0f0f15dd;true]",
            "listcolors[#00000099;#3a3a3a;#111111;#000000;#ffffff]",
            "box[0.2,0.2;11.6,10.2;#1a1a24cc]",
            "label[0.8,0.55;" .. minetest.formspec_escape(title) .. "]",
            "button_exit[10.4,0.4;1.0,0.7;close;Close]",
            "list[detached:playervaults_" .. minetest.formspec_escape(owner) .. "_" .. tostring(vault_index) .. ";main;" .. PV.VAULT_X .. "," .. PV.VAULT_Y .. ";" .. PV.VAULT_W .. "," .. PV.VAULT_ROWS_TOTAL .. ";]",
            "label[1.35,4.8;Inventory]",
            "list[current_player;main;" .. PV.INV_X .. "," .. PV.INV_Y .. ";8,4;]",
            "listring[]",
        })
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

        if fields.quit or fields.close then
            PV.close_session(viewer)
            return true
        end
        return false
    end)
end
