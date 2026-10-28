--[[
    varindex.lua - the names of the vars the dev tools know about, and searching them.

    Names come from three places: anything the API will enumerate, the optional varlist.lua, and every var seen in a
    VarTransmit event (a character's vars are all sent at login, so this fills up on its own).
]]

local Index = {}

local KINDS = { player = "VarPlayer", client = "VarClient" }
local SETTERS = { player = "!setvar", client = "!setvarc" }

local names = {}          -- name -> kind ("player" / "client")
local lower = {}          -- name -> lower-case name (for searching)
local changedAt = {}      -- name -> order in which it last changed (higher = more recent)
local changeCounter = 0
local total = 0

----------------------------------------------------------------
-- NAMES
----------------------------------------------------------------
function Index.add(name, kind)
    if type(name) ~= "string" or name == "" or not KINDS[kind] then return end
    local isNew = not names[name]
    if isNew then
        total = total + 1
        lower[name] = name:lower()
    end
    names[name] = kind
    if isNew and Index.onNew then Index.onNew(name, kind) end
end

function Index.count(kind)
    if not kind then return total end
    local n = 0
    for _, k in pairs(names) do if k == kind then n = n + 1 end end
    return n
end
function Index.kindOf(name) return names[name] end
function Index.setter(kind) return SETTERS[kind] end

-- the value of a var, or nil when it can't be read
function Index.value(name, kind)
    local ok, value = pcall(function() return var[KINDS[kind]][name].value end)
    if ok then return value end
    return nil
end

-- which kind of var a name is, found by trying to read it
local function detectKind(name)
    for _, kind in ipairs({ "player", "client" }) do
        if Index.value(name, kind) ~= nil then return kind end
    end
    return nil
end

----------------------------------------------------------------
-- SOURCES
----------------------------------------------------------------
local function enumerate(kind)
    pcall(function()
        for key, value in pairs(var[KINDS[kind]]) do
            if type(value) ~= "function" then Index.add(key, kind) end   -- skips helpers such as FromID
        end
    end)
end

local function loadList()
    local ok, list = pcall(require, "data/varlist")
    if not ok or type(list) ~= "table" then return end
    for kind in pairs(KINDS) do
        for _, name in ipairs(list[kind] or {}) do Index.add(name, kind) end
    end
end

local function onVarTransmit(ev)
    local name = tostring(ev.var)
    if not names[name] then
        local kind = detectKind(name)
        if kind then Index.add(name, kind) end
    end
    if names[name] and ev.oldValue ~= ev.newValue then
        changeCounter = changeCounter + 1
        changedAt[name] = changeCounter
    end
    if Index.onChange then Index.onChange(name, ev.newValue) end
end

function Index.start()
    for kind in pairs(KINDS) do enumerate(kind) end
    loadList()
    Event.VarTransmit.Subscribe("devtools_vars", onVarTransmit)
end

function Index.stop()
    Event.VarTransmit.Unsubscribe("devtools_vars")
end

----------------------------------------------------------------
-- SEARCH
----------------------------------------------------------------
-- Every word of `query` must appear in the name ("combat armour" finds COMBATV2_ARMOUR_RATING).
-- kind: "player", "client" or nil for both. Recently changed vars come first, then A-Z.
-- Returns the first `limit` matches as { name, kind } plus how many matched in all.
function Index.search(query, kind, limit)
    local terms = {}
    for word in tostring(query or ""):lower():gmatch("%S+") do terms[#terms + 1] = word end

    local found = {}
    for name, nameKind in pairs(names) do
        if not kind or kind == nameKind then
            local text, matches = lower[name], true
            for _, term in ipairs(terms) do
                if not text:find(term, 1, true) then matches = false; break end
            end
            if matches then found[#found + 1] = name end
        end
    end

    table.sort(found, function(a, b)
        local ca, cb = changedAt[a] or 0, changedAt[b] or 0
        if ca ~= cb then return ca > cb end
        return a < b
    end)

    local results = {}
    for i = 1, math.min(#found, limit) do
        results[i] = { name = found[i], kind = names[found[i]] }
    end
    return results, #found
end

return Index
