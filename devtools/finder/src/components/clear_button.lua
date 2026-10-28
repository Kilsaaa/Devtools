local rsprite = require("rsprite/src/app/init").Public
local Client = require("finder/src/services/client")
local Theme = require("finder/src/utils/theme")

local ClearButton = {}

ClearButton.SIZE = 16
ClearButton.RESTING_SPRITE = "RS3_ICON_CLEAR_16PX_0"
ClearButton.HOVERED_SPRITE = "RS3_ICON_CLEAR_16PX_1"

local HOOK_KEY = "rsprite-finder:clear-button"

function ClearButton.New(parent, layout, onClear)
    local button = { hovered = false, visible = false }
    button.root = Client.NewLayer(parent, {
        x = layout.x,
        y = layout.y,
        width = ClearButton.SIZE,
        height = ClearButton.SIZE,
        clickable = true,
    })
    button.image = Client.NewSprite(button.root, {
        x = 0,
        y = 0,
        width = ClearButton.SIZE,
        height = ClearButton.SIZE,
    })
    Client.SetHoverCursor(button.root, Client.CursorId(Theme.BUTTON_CURSOR))

    local function paint()
        local name = button.hovered and ClearButton.HOVERED_SPRITE or ClearButton.RESTING_SPRITE
        Client.Set(button.image, "spriteID", rsprite.Get(name) or -1)
    end

    function button.SetVisible(visible)
        button.visible = visible == true
        if not button.visible then
            button.hovered = false
            paint()
        end
        Client.Set(button.root, "hidden", not button.visible)
        Client.Set(button.image, "hidden", not button.visible)
    end

    Client.OnHook(button.root, "ONMOUSEOVER", HOOK_KEY, Client.MOUSE_ENTER_LABELS, function()
        button.hovered = true
        paint()
        return true
    end)
    Client.OnHook(button.root, "ONMOUSELEAVE", HOOK_KEY, Client.MOUSE_LEAVE_LABELS, function()
        button.hovered = false
        paint()
        return true
    end)
    Client.OnHook(button.root, "ONCLICK", HOOK_KEY, Client.CLICK_LABELS, function()
        if button.visible then
            onClear()
        end
        return false
    end)

    if layout.tooltip ~= nil and button.root ~= nil then
        button.tooltip = Client.Call(
            "attaching the clear button tooltip",
            prettyui.Tooltip.attach,
            button.root,
            parent,
            { text = layout.tooltip }
        )
    end

    paint()
    button.SetVisible(false)
    return button
end

return ClearButton
