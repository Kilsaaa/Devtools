local Client = require("rsprite/src/services/client")
local Warnings = require("rsprite/src/services/warnings")

local SpriteContents = {}

SpriteContents.CLEARED_ITEM = -1

local spritesWithItems = setmetatable({}, { __mode = "k" })

function SpriteContents.NoteItem(sprite)
    spritesWithItems[sprite] = true
end

function SpriteContents.ForgetItem(sprite)
    spritesWithItems[sprite] = nil
end

function SpriteContents.HasItem(sprite)
    return spritesWithItems[sprite] == true
end

function SpriteContents.ClearItem(sprite)
    Warnings.IfFailed(
        "clear item",
        "clearing item art",
        Client.SetAssociatedObject(sprite, SpriteContents.CLEARED_ITEM)
    )
    Warnings.IfFailed(
        "clear item quantity",
        "clearing an item quantity",
        Client.SetProperty(
            sprite,
            "associatedObjectQuantityMode",
            Client.QuantityDisplayMode("NEVER")
        )
    )
    SpriteContents.ForgetItem(sprite)
end

return SpriteContents
