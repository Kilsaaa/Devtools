local SpriteLookup = require("rsprite/src/features/lookup/sprite_lookup")
local Warnings = require("rsprite/src/services/warnings")
local WholeNumber = require("rsprite/src/utils/whole_number")

local SourceChain = {}

local SOURCE_TYPES = { string = true, number = true, userdata = true }

function SourceChain.Entries(functionName, nameOrChain)
    local sourceType = type(nameOrChain)
    if SOURCE_TYPES[sourceType] then
        return { nameOrChain }
    end
    if sourceType ~= "table" then
        return nil,
            string.format(
                "%s: source must be a sprite name, sprite id, resource handle or an array of them, got %s",
                functionName,
                sourceType
            )
    end
    for position, entry in ipairs(nameOrChain) do
        if not SOURCE_TYPES[type(entry)] then
            return nil,
                string.format(
                    "%s: chain entry %d must be a sprite name, sprite id or resource handle, got %s",
                    functionName,
                    position,
                    type(entry)
                )
        end
    end
    return nameOrChain
end

local function resolveEntry(entry)
    local entryType = type(entry)
    if entryType == "string" then
        return SpriteLookup.Get(entry)
    end
    if entryType == "userdata" then
        return entry
    end
    local wholeId = WholeNumber.From(entry)
    if wholeId == nil then
        Warnings.Once(
            "invalid id " .. tostring(entry),
            "skipped sprite id " .. tostring(entry) .. " because ids are whole numbers 0 or above"
        )
        return nil
    end
    if SpriteLookup.Name(wholeId) == nil then
        return nil
    end
    return wholeId
end

function SourceChain.ResolveEntries(chain)
    for position, entry in ipairs(chain) do
        local source = resolveEntry(entry)
        if source ~= nil then
            return source, position
        end
    end
    return nil
end

function SourceChain.Resolve(nameOrChain)
    local chain, problem = SourceChain.Entries("rsprite.Resolve", nameOrChain)
    if chain == nil then
        error(problem, 2)
    end
    return SourceChain.ResolveEntries(chain)
end

return SourceChain
