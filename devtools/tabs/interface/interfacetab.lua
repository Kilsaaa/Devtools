--[[
    interfacetab.lua - the "Interface" tab: look inside one of the game's interfaces.

    Tree sub-tab: type an interface id and press Load. The left list shows every static component of that interface,
    named with the game's asset names and indented under the component that holds it. Pick one and the panel on the
    right lists everything known about it (sprite, text, size, position, item and so on - only what it really has).
    Click a property on the right and its value appears in the box under the panel, ready to type in: the component
    changes as you type. A yes/no property (Hidden and so on) is flipped with the True / False button instead.

    The filter above the list narrows it to components that contain the text you type.
    Under the panels: the sprite of the picked component, "Revert all changes", and one line describing the component
    (to select and copy).

    Lookup sub-tab: find a component by its name (see lookuptab.lua).

    Notes
      - Hide only affects what this plugin hides: it can't force something the game hides to appear.
      - "Revert all changes" unhides everything hidden here and puts back every value edited here. Turning the plugin
        off does the same. "Revert" next to Apply puts back just the chosen value.
      - The interface has to be loaded (visible in the game right now) to be inspected.
      - Interface components can't be listed in one call, so the ids 0 to MAX_STATIC_ID are tried one by one.
]]

local UI = require("core/uiutil")
local LookupTab = require("tabs/interface/lookuptab")
local TreeView = require("widgets/treeview")
local Settings = require("core/settings")
local Layers = require("core/layers")
local Names = require("tabs/interface/componentnames")

local InterfaceTab = {}

----------------------------------------------------------------
-- LAYOUT
----------------------------------------------------------------
local MAX_STATIC_ID  = 2500       -- highest static component id tried
local DYNAMIC_LEVELS = 3          -- how many levels of dynamic components are listed under a static one
local MAX_DYNAMIC_PER_PARENT = 150
local MAX_DYNAMIC_ROWS = 8000     -- most dynamic rows listed for one interface
local MAX_LIST_ROWS  = 400        -- most rows put in the plain list that is used if the drawn tree can't be made
local LIST_WIDTH     = 440
local PANEL_WIDTH    = 440
local LIST_GAP       = 18
local PANEL_HEIGHT   = 360
local INPUT_WIDTH    = 140
local CLEAR_WIDTH    = 70         -- the Clear buttons next to the two filters
local BUTTON_WIDTH   = 60         -- Apply / Revert (fancy buttons are drawn about 22 wider than this)
-- Where the value box (under the right panel) sits. VALUE_X is how far from the left edge of the left panel its left edge is
-- (the right panel starts at LIST_WIDTH + LIST_GAP = 458); VALUE_DOWN is how far it is pushed down from the top of its row.
local VALUE_X        = 456
local VALUE_DOWN     = 21

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}

local interfaceID = nil           -- the interface being looked at
local tree = {}                   -- left list: { key, label, component }
local byKey = {}                  -- key -> entry
local filterText = ""
local spritesOnly = false         -- the "Show Sprites only" checkbox
local expanded = {}               -- key -> true for the tree rows that are open
local selected = nil              -- the entry chosen on the left
local hiddenByUs = {}             -- components this tab has hidden
local chosen = nil                -- the component shown in the details list
local typedLua = ""
local typedInterface = ""
local originals = {}               -- component -> { property key -> its value before this tab changed it }
local editOrder = {}              -- the edited components, in the order they were first edited
local editInfo = {}               -- component -> the Lua that finds it again
local editSetting = false          -- true while the plugin fills the edit box itself (a silent SetText still fires onChange)
local typing = false               -- true while key presses are typed into the value box by the plugin (the game gives plugins no way to focus it)
local TYPING_KEY = "devtools_interface_typing"
local editing = nil               -- the detail row shown in the edit box: { name, value, key }
local detail = {}                 -- its { name, value, key } triples

-- (there is no status line under the boxes any more: messages go to the console)
local function status(text)
    if type(text) == "string" and text ~= "" then pcall(print, "[DevTools interface] " .. text) end
end

-- Every list refill makes new rows in the game, and the game only has about 4000 dynamic components to give out
-- ("invalid dynamic ID ... between 0 and 4096"). So a list is only refilled when its rows really changed.
local signatures = {}
local function fillList(name, list, entries)
    local parts = {}
    for i, e in ipairs(entries) do parts[i] = tostring(e.id) .. "|" .. tostring(e.label) .. "|" .. tostring(e.selected) end
    local signature = table.concat(parts, "\n")
    if signatures[name] == signature then return end
    signatures[name] = signature
    list:SetEntries(entries)
end
local SPRITE_SIZE = 32             -- the picture of the picked component's sprite, under the right panel
local function showSprite(component)
    local picture = controls.sprite
    if not picture then return end
    local spriteID
    if component then
        for _, field in ipairs({ "spriteID", "spriteId" }) do
            local ok, value = pcall(function() return component[field] end)
            if ok and type(value) == "number" and value >= 0 then spriteID = value; break end
        end
    end
    pcall(function() picture:SetSprite(spriteID or -1) end)
end
local treeInterfaceName = nil           -- the name of the interface shown in the tree
local assetName = Names.nameOf    -- the game's name for a static component
local filterWait = nil                -- game ticks until the left filter is applied (typing waits until you pause)
local showEditing                 -- defined with the editing code below

local try = UI.try
local Info = require("tabs/interface/componentinfo")
local idString, tag, summary, searchText, details, lookupCode =
    Info.idString, Info.tag, Info.summary, Info.searchText, Info.details, Info.lookupCode

----------------------------------------------------------------
-- READING AN INTERFACE
----------------------------------------------------------------
-- every static component of the interface, in parent-then-child order, with how deep each one is
local function readInterface(id)
    local loaded = false
    pcall(function() loaded = ui.Interfaces:GetInterface(id) ~= nil end)
    if not loaded then return nil, "Interface " .. id .. " isn't loaded right now" end

    local found, children, roots = {}, {}, {}
    for staticID = 0, MAX_STATIC_ID do
        local ok, component = pcall(function() return ui.Interfaces:GetComponent(id, staticID) end)
        if ok and component then found[staticID] = component end
    end

    for staticID, component in pairs(found) do
        local parent = try(component, "parentStatic")
        local parentID = parent and try(parent, "staticID")
        local sameInterface = parent and (try(parent, "interfaceID") == id or try(parent, "interfaceID") == nil)
        if type(parentID) == "number" and parentID ~= staticID and sameInterface and found[parentID] then
            children[parentID] = children[parentID] or {}
            table.insert(children[parentID], staticID)
        else
            roots[#roots + 1] = staticID
        end
    end
    table.sort(roots)
    for _, list in pairs(children) do table.sort(list) end

    local result, seen = {}, {}
    result.interfaceRoots = {}
    -- dynamic components are listed under the static component that holds them (and the ones inside those, a few levels down). They are
    -- recreated by the game as it updates, so these rows are a picture of what was there when Load was pressed.
    local dynamicBudget = MAX_DYNAMIC_ROWS
    local function addDynamic(component, depth, parentEntry, keyPrefix, levels)
        local list = {}
        pcall(function()
            component:IterateDynamicComponents(function(child) if #list < MAX_DYNAMIC_PER_PARENT then list[#list + 1] = child end end)
        end)
        local added = 0
        for i, child in ipairs(list) do
            if dynamicBudget <= 0 then break end
            dynamicBudget = dynamicBudget - 1
            added = added + 1
            local key = keyPrefix .. ":d" .. i
            local row = {
                key = key, depth = depth, component = child, parent = parentEntry, dynamic = true, root = parentEntry.root,
                name = tag(child) .. "  " .. summary(child), hasChildren = false, search = searchText(child),
                hasSprite = (function()
                    for _, field in ipairs({ "spriteID", "spriteId" }) do
                        local v = try(child, field)
                        if type(v) == "number" then return v >= 0 end
                    end
                    return false
                end)(),
            }
            result[#result + 1] = row
            if levels > 1 and addDynamic(child, depth + 1, row, key, levels - 1) > 0 then row.hasChildren = true end
        end
        return added
    end
    local function walk(staticID, depth, parentEntry, isLast)
        if seen[staticID] or depth > 40 then return end
        seen[staticID] = true
        local component = found[staticID]
        -- what a filter looks at: this component and the static and dynamic components inside it
        local search = { searchText(component) }
        pcall(function()
            component:IterateStaticComponents(function(child) search[#search + 1] = searchText(child) end)
        end)
        pcall(function()
            component:IterateDynamicComponents(function(child) search[#search + 1] = searchText(child) end)
        end)
        local kids = children[staticID] or {}
        local entry = {
            key = tostring(staticID), depth = depth, component = component, parent = parentEntry, last = isLast,
            root = parentEntry and parentEntry.root or nil,
            name = (function() local n = assetName(component); return n and (string.match(n, "__(.*)$") or n) end)()
                or (tag(component) .. "  " .. summary(component)),
            hasChildren = #kids > 0,
            interfaceTop = parentEntry == nil or parentEntry.ancestor == true,
            hasSprite = (function()
                for _, field in ipairs({ "spriteID", "spriteId" }) do
                    local v = try(component, field)
                    if type(v) == "number" then return v >= 0 end
                end
                return false
            end)(),
            search = string.lower(tostring(staticID)) .. " " .. string.lower(assetName(component) or "") .. " " .. table.concat(search, " "),
        }
        entry.root = entry.root or entry
        result[#result + 1] = entry
        if entry.interfaceTop then result.interfaceRoots[#result.interfaceRoots + 1] = entry end
        for i, childID in ipairs(kids) do walk(childID, depth + 1, entry, i == #kids) end
        -- the dynamic components inside it (text, bars, sprites the game adds), shown under the static ones
        if addDynamic(component, depth + 1, entry, entry.key, DYNAMIC_LEVELS) > 0 then entry.hasChildren = true end
    end

    -- The components the interface sits inside (in other interfaces) are shown above it: the chain of parents of each top component,
    -- outermost first. Chains that share a parent share its row.
    local function keyOfComponent(component)
        local owner, number = try(component, "interfaceID"), try(component, "staticID")
        if type(owner) == "number" and type(number) == "number" then return owner .. ":" .. number end
        return nil
    end
    local nodes, tops = {}, {}              -- ancestor key -> node { component, kids = {ancestor nodes}, roots = {static ids} }
    local function nodeFor(component, key)
        local node = nodes[key]
        if not node then node = { key = key, component = component, kids = {}, kidSeen = {}, roots = {} }; nodes[key] = node end
        return node
    end
    local plainRoots = {}
    for _, staticID in ipairs(roots) do
        local chain, chainSeen = {}, {}
        local current = try(found[staticID], "parentStatic")
        while current and #chain < 30 do
            local key = keyOfComponent(current)
            if not key or chainSeen[key] then break end
            chainSeen[key] = true
            table.insert(chain, 1, { key = key, component = current })      -- outermost ends up first
            current = try(current, "parentStatic")
        end
        if #chain == 0 then
            plainRoots[#plainRoots + 1] = staticID
        else
            local above
            for _, link in ipairs(chain) do
                local node = nodeFor(link.component, link.key)
                if above then
                    if not above.kidSeen[link.key] then above.kidSeen[link.key] = true; above.kids[#above.kids + 1] = node end
                elseif not nodes["top:" .. link.key] then
                    nodes["top:" .. link.key] = true
                    tops[#tops + 1] = node
                end
                above = node
            end
            above.roots[#above.roots + 1] = staticID
        end
    end
    -- (the names of components in other interfaces switch the name table, so the loaded interface's names are loaded again afterwards)
    local function walkAncestor(node, depth, parentEntry)
        local component = node.component
        local ownerNumber = try(component, "interfaceID")
        local base = assetName(component)
        local entry = {
            key = node.key, depth = depth, component = component, parent = parentEntry, ancestor = true, ownerInterface = ownerNumber,
            name = (base and (string.match(base, "__(.*)$") or base)) or (tag(component) .. "  " .. summary(component)),
            hasChildren = true, search = "",
            hasSprite = (function()
                for _, field in ipairs({ "spriteID", "spriteId" }) do
                    local v = try(component, field)
                    if type(v) == "number" then return v >= 0 end
                end
                return false
            end)(),
        }
        entry.root = parentEntry and parentEntry.root or entry
        result[#result + 1] = entry
        result.ancestors = result.ancestors or {}
        result.ancestors[#result.ancestors + 1] = entry
        for _, kid in ipairs(node.kids) do walkAncestor(kid, depth + 1, entry) end
        node.entry = entry
    end
    for _, node in ipairs(tops) do walkAncestor(node, 0, nil) end
    -- the interface's own top components go under the innermost parent of each chain, after the parents
    local function walkRoots(node)
        for _, kid in ipairs(node.kids) do walkRoots(kid) end
        for i, staticID in ipairs(node.roots) do walk(staticID, node.entry.depth + 1, node.entry, i == #node.roots) end
    end
    for _, node in ipairs(tops) do walkRoots(node) end
    for i, staticID in ipairs(plainRoots) do walk(staticID, 0, nil, i == #plainRoots) end
    -- put the entries in outline order: each parent row, then what is inside it
    local ordered, placed = {}, {}
    local childrenOf = {}
    for _, entry in ipairs(result) do
        local key = entry.parent or false
        childrenOf[key] = childrenOf[key] or {}
        table.insert(childrenOf[key], entry)
    end
    local function place(entry)
        if placed[entry] then return end
        placed[entry] = true
        ordered[#ordered + 1] = entry
        -- other ancestors first, then the interface's own rows
        for _, child in ipairs(childrenOf[entry] or {}) do if child.ancestor then place(child) end end
        for _, child in ipairs(childrenOf[entry] or {}) do if not child.ancestor then place(child) end end
    end
    for _, entry in ipairs(childrenOf[false] or {}) do place(entry) end
    ordered.interfaceRoots, ordered.ancestors = result.interfaceRoots, result.ancestors
    return ordered
end

----------------------------------------------------------------
-- SHOW SELECTED: an outline that pulses in the game around the picked component
----------------------------------------------------------------
local PULSE_KEY = "devtools_interface_pulse"
local treeSetting = false            -- true while the plugin ticks or unticks the box itself
local showSelected = false            -- the checkbox
local showColour = 0xFFDD00           -- 0xRRGGBB, from the colour picker
local pulseTarget = nil               -- { interface, static } of the picked component (looked up fresh every frame)
local pulseRect, pulseFrame, pulseFailures = nil, 0, 0

local function hidePulse()
    if pulseRect then pcall(function() pulseRect.hidden = true end) end
end

local function destroyPulse()
    if pulseRect then pcall(function() pulseRect:Destroy() end) end
    pulseRect = nil
end

local function drawPulse()
    if not (showSelected and pulseTarget) then return hidePulse() end
    local ok, err = pcall(function()
        local component = ui.Interfaces:GetComponent(pulseTarget[1], pulseTarget[2])
        local parent = Layers.parent()
        if not component or not parent then return hidePulse() end
        if try(component, "hidden") == true or try(component, "visibleGlobal") == false then return hidePulse() end
        local width, height = try(component, "width"), try(component, "height")
        local global, origin = try(component, "xyGlobal"), try(parent, "xyGlobal")
        if not global or not origin or type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
            return hidePulse()
        end
        -- the game's global positions leave out the scrolling of the layers the component sits in
        local x, y, up = global.x, global.y, try(component, "parent")
        for _ = 1, 64 do
            if not up then break end
            x = x - (try(up, "scrollX") or 0)
            y = y - (try(up, "scrollY") or 0)
            up = try(up, "parent")
        end
        if not pulseRect then
            pulseRect = ui.Rectangle.new(parent)
            pulseRect.fill, pulseRect.outlineThickness, pulseRect.clickthrough = false, 3, true
        end
        pulseFrame = pulseFrame + 1
        local fade = 0.5 + 0.5 * math.sin(pulseFrame * 0.05)
        local alpha = math.floor(70 + 185 * fade)
        pulseRect:SetPos(math.floor(x - origin.x), math.floor(y - origin.y))
        pulseRect:SetSize(width, height)
        pulseRect.rgba = showColour * 256 + alpha
        pulseRect.hidden = false
        if pulseFrame % 30 == 1 then pulseRect:MoveToFront() end
    end)
    if ok then pulseFailures = 0 else
        destroyPulse()
        pulseFailures = pulseFailures + 1
        if pulseFailures >= 5 then
            showSelected = false
            pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
            if controls.showCheck then treeSetting = true; pcall(function() controls.showCheck:SetSelected("show", false, true) end); treeSetting = false end
            status("Highlight Selected turned itself off: " .. tostring(err))
        end
    end
end

local function setShowSelected(on)
    showSelected = on == true
    Settings.set("showSelected", showSelected and 1 or 0)
    pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
    pulseFailures = 0
    if showSelected then
        local ok, err = pcall(function() Event.Draw.Subscribe(PULSE_KEY, drawPulse) end)
        if not ok then showSelected = false; status("Couldn't start Highlight Selected: " .. tostring(err)) end
    else
        destroyPulse()
    end
end

-- (the Tree tab's highlight stays on when you change tab or close the window; only unticking the box turns it off)

local function stopPulse()
    pcall(function() Event.Draw.Unsubscribe(PULSE_KEY) end)
    destroyPulse()
    pulseTarget = nil
end

----------------------------------------------------------------
-- THE EDITOR UNDER THE RIGHT PANEL: shown only while a component is picked; and the code for the edits made to it
----------------------------------------------------------------
local function setEditorVisible(visible)
    for _, name in ipairs({ "editLabel", "editField", "editRevert", "revertAll" }) do
        UI.setHidden(controls[name], not visible)
    end
end

-- Lua for every edit made here, on any component of any interface, written the way it would be written by hand:
--   one edit on a component:      ui.Interfaces:GetComponent(id.Component.NAME):SetHeight(150)
--   several edits on a component: do local c = ui.Interfaces:GetComponent(...); c:SetWidth(200); c:SetHeight(20) end
-- A dynamic component is found by its place among the dynamic components of its static one, with the helper `nth` (put at the start
-- when it is needed).
local EDIT_ORDER = { "x", "y", "width", "height", "alpha", "rgba", "content", "font", "sprite", "hidden", "enabled", "clickthrough" }
local NTH_HELPER = "local function nth(parent, index) local count, found = 0, nil; parent:IterateDynamicComponents(function(child) count = count + 1; if count == index then found = child end end); return found end; "

-- how to get at a static component: by its game name when it has one, otherwise by its numbers
local function baseExpression(component)
    local interfaceNumber, staticNumber = try(component, "interfaceID"), try(component, "staticID")
    local okName, name = pcall(assetName, component)
    if okName and name then return "ui.Interfaces:GetComponent(id.Component." .. name .. ")" end
    return "ui.Interfaces:GetComponent(" .. tostring(interfaceNumber) .. ", " .. tostring(staticNumber) .. ")"
end

local function findCode(component, entry)
    local expression = baseExpression(component)
    local usesNth = false
    if entry and entry.key and entry.dynamic then
        for index in tostring(entry.key):gmatch(":d(%d+)") do
            expression = "nth(" .. expression .. ", " .. index .. ")"
            usesNth = true
        end
    end
    return expression, usesNth
end

-- remembers how to find a component the first time it is edited
local function noteEdit(component)
    if editInfo[component] then return end
    local entry = selected and selected.component == component and selected or nil
    local expression, usesNth = findCode(component, entry)
    editInfo[component] = { expr = expression, usesNth = usesNth }
    editOrder[#editOrder + 1] = component
end

-- the end of each edit statement (what follows the component): ":SetX(5)" or ".alpha = 1"
local function editStatements(component, changed)
    local parts = {}
    for _, key in ipairs(EDIT_ORDER) do
        if changed[key] ~= nil then
            if key == "sprite" then
                for _, field in ipairs({ "spriteID", "spriteId" }) do
                    local v = try(component, field)
                    if type(v) == "number" then parts[#parts + 1] = "." .. field .. " = " .. tostring(v); break end
                end
            elseif key == "x" or key == "y" or key == "width" or key == "height" then
                local value = try(component, key)
                local setter = ({ x = "SetX", y = "SetY", width = "SetWidth", height = "SetHeight" })[key]
                if value ~= nil then parts[#parts + 1] = ":" .. setter .. "(" .. tostring(value) .. ")" end
            elseif key == "rgba" then
                local value = try(component, "rgba")
                if type(value) == "number" then parts[#parts + 1] = string.format(".rgba = 0x%08X", math.floor(value)) end
            elseif key == "content" then
                parts[#parts + 1] = string.format(".content = %q", tostring(try(component, "content") or ""))
            else
                local value = try(component, key)
                if value ~= nil then parts[#parts + 1] = "." .. key .. " = " .. tostring(value) end
            end
        end
    end
    return parts
end

local function editCode()
    local lines, needNth = {}, false
    for _, component in ipairs(editOrder) do
        local changed = originals[component]
        local info = editInfo[component]
        if changed and info then
            local parts = editStatements(component, changed)
            if #parts == 1 then
                lines[#lines + 1] = info.expr .. parts[1]
            elseif #parts > 1 then
                local statements = { "local c = " .. info.expr }
                for _, part in ipairs(parts) do statements[#statements + 1] = "c" .. part end
                lines[#lines + 1] = "do " .. table.concat(statements, "; ") .. " end"
            end
            if #parts > 0 and info.usesNth then needNth = true end
        end
    end
    if #lines == 0 then return "" end
    local text = table.concat(lines, "; ")
    if needNth then text = NTH_HELPER .. text end
    return text
end

local function updateEditCode()
    if controls.editCode then pcall(function() controls.editCode:SetText(editCode(), false) end) end
end

----------------------------------------------------------------
-- THE DETAILS (the right panel)
----------------------------------------------------------------
local function setCopyBox(text)
    if controls.copyBox then pcall(function() controls.copyBox:SetText(text, false) end) end
end

local function showDetails(component)
    chosen = component
    pulseTarget = nil
    if component then
        local iid, sid = try(component, "interfaceID"), try(component, "staticID")
        if type(iid) == "number" and type(sid) == "number" then pulseTarget = { iid, sid } end
    end
    detail = component and details(component) or {}
    showSprite(component)

    local entries = {}
    for i, pair in ipairs(detail) do entries[#entries + 1] = { id = i, label = pair[1] .. ":  " .. pair[2], faded = pair[3] == nil } end
    if controls.details then fillList("details", controls.details, entries) end
    setCopyBox(component and lookupCode(component) or "")
    showEditing(nil)
    setEditorVisible(component ~= nil)
    updateEditCode()
    if not component then status("") end
end

----------------------------------------------------------------
-- EDITING A VALUE (the edit box under the details)
----------------------------------------------------------------
local function asBoolean(text)
    local lowered = string.lower(tostring(text))
    if lowered == "yes" or lowered == "true" or lowered == "1" or lowered == "on" then return true end
    if lowered == "no" or lowered == "false" or lowered == "0" or lowered == "off" then return false end
    return nil
end

-- writes `text` to the property `key` of the component; returns true, or false and why not
local function applyValue(component, key, text)
    local number = tonumber(text)
    local ok, err = pcall(function()
        if key == "content" then component.content = text
        elseif key == "x" then component:SetX(math.floor(assert(number, "needs a number")))
        elseif key == "y" then component:SetY(math.floor(assert(number, "needs a number")))
        elseif key == "width" then component:SetWidth(math.floor(assert(number, "needs a number")))
        elseif key == "height" then component:SetHeight(math.floor(assert(number, "needs a number")))
        elseif key == "alpha" then component.alpha = assert(number, "needs a number between 0 and 1")
        elseif key == "font" then component.font = math.floor(assert(number, "needs a font id"))
        elseif key == "rgba" then component.rgba = assert(tonumber(text, 16), "needs a hex colour such as FF8800FF")
        elseif key == "hidden" or key == "enabled" or key == "clickthrough" then
            local value = asBoolean(text)
            assert(value ~= nil, "needs yes or no")
            component[key] = value
        elseif key == "sprite" then
            local done = false
            for _, field in ipairs({ "spriteID", "spriteId" }) do
                if not done and type(try(component, field)) == "number" then component[field] = math.floor(assert(number, "needs a sprite id")); done = true end
            end
            assert(done, "this component has no sprite to change")
        else
            error("that value can't be edited")
        end
    end)
    if ok then return true end
    return false, tostring(err):gsub("^.-:%d+: ", "")
end

local BOOLEAN_KEYS = { hidden = true, enabled = true, clickthrough = true }

-- the edit box under the right panel. A yes/no property gets one button that shows True or False and flips it.
function showEditing(pair)
    editing = pair
    typing = pair ~= nil and pair[3] ~= nil and not BOOLEAN_KEYS[pair[3]]
    if not controls.editField then return end
    -- the button is only the True / False switch: every other value is applied as it is typed
    UI.setHidden(controls.editApply, not (pair ~= nil and BOOLEAN_KEYS[pair[3]] == true))
    if not pair then
        UI.setText(controls.editLabel, chosen and "Pick a property above" or "")
        editSetting = true; pcall(function() controls.editField:SetText("", false) end); editSetting = false
        UI.setDisabled(controls.editField, true)
        UI.setButton(controls.editApply, "Apply", "positive")
        UI.setDisabled(controls.editApply, true)
        UI.setDisabled(controls.editRevert, true)
        return
    end
    local editable = pair[3] ~= nil
    UI.setText(controls.editLabel, pair[1])
    editSetting = true; pcall(function() controls.editField:SetText(pair[2], false) end); editSetting = false
    if BOOLEAN_KEYS[pair[3]] then
        local isTrue = pair[2] == "yes"
        UI.setDisabled(controls.editField, true)
        UI.setButton(controls.editApply, isTrue and "True" or "False", isTrue and "positive" or "negative")
    else
        UI.setDisabled(controls.editField, not editable)
        UI.setButton(controls.editApply, "Apply", "positive")
    end
    UI.setDisabled(controls.editApply, not (editable and BOOLEAN_KEYS[pair[3]] == true))
    UI.setDisabled(controls.editRevert, not editable)
end

-- clicking a detail puts its value in the edit box (the copy box above is not touched)
-- fills the right panel again with the picked property highlighted
local function highlightDetails()
    local entries = {}
    for i, pair in ipairs(detail) do entries[#entries + 1] = { id = i, label = pair[1] .. ":  " .. pair[2], selected = pair == editing, faded = pair[3] == nil } end
    if controls.details then fillList("details", controls.details, entries) end
end

local function onDetailPick(_, key, isSelected)
    if not isSelected then return end
    local pair = detail[key]
    if pair then
        showEditing(pair)
        highlightDetails()
        status("")
    end
end

-- show the details again after a change, with the same row still chosen
local function redisplay(key)
    showDetails(chosen)
    for _, pair in ipairs(detail) do
        if pair[3] == key then showEditing(pair) end
    end
    highlightDetails()
end

local function onApply()
    if not chosen or not editing or not editing[3] then return end
    local name, key = editing[1], editing[3]
    local before = editing[2]
    local newText = UI.fieldText(controls.editField)
    if BOOLEAN_KEYS[key] then newText = (before == "yes") and "no" or "yes" end
    local ok, why = applyValue(chosen, key, newText)
    if not ok then return status("Couldn't change " .. name .. ": " .. tostring(why)) end
    if key == "hidden" then
        if newText == "yes" then hiddenByUs[chosen] = true else hiddenByUs[chosen] = nil end
    end

    noteEdit(chosen)
    originals[chosen] = originals[chosen] or {}
    if originals[chosen][key] == nil then originals[chosen][key] = before end   -- only the very first value is kept
    redisplay(key)
    status("")
end

-- a value that isn't yes/no is changed as it is typed: every change in the box is applied straight away
local function onEditChanged(field)
    if editSetting or not chosen or not editing or not editing[3] or BOOLEAN_KEYS[editing[3]] then return end
    local name, key, before = editing[1], editing[3], editing[2]
    local text = UI.fieldText(field)
    if text == before then return end
    local ok, why = applyValue(chosen, key, text)
    if not ok then return end   -- half-typed values (an empty number and so on) are simply not applied; no message is shown
    noteEdit(chosen)
    originals[chosen] = originals[chosen] or {}
    if originals[chosen][key] == nil then originals[chosen][key] = before end   -- only the very first value is kept
    editing[2] = text
    highlightDetails()
    updateEditCode()
end

-- the game gives plugins no way to put the cursor in a text box, so while a value is picked the key presses are typed
-- into the box here instead (Backspace deletes, Enter or Escape stops). Clicking the box itself hands typing back to it.
local function setBoxText(text)
    editSetting = true
    pcall(function() controls.editField:SetText(text, false) end)
    editSetting = false
    onEditChanged(controls.editField)
end

-- The keys are not typed straight away. Clicking the box gives it the game's own typing, and then typing here as well made every
-- letter appear twice. So a key is put in a queue, and on the next update the box is looked at: if its text has changed, the box
-- typed the key itself and this plugin stops typing for it; if it hasn't, the plugin types the key.
local keyQueue = {}
local boxSnapshot = nil          -- the value box's text on the last update

local function applyKey(current, code)
    if code == 8 then return current:sub(1, -2) end
    return current .. string.char(code)
end

local function onKeyTyped(event)
    if not typing or not controls.editField or not editing then return end
    local code = event.char
    if type(code) ~= "number" then return end
    if code == 13 or code == 27 then
        typing = false
        keyQueue = {}
    elseif code == 8 or (code >= 32 and code < 127 and not (Keyboard.IsControlDown() or Keyboard.IsMetaDown())) then
        -- (the text as it was on the last update: the box may already have typed this key by the time the event arrives, so its text now
        -- can't be used to tell what it was before)
        if #keyQueue == 0 then keyQueue.before = boxSnapshot or UI.fieldText(controls.editField) end
        keyQueue[#keyQueue + 1] = code
    end
end

local function processKeys()
    if #keyQueue == 0 then
        boxSnapshot = controls.editField and UI.fieldText(controls.editField) or nil
        return
    end
    local queue, before = keyQueue, keyQueue.before
    keyQueue = {}
    if not typing or not controls.editField or not editing then return end
    local now = UI.fieldText(controls.editField)
    if now ~= before then
        typing = false        -- the box typed it itself
        return
    end
    local text = now
    for _, code in ipairs(queue) do text = applyKey(text, code) end
    setBoxText(text)
    boxSnapshot = text
end

-- clicking a text box (this one or any other) hands typing back to the game
local function hookBox(field)
    if not field then return end
    local native
    for _, name in ipairs({ "input", "field", "native", "inputField", "component", "textField" }) do
        local ok, part = pcall(function() return field[name] end)
        if ok and part ~= nil and type(part) ~= "table" and type(part) ~= "number" and type(part) ~= "string" then native = part; break end
    end
    if native then
        pcall(function()
            native:Subscribe(ui.Hook.ONCLICK, TYPING_KEY, function() typing = false; return false end)
        end)
    end
end

local function listenToBox()
    for _, name in ipairs({ "editField", "input", "filter", "copyBox", "editCode", "luaInput" }) do hookBox(controls[name]) end
end

-- puts the chosen detail back to the value it had before this tab changed it
local function onRevert()
    if not chosen or not editing or not editing[3] then return end
    local name, key = editing[1], editing[3]
    local saved = originals[chosen] and originals[chosen][key]
    if saved == nil then return end

    local ok, why = applyValue(chosen, key, saved)
    if not ok then return status("Couldn't revert " .. name .. ": " .. tostring(why)) end
    originals[chosen][key] = nil
    if next(originals[chosen]) == nil then
        originals[chosen] = nil
        editInfo[chosen] = nil
        for i, component in ipairs(editOrder) do if component == chosen then table.remove(editOrder, i); break end end
    end
    if key == "hidden" then hiddenByUs[chosen] = nil end
    redisplay(key)
    updateEditCode()
end

----------------------------------------------------------------
-- LEFT LIST
----------------------------------------------------------------
-- the rows to show: with a filter, the matches and the rows above them (all open); without one, every row whose parents
-- are all open. Returns the rows and whether a filter is in use.
local function visibleTree(showAll)
    local want = string.lower(filterText or "")
    local shown = {}
    if want ~= "" or spritesOnly then
        local keep = {}
        for _, entry in ipairs(tree) do
            local match = (want == "" or string.find(entry.search or string.lower(entry.name), want, 1, true) ~= nil)
                and (not spritesOnly or entry.hasSprite)
            if match then
                local p = entry
                while p and not keep[p] do keep[p] = true; p = p.parent end
            end
        end
        for _, entry in ipairs(tree) do if keep[entry] then shown[#shown + 1] = entry end end
        return shown, true
    end
    if showAll then return tree, true end
    local open = {}
    for _, entry in ipairs(tree) do
        if not entry.parent or (open[entry.parent] and expanded[entry.parent.key]) then
            open[entry] = true
            shown[#shown + 1] = entry
        end
    end
    return shown, false
end

local function refreshLeft()
    if not (controls.treeView or controls.list) then return end
    local all, filtering = visibleTree(controls.treeView == nil)

    -- everything except the selected row and the rows inside it is drawn faded
    local function inSelection(entry)
        local p = entry
        while p do
            if p == selected then return true end
            p = p.parent
        end
        return false
    end
    local fadedSet = {}
    if selected then
        for _, entry in ipairs(all) do
            -- not faded: the picked row and what is inside it, its parent, and the rows beside it (same parent)
            local keep = inSelection(entry) or entry == selected.parent or entry.parent == selected.parent
            if not keep then fadedSet[entry] = true end
        end
    end

    -- the top row carries the interface's name
    local function rowText(entry)
        if entry.ancestor then return entry.name .. "  [interface " .. tostring(entry.ownerInterface or "?") .. "]" end
        if entry.interfaceTop then return entry.name .. "  (" .. tostring(treeInterfaceName or interfaceID) .. ")" end
        return entry.name
    end

    if controls.treeView then
        local entries = {}
        for _, entry in ipairs(all) do
            entries[#entries + 1] = {
                id = entry.key, text = rowText(entry), depth = entry.depth, expandable = entry.hasChildren,
                expanded = entry.hasChildren and (filtering or expanded[entry.key] == true) or false,
                selected = selected == entry, faded = fadedSet[entry] == true,
            }
        end
        local ok, err = pcall(function() controls.treeView:SetEntries(entries) end)
        if not ok then status("Couldn't draw the tree: " .. tostring(err)) end
    else
        local entries = {}
        for i, entry in ipairs(all) do
            if i > MAX_LIST_ROWS then break end
            entries[#entries + 1] = {
                id = entry.key, selected = selected == entry,
                label = string.rep("    ", entry.depth) .. (entry.hasChildren and "v " or "- ") .. rowText(entry),
            }
        end
        fillList("left", controls.list, entries)
    end
end

-- Unhides everything that was hidden and puts every edited value back. Returns how many things were put back.
local function revertAll()
    local count = 0
    for component in pairs(hiddenByUs) do
        pcall(function() component.hidden = false end)
        count = count + 1
    end
    hiddenByUs = {}
    for component, changed in pairs(originals) do
        for key, saved in pairs(changed) do
            if applyValue(component, key, saved) then count = count + 1 end
        end
    end
    originals = {}
    editOrder, editInfo = {}, {}
    return count
end

local function revertAllClicked()
    local count = revertAll()
    if chosen then showDetails(chosen) end
    updateEditCode()
    status(count > 0 and ("Reverted " .. count .. " change" .. (count == 1 and "" or "s")) or "Nothing had been changed")
end

----------------------------------------------------------------
-- RUN LUA (the box beside the edits box: paste the edits copied from the left and press Run)
----------------------------------------------------------------
local RUN_KEYS = { "x", "y", "width", "height", "alpha", "rgba", "content", "font", "sprite", "hidden", "enabled", "clickthrough" }
-- (the first version of the helper, in edits copied earlier)
local OLD_NTH_HELPER = "local function nth(p, i) local n, r = 0, nil; p:IterateDynamicComponents(function(d) n = n + 1; if n == i then r = d end end); return r end; "

-- a property as the detail panel writes it, so Revert can put it back
local function propertyText(key, value)
    if value == nil then return nil end
    if key == "rgba" and type(value) == "number" then return string.format("%08X", math.floor(value)) end
    if type(value) == "boolean" then return value and "yes" or "no" end
    return tostring(value)
end

local function readProperty(component, key)
    if key == "sprite" then
        for _, field in ipairs({ "spriteID", "spriteId" }) do
            local v = try(component, field)
            if type(v) == "number" then return v end
        end
        return nil
    end
    return try(component, key)
end

-- Runs the Lua in the box. Every component the code gets (with ui.Interfaces:GetComponent, or the helper nth) is noted as it is handed
-- over, with its values at that moment. Afterwards, whatever changed is recorded, so the edits box lists it and Revert / Revert all
-- can undo it, exactly like an edit made in the right panel.
local function runLua()
    local text = UI.fieldText(controls.luaInput)
    if text:match("^%s*$") then return status("Paste some Lua into the box first") end
    if type(load) ~= "function" then return status("This sandbox doesn't allow running Lua from text (load isn't available)") end

    local body = text
    for _, helper in ipairs({ NTH_HELPER, OLD_NTH_HELPER }) do
        if body:sub(1, #helper) == helper then body = body:sub(#helper + 1); break end
    end

    local tracked, info, before = {}, {}, {}
    local function track(component, expression, usesNth)
        if component == nil or type(component) == "number" or type(component) == "string" or type(component) == "boolean" then return component end
        if not info[component] then
            info[component] = { expr = expression, usesNth = usesNth }
            tracked[#tracked + 1] = component
            local values = {}
            for _, key in ipairs(RUN_KEYS) do values[key] = readProperty(component, key) end
            before[component] = values
        end
        return component
    end

    -- ui.Interfaces:GetComponent and nth are replaced, for this run only, by versions that note what they hand over
    local realInterfaces = ui.Interfaces
    local proxyInterfaces = setmetatable({
        GetComponent = function(_, ...)
            local component = realInterfaces:GetComponent(...)
            if component then track(component, baseExpression(component), false) end
            return component
        end,
    }, { __index = realInterfaces })
    local proxyUi = setmetatable({ Interfaces = proxyInterfaces }, { __index = ui })
    local function trackedNth(parent, index)
        local count, found = 0, nil
        parent:IterateDynamicComponents(function(child)
            count = count + 1
            if count == index then found = child end
        end)
        if found then
            local parentInfo = info[parent]
            track(found, "nth(" .. (parentInfo and parentInfo.expr or baseExpression(parent)) .. ", " .. tostring(index) .. ")", true)
        end
        return found
    end
    local env = setmetatable({ ui = proxyUi, nth = trackedNth }, { __index = _ENV })

    local fn, err = load(body, "=edits", "t", env)
    if not fn then return status("Couldn't read that Lua: " .. tostring(err)) end
    local ok, why = pcall(fn)

    local changedCount = 0
    for _, component in ipairs(tracked) do
        for _, key in ipairs(RUN_KEYS) do
            local now, was = readProperty(component, key), before[component][key]
            if now ~= was and was ~= nil then
                if not editInfo[component] then
                    editInfo[component] = info[component]
                    editOrder[#editOrder + 1] = component
                end
                originals[component] = originals[component] or {}
                if originals[component][key] == nil then originals[component][key] = propertyText(key, was) end
                if key == "hidden" then
                    if now == true then hiddenByUs[component] = true else hiddenByUs[component] = nil end
                end
                changedCount = changedCount + 1
            end
        end
    end
    if chosen then showDetails(chosen) end
    updateEditCode()
    if not ok then
        return status("Error: " .. tostring(why) .. (changedCount > 0 and ("  (" .. changedCount .. " value" .. (changedCount == 1 and "" or "s") .. " were changed before it)") or ""))
    end
    status("Ran it: " .. #tracked .. " component" .. (#tracked == 1 and "" or "s") .. " found, " .. changedCount .. " value" .. (changedCount == 1 and "" or "s") .. " changed")
end

----------------------------------------------------------------
-- BUTTONS
----------------------------------------------------------------
-- Clicking a row's name selects it. Clicking its arrow opens / closes it (and selects it). The game can report one click
-- more than once, so a second report of the same click in the same update is ignored.
local lastClickKey, lastClickAt = nil, -1
local lastToggleKey, lastToggleAt = nil, -1
local clickTick = 0                -- goes up on every game update (InterfaceTab.tick)

local function pickEntry(key, toggle)
    local entry = byKey[key]
    if not entry then return end
    local changed = selected ~= entry
    selected = entry
    if toggle and entry.hasChildren and (filterText or "") == "" then expanded[key] = not expanded[key] or nil end
    if changed then showDetails(entry.component) end
    refreshLeft()
    status("")
end

local function selectKey(key)
    if lastClickKey == key and lastClickAt == clickTick then return end
    lastClickKey, lastClickAt = key, clickTick
    pickEntry(key, false)
end

local function toggleKey(key)
    if lastToggleKey == key and lastToggleAt == clickTick then return end
    lastToggleKey, lastToggleAt = key, clickTick
    pickEntry(key, true)
end

-- the plain list (only used if the drawn tree couldn't be made)
local function onPick(_, key, isSelected)
    if isSelected then pickEntry(key, true) end
end

-- Puts the whole tab back as it was when first opened: reverts every edit, forgets the loaded interface and clears the boxes
local function resetTab()
    revertAll()
    interfaceID, tree, byKey, selected = nil, {}, {}, nil
    filterText, expanded, typedInterface = "", {}, ""
    chosen, editing, detail = nil, nil, {}
    for _, name in ipairs({ "input", "filter", "copyBox", "editField" }) do
        local control = controls[name]
        if control then pcall(function() control:SetText("", false) end) end
    end
    if controls.list or controls.treeView then refreshLeft() end
    if controls.editField then
        showDetails(nil)
        showEditing(nil)
    end
    for _, name in ipairs({ "luaInput", "editCode" }) do
        local control = controls[name]
        if control then pcall(function() control:SetText("", false) end) end
    end
end

local function loadInterface()
    local text = UI.fieldText(controls.input)
    local id = tonumber(text)
    if not id then return status("Type an interface id (a number) first") end
    id = math.floor(id)

    local result, problem = readInterface(id)
    if not result then return status(problem) end

    interfaceID = id
    treeInterfaceName = Names.interfaceName(id)
    tree, byKey = result, {}
    for _, entry in ipairs(tree) do byKey[entry.key] = entry end
    selected, expanded = nil, {}
    -- everything above the interface is opened, and the interface's top row is picked, so the tree starts at the interface
    -- with its parents above it
    for _, entry in ipairs(tree.ancestors or {}) do expanded[entry.key] = true end
    local tops = tree.interfaceRoots or {}
    if #tops == 1 and tops[1].hasChildren then expanded[tops[1].key] = true end
    selected = tops[1]
    showDetails(selected and selected.component or nil)
    refreshLeft()
    if selected and controls.treeView then
        local rows = visibleTree(false)
        for i, entry in ipairs(rows) do
            if entry == selected then pcall(function() controls.treeView:Reveal(i) end); break end
        end
    end
    Info.startSpriteNames()
    local ancestorCount = #(tree.ancestors or {})
    local componentCount = #tree - ancestorCount
    status(componentCount == 0 and ("Interface " .. id .. " is loaded but no components were found")
        or ("Loaded interface " .. id .. (ancestorCount > 0 and (" (with " .. ancestorCount .. " parent component" .. (ancestorCount == 1 and "" or "s") .. " above it)") or "")))
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
local LOAD_KEY = "F8"              -- pressing it loads the interface, like the Load button
local function onLoadKeyDown(event)
    if event.isRepeat or event.gameKey ~= GameKey[LOAD_KEY] or Keyboard.IsBlocked() then return end
    pcall(loadInterface)
end
local SUB_TAB_HEIGHT = 750       -- the area under the Tree / Lookup tabs

local subIndex = 1                -- the sub-tab showing (1 Tree, 2 Lookup)
local TREE_SUB_TAB, LOOKUP_SUB_TAB = 1, 2
local subTabs, subView, pendingSubTab, pendingOpen, lookupScroll = nil, nil, nil, nil, nil

local function buildTree(page)
    pcall(function() Event.KeyDown.Subscribe("devtools_interface_loadkey", onLoadKeyDown) end)
    page:AddText({ text = "Interface id", width = 100, columnGap = 0 })
    controls.input = page:AddTextField({
        placeholder = "e.g. 1473", maxLength = 8, width = INPUT_WIDTH, inline = true, columnGap = 10, onSubmit = loadInterface,
    })
    page:AddSimpleButton("Load (" .. LOAD_KEY .. ")", loadInterface, { width = 100, inline = true, columnGap = 10, tooltip = "Reads the interface. The " .. LOAD_KEY .. " key does the same, even while you hover something in the game." })
    page:AddSimpleButton("Reset", resetTab, {
        width = 90, inline = true, columnGap = 100, tooltip = "Revert every edit and clear the loaded interface, filters and boxes",
    })
    page:AddDivider({ marginTop = -29, marginBottom = -8 })

    -- the filter is half the width of the list, with a Clear button next to it
    local leftFilterWidth = math.floor(LIST_WIDTH / 2)
    controls.filter = page:AddTextField({
        placeholder = "Filter components by text, item, sprite, type or id", maxLength = 40, width = leftFilterWidth, columnGap = 10,
        onChange = function(field) filterText = UI.fieldText(field); filterWait = 2 end,
    })
    pcall(function() controls.filter:SetText(filterText, false) end)
    pcall(function() controls.input:SetText(typedInterface, false) end)
    page:AddSimpleButton("Clear", function()
        pcall(function() controls.filter:SetText("", false) end)
        filterText = ""; filterWait = nil; refreshLeft()
    end, { inline = true, columnGap = 0, width = CLEAR_WIDTH, tooltip = "Clear the filter" })

    -- the tree is drawn out of the game's own components inside a panel. If that can't be done a plain list is used.
    local treeError = "no panel"
    local host
    pcall(function() host = page:AddPanel({ width = LIST_WIDTH, height = PANEL_HEIGHT, columnGap = LIST_GAP }) end)
    if host then
        pcall(function() host:SetScrollable(false) end)
        for _, name in ipairs({ "root", "content", "container" }) do
            local parent = not controls.treeView and TreeView and (function() local ok, v = pcall(function() return host[name] end); return ok and v or nil end)()
            if parent then
                local ok, view = pcall(TreeView.new, parent, 0, 0, LIST_WIDTH, PANEL_HEIGHT, selectKey, toggleKey)
                if ok then controls.treeView = view else treeError = "host." .. name .. ": " .. tostring(view) end
            end
        end
        if not controls.treeView then
            local ok, view = pcall(TreeView.new, host, 0, 0, LIST_WIDTH, PANEL_HEIGHT, selectKey, toggleKey)
            if ok then controls.treeView = view else treeError = "panel: " .. tostring(view) end
        end
    end
    if not controls.treeView then
        controls.list = page:AddList({
            maxSelected = 1, entries = {}, onChange = onPick, width = LIST_WIDTH, height = PANEL_HEIGHT, columnGap = LIST_GAP,
        })
    end
    -- the right-hand panel: every property of the picked component, drawn with the same scrolling view as the tree
    local detailsHost
    pcall(function() detailsHost = page:AddPanel({ width = PANEL_WIDTH, height = PANEL_HEIGHT, inline = true }) end)
    if detailsHost then
        pcall(function() detailsHost:SetScrollable(false) end)
        for _, name in ipairs({ "root", "content", "container" }) do
            local parent = not controls.detailsView and (function() local ok, v = pcall(function() return detailsHost[name] end); return ok and v or nil end)()
            if parent then
                local ok, view = pcall(TreeView.new, parent, 0, 0, PANEL_WIDTH, PANEL_HEIGHT, function(key) onDetailPick(nil, tonumber(key), true) end, nil, true)
                if ok then controls.detailsView = view end
            end
        end
    end
    if controls.detailsView then
        local view = controls.detailsView
        -- fillList only needs SetEntries, so the drawn view stands in for a list
        controls.details = { SetEntries = function(_, entries)
            local rowsOut = {}
            for _, e in ipairs(entries) do rowsOut[#rowsOut + 1] = { id = e.id, text = e.label, depth = 0, selected = e.selected == true, faded = e.faded == true } end
            view:SetEntries(rowsOut)
        end }
    else
        controls.details = page:AddList({
            maxSelected = 1, entries = {}, onChange = onDetailPick, width = PANEL_WIDTH, height = PANEL_HEIGHT, inline = true,
        })
    end

    -- under the left tree: what it is. Under the right panel: what is being edited, and the sprite of the component.
    -- "[checkbox] Show Selected [colour]": the picked component pulses in the game in the chosen colour (both are remembered)
    showSelected = Settings.get("showSelected", 0) == 1
    showColour = Settings.get("showColour", showColour)
    local CHECK_WIDTH, CHECK2_WIDTH, SWATCH, SWATCH_GAP = 175, 150, 24, 55          -- a guess at the checkbox's width, so the right-hand label lines up
    -- a checkbox on its own spans the whole row, so a small spacer starts the row and the checkbox joins it
    page:AddText({ text = "", width = 1, columnGap = 0, marginTop = 10 })
    pcall(function()
        controls.showCheck = page:AddCheckboxButton({ { text = "Highlight Selected", value = "show", selected = showSelected } }, {
            inline = true, onChange = function(_, _, _, isSelected)
                if treeSetting then return end
                setShowSelected(isSelected)
            end,
        })
    end)
    pcall(function()
        controls.showColour = page:AddColourPicker({
            value = showColour * 256 + 255, alphaSlider = false, buttonSize = SWATCH, inline = true,
            columnGap = SWATCH_GAP, tooltip = "The colour of the pulsing outline",
            windowTitle = "Highlight Selected colour",
            onChange = function(_, colour)
                if type(colour) == "number" then
                    showColour = math.floor(colour) // 256
                    Settings.set("showColour", showColour)
                end
            end,
        })
    end)
    pcall(function()
        controls.spritesCheck = page:AddCheckboxButton({ { text = "Show Sprites only", value = "sprites", selected = spritesOnly } }, {
            inline = true, columnGap = LIST_WIDTH - SPRITE_SIZE - CHECK_WIDTH - SWATCH - SWATCH_GAP - CHECK2_WIDTH,
            onChange = function(_, _, _, isSelected)
                spritesOnly = isSelected == true
                -- keep the picked row where it is: open everything above it, so switching the filter off doesn't collapse the tree
                local p = selected and selected.parent
                while p do expanded[p.key] = true; p = p.parent end
                refreshLeft()
                if selected and controls.treeView then
                    local rows = visibleTree(false)
                    for i, entry in ipairs(rows) do
                        if entry == selected then pcall(function() controls.treeView:Reveal(i) end); break end
                    end
                end
            end,
        })
    end)
    if showSelected then setShowSelected(true) end
    -- the sprite of the picked component: against the right border of the left panel, on the same line
    controls.sprite = nil
    for _, start in ipairs({ -1, 0 }) do
        if not controls.sprite then
            pcall(function()
                controls.sprite = page:AddSprite(start, { size = SPRITE_SIZE, inline = true, columnGap = LIST_GAP + 14 })
            end)
        end
    end
    controls.editLabel = page:AddText({ text = "", width = PANEL_WIDTH, inline = true, columnGap = 0, marginTop = 8 })

    -- left: a line, then the Lua lookup of the picked component. Right: the value box, then the buttons.
    page:AddDivider({ width = LIST_WIDTH - 8, marginTop = -34, marginBottom = -36, columnGap = VALUE_X - (LIST_WIDTH - 8) })
    controls.editField = page:AddTextField({
        placeholder = "Value", maxLength = 500, width = PANEL_WIDTH + LIST_WIDTH + LIST_GAP - VALUE_X, inline = true, columnGap = 0, offsetY = VALUE_DOWN, onSubmit = onEditChanged, onChange = onEditChanged,
    })
    page:AddText({ text = "Lua lookup of the selected component (select and copy)", width = LIST_WIDTH + LIST_GAP, columnGap = 0 })
    -- the fancy Apply button is drawn wider than it is declared (and changes width with its label), so a spacer of
    -- Simple-button width is left after it
    pcall(listenToBox)
    pcall(function() Event.KeyTyped.Subscribe(TYPING_KEY, onKeyTyped) end)
    controls.editApply = page:AddFancyButton("Apply", onApply, { variant = "positive", width = BUTTON_WIDTH, inline = true, columnGap = 0 })
    page:AddText({ text = "", width = 75, inline = true, columnGap = 0 })
    controls.editRevert = page:AddSimpleButton("Revert", onRevert, {
        width = 70, inline = true, columnGap = 10,
        tooltip = "Put this value back to what it was before it was edited here",
    })
    controls.revertAll = page:AddSimpleButton("Revert all changes", revertAllClicked, {
        width = 150, inline = true, columnGap = 0,
        tooltip = "Unhide everything hidden here and put back every value edited here",
    })
    controls.copyBox = page:AddTextField({ placeholder = "Pick a component", maxLength = 9999, width = LIST_WIDTH, columnGap = LIST_GAP })
    -- the edits box on the left, and the box to run Lua on the right, each with a line above it saying what it is
    page:AddText({ text = "Lua for every edit made with this tool", width = LIST_WIDTH + LIST_GAP, columnGap = 0 })
    page:AddText({ text = "Paste Lua code for edits and press Run to apply them", width = PANEL_WIDTH, inline = true, columnGap = 0 })
    controls.editCode = page:AddTextField({ placeholder = "Nothing edited", maxLength = 9999, width = LIST_WIDTH, columnGap = LIST_GAP })
    controls.luaInput = page:AddTextField({
        placeholder = "Paste Lua edits here", maxLength = 9999, width = PANEL_WIDTH - 90 - 90, inline = true, columnGap = 0, onSubmit = runLua,
    })
    pcall(function() controls.luaInput:SetText(typedLua, false) end)
    controls.luaRun = page:AddSimpleButton("Run", runLua, {
        width = 70, inline = true, columnGap = 10, tooltip = "Runs the Lua in the box. Edits copied from the box on the left are applied and can be reverted",
    })
    controls.luaClear = page:AddSimpleButton("Clear", function()
        pcall(function() controls.luaInput:SetText("", false) end)
    end, { width = 70, inline = true, columnGap = 10, tooltip = "Clear the Lua box" })
    if not controls.treeView then
        pcall(print, "[DevTools interface] the drawn tree couldn't be made: " .. tostring(treeError))
    end

    refreshLeft()
    local editedName = editing and editing[1]
    showDetails(chosen)
    local editedRow = nil
    for _, pair in ipairs(detail) do
        if pair[1] == editedName then editedRow = pair end
    end
    showEditing(editedRow)
end

local function releaseTree()
    if controls.luaInput then typedLua = UI.fieldText(controls.luaInput) end
    if controls.input then typedInterface = UI.fieldText(controls.input) end
    pcall(function() Event.KeyTyped.Unsubscribe(TYPING_KEY) end)
    pcall(function() Event.KeyDown.Unsubscribe("devtools_interface_loadkey") end)
    if controls.treeView then pcall(function() controls.treeView:Destroy() end) end
    if controls.detailsView then pcall(function() controls.detailsView:Destroy() end) end
    -- just the rectangle, highlight keeps running and draws a new one next frame
    destroyPulse()
    controls, signatures, filterWait = {}, {}, nil
end

local function buildSubTab(index)
    subView = prettyui.SimpleView.new(subTabs:GetPage(index).content, {
        width = 0, height = 0, widthAnchor = 1.0, heightAnchor = 1.0, scrollable = index == LOOKUP_SUB_TAB,
    })
    if index == LOOKUP_SUB_TAB then
        LookupTab.build(subView)
        if lookupScroll then subView:SetScrollPosition(lookupScroll) end
    else
        buildTree(subView)
    end
end

local function openPendingInterface()
    local number = pendingOpen
    pendingOpen = nil
    if controls.input then pcall(function() controls.input:SetText(tostring(number), false) end) end
    loadInterface()
    -- pick the top row and open what is under it
    local top = tree.interfaceRoots and tree.interfaceRoots[1] or tree[1]
    if top then
        selected = top
        expanded[top.key] = true
        showDetails(top.component)
        refreshLeft()
    end
end

local function switchSubTab(index)
    if subView then
        if subIndex == LOOKUP_SUB_TAB then
            pcall(LookupTab.leave)
            pcall(LookupTab.release)
            lookupScroll = subView.scrollY
        else
            pcall(releaseTree)
        end
        pcall(function() subView:Destroy() end)
        subView = nil
    end
    subIndex = index
    buildSubTab(index)
    if index == LOOKUP_SUB_TAB then pcall(LookupTab.enter) end
end

-- the tab holds two sub-tabs: Tree (the interface browser above) and Lookup (find a component by its name)
function InterfaceTab.build(page)
    subTabs = page:AddTabs({ { text = "Tree" }, { text = "Lookup" } }, {
        height = SUB_TAB_HEIGHT, activeIndex = subIndex, scrollable = false,
        onChange = function(_, index)
            -- same as main tabs, swap waits for next update
            pendingSubTab = index; typing = false
        end,
    })
    -- no scrollbar on the tab page holding it: everything fits in the window
    pcall(function() page:SetScrollable(false) end)
    buildSubTab(subIndex)

    -- "Open in tree" on the Lookup sub-tab: show the Tree sub-tab and load that interface in it
    LookupTab.openInTree = function(number)
        -- tree isnt built yet so this loads once it is, see InterfaceTab.tick
        pendingOpen = number
        subTabs:SetActive(TREE_SUB_TAB)
        return "Opened interface " .. number .. " in the Tree tab"
    end
end

-- called by the window when another tab is shown
function InterfaceTab.onHide() typing = false end
function InterfaceTab.onShow() if subIndex == 2 then pcall(LookupTab.enter) end end

function InterfaceTab.start()
    LookupTab.start()
end

function InterfaceTab.reset()
    resetTab()
    LookupTab.reset()
end

function InterfaceTab.release()
    typing = false
    if subView and subIndex == LOOKUP_SUB_TAB then lookupScroll = subView.scrollY end
    releaseTree()
    LookupTab.release()
    if subView then pcall(function() subView:Destroy() end) end
    subView, subTabs, pendingSubTab, pendingOpen = nil, nil, nil, nil
end

-- runs on every game update: queued key presses, sprite names, the tree, and the left filter once typing pauses
function InterfaceTab.tick()
    clickTick = clickTick + 1
    if pendingSubTab then
        local index = pendingSubTab
        pendingSubTab = nil
        pcall(switchSubTab, index)
    end
    if pendingOpen and subIndex == TREE_SUB_TAB and controls.input then pcall(openPendingInterface) end
    pcall(processKeys)
    pcall(LookupTab.tick)
    if Info.stepSpriteNames() and controls.details and chosen then pcall(showDetails, chosen) end
    if controls.treeView then pcall(function() controls.treeView:Refresh() end) end
    if filterWait then
        filterWait = filterWait - 1
        if filterWait <= 0 then filterWait = nil; pcall(refreshLeft) end
    end
end

function InterfaceTab.shutdown()
    typing = false
    pcall(function() Event.KeyTyped.Unsubscribe(TYPING_KEY) end)
    pcall(function() Event.KeyDown.Unsubscribe("devtools_interface_loadkey") end)
    stopPulse()
    LookupTab.shutdown()
    revertAll()
end

return InterfaceTab