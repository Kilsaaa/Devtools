--[[
    quicktab.lua - the "Quick Cheats" tab: one button per cheat that needs nothing typed (godmode, bank ...).

    Plain buttons run their cheat when clicked. Toggle buttons switch something on and off and always say what the
    next click will do ("Turn on god mode" / "Turn off god mode"). The game can't be asked whether it is on, so a
    toggle's state is remembered by this tab: everything starts as off each time the plugin loads.
    The risky cheats (clearing your backpack, resetting the account ...) need a second click to confirm.
    Cheats only work on a development server.

    To add a button, add an entry to GROUPS below.
]]

local UI = require("core/uiutil")
local Settings = require("core/settings")

local QuickTab = {}

----------------------------------------------------------------
-- THE BUTTONS (from https://developer.runescape.com/rs/cheats.html)
----------------------------------------------------------------
-- A plain button:  { text = "...", command = "!...", tip = "what it does", confirm = true }
-- A toggle:        { start = "text while off", stop = "text while on", on = "!command to turn on",
--                    off = "!command to turn off", tip = "...", confirm = true }   (confirm only applies to turning on)
local GROUPS = {
    { title = "Player state and combat", buttons = {
        { start = "Turn on god mode", stop = "Turn off god mode", on = "!godmode", off = "!godmode",
          tip = "Combat invulnerability" },
        { start = "Turn on max HP", stop = "Turn off max HP", on = "!maxhp", off = "!maxhp",
          tip = "Continuously restore health to maximum" },
        { text = "Hit all NPCs", command = "!hitall", tip = "Deal 5000 damage to every NPC within 50 tiles" },
        { text = "Complete everything", command = "!allinone", confirm = true,
          tip = "Complete every quest and task and set all skills to maximum" },
    } },
    { title = "Location", buttons = {
        { text = "Get coordinate",    command = "!getcoord",  tip = "Show your current coordinate" },
        { text = "Save coordinate",   action = "save", tip = "Remember your current coordinate (kept between sessions)" },
        { text = "Teleport to saved", action = "teleport", tip = "Teleport to the coordinate saved with Save coordinate" },
    } },
    { title = "Items and bank", buttons = {
        { text = "Open bank",       command = "!bank",      tip = "Open your bank without a banker or chest" },
        { text = "Clear backpack",  command = "!clearinv",  confirm = true, tip = "DESTROY every item in your backpack" },
        { text = "Clear equipment", command = "!clearworn", confirm = true, tip = "DESTROY every item you are wearing" },
    } },
    { title = "Inspect (prints to the developer console)", buttons = {
        { text = "List NPCs nearby", command = "!listnpcs 32",  tip = "List the NPCs within 32 tiles" },
        { text = "List locs nearby", command = "!listlocs 32",  tip = "List the locs (objects, scenery) within 32 tiles" },
        { text = "List backpack",    command = "!listinv inv",  tip = "List your backpack, including each item's VarObj values" },
        { text = "List equipment",   command = "!listinv worn", tip = "List what you are wearing" },
        { text = "List bank",        command = "!listinv bank", tip = "List your bank" },
    } },
    { title = "Interface", buttons = {
        { start = "Hide interface", stop = "Show interface", on = "!tlihide", off = "!tlishow",
          tip = "Hide all top-level interface windows (for screenshots)" },
    } },
    { title = "Invention and Archaeology", buttons = {
        { text = "Run machines 1 hour", command = "!inventmachinerun", tip = "Advance constructed Invention machines by one simulated hour" },
        { text = "Give all materials",  command = "!inventgivemats",   tip = "Give the maximum storage count of every Invention material" },
        { text = "Wipe all materials",  command = "!inventwipemats",   confirm = true, tip = "REMOVE every Invention material" },
        { text = "Finish archaeology tutorial", command = "!archcompletetutorial", tip = "Complete the Archaeology tutorial and grant its items" },
    } },
    { title = "Account type", buttons = {
        { start = "Turn on ironman", stop = "Turn off ironman", on = "!setironman 1", off = "!setironman 0", tip = "Ironman status" },
        { start = "Turn on hardcore", stop = "Turn off hardcore", on = "!sethardcore 1", off = "!sethardcore 0", tip = "Hardcore status" },
        { start = "Turn on group ironman", stop = "Turn off group ironman", on = "!setgroupironman 1", off = "!setgroupironman 0",
          tip = "Group ironman status" },
        { start = "Reset account on logout", stop = "Cancel account reset", on = "!resetsave", off = "!unresetsave",
          confirm = true, tip = "Flag the account to reset when you next log out" },
    } },
}

local LABEL_WIDTH  = 250         -- same as the Events tab
local BUTTON_WIDTH = 100
local COLUMN_GAP   = 90         -- space between the two columns
local COLUMNS      = 2

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}
local buttons = {}                -- toggle entry -> its fancy button
local isOn = {}                   -- toggle entry -> true while it is switched on
local armed = nil                 -- the command waiting for its second click

local function status(text) UI.setText(controls.statusText, text) end

local function send(command)
    if type(ExecuteConsoleCommand) ~= "function" then
        status("Can't run cheats here (development server only)")
        return false
    end
    local ok, err = pcall(ExecuteConsoleCommand, command)
    status(ok and ("Sent: " .. command) or ("Failed: " .. tostring(err)))
    return ok
end

-- true when the command can go ahead; a risky one first asks for a second click
local showButton   -- defined below (puts a button's text back to what it normally says)
local armedEntry = nil

local function disarm()
    armed = nil
    if armedEntry then showButton(armedEntry) end
    armedEntry = nil
end

local function confirmed(entry, command, tip)
    if armed == command then
        disarm()
        return true
    end
    disarm()
    armed = command
    armedEntry = entry
    pcall(function() UI.setButton(buttons[entry], "Confirm", "negative") end)
    status("Click Confirm to run: " .. command .. "  (" .. tip .. ")")
    return false
end

-- A toggle is a plain (yellow) button that lights up while it is on. Plain buttons can't change their text, so the
-- state is shown by the lit-up look and in the line at the bottom.
local function toggleKey(entry)
    if not entry.number then
        local n = 0
        for _, group in ipairs(GROUPS) do
            for _, e in ipairs(group.buttons) do
                n = n + 1
                if e == entry then entry.number = n end
            end
        end
    end
    return "quick" .. tostring(entry.number)
end

-- the remembered state of a toggle is read once, the first time the tab is built
local loaded = false
local function loadToggles()
    if loaded then return end
    loaded = true
    for _, group in ipairs(GROUPS) do
        for _, entry in ipairs(group.buttons) do
            if entry.start then isOn[entry] = Settings.get(toggleKey(entry), 0) == 1 end
        end
    end
end

function showButton(entry)
    local button = buttons[entry]
    if not button then return end
    if entry.start then
        UI.setButton(button, isOn[entry] and "Turn off" or "Turn on", isOn[entry] and "negative" or "positive")
    else
        UI.setButton(button, "Run", "positive")
    end
end
local showToggle = showButton

local function onToggleClicked(entry)
    local turningOn = not isOn[entry]
    local command = turningOn and entry.on or entry.off
    if turningOn and entry.confirm and not confirmed(entry, command, entry.tip) then return end
    disarm()

    if send(command) then
        isOn[entry] = turningOn
        Settings.set(toggleKey(entry), turningOn and 1 or 0)
        status(entry.label .. ": " .. (turningOn and "ON" or "off") .. "   (" .. command .. ")")
    end
    showToggle(entry)
end

-- The game's own save / teleport debug commands aren't available ("could not find debugproc"), so the coordinate is kept here.
local function playerCoordinate()
    local coord
    pcall(function() coord = PlayerList.Self().coordGrid end)
    local x, z, level = coord and UI.try(coord, "x"), coord and UI.try(coord, "z"), coord and UI.try(coord, "level")
    if type(x) == "number" and type(z) == "number" then return x, z, level or 0 end
    return nil
end

local function coordinateText(x, z, level)   -- the way the game writes it: level,mapSquareX,mapSquareZ,localX,localZ
    return level .. "," .. x // 64 .. "," .. z // 64 .. "," .. x % 64 .. "," .. z % 64
end

local function runAction(entry)
    if entry.action == "save" then
        local x, z, level = playerCoordinate()
        if not x then return status("Couldn't read your coordinate") end
        Settings.set("savedX", x); Settings.set("savedZ", z); Settings.set("savedLevel", level)
        status("Saved " .. coordinateText(x, z, level))
    else
        local x, z, level = Settings.get("savedX", nil), Settings.get("savedZ", nil), Settings.get("savedLevel", 0)
        if not x or not z then return status("No coordinate saved yet: use Save coordinate first") end
        send("!tele " .. coordinateText(x, z, level))
    end
end

local function onButtonClicked(entry)
    if entry.action then return runAction(entry) end
    if entry.confirm and not confirmed(entry, entry.command, entry.tip) then return end
    disarm()
    send(entry.command)
    showButton(entry)
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function QuickTab.build(page)
    page:AddText({ text = "One click runs the cheat. Cheats marked * ask you to click Confirm. Toggles say what the next click does." })

    loadToggles()
    buttons = {}
    for _, group in ipairs(GROUPS) do
        page:AddDivider(UI.TIGHT_DIVIDER)
        UI.heading(page, group.title)

        -- like the Events tab: a label, then its button, two to a line
        for i, entry in ipairs(group.buttons) do
            local column = (i - 1) % COLUMNS
            local last = column == COLUMNS - 1 or i == #group.buttons
            local label
            if entry.start then
                entry.label = entry.label or (entry.start:gsub("^Turn on ", ""):gsub("^%l", string.upper))
                label = entry.label
            else
                label = entry.text
            end
            if entry.confirm then label = label .. " *" end

            page:AddText({ text = label .. ":", width = LABEL_WIDTH, columnGap = 0, inline = column > 0, tooltip = entry.tip })
            local onClick = entry.start and function() onToggleClicked(entry) end or function() onButtonClicked(entry) end
            buttons[entry] = page:AddFancyButton("Run", onClick, {
                variant = "positive", width = BUTTON_WIDTH, inline = true, columnGap = last and 0 or COLUMN_GAP, tooltip = entry.tip,
            })
            showButton(entry)
        end
    end

    page:AddDivider(UI.TIGHT_DIVIDER)
    controls.statusText = page:AddText({ text = "" })
end

function QuickTab.reset()
    isOn = {}
    loaded = true
    for entry in pairs(buttons) do showButton(entry) end
end

function QuickTab.release() controls, buttons, armed, armedEntry = {}, {}, nil, nil end
function QuickTab.onVarChanged() end
function QuickTab.onScanProgress() end

return QuickTab