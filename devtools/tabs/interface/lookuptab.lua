--[[
    lookuptab.lua - the "Lookup" sub-tab of the Interface tab: scan for the interfaces the game has, and filter them.

    Press "Scan (F9)" (or the F9 key) to list the interfaces. F9 is there because many things (tooltips, menus) only exist
    while the mouse is over something: pressing the button would move the mouse away, but F9 scans while the mouse is
    still where it was.

    The list shows every interface the game has a name for, with the loaded ones first (the others are faded). "Loaded only"
    leaves the faded ones out. The filter keeps the interfaces whose number, name or component names contain every word
    typed (so "tooltip" finds the interfaces that have a tooltip component).

    Pick an interface to see it, then:
      Open in tree          - switches to the Tree sub-tab and loads that interface there
      Highlight Selected    - an outline that pulses in the game around the picked interface (while it is loaded)

    The names come from id.Component (about 100,000 of them): the text before the first double underscore is the
    interface's name, and a name's number packs the interface id and the component id together (interface * 65536 + component).
]]

local UI = require("core/uiutil")
local TreeView = require("widgets/treeview")
local Settings = require("core/settings")
local Layers = require("core/layers")
local Names = require("tabs/interface/componentnames")

local LookupTab = {}

-- set by the Interface tab: switches to the Tree sub-tab and loads an interface there; returns a message
LookupTab.openInTree = nil

----------------------------------------------------------------
-- LAYOUT AND LIMITS
----------------------------------------------------------------
local HOTKEY         = "F9"
local MAX_INTERFACE  = 3000       -- highest interface number tried when looking for loaded interfaces
local MAX_STATIC_ID  = 2500       -- highest component id tried when finding an interface's top components
local MAX_ROOTS      = 60         -- most top components outlined (for an interface with no names)
local MAX_COMPONENTS = 400        -- most named components measured for the outline
local PANEL_WIDTH    = 898
local PANEL_HEIGHT   = 340
local SWATCH         = 24
local LOADED_GAP     = 530        -- space after "Loaded only", before the Clear list button
local SCAN_GAP       = 40         -- space after the Scan button (the button is drawn wider than its width), before "Loaded only"
local OPEN_GAP       = 60         -- the same after Open in tree, before "Highlight Selected"
local COUNT_WIDTH    = 160        -- the "Showing X of Y" text beside the Clear button, against the right border of the list
local FILTER_WIDTH   = 300
local BY_WIDTH       = 210        -- the Filter by drop-down
local CLEAR_WIDTH    = 70

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}
local rows = {}                  -- what the list shows: { number, name, loaded }
local selected = nil             -- the picked row
local loadedOnly = false
local filterText = ""
local filterBy = "name"           -- "name" or "content" (the Filter by drop-down)
local filterWait = nil
local scanned = false

local highlight = false          -- the checkbox
local colour = 0x39D6FF          -- 0xRRGGBB
local pulseRect, pulseFrame, pulseFailures = nil, 0, 0
local pulseNoted = false
local lastHidden = nil
local settingBox = false          -- true while the plugin ticks or unticks the box itself
local sawHidden = false          -- the page was seen hidden since the highlight was turned off
local resume = false             -- the highlight was on when the page was left, so it comes back when the page is shown again
local pulseTarget = nil          -- { interface number, { static ids of its top components } }

local PULSE_KEY = "devtools_lookup_pulse"
local HOTKEY_KEY = "devtools_lookup_hotkey"

local function status(text) UI.setText(controls.statusText, text) end

local try = UI.try

----------------------------------------------------------------
-- THE INTERFACES
----------------------------------------------------------------
local function isLoaded(number)
    local ok, result = pcall(function() return ui.Interfaces:GetInterface(number) ~= nil end)
    return ok and result == true
end

-- Name: the interface's number and name. Content: those and the names of the components inside it.
local function searchText(entry)
    if filterBy == "content" then
        if not entry.searchContent then
            entry.searchContent = string.lower(tostring(entry.number) .. " " .. (entry.name or "") .. " " .. table.concat(entry.names or {}, " "))
        end
        return entry.searchContent
    end
    if not entry.searchName then entry.searchName = string.lower(tostring(entry.number) .. " " .. (entry.name or "")) end
    return entry.searchName
end

----------------------------------------------------------------
-- THE LIST
----------------------------------------------------------------
local allRows = {}               -- every interface found by the last scan

local function rowText(row)
    return string.format("%4d     %s%s", row.number, row.name or "(no name)", row.loaded and "" or "     not loaded")
end

local function fillList()
    local entries = {}
    for i, row in ipairs(rows) do
        entries[#entries + 1] = { id = i, text = rowText(row), depth = 0, selected = row == selected, faded = not row.loaded, label = rowText(row) }
    end
    if controls.view then
        pcall(function() controls.view:SetEntries(entries) end)
    elseif controls.list then
        local plain = {}
        for i, e in ipairs(entries) do plain[i] = { id = e.id, label = e.label, selected = e.selected } end
        pcall(function() controls.list:SetEntries(plain) end)
    end
end

local function applyFilter()
    local terms = {}
    for word in string.gmatch(string.lower(filterText or ""), "%S+") do terms[#terms + 1] = word end
    rows = {}
    for _, row in ipairs(allRows) do
        if row.loaded or not loadedOnly then
            local ok = true
            if #terms > 0 then
                local text = row.entry and searchText(row.entry) or tostring(row.number)
                for _, term in ipairs(terms) do
                    if not string.find(text, term, 1, true) then ok = false; break end
                end
            end
            if ok then rows[#rows + 1] = row end
        end
    end
    -- keep the picked interface only while it is still listed
    local still = false
    for _, row in ipairs(rows) do
        if selected and row.number == selected.number then selected = row; still = true end
    end
    if not still then selected = nil; pulseTarget = nil end
    fillList()
    if controls.countText then
        UI.setText(controls.countText, scanned and ("Showing " .. #rows .. " of " .. #allRows) or "")
    end
end

----------------------------------------------------------------
-- HIGHLIGHT SELECTED (the outline around the picked interface's top components)
----------------------------------------------------------------
local function hidePulse()
    if pulseRect then pcall(function() pulseRect.hidden = true end) end
end

local function destroyPulse()
    if pulseRect then pcall(function() pulseRect:Destroy() end) end
    pulseRect = nil
end

local findRoots                 -- defined below

-- the static ids of the interface's named components (what the game calls them), found when it is picked
local function namedIDs(number)
    local entry = Names.interfaces()[number]
    local ids = {}
    if entry then
        for _, name in ipairs(entry.names) do
            local ok, value = pcall(function() return id.Component[name] end)
            if ok and type(value) == "number" then
                ids[#ids + 1] = value % 65536
                if #ids >= MAX_COMPONENTS then break end
            end
        end
    end
    return ids
end

-- the box around every visible component of the interface, in screen pixels; nil when nothing of it is showing
local function interfaceBounds(target)
    local left, top, right, bottom, seen = nil, nil, nil, nil, 0
    for _, staticID in ipairs(target.ids) do
        local okc, component = pcall(function() return ui.Interfaces:GetComponent(target.number, staticID) end)
        if okc and component then
            seen = seen + 1
            if try(component, "hidden") ~= true and try(component, "visibleGlobal") ~= false then
                local width, height = try(component, "width"), try(component, "height")
                local global = try(component, "xyGlobal")
                if global and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
                    -- the game's global positions leave out the scrolling of the layers the component sits in
                    local x, y, up = global.x, global.y, try(component, "parent")
                    for _ = 1, 64 do
                        if not up then break end
                        x = x - (try(up, "scrollX") or 0)
                        y = y - (try(up, "scrollY") or 0)
                        up = try(up, "parent")
                    end
                    left = left and math.min(left, x) or x
                    top = top and math.min(top, y) or y
                    right = right and math.max(right, x + width) or (x + width)
                    bottom = bottom and math.max(bottom, y + height) or (y + height)
                end
            end
        end
    end
    return left, top, right, bottom, seen
end

local checkFrame = 0
local function drawPulse()
    local target = pulseTarget
    if not (highlight and target) then return hidePulse() end
    local ok, err = pcall(function()
        local parent = Layers.parent()
        local origin = parent and try(parent, "xyGlobal")
        if not parent or not origin then return hidePulse() end

        -- The picked interface may only exist while something is hovered (a tooltip), so it is measured again every few
        -- frames; the outline appears when it shows up and goes when it goes.
        checkFrame = checkFrame + 1
        if target.ids == nil then target.ids = namedIDs(target.number) end
        if checkFrame % 4 == 1 or target.box == nil then
            local ids = target.ids
            if #ids == 0 and isLoaded(target.number) then ids = findRoots(target.number); target.ids = ids end
            local left, top, right, bottom, seen = interfaceBounds(target)
            local state = left and "outlined" or (seen > 0 and "loaded, nothing visible" or "not showing")
            if state ~= target.state then
                target.state = state
                pcall(print, "[DevTools highlight] interface " .. target.number .. ": " .. state .. " (" .. #target.ids .. " named components, " .. seen .. " found)")
            end
            target.box = left and { left, top, right, bottom } or false
        end
        local box = target.box
        if not box then return hidePulse() end
        if not pulseRect then
            pulseRect = ui.Rectangle.new(parent)
            pulseRect.fill, pulseRect.outlineThickness, pulseRect.clickthrough = false, 3, true
        end
        pulseFrame = pulseFrame + 1
        local fade = 0.5 + 0.5 * math.sin(pulseFrame * 0.05)
        pulseRect:SetPos(math.floor(box[1] - origin.x), math.floor(box[2] - origin.y))
        pulseRect:SetSize(math.floor(box[3] - box[1]), math.floor(box[4] - box[2]))
        pulseRect.rgba = colour * 256 + math.floor(70 + 185 * fade)
        pulseRect.hidden = false
        if pulseFrame % 30 == 1 then pulseRect:MoveToFront() end
    end)
    if ok then pulseFailures = 0 else
        destroyPulse()
        pulseFailures = pulseFailures + 1
        if pulseFailures >= 5 then
            highlight = false
            pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
            if controls.highlightCheck then settingBox = true; pcall(function() controls.highlightCheck:SetSelected("show", false, true) end); settingBox = false end
            status("Highlight Selected turned itself off: " .. tostring(err))
        end
    end
end

local function setHighlight(on)
    highlight = on == true
    pcall(print, "[DevTools highlight] lookup highlight " .. (highlight and "on" or "off") .. (pulseTarget and (", interface " .. tostring(pulseTarget.number)) or ", nothing picked"))
    pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
    pulseFailures = 0
    if highlight then
        local ok, err = pcall(function() Event.Draw.Subscribe(PULSE_KEY, drawPulse) end)
        if not ok then highlight = false; status("Couldn't start Highlight Selected: " .. tostring(err)) end
    else
        destroyPulse()
    end
end

-- turns Highlight Selected off and unticks it (used whenever this page is left)
local function highlightOff()
    if not highlight then return end
    resume = true
    sawHidden = false
    setHighlight(false)
    if controls.highlightCheck then settingBox = true; pcall(function() controls.highlightCheck:SetSelected("show", false, true) end); settingBox = false end
end

local function stopPulse()
    pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
    destroyPulse()
    pulseTarget = nil
end

-- the interface's top components (the ones with no parent inside this interface), found once when it is picked
function findRoots(number)
    local found = {}
    for staticID = 0, MAX_STATIC_ID do
        local ok, component = pcall(function() return ui.Interfaces:GetComponent(number, staticID) end)
        if ok and component then found[staticID] = component end
    end
    local roots = {}
    for staticID = 0, MAX_STATIC_ID do
        local component = found[staticID]
        if component then
            local parent = try(component, "parentStatic")
            local parentID = parent and try(parent, "staticID")
            local sameInterface = parent and (try(parent, "interfaceID") == number or try(parent, "interfaceID") == nil)
            if not (type(parentID) == "number" and parentID ~= staticID and sameInterface and found[parentID]) then
                roots[#roots + 1] = staticID
                if #roots >= MAX_ROOTS then break end
            end
        end
    end
    return roots
end

----------------------------------------------------------------
-- PICKING AN INTERFACE
----------------------------------------------------------------
local function showInfo()
    if not selected then
        UI.setText(controls.infoText, "Pick an interface")
        UI.setDisabled(controls.openButton, true)
        return
    end
    UI.setDisabled(controls.openButton, false)
    local count = selected.entry and #selected.entry.names or 0
    UI.setText(controls.infoText, string.upper(selected.name or "no name") .. " (" .. selected.number .. ") - "
        .. count .. " named component" .. (count == 1 and "" or "s") .. (selected.loaded and "" or " - not loaded right now"))
end

local function pick(index)
    local row = rows[index]
    if not row then return end
    selected = row
    row.loaded = isLoaded(row.number)
    pulseTarget = { number = row.number }
    pcall(print, "[DevTools highlight] lookup picked interface " .. row.number)
    pulseNoted = false
    fillList()
    showInfo()
    status("")
end

----------------------------------------------------------------
-- SCAN
----------------------------------------------------------------
local function scan(source)
    local interfaces = Names.interfaces()
    local seen, found = {}, {}
    for number, entry in pairs(interfaces) do
        seen[number] = true
        found[#found + 1] = { number = number, name = entry.name, entry = entry, loaded = isLoaded(number) }
    end
    -- loaded interfaces the game has no names for
    for number = 0, MAX_INTERFACE do
        if not seen[number] and isLoaded(number) then
            found[#found + 1] = { number = number, loaded = true }
        end
    end
    table.sort(found, function(a, b)
        if a.loaded ~= b.loaded then return a.loaded end
        return a.number < b.number
    end)
    allRows = found
    scanned = true
    -- f9 can scan when this page isnt built, results get kept and drawn when it opens
    if not controls.statusText then return end
    applyFilter()
    showInfo()
    status(source == "hotkey" and ("Scanned with " .. HOTKEY) or "")
end

local function onKeyDown(event)
    if event.isRepeat or event.gameKey ~= GameKey[HOTKEY] or Keyboard.IsBlocked() then return end
    pcall(scan, "hotkey")
end

-- empties the list (the filter text and the picked options are left as they are)
local function clearList()
    allRows, rows, selected, scanned = {}, {}, nil, false
    pulseTarget = nil
    fillList()
    UI.setText(controls.countText, "")
    showInfo()
    status("")
end

local function onOpenClicked()
    if not selected then return status("Pick an interface first") end
    if type(LookupTab.openInTree) ~= "function" then return status("The Tree tab isn't available") end
    highlightOff()
    local ok, message = pcall(LookupTab.openInTree, selected.number)
    status(ok and tostring(message or "") or ("Couldn't open it: " .. tostring(message)))
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function LookupTab.build(page)
    UI.heading(page, "Find an interface")
    page:AddText({ text = "Press Scan (" .. HOTKEY .. ") to list the interfaces." })

    controls.scan = page:AddFancyButton("Scan (" .. HOTKEY .. ")", function() scan("button") end, {
        variant = "positive", width = 130, columnGap = SCAN_GAP,
        tooltip = "Lists the interfaces. The " .. HOTKEY .. " key does the same, even while you hover something in the game.",
    })
    pcall(function()
        controls.loadedOnly = page:AddCheckboxButton({ { text = "Loaded only", value = "loaded", selected = loadedOnly } }, {
            inline = true, columnGap = LOADED_GAP,
            onChange = function(_, _, _, isSelected) loadedOnly = isSelected == true; applyFilter() end,
        })
    end)
    page:AddSimpleButton("Clear list", clearList, { inline = true, columnGap = 0, width = 90, tooltip = "Empty the list (scan again to fill it)" })

    -- the list is drawn with the same view as the Tree tab; a plain list is used if that can't be made
    local host
    pcall(function() host = page:AddPanel({ width = PANEL_WIDTH, height = PANEL_HEIGHT }) end)
    if host then
        pcall(function() host:SetScrollable(false) end)
        for _, name in ipairs({ "root", "content", "container" }) do
            local parent = not controls.view and (function() local ok, v = pcall(function() return host[name] end); return ok and v or nil end)()
            if parent then
                local ok, view = pcall(TreeView.new, parent, 0, 0, PANEL_WIDTH, PANEL_HEIGHT, function(key) pick(tonumber(key)) end, nil, true)
                if ok then controls.view = view end
            end
        end
    end
    if not controls.view then
        controls.list = page:AddList({
            maxSelected = 1, entries = {}, width = PANEL_WIDTH, height = PANEL_HEIGHT,
            onChange = function(_, key, isSelected) if isSelected then pick(key) end end,
        })
    end

    -- under the list: the filter (it works on the scanned list as you type), then Open in tree
    controls.filter = page:AddTextField({
        placeholder = "Filter text", maxLength = 60, width = FILTER_WIDTH, columnGap = 10, marginTop = 10,
        onChange = function(field) filterText = UI.fieldText(field); filterWait = nil; applyFilter() end,
    })
    pcall(function() controls.filter:SetText(filterText, false) end)
    pcall(function()
        controls.filterBy = page:AddComboBox({
            entries = { { label = "Filter by: Name", id = 1 }, { label = "Filter by: Content", id = 2 } }, selectedID = filterBy == "content" and 2 or 1,
            width = BY_WIDTH, inline = true, columnGap = 10,
            onChange = function(_, chosenId) filterBy = chosenId == 2 and "content" or "name"; applyFilter() end,
        })
    end)
    page:AddSimpleButton("Clear", function()
        pcall(function() controls.filter:SetText("", false) end)
        filterText = ""; filterWait = nil; applyFilter()
    end, { inline = true, columnGap = PANEL_WIDTH - FILTER_WIDTH - 10 - BY_WIDTH - 10 - CLEAR_WIDTH - COUNT_WIDTH, width = CLEAR_WIDTH, tooltip = "Clear the filter" })
    controls.countText = page:AddText({ text = "", width = COUNT_WIDTH, inline = true, columnGap = 0 })

    -- under the list: Open in tree, and the Highlight Selected checkbox with its colour
    colour = Settings.get("lookupColour", colour)
    controls.openButton = page:AddFancyButton("Open in tree", onOpenClicked, {
        variant = "positive", width = 130, columnGap = OPEN_GAP, marginTop = 10,
        tooltip = "Switch to the Tree tab and load the picked interface there",
    })
    pcall(function()
        controls.highlightCheck = page:AddCheckboxButton({ { text = "Highlight Selected", value = "show", selected = highlight } }, {
            inline = true, columnGap = 8, onChange = function(_, _, _, isSelected)
                if settingBox then return end      -- the plugin itself ticking / unticking the box
                resume = false; setHighlight(isSelected)
            end,
        })
    end)
    pcall(function()
        controls.colour = page:AddColourPicker({
            value = colour * 256 + 255, alphaSlider = false, buttonSize = SWATCH, inline = true,
            tooltip = "The colour of the pulsing outline", windowTitle = "Highlight Selected colour",
            onChange = function(_, value)
                if type(value) == "number" then
                    colour = math.floor(value) // 256
                    Settings.set("lookupColour", colour)
                end
            end,
        })
    end)
    controls.infoText = page:AddText({ text = "Pick an interface" })
    controls.statusText = page:AddText({ text = controls.view and "" or "(the drawn list couldn't be made, so a plain list is used)" })

    if scanned then applyFilter() end
    showInfo()
end

-- the filter waits until you stop typing (called from the Interface tab's update)
function LookupTab.tick()
    -- leaving this page for another sub-tab turns the highlight off, and showing it
    -- again turns it back on if it was on
    pcall(function()
    if controls.scan then
            local hiddenNow = UI.pageHidden(try(controls.scan, "root"))
            if hiddenNow ~= lastHidden then
                lastHidden = hiddenNow
                pcall(print, "[DevTools highlight] lookup page " .. (hiddenNow and "hidden" or "shown"))
            end
            if hiddenNow then
                if highlight then highlightOff() end
                if resume then sawHidden = true end
            elseif resume and sawHidden then
                sawHidden = false
                LookupTab.enter()
            end
        end
    end)
    -- the filter box is also looked at every update, in case typing doesn't report a change
    if controls.filter then
        local typed = UI.fieldText(controls.filter)
        if typed ~= filterText then filterText = typed; filterWait = nil; pcall(applyFilter) end
    end
    if controls.view then pcall(function() controls.view:Refresh() end) end
    if filterWait then
        filterWait = filterWait - 1
        if filterWait <= 0 then filterWait = nil; pcall(applyFilter) end
    end
end

-- called when this page is left, and when it is shown again
function LookupTab.leave() highlightOff() end
function LookupTab.enter()
    if not resume then return end
    resume = false
    setHighlight(true)
    if controls.highlightCheck then settingBox = true; pcall(function() controls.highlightCheck:SetSelected("show", true, true) end); settingBox = false end
end

-- back to how it was when first opened
function LookupTab.reset()
    allRows, rows, selected, scanned, resume = {}, {}, nil, false, false
    filterText, filterWait = "", nil
    pulseTarget = nil
    if controls.filter then pcall(function() controls.filter:SetText("", false) end) end
    if controls.statusText then fillList(); showInfo(); status("") end
end

-- f9 is always listening since its for catching whats open while hovering, page might not be built
function LookupTab.start()
    Event.KeyDown.Subscribe(HOTKEY_KEY, onKeyDown)
end

function LookupTab.release()
    -- just the rectangle, highlight keeps running and draws a new one next frame
    destroyPulse()
    if controls.view then pcall(function() controls.view:Destroy() end) end
    controls = {}
    rows = {}
end

function LookupTab.shutdown()
    pcall(function() Event.KeyDown.Unsubscribe(HOTKEY_KEY) end)
    stopPulse()
end

return LookupTab
