--[[
    componentinfo.lua - describing a game component in words: its id, a one-line summary for the tree, the text a filter searches, the
    property list shown on the right of the Interface tab, and the Lua that finds it again.
]]

local UI = require("core/uiutil")
local Names = require("tabs/interface/componentnames")

local Info = {}

local try = UI.try

local function yesNo(value) return value and "yes" or "no" end

-- the sprite id of a component (a number, which may be -1 for "none"), or nil when it has no sprite property
function Info.spriteOf(component)
    for _, field in ipairs({ "spriteID", "spriteId" }) do
        local sprite = try(component, field)
        if type(sprite) == "number" then return sprite, field end
    end
    return nil
end

local function isDynamic(component)
    local dynamicID = try(component, "dynamicID")
    return type(dynamicID) == "number" and dynamicID >= 0
end

-- "20" for a static component, "20,2,7" (static, category, dynamic) for a dynamic one
function Info.idString(component)
    local static = tostring(try(component, "staticID") or "?")
    if isDynamic(component) then
        return static .. "," .. tostring(try(component, "categoryID")) .. "," .. try(component, "dynamicID")
    end
    return static
end

-- "S 20" for a static component, "D 20,2,7" for a dynamic one
function Info.tag(component)
    return (isDynamic(component) and "D " or "S ") .. Info.idString(component)
end

-- the name of an item (obj) by id, if it can be found
local function itemName(objectID)
    local ok, name = pcall(function() return config.Obj.FromID(objectID).name end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function objectOf(component)
    local objectID = try(component, "associatedObjectID")
    if type(objectID) == "number" and objectID >= 0 then return objectID end
    return nil
end

----------------------------------------------------------------
-- SPRITE NAMES (id.Sprite.NAME gives a number)
----------------------------------------------------------------
-- Every name has to be looked up to find which number it is, so it is done a few thousand at a time on the game's updates
-- (Info.stepSpriteNames, called from the tab's tick) and the details are drawn again at the end.
local spriteNameByValue = {}
local spriteKeys, spriteIndex = nil, 1
local SPRITE_BATCH = 3000

function Info.startSpriteNames()
    if spriteKeys then return end
    spriteKeys = {}
    pcall(function()
        for key, value in pairs(id.Sprite) do
            spriteKeys[#spriteKeys + 1] = type(key) == "number" and tostring(value) or tostring(key)
        end
    end)
end

-- does the next batch of sprite names; returns true on the call that finishes the list
function Info.stepSpriteNames()
    if not spriteKeys or spriteIndex > #spriteKeys then return false end
    local last = math.min(spriteIndex + SPRITE_BATCH - 1, #spriteKeys)
    for i = spriteIndex, last do
        local name = spriteKeys[i]
        local ok, value = pcall(function() return id.Sprite[name] end)
        if ok and type(value) == "number" and spriteNameByValue[value] == nil then spriteNameByValue[value] = name end
    end
    spriteIndex = last + 1
    return spriteIndex > #spriteKeys
end

-- lets go of the sprite names (tens of thousands of entries) when the plugin is turned off
function Info.shutdown()
    spriteNameByValue, spriteKeys, spriteIndex = {}, nil, 1
end

----------------------------------------------------------------
-- DESCRIPTIONS
----------------------------------------------------------------
-- a short description for a list row: type, text or sprite, then the size spelled out
function Info.summary(component)
    local text = tostring(try(component, "type") or "?")

    local content = try(component, "content")
    if type(content) == "string" and content ~= "" then
        if #content > 22 then content = string.sub(content, 1, 22) .. "..." end
        text = text .. ' "' .. content .. '"'
    end
    local sprite = Info.spriteOf(component)
    if sprite then text = text .. "  sprite " .. (spriteNameByValue[sprite] or sprite) end

    local objectID = objectOf(component)
    if objectID then text = text .. "  item " .. (itemName(objectID) or objectID) end

    local w, h = try(component, "width"), try(component, "height")
    if type(w) == "number" and type(h) == "number" then text = text .. "  w " .. w .. "  h " .. h end
    return text
end

-- all the text a filter should look at for one component: its type, text, sprite and item
function Info.searchText(component)
    local parts = { tostring(try(component, "type") or ""), Info.tag(component) }
    local content = try(component, "content")
    if type(content) == "string" then parts[#parts + 1] = content end
    local sprite = Info.spriteOf(component)
    if sprite then parts[#parts + 1] = "sprite " .. sprite end
    local objectID = objectOf(component)
    if objectID then parts[#parts + 1] = "item " .. objectID .. " " .. (itemName(objectID) or "") end
    return string.lower(table.concat(parts, " "))
end

-- every property worth knowing, named in full, as { name, value, key } (the key says which property it is, for editing; nil when the
-- property can't be edited)
function Info.details(component)
    local list = {}
    local function add(name, value, key)
        if value ~= nil then list[#list + 1] = { name, tostring(value), key } end
    end

    -- the first twelve rows are always the same ones, so the sprite can sit beside "Y on screen"
    add("Interface id", try(component, "interfaceID"))
    add("Kind", isDynamic(component) and "D (dynamic)" or "S (static)")
    add("Asset name", Names.nameOf(component) or "none")
    add("Type", try(component, "type") or "?")
    add("Component id", Info.idString(component))
    local parent = try(component, "parent")
    add("Parent component id", parent and Info.idString(parent) or "none")
    add("X (from its parent's left)", try(component, "x") or "?", "x")
    add("Y (from its parent's top)", try(component, "y") or "?", "y")
    add("Width", try(component, "width") or "?", "width")
    add("Height", try(component, "height") or "?", "height")
    local global = try(component, "xyGlobal")
    add("X on screen", global and try(global, "x") or "?")
    add("Y on screen", global and try(global, "y") or "?")

    add("Static component id", try(component, "staticID"))
    if isDynamic(component) then
        add("Dynamic category id", try(component, "categoryID"))
        add("Dynamic id", try(component, "dynamicID"))
    end
    local parentStatic = try(component, "parentStatic")
    if parentStatic then add("Parent static component id", try(parentStatic, "staticID")) end
    -- in case the game offers a name some other way: look for any text property that sounds like one
    for _, field in ipairs({ "name", "configName", "assetName", "debugName", "identifier", "label", "title" }) do
        local value = try(component, field)
        if type(value) == "string" and value ~= "" then add("Property " .. field, value) end
    end
    local okText, asText = pcall(tostring, component)
    if okText and type(asText) == "string" then add("As text", asText) end

    local visible = try(component, "visible")
    if visible ~= nil then add("Visible", yesNo(visible)) end
    local visibleGlobal = try(component, "visibleGlobal")
    if visibleGlobal ~= nil then add("Visible (and every parent visible)", yesNo(visibleGlobal)) end
    local hidden = try(component, "hidden")
    if hidden ~= nil then add("Hidden by a plugin", yesNo(hidden), "hidden") end
    local enabled = try(component, "enabled")
    if enabled ~= nil then add("Responds to clicks", yesNo(enabled), "enabled") end
    local clickthrough = try(component, "clickthrough")
    if clickthrough ~= nil then add("Clicks pass through", yesNo(clickthrough), "clickthrough") end
    add("Opacity (0 to 1)", try(component, "alpha"), "alpha")
    local rgba = try(component, "rgba")
    if type(rgba) == "number" then add("Colour (RGBA hex)", string.format("%08X", rgba), "rgba") end

    local content = try(component, "content")
    if type(content) == "string" and content ~= "" then add("Text", content, "content") end
    add("Font id", try(component, "font"), "font")
    local sprite = Info.spriteOf(component)
    if sprite then
        add("Sprite id", sprite, "sprite")
        add("Sprite name", spriteNameByValue[sprite])
    end
    local objectID = objectOf(component)
    if objectID then
        add("Item (obj) id", objectID)
        add("Item name", itemName(objectID))
    end
    return list
end

-- the Lua that finds this component again: by its game name when it has one, otherwise by interface and component id
function Info.lookupCode(component)
    local interfaceNumber, staticNumber = try(component, "interfaceID"), try(component, "staticID")
    if type(interfaceNumber) ~= "number" or type(staticNumber) ~= "number" then return "" end
    local name = Names.nameOf(component)
    local code
    if name and not isDynamic(component) then
        code = "local c = ui.Interfaces:GetComponent(id.Component." .. name .. ")  -- " .. interfaceNumber .. ", " .. staticNumber
    else
        code = "local c = ui.Interfaces:GetComponent(" .. interfaceNumber .. ", " .. staticNumber .. ")"
    end
    if isDynamic(component) then
        code = code .. "  -- this is dynamic (category " .. tostring(try(component, "categoryID")) .. ", id " .. try(component, "dynamicID") .. "): it is one of this static component's children"
    end
    return code
end

return Info