--[[
    configstab.lua - the "Configs" tab: browse the game's configs (NPC, Obj, Quest, Achievement, vars).

    Pick a type, type a keyphrase or an id, pick a result and its properties appear beside the results. Click a
    property (or "All") to put it in the copy box under them, then select the text there and copy it.
    "Search" asks the game for every id of the type, so configs that aren't listed yet turn up.
]]

local Configs = require("data/configs")
local UI = require("core/uiutil")

local ConfigsTab = {}

----------------------------------------------------------------
-- LAYOUT
----------------------------------------------------------------
local LIST_ROWS      = 12         -- rows visible in the results and details lists
local ROW_HEIGHT     = 22         -- pixels per row
local LIST_HEIGHT    = LIST_ROWS * ROW_HEIGHT
local PAGE_SIZE      = 40         -- results shown at a time (PrettyUI can only hold about 4,000 rows in all)
local LIST_WIDTH     = 455        -- each of the two lists; the details sit to the right of the results
local LIST_GAP       = 18         -- space between them
local MAX_TEXT       = 64         -- longest filter that can be typed
local DROPDOWN_WIDTH = 280        -- the Type and Display as dropdowns
local FILTER_WIDTH   = 430        -- the filter box
local COPY_WIDTH     = LIST_WIDTH
local RESULT_FILTER_WIDTH = 260   -- the "filter these results" box
local CLEAR_WIDTH    = 70         -- its Clear button
local DISPLAY_LABEL  = 75         -- "Display as" text under the results
local DISPLAY_COMBO  = 190        -- and its dropdown
local PAGER_BUTTON   = 70         -- width of the Prev / Next buttons
local PAGER_GAP      = 10         -- space between Prev and Next
local SAVE_DISPLAY   = "devtoolsDisplayMode"
local ALL            = "__all"    -- id of the "All" row in the details list

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}               -- list, details, search, copyBox, countText, detailTitle, statusText
local typeKey = Configs.TYPES[1].key
local displayMode = 1             -- how results are named (Configs.DISPLAY_MODES); remembered between sessions
local selected = nil              -- config name picked in the list
local typedSearch = ""
local listScroll = {}
local detail = {}                 -- { field, value } pairs of the selected config
local showResults = true          -- false after Reset, until you type or press Search
local resultFilter = ""            -- what is typed in the "filter these results" box
local pageIndex = 1               -- which page of the results is showing

local function status(text) UI.setText(controls.statusText, text) end

----------------------------------------------------------------
-- COPY BOX
-- The API has no clipboard call, so what you click in the details is put in the box under the lists. Select the text
-- there (Ctrl+A) and copy it (Ctrl+C).
----------------------------------------------------------------
local function setCopyBox(text)
    if controls.copyBox then pcall(function() controls.copyBox:SetText(text, false) end) end
end

local function allText()
    local lines = {}
    for _, pair in ipairs(detail) do lines[#lines + 1] = pair[1] .. ": " .. pair[2] end
    return table.concat(lines, "; ")
end

-- A click in the details: "All" copies every property, a property copies just its value
local function onDetailPick(_, key, isSelected)
    if not isSelected then return end
    if key == ALL then return setCopyBox(allText()) end
    local pair = detail[key]
    if pair then setCopyBox(pair[2]) end
end

----------------------------------------------------------------
-- SELECTED CONFIG
----------------------------------------------------------------
local function showDetails()
    detail = {}
    local cfg = selected and Configs.open(typeKey, selected)

    if not selected then
        UI.setText(controls.detailTitle, "Nothing selected")
    elseif not cfg then
        UI.setText(controls.detailTitle, selected .. "  (can't be read)")
    else
        UI.setText(controls.detailTitle, selected)
        detail = Configs.describe(typeKey, cfg)
    end

    local entries = {}
    if #detail > 0 then entries[1] = { id = ALL, label = "All" } end
    for i, pair in ipairs(detail) do entries[#entries + 1] = { id = i, label = pair[1] .. ":  " .. pair[2] } end
    controls.details:SetEntries(entries)

    setCopyBox(#detail > 0 and allText() or "")
end

local function onPick(_, name, isSelected)
    if not isSelected then return end
    selected = name
    showDetails()
    status("")
end

----------------------------------------------------------------
-- RESULTS LIST
----------------------------------------------------------------
local function countLine(shown, total)
    local scanning, nextId, found, errors = Configs.scanning(typeKey)
    if scanning then return "Searching... id " .. nextId .. ", " .. found .. " found" end
    if Configs.count(typeKey) == 0 then
        return errors and errors > 0 and ("None found (" .. errors .. " lookups failed)")
            or "None listed yet - type an exact id or name, or press Search"
    end
    if shown == 0 then return "Showing 0 of " .. total .. " results" end
    local first = (pageIndex - 1) * PAGE_SIZE + 1
    return "Showing " .. first .. "-" .. (first + shown - 1) .. " of " .. total .. " results"
end

local function refreshResults()
    if not controls.list then return end

    if not showResults then
        controls.list:SetEntries({})
        UI.setText(controls.countText, "")
        return
    end

    local all = Configs.search(typeKey, UI.fieldText(controls.search), math.huge)

    -- the "filter these results" box narrows the list by what is actually shown on each row
    local terms = {}
    for word in resultFilter:lower():gmatch("%S+") do terms[#terms + 1] = word end
    if #terms > 0 then
        local kept = {}
        for _, hit in ipairs(all) do
            local label = Configs.label(typeKey, hit.name, hit.id, displayMode):lower()
            local ok = true
            for _, term in ipairs(terms) do
                if not label:find(term, 1, true) then ok = false; break end
            end
            if ok then kept[#kept + 1] = hit end
        end
        all = kept
    end

    local results
    results, pageIndex = UI.page(all, pageIndex, PAGE_SIZE)

    local entries = {}
    for _, hit in ipairs(results) do
        entries[#entries + 1] = {
            id = hit.name,
            label = Configs.label(typeKey, hit.name, hit.id, displayMode),
            selected = hit.name == selected,
        }
    end
    controls.list:SetEntries(entries)
    UI.setText(controls.countText, countLine(#results, #all))
end

----------------------------------------------------------------
-- BUTTONS AND DROPDOWNS
----------------------------------------------------------------
local function typeIndex()
    for index, def in ipairs(Configs.TYPES) do
        if def.key == typeKey then return index end
    end
    return 1
end

local function onTypeChosen(_, chosenId)
    local def = Configs.TYPES[chosenId]
    if not def then return end
    typeKey = def.key
    selected = nil
    pageIndex = 1
    refreshResults()
    showDetails()
    status("")
end

local function onDisplayChosen(_, chosenId)
    displayMode = chosenId
    pcall(function() PersistentDB:SetInt(SAVE_DISPLAY, chosenId) end)
    refreshResults()
end

local function onFilterChanged()
    showResults = true
    pageIndex = 1
    refreshResults()
end

local function onClearResultFilter()
    pcall(function() controls.resultFilter:SetText("", false) end)
    resultFilter = ""
    pageIndex = 1
    refreshResults()
end

local function onResultFilterChanged()
    resultFilter = UI.fieldText(controls.resultFilter)
    pageIndex = 1
    refreshResults()
end

local function onPageMoved(step)
    pageIndex = pageIndex + step
    refreshResults()
end

local function onSearchClicked()
    showResults = true
    status(Configs.startScan(typeKey) and ("Searching every " .. typeKey .. " id - this takes a few seconds")
        or "Already searching")
    refreshResults()
end

-- Clears the filter box and the results
local function onResetClicked()
    pcall(function() controls.search:SetText("", false) end)
    pcall(function() controls.resultFilter:SetText("", false) end)
    resultFilter = ""
    showResults = false
    pageIndex = 1
    refreshResults()
    status("")
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function ConfigsTab.reset()
    displayMode = 1
    pcall(function() PersistentDB:SetInt(SAVE_DISPLAY, 1) end)
end

function ConfigsTab.loadSettings()
    local ok, saved = pcall(function() return PersistentDB:GetInt(SAVE_DISPLAY) end)
    if ok and Configs.DISPLAY_MODES[saved] then displayMode = saved end
end

-- Every width in a row below adds up to LIST_WIDTH, and every gap inside a row is 0, so the rows line up exactly
function ConfigsTab.build(page)
    page:AddText({ text = "Type" })
    page:AddComboBox({
        entries = UI.dropdownEntries(Configs.TYPES), selectedID = typeIndex(), onChange = onTypeChosen, width = DROPDOWN_WIDTH,
    })

    page:AddText({ text = "Filter" })
    controls.search = page:AddTextField({
        placeholder = "Filter by name, or type an id", maxLength = MAX_TEXT, onChange = onFilterChanged, width = FILTER_WIDTH,
    })
    page:AddSimpleButton("Search", onSearchClicked, { tooltip = "Try every id to list all configs of this type" })
    page:AddSimpleButton("Reset", onResetClicked, { inline = true, tooltip = "Clear the filter and the results" })
    page:AddDivider(UI.TIGHT_DIVIDER)

    -- above the lists: filter the results (left), name of the selected config (right)
    controls.resultFilter = page:AddTextField({
        placeholder = "Filter these results as you type", maxLength = MAX_TEXT, onChange = onResultFilterChanged,
        width = RESULT_FILTER_WIDTH, columnGap = 0,
    })
    page:AddSimpleButton("Clear", onClearResultFilter, {
        inline = true, columnGap = 0, width = CLEAR_WIDTH, tooltip = "Clear the results filter",
    })
    page:AddText({ text = "", inline = true, columnGap = LIST_GAP, width = LIST_WIDTH - RESULT_FILTER_WIDTH - CLEAR_WIDTH })
    controls.detailTitle = page:AddText({ text = "Nothing selected", width = LIST_WIDTH, inline = true })

    -- the results on the left, the selected config's properties on the right
    controls.list = page:AddList({
        maxSelected = 1, entries = {}, onChange = onPick, width = LIST_WIDTH, height = LIST_HEIGHT, columnGap = LIST_GAP,
    })
    controls.details = page:AddList({
        maxSelected = 1, entries = {}, onChange = onDetailPick, width = LIST_WIDTH, height = LIST_HEIGHT, inline = true,
    })

    -- under the results: "Display as" on the left, Prev / Next on the right
    page:AddText({ text = "Display as", width = DISPLAY_LABEL, columnGap = 0 })
    page:AddComboBox({
        entries = UI.dropdownEntries(Configs.DISPLAY_MODES), selectedID = displayMode, onChange = onDisplayChosen,
        width = DISPLAY_COMBO, inline = true, columnGap = 0,
    })
    page:AddText({
        text = "", inline = true, columnGap = 0,
        width = LIST_WIDTH - DISPLAY_LABEL - DISPLAY_COMBO - 2 * PAGER_BUTTON - PAGER_GAP,
    })
    page:AddSimpleButton("Prev", function() onPageMoved(-1) end, {
        inline = true, columnGap = PAGER_GAP, width = PAGER_BUTTON, tooltip = "Previous page of results",
    })
    page:AddSimpleButton("Next", function() onPageMoved(1) end, {
        inline = true, columnGap = 0, width = PAGER_BUTTON, tooltip = "Next page of results",
    })
    controls.countText = page:AddText({ text = "", width = LIST_WIDTH })
    page:AddDivider(UI.TIGHT_DIVIDER)

    page:AddText({ text = "Copy box - select the text and copy it" })
    controls.copyBox = page:AddTextField({ placeholder = "Click a property above", maxLength = 9999, width = COPY_WIDTH })
    controls.statusText = page:AddText({ text = "" })

    pcall(function() controls.search:SetText(typedSearch, false) end)
    pcall(function() controls.resultFilter:SetText(resultFilter, false) end)
    refreshResults()
    showDetails()
    if listScroll.list then pcall(function() controls.list:SetScrollPosition(listScroll.list) end) end
    if listScroll.details then pcall(function() controls.details:SetScrollPosition(listScroll.details) end) end
end

-- The window was closed for good: forget its controls
function ConfigsTab.release()
    -- tab gets rebuilt every time its shown so typed text has to live here
    if controls.search then typedSearch = UI.fieldText(controls.search) end
    if controls.list then listScroll.list = controls.list.scrollY end
    if controls.details then listScroll.details = controls.details.scrollY end
    controls = {}
end

-- keep a selected var's value live
function ConfigsTab.onVarChanged(name)
    if controls.list and Configs.get(typeKey).vars and selected == name then showDetails() end
end

local lastFound = -1
function ConfigsTab.onScanProgress(key)
    if not controls.list or key ~= typeKey then return end
    local scanning, nextId, found = Configs.scanning(key)
    if not scanning then
        lastFound = -1
        refreshResults()
        status("Search finished")
    elseif found ~= lastFound or nextId % 2000 < 400 then
        lastFound = found
        UI.setText(controls.countText, countLine(0, 1))
    end
end

return ConfigsTab
