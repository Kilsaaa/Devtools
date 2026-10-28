--[[
    varlist.lua - OPTIONAL list of var names for the var browser.

    The API can't list every var, so the browser only knows the vars it has seen change plus whatever is listed here.
    To fill it in, run "pan VarPlayer" and "pan VarClient" in the client console and paste the var names below
    (names only, e.g. "COMBATV2_ARMOUR_RATING"). Leave the tables empty if you don't need it.
]]

return {
    player = {
        -- "COMBATV2_ARMOUR_RATING",
    },
    client = {
        -- "LORE_SPELL_DESC",
    },
}
