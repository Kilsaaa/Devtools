--[[
    layers.lua - which top-level layer the Dev Tools window, the hover box and the NPC labels are drawn on.

    Everything is normally drawn on the game area, and other interfaces (backpack, bank ...) can sit in front of it. The
    documentation says plugin components belong on TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP, "a layer on the game window
    that appears above most game and interface components". "Auto" uses that layer. Other top-level layers
    (TOPLEVEL_V2__...) can be picked in the Overlays tab ("Draw on layer"), and the game area is the fallback.

    The layer chosen is remembered between sessions (by its position in the list).
]]

local UI = require("core/uiutil")

local Layers = {}

local PREFIX = "TOPLEVEL_V2__"
local SAVE = "devtoolsLayerIndex"
local AUTO = "Auto (a layer in front if there is one)"
local GAME = "Game area"
local PLUGIN_LAYER = PREFIX .. "PLUGIN_BUILD_LAYER_TOP"   -- the documented layer for plugin components
local PREFERRED = { "TOOLTIP", "POPUP", "OVERLAY", "MODAL", "FOREGROUND", "FRONT" }

Layers.onChange = nil          -- called after a different layer is chosen
local list = nil               -- { { name = "...", value = number } ... }, built once
local index = nil              -- chosen position in names()

local try = UI.try

local function found()
    if list then return list end
    list = {}
    pcall(function()
        for name, value in pairs(id.Component) do
            if type(name) == "string" and type(value) == "number" and string.sub(name, 1, #PREFIX) == PREFIX then
                list[#list + 1] = { name = name, value = value }
            end
        end
    end)
    -- the documented plugin layer is always offered, even if the id table can't be walked
    local has = false
    for _, entry in ipairs(list) do if entry.name == PLUGIN_LAYER then has = true end end
    if not has then
        local ok, value = pcall(function() return id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP end)
        if ok and type(value) == "number" then list[#list + 1] = { name = PLUGIN_LAYER, value = value } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- the names to choose from: Auto, Game area, then every top-level layer found
function Layers.names()
    local names = { AUTO, GAME }
    for _, entry in ipairs(found()) do
        if entry.name ~= PREFIX .. "GAME_AREA" then names[#names + 1] = entry.name end
    end
    return names
end

function Layers.index()
    if not index then
        local ok, saved = pcall(function() return PersistentDB:GetInt(SAVE) end)
        index = (ok and type(saved) == "number" and saved >= 1 and saved <= #Layers.names()) and saved or 1
    end
    return index
end

-- back to Auto without redrawing anything (the window is rebuilt by whoever asked)
function Layers.reset()
    index = 1
    pcall(function() PersistentDB:SetInt(SAVE, 1) end)
end

function Layers.set(newIndex)
    if newIndex == index then return end
    index = newIndex
    pcall(function() PersistentDB:SetInt(SAVE, newIndex) end)
    if Layers.onChange then pcall(Layers.onChange) end
end

local function component(value, trusted)
    local ok, c = pcall(function() return ui.Interfaces:GetComponent(value) end)
    if not ok or not c then return nil end
    -- only a layer that can hold other components is any use (the documented plugin layer is known to be one)
    if not trusted and type(try(c, "IterateStaticComponents")) ~= "function" then return nil end
    return c
end

local function gameArea()
    local ok, area = pcall(function() return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) end)
    if ok then return area end
    return nil
end

-- every layer that can be drawn on: { { name = ..., component = ... } ... }, for the "where does each layer draw" test
function Layers.all()
    local result = {}
    local area = gameArea()
    if area then result[#result + 1] = { name = "TOPLEVEL_V2__GAME_AREA", component = area } end
    for _, entry in ipairs(found()) do
        if entry.name ~= PREFIX .. "GAME_AREA" then
            local c = component(entry.value, entry.name == PLUGIN_LAYER)
            if c then result[#result + 1] = { name = entry.name, component = c } end
        end
    end
    return result
end

-- the component to draw on, and its name
function Layers.parent()
    local names = Layers.names()
    local name = names[Layers.index()] or AUTO

    if name == AUTO then
        for _, entry in ipairs(found()) do
            if entry.name == PLUGIN_LAYER then
                local c = component(entry.value, true)
                if c then return c, entry.name end
            end
        end
        for _, keyword in ipairs(PREFERRED) do
            for _, entry in ipairs(found()) do
                if string.find(entry.name, keyword, 1, true) then
                    local c = component(entry.value)
                    if c then return c, entry.name end
                end
            end
        end
    elseif name ~= GAME then
        for _, entry in ipairs(found()) do
            if entry.name == name then
                local c = component(entry.value, name == PLUGIN_LAYER)
                if c then return c, name end
            end
        end
    end
    return gameArea(), "TOPLEVEL_V2__GAME_AREA"
end

return Layers
