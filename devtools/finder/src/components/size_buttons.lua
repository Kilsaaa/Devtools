local rsprite = require("rsprite/src/app/init").Public
local Client = require("finder/src/services/client")
local Theme = require("finder/src/utils/theme")

local SizeButtons = {}

SizeButtons.TILE_SIZE = 8
SizeButtons.HOVER_CURSOR = Theme.BUTTON_CURSOR
SizeButtons.TEXT_COLOUR = 0xFFFFFFFF

local PIECES = {
    "topLeft",
    "top",
    "topRight",
    "left",
    "centre",
    "right",
    "bottomLeft",
    "bottom",
    "bottomRight",
}
local TILED_PIECES = { top = true, left = true, centre = true, right = true, bottom = true }
local FIRST_SPRITE_OF_STATE = { hovered = 9, neutral = 18, active = 27 }
local SPRITE_NAME_PREFIX = "RS3_BTN_ICON_RESIZABLE_"
local CLICK_KEY_PREFIX = "rsprite-finder:size:"

SizeButtons.PIECES = PIECES

function SizeButtons.SpriteName(state, piece)
    for position, name in ipairs(PIECES) do
        if name == piece then
            return SPRITE_NAME_PREFIX .. (FIRST_SPRITE_OF_STATE[state] + position - 1)
        end
    end
    return nil
end

local function pieceLayout(piece, width, height)
    local tile = SizeButtons.TILE_SIZE
    local middleWidth = width - tile * 2
    local middleHeight = height - tile * 2
    local rightColumn = width - tile
    local bottomRow = height - tile
    local layouts = {
        topLeft = { x = 0, y = 0, width = tile, height = tile },
        top = { x = tile, y = 0, width = middleWidth, height = tile },
        topRight = { x = rightColumn, y = 0, width = tile, height = tile },
        left = { x = 0, y = tile, width = tile, height = middleHeight },
        centre = { x = tile, y = tile, width = middleWidth, height = middleHeight },
        right = { x = rightColumn, y = tile, width = tile, height = middleHeight },
        bottomLeft = { x = 0, y = bottomRow, width = tile, height = tile },
        bottom = { x = tile, y = bottomRow, width = middleWidth, height = tile },
        bottomRight = { x = rightColumn, y = bottomRow, width = tile, height = tile },
    }
    local layout = layouts[piece]
    layout.tiling = TILED_PIECES[piece] == true
    return layout
end

local function buildButton(parent, layout, label, font, cursorId)
    local button = { parts = {}, hovered = false, lit = false }
    button.root = Client.NewLayer(parent, {
        x = layout.x,
        y = layout.y,
        width = layout.width,
        height = layout.height,
        clickable = true,
    })
    for _, piece in ipairs(PIECES) do
        button.parts[piece] =
            Client.NewSprite(button.root, pieceLayout(piece, layout.width, layout.height))
    end
    button.label = Client.NewText(button.root, {
        x = 0,
        y = 0,
        width = layout.width,
        height = layout.height,
        text = label,
        font = font,
        colour = SizeButtons.TEXT_COLOUR,
        centred = true,
        centredVertically = true,
    })
    Client.Set(button.label, "isShadowed", true)
    Client.SetHoverCursor(button.root, cursorId)
    return button
end

local function paint(button)
    local state = (button.lit and "active") or (button.hovered and "hovered") or "neutral"
    button.state = state
    for piece, sprite in pairs(button.parts) do
        Client.Set(sprite, "spriteID", rsprite.Get(SizeButtons.SpriteName(state, piece)) or -1)
    end
end

function SizeButtons.New(parent, layout, sizes, onSelect)
    local group = { buttons = {}, sizes = sizes }
    local font = Client.Font(Theme.BODY_FONT)
    local cursorId = Client.CursorId(SizeButtons.HOVER_CURSOR)
    for position, size in ipairs(sizes) do
        local button = buildButton(parent, {
            x = layout.x + (position - 1) * (layout.buttonWidth + layout.gap),
            y = layout.y,
            width = layout.buttonWidth,
            height = layout.height,
        }, tostring(size), font, cursorId)
        button.size = size
        group.buttons[position] = button
        Client.OnHook(
            button.root,
            "ONMOUSEOVER",
            CLICK_KEY_PREFIX .. size,
            Client.MOUSE_ENTER_LABELS,
            function()
                button.hovered = true
                paint(button)
                return true
            end
        )
        Client.OnHook(
            button.root,
            "ONMOUSELEAVE",
            CLICK_KEY_PREFIX .. size,
            Client.MOUSE_LEAVE_LABELS,
            function()
                button.hovered = false
                paint(button)
                return true
            end
        )
        Client.OnHook(
            button.root,
            "ONCLICK",
            CLICK_KEY_PREFIX .. size,
            Client.CLICK_LABELS,
            function()
                onSelect(size)
                return false
            end
        )
        paint(button)
    end

    function group.Light(size)
        for _, button in ipairs(group.buttons) do
            button.lit = button.size == size
            paint(button)
        end
    end

    function group.LitSizes()
        local lit = {}
        for _, button in ipairs(group.buttons) do
            if button.lit then
                lit[#lit + 1] = button.size
            end
        end
        return lit
    end

    return group
end

return SizeButtons
