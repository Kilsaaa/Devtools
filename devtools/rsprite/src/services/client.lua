local Client = {}

local RESOURCE_EXTENSION = ".png"

function Client.SpriteIdByName(name)
    return pcall(function()
        return id.Sprite[name]
    end)
end

function Client.SpriteNameById(spriteId)
    return pcall(function()
        return id.Sprite.FromID(spriteId)
    end)
end

function Client.CreateSprite(parent)
    return pcall(function()
        return ui.Sprite.new(parent)
    end)
end

function Client.SetPosition(sprite, x, y, xAnchor, yAnchor)
    return pcall(function()
        sprite:SetPos(x, y, xAnchor, yAnchor)
    end)
end

function Client.SetSize(sprite, width, height)
    return pcall(function()
        sprite:SetSize(width, height)
    end)
end

function Client.SetProperty(sprite, propertyName, value)
    return pcall(function()
        sprite[propertyName] = value
    end)
end

function Client.SetAssociatedObject(sprite, itemId)
    return pcall(function()
        sprite:SetAssociatedObject(itemId)
    end)
end

function Client.QuantityDisplayMode(modeName)
    local found, mode = pcall(function()
        return ui.ObjectQuantityDisplayMode[modeName]
    end)
    if found then
        return mode
    end
    return nil
end

function Client.OwnResource(resourceName)
    for _, key in ipairs({ resourceName, resourceName .. RESOURCE_EXTENSION }) do
        local found, handle = pcall(function()
            return Plugin.resources[key]
        end)
        if found and handle ~= nil then
            return handle
        end
    end
    return nil
end

function Client.Subscribe(eventName, key, callback)
    return pcall(function()
        Event[eventName].Subscribe(key, callback)
    end)
end

function Client.Unsubscribe(eventName, key)
    return pcall(function()
        Event[eventName].Unsubscribe(key)
    end)
end

return Client
