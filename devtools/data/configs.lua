--[[
    configs.lua - the config types the dev tools can browse (NPC, Obj, Quest, Achievement, vars) and how to find,
    search and describe them.

    The API has no call that lists every config, so names are gathered from whatever it will give us:
      1. the id table (id.NPC.HANS -> 1234), if it can be walked,
      2. an optional "Scan all", which asks for every id in turn,
      3. an exact id or name typed in the filter box, which is always looked up directly.
    To browse another config type, add a line to TYPES below.
]]

local VarIndex = require("data/varindex")

local Configs = {}

----------------------------------------------------------------
-- THE TYPES
----------------------------------------------------------------
-- key: shown on the button     access: the config table (config.NPC)     ids: the id table (id.NPC)
-- fields: the properties shown for a selected config, in order (names from the API documentation)
-- vars: "player" / "client" for var types (used by the Set Var tab); negative: ids also run below zero (VarBits)
local TYPES = {
    {
        key = "Achievement", access = function() return config.Achievement end, ids = function() return id.Achievement end,
        fields = { "id", "configName", "name", "reward", "isMembers", "category", "subCategory", "runeScore", "hiddenType",
            "spriteID", "tallyTarget", "tallyProgress", "progress", "prereqsComplete", "totalPrereqCount",
            "totalRequirementCount", "prereqGroupCount", "requirementGroupCount" },
    },
    {
        key = "NPC", access = function() return config.NPC end, ids = function() return id.NPC end,
        fields = { "id", "configName", "name", "visibleCombatLevel", "isFamiliar", "isActive", "isMultiNPC", "multiVar",
            "gridSize", "wanderRange", "maxRange", "turnSpeed", "attackOpIndex", "opNames", "bas", "mapElement", "quests",
            "params" },
    },
    {
        key = "Obj", label = "Obj (items)", access = function() return config.Obj end, ids = function() return id.Obj end,
        fields = { "id", "configName", "name", "isMembers", "category", "cost", "isTradeable", "isStockmarket",
            "stockmarketBuyLimit", "stackType", "teamID", "groundOpNames", "interfaceOpNames", "quests", "params" },
    },
    {
        key = "Quest", access = function() return config.Quest end, ids = function() return id.Quest end,
        fields = { "id", "configName", "name", "deprecated", "isMembers", "questPoints", "difficulty", "hasStartedQuest",
            "hasFinishedQuest", "canStartQuest", "preReqQuestPoints", "preReqQuests", "params" },
    },
    {
        key = "VarPlayer", vars = "player", negative = true, access = function() return var.VarPlayer end, ids = function() return id.VarPlayer end,
        fields = { "id", "configName", "typeName", "value", "valueType", "isVarBit", "baseVar", "varBitMask" },
    },
    {
        key = "VarClient", vars = "client", negative = true, access = function() return var.VarClient end, ids = function() return id.VarClient end,
        fields = { "id", "configName", "typeName", "value", "valueType", "isVarBit", "baseVar", "varBitMask" },
    },
}

local BY_KEY = {}
for _, def in ipairs(TYPES) do BY_KEY[def.key] = def end

Configs.TYPES = TYPES
function Configs.get(key) return BY_KEY[key] end

----------------------------------------------------------------
-- KNOWN CONFIGS
----------------------------------------------------------------
local SCAN_LIMIT    = 100000     -- highest id "Scan all" tries
local SCAN_PER_TICK = 400        -- ids tried per Logic update while scanning
local SCAN_GIVE_UP   = 5000       -- stop after this many empty ids in a row (once something has been found)

local known = {}                 -- type key -> { [configName] = { name = configName, id = number, text = search text } }
local counts = {}                -- type key -> how many are in known[key]
local walked = {}                -- type key -> true once the id table has been tried
local scans = {}                 -- type key -> { nextId = n, done = bool }

-- "ABYSSAL_HELM" -> "Abyssal Helm" (used when a config has no name of its own)
local function titleCase(configName)
    local words = configName:lower():gsub("_", " ")
    return (words:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function remember(key, configName, idNumber, displayName)
    if type(configName) ~= "string" or configName == "" then return end
    known[key] = known[key] or {}
    local entry = known[key][configName]
    if not entry then
        entry = { name = configName }
        known[key][configName] = entry
        counts[key] = (counts[key] or 0) + 1
    end
    entry.id = type(idNumber) == "number" and idNumber or entry.id
    if type(displayName) == "string" and displayName ~= "" then entry.display = displayName end
    entry.text = (configName .. " " .. (entry.display or "")):lower()
end

-- Walk the id table (id.NPC) if the API lets us
local function walkIds(def)
    if walked[def.key] then return end
    walked[def.key] = true
    pcall(function()
        for name, number in pairs(def.ids()) do remember(def.key, name, number) end
    end)
end

function Configs.count(key)
    local def = BY_KEY[key]
    walkIds(def)
    return counts[key] or 0
end

----------------------------------------------------------------
-- LOOKUP
----------------------------------------------------------------
-- A config by exact name or id; nil when there isn't one
function Configs.fetch(key, nameOrId)
    local def = BY_KEY[key]
    if not def then return nil end
    local ok, cfg = pcall(function()
        local number = tonumber(nameOrId)
        if number then return def.access().FromID(number) end
        return def.access()[nameOrId]
    end)
    if ok and cfg ~= nil and type(cfg) ~= "number" and type(cfg) ~= "string" then return cfg end
    return nil
end

local function property(cfg, field)
    local ok, value = pcall(function() return cfg[field] end)
    if ok then return value end
    return nil
end

-- A listed config by name, falling back to its id when the name lookup doesn't work
function Configs.open(key, name)
    local cfg = Configs.fetch(key, name)
    if cfg then return cfg end
    local entry = known[key] and known[key][name]
    if entry and entry.id then return Configs.fetch(key, entry.id) end
    return nil
end


----------------------------------------------------------------
-- HOW A RESULT IS SHOWN
----------------------------------------------------------------
Configs.DISPLAY_MODES = {
    { id = 1, label = "Config name" },
    { id = 2, label = "Name" },
    { id = 3, label = "ID" },
}

-- The config's own name ("Abyssal helm"), read once; configs without one get their config name tidied up
local function displayName(key, configName)
    local entry = known[key] and known[key][configName]
    if entry and entry.display then return entry.display end

    local cfg = Configs.open(key, configName)
    local name = cfg and property(cfg, "name")
    local shown = (type(name) == "string" and name ~= "") and name or titleCase(configName)
    if entry then
        entry.display = shown
        entry.text = (configName .. " " .. shown):lower()
    end
    return shown
end

-- The text for one row of the results, in the chosen display mode
function Configs.label(key, configName, number, mode)
    if mode == 2 then return displayName(key, configName) end
    if mode == 3 then
        if not number then
            local cfg = Configs.open(key, configName)
            number = cfg and property(cfg, "id")
            local entry = known[key] and known[key][configName]
            if entry and number then entry.id = number end
        end
        return number and tostring(number) or "?"
    end
    return configName
end

----------------------------------------------------------------
-- SEARCH
----------------------------------------------------------------
-- Every word of the query must appear in the name. A number (or exact name) is also looked up directly, so anything
-- can be found even if it was never listed. Returns up to `limit` { name, id } and how many matched in all.
function Configs.search(key, query, limit)
    local def = BY_KEY[key]
    query = tostring(query or "")
    local results, seen = {}, {}

    local function add(name, number)
        if name and not seen[name] then
            seen[name] = true
            results[#results + 1] = { name = name, id = number }
        end
    end

    -- an exact id / name typed in
    local trimmed = query:match("^%s*(.-)%s*$")
    if trimmed ~= "" and (tonumber(trimmed) or not trimmed:find("%s")) then
        local cfg = Configs.fetch(key, trimmed)
        local exactName = cfg and property(cfg, "configName")
        if type(exactName) == "string" then
            remember(key, exactName, property(cfg, "id"), property(cfg, "name"))
            add(exactName, property(cfg, "id"))
        end
    end

    local matches = {}
    walkIds(def)
    local terms = {}
    for word in query:lower():gmatch("%S+") do terms[#terms + 1] = word end
    for name, entry in pairs(known[key] or {}) do
        local text, ok = entry.text, true
        for _, term in ipairs(terms) do
            if not text:find(term, 1, true) then ok = false; break end
        end
        if ok then matches[#matches + 1] = name end
    end
    table.sort(matches)

    local total = #results
    for _, name in ipairs(matches) do
        if not seen[name] then total = total + 1 end
        if #results < limit then
            local entry = known[key] and known[key][name]
            add(name, entry and entry.id)
        end
    end
    return results, total
end

----------------------------------------------------------------
-- DESCRIBING A CONFIG
----------------------------------------------------------------
local function describe(value)
    local kind = type(value)
    if value == nil then return "-" end
    if kind == "boolean" or kind == "number" or kind == "string" then return tostring(value) end

    -- another config (QuestType, VarType ...): show its name
    local ok, configName = pcall(function() return value.configName end)
    if ok and type(configName) == "string" then return configName end

    -- a list: show how many, and the first few
    if kind == "table" then
        local parts, count = {}, 0
        for _, item in pairs(value) do
            count = count + 1
            if count <= 4 then parts[#parts + 1] = describe(item) end
        end
        if count == 0 then return "(empty)" end
        return "[" .. count .. "] " .. table.concat(parts, ", ") .. (count > 4 and ", ..." or "")
    end
    return tostring(value)
end

-- { { "name", "value as text" }, ... } for the fields of a type that the config actually has
function Configs.describe(key, cfg)
    local def = BY_KEY[key]
    local lines = {}
    for _, field in ipairs(def.fields) do
        local value = property(cfg, field)
        if value ~= nil then lines[#lines + 1] = { field, describe(value) } end
    end
    return lines
end

----------------------------------------------------------------
-- SCAN ALL
----------------------------------------------------------------
-- running: still going. Also how far it has got, how many were found and how many lookups failed.
function Configs.scanning(key)
    local scan = scans[key]
    if not scan then return false, 0, 0, 0 end
    return not scan.done, scan.nextId, scan.found, scan.errors
end

function Configs.startScan(key)
    local def = BY_KEY[key]
    if scans[key] and not scans[key].done then return false end
    walked[key] = nil
    scans[key] = { nextId = 0, dir = 1, done = false, found = 0, errors = 0, misses = 0, passFound = 0 }
    return true
end

-- Tries the next SCAN_PER_TICK ids. Var types are scanned upwards from 0, then downwards from -1 (VarBit ids are negative).
local function scanSlice(def, scan)
    for _ = 1, SCAN_PER_TICK do
        local number = scan.nextId
        local ok, cfg = pcall(function() return def.access().FromID(number) end)
        local configName = ok and cfg ~= nil and type(cfg) ~= "number" and property(cfg, "configName")
        if type(configName) == "string" and configName ~= "" then
            remember(def.key, configName, number, property(cfg, "name"))
            scan.found, scan.passFound, scan.misses = scan.found + 1, scan.passFound + 1, 0
        else
            if not ok then scan.errors = scan.errors + 1 end
            scan.misses = scan.misses + 1
        end
        scan.nextId = number + scan.dir

        -- ids are handed out in a dense run, so a long stretch with nothing means we are past the end
        local pastEnd = math.abs(scan.nextId) > SCAN_LIMIT or (scan.passFound > 0 and scan.misses >= SCAN_GIVE_UP)
        if pastEnd then
            if scan.dir == 1 and def.negative then
                scan.dir, scan.nextId, scan.misses, scan.passFound = -1, -1, 0, 0
            else
                scan.done = true
                return
            end
        end
    end
end

local function onLogic()
    for key, scan in pairs(scans) do
        if not scan.done then
            scanSlice(BY_KEY[key], scan)
            if Configs.onProgress then Configs.onProgress(key) end
            return   -- one type per update
        end
    end
end

-- vars the game sends (or varlist.lua names) are added to the browser as they appear
local VAR_KEYS = { player = "VarPlayer", client = "VarClient" }

function Configs.start()
    VarIndex.onNew = function(name, kind) remember(VAR_KEYS[kind], name) end
    VarIndex.start()
    Event.Logic.Subscribe("devtools_scan", onLogic)
end

function Configs.stop()
    VarIndex.stop()
    Event.Logic.Unsubscribe("devtools_scan")
end

return Configs
