local ResultList = {}

ResultList.VARIANTS_FORMAT = "%s (%d variants)"

local MOBILE_MARK = "_MOBILE"
local LANGUAGE_SUFFIXES = { "_FR", "_DE", "_PT", "_ES" }
local FAMILY_PATTERN = "^(.+)_(%d+)$"

function ResultList.FamilyOf(name)
    local family, number = string.match(name, FAMILY_PATTERN)
    if family == nil then
        return nil, nil
    end
    return family, tonumber(number)
end

function ResultList.IsClutter(name)
    if string.find(name, MOBILE_MARK, 1, true) ~= nil then
        return true
    end
    local withoutNumber = ResultList.FamilyOf(name) or name
    for _, suffix in ipairs(LANGUAGE_SUFFIXES) do
        for _, candidate in ipairs({ name, withoutNumber }) do
            if #candidate > #suffix and string.sub(candidate, -#suffix) == suffix then
                return true
            end
        end
    end
    return false
end

local function keptEntries(entries, hideClutter)
    if not hideClutter then
        return entries
    end
    local kept = {}
    for _, entry in ipairs(entries) do
        if not ResultList.IsClutter(entry.name) then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

local function membersByFamily(entries)
    local members = {}
    for _, entry in ipairs(entries) do
        local family, number = ResultList.FamilyOf(entry.name)
        if family ~= nil then
            members[family] = members[family] or {}
            local list = members[family]
            list[#list + 1] = { entry = entry, number = number }
        end
    end
    return members
end

local function numericOrder(left, right)
    if left.number ~= right.number then
        return left.number < right.number
    end
    return left.entry.name < right.entry.name
end

local function familyTile(family, numbered)
    table.sort(numbered, numericOrder)
    local members = {}
    for position, member in ipairs(numbered) do
        members[position] = member.entry
    end
    return {
        name = members[1].name,
        label = string.format(ResultList.VARIANTS_FORMAT, family, #members),
        family = family,
        members = members,
    }
end

local function singleTile(entry)
    return { name = entry.name, label = entry.name, members = { entry } }
end

local function favouriteList(entries, favourites)
    local entryByName = {}
    for _, entry in ipairs(entries) do
        entryByName[entry.name] = entry
    end
    local list = { tiles = {}, locationByName = {} }
    for _, name in ipairs(favourites) do
        local entry = entryByName[name]
        if entry ~= nil and list.locationByName[name] == nil then
            list.tiles[#list.tiles + 1] = singleTile(entry)
            list.locationByName[name] = { tile = #list.tiles, variant = 1 }
        end
    end
    return list
end

function ResultList.Build(entries, options)
    local settings = options or {}
    if settings.favourites ~= nil then
        return favouriteList(entries or {}, settings.favourites)
    end
    local kept = keptEntries(entries or {}, settings.hideClutter)
    local families = settings.groupVariants and membersByFamily(kept) or {}
    local list = { tiles = {}, locationByName = {} }
    local placedFamilies = {}
    for _, entry in ipairs(kept) do
        local family = ResultList.FamilyOf(entry.name)
        local numbered = family ~= nil and families[family] or nil
        local tile = nil
        if numbered ~= nil and #numbered >= 2 then
            if not placedFamilies[family] then
                placedFamilies[family] = true
                tile = familyTile(family, numbered)
            end
        else
            tile = singleTile(entry)
        end
        if tile ~= nil then
            list.tiles[#list.tiles + 1] = tile
            for variant, member in ipairs(tile.members) do
                list.locationByName[member.name] = { tile = #list.tiles, variant = variant }
            end
        end
    end
    return list
end

function ResultList.Locate(list, name)
    local location = name ~= nil and list.locationByName[name] or nil
    if location == nil then
        return nil, nil
    end
    return location.tile, location.variant
end

return ResultList
