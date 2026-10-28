local Arguments = require("rsprite/src/utils/arguments")
local Client = require("rsprite/src/services/client")
local Placeholder = require("rsprite/src/components/placeholder")
local SourceChain = require("rsprite/src/features/drawing/source_chain")
local SpriteContents = require("rsprite/src/features/drawing/sprite_contents")
local Warnings = require("rsprite/src/services/warnings")

local SpriteDrawing = {}

SpriteDrawing.DEFAULT_SIZE = 24

SpriteDrawing.LAYOUT_OPTION_TYPES = {
    x = "number",
    y = "number",
    xAnchor = "number",
    yAnchor = "number",
    size = "number",
    width = "number",
    height = "number",
}

local APPEARANCE_OPTION_TYPES = {
    colour = "number",
    alpha = "number",
    placeholder = "boolean",
}

local DRAW_OPTION_TYPES =
    Arguments.CombineTypes(SpriteDrawing.LAYOUT_OPTION_TYPES, APPEARANCE_OPTION_TYPES)

local SIZE_OPTIONS = { "size", "width", "height" }
local POSITION_OPTIONS = { "x", "y", "xAnchor", "yAnchor" }

function SpriteDrawing.LayoutProblem(functionName, options)
    for _, optionName in ipairs(SIZE_OPTIONS) do
        local problem = Arguments.SizeOptionProblem(functionName, options, optionName)
        if problem ~= nil then
            return problem
        end
    end
    for _, optionName in ipairs(POSITION_OPTIONS) do
        local problem = Arguments.FiniteOptionProblem(functionName, options, optionName)
        if problem ~= nil then
            return problem
        end
    end
    return nil
end

function SpriteDrawing.CreateLaidOut(parent, options)
    local created, sprite = Client.CreateSprite(parent)
    if not Warnings.IfFailed("create sprite", "creating a sprite", created, sprite) then
        return nil
    end
    local size = options.size or SpriteDrawing.DEFAULT_SIZE
    Warnings.IfFailed(
        "position sprite",
        "positioning a sprite",
        Client.SetPosition(
            sprite,
            options.x or 0,
            options.y or 0,
            options.xAnchor or 0,
            options.yAnchor or 0
        )
    )
    Warnings.IfFailed(
        "size sprite",
        "sizing a sprite",
        Client.SetSize(sprite, options.width or size, options.height or size)
    )
    Warnings.IfFailed(
        "clickthrough sprite",
        "making a sprite clickthrough",
        Client.SetProperty(sprite, "clickthrough", true)
    )
    return sprite
end

local function applySource(sprite, chain, options)
    if options.colour ~= nil then
        Warnings.IfFailed(
            "colour",
            "setting a sprite colour",
            Client.SetProperty(sprite, "rgba", options.colour)
        )
    end
    if options.alpha ~= nil then
        Warnings.IfFailed(
            "alpha",
            "setting a sprite alpha",
            Client.SetProperty(sprite, "alpha", options.alpha)
        )
    end
    local source, position = SourceChain.ResolveEntries(chain)
    if source ~= nil then
        local description = "drawing sprite " .. tostring(source)
        if
            Warnings.IfFailed(
                description,
                description,
                Client.SetProperty(sprite, "sprite", source)
            )
        then
            Warnings.IfFailed(
                "show sprite",
                "showing a sprite",
                Client.SetProperty(sprite, "hidden", false)
            )
            return position
        end
    end
    Placeholder.Show(sprite, options.placeholder ~= false)
    return nil
end

function SpriteDrawing.SetSource(sprite, nameOrChain, options)
    local problem = Arguments.ComponentProblem("rsprite.SetSource", "sprite", sprite)
        or Arguments.OptionsProblem("rsprite.SetSource", options, APPEARANCE_OPTION_TYPES)
    if problem ~= nil then
        error(problem, 2)
    end
    local chain, chainProblem = SourceChain.Entries("rsprite.SetSource", nameOrChain)
    if chain == nil then
        error(chainProblem, 2)
    end
    if SpriteContents.HasItem(sprite) then
        Warnings.IfFailed(
            "hide item sprite",
            "hiding an item sprite",
            Client.SetProperty(sprite, "hidden", true)
        )
        SpriteContents.ClearItem(sprite)
    end
    return applySource(sprite, chain, options or {})
end

function SpriteDrawing.Draw(parent, nameOrChain, options)
    local problem = Arguments.ComponentProblem("rsprite.Draw", "parent", parent)
        or Arguments.OptionsProblem("rsprite.Draw", options, DRAW_OPTION_TYPES)
        or SpriteDrawing.LayoutProblem("rsprite.Draw", options)
    if problem ~= nil then
        error(problem, 2)
    end
    local chain, chainProblem = SourceChain.Entries("rsprite.Draw", nameOrChain)
    if chain == nil then
        error(chainProblem, 2)
    end
    local resolvedOptions = options or {}
    local sprite = SpriteDrawing.CreateLaidOut(parent, resolvedOptions)
    if sprite == nil then
        return nil, nil
    end
    return sprite, applySource(sprite, chain, resolvedOptions)
end

return SpriteDrawing
