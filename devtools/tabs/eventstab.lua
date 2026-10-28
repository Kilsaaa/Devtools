--[[
    eventstab.lua - the "Events" tab: one toggle per game event. While a toggle is on, every time that event fires a
    line describing it is printed to the developer console.

    Each button says what it will do next ("Turn on" / "Turn off"). Everything starts off, and every listener is
    removed when the plugin shuts down. To add an event, add an entry to EVENTS below.

    Printing is off by default (events are only counted). When on, a line is logged the same way a normal plugin does
    it, at most 20 lines a second. VarTransmit fires for every var, so the filter box narrows it to vars whose name matches (empty = all, capped).
]]

local UI = require("core/uiutil")

local EventsTab = {}

----------------------------------------------------------------
-- DESCRIBING THINGS FOR THE CONSOLE
----------------------------------------------------------------
-- Text for any value: numbers and strings as they are, configs by their config name, other objects by their name
local function show(value)
    local kind = type(value)
    if value == nil then return "nil" end
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return value end

    for _, field in ipairs({ "configName", "name" }) do
        local ok, text = pcall(function() return value[field] end)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    if kind == "table" then
        local count = 0
        for _ in pairs(value) do count = count + 1 end
        return "[" .. count .. " items]"
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "?"
end

-- "a=1 b=name" for the given fields of the event payload
local function fields(...)
    local names = { ... }
    return function(e)
        local parts = {}
        for _, name in ipairs(names) do
            local ok, value = pcall(function() return e[name] end)
            parts[#parts + 1] = name .. "=" .. show(ok and value or nil)
        end
        return table.concat(parts, "  ")
    end
end

-- an entity (NPC / player) with its name, plus any extra fields
local function entity(key, ...)
    local extra = fields(...)
    return function(e)
        local ok, ent = pcall(function() return e[key] end)
        local name = "?"
        if ok and ent ~= nil then
            local named, nameText = pcall(function() return ent.name or ent.config.name end)
            name = named and show(nameText) or show(ent)
        end
        return key .. "=" .. name .. "  " .. extra(e)
    end
end

----------------------------------------------------------------
-- THE EVENTS (from https://developer.runescape.com/rs/core/events.html)
----------------------------------------------------------------
-- name:   the event, as in Event.<name>
-- format: builds the console line from the event's payload
-- every:  only report every Nth time (for events that fire constantly)
-- busy:   fires a lot - marked in the list
-- what each event is, shown when hovering its name or button
local TIPS = {
    VarTransmit = "A var (VarPlayer / VarClient / VarBit) changed. Fires very often. Gives the var, old value and new value.",
    SkillTransmit = "A skill's XP or level changed. Gives the skill, old/new XP and old/new level.",
    RunEnergyTransmit = "Run energy changed.",
    RunWeightTransmit = "Carried weight changed.",
    InventoryAdded = "An inventory (backpack, bank, worn items, etc.) was loaded or created.",
    InventoryUpdated = "Items in an inventory changed. Says which slots.",
    InventoryRemoved = "An inventory was unloaded.",
    GrandExchangeOfferUpdated = "A Grand Exchange offer slot changed.",
    NPCEntityAdded = "An NPC came into view (or was added to the game world).",
    NPCEntityRemoved = "An NPC left view, died or was removed.",
    PlayerEntityAdded = "A player came into view.",
    PlayerEntityRemoved = "A player left view.",
    ObjStackEntityAdded = "A pile of ground items appeared.",
    ObjStackEntityRemoved = "A pile of ground items disappeared.",
    ObjStackEntityChanged = "The amount in a ground item pile changed.",
    LocAdded = "A scenery object (tree, door, rock, etc.) was added to the world.",
    LocRemoved = "A scenery object was removed.",
    LocCustomised = "A scenery object had its models or colours changed.",
    LocAnimation = "A scenery object started an animation.",
    WorldCreated = "The game world (map area) was created or reloaded.",
    WorldUpdated = "The game world was updated.",
    RegionCreated = "A region (an instanced or dynamic map area) was created.",
    RegionUpdated = "A region was updated.",
    MiniMenuOpened = "The right-click menu opened.",
    MiniMenuClosed = "The right-click menu closed.",
    MiniMenuReady = "The menu entries were worked out (fires every tick while hovering). Fires a lot.",
    MiniMenuEntryAdded = "A menu entry was added to the list.",
    MiniMenuEntrySelected = "A menu entry was chosen (clicked).",
    KeyDown = "A key was pressed down (repeats while held).",
    KeyUp = "A key was released.",
    KeyTyped = "A character was typed.",
    ChatMessage = "A chat message arrived. Needs the chat permission to be granted.",
    GameStateChanged = "The game state changed (for example logging in, loading, or logging out).",
    WindowFocusChanged = "The game window gained or lost focus.",
    WindowSizeChanged = "The game window was resized.",
    ServerLogic = "A server tick (about every 0.6 seconds).",
    Logic = "A client update (50 times a second). Printed every 50th.",
    Draw = "A frame was drawn. Printed every 120th.",
    EntityDraw = "An entity (NPC, player or ground item) was drawn. Fires a lot. Printed every 120th.",
    OptionalDependencyChanged = "An optional plugin dependency was turned on or off.",
    OptionalPermissionChanged = "An optional permission (such as chat access) was granted or taken away.",
    SettingsLayerReady = "This plugin's settings page opened.",
    ContentLayerReady = "This plugin's ribbon page opened.",
}

local EVENTS = {
    { name = "VarTransmit", busy = true, format = function(e)
        -- only the same reads the working plugins use: tostring on the var, plain old/new values
        return tostring(e.var) .. "  " .. tostring(e.oldValue) .. " -> " .. tostring(e.newValue)
    end },
    { name = "SkillTransmit", format = fields("skill", "oldXP", "newXP", "oldGameplayLevel", "newGameplayLevel") },
    { name = "RunEnergyTransmit", format = fields("oldRunEnergy", "newRunEnergy") },
    { name = "RunWeightTransmit", format = fields("oldRunWeight", "newRunWeight") },
    { name = "InventoryAdded", format = fields("inv") },
    { name = "InventoryUpdated", format = fields("inv", "slotsUpdated") },
    { name = "InventoryRemoved", format = fields("inv") },
    { name = "GrandExchangeOfferUpdated", format = fields("slot", "listing") },

    { name = "NPCEntityAdded", format = entity("npcEntity", "entityType") },
    { name = "NPCEntityRemoved", format = entity("npcEntity", "entityType") },
    { name = "PlayerEntityAdded", format = entity("playerEntity", "entityType") },
    { name = "PlayerEntityRemoved", format = entity("playerEntity", "entityType") },
    { name = "ObjStackEntityAdded", format = fields("objType", "count", "isOwner") },
    { name = "ObjStackEntityRemoved", format = fields("objType", "count", "isOwner") },
    { name = "ObjStackEntityChanged", format = fields("objType", "oldCount", "newCount", "isOwner") },

    { name = "LocAdded", busy = true, format = fields("config", "shapeType", "rotationType", "coordGrid") },
    { name = "LocRemoved", busy = true, format = fields("shapeType", "rotationType", "coordGrid") },
    { name = "LocCustomised", format = fields("config", "shapeType", "coordGrid") },
    { name = "LocAnimation", busy = true, format = fields("animation", "animationDelay", "coordGrid") },
    { name = "WorldCreated", format = fields("mapSquareMinX", "mapSquareMinZ", "mapSquareMaxX", "mapSquareMaxZ") },
    { name = "WorldUpdated", format = fields() },
    { name = "RegionCreated", format = fields("mapSquareMinX", "mapSquareMinZ", "regionGridWidth", "regionGridLength") },
    { name = "RegionUpdated", format = fields() },

    { name = "MiniMenuOpened", format = fields() },
    { name = "MiniMenuClosed", format = fields() },
    { name = "MiniMenuReady", format = fields() },
    { name = "MiniMenuEntrySelected", format = fields("entry") },
    { name = "MiniMenuEntryAdded", busy = true, format = fields("entry") },

    { name = "KeyDown", busy = true, format = fields("gameKey", "systemKey", "modifiers", "isRepeat") },
    { name = "KeyUp", format = fields("gameKey", "systemKey", "modifiers") },
    { name = "KeyTyped", format = function(e)
        local ok, text = pcall(string.char, e.char)
        return "char=" .. (ok and text or show(e.char)) .. "  modifiers=" .. show(e.modifiers)
    end },
    { name = "ChatMessage", format = fields("chatType", "senderNameSimple", "chatMessage") },

    { name = "GameStateChanged", format = fields("oldState", "newState") },
    { name = "WindowFocusChanged", format = fields("hasFocus") },
    { name = "WindowSizeChanged", format = fields("oldWidth", "oldHeight", "newWidth", "newHeight") },
    { name = "ServerLogic", busy = true, every = 5, format = fields() },
    { name = "Logic", busy = true, every = 50, format = fields("logicTick") },
    { name = "Draw", busy = true, every = 120, format = fields("timeDeltaSecs") },
    { name = "EntityDraw", busy = true, every = 120, format = fields("entityType") },
    { name = "OptionalDependencyChanged", format = fields("pluginIdentifier", "enabled") },
    { name = "OptionalPermissionChanged", format = fields("permissionName", "enabled") },
    { name = "SettingsLayerReady", format = fields() },
    { name = "ContentLayerReady", format = fields() },
}

----------------------------------------------------------------
-- LAYOUT
----------------------------------------------------------------
local COLUMNS      = 2
local LABEL_WIDTH  = 250
local BUTTON_WIDTH = 100
local COLUMN_GAP   = 90           -- space between the two columns
local REFRESH_EVERY = 50          -- Logic updates between refreshes of the counts shown (about 0.5 s)

local MAX_PER_SECOND = 20        -- most console lines per second, so nothing can flood it

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}               -- statusText, lastText
local rows = {}                   -- event name -> { label, button }
local running = {}                -- event name -> { count, seen, last }
local dirty = false               -- counts changed since the labels were last refreshed
local ticks = 0
local varSeen, lastVarText = 0, "-"   -- how many VarTransmit were looked at, and what the last one looked like
local linesThisSecond = 0       -- lines printed in the current second
local varFilter = ""             -- VarTransmit prints only vars whose name contains this
local printing = true             -- every event prints a line to the developer console

local function refName(name) return "devtools_event_" .. name end
local function status(text) UI.setText(controls.statusText, text) end

----------------------------------------------------------------
-- THE LISTENERS
----------------------------------------------------------------
local function labelText(def)
    local state = running[def.name]
    local text = def.name .. (def.busy and " *" or "")
    if state then text = text .. "  - ON (" .. state.count .. ")" end
    return text
end

local function refreshRow(def)
    local row = rows[def.name]
    if not row then return end
    UI.setText(row.label, labelText(def))
    if running[def.name] then
        UI.setButton(row.button, "Turn off", "negative")
    else
        UI.setButton(row.button, "Turn on", "positive")
    end
end

-- Called inside the event. Logs directly, the same way a normal plugin does, but only when printing is on,
-- (for VarTransmit) only for vars matching the filter box, and at most MAX_PER_SECOND lines a second.
local function report(def, state, payload)
    state.count = state.count + 1
    dirty = true
    if not printing then return end
    if def.every and state.count % def.every ~= 0 then return end
    if linesThisSecond >= MAX_PER_SECOND then return end

    local line
    if def.name == "VarTransmit" then
        local v = payload.var
        local names = { tostring(v) }
        for _, field in ipairs({ "configName", "name" }) do
            local ok, text = pcall(function() return v[field] end)
            if ok and type(text) == "string" and text ~= "" then names[#names + 1] = text end
        end
        local name = names[2] or names[1]
        varSeen = (varSeen or 0) + 1
        lastVarText = table.concat(names, " | ")

        local want = string.lower(varFilter)
        local matched = want == ""   -- empty filter: every var (the line cap keeps the console safe)
        for _, text in ipairs(names) do
            if not matched and string.find(string.lower(text), want, 1, true) then matched = true end
        end
        if not matched then   -- the way a normal plugin does it: compare with the var itself
            for _, table_ in ipairs({ "VarPlayer", "Player", "VarClient" }) do
                local ok, same = pcall(function() return v == var[table_][varFilter] end)
                if ok and same then matched = true; name = varFilter end
            end
        end
        if not matched then return end
        line = "[VarTransmit] Value change: " .. name .. "  " .. tostring(payload.oldValue) .. " -> " .. tostring(payload.newValue)
    else
        local ok, text = pcall(def.format, payload or {})
        line = "[" .. def.name .. "] " .. (ok and text or "(couldn't read the payload)")
    end
    linesThisSecond = linesThisSecond + 1
    log(line)
end

local function turnOn(def)
    local state = { count = 0 }
    local ok, err = pcall(function()
        Event[def.name].Subscribe(refName(def.name), function(payload) report(def, state, payload) end)
    end)
    if not ok then return status("Couldn't listen for " .. def.name .. ": " .. tostring(err)) end
    running[def.name] = state
end

local function turnOff(def)
    pcall(function() Event[def.name].Unsubscribe(refName(def.name)) end)
    running[def.name] = nil
end

local function toggle(def)
    if running[def.name] then turnOff(def) else turnOn(def) end
    refreshRow(def)
end

local function turnAllOff()
    for _, def in ipairs(EVENTS) do
        if running[def.name] then turnOff(def); refreshRow(def) end
    end
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function EventsTab.build(page)
    page:AddText({ text = "Only print vars containing:", width = 190, columnGap = 0 })
    controls.filter = page:AddTextField({
        width = 250, placeholder = "part of a var name (empty = all)", inline = true, columnGap = 0,
        onChange = function(field) varFilter = UI.fieldText(field) or "" end,
    })
    -- the button sits in the top right corner, on the same line (the empty text pushes it across)
    page:AddText({ text = "", width = 290, inline = true, columnGap = 0 })
    page:AddSimpleButton("Turn everything off", turnAllOff, {
        width = 190, inline = true, columnGap = 0, tooltip = "Stop every listener",
    })
    page:AddDivider(UI.TIGHT_DIVIDER)

    rows = {}
    for index, def in ipairs(EVENTS) do
        local column = (index - 1) % COLUMNS
        local last = column == COLUMNS - 1 or index == #EVENTS

        -- label, then its button; the second column is on the same line as the first
        local label = page:AddText({
            text = labelText(def), width = LABEL_WIDTH, columnGap = 0, inline = column > 0, tooltip = TIPS[def.name],
        })
        local button = page:AddFancyButton("Turn on", function() toggle(def) end, {
            variant = "positive", width = BUTTON_WIDTH, inline = true, columnGap = last and 0 or COLUMN_GAP,
            tooltip = TIPS[def.name],
        })
        rows[def.name] = { label = label, button = button }
        refreshRow(def)
    end

    controls.statusText = page:AddText({ text = "" })
end

function EventsTab.release()
    controls, rows = {}, {}
end

-- keeps the "N seen" counts up to date without redrawing on every event
function EventsTab.onVarChanged() end
function EventsTab.onScanProgress() end

function EventsTab.tick()
    ticks = ticks + 1
    if ticks % 50 == 0 then linesThisSecond = 0 end
    if not dirty or ticks % REFRESH_EVERY ~= 0 then return end
    dirty = false
    for _, def in ipairs(EVENTS) do
        if running[def.name] then UI.setText(rows[def.name] and rows[def.name].label, labelText(def)) end
    end
end

-- the Dev Tools window was closed: the key events fire on every key press, so they are not left running with nothing to look at them
local KEY_EVENTS = { KeyDown = true, KeyUp = true, KeyTyped = true }
function EventsTab.stopKeyEvents()
    for _, def in ipairs(EVENTS) do
        if KEY_EVENTS[def.name] and running[def.name] then
            turnOff(def)
            refreshRow(def)
        end
    end
end

-- the plugin is shutting down: remove every listener
function EventsTab.shutdown()
    for _, def in ipairs(EVENTS) do
        if running[def.name] then turnOff(def) end
    end
end

return EventsTab
