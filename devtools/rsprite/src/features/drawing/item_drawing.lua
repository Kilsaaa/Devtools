local Arguments = require("rsprite/src/utils/arguments")
local Client = require("rsprite/src/services/client")
local NumberText = require("rsprite/src/utils/number_text")
local Placeholder = require("rsprite/src/components/placeholder")
local SpriteContents = require("rsprite/src/features/drawing/sprite_contents")
local SpriteDrawing = require("rsprite/src/features/drawing/sprite_drawing")
local Warnings = require("rsprite/src/services/warnings")
local WholeNumber = require("rsprite/src/utils/whole_number")

local ItemDrawing = {}

local SET_ITEM_OPTION_TYPES = {
    quantity = "number",
    placeholder = "boolean",
}

local DRAW_ITEM_OPTION_TYPES =
    Arguments.CombineTypes(SpriteDrawing.LAYOUT_OPTION_TYPES, SET_ITEM_OPTION_TYPES)

local function optionsProblem(functionName, options, expectedTypes)
    return Arguments.OptionsProblem(functionName, options, expectedTypes)
        or Arguments.WholeNumberOptionProblem(functionName, options, "quantity")
end

local function setItemProperty(sprite, propertyName, value)
    return Warnings.IfFailed(
        "item " .. propertyName,
        "setting " .. propertyName .. " on an item sprite",
        Client.SetProperty(sprite, propertyName, value)
    )
end

local function clearArt(sprite, mayHoldOldArt)
    if mayHoldOldArt then
        Warnings.IfFailed(
            "clear item",
            "clearing item art",
            Client.SetAssociatedObject(sprite, SpriteContents.CLEARED_ITEM)
        )
        SpriteContents.ForgetItem(sprite)
    end
end

local function showPlaceholder(sprite, options, mayHoldOldArt)
    clearArt(sprite, mayHoldOldArt)
    Placeholder.Show(sprite, options.placeholder ~= false)
    return false
end

local function showItem(sprite, itemId, options, mayHoldOldArt)
    setItemProperty(sprite, "hidden", true)
    if itemId == nil then
        clearArt(sprite, mayHoldOldArt)
        return false
    end
    local wholeId = WholeNumber.From(itemId)
    if wholeId == nil then
        local outcome = options.placeholder ~= false and "the placeholder is shown instead"
            or "nothing is shown"
        local idText = NumberText.Describe(itemId)
        Warnings.Once(
            "item id " .. idText,
            "item id " .. idText .. " is not a whole number 0 or above, so " .. outcome
        )
        return showPlaceholder(sprite, options, mayHoldOldArt)
    end
    local description = "drawing item " .. wholeId
    if
        not Warnings.IfFailed(description, description, Client.SetAssociatedObject(sprite, wholeId))
    then
        return showPlaceholder(sprite, options, true)
    end
    SpriteContents.NoteItem(sprite)
    if options.quantity ~= nil then
        setItemProperty(
            sprite,
            "associatedObjectQuantityMode",
            Client.QuantityDisplayMode("ALWAYS")
        )
        setItemProperty(sprite, "associatedObjectQuantity", options.quantity)
    else
        setItemProperty(sprite, "associatedObjectQuantityMode", Client.QuantityDisplayMode("NEVER"))
    end
    setItemProperty(sprite, "hidden", false)
    return true
end

function ItemDrawing.DrawItem(parent, itemId, options)
    local problem = Arguments.ComponentProblem("rsprite.DrawItem", "parent", parent)
        or optionsProblem("rsprite.DrawItem", options, DRAW_ITEM_OPTION_TYPES)
        or SpriteDrawing.LayoutProblem("rsprite.DrawItem", options)
    if problem ~= nil then
        error(problem, 2)
    end
    local resolvedOptions = options or {}
    local sprite = SpriteDrawing.CreateLaidOut(parent, resolvedOptions)
    if sprite == nil then
        return nil
    end
    showItem(sprite, itemId, resolvedOptions, false)
    return sprite
end

function ItemDrawing.SetItem(sprite, itemId, options)
    local problem = Arguments.ComponentProblem("rsprite.SetItem", "sprite", sprite)
        or optionsProblem("rsprite.SetItem", options, SET_ITEM_OPTION_TYPES)
    if problem ~= nil then
        error(problem, 2)
    end
    return showItem(sprite, itemId, options or {}, true)
end

return ItemDrawing
