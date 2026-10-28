--[[
    spritestab.lua - the "Sprites" tab: search every sprite in the game by name, tag or alias.

    This is the rsprite sprite finder (https://github.com/sereselene/rsprite, PolyForm Strict 1.0.0 - see LICENSE-rsprite.txt before sharing this plugin) built into Dev Tools: the
    library is in the rsprite folder and the finder's window is in the finder folder (both with their requires pointed
    at those folders). The finder draws into a panel on this tab instead of opening a window of its own.

    The sprite names are read the first time the tab is shown (it takes a moment), and nothing is drawn until then.
    Sprites that crashed the client are remembered and hidden: "Show hidden sprites again" brings them back.
]]

local FinderWindow = require("finder/src/features/finder/finder_window")
local FinderOptions = require("finder/src/features/finder/finder_options")
local RSprite = require("rsprite/src/app/init")
local UI = require("core/uiutil")

local SpritesTab = {}

local controls = {}
local built = false
local started = false
local hostPanel = nil
local contentParent = nil   -- the panel's drawing layer; the finder lives in a holder layer made inside it each time the tab is shown

-- the panel's frame is made of edge and corner pieces. Hiding them removes the border, but they belong to the Dev Tools
-- window too, so they are only hidden while the Sprites tab is showing and put back as soon as another tab is picked.
local FRAME_LAYERS = { "dock", "overlay" }
local FRAME_PIECES = { "top", "bottom", "left", "right", "topLeft", "topRight", "bottomLeft", "bottomRight" }

local function setFrameHidden(hidden)
    if not hostPanel then return end
    for _, layer in ipairs(FRAME_LAYERS) do
        for _, piece in ipairs(FRAME_PIECES) do
            pcall(function() hostPanel[layer][piece].hidden = hidden end)
        end
    end
end

local function note(text)
    pcall(print, "[DevTools sprites] " .. text)
end

local function status(text) UI.setText(controls.statusText, text) end

local function start()
    if started then return end
    started = true
    -- the finder draws into a layer of its own, which is destroyed when the tab is left (freeing its layers for the other tabs)
    local holder
    pcall(function()
        holder = ui.Layer.new(contentParent)
        holder:SetPos(0, 0)
        holder:SetSize(FinderWindow.WIDTH, FinderWindow.CONTENT_HEIGHT)
        holder.clickthrough = true
    end)
    if not holder then
        status("The sprite finder couldn't make its drawing layer.")
        started = false
        return
    end
    FinderWindow.SetContent(holder, function() pcall(function() holder:Destroy() end) end)
    note("step 1: building the finder")
    local ok, err = pcall(FinderWindow.Prepare)
    if not ok then note("building the finder failed: " .. tostring(err)); status("Building the finder failed (see the console)."); started = false; return end
    built = true
    status("")
    note("step 2: opening (reads the sprite names)")
    local ok2, err2 = pcall(FinderWindow.Open)
    if not ok2 then note("opening the finder failed: " .. tostring(err2)) end
    note("step 3: done")
end

function SpritesTab.build(page)
    controls = {}
    built, started = false, false
    local host
    pcall(function() host = page:AddPanel({ width = FinderWindow.WIDTH, height = FinderWindow.CONTENT_HEIGHT }) end)
    if not host then
        page:AddText({ text = "The sprite finder needs a panel to draw into, and this version of PrettyUI couldn't make one." })
        return
    end
    pcall(function() host:SetScrollable(false) end)
    hostPanel = host
    local content
    for _, name in ipairs({ "root", "content", "container" }) do
        if not content then
            local ok, value = pcall(function() return host[name] end)
            if ok and value then content = value end
        end
    end
    if not content then
        page:AddText({ text = "The sprite finder couldn't find where to draw." })
        return
    end

    contentParent = content
    -- nothing is built or read until the tab is shown
    built = false

    -- under the finder: its two options, and a way to bring back sprites that were hidden after a crash
    local options = FinderOptions.Current()
    local choices = {}
    for position, choice in ipairs(FinderOptions.CHOICES) do
        choices[position] = { text = choice.text, value = choice.value, selected = options[choice.value] == true }
    end
    pcall(function()
        page:AddCheckboxButton(choices, {
            onChange = function(_, _, changedValue, selected)
                if FinderOptions.Set(changedValue, selected) and built then pcall(FinderWindow.OptionsChanged) end
            end,
        })
    end)
    controls.statusText = page:AddText({ text = "" })
end

-- the tab is showing: read the names (the first time), search and draw
function SpritesTab.onShow()
    setFrameHidden(true)
    start()
end

-- take the finder down: it saves its state, then its layer (and everything drawn in it) is destroyed
local function teardown()
    if started then pcall(FinderWindow.Destroy) end
    built, started = false, false
end

-- the tab is no longer showing: forget what was being drawn (so the crash guard stops waiting)
function SpritesTab.onHide()
    setFrameHidden(false)
    teardown()
end

function SpritesTab.onScanProgress() end
function SpritesTab.onVarChanged() end

function SpritesTab.release()
    setFrameHidden(false)
    teardown()
    controls, contentParent, hostPanel = {}, nil, nil
end

function SpritesTab.reset() end

function SpritesTab.shutdown()
    setFrameHidden(false)
    pcall(FinderWindow.Destroy)
    pcall(RSprite.Shutdown)
end

return SpritesTab