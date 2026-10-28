--[[
    componentnames.lua - the game's names for interfaces and their components (id.Component.NAME).

    A name's number packs the interface id and the component id together (interface * 65536 + component). id.Component has about
    100,000 keys, so they are read once, grouped by the text before the first double underscore (that text is the interface's name),
    and the interface each group belongs to is found by looking up one of its names. Shared by the Interface tab and its Lookup sub-tab.
]]

local UI = require("core/uiutil")

local Names = {}

local try = UI.try

local interfaces = nil          -- interface number -> { number, name, names = { every component name of that interface } }
local valuesByInterface = {}    -- interface number -> { packed number -> component name }, built the first time the interface is asked about

-- reads every key of id.Component and groups the names by their interface
local function index()
    if interfaces then return end
    interfaces = {}
    local groups, seen = {}, {}

    -- the keys may not be plain Lua strings, so every key is wrapped with tostring
    local function add(key, value)
        local name = type(key) == "number" and tostring(value) or tostring(key)
        if seen[name] then return end
        seen[name] = true
        local prefix = string.match(name, "^(.-)__")
        if prefix and prefix ~= "" then
            local list = groups[prefix]
            if not list then list = {}; groups[prefix] = list end
            list[#list + 1] = name
        end
    end
    pcall(function() for key, value in pairs(id.Component) do add(key, value) end end)
    if next(seen) == nil then
        pcall(function() for key, value in ipairs(id.Component) do add(key, value) end end)
    end

    for prefix, list in pairs(groups) do
        local ok, value = pcall(function() return id.Component[list[1]] end)
        if ok and type(value) == "number" then
            local number = value // 65536
            local entry = interfaces[number]
            if not entry then
                entry = { number = number, name = prefix, names = {} }
                interfaces[number] = entry
            end
            for _, name in ipairs(list) do entry.names[#entry.names + 1] = name end
        end
    end
end

-- every interface the game has names for: number -> { number, name, names }
function Names.interfaces()
    index()
    return interfaces
end

-- the game's name for an interface ("TOPLEVEL_V2_COMBAT_BAR"), or nil
function Names.interfaceName(number)
    index()
    local entry = interfaces[number]
    return entry and entry.name or nil
end

-- the game's name for a static component ("TOPLEVEL_V2_COMBAT_BAR__ACTIONBAR_LAYER"), or nil
function Names.nameOf(component)
    local interfaceNumber, staticNumber = try(component, "interfaceID"), try(component, "staticID")
    if type(interfaceNumber) ~= "number" or type(staticNumber) ~= "number" then return nil end
    interfaceNumber = math.floor(interfaceNumber)

    local values = valuesByInterface[interfaceNumber]
    if not values then
        values = {}
        index()
        local entry = interfaces[interfaceNumber]
        for _, name in ipairs(entry and entry.names or {}) do
            local ok, value = pcall(function() return id.Component[name] end)
            if ok and type(value) == "number" then values[value] = name end
        end
        valuesByInterface[interfaceNumber] = values
    end
    return values[interfaceNumber * 65536 + math.floor(staticNumber)]
end

return Names
