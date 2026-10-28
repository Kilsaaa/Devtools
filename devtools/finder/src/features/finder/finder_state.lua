local ResultList = require("finder/src/features/finder/result_list")

local FinderState = {}

FinderState.PAGE_SIZE = 45   -- 9 per row x 5 rows (63 and 90 ran the client out of layers)
FinderState.SEARCH_CHANGED = "search"
FinderState.OPTIONS_CHANGED = "options"
FinderState.PREVIEW_SIZES = { 16, 24, 32, 48, 64 }
FinderState.DEFAULT_PREVIEW_SIZE = 48
FinderState.PREVIEW_BACKGROUNDS = { "dark", "light", "checker" }
FinderState.SAVED_VERSION = 2

local COPY_FORMAT = 'rsprite.Get("%s")'
local DRAW_FORMAT = 'rsprite.Draw(parent, "%s", { size = %d })'
local PRETTYUI_FORMAT = 'window:AddSprite(rsprite.Get("%s"), { size = %d })'

local function isPreviewSize(size)
    for _, allowed in ipairs(FinderState.PREVIEW_SIZES) do
        if size == allowed then
            return true
        end
    end
    return false
end

local function backgroundPosition(background)
    for position, known in ipairs(FinderState.PREVIEW_BACKGROUNDS) do
        if background == known then
            return position
        end
    end
    return nil
end

local function nonEmptyString(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

function FinderState.New(saved)
    local source = type(saved) == "table" and saved or {}
    local state = {
        query = type(source.query) == "string" and source.query or "",
        tag = nonEmptyString(source.tag),
        page = 1,
        previewSize = FinderState.DEFAULT_PREVIEW_SIZE,
        previewBackground = FinderState.PREVIEW_BACKGROUNDS[1],
        selectedName = nil,
        selectedTile = nil,
        selectedEntry = nil,
        variant = 1,
        entries = nil,
        results = nil,
        tiles = {},
        total = 0,
    }
    local savedByThisVersion = type(source.version) == "number"
        and source.version >= FinderState.SAVED_VERSION
    if savedByThisVersion and type(source.page) == "number" and source.page >= 1 then
        state.page = math.floor(source.page)
    end
    if savedByThisVersion then
        state.selectedName = nonEmptyString(source.selectedName)
    end
    if isPreviewSize(source.previewSize) then
        state.previewSize = source.previewSize
    end
    if backgroundPosition(source.previewBackground) ~= nil then
        state.previewBackground = source.previewBackground
    end
    return state
end

function FinderState.Snapshot(state)
    return {
        version = FinderState.SAVED_VERSION,
        query = state.query,
        tag = state.tag or "",
        page = state.page,
        previewSize = state.previewSize,
        previewBackground = state.previewBackground,
        selectedName = state.selectedName or "",
    }
end

function FinderState.PageCount(state)
    return math.max(1, math.ceil(state.total / FinderState.PAGE_SIZE))
end

function FinderState.Offset(state)
    return (state.page - 1) * FinderState.PAGE_SIZE
end

function FinderState.Invalidate(state)
    state.results = nil
end

function FinderState.ForgetSearch(state)
    state.entries = nil
    state.results = nil
end

function FinderState.StartOver(state)
    state.page = 1
    FinderState.Select(state, nil)
    FinderState.ForgetSearch(state)
end

function FinderState.SetQuery(state, query)
    if query == state.query then
        return false
    end
    state.query = query
    state.page = 1
    FinderState.ForgetSearch(state)
    return true
end

function FinderState.SetTag(state, tag)
    local normalisedTag = nonEmptyString(tag)
    if normalisedTag == state.tag then
        return false
    end
    state.tag = normalisedTag
    state.page = 1
    FinderState.ForgetSearch(state)
    return true
end

function FinderState.ClearFilters(state)
    local queryChanged = FinderState.SetQuery(state, "")
    local tagChanged = FinderState.SetTag(state, nil)
    return queryChanged or tagChanged
end

local function clampPage(state, page)
    return math.max(1, math.min(math.floor(page), FinderState.PageCount(state)))
end

function FinderState.SetPage(state, page)
    local clamped = clampPage(state, page)
    if clamped == state.page then
        return false
    end
    state.page = clamped
    return true
end

function FinderState.SetPreviewSize(state, size)
    if not isPreviewSize(size) then
        return false
    end
    state.previewSize = size
    return true
end

function FinderState.CycleBackground(state)
    local position = backgroundPosition(state.previewBackground) or 0
    local backgrounds = FinderState.PREVIEW_BACKGROUNDS
    state.previewBackground = backgrounds[position % #backgrounds + 1]
    return state.previewBackground
end

function FinderState.Select(state, tile, variant)
    state.selectedTile = tile
    if tile == nil then
        state.variant = 1
        state.selectedEntry = nil
        state.selectedName = nil
        return
    end
    state.variant = math.max(1, math.min(variant or 1, #tile.members))
    state.selectedEntry = tile.members[state.variant]
    state.selectedName = state.selectedEntry.name
end

function FinderState.StepVariant(state, step)
    local tile = state.selectedTile
    if tile == nil then
        return false
    end
    local variant = math.max(1, math.min(state.variant + step, #tile.members))
    if variant == state.variant then
        return false
    end
    FinderState.Select(state, tile, variant)
    return true
end

function FinderState.VariantStep(state)
    local tile = state.selectedTile
    if tile == nil or tile.family == nil then
        return nil
    end
    return { index = state.variant, count = #tile.members }
end

function FinderState.SelectedPosition(state)
    if state.results == nil then
        return nil
    end
    local tilePosition = ResultList.Locate(state.results, state.selectedName)
    if tilePosition == nil then
        return nil
    end
    local position = tilePosition - FinderState.Offset(state)
    if position < 1 or position > FinderState.PAGE_SIZE then
        return nil
    end
    return position
end

local function pageOf(tilePosition)
    return math.floor((tilePosition - 1) / FinderState.PAGE_SIZE) + 1
end

local function slicePage(state)
    state.page = clampPage(state, state.page)
    local tiles = {}
    local offset = FinderState.Offset(state)
    for position = 1, FinderState.PAGE_SIZE do
        tiles[position] = state.results.tiles[offset + position]
    end
    state.tiles = tiles
end

function FinderState.Refresh(state, search, options, change)
    if state.results == nil then
        if state.entries == nil then
            state.entries = search(state.query, state.tag)
        end
        state.results = ResultList.Build(state.entries, options)
    end
    state.total = #state.results.tiles
    local tilePosition, variant = ResultList.Locate(state.results, state.selectedName)
    if change == FinderState.OPTIONS_CHANGED then
        state.page = tilePosition ~= nil and pageOf(tilePosition) or 1
    end
    slicePage(state)
    local onPage = FinderState.SelectedPosition(state) ~= nil
    if tilePosition ~= nil and (change ~= FinderState.SEARCH_CHANGED or onPage) then
        FinderState.Select(state, state.results.tiles[tilePosition], variant)
    else
        FinderState.Select(state, state.tiles[1], 1)
    end
end

function FinderState.GetText(name)
    return string.format(COPY_FORMAT, name)
end

function FinderState.DrawText(name, previewSize)
    return string.format(DRAW_FORMAT, name, previewSize)
end

function FinderState.PrettyText(name, previewSize)
    return string.format(PRETTYUI_FORMAT, name, previewSize)
end

function FinderState.FormatCount(count)
    local formatted = tostring(math.floor(count))
    local replaced
    repeat
        formatted, replaced = string.gsub(formatted, "^(%d+)(%d%d%d)", "%1,%2")
    until replaced == 0
    return formatted
end

local function counted(count, singular, plural)
    return FinderState.FormatCount(count) .. " " .. (count == 1 and singular or plural)
end

function FinderState.ResultsLabel(state, favouritesOnly)
    if favouritesOnly then
        return counted(state.total, "favourite", "favourites")
    end
    if state.query == "" and state.tag == nil then
        return counted(state.total, "sprite", "sprites")
    end
    return counted(state.total, "match", "matches")
end

function FinderState.VariantLabel(step)
    return string.format(
        "Variant %s of %s",
        FinderState.FormatCount(step.index),
        FinderState.FormatCount(step.count)
    )
end

function FinderState.PageLabel(state)
    return string.format(
        "Page %s of %s",
        FinderState.FormatCount(state.page),
        FinderState.FormatCount(FinderState.PageCount(state))
    )
end

return FinderState