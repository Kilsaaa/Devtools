local Warnings = {}

local PREFIX = "rsprite: "

local warnedKeys = {}

function Warnings.Once(key, message)
    if warnedKeys[key] then
        return
    end
    warnedKeys[key] = true
    print(PREFIX .. message)
end

function Warnings.IfFailed(key, action, succeeded, failure)
    if not succeeded then
        Warnings.Once(key, action .. " failed: " .. tostring(failure))
    end
    return succeeded
end

return Warnings
