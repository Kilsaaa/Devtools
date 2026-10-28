local Client = require("finder/src/services/client")
local Favourites = require("finder/src/features/finder/favourites")
local Preferences = require("finder/src/services/preferences")

local CrashGuard = {}

CrashGuard.MARKER_NAME = "drawing"
CrashGuard.HIDDEN_NAME = "hidden"
CrashGuard.CLEAR_AFTER_TICKS = 50
CrashGuard.MARKER_VERSION = 1
CrashGuard.RECOVERY_MESSAGE =
    "the last session closed while drawing these sprites, so they are now hidden: "

local EMPTY = {}

local hiddenNames = nil
local ticksUntilClear = nil
local markerWrittenThisSession = false
local recoveryChecked = false

local function loadHidden()
    if hiddenNames == nil then
        local saved = Preferences.Load(CrashGuard.HIDDEN_NAME) or EMPTY
        hiddenNames = {}
        for _, name in ipairs(Favourites.Decode(saved.names)) do
            hiddenNames[name] = true
        end
    end
    return hiddenNames
end

local function hiddenList()
    local names = {}
    for name in pairs(loadHidden()) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function saveHidden()
    Preferences.Save(CrashGuard.HIDDEN_NAME, { names = Favourites.Encode(hiddenList()) })
end

function CrashGuard.IsHidden(name)
    return loadHidden()[name] == true
end

function CrashGuard.HiddenCount()
    return #hiddenList()
end

function CrashGuard.FilterEntries(entries)
    local hidden = loadHidden()
    if next(hidden) == nil then
        return entries
    end
    local kept = {}
    for _, entry in ipairs(entries) do
        if not hidden[entry.name] then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

function CrashGuard.ShowHiddenAgain()
    local count = CrashGuard.HiddenCount()
    hiddenNames = {}
    saveHidden()
    return count
end

function CrashGuard.BeforeDraw(view, names)
    markerWrittenThisSession = true
    ticksUntilClear = CrashGuard.CLEAR_AFTER_TICKS
    Preferences.Save(CrashGuard.MARKER_NAME, {
        version = CrashGuard.MARKER_VERSION,
        page = view.page,
        query = view.query,
        tag = view.tag or "",
        groupVariants = view.groupVariants == true,
        hideClutter = view.hideClutter == true,
        favouritesOnly = view.favouritesOnly == true,
        names = Favourites.Encode(names),
    })
end

function CrashGuard.Clear()
    if ticksUntilClear == nil then
        return
    end
    ticksUntilClear = nil
    Preferences.Save(CrashGuard.MARKER_NAME, EMPTY)
end

function CrashGuard.Tick()
    if ticksUntilClear == nil then
        return
    end
    ticksUntilClear = ticksUntilClear - 1
    if ticksUntilClear <= 0 then
        CrashGuard.Clear()
    end
end

function CrashGuard.IsWaiting()
    return ticksUntilClear ~= nil
end

function CrashGuard.Recover()
    if recoveryChecked or markerWrittenThisSession then
        return nil
    end
    recoveryChecked = true
    local marker = Preferences.Load(CrashGuard.MARKER_NAME)
    if marker == nil then
        return nil
    end
    local names = Favourites.Decode(marker.names)
    Preferences.Save(CrashGuard.MARKER_NAME, EMPTY)
    if #names == 0 then
        return nil
    end
    local hidden = loadHidden()
    for _, name in ipairs(names) do
        hidden[name] = true
    end
    saveHidden()
    Client.Warn("crash recovery", CrashGuard.RECOVERY_MESSAGE .. table.concat(names, ", "))
    return names
end

return CrashGuard
