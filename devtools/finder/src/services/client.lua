local Client = {}

local PREFIX = "rsprite-finder: "

local warnedKeys = {}
local fontConfigsById = {}

Client.CLICK_LABELS = { listening = "listening for clicks", handling = "handling a click" }
Client.MOUSE_ENTER_LABELS =
    { listening = "listening for the mouse entering", handling = "handling the mouse entering" }
Client.MOUSE_LEAVE_LABELS =
    { listening = "listening for the mouse leaving", handling = "handling the mouse leaving" }

function Client.Warn(key, message)
    if warnedKeys[key] then
        return
    end
    warnedKeys[key] = true
    print(PREFIX .. message)
end

function Client.Say(message)
    print(PREFIX .. message)
end

function Client.Call(label, action, ...)
    local results = table.pack(pcall(action, ...))
    if not results[1] then
        Client.Warn(label, label .. " failed: " .. tostring(results[2]))
        return nil
    end
    return table.unpack(results, 2, results.n)
end

function Client.GameArea()
    return Client.Call("finding the game area", function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    end)
end

function Client.Font(fontName)
    return Client.Call("finding font " .. fontName, function()
        return id.Font[fontName]
    end)
end

local function fontConfig(fontId)
    local cached = fontConfigsById[fontId]
    if cached ~= nil then
        return cached
    end
    local found = config.Font.FromID(fontId)
    if fontId ~= nil then
        fontConfigsById[fontId] = found
    end
    return found
end

function Client.TextWidth(fontId, text)
    return Client.Call("measuring text", function()
        return fontConfig(fontId):GetStringWidth(text, false)
    end)
end

function Client.ComponentSize(component)
    return Client.Call("reading a component size", function()
        return component.width, component.height
    end)
end

local function place(component, layout)
    component:SetPos(layout.x or 0, layout.y or 0)
    component:SetSize(layout.width or 0, layout.height or 0)
end

function Client.NewText(parent, layout)
    return Client.Call("creating text", function()
        local text = ui.Text.new(parent)
        place(text, layout)
        text.content = layout.text or ""
        if layout.font ~= nil then
            text.font = layout.font
        end
        text.rgba = layout.colour
        text.maxLines = layout.maxLines or 1
        text.clickthrough = true
        if layout.centred then
            text.alignHorizontal = ui.AlignMode.CENTRE
        end
        if layout.centredVertically then
            text.alignVertical = ui.AlignMode.CENTRE
        end
        if layout.hidden then
            text.hidden = true
        end
        return text
    end)
end

function Client.NewRectangle(parent, layout)
    return Client.Call("creating a rectangle", function()
        local rectangle = ui.Rectangle.new(parent)
        place(rectangle, layout)
        rectangle.fill = layout.outline == nil
        if layout.outline ~= nil then
            rectangle.outlineThickness = layout.outline
        end
        rectangle.rgba = layout.colour
        rectangle.clickthrough = layout.clickable ~= true
        if layout.hidden then
            rectangle.hidden = true
        end
        return rectangle
    end)
end

function Client.Set(component, propertyName, value)
    if component == nil then
        return false
    end
    return Client.Call("setting " .. propertyName, function()
        component[propertyName] = value
        return true
    end) == true
end

function Client.OnHook(component, hookName, key, labels, callback)
    if component == nil then
        return false
    end
    return Client.Call(labels.listening, function()
        component:Subscribe(ui.Hook[hookName], key, function(...)
            local handled = Client.Call(labels.handling, callback, ...)
            return handled ~= false
        end)
        return true
    end) == true
end

function Client.OnClick(component, key, callback)
    return Client.OnHook(component, "ONCLICK", key, Client.CLICK_LABELS, function()
        Client.Call(Client.CLICK_LABELS.handling, callback)
        return false
    end)
end

function Client.NewLayer(parent, layout)
    return Client.Call("creating a layer", function()
        local layer = ui.Layer.new(parent)
        place(layer, layout)
        layer.clickthrough = layout.clickable ~= true
        return layer
    end)
end

function Client.NewSprite(parent, layout)
    return Client.Call("creating a sprite", function()
        local sprite = ui.Sprite.new(parent)
        place(sprite, layout)
        sprite.isTiling = layout.tiling == true
        sprite.clickthrough = true
        return sprite
    end)
end

function Client.CursorId(cursorName)
    return Client.Call("finding cursor " .. cursorName, function()
        return config.Cursor[cursorName].id
    end)
end

function Client.SetHoverCursor(component, cursorId)
    if component == nil then
        return false
    end
    return Client.Call("setting a hover cursor", function()
        component.opConfig:ClearOpCursors()
        component.cursorConfig.mouseOverCursor = cursorId or -1
        if cursorId ~= nil then
            component.opConfig:SetOpCursor(0, cursorId)
        end
        return true
    end) == true
end

function Client.OwnResource(resourceName)
    for _, key in ipairs({ resourceName, resourceName .. ".png" }) do
        local found = Client.Call("finding resource " .. key, function()
            return Plugin.resources[key]
        end)
        if found ~= nil then
            return found
        end
    end
    return nil
end

function Client.NewInputField(parent, layout)
    return Client.Call("creating an input field", function()
        local field = ui.InputField.new(parent)
        field.stylesheetID = id.StyleSheet.INPUT_DEFAULT
        place(field, layout)
        field:Setup(
            ui.TextContentVisibilityMode.VISIBLE,
            ui.InputFieldFilterMode.NONE,
            layout.maxLength
        )
        field.inputMode = ui.InputFieldKeyHandlingMode.DEFAULT
        field.emptyText = layout.placeholder or ""
        field.content = layout.text or ""
        field.contentMargin =
            ui.Margin.new(layout.margin, layout.topInset, layout.rightMargin or layout.margin, 0)
        field.text.font = layout.font
        field.text.rgba = layout.colour
        field.text.isShadowed = true
        field.emptyTextRGBA = layout.placeholderColour
        field.caretRGBA = layout.caretColour
        field.selectionHighlightRGBA = layout.selectionColour
        if layout.background ~= nil then
            field.containerSprite.sprite = layout.background
            field.containerSprite.visualMargins = ui.Margin.new(layout.margin)
            field.containerSprite.isTiling = true
        end
        return field
    end)
end

function Client.NewComboField(parent, layout)
    return Client.Call("creating a combo field", function()
        local combo = ui.ComboField.new(parent)
        combo.stylesheetID = id.StyleSheet.COMBO_DEFAULT
        place(combo, layout)
        combo.entryHeight = layout.entryHeight
        combo.dropdownMaxVisibleEntries = layout.visibleEntries
        combo.contentMargin = ui.Margin.new(layout.margin, 0, layout.margin, 0)
        combo.headerMargin = ui.Margin.new(layout.margin, 0, layout.margin, 0)
        combo.entryText.font = layout.font
        combo.entryText.rgba = layout.colour
        combo.entryText.isShadowed = true
        combo.mouseoverForegroundRGBA = layout.colour
        combo.mouseoverBackgroundRGBA = layout.hoverColour
        combo.selectedForegroundRGBA = layout.colour
        combo.selectedBackgroundRGBA = layout.selectedColour
        combo.disabledForegroundRGBA = layout.disabledColour
        combo.selectionHighlightRGBA = layout.selectedColour
        combo.caretRGBA = layout.caretColour
        combo.errorCaretRGBA = layout.caretColour
        return combo
    end)
end

function Client.LoadStructuredData(label, key)
    return Client.Call(label, function()
        return PersistentDB:GetStructuredData(key)
    end)
end

function Client.SaveStructuredData(label, key, value)
    return Client.Call(label, function()
        PersistentDB:SetStructuredData(key, value)
        return true
    end) == true
end

function Client.Subscribe(eventName, key, callback)
    return Client.Call("subscribing to " .. eventName, function()
        Event[eventName].Subscribe(key, callback)
        return true
    end) == true
end

function Client.Unsubscribe(eventName, key)
    Client.Call("unsubscribing from " .. eventName, function()
        Event[eventName].Unsubscribe(key)
    end)
end

return Client
