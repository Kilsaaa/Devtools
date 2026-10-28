local Client = require("rsprite/src/services/client")
local UnsafeSprites = require("rsprite/src/features/lookup/unsafe_sprites")
local Warnings = require("rsprite/src/services/warnings")

local NameIndex = {}

NameIndex.CHUNK_SIZE = 2000
NameIndex.CONSECUTIVE_NIL_LIMIT = 500

local HIGHEST_ID_CEILING = 1000000
local LOGIC_EVENT = "Logic"
local SUBSCRIPTION_KEY = "rsprite:name-index"

local entries = nil
local walk = nil
local readyCallbacks = {}
local failedCallbacks = setmetatable({}, { __mode = "k" })
local subscribed = false

local function newWalk()
    return { nextId = 0, nilsSinceHit = 0, names = {}, ids = {} }
end

local function walkFinished(state)
    return state.nilsSinceHit >= NameIndex.CONSECUTIVE_NIL_LIMIT
        or state.nextId > HIGHEST_ID_CEILING
end

local function advance(state, limit)
    local processed = 0
    while not walkFinished(state) and (limit == nil or processed < limit) do
        local spriteId = state.nextId
        local found, name = Client.SpriteNameById(spriteId)
        if found and type(name) == "string" and name ~= "" then
            if not UnsafeSprites.IsUnsafeId(spriteId) and not UnsafeSprites.IsUnsafeName(name) then
                state.names[#state.names + 1] = name
                state.ids[#state.ids + 1] = spriteId
            end
            state.nilsSinceHit = 0
        else
            state.nilsSinceHit = state.nilsSinceHit + 1
        end
        state.nextId = spriteId + 1
        processed = processed + 1
    end
    return walkFinished(state)
end

local function stopTicking()
    if not subscribed then
        return
    end
    subscribed = false
    Warnings.IfFailed(
        "index unsubscribe",
        "stopping the name index build",
        Client.Unsubscribe(LOGIC_EVENT, SUBSCRIPTION_KEY)
    )
end

local function notify(callback)
    if failedCallbacks[callback] then
        return
    end
    local succeeded, failure = pcall(callback, #entries.names)
    if succeeded then
        return
    end
    failedCallbacks[callback] = true
    local errorText = tostring(failure)
    Warnings.Once(
        "index ready callback " .. errorText,
        "the function passed to rsprite.BuildIndex raised an error and was skipped: " .. errorText
    )
end

local function finish()
    stopTicking()
    entries = { names = walk.names, ids = walk.ids }
    walk = nil
    if #entries.names == 0 then
        Warnings.Once(
            "index empty",
            "the sprite name index came back empty, so Find has nothing to search"
        )
    end
    local callbacks = readyCallbacks
    readyCallbacks = {}
    for _, callback in ipairs(callbacks) do
        notify(callback)
    end
end

local function onLogic()
    if walk == nil then
        stopTicking()
        return
    end
    if advance(walk, NameIndex.CHUNK_SIZE) then
        finish()
    end
end

function NameIndex.IsReady()
    return entries ~= nil
end

function NameIndex.Entries()
    if entries == nil then
        walk = walk or newWalk()
        advance(walk, nil)
        finish()
    end
    return entries
end

function NameIndex.Build(onReady)
    if onReady ~= nil and type(onReady) ~= "function" then
        error(
            string.format("rsprite.BuildIndex: onReady must be a function, got %s", type(onReady)),
            2
        )
    end
    if entries ~= nil then
        if onReady ~= nil then
            notify(onReady)
        end
        return
    end
    if onReady ~= nil then
        readyCallbacks[#readyCallbacks + 1] = onReady
    end
    if walk ~= nil then
        return
    end
    walk = newWalk()
    local started, failure = Client.Subscribe(LOGIC_EVENT, SUBSCRIPTION_KEY, onLogic)
    if not started then
        Warnings.Once(
            "index subscribe",
            "building the name index across ticks failed, so it was built in one go: "
                .. tostring(failure)
        )
        NameIndex.Entries()
        return
    end
    subscribed = true
end

function NameIndex.Shutdown()
    stopTicking()
    walk = nil
    entries = nil          -- the list of every sprite name: let go of it now rather than when the plugin is unloaded
    readyCallbacks = {}
end

return NameIndex