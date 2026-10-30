--[[
    uiutil.lua - small helpers shared by the Dev Tools tabs.
]]

local UI = {}

local function readField(object, field) return object[field] end

-- object[field], or nil when reading it raises an error (game objects can refuse some properties).
-- (No closure is made here: this is called thousands of times a frame by some tabs.)
function UI.try(object, field)
    local ok, value = pcall(readField, object, field)
    if ok then return value end
    return nil
end

-- Changes the text of a PrettyUI text object
function UI.setText(control, text)
    if control then control.content = text end
end

local hoverTip = nil

function UI.addHoverTip(page, control, text)
    if not text then return end
    local root = UI.try(control, "root")
    local target = root or control
    if not root then target.enabled = true end
    target.clickthrough = false
    target:Subscribe(ui.Hook.ONMOUSEOVER, "devtools_hover_tip", function(_, x, y)
        if hoverTip and hoverTip.target == target then return true end
        if hoverTip then hoverTip:Destroy() end
        hoverTip = prettyui.Tooltip.attach(target, page.content, text, { followCursor = not root })
        hoverTip.cursorX, hoverTip.cursorY = x, y
        hoverTip:Show()
        return true
    end)
end

-- A divider with less space above and below it (the default leaves a lot of padding)
UI.TIGHT_DIVIDER = { marginTop = -16, marginBottom = -8 }

-- A heading above a group of controls (the page's title style, or plain text if the page can't make one)
function UI.heading(page, text)
    local ok = pcall(function() page:AddTitle(text) end)
    if not ok then page:AddText({ text = text, marginBottom = 10 }) end
end

-- Greys out (or re-enables) a control. Tries the control's own method first, then the component's enabled flag.
function UI.setDisabled(control, disabled)
    if not control then return end
    local done = pcall(function() control:SetDisabled(disabled) end)
    if not done then pcall(function() control:SetActive(not disabled) end) end
    pcall(function() control.enabled = not disabled end)
end

-- Hides (or shows) a control, trying the ways a control might offer. Returns nothing: if none work it stays as it was.
function UI.setHidden(control, hidden)
    if not control then return end
    -- PrettyUI documents no way to hide a button, so every plausible way is tried (each is harmless if it doesn't exist)
    pcall(function() control:SetHidden(hidden) end)
    pcall(function() control:SetVisible(not hidden) end)
    pcall(function() control.hidden = hidden end)
    pcall(function() control.visible = not hidden end)
    pcall(function() control.alpha = hidden and 0 or 1 end)
    pcall(function() control:SetAlpha(hidden and 0 or 1) end)
    for _, inner in ipairs({ "component", "native", "root", "layer", "frame", "button", "background" }) do
        pcall(function() control[inner].hidden = hidden end)
    end
end

-- The text typed into a text field ("" when it can't be read)
function UI.fieldText(field)
    if not field then return "" end
    local ok, text = pcall(function() return field:GetText() end)
    return ok and text or ""
end

-- { { label = ..., id = 1 }, ... } from a list of items that each have a label (or a key)
function UI.dropdownEntries(list)
    local entries = {}
    for i, item in ipairs(list) do entries[i] = { label = item.label or item.key, id = i } end
    return entries
end

-- Changes a fancy button's text and look (variant: "positive", "neutral" or "negative"). Only fancy buttons can do
-- this - simple buttons have no way to change their text.
function UI.setButton(button, text, variant)
    if not button then return end
    pcall(function() button:SetText(text) end)
    if variant then pcall(function() button:SetVariant(variant) end) end
end

-- One page of a long list. Returns the items on page `page`, the page number actually used (kept within range) and
-- how many pages there are. PrettyUI makes a component for every row and can only hold about 4,000 of them in all,
-- so long result lists have to be shown a page at a time.
function UI.page(items, page, size)
    local pages = math.max(1, math.ceil(#items / size))
    page = math.min(math.max(page, 1), pages)
    local shown = {}
    for i = (page - 1) * size + 1, math.min(#items, page * size) do shown[#shown + 1] = items[i] end
    return shown, page, pages
end

-- true when the component, or anything it sits in, is hidden (a tab page that isn't showing)
function UI.pageHidden(component)
    local c = component
    for _ = 1, 40 do
        if not c then return false end
        for _, field in ipairs({ "hidden", "visible", "visibleGlobal" }) do
            local ok, value = pcall(function() return c[field] end)
            if ok and ((field == "hidden" and value == true) or (field ~= "hidden" and value == false)) then return true end
        end
        local ok, parent = pcall(function() return c.parent end)
        c = ok and parent or nil
    end
    return false
end

return UI
