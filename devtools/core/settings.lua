--[[
    settings.lua - what Dev Tools remembers between sessions (PersistentDB only holds whole numbers).

    Each value is saved with a second "is set" number so a value that was never saved (or was reset) reads as the default.
    Settings.reset() forgets everything saved here; the modules that keep their own keys are reset through Settings.onReset.
]]

local Settings = {}

local PREFIX = "devtools_"

function Settings.get(key, default)
    local ok, flag, value = pcall(function() return PersistentDB:GetInt(PREFIX .. key .. "_set"), PersistentDB:GetInt(PREFIX .. key) end)
    if ok and flag == 1 and type(value) == "number" then return value end
    return default
end

function Settings.set(key, value)
    pcall(function()
        PersistentDB:SetInt(PREFIX .. key, math.floor(value))
        PersistentDB:SetInt(PREFIX .. key .. "_set", 1)
    end)
end

function Settings.clear(key)
    pcall(function() PersistentDB:SetInt(PREFIX .. key .. "_set", 0) end)
end

-- keys that have been written this session, so reset knows what to clear
local used = {}
local setOriginal = Settings.set
function Settings.set(key, value)
    used[key] = true
    setOriginal(key, value)
end

-- keys that may have been saved by an earlier session
local KNOWN = { "winRX", "winRY", "pos2RX", "pos2RY", "building", "skipTab", "early", "noWatch", "creating", "showSelected", "showColour", "npcColour", "locColour", "tileColour", "boxColour", "tileOn", "savedX", "savedZ", "savedLevel" }

function Settings.reset()
    for _, key in ipairs(KNOWN) do Settings.clear(key) end
    for key in pairs(used) do Settings.clear(key) end
    -- the quick cheat toggles and the cheat choice are numbered, so clear the whole range
    for i = 1, 60 do Settings.clear("quick" .. i) end
    Settings.clear("cheatIndex")
    Settings.clear("cheatValue")
end

return Settings