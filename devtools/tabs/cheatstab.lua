--[[
    cheatstab.lua - the "Cheats" tab: build a developer cheat that needs a target and/or a value, then run it.

    Choose a cheat, then pick what it applies to (a var, an item, a skill ...), type its value and press Apply.
    The exact command is shown before it is run. Cheats only work on a development server.
    The cheats that need nothing typed (godmode, bank ...) are on the "Quick Cheats" tab.

    To add a cheat, add an entry to CHEATS below.
]]

local Configs = require("data/configs")
local UI = require("core/uiutil")
local Settings = require("core/settings")

local CheatsTab = {}

----------------------------------------------------------------
-- THE CHEATS (from https://developer.runescape.com/rs/cheats.html)
----------------------------------------------------------------
local SKILLS = {
    "attack", "defence", "strength", "constitution", "ranged", "prayer", "magic", "cooking", "woodcutting", "fletching",
    "fishing", "firemaking", "crafting", "smithing", "mining", "herblore", "agility", "thieving", "slayer", "farming",
    "runecrafting", "hunter", "construction", "summoning", "dungeoneering", "divination", "invention", "archaeology",
    "necromancy",
}

-- label:          shown in the dropdown
-- search:         a config type to pick the target from (Obj, VarPlayer, VarClient)
-- choices:        or a fixed list to pick the target from (skills)
-- (neither):      the cheat has no target, only a value
-- targetOptional: the cheat works without picking a target
-- valueLabel:     what the value box is for;   optional: it works without a value;   noValue: no value at all
-- quick:          true = the toggle button turns the picked var on (1) or off (0)
-- command:        builds the cheat text from the picked target and the typed value
local CHEATS = {
    -- variables
    { label = "Set player var", search = "VarPlayer", valueLabel = "Value", quick = true,
      command = function(target, value) return "!setvar " .. target .. " " .. value end },
    { label = "Set client var", search = "VarClient", valueLabel = "Value", quick = true,
      command = function(target, value) return "!setvarc " .. target .. " " .. value end },
    { label = "Show a player var in the console", search = "VarPlayer", noValue = true,
      command = function(target) return "!getvar " .. target end },
    { label = "Show a client var in the console", search = "VarClient", noValue = true,
      command = function(target) return "!getvarc " .. target end },

    -- items
    { label = "Give item", search = "Obj", optional = true, valueLabel = "Amount, then inventory (optional, e.g. 10 or 10 bank)",
      command = function(target, value) return "!give " .. target .. (value ~= "" and (" " .. value) or "") end },
    { label = "Drop item at your feet", search = "Obj", optional = true, valueLabel = "Amount (optional)",
      command = function(target, value) return "!objadd " .. target .. (value ~= "" and (" " .. value) or "") end },
    { label = "List ground items nearby", search = "Obj", targetOptional = true, valueLabel = "Radius (up to 32)",
      command = function(target, value) return "!listobjs " .. value .. " " .. (target or "null") end },

    -- skills
    { label = "Set skill level", choices = SKILLS, valueLabel = "Level",
      command = function(target, value) return "!skillsetlevel " .. target .. " " .. value end },
    { label = "Add skill levels", choices = SKILLS, valueLabel = "Levels to add",
      command = function(target, value) return "!skilladdlevel " .. target .. " " .. value end },
    { label = "Set skill XP", choices = SKILLS, valueLabel = "XP",
      command = function(target, value) return "!skillsetxp " .. target .. " " .. value end },
    { label = "Add skill XP", choices = SKILLS, valueLabel = "XP to add",
      command = function(target, value) return "!skilladdxp " .. target .. " " .. value end },

    -- location and inspection
    { label = "Teleport", valueLabel = "Coordinate or named teleport (e.g. 0,50,50 or grandexchange)",
      command = function(_, value) return "!tele " .. value end },
    { label = "List NPCs nearby", valueLabel = "Radius (up to 32)",
      command = function(_, value) return "!listnpcs " .. value end },
    { label = "List locs nearby", valueLabel = "Radius (up to 32)",
      command = function(_, value) return "!listlocs " .. value end },
    { label = "List an inventory", valueLabel = "Inventory name (e.g. inv, bank, worn)",
      command = function(_, value) return "!listinv " .. value end },

    -- currency pouch and archaeology
    { label = "Add to currency pouch", valueLabel = "currency_id count ignore_overflow (e.g. 1 1000 1)",
      command = function(_, value) return "!pouchadd " .. value end },
    { label = "Remove from currency pouch", valueLabel = "currency_id count (e.g. 1 1000)",
      command = function(_, value) return "!pouchdel " .. value end },
    { label = "Give archaeology materials", valueLabel = "count inventory (e.g. 100 inv)",
      command = function(_, value) return "!archgivemats " .. value end },
}

----------------------------------------------------------------
-- LAYOUT
----------------------------------------------------------------
local LIST_HEIGHT    = 12 * 22          -- twelve rows
local PAGE_SIZE      = 40           -- results shown at a time (PrettyUI can only hold about 4,000 rows in all)
local MAX_TEXT       = 120
local DROPDOWN_WIDTH = 380
local FILTER_WIDTH   = 430
local VALUE_WIDTH    = 520

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}               -- list, search, countText, valueField, preview, statusText
local cheatIndex = 1
local selected = nil              -- target picked in the list
local typedSearch = ""
local listScroll = {}
local pageIndex = 1               -- which page of the results is showing

local updateToggle                -- defined further down (the pick handlers call it)
local function cheat() return CHEATS[cheatIndex] end
local function hasTarget() return cheat().search ~= nil or cheat().choices ~= nil end
local function status(text) UI.setText(controls.statusText, text) end

----------------------------------------------------------------
-- THE COMMAND
----------------------------------------------------------------
-- The command for the current pick and `value`, or nil with the reason it can't be built yet
local function buildCommand(value)
    local c = cheat()
    if hasTarget() and not c.targetOptional and not selected then return nil, "Pick something from the list" end

    value = tostring(value or UI.fieldText(controls.valueField))
    if c.noValue then value = "" end
    if value == "" and not c.optional and not c.noValue then return nil, "Type a value" end
    return c.command(selected, value)
end

local function updatePreview()
    local command, reason = buildCommand()
    UI.setText(controls.preview, command and ("Command:  " .. command) or ("Command:  (" .. reason .. ")"))
end

local function apply(value)
    local command, reason = buildCommand(value)
    if not command then return status(reason) end
    if type(ExecuteConsoleCommand) ~= "function" then return status("Can't run cheats here (development server only)") end

    local ok, err = pcall(ExecuteConsoleCommand, command)
    status(ok and ("Sent: " .. command) or ("Failed: " .. tostring(err)))
end

----------------------------------------------------------------
-- RESULTS
----------------------------------------------------------------
local function varValue(name)
    local cfg = Configs.fetch(cheat().search, name)
    local ok, value = pcall(function() return cfg.value end)
    return (ok and value ~= nil) and tostring(value) or "?"
end

-- The names to choose from: configs of the cheat's type, a fixed list, or nothing
local function candidates()
    local filter = UI.fieldText(controls.search)
    if cheat().search then
        local hits = Configs.search(cheat().search, filter, math.huge)
        local names = {}
        for i, hit in ipairs(hits) do names[i] = hit.name end
        return names
    end
    if cheat().choices then
        local terms, names = {}, {}
        for word in filter:lower():gmatch("%S+") do terms[#terms + 1] = word end
        for _, name in ipairs(cheat().choices) do
            local ok = true
            for _, term in ipairs(terms) do
                if not name:find(term, 1, true) then ok = false; break end
            end
            if ok then names[#names + 1] = name end
        end
        return names
    end
    return {}
end

local function countLine(shown, total)
    if not hasTarget() then return "This cheat has no target - just type its value" end
    if cheat().search then
        local scanning, nextId, found = Configs.scanning(cheat().search)
        if scanning then return "Searching... id " .. nextId .. ", " .. found .. " found" end
        if Configs.count(cheat().search) == 0 then return "None listed yet - type an exact name or press Search all" end
    end
    if shown == 0 then return "Showing 0 of " .. total .. " results" end
    local first = (pageIndex - 1) * PAGE_SIZE + 1
    return "Showing " .. first .. "-" .. (first + shown - 1) .. " of " .. total .. " results"
end

local function refreshResults()
    if not controls.list then return end

    local all = candidates()
    local names
    local pages
    names, pageIndex, pages = UI.page(all, pageIndex, PAGE_SIZE)
    UI.setDisabled(controls.prevButton, pageIndex <= 1)
    UI.setDisabled(controls.nextButton, pageIndex >= (pages or 1))

    local isVar = cheat().search and Configs.get(cheat().search).vars
    local entries = {}
    for _, name in ipairs(names) do
        local label = name
        if isVar and #all <= 300 then label = label .. "  =  " .. varValue(name) end
        entries[#entries + 1] = { id = name, label = label, selected = name == selected }
    end
    controls.list:SetEntries(entries)
    UI.setText(controls.countText, countLine(#names, #all))
end

----------------------------------------------------------------
-- BUTTONS AND DROPDOWNS
----------------------------------------------------------------
-- What the Target part of the tab is for, for the cheat that is chosen. The box and button can't be hidden, so they are
-- greyed out when the cheat has no use for them.
local function targetHelp()
    local c = cheat()
    if c.choices then return "Target - pick one from the list below" end
    if not c.search then return "No target needed - ignore the list, just type the value below" end

    local kind = c.search == "Obj" and "an item" or "a var"
    local text = "Target - pick " .. kind .. " from the list below (type to filter)."
    if c.targetOptional then text = "Target (optional) - pick " .. kind .. " to limit it to that, or leave it empty." end
    return text .. " If it isn't listed, press Search all."
end

local function updateTargetUi()
    UI.setText(controls.targetLabel, targetHelp())
    local usesSearch = cheat().search ~= nil
    UI.setDisabled(controls.searchButton, not usesSearch)
    UI.setDisabled(controls.search, not hasTarget())
end

local function onCheatChosen(_, chosenId)
    if not CHEATS[chosenId] then return end
    cheatIndex = chosenId
    -- Give item starts with an amount of 1; every other cheat starts with an empty value
    local startValue = cheat().label == "Give item" and "1" or ""
    if controls.valueField then pcall(function() controls.valueField:SetText(startValue, false) end) end
    if startValue ~= "" then Settings.set("cheatValue", 1) else Settings.clear("cheatValue") end
    Settings.set("cheatIndex", chosenId)
    selected = nil
    pageIndex = 1
    refreshResults()
    updatePreview()
    updateTargetUi()
    updateToggle()
    UI.setText(controls.valueLabel, cheat().noValue and "No value needed for this cheat" or ("Value - " .. (cheat().valueLabel or "")))
    status("")
end

local function onPick(_, name, isSelected)
    if not isSelected then return end
    selected = name
    updatePreview()
    updateToggle()
    status("")
end

local function onSearchClicked()
    if not cheat().search then return status("Nothing to search for") end
    status(Configs.startScan(cheat().search) and "Searching every id - this takes a few seconds" or "Already searching")
    refreshResults()
end

-- The toggle button: for a var, says what the next click will do (the var is on when it is anything but 0)
local function currentValue()
    if not cheat().quick or not selected then return nil end
    return tonumber(varValue(selected))
end

function updateToggle()
    local button = controls.toggle
    if not cheat().quick then
        UI.setButton(button, "Toggle (vars only)", "neutral")
        return pcall(function() button:SetDisabled(true) end)
    end
    pcall(function() button:SetDisabled(false) end)

    local value = currentValue()
    if value == nil then
        UI.setButton(button, "Pick a var to toggle", "neutral")
    elseif value ~= 0 then
        UI.setButton(button, "Turn off (set to 0)", "negative")
    else
        UI.setButton(button, "Turn on (set to 1)", "positive")
    end
end

local function onToggleClicked()
    local value = currentValue()
    if value == nil then return status("Pick a var first") end
    apply(value ~= 0 and 0 or 1)
    updateToggle()
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function CheatsTab.build(page)
    local savedIndex = Settings.get("cheatIndex", cheatIndex)
    if CHEATS[savedIndex] then cheatIndex = savedIndex end
    page:AddText({ text = "1. Choose a cheat   2. Pick its target (if it has one)   3. Type its value   4. Apply" })

    page:AddText({ text = "Cheat" })
    page:AddComboBox({
        entries = UI.dropdownEntries(CHEATS), selectedID = cheatIndex, onChange = onCheatChosen, width = DROPDOWN_WIDTH,
    })

    controls.targetLabel = page:AddText({ text = "" })
    controls.search = page:AddTextField({
        placeholder = "Filter by name, or type an id", maxLength = MAX_TEXT, width = FILTER_WIDTH,
        onChange = function() pageIndex = 1; refreshResults() end,
    })
    controls.searchButton = page:AddSimpleButton("Search all", onSearchClicked, {
        tooltip = "Only needed when the item or var you want isn't in the list: asks the game for every id of the type",
    })

    controls.list = page:AddList({ maxSelected = 1, entries = {}, onChange = onPick, height = LIST_HEIGHT })
    controls.prevButton = page:AddSimpleButton("Prev", function() pageIndex = pageIndex - 1; refreshResults() end, { width = 80 })
    controls.nextButton = page:AddSimpleButton("Next", function() pageIndex = pageIndex + 1; refreshResults() end, { inline = true, width = 80 })
    controls.countText = page:AddText({ text = "" })

    page:AddDivider(UI.TIGHT_DIVIDER)
    controls.valueLabel = page:AddText({ text = "Value - " .. (cheat().valueLabel or "") })
    controls.valueField = page:AddTextField({
        placeholder = "Value", maxLength = MAX_TEXT, width = VALUE_WIDTH,
        onChange = function(field)
            updatePreview()
            local number = tonumber(UI.fieldText(field))
            if number and number == math.floor(number) then Settings.set("cheatValue", number) end
        end,
        onSubmit = function() apply() end,
    })
    page:AddSimpleButton("Clear", function()
        if controls.valueField then pcall(function() controls.valueField:SetText("", false) end) end
        Settings.clear("cheatValue")
        updatePreview()
    end, { width = 70, inline = true, columnGap = 10, tooltip = "Empties the value box" })
    controls.preview = page:AddText({ text = "" })

    page:AddFancyButton("Apply", function() apply() end, { variant = "positive" })
    controls.toggle = page:AddFancyButton("Toggle (vars only)", onToggleClicked, { variant = "neutral", inline = true })
    controls.statusText = page:AddText({ text = "" })

    local savedValue = Settings.get("cheatValue", nil)
    if not savedValue and cheat().label == "Give item" then savedValue = 1 end
    if savedValue then pcall(function() controls.valueField:SetText(tostring(savedValue), false) end) end
    pcall(function() controls.search:SetText(typedSearch, false) end)

    refreshResults()
    if listScroll.list then pcall(function() controls.list:SetScrollPosition(listScroll.list) end) end
    updatePreview()
    updateTargetUi()
    updateToggle()
end

function CheatsTab.reset()
    cheatIndex, selected, pageIndex = 1, nil, 1
end

function CheatsTab.release()
    -- tab gets rebuilt every time its shown so typed text has to live here
    if controls.search then typedSearch = UI.fieldText(controls.search) end
    if controls.list then listScroll.list = controls.list.scrollY end
    controls = {}
end

-- the toggle follows the var as the game changes it
function CheatsTab.onVarChanged(name)
    if controls.toggle and selected == name then updateToggle() end
end

function CheatsTab.onScanProgress(key)
    if controls.list and key == cheat().search then
        if Configs.scanning(key) then
            UI.setText(controls.countText, countLine(0, 0))
        else
            refreshResults()
            status("Search finished")
        end
    end
end

return CheatsTab