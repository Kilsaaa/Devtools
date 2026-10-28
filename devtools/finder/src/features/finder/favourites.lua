local Preferences = require("finder/src/services/preferences")

local Favourites = {}

Favourites.PREFERENCES_NAME = "favourites"
Favourites.SEPARATOR = ","

local NAME_PATTERN = "[^" .. Favourites.SEPARATOR .. "]+"

function Favourites.Decode(text)
    local names = {}
    if type(text) ~= "string" then
        return names
    end
    for name in string.gmatch(text, NAME_PATTERN) do
        names[#names + 1] = name
    end
    return names
end

function Favourites.Encode(names)
    return table.concat(names, Favourites.SEPARATOR)
end

function Favourites.New(saved)
    local source = type(saved) == "table" and saved or {}
    return {
        names = Favourites.Decode(source.names),
        only = source.only == true,
    }
end

function Favourites.Load()
    return Favourites.New(Preferences.Load(Favourites.PREFERENCES_NAME))
end

function Favourites.Save(favourites)
    return Preferences.Save(Favourites.PREFERENCES_NAME, {
        names = Favourites.Encode(favourites.names),
        only = favourites.only,
    })
end

local function positionOf(favourites, name)
    for position, favourite in ipairs(favourites.names) do
        if favourite == name then
            return position
        end
    end
    return nil
end

function Favourites.Contains(favourites, name)
    return name ~= nil and positionOf(favourites, name) ~= nil
end

function Favourites.Set(favourites, name, starred)
    if name == nil then
        return false
    end
    local position = positionOf(favourites, name)
    if starred and position == nil then
        table.insert(favourites.names, 1, name)
        return true
    end
    if not starred and position ~= nil then
        table.remove(favourites.names, position)
        return true
    end
    return false
end

return Favourites
