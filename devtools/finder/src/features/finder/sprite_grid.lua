local rsprite = require("rsprite/src/app/init").Public
local Client = require("finder/src/services/client")
local FinderState = require("finder/src/features/finder/finder_state")
local HiddenSprite = require("finder/src/utils/hidden_sprite")
local Theme = require("finder/src/utils/theme")

local SpriteGrid = {}

SpriteGrid.COLUMNS = 9   -- sprites per row
SpriteGrid.ROWS = math.ceil(FinderState.PAGE_SIZE / SpriteGrid.COLUMNS)
SpriteGrid.TILE_COUNT = FinderState.PAGE_SIZE
SpriteGrid.TILE_WIDTH = 70
SpriteGrid.TILE_HEIGHT = 64
SpriteGrid.SPRITE_SIZE = 32

local COLUMN_GAP = 6
local MINIMUM_ROW_GAP = 6
local BORDER_THICKNESS = 2
local TOOLTIP_WIDTH = 320
local CLICK_KEY_PREFIX = "rsprite-finder:tile:"

SpriteGrid.WIDTH = SpriteGrid.COLUMNS * SpriteGrid.TILE_WIDTH
    + (SpriteGrid.COLUMNS - 1) * COLUMN_GAP
SpriteGrid.MINIMUM_HEIGHT = SpriteGrid.ROWS * SpriteGrid.TILE_HEIGHT
    + (SpriteGrid.ROWS - 1) * MINIMUM_ROW_GAP

function SpriteGrid.RowGap(height)
    local spare = (height or SpriteGrid.MINIMUM_HEIGHT) - SpriteGrid.ROWS * SpriteGrid.TILE_HEIGHT
    return math.max(MINIMUM_ROW_GAP, math.floor(spare / (SpriteGrid.ROWS - 1)))
end

local function buildTile(parent, origin, rowGap, position, onSelect)
    local column = (position - 1) % SpriteGrid.COLUMNS
    local row = math.floor((position - 1) / SpriteGrid.COLUMNS)
    local x = origin.x + column * (SpriteGrid.TILE_WIDTH + COLUMN_GAP)
    local y = origin.y + row * (SpriteGrid.TILE_HEIGHT + rowGap)
    local tile = { parent = parent }
    tile.square = Client.NewRectangle(parent, {
        x = x,
        y = y,
        width = SpriteGrid.TILE_WIDTH,
        height = SpriteGrid.TILE_HEIGHT,
        colour = Theme.TILE,
        clickable = true,
    })
    Client.OnClick(tile.square, CLICK_KEY_PREFIX .. position, function()
        onSelect(position)
    end)
    tile.sprite = Client.Call("drawing a tile sprite", rsprite.Draw, parent, HiddenSprite.SOURCE, {
        x = x + math.floor((SpriteGrid.TILE_WIDTH - SpriteGrid.SPRITE_SIZE) / 2),
        y = y + math.floor((SpriteGrid.TILE_HEIGHT - SpriteGrid.SPRITE_SIZE) / 2),
        size = SpriteGrid.SPRITE_SIZE,
        placeholder = false,
    })
    tile.border = Client.NewRectangle(parent, {
        x = x,
        y = y,
        width = SpriteGrid.TILE_WIDTH,
        height = SpriteGrid.TILE_HEIGHT,
        colour = Theme.GOLD,
        outline = BORDER_THICKNESS,
        hidden = true,
    })
    return tile
end

local function setTooltip(tile, text)
    if tile.tooltip ~= nil then
        Client.Call("updating a tile tooltip", function()
            tile.tooltip:SetText(text)
        end)
        return
    end
    if tile.square ~= nil then
        tile.tooltip = Client.Call(
            "attaching a tile tooltip",
            prettyui.Tooltip.attach,
            tile.square,
            tile.parent,
            {
                text = text,
                maxWidth = TOOLTIP_WIDTH,
            }
        )
    end
end

local function hideTile(tile)
    Client.Set(tile.square, "hidden", true)
    Client.Set(tile.border, "hidden", true)
    Client.Call(
        "hiding a tile sprite",
        rsprite.SetSource,
        tile.sprite,
        HiddenSprite.SOURCE,
        HiddenSprite.OPTIONS
    )
end

function SpriteGrid.New(parent, origin, onSelect)
    local grid = { tiles = {}, rowGap = SpriteGrid.RowGap(origin.height) }
    for position = 1, SpriteGrid.TILE_COUNT do
        grid.tiles[position] = buildTile(parent, origin, grid.rowGap, position, onSelect)
    end

    function grid.Show(results, selectedPosition)
        for position, tile in ipairs(grid.tiles) do
            local result = results[position]
            tile.showing = result ~= nil
            if result == nil then
                hideTile(tile)
            else
                Client.Set(tile.square, "hidden", false)
                Client.Call("showing a tile sprite", rsprite.SetSource, tile.sprite, result.name)
                Client.Set(tile.border, "hidden", position ~= selectedPosition)
                setTooltip(tile, result.label)
            end
        end
    end

    function grid.ShowSelection(selectedPosition)
        for position, tile in ipairs(grid.tiles) do
            if tile.showing then
                Client.Set(tile.border, "hidden", position ~= selectedPosition)
            end
        end
    end

    function grid.Hide()
        for _, tile in ipairs(grid.tiles) do
            tile.showing = false
            hideTile(tile)
        end
    end

    return grid
end

return SpriteGrid