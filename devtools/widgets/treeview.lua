--[[
    treeview.lua - a tree that is drawn out of the game's own components (rectangles for the lines, a sprite for each
    arrow, text for each name), instead of text in a list. Only the rows that can be seen are made, and they are
    reused as you scroll, so a tree of any size costs the same fixed number of components.

    Adapted from tree_view.lua in the Component Inspector plugin by Joshua Filby (MIT licence):
    https://github.com/Joshua-F/RSPlugins/tree/component-inspector

    MIT License - Copyright 2026 Joshua Filby. Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to
    the following conditions: the above copyright notice and this permission notice shall be included in all copies or
    substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

    Entries are { id, text, depth, expandable, expanded, selected, faded }. Rows are in display order; the lines are
    worked out from the depths.
]]

local ROW_HEIGHT, INDENT, BAR_WIDTH = 22, 14, 14
local TEXT, MUTED = 0xE7D7B0FF, 0x8B8882FF
local SELECTED, HOVER = 0x294658FF, 0x302E29FF
local LINE = 0x716B61FF

local TreeView = {}
TreeView.__index = TreeView
TreeView.ROW_HEIGHT = ROW_HEIGHT

local function rectangle(parent, colour)
    local result = ui.Rectangle.new(parent)
    result.fill, result.rgba, result.clickthrough = true, colour, true
    return result
end

local function mouseY()
    local position = Mouse.GetPosition()
    if not position then return end
    local scale = 100
    pcall(function() scale = tonumber(game.options.InterfaceScale.setting) or 100 end)
    return position.y * 100 / math.max(1, scale)
end

local function escapeTags(text)
    return (tostring(text):gsub("[<>]", { ["<"] = "<lt>", [">"] = "<gt>" }))
end

-- parent: a component the tree can be made inside (it is made at x, y with this width and height).
-- plain: draw a simple scrolling list of text rows (no lines or arrows) instead of a tree.
function TreeView.new(parent, x, y, width, height, onSelect, onToggle, plain)
    local self = setmetatable({
        entries = {}, rows = {}, scrollY = 0, width = width - BAR_WIDTH - 3, height = height - 2, thumbHeight = 0,
        parent = parent, dirty = true, onSelect = onSelect, onToggle = onToggle, plain = plain == true,
    }, TreeView)
    self.root = ui.Layer.new(parent)
    self.root:SetPos(x, y)
    self.root:SetSize(width, height)
    self.root.clickthrough = false
    local background = rectangle(self.root, 0x171512E8)
    background:SetSize(width, height)
    local border = rectangle(self.root, 0x716B61FF)
    border.fill, border.outlineThickness = false, 1
    border:SetSize(width, height)
    self.viewport = ui.Layer.new(self.root)
    self.viewport:SetPos(1, 1)
    self.viewport:SetSize(self.width, self.height)
    self.viewport.clickthrough = false
    self.track = ui.Layer.new(self.root)
    self.track:SetPos(width - BAR_WIDTH - 1, 1)
    self.track:SetSize(BAR_WIDTH, self.height)
    self.track.clickthrough = false
    local trackBackground = rectangle(self.track, 0x24221FFF)
    trackBackground:SetSize(BAR_WIDTH, self.height)
    -- the bar you see, and an invisible one on top of it that takes the mouse (it is made enormous while dragging)
    self.thumbShow = rectangle(self.track, LINE)
    self.thumb = rectangle(self.track, 0x00000000)
    self.thumb.clickthrough = false

    self:BindWheel(self.root)
    self:BindWheel(self.viewport)
    self:BindWheel(self.track)
    self:BindWheel(self.thumb)
    self.track:Subscribe(ui.Hook.ONCLICK, function(_, _, clickY)
        local travel = self.height - self.thumbHeight
        if travel > 0 then self:SetScrollPosition((clickY - self.thumbHeight / 2) * self:MaxScroll() / travel) end
        return false
    end)
    -- Dragging the thumb: the game only sends "held" to the component the pointer is over, so while the thumb is held a
    -- see-through layer is put over the whole window. The drag carries on over that layer until the button is let go.
    self.thumb:Subscribe(ui.Hook.ONCLICK, function() self:Note("thumb click"); self:BeginDrag(); return false end)
    self.thumb:Subscribe(ui.Hook.ONHOLD, function() self:Note("thumb hold"); self:DragMove(); return false end)
    -- the game reports a release on the thumb as soon as the pointer leaves it, so that is not the end of the drag
    self.thumb:Subscribe(ui.Hook.ONRELEASE, function() self:Note("thumb release (ignored)"); return false end)
    for _, name in ipairs({ "ONDRAG", "ONDRAGCOMPLETE", "ONCLICKREPEAT" }) do
        local hook = ui.Hook[name]
        if hook then
            pcall(function() self.thumb:Subscribe(hook, function() self:Note("thumb " .. name); return false end) end)
        end
    end
    return self
end

-- A line in the log about the scrollbar drag, once for each kind of event per drag (the drag does not work in every
-- situation and this shows which events the game really sends)
function TreeView:Note(text)
    self.noted = self.noted or {}
    if self.noted[text] then return end
    self.noted[text] = true
    pcall(function() print("[DevTools scrollbar] " .. text) end)
end

-- the layer at the top of the window this tree is in (the one that covers the whole screen)
function TreeView:TopLayer()
    local top, current = nil, self.root
    for _ = 1, 64 do
        local ok, up = pcall(function() return current.parent end)
        if not ok or not up then break end
        top, current = up, up
    end
    return top
end

function TreeView:PlaceThumb()
    local top = math.floor(self.scrollY / math.max(1, self:MaxScroll()) * (self.height - self.thumbHeight))
    self.thumbShow:SetSize(BAR_WIDTH, self.thumbHeight)
    self.thumbShow:SetPos(0, top)
    self.thumb:SetSize(BAR_WIDTH, self.thumbHeight)
    self.thumb:SetPos(0, top)
end

function TreeView:BeginDrag()
    if self.drag then self:EndDrag() end
    local y = mouseY()
    if not y then return end
    self.drag = { y = y, scroll = self.scrollY }
    self.dragIdle = 0
    self.noted = {}
    -- a see-through layer over the whole window takes over once the pointer leaves the thumb
    local made, why = pcall(function()
        if not self.capture then
            local top = self:TopLayer()
            if not top then error("no top layer") end
            self.capture = ui.Layer.new(top)
            self.capture:SetPos(0, 0)
            self.capture:SetSize(0, 0, 1, 1)
            self.capture.clickthrough = false
            self.capture:Subscribe(ui.Hook.ONHOLD, function() self:Note("capture hold"); self:DragMove(); return false end)
            self.capture:Subscribe(ui.Hook.ONRELEASE, function() self:Note("capture release"); self:EndDrag(); return false end)
            self.capture:Subscribe(ui.Hook.ONCLICK, function() self:Note("capture click"); self:EndDrag(); return false end)
            self:Note("capture made, " .. tostring(self.capture.width) .. " x " .. tostring(self.capture.height))
        end
        self.capture.hidden = false
        self.capture:MoveToFront()
    end)
    if not made then self:Note("capture failed: " .. tostring(why)) end
    -- if the release is never seen, the drag (and the huge thumb) is dropped once nothing is held any more
    self.dragKey = "devtools_treeview_drag_" .. tostring(self)
    pcall(function()
        Event.Draw.Subscribe(self.dragKey, function()
            self.dragIdle = (self.dragIdle or 0) + 1
            if self.dragIdle > 20 then self:EndDrag() end
        end)
    end)
end

function TreeView:DragMove()
    if not self.drag then return end
    self.dragIdle = 0
    local y, travel = mouseY(), self.height - self.thumbHeight
    if y and travel > 0 then
        self:SetScrollPosition(self.drag.scroll + (y - self.drag.y) * self:MaxScroll() / travel)
    end
end

function TreeView:EndDrag()
    local was = self.drag ~= nil
    self.drag = nil
    if self.capture then pcall(function() self.capture.hidden = true end) end
    if was then pcall(function() self:PlaceThumb() end) end
    if self.dragKey then pcall(function() Event.Draw.Unsubscribe(self.dragKey) end); self.dragKey = nil end
end

function TreeView:MaxScroll()
    return math.max(0, #self.entries * ROW_HEIGHT - self.height)
end

function TreeView:BindWheel(component)
    component:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        self:SetScrollPosition(self.scrollY + delta * ROW_HEIGHT * 3)
        return false
    end)
end

function TreeView:SetScrollPosition(position)
    local value = math.max(0, math.min(self:MaxScroll(), math.floor(position)))
    if value ~= self.scrollY then
        self.scrollY, self.dirty = value, true
        self:Refresh()
    end
end

-- the rows to show, in order. The scroll position is kept.
function TreeView:SetEntries(entries)
    local branches = {}
    for _, entry in ipairs(entries) do
        while #branches > 0 and branches[#branches].depth >= entry.depth do
            local previous = table.remove(branches)
            previous.lastChild = previous.depth > entry.depth
        end
        entry.ancestor = branches[#branches]
        branches[#branches + 1] = entry
    end
    for _, entry in ipairs(branches) do entry.lastChild = true end
    self.entries = entries
    self.scrollY = math.max(0, math.min(self:MaxScroll(), self.scrollY))
    self.dirty = true
    self:Refresh()
end

-- scrolls so that row number `index` is on screen
function TreeView:Reveal(index)
    local top = (index - 1) * ROW_HEIGHT
    if top < self.scrollY then self:SetScrollPosition(top)
    elseif top + ROW_HEIGHT > self.scrollY + self.height then self:SetScrollPosition(top + ROW_HEIGHT - self.height) end
end

function TreeView:ColourRow(row)
    row.background.rgba = row.entry and row.entry.selected and SELECTED or (row.hovered and HOVER or 0x00000000)
end

function TreeView:CreateRow()
    local root = ui.Layer.new(self.viewport)
    root:SetSize(self.width, ROW_HEIGHT)
    root.clickthrough = false
    local row = {
        root = root, background = rectangle(root, 0), accent = rectangle(root, 0x39D6FFFF),
        guide = rectangle(root, LINE), twig = rectangle(root, LINE), continuations = {}, hovered = false,
    }
    row.background:SetSize(self.width, ROW_HEIGHT)
    row.accent:SetSize(2, ROW_HEIGHT)
    row.toggle = ui.Layer.new(root)
    row.toggle:SetSize(20, ROW_HEIGHT)
    row.toggle.clickthrough = false
    row.arrow = ui.Sprite.new(row.toggle)
    row.arrow:SetPos(2, 3)
    row.arrow:SetSize(16, 16)
    row.arrow.clickthrough = true
    row.label = prettyui.Text.new(root, { text = "", height = ROW_HEIGHT, maxLines = 1 })
    row.label.clickthrough = true
    for _, component in ipairs({ root, row.background, row.accent, row.guide, row.twig, row.toggle, row.arrow, row.label }) do
        self:BindWheel(component)
    end
    root:Subscribe(ui.Hook.ONCLICK, function()
        if row.entry then self.onSelect(row.entry.id) end
        return false
    end)
    row.toggle:Subscribe(ui.Hook.ONCLICK, function()
        if row.entry and row.entry.expandable and self.onToggle then self.onToggle(row.entry.id) end
        return false
    end)
    root:Subscribe(ui.Hook.ONMOUSEOVER, function() row.hovered = true; self:ColourRow(row); return true end)
    root:Subscribe(ui.Hook.ONMOUSELEAVE, function() row.hovered = false; self:ColourRow(row); return true end)
    self.rows[#self.rows + 1] = row
    return row
end

-- the vertical lines of the branches above this row that carry on past it
function TreeView:UpdateContinuations(row, entry, indent, budget)
    local ancestor, count = entry.ancestor, 0
    while ancestor do
        local x = ancestor.depth * INDENT
        if ancestor.depth > 0 and not ancestor.lastChild and x < indent then
            local line = row.continuations[count + 1]
            if not line then
                if budget == 0 then self.dirty = true; break end
                line = rectangle(row.root, LINE)
                line:SetSize(2, ROW_HEIGHT)
                self:BindWheel(line)
                row.continuations[count + 1] = line
                budget = budget - 1
            end
            count = count + 1
            line:SetPos(x - 3, 0)
            line.hidden = false
        end
        ancestor = ancestor.ancestor
    end
    for index = count + 1, #row.continuations do row.continuations[index].hidden = true end
    return budget
end

local arrowDown, arrowRight
local function findArrows()
    if arrowDown ~= nil then return end
    arrowDown, arrowRight = false, false
    pcall(function() arrowDown = id.Sprite.RS3_ICON_DIRECTION_DOWN_32PX_2 or false end)
    pcall(function() arrowRight = id.Sprite.RS3_ICON_DIRECTION_RIGHT_32PX_2 or false end)
end

-- draws the rows that are in view (a few new rows are made per call, so it carries on until everything is drawn)
function TreeView:Update()
    if not self.dirty then return end
    self.dirty = false
    findArrows()
    local first = math.floor(self.scrollY / ROW_HEIGHT) + 1
    local count = math.min(math.ceil(self.height / ROW_HEIGHT) + 1, #self.entries - first + 1)
    local created, guideBudget = 0, 32
    self.viewport:SetScrollSize(self.width, math.max(self.height, #self.entries * ROW_HEIGHT))
    self.viewport:SetScrollPos(0, self.scrollY)
    for slot = 1, count do
        local row = self.rows[slot]
        if not row then
            if created == 8 then self.dirty = true; break end
            row, created = self:CreateRow(), created + 1
        end
        local index = first + slot - 1
        local entry = self.entries[index]
        if not row.entry or row.entry.id ~= entry.id then row.hovered = false end
        row.entry = entry
        row.root.hidden = false
        row.root:SetPos(0, (index - 1) * ROW_HEIGHT)
        local indent = math.min(entry.depth * INDENT, math.max(0, self.width - 140))
        local plain = self.plain
        row.toggle:SetPos(4 + indent, 0)
        row.toggle.hidden = plain or not entry.expandable
        local sprite = entry.expanded and arrowDown or arrowRight
        if sprite then row.arrow.spriteID = sprite end
        local colour = entry.faded and MUTED or TEXT
        row.arrow.rgba = colour
        local middle = math.floor(ROW_HEIGHT / 2) - 1
        row.guide.hidden, row.twig.hidden = plain or entry.depth == 0, plain or entry.depth == 0
        row.guide:SetPos(indent - 3, 0)
        row.guide:SetSize(2, entry.lastChild and middle + 2 or ROW_HEIGHT)
        -- the branch runs on to the name when there is no arrow in the way
        local reach = entry.expandable and 7 or 17
        row.twig:SetPos(indent - 3, middle)
        row.twig:SetSize(reach, 2)
        guideBudget = plain and guideBudget or self:UpdateContinuations(row, entry, indent, guideBudget)
        if plain then
            for _, line in ipairs(row.continuations) do line.hidden = true end
            row.label:SetPos(8, 0)
            row.label:SetSize(math.max(1, self.width - 12), ROW_HEIGHT)
        else
            local labelX = entry.expandable and (indent + 24) or (indent + 18)
            row.label:SetPos(labelX, 0)
            row.label:SetSize(math.max(1, self.width - labelX - 4), ROW_HEIGHT)
        end
        row.label.content = escapeTags(entry.text)
        row.label.rgba = colour
        row.accent.hidden = not entry.selected
        self:ColourRow(row)
    end
    for slot = math.max(0, count) + 1, #self.rows do self.rows[slot].root.hidden = true; self.rows[slot].entry = nil end
    local maximum = self:MaxScroll()
    self.track.hidden = maximum == 0
    if maximum > 0 then
        self.thumbHeight = math.min(self.height, math.max(24, math.floor(self.height * self.height / (#self.entries * ROW_HEIGHT))))
        self.thumbShow:SetSize(BAR_WIDTH, self.thumbHeight)
        self.thumbShow:SetPos(0, math.floor(self.scrollY / maximum * (self.height - self.thumbHeight)))
        if not self.drag then
            self.thumb:SetSize(BAR_WIDTH, self.thumbHeight)
            self.thumb:SetPos(0, math.floor(self.scrollY / maximum * (self.height - self.thumbHeight)))
        end
    end
end

-- draws now, and keeps going for the rows that didn't fit in one call
function TreeView:Refresh()
    for _ = 1, 6 do
        if not self.dirty then break end
        self:Update()
    end
end

function TreeView:Destroy()
    self:EndDrag()
    if self.capture then pcall(function() self.capture:Destroy() end); self.capture = nil end
    pcall(function() self.root:Destroy() end)
    self.rows, self.entries = {}, {}
end

return TreeView
