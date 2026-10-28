local Client = require("rsprite/src/services/client")
local Warnings = require("rsprite/src/services/warnings")

local Placeholder = {}

local RESOURCE_NAME = "placeholder"

local handle = nil

local function placeholderHandle()
    if handle == nil then
        handle = Client.OwnResource(RESOURCE_NAME)
    end
    return handle
end

function Placeholder.Show(sprite, enabled)
    if enabled then
        local resource = placeholderHandle()
        if resource ~= nil and Client.SetProperty(sprite, "sprite", resource) then
            Client.SetProperty(sprite, "hidden", false)
            return true
        end
        Warnings.Once(
            "placeholder",
            "the placeholder image could not be shown, so the sprite is hidden instead"
        )
    end
    Client.SetProperty(sprite, "hidden", true)
    return false
end

return Placeholder
