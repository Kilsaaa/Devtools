local Client = require("rsprite/src/services/client")
local UnsafeSprites = require("rsprite/src/features/lookup/unsafe_sprites")
local Warnings = require("rsprite/src/services/warnings")
local WholeNumber = require("rsprite/src/utils/whole_number")

local SpriteLookup = {}

local MISSING = false

local idByName = {}
local nameById = {}

function SpriteLookup.Get(name)
    if name == nil then
        return nil
    end
    if type(name) ~= "string" then
        error("rsprite.Get: name must be a string, got " .. type(name), 2)
    end
    if name == "" then
        return nil
    end
    local key = string.upper(name)
    if UnsafeSprites.IsUnsafeName(key) then
        return UnsafeSprites.Reject(key)
    end
    local cached = idByName[key]
    if cached ~= nil then
        return cached or nil
    end
    local found, value = Client.SpriteIdByName(key)
    if not found then
        Warnings.Once(
            "get failed " .. key,
            "looking up sprite " .. key .. " failed: " .. tostring(value)
        )
        return nil
    end
    local spriteId = WholeNumber.From(value)
    if spriteId ~= nil and UnsafeSprites.IsUnsafeId(spriteId) then
        idByName[key] = MISSING
        return UnsafeSprites.Reject(UnsafeSprites.NameOfId(spriteId))
    end
    if spriteId == nil then
        Warnings.Once("get " .. key, "there is no sprite called " .. key)
    end
    idByName[key] = spriteId or MISSING
    return spriteId
end

function SpriteLookup.Name(spriteId)
    if spriteId == nil then
        return nil
    end
    if type(spriteId) ~= "number" then
        error("rsprite.Name: id must be a number, got " .. type(spriteId), 2)
    end
    local wholeId = WholeNumber.From(spriteId)
    if wholeId == nil then
        return nil
    end
    if UnsafeSprites.IsUnsafeId(wholeId) then
        return UnsafeSprites.Reject(UnsafeSprites.NameOfId(wholeId))
    end
    local cached = nameById[wholeId]
    if cached ~= nil then
        return cached or nil
    end
    local found, value = Client.SpriteNameById(wholeId)
    if not found then
        Warnings.Once(
            "name failed " .. wholeId,
            "looking up sprite id " .. wholeId .. " failed: " .. tostring(value)
        )
        return nil
    end
    local name = type(value) == "string" and value ~= "" and value or nil
    if name == nil then
        Warnings.Once("name " .. wholeId, "there is no sprite with id " .. wholeId)
    end
    nameById[wholeId] = name or MISSING
    return name
end

return SpriteLookup
