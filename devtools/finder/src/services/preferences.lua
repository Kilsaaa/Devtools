local Client = require("finder/src/services/client")

local Preferences = {}

Preferences.PREFIX = "rsprite_finder_"

function Preferences.Key(name)
    return Preferences.PREFIX .. name
end

function Preferences.Load(name)
    local value =
        Client.LoadStructuredData("loading the " .. name .. " settings", Preferences.Key(name))
    if type(value) == "table" then
        return value
    end
    return nil
end

function Preferences.Save(name, value)
    return Client.SaveStructuredData(
        "saving the " .. name .. " settings",
        Preferences.Key(name),
        value
    )
end

return Preferences
