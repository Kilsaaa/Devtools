local Curation = require("rsprite/src/data/curation")
local Warnings = require("rsprite/src/services/warnings")

local UnsafeSprites = {}

local nameById = {}
local idByName = {}
for spriteId, name in pairs(Curation.unsafe or {}) do
    nameById[spriteId] = name
    idByName[name] = spriteId
end

function UnsafeSprites.NameOfId(spriteId)
    return nameById[spriteId]
end

function UnsafeSprites.IsUnsafeId(spriteId)
    return nameById[spriteId] ~= nil
end

function UnsafeSprites.IsUnsafeName(upperName)
    return idByName[upperName] ~= nil
end

function UnsafeSprites.Reject(name)
    Warnings.Once(
        "unsafe " .. name,
        name .. " is known to crash the client, so it is treated as missing"
    )
    return nil
end

return UnsafeSprites
