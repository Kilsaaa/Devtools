--[[
    devtools.lua - the Dev Tools window.

    The plugin's ribbon page holds one button, "Open Dev Tools". It opens a movable window with a tab per tool:
      Configs - browse the game's configs (configstab.lua)
      Events  - toggle listeners that print game events to the console (eventstab.lua)
      Interface - look inside an interface and hide / show its components (interfacetab.lua)
      Cheats  - build and run developer cheats that need a target or a value (cheatstab.lua)
      Quick Cheats - one-click cheats such as godmode and bank (quicktab.lua)
      Overlays - toggles that show ids over NPCs and in hover text (overlaystab.lua)
    To add a tool, write a module with build(page) / release() / onScanProgress(key) / onVarChanged(name) and add it to TABS.
]]

local Configs = require("data/configs")
local VarIndex = require("data/varindex")
local ConfigsTab = require("tabs/configstab")
local CheatsTab = require("tabs/cheatstab")
local QuickTab = require("tabs/quicktab")
local EventsTab = require("tabs/eventstab")
local OverlaysTab = require("tabs/overlaystab")
local InterfaceTab = require("tabs/interface/interfacetab")
local SpritesTab = require("tabs/spritestab")
local Layers = require("core/layers")
local Settings = require("core/settings")
local UI = require("core/uiutil")

local DevTools = {}

----------------------------------------------------------------
-- LAYOUT
----------------------------------------------------------------
local WINDOW_TITLE  = "Dev Tools"
local WINDOW_WIDTH  = 980
local WINDOW_HEIGHT = 910
local TAB_HEIGHT    = WINDOW_HEIGHT - 70    -- the tab area inside the window

local TABS = {
    { text = "Configs", tool = ConfigsTab },
    { text = "Events", tool = EventsTab },
    { text = "Interface", tool = InterfaceTab },
    { text = "Overlays", tool = OverlaysTab },
    { text = "Sprites", tool = SpritesTab },
    { text = "Cheats",  tool = CheatsTab },
    { text = "Quick Cheats", tool = QuickTab },
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local ribbonView = nil            -- the page shown when the ribbon icon is selected
local ribbonParent = nil          -- that page's component (the fallback parent for the window)
local activeTab = nil             -- the tab last seen showing
local statusText = nil            -- the line on the ribbon page
local rebuildWindow = false   -- set when the layer changed: the window is rebuilt on the next update
local tabsRef = nil
local pendingTab = nil
local startTab = 1            -- the tab to open on when the window is built

local skipTab = 0             -- the tab switched off by the crash guard (see checkMarkers)
local buildTab

local function note(text)
    if type(log) == "function" then pcall(log, "[DevTools] " .. text) end
end

local window = nil            -- the movable tools window

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local function windowParent()
    local parent = Layers.parent()
    if parent then return parent end
    return ribbonParent
end

-- CRASH GUARD
-- Before each tab is built a marker is saved to the PersistentDB, and it is cleared when the tab is done. If the client
-- crashes while a tab is being built the marker is still there the next time the window is opened, so that tab is
-- replaced by a note from then on ("Reset to defaults" in the ribbon turns it back on).
local function checkMarkers()
    local building = Settings.get("building", 0)
    if building > 0 then
        Settings.set("skipTab", building)
        Settings.set("building", 0)
        note("the client crashed while tab " .. building .. " was being built, so that tab is now switched off")
    end
    skipTab = Settings.get("skipTab", 0)
end

----------------------------------------------------------------
-- REMEMBERING WHERE THE WINDOW IS
-- On shutdown the window's top-left corner is saved as a distance from the centre of the layer it is drawn on (stored with 32768
-- added, because the saved numbers are whole and may not be negative). The next time the window is opened it goes back there.
----------------------------------------------------------------
local POSITION_OFFSET = 32768
local membersLogged = false

local function membersOf(value)
    local list = {}
    local function collect(source) if type(source) == "table" then for key in pairs(source) do list[#list + 1] = tostring(key) end end end
    pcall(collect, value)
    pcall(function() local meta = getmetatable(value); if meta then collect(meta); collect(meta.__index) end end)
    table.sort(list)
    return table.concat(list, ",")
end

-- the window's top-left corner on the screen, or nil (several likely places are tried)
local function windowCorner()
    if not window then return nil end
    local candidates = { window }
    for _, name in ipairs({ "component", "root", "frame", "layer", "native", "window", "container", "background" }) do
        local inner = UI.try(window, name)
        if inner then candidates[#candidates + 1] = inner end
    end
    for _, candidate in ipairs(candidates) do
        local global = UI.try(candidate, "xyGlobal")
        local x, y = global and UI.try(global, "x"), global and UI.try(global, "y")
        if type(x) == "number" and type(y) == "number" then return x, y end
    end
    if not membersLogged then
        membersLogged = true
        note("couldn't read the window's position; its members are: " .. membersOf(window))
    end
    return nil
end

local function savePosition()
    local parent = windowParent()
    local x, y = windowCorner()
    if not (parent and x) then return end
    local parentGlobal = UI.try(parent, "xyGlobal")
    local parentX, parentY = parentGlobal and UI.try(parentGlobal, "x") or 0, parentGlobal and UI.try(parentGlobal, "y") or 0
    local width, height = UI.try(parent, "width"), UI.try(parent, "height")
    if type(width) ~= "number" or type(height) ~= "number" then return end
    Settings.set("winRX", math.floor(x - parentX - width / 2) + POSITION_OFFSET)
    Settings.set("winRY", math.floor(y - parentY - height / 2) + POSITION_OFFSET)
    local root = UI.try(window, "root")
    local windowWidth, windowHeight = root and UI.try(root, "width"), root and UI.try(root, "height")
    if type(windowWidth) == "number" and type(windowHeight) == "number" then
        Settings.set("winWidth", windowWidth)
        Settings.set("winHeight", windowHeight)
    end
end

-- where the window should open: the saved spot (kept on the screen), or centred
local function startPosition(parent)
    local x, y = -math.floor(WINDOW_WIDTH / 2), -math.floor(WINDOW_HEIGHT / 2)
    local savedX, savedY = Settings.get("winRX", nil), Settings.get("winRY", nil)
    if savedX and savedY then
        x, y = savedX - POSITION_OFFSET, savedY - POSITION_OFFSET
        local width, height = UI.try(parent, "width"), UI.try(parent, "height")
        if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
            x = math.max(-math.floor(width / 2), math.min(x, math.floor(width / 2) - 120))
            y = math.max(-math.floor(height / 2), math.min(y, math.floor(height / 2) - 60))
        end
    end
    return x, y
end

----------------------------------------------------------------
-- NOTICING THAT THE WINDOW WAS CLOSED
-- The window is hidden when closed, not destroyed, so it is looked at on every update. When it goes from showing to hidden the key
-- events on the Events tab are switched off (see EventsTab.stopKeyEvents).
----------------------------------------------------------------
local wasShown = false
local visibilityLogged = false

-- true if the window is showing, false if it is hidden, nil if that can't be read (several likely places are tried)
local function windowShown()
    if not window then return nil end
    local candidates = { window }
    for _, name in ipairs({ "component", "root", "frame", "layer", "native", "window", "container", "background" }) do
        local inner = UI.try(window, name)
        if inner then candidates[#candidates + 1] = inner end
    end
    local ok, value = pcall(function() return window:IsVisible() end)
    if ok and type(value) == "boolean" then return value end
    for _, candidate in ipairs(candidates) do
        for _, field in ipairs({ "visibleGlobal", "visible", "isVisible" }) do
            local state = UI.try(candidate, field)
            if type(state) == "boolean" then return state end
        end
        local hidden = UI.try(candidate, "hidden")
        if type(hidden) == "boolean" then return not hidden end
    end
    if not visibilityLogged then
        visibilityLogged = true
        note("couldn't tell whether the window is showing, so closing it won't switch the key events off; its members are: " .. membersOf(window))
    end
    return nil
end

local destroyWindow

local function watchWindowClosed()
    local shown = windowShown()
    if shown == nil then return end
    if wasShown and not shown then
        pcall(EventsTab.stopKeyEvents)
        -- closing destroys the window so save position and tab first
        pcall(savePosition)
        startTab = activeTab or startTab
        destroyWindow()
        return
    end
    wasShown = shown
end

local tabView = nil
local tabScroll = {}

local function destroyTabView(index)
    if not tabView then return end
    local tool = TABS[index] and TABS[index].tool
    if tool and tool.onHide then pcall(tool.onHide) end
    if tool and type(tool.release) == "function" then pcall(tool.release) end
    tabScroll[index] = tabView.scrollY
    pcall(function() tabView:Destroy() end)
    tabView = nil
end

buildTab = function(index)
    local tab = TABS[index]
    if not (tab and tabsRef) then return end
    -- each tab gets its own view so leaving it can destroy everything and free the ids for other plugins
    tabView = prettyui.SimpleView.new(tabsRef:GetPage(index).content, { width = 0, height = 0, widthAnchor = 1.0, heightAnchor = 1.0 })
    if index == skipTab then
        tabView:AddText({ text = "This tab crashed the client when it was built last time, so it is switched off." })
        tabView:AddText({ text = "Use 'Reset to defaults' on the Dev Tools ribbon page to switch it back on." })
        return
    end
    Settings.set("building", index)
    tab.tool.build(tabView)
    Settings.set("building", 0)
    if tabScroll[index] then tabView:SetScrollPosition(tabScroll[index]) end
end

local function buildWindow()
    local parent = windowParent()
    if not parent then return end
    checkMarkers()

    -- where it was when the plugin last shut down (centred the first time)
    local startX, startY = startPosition(parent)
    window = prettyui.Window.new(parent, {
        title = WINDOW_TITLE, width = Settings.get("winWidth", WINDOW_WIDTH), height = Settings.get("winHeight", WINDOW_HEIGHT),
        xAnchor = 0.5, yAnchor = 0.5,
        x = startX, y = startY,
        resizable = true, minWidth = 520, minHeight = 400,
        destroyOnClose = false,
        onClose = function() pcall(EventsTab.stopKeyEvents) end,   -- (used if the window offers a close callback)
    })
    wasShown = false

    local tabEntries = {}
    for i, tab in ipairs(TABS) do tabEntries[i] = { text = tab.text } end
    local tabs = window:AddTabs(tabEntries, {
        height = TAB_HEIGHT, activeIndex = startTab, scrollable = false,
        -- waits for next update, destroying and building tabs inside a click can crash the client
        onChange = function(_, index) pendingTab = index end,
    })
    tabsRef = tabs
    buildTab(startTab)
    activeTab = startTab
    if TABS[startTab] and TABS[startTab].tool.onShow then pcall(TABS[startTab].tool.onShow) end

    window:Show()   -- shows and raises it above everything else on its layer
end

-- Keeps track of which tab is showing: only that tab is built
function DevTools.onTabChanged(index)
    if type(index) ~= "number" or index == activeTab then return end
    destroyTabView(activeTab)
    activeTab = index
    pcall(buildTab, index)
    if TABS[index] and TABS[index].tool.onShow then pcall(TABS[index].tool.onShow) end
end

destroyWindow = function()
    destroyTabView(activeTab)
    if window then pcall(function() window:Destroy() end) end
    window, tabsRef, activeTab, pendingTab, wasShown = nil, nil, nil, nil, false
    -- (a tab file from an older copy may not have a release function: that must not stop the window from closing)
    for _, tab in ipairs(TABS) do
        if type(tab.tool.release) == "function" then pcall(tab.tool.release) end
    end
end

function DevTools.open()
    if window then
        pcall(function() window:Show() end)
        pcall(function() window:MoveToFront() end)
        return
    end
    if not pcall(buildWindow) then destroyWindow() end
end

----------------------------------------------------------------
-- RESET TO DEFAULTS
-- Forgets everything saved (drawing layer, display mode, quick cheat toggles, cheat settings, a tab switched off by the
-- crash guard). If the window is open it is drawn again.
----------------------------------------------------------------
function DevTools.resetDefaults()
    Settings.reset()
    Layers.reset()
    ConfigsTab.reset()
    CheatsTab.reset()
    QuickTab.reset()
    startTab = 1
    if window then rebuildWindow = true end
    UI.setText(statusText, "Settings reset to the defaults")
end

----------------------------------------------------------------
-- RIBBON PAGE
----------------------------------------------------------------
local function destroyRibbon()
    if ribbonView then pcall(function() ribbonView:Destroy() end) end
    ribbonView, ribbonParent = nil, nil
end

local function onRibbonOpened(event)
    destroyRibbon()
    ribbonParent = event.component
    ribbonView = prettyui.SimpleView.new(ribbonParent, { width = ribbonParent.width, height = ribbonParent.height })
    ribbonView:AddTitle("Dev Tools")
    ribbonView:AddText({ text = "Browse the game's configs and run developer cheats." })
    ribbonView:AddFancyButton("Open Dev Tools", DevTools.open, { variant = "positive" })
    ribbonView:AddFancyButton("Reset to defaults", DevTools.resetDefaults, {
        variant = "neutral", tooltip = "Forget the saved layer, quick cheat toggles and cheat settings",
    })
    statusText = ribbonView:AddText({ text = "" })
end

----------------------------------------------------------------
-- START / STOP
----------------------------------------------------------------
function DevTools.init()
    ConfigsTab.loadSettings()

    VarIndex.onChange = function(name)
        if window then for _, tab in ipairs(TABS) do pcall(tab.tool.onVarChanged, name) end end
    end
    Configs.onProgress = function(key)
        if window then for _, tab in ipairs(TABS) do pcall(tab.tool.onScanProgress, key) end end
    end

    Configs.start()
    pcall(OverlaysTab.start)
    pcall(InterfaceTab.start)
    -- (choosing another layer in the Overlays tab does not rebuild the window: destroying and recreating it from inside
    -- that dropdown moved it back to the centre and crashed the client. It uses the chosen layer the next time it is opened.)
    Layers.onChange = nil
    Event.Logic.Subscribe("devtools_window", function()
        if pendingTab then
            local index = pendingTab
            pendingTab = nil
            DevTools.onTabChanged(index)
        end
        pcall(watchWindowClosed)
        pcall(EventsTab.tick)
        pcall(InterfaceTab.tick)
        if rebuildWindow then   -- the layer was changed: draw the window again on the new layer
            rebuildWindow = false
            if window then
                destroyWindow()
                if not pcall(buildWindow) then destroyWindow() end
            end
        end
    end)
    Event.ContentLayerReady.Subscribe("devtools_ribbon", onRibbonOpened)
end

function DevTools.shutdown()
    -- the window's position is saved first, while the window still exists
    pcall(savePosition)
    pcall(EventsTab.shutdown)
    pcall(OverlaysTab.shutdown)
    pcall(InterfaceTab.shutdown)
    pcall(SpritesTab.shutdown)
    pcall(Configs.stop)
    pcall(function()
        Event.Logic.Unsubscribe("devtools_window")
        Event.ContentLayerReady.Unsubscribe("devtools_ribbon")
    end)
    destroyWindow()
    destroyRibbon()
end

return DevTools
