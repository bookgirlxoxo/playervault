local MODNAME = minetest.get_current_modname()
local MODPATH = minetest.get_modpath(MODNAME)

local PV = {
    MODNAME = MODNAME,
    storage = minetest.get_mod_storage(),
    settings = minetest.settings,

    VAULT_W = 9,
    VAULT_ROWS_TOTAL = 3,
    VAULT_SIZE = 27,
    VAULT_X = 0.5,
    VAULT_Y = 1.05,
    INV_X = 1,
    INV_Y = 5.25,
    DEFAULT_VAULT_AMOUNT = 1,
    MAX_GRANT_AMOUNT = 25,

    open_sessions = {},
    owner_sessions = {},
    detached_ready = {},
}

dofile(MODPATH .. "/lib/gui.lua")(PV)
dofile(MODPATH .. "/lib/core.lua")(PV)
dofile(MODPATH .. "/lib/commands.lua")(PV)
