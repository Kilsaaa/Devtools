--[[
    overlaystab.lua - the "Overlays" tab: toggles that show extra information in the game itself.

      NPC IDs above heads  - a label over every NPC in view with its name and config id (yellow)
      Object IDs           - the same over every object near the player (cyan)
      IDs in hover text    - adds ids (NPC / loc / obj / interface component / sprite) to the hover text and menu entries

    Everything starts off, and everything is removed again when a toggle is turned off or the plugin shuts down.
    These use parts of the API that have not been tried in the real game yet, so each one is wrapped so that a
    problem turns it off and says why in the status line, instead of repeating.
]]

local UI = require("core/uiutil")
local Layers = require("core/layers")
local Settings = require("core/settings")

local OverlaysTab = {}

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local LOC_RANGE    = 25           -- objects are labelled within this many tiles of the player
local LABEL_WIDTH  = 200
local LABEL_HEIGHT = 18
local LABEL_ABOVE  = 1500         -- how far above the NPC's position the label sits (game units, 1024 is about a tile)
local MAX_ERRORS   = 3            -- an overlay that fails this many times in a row is switched off
local LABEL_COLUMN = 270
local BUTTON_WIDTH = 100

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local controls = {}               -- statusText and the buttons
local on = { npc = false, loc = false, hover = false, tile = false, box = false, layers = false, tips = false, abilities = false }
local errors = { npc = 0, loc = 0, hover = 0, tile = 0, box = 0, layers = 0, tips = 0, abilities = 0 }

local labels = { npc = {}, loc = {} }   -- pools of ui.Text over NPCs and objects
local locDrawCalls = 0
local labelParent = nil
local font = nil                  -- font id for the labels, if one could be found
local fontName = nil
local heardEntry = false          -- whether the hover box has had something to show yet
local readyCalls = 0              -- how often the hover menu event has fired (shown in the status line)
local drawCalls = 0               -- how often the overlay ran (shown in the status line)

local function status(text) UI.setText(controls.statusText, text) end

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
-- reads a field without ever raising an error
local try = UI.try

-- the id of a config, whichever way it is exposed
local function idOf(cfg)
    if cfg == nil then return nil end
    for _, field in ipairs({ "id", "ID", "configID" }) do
        local value = try(cfg, field)
        if type(value) == "number" then return value end
    end
    return nil
end

-- the layer to draw on (see layers.lua)
local layerName = nil
local function gameArea()
    local parent, name = Layers.parent()
    layerName = name
    return parent
end

-- the font for the labels: MUSEO_SANS_15PT_REGULAR (id 30), which the documentation uses in its examples
local function findFont()
    if font then return end
    local ok, value = pcall(function() return id.Font.MUSEO_SANS_15PT_REGULAR end)
    if ok and type(value) == "number" then font, fontName = value, "MUSEO_SANS_15PT_REGULAR"; return end
    ok, value = pcall(function() return config.Font.MUSEO_SANS_15PT_REGULAR.id end)
    if ok and type(value) == "number" then font, fontName = value, "MUSEO_SANS_15PT_REGULAR"; return end
    font, fontName = 30, "30 (MUSEO_SANS_15PT_REGULAR, from the documentation)"
end

-- a failure counts against a toggle; too many in a row turns it off
local turnOff
local function failed(key, err)
    errors[key] = errors[key] + 1
    status("Problem (" .. key .. " " .. errors[key] .. "/" .. MAX_ERRORS .. "): " .. tostring(err))
    if errors[key] >= MAX_ERRORS then
        turnOff(key)
        status("Turned off because it kept failing: " .. tostring(err))
    end
end

----------------------------------------------------------------
-- IDS ABOVE NPCS AND OBJECTS
-- Both use the same code: a pool of text labels, one per thing in view, drawn each frame at the thing's screen position.
-- NPC labels are yellow and object labels are cyan unless another colour is picked (0xRRGGBB; remembered between sessions).
----------------------------------------------------------------
local colours = { npc = 0xFFFF4D, loc = 0x4DFFFF, tile = 0xFFDD00, box = 0xFF6EFF }
local COLOUR_SETTING = { npc = "npcColour", loc = "locColour", tile = "tileColour", box = "boxColour" }

local function colourVector(key)
    local c = colours[key]
    return Vector4.new(((c >> 16) & 255) / 255, ((c >> 8) & 255) / 255, (c & 255) / 255, 1.0)
end

local tileDots, boxDots   -- defined with the floor tile border and the object outlines below
local function setColour(key, value)
    colours[key] = value
    Settings.set(COLOUR_SETTING[key], value)
    local things = (key == "tile" and tileDots) or (key == "box" and boxDots) or labels[key]
    for _, thing in ipairs(things or {}) do pcall(function() thing.colour = colourVector(key) end) end
end

local function getLabel(key, index)
    local pool = labels[key]
    local label = pool[index]
    if label then return label end

    label = ui.Text.new(labelParent)
    label:AlignTo(ui.AlignMode.CENTRE)
    label:SetSize(LABEL_WIDTH, LABEL_HEIGHT)
    if font then label.font = font end
    pcall(function() label.alpha = 1.0 end)
    pcall(function() label.isShadowed = true end)
    pcall(function() label.shadowColour = Vector4.new(0.0, 0.0, 0.0, 1.0) end)
    pcall(function() label.colour = colourVector(key) end)
    pcall(function() label.clickthrough = true end)
    pcall(function() label:MoveToFront() end)
    pool[index] = label
    return label
end

-- "Name (config id)", plus the parent id for a multi-config
local function entityText(entity, fallback, multiField)
    local name = try(entity, "displayName")
    local configID = try(entity, "configID")
    local text = (type(name) == "string" and name ~= "") and name or fallback
    if type(configID) == "number" then text = text .. " (" .. configID .. ")" end
    if try(entity, multiField) == true then
        local parentID = try(entity, "parentConfigID")
        if type(parentID) == "number" then text = text .. " [parent " .. parentID .. "]" end
    end
    return text
end

local function npcText(npc) return entityText(npc, "NPC", "isMultiNPC") end
local function locText(loc) return entityText(loc, "Object", "isMultiLoc") end

-- the objects to label: those within LOC_RANGE tiles of the player (LocList.All() can be very large)
local function nearbyLocs(range)
    local coord
    pcall(function() coord = PlayerList.Self().coordGrid end)
    if not coord then pcall(function() coord = Player.GetEntity().coordGrid end) end
    if coord then
        local ok, list = pcall(function() return LocList.ByDistance(coord, range or LOC_RANGE, true) end)
        if ok and list then return list end
    end
    return LocList.All()
end

-- one pass over a list of entities: each one on screen gets a label above it
local function drawLabels(key, list, textOf)
    local originX, originY, width, height = 0, 0, nil, nil
    local global = try(labelParent, "xyGlobal")
    if global then originX, originY = try(global, "x") or 0, try(global, "y") or 0 end
    local w, h = try(labelParent, "width"), try(labelParent, "height")
    if type(w) == "number" and w > 0 then width = w end    -- a size of 0 means "unknown", so don't clip
    if type(h) == "number" and h > 0 then height = h end

    local seen, projected, shown, firstX, firstY = 0, 0, 0, nil, nil
    for _, entity in ipairs(list) do
        seen = seen + 1
        if entity.isValid then
            local screen = ScreenConvert.Vector3ToScreen(entity.position + Vector3.new(0, LABEL_ABOVE, 0))
            if screen then
                projected = projected + 1
                local x, y = screen.x - originX, screen.y - originY
                local inside = (not width or (x > 0 and x < width)) and (not height or (y > 0 and y < height))
                if inside then
                    shown = shown + 1
                    local label = getLabel(key, shown)
                    label.hidden = false
                    label:SetPos(math.floor(x - LABEL_WIDTH / 2), math.floor(y - LABEL_HEIGHT / 2))
                    local text = textOf(entity)
                    if label.content ~= text then label.content = text end
                    if not firstX then firstX, firstY = math.floor(x), math.floor(y) end
                end
            end
        end
    end
    local pool = labels[key]
    for i = shown + 1, #pool do pool[i].hidden = true end
    return "found " .. seen .. ", projected " .. projected .. ", drawn " .. shown
        .. (firstX and (", first at " .. firstX .. "," .. firstY) or "")
        .. " | area " .. tostring(w) .. "x" .. tostring(h) .. " at " .. originX .. "," .. originY
        .. " | font " .. tostring(fontName)
end

local function drawNpcIds()
    if not on.npc then return end
    drawCalls = drawCalls + 1
    local ok, result = pcall(function() return "NPCs: " .. drawLabels("npc", NPCList.All(), npcText) end)
    if ok then
        errors.npc = 0
        if drawCalls % 50 == 1 then status(result) end
    else
        failed("npc", result)
    end
end

local function drawLocIds()
    if not on.loc then return end
    locDrawCalls = locDrawCalls + 1
    local ok, result = pcall(function() return "Objects: " .. drawLabels("loc", nearbyLocs(), locText) end)
    if ok then
        errors.loc = 0
        if locDrawCalls % 50 == 1 then status(result) end
    else
        failed("loc", result)
    end
end

local function destroyLabels(key)
    for name, pool in pairs(labels) do
        if not key or key == name then
            for _, label in ipairs(pool) do pcall(function() label:Destroy() end) end
            labels[name] = {}
        end
    end
end

----------------------------------------------------------------
-- OBJECT OUTLINES
-- Each nearby object's bounding box is drawn as its twelve edges plus the four lines crossing through the inside, using solid
-- ui.Line components (a line runs corner to corner of its own box; `invert` makes it run the other way). The box comes from the
-- object's `aabb`; if that can't be read the console says what it contains.
----------------------------------------------------------------
local BOX_RANGE = 12              -- objects are outlined within this many tiles of the player
local LINE_WIDTH = 2
local LINES_PER_OBJECT = 16
-- Every line is a dynamic component, and the game allows only 4096 of them in total (shared with every window and plugin: the Dev
-- Tools window and colour pickers fail to open when they run out). So the number of lines is capped.
local MAX_BOX_LINES = 640
boxDots = {}                      -- the lines (named dots because the colour code treats this as a list of things to recolour)
local boxLogged = false

local boxFull = false             -- a line couldn't be made: no more are tried

local function hideBoxDots(from)
    for i = from or 1, #boxDots do pcall(function() boxDots[i].hidden = true end) end
end

local function destroyBoxDots()
    for _, line in ipairs(boxDots) do pcall(function() line:Destroy() end) end
    boxDots, boxFull = {}, false
end

-- the line with this number, made when it doesn't exist yet; nil when the limit is reached or the game won't make another
local function boxLine(index)
    local line = boxDots[index]
    if line then return line end
    if boxFull or index > MAX_BOX_LINES then return nil end
    local ok, made = pcall(function() return ui.Line.new(labelParent) end)
    if not (ok and made) then boxFull = true; return nil end
    line = made
    pcall(function() line.width = LINE_WIDTH end)
    pcall(function() line.colour = colourVector("box") end)
    pcall(function() line.alpha = 1.0 end)
    pcall(function() line.clickthrough = true end)
    boxDots[index] = line
    return line
end

local function numbers(point)
    if not point then return nil end
    local x, y, z = try(point, "x"), try(point, "y"), try(point, "z")
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
    return nil
end

-- the two opposite corners of an entity's bounding box in world units, or nil
local function readBounds(entity)
    local box = try(entity, "aabb")
    if not box then return nil end
    local lox, loy, loz, hix, hiy, hiz
    for _, names in ipairs({ { "min", "max" }, { "minimum", "maximum" }, { "lower", "upper" }, { "minPoint", "maxPoint" },
                             { "minCorner", "maxCorner" }, { "mins", "maxs" }, { "low", "high" } }) do
        local a, b, c = numbers(try(box, names[1]))
        local d, e, f = numbers(try(box, names[2]))
        if a and d then lox, loy, loz, hix, hiy, hiz = a, b, c, d, e, f; break end
    end
    if not lox then
        local lowX, highX = try(box, "minX"), try(box, "maxX")
        if type(lowX) == "number" and type(highX) == "number" then
            lox, hix = lowX, highX
            loy, hiy = try(box, "minY"), try(box, "maxY")
            loz, hiz = try(box, "minZ"), try(box, "maxZ")
        end
    end
    if not lox then
        local cx, cy, cz = numbers(try(box, "centre") or try(box, "center"))
        local ex, ey, ez = numbers(try(box, "extents") or try(box, "halfExtents") or try(box, "halfSize"))
        if cx and ex then lox, loy, loz, hix, hiy, hiz = cx - ex, cy - ey, cz - ez, cx + ex, cy + ey, cz + ez end
    end
    if not (lox and loy and loz and hix and hiy and hiz) then return nil end
    -- relative to the object's position rather than the world?
    local position = try(entity, "position")
    local px, py, pz = numbers(position)
    if px and math.abs(px) > 100000 and math.abs(lox) < 100000 then
        lox, hix, loy, hiy, loz, hiz = lox + px, hix + px, loy + py, hiy + py, loz + pz, hiz + pz
    end
    return lox, loy, loz, hix, hiy, hiz
end

-- says in the console what a bounding box holds, once, when it couldn't be read
local function logBoundsProblem(entity)
    if boxLogged then return end
    boxLogged = true
    local function members(value)
        local list = {}
        local function collect(source) if type(source) == "table" then for key in pairs(source) do list[#list + 1] = tostring(key) end end end
        pcall(collect, value)
        pcall(function() local meta = getmetatable(value); if meta then collect(meta); collect(meta.__index) end end)
        table.sort(list)
        return table.concat(list, ",")
    end
    local box = try(entity, "aabb")
    log("[Overlays] object outline: couldn't read the bounds. entity " .. tostring(entity) .. ": " .. members(entity)
        .. " | aabb " .. tostring(box) .. ": " .. members(box))
end

local CORNER_BITS = {}
for index = 0, 7 do CORNER_BITS[index] = { index & 1, (index >> 1) & 1, (index >> 2) & 1 } end

-- the 12 edges (corners that differ in one bit) and the 4 crossing lines (corners that differ in all three)
local OUTLINE_LINES = {}
for a = 0, 7 do
    for b = a + 1, 7 do
        local differ = (a ~ b)
        local bits = (differ & 1) + ((differ >> 1) & 1) + ((differ >> 2) & 1)
        if bits == 1 or bits == 3 then OUTLINE_LINES[#OUTLINE_LINES + 1] = { a, b } end
    end
end

local function drawOutlines()
    if not on.box then return end
    local ok, result = pcall(function()
        local used = 0
        local originX, originY = 0, 0
        local global = try(labelParent, "xyGlobal")
        if global then originX, originY = try(global, "x") or 0, try(global, "y") or 0 end

        -- a line from one screen point to another: a box with the two points at opposite corners, drawn along one diagonal
        local function addLine(from, to)
            local line = boxLine(used + 1)
            if not line then used = MAX_BOX_LINES; return end
            used = used + 1
            local x1, y1, x2, y2 = from[1] - originX, from[2] - originY, to[1] - originX, to[2] - originY
            line:SetPos(math.floor(math.min(x1, x2)), math.floor(math.min(y1, y2)))
            line:SetSize(math.max(1, math.floor(math.abs(x2 - x1))), math.max(1, math.floor(math.abs(y2 - y1))))
            line.invert = (x2 - x1) * (y2 - y1) < 0
            line.hidden = false
        end

        -- nearest first, and an object is only drawn when all its lines fit, so what is drawn changes smoothly as you move
        local player
        pcall(function() player = PlayerList.Self() end)
        local here = player and try(player, "position")
        local px, pz = here and try(here, "x"), here and try(here, "z")
        local ordered = {}
        for _, entity in ipairs(nearbyLocs(BOX_RANGE)) do
            if entity.isValid then
                local position = try(entity, "position")
                local x, z = position and try(position, "x"), position and try(position, "z")
                local distance = (type(px) == "number" and type(x) == "number") and ((x - px) ^ 2 + (z - pz) ^ 2) or 0
                ordered[#ordered + 1] = { entity = entity, distance = distance }
            end
        end
        table.sort(ordered, function(a, b) return a.distance < b.distance end)
        for _, item in ipairs(ordered) do
            local entity = item.entity
            if used < MAX_BOX_LINES then
                local lox, loy, loz, hix, hiy, hiz = readBounds(entity)
                if not lox then
                    logBoundsProblem(entity)
                else
                    local points, visible = {}, true
                    for index = 0, 7 do
                        local bits = CORNER_BITS[index]
                        local screen = ScreenConvert.Vector3ToScreen(Vector3.new(
                            bits[1] == 0 and lox or hix, bits[2] == 0 and loy or hiy, bits[3] == 0 and loz or hiz))
                        if not screen then visible = false; break end
                        points[index] = { screen.x, screen.y }
                    end
                    if visible then
                        if used + LINES_PER_OBJECT <= MAX_BOX_LINES then
                            for _, line in ipairs(OUTLINE_LINES) do addLine(points[line[1]], points[line[2]]) end
                        end
                    end
                end
            end
        end
        hideBoxDots(used + 1)
    end)
    if ok then
        errors.box = 0
    else
        failed("box", result)
    end
end

----------------------------------------------------------------
-- HOVER DETAILS
----------------------------------------------------------------
-- the id of the interface a component belongs to
local function interfaceOf(component)
    local value = try(component, "interfaceID")
    if type(value) == "number" then return value end
    local iface = try(component, "parentInterface")
    value = iface and try(iface, "id")
    if type(value) == "number" then return value end
    return nil
end

-- "1473:5" (interface:component), plus "dyn 3,12" for a component made while the game runs
local function componentRef(component)
    local text = (interfaceOf(component) and tostring(interfaceOf(component)) or "?") .. ":" .. tostring(try(component, "staticID") or "?")
    local dynamicID = try(component, "dynamicID")
    if type(dynamicID) == "number" and dynamicID >= 0 then
        text = text .. " dyn " .. tostring(try(component, "categoryID")) .. "," .. tostring(dynamicID)
    end
    return text
end

-- a tile the way the game writes coordinates: level,mapSquareX,mapSquareZ,localX,localZ (e.g. 0,51,158,50,30)
local function tileText(gridX, gridZ)
    if type(gridX) ~= "number" or type(gridZ) ~= "number" then return tostring(gridX) .. ", " .. tostring(gridZ) end
    local level = 0
    pcall(function() level = try(PlayerList.Self().coordGrid, "level") or 0 end)
    return level .. "," .. gridX // 64 .. "," .. gridZ // 64 .. "," .. gridX % 64 .. "," .. gridZ % 64
end

-- the lines shown for one menu entry (the thing under the cursor)
local function describeLines(entry)
    local lines = {}
    local function add(text) lines[#lines + 1] = text end

    local fullText = try(entry, "fullText")
    add(type(fullText) == "string" and fullText ~= "" and fullText or "(no text)")

    local npcData = try(entry, "npcData")
    if npcData then
        local npc = try(npcData, "entity")
        if npc then
            add("NPC id: " .. tostring(try(npc, "configID")) .. "    uid: " .. tostring(try(npc, "uid")))
            local parentID = try(npc, "parentConfigID")
            if try(npc, "isMultiNPC") == true and parentID then add("Parent (multi) id: " .. tostring(parentID)) end
        end
    end

    local locData = try(entry, "locData")
    if locData then
        add("Loc id: " .. tostring(idOf(try(locData, "config")) or "?"))
        add("Tile: " .. tileText(try(locData, "coordGridX"), try(locData, "coordGridZ")))
    end

    local objData = try(entry, "objData")
    if objData then
        add("Obj id: " .. tostring(idOf(try(objData, "config")) or "?"))
    end

    local componentData = try(entry, "componentData")
    if componentData then
        local component = try(componentData, "component")
        if component then
            add("Interface: " .. tostring(interfaceOf(component) or "?"))
            add("Component: " .. componentRef(component))
            local typeName = try(component, "type")
            if typeName ~= nil then add("Type: " .. tostring(typeName)) end
            local chain, parent = {}, try(component, "parent")
            while parent and #chain < 8 do
                chain[#chain + 1] = componentRef(parent)
                parent = try(parent, "parent")
            end
            if #chain > 0 then add("Parents: " .. table.concat(chain, " / ")) end
            for _, field in ipairs({ "spriteID", "spriteId", "sprite" }) do
                local sprite = try(component, field)
                if type(sprite) == "number" then add("Sprite: " .. sprite); break end
            end
        end
        local objID = idOf(try(componentData, "objConfig"))
        if objID then add("Obj id: " .. tostring(objID)) end
        local opIndex = try(componentData, "opIndex")
        if opIndex then add("Op: " .. tostring(opIndex)) end
    end

    local groundData = try(entry, "groundData")
    if groundData then
        add("Tile: " .. tileText(try(groundData, "coordGridX"), try(groundData, "coordGridZ")))
    end

    local icons = try(entry, "iconSpriteIDs")
    if type(icons) == "table" and #icons > 0 then
        local list = {}
        for _, spriteID in ipairs(icons) do list[#list + 1] = tostring(spriteID) end
        add("Icon sprites: " .. table.concat(list, ", "))
    end

    return lines
end

-- the box drawn next to the cursor, in the same colours as the Dev Tools window: near-black brown, a gold-brown border,
-- a gold title and cream text
local box = nil                   -- { background, edge, rule, title, body }
local CHAR_WIDTH, LINE_HEIGHT, BOX_PAD = 7.5, 18, 10
local TITLE_HEIGHT = 22
local BOX_OFFSET_X, BOX_OFFSET_Y = 14, 10
local GOLD  = { 0.55, 0.42, 0.22 }

local function makeText(colour)
    local text = ui.Text.new(labelParent)
    if font then text.font = font end
    pcall(function() text:AlignTo(ui.AlignMode.LEFT, ui.AlignMode.TOP) end)
    pcall(function() text.isShadowed = true end)
    pcall(function() text.colour = Vector4.new(colour[1], colour[2], colour[3], 1.0) end)
    return text
end

local function createBox()
    if box then return end
    findFont()
    local background = ui.Rectangle.new(labelParent)
    background.fill = true
    background.colour = Vector4.new(0.09, 0.075, 0.06, 0.97)
    local edge = ui.Rectangle.new(labelParent)
    edge.fill = false
    edge.outlineThickness = 2
    edge.colour = Vector4.new(GOLD[1], GOLD[2], GOLD[3], 1.0)
    local rule = ui.Rectangle.new(labelParent)
    rule.fill = true
    rule.colour = Vector4.new(GOLD[1], GOLD[2], GOLD[3], 0.8)
    local title = makeText({ 1.0, 0.82, 0.45 })
    local body = makeText({ 0.93, 0.87, 0.72 })
    box = { background = background, edge = edge, rule = rule, title = title, body = body }
    for _, part in pairs(box) do
        pcall(function() part.alpha = 1.0 end)
        pcall(function() part.clickthrough = true end)
        pcall(function() part.hidden = true end)
    end
end

local function hideBox()
    if not box then return end
    for _, part in pairs(box) do pcall(function() part.hidden = true end) end
end

local function destroyBox()
    if not box then return end
    for _, part in pairs(box) do pcall(function() part:Destroy() end) end
    box = nil
end

-- Draws the box with its bottom-left corner just up and to the right of the cursor, growing up and to the right.
-- It is kept inside the game area, and goes below the cursor instead when there is no room above.
-- lines[1] is the title; the rest go under it.
local function showBox(lines)
    createBox()
    local widest = 0
    for _, line in ipairs(lines) do widest = math.max(widest, #line) end
    local bodyLines = math.max(0, #lines - 1)
    local width = math.max(160, math.floor(widest * CHAR_WIDTH) + BOX_PAD * 2)
    local height = BOX_PAD + TITLE_HEIGHT + (bodyLines > 0 and (bodyLines * LINE_HEIGHT + 4) or 0) + BOX_PAD

    local originX, originY = 0, 0
    local global = try(labelParent, "xyGlobal")
    if global then originX, originY = try(global, "x") or 0, try(global, "y") or 0 end

    local mouseX, mouseY = 40, 200
    local mouse = Mouse and Mouse.IsAvailable() and Mouse.GetPosition()
    if mouse then mouseX, mouseY = mouse.x - originX, mouse.y - originY end

    local x, y = mouseX + BOX_OFFSET_X, mouseY - BOX_OFFSET_Y - height
    local areaW, areaH = try(labelParent, "width"), try(labelParent, "height")
    if y < 0 then y = mouseY + BOX_OFFSET_Y end
    if type(areaW) == "number" and areaW > 0 then x = math.max(0, math.min(x, areaW - width - 4)) end
    if type(areaH) == "number" and areaH > 0 then y = math.max(0, math.min(y, areaH - height - 4)) end
    x, y = math.floor(x), math.floor(y)

    box.background:SetPos(x, y); box.background:SetSize(width, height)
    box.edge:SetPos(x, y);       box.edge:SetSize(width, height)
    box.title:SetPos(x + BOX_PAD, y + BOX_PAD); box.title:SetSize(width - BOX_PAD * 2, TITLE_HEIGHT)
    box.rule:SetPos(x + BOX_PAD, y + BOX_PAD + TITLE_HEIGHT - 2); box.rule:SetSize(width - BOX_PAD * 2, 1)
    box.body:SetPos(x + BOX_PAD, y + BOX_PAD + TITLE_HEIGHT + 4)
    box.body:SetSize(width - BOX_PAD * 2, math.max(1, bodyLines * LINE_HEIGHT))

    if box.title.content ~= lines[1] then box.title.content = lines[1] end
    local rest = {}
    for i = 2, #lines do rest[#rest + 1] = lines[i] end
    local content = table.concat(rest, "\n")
    if box.body.content ~= content then box.body.content = content end

    box.rule.hidden = bodyLines == 0
    for _, part in ipairs({ box.background, box.edge, box.title, box.body }) do part.hidden = false end
    if bodyLines > 0 then box.rule.hidden = false end
    -- back to front, so the text ends up on top of the background
    for _, part in ipairs({ box.background, box.edge, box.rule, box.title, box.body }) do
        pcall(function() part:MoveToFront() end)
    end
    return x, y, width, height
end

----------------------------------------------------------------
-- FLOOR TILE BORDER
-- The tile under the cursor is outlined with a ring of small dots joining its four corners (the corners are worked out from
-- the tile's grid position, relative to the player, at the player's height; so on a slope the outline floats a little).
----------------------------------------------------------------
local TILE_SIZE = 512             -- game units in one tile
local DOTS_PER_EDGE, DOT_SIZE = 12, 3
tileDots = {}

local function hideTile()
    for _, dot in ipairs(tileDots) do pcall(function() dot.hidden = true end) end
end

local tileHeights = nil           -- { key = "x,z", heights = { four corner heights } } for the tile last outlined

local function destroyTile()
    tileHeights = nil
    for _, dot in ipairs(tileDots) do pcall(function() dot:Destroy() end) end
    tileDots = {}
end

local function tileDot(index)
    local dot = tileDots[index]
    if dot then return dot end
    dot = ui.Rectangle.new(labelParent)
    dot.fill = true
    dot:SetSize(DOT_SIZE, DOT_SIZE)
    pcall(function() dot.colour = colourVector("tile") end)
    pcall(function() dot.alpha = 1.0 end)
    pcall(function() dot.clickthrough = true end)
    tileDots[index] = dot
    return dot
end

-- Working out where a tile corner is on the screen, at the right height.
-- ScreenConvert.ScreenToCoordFine says which ground point is under a screen position, height included. The cursor is on the hovered
-- tile, so that gives the tile's height; then each corner is placed at that height, projected, and the ground under that spot on the
-- screen is asked for again, a few times over, so every corner settles at its own height (a tile on stairs or a slope is tilted).
local HEIGHT_PASSES = 8
local CORNERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

-- the ground height under a screen position, or nil
local function groundHeightAt(screenX, screenY)
    local ok, fine = pcall(function() return ScreenConvert.ScreenToCoordFine(screenX, screenY) end)
    local height = ok and fine and try(fine, "y")
    if type(height) == "number" then return height end
    return nil
end

local function cornerWorld(cornerX, cornerZ, height)
    return Vector3.new(cornerX * TILE_SIZE, height, cornerZ * TILE_SIZE)
end

-- settles one corner's height, starting from a guess
local function cornerHeight(cornerX, cornerZ, startHeight)
    local height = startHeight
    for _ = 1, HEIGHT_PASSES do
        local screen = ScreenConvert.Vector3ToScreen(cornerWorld(cornerX, cornerZ, height))
        if not screen then return nil end
        height = groundHeightAt(screen.x, screen.y) or height
    end
    return height
end

-- The four corner heights are worked out once, when the cursor moves onto a tile, and kept while it stays on that tile: they depend
-- on the ground, not on where in the tile the cursor is, so the outline holds still. (Only the screen positions are redone each time.)
local function heightsFor(gx, gz)
    local key = gx .. "," .. gz
    if tileHeights and tileHeights.key == key then return tileHeights.heights end
    local mouse = Mouse and Mouse.IsAvailable() and Mouse.GetPosition()
    local startHeight = mouse and groundHeightAt(mouse.x, mouse.y)
    if not startHeight then
        local player
        pcall(function() player = PlayerList.Self() end)
        startHeight = player and try(player, "position") and player.position.y
    end
    if not startHeight then return nil end
    local heights = {}
    for i, offset in ipairs(CORNERS) do
        heights[i] = cornerHeight(gx + offset[1], gz + offset[2], startHeight)
        if not heights[i] then return nil end
    end
    tileHeights = { key = key, heights = heights }
    return heights
end

local function drawTile(gx, gz)
    local heights = heightsFor(gx, gz)
    if not heights then return hideTile() end

    local originX, originY = 0, 0
    local global = try(labelParent, "xyGlobal")
    if global then originX, originY = try(global, "x") or 0, try(global, "y") or 0 end

    local corners = {}
    for i, offset in ipairs(CORNERS) do
        local screen = ScreenConvert.Vector3ToScreen(cornerWorld(gx + offset[1], gz + offset[2], heights[i]))
        if not screen then return hideTile() end
        corners[i] = { screen.x - originX, screen.y - originY }
    end

    local index = 0
    for edge = 1, 4 do
        local from, to = corners[edge], corners[edge % 4 + 1]
        for step = 0, DOTS_PER_EDGE - 1 do
            local fraction = step / DOTS_PER_EDGE
            index = index + 1
            local dot = tileDot(index)
            dot:SetPos(math.floor(from[1] + (to[1] - from[1]) * fraction - DOT_SIZE / 2),
                       math.floor(from[2] + (to[2] - from[2]) * fraction - DOT_SIZE / 2))
            dot.hidden = false
            pcall(function() dot:MoveToFront() end)
        end
    end
end

-- outlines the tile under the cursor (the top menu entry's ground data), or hides the outline
local function updateTile(top)
    local data = top and try(top, "groundData")
    local gx, gz = data and try(data, "coordGridX"), data and try(data, "coordGridZ")
    if type(gx) ~= "number" or type(gz) ~= "number" then return hideTile() end
    -- The menu's tile is picked by the game in its own way, and on a steep slope it can be the tile below the one the cursor is
    -- visibly over. So the tile is worked out from the ground point under the cursor instead (the same one the outline's height
    -- comes from); the menu's tile is only used when that can't be read.
    local mouse = Mouse and Mouse.IsAvailable() and Mouse.GetPosition()
    if mouse then
        local ok, under = pcall(function() return ScreenConvert.ScreenToCoordGrid(mouse.x, mouse.y) end)
        local ux, uz = ok and under and try(under, "x"), ok and under and try(under, "z")
        if type(ux) == "number" and type(uz) == "number" then gx, gz = ux, uz end
    end
    drawTile(gx, gz)
end

local function onMiniMenuReady(event)
    if not (on.hover or on.tile) then return end
    readyCalls = readyCalls + 1
    local menu = event.miniMenu
    local top = nil
    local okTop = pcall(function()
        if not menu.isOpen then top = menu.entries[menu.entryCount] end
    end)

    if on.tile then
        local ok, err = pcall(updateTile, top)
        if ok then errors.tile = 0 else failed("tile", err) end
    end

    if on.hover then
        local ok, err = pcall(function()
            if top then
                heardEntry = true
                local lines = describeLines(top)
                local x, y, w, h = showBox(lines)
                if readyCalls % 50 == 1 then
                    status("Hover box: " .. readyCalls .. " menu updates. Top entry: " .. tostring(lines[1])
                        .. ". Box drawn at " .. x .. "," .. y .. " size " .. w .. "x" .. h)
                end
            elseif not heardEntry and readyCalls < 200 then
                -- nothing hovered yet: leave the "ready" box where it is for a few seconds so you can see boxes work at all
                if readyCalls % 50 == 1 then status("Hover box: " .. readyCalls .. " menu updates, nothing under the cursor yet") end
            else
                hideBox()
                if readyCalls % 50 == 1 then status("Hover box: " .. readyCalls .. " menu updates, nothing under the cursor (or the menu is open)") end
            end
        end)
        if ok and okTop then errors.hover = 0 else failed("hover", err or "couldn't read the menu") end
    end
end

----------------------------------------------------------------
-- TURNING THINGS ON AND OFF
----------------------------------------------------------------
----------------------------------------------------------------
-- HIDING THE GAME'S HOVER TOOLTIP
-- The tooltip is the TOPLEVEL_V2__OPTEXT_BUBBLE component. It is hidden every drawn frame (the game shows it again
-- each time something new is hovered) and shown again when the toggle is turned off.
----------------------------------------------------------------
local function tooltipBubble()
    local ok, component = pcall(function() return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__OPTEXT_BUBBLE) end)
    return ok and component or nil
end

local function hideTooltipBubble()
    local component = tooltipBubble()
    if component and try(component, "hidden") ~= true then pcall(function() component.hidden = true end) end
end

-- The ability tooltip: the description text and every component above it inside the same interface (the tooltip's frame
-- and background), looked up fresh each time so no component is held between frames.
local ABILITY_DEPTH = 8
local function abilityTooltipParts()
    local parts = {}
    local ok, component = pcall(function() return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_ABILITY_BOOK_TOOLTIP__DESC_TEXT) end)
    if not ok or not component then return parts end
    local interfaceID = try(component, "interfaceID")
    parts[1] = component
    for _ = 1, ABILITY_DEPTH do
        local parent = try(component, "parentStatic") or try(component, "parent")
        if not parent or parent == component then break end
        local parentInterface = try(parent, "interfaceID")
        if interfaceID ~= nil and parentInterface ~= nil and parentInterface ~= interfaceID then break end
        parts[#parts + 1] = parent
        component = parent
    end
    return parts
end

local function setAbilityTooltipHidden(hidden)
    for _, part in ipairs(abilityTooltipParts()) do
        if hidden then
            if try(part, "hidden") ~= true then pcall(function() part.hidden = true end) end
        else
            pcall(function() part.hidden = false end)
        end
    end
end

local function hideAbilityTooltip() setAbilityTooltipHidden(true) end

-- "where does each layer draw": a labelled box on every layer, so you can see which are in front of the game's tooltips
local layerBoxes = {}
local function destroyLayerBoxes()
    for _, part in ipairs(layerBoxes) do pcall(function() part:Destroy() end) end
    layerBoxes = {}
end

local function showLayerBoxes()
    destroyLayerBoxes()
    findFont()
    local shown = 0
    for i, layer in ipairs(Layers.all()) do
        local ok = pcall(function()
            local background = ui.Rectangle.new(layer.component)
            background.fill = true
            background.colour = Vector4.new(0.09, 0.075, 0.06, 0.97)
            background:SetPos(30, 90 + (i - 1) * 30); background:SetSize(430, 26)
            local text = ui.Text.new(layer.component)
            if font then text.font = font end
            pcall(function() text:AlignTo(ui.AlignMode.LEFT, ui.AlignMode.CENTRE) end)
            pcall(function() text.colour = Vector4.new(1.0, 0.82, 0.45, 1.0) end)
            text:SetPos(38, 90 + (i - 1) * 30); text:SetSize(414, 26)
            text.content = i .. ". " .. layer.name
            layerBoxes[#layerBoxes + 1] = background
            layerBoxes[#layerBoxes + 1] = text
            pcall(function() background:MoveToFront() end)
            pcall(function() text:MoveToFront() end)
            shown = shown + 1
        end)
    end
    return shown
end

-- every toggle is a row like on the Events tab: a label, then a button that says what the next click does
local function refresh(key)
    UI.setButton(controls[key], on[key] and "Turn off" or "Turn on", on[key] and "negative" or "positive")
end

local function hoverSubscribed()
    return on.hover or on.tile
end

function turnOff(key)
    on[key] = false
    errors[key] = 0
    if key == "layers" then
        destroyLayerBoxes()
    elseif key == "tips" then
        pcall(function() Event.Draw.Unsubscribe("devtools_overlay_tips") end)
        local component = tooltipBubble()
        if component then pcall(function() component.hidden = false end) end
    elseif key == "abilities" then
        pcall(function() Event.Draw.Unsubscribe("devtools_overlay_abilities") end)
        setAbilityTooltipHidden(false)
    elseif key == "box" then
        pcall(function() Event.Draw.Unsubscribe("devtools_overlay_box") end)
        destroyBoxDots()
    elseif key == "npc" then
        pcall(function() Event.Draw.Unsubscribe("devtools_overlay_npc") end)
        destroyLabels("npc")
    elseif key == "loc" then
        pcall(function() Event.Draw.Unsubscribe("devtools_overlay_loc") end)
        destroyLabels("loc")
    else
        if key == "hover" then destroyBox() end
        if key == "tile" then destroyTile() end
        if not hoverSubscribed() then
            pcall(function() Event.MiniMenuReady.Unsubscribe("devtools_overlay_hover") end)
        end
    end
    refresh(key)
end

local function turnOn(key)
    if key == "layers" then
        local count = showLayerBoxes()
        if count == 0 then return status("Couldn't draw on any layer") end
        status(count .. " layers marked. Hover something so the game's tooltip appears: the layers whose label stays readable over it are in front. Pick one in the dropdown above.")
    elseif key == "tips" then
        local ok, err = pcall(function() Event.Draw.Subscribe("devtools_overlay_tips", hideTooltipBubble) end)
        if not ok then return status("Couldn't listen for events: " .. tostring(err)) end
        status("Hiding the game's hover tooltip")
    elseif key == "abilities" then
        local ok, err = pcall(function() Event.Draw.Subscribe("devtools_overlay_abilities", hideAbilityTooltip) end)
        if not ok then return status("Couldn't listen for events: " .. tostring(err)) end
        status("Hiding the ability tooltip")
    elseif key == "npc" then
        labelParent = gameArea()
        if not labelParent then return status("Couldn't find the game area to draw on") end
        findFont()
        local ok, err = pcall(function() Event.Draw.Subscribe("devtools_overlay_npc", drawNpcIds) end)
        if not ok then return status("Couldn't listen for Draw: " .. tostring(err)) end
        drawCalls = 0
        status("NPC labels on (layer " .. tostring(layerName) .. "), waiting for the first frame..." .. (fontName and (" (font " .. fontName .. ")") or " (no font found, using the default)"))
    elseif key == "box" then
        labelParent = gameArea()
        if not labelParent then return status("Couldn't find the game area to draw on") end
        local ok, err = pcall(function() Event.Draw.Subscribe("devtools_overlay_box", drawOutlines) end)
        if not ok then return status("Couldn't listen for Draw: " .. tostring(err)) end
        boxLogged = false
        status("Outlining objects within " .. BOX_RANGE .. " tiles (layer " .. tostring(layerName) .. ")")
    elseif key == "loc" then
        labelParent = gameArea()
        if not labelParent then return status("Couldn't find the game area to draw on") end
        findFont()
        local ok, err = pcall(function() Event.Draw.Subscribe("devtools_overlay_loc", drawLocIds) end)
        if not ok then return status("Couldn't listen for Draw: " .. tostring(err)) end
        locDrawCalls = 0
        status("Object labels on (within " .. LOC_RANGE .. " tiles), waiting for the first frame...")
    else
        if key == "hover" or key == "tile" then
            labelParent = gameArea()
            if not labelParent then return status("Couldn't find the game area to draw on") end
        end
        local wasListening = hoverSubscribed()
        if not wasListening then
            local ok, err = pcall(function() Event.MiniMenuReady.Subscribe("devtools_overlay_hover", onMiniMenuReady) end)
            if not ok then return status("Couldn't listen for the menu: " .. tostring(err)) end
        end
        readyCalls = 0
        heardEntry = false
        if key == "hover" then
            local ok, err = pcall(function() showBox({ "Hover details", "Hover over an NPC, item or interface" }) end)
            if not ok then
                status("Couldn't draw the box: " .. tostring(err))
                destroyBox()
                return
            end
        end
        if key == "hover" then
            status("Hover box on (layer " .. tostring(layerName) .. ") - you should see a box now, then it follows what you hover")
        elseif key == "tile" then
            status("Highlighting the floor tile under the cursor (layer " .. tostring(layerName) .. ")")
        else
            status("Hovered details are printed to the console")
        end
    end
    on[key] = true
    errors[key] = 0
    refresh(key)
end

local function toggle(key)
    if on[key] then
        turnOff(key)
        status("")
    else
        -- the hover box replaces the game's tooltip, so the game's own tooltip is hidden as well
        if key == "hover" and not on.tips then turnOn("tips") end
        if key == "hover" and not on.abilities then turnOn("abilities") end
        turnOn(key)
    end
    if key == "tile" then Settings.set("tileOn", on.tile and 1 or 0) end
end

-- a different layer: everything drawn is thrown away and made again on the new one
local function onLayerChosen(chosenId)
    destroyBox()
    destroyTile()
    destroyBoxDots()
    destroyLabels()
    labelParent = nil
    Layers.set(chosenId)
    if on.npc or on.loc or on.hover or on.tile or on.box then labelParent = gameArea() end
    status("Drawing on " .. tostring((Layers.names())[chosenId]))
end

----------------------------------------------------------------
-- CALLED BY THE WINDOW
----------------------------------------------------------------
function OverlaysTab.build(page)
    page:AddText({ text = "Show extra information in the game itself. Everything starts off." })
    UI.heading(page, "Draw on layer")
    page:AddText({ text = "If boxes or labels appear behind other interfaces, try another layer. The Dev Tools window itself keeps its layer until it is next opened." })
    local layerEntries = {}
    for i, name in ipairs(Layers.names()) do layerEntries[i] = { label = name, id = i } end
    page:AddComboBox({
        entries = layerEntries, selectedID = Layers.index(), width = 420,
        onChange = function(_, chosenId) onLayerChosen(chosenId) end,
    })
    page:AddDivider(UI.TIGHT_DIVIDER)

    for key, setting in pairs(COLOUR_SETTING) do colours[key] = Settings.get(setting, colours[key]) end

    local SWATCH, SWATCH_GAP = 24, 0
    local PICKER_GAP = 70         -- the gap after a button that has a colour picker (the spacing is set on the item before the picker)
    -- a colour picker to the right of a toggle's button
    local function addPicker(key, tip)
        pcall(function()
            page:AddColourPicker({
                value = colours[key] * 256 + 255, alphaSlider = false, buttonSize = SWATCH, inline = true,
                columnGap = SWATCH_GAP, tooltip = tip, windowTitle = tip,
                onChange = function(_, colour)
                    if type(colour) == "number" then setColour(key, math.floor(colour) // 256) end
                end,
            })
        end)
    end

    local function toggleButton(key, label, description, tip, pickerKey, pickerTip)
        page:AddText({ text = label, width = LABEL_COLUMN, columnGap = 0, tooltip = tip or description })
        controls[key] = page:AddFancyButton(on[key] and "Turn off" or "Turn on", function() toggle(key) end, {
            variant = on[key] and "negative" or "positive", width = BUTTON_WIDTH, inline = true, columnGap = pickerKey and PICKER_GAP or 0, tooltip = tip or description,
        })
        if pickerKey then addPicker(pickerKey, pickerTip) end
    end

    toggleButton("npc", "Show NPC IDs above heads:", "Puts the name and config id over every NPC in view (yellow).",
        "Draws a label above each NPC's head", "npc", "NPC label colour")
    toggleButton("loc", "Show object IDs above objects:", "Puts the name and config id over every object near you (cyan).",
        "Draws a label above each object within " .. LOC_RANGE .. " tiles", "loc", "Object label colour")
    toggleButton("box", "Show object outlines:", "Draws a box around every nearby object, with lines crossing through it.",
        "Outlines each object within " .. BOX_RANGE .. " tiles with its bounding box and a cross through the inside",
        "box", "Object outline colour")
    toggleButton("hover", "Show component details on hover:", "Draws a brown box next to the cursor with the details of whatever you hover over.",
        "Shows the NPC / scenery / item ids, the interface and component, parent components and sprites.",
        nil, nil)
    toggleButton("tile", "Highlight tile on hover:", "Outlines the floor tile under the cursor.",
        "Outlines the floor tile under the cursor, tilted to follow slopes and stairs. Remembered between sessions.",
        "tile", "Tile highlight colour")
    toggleButton("tips", "Hide item tooltips:", "Hides the game's own hover tooltip.",
        "Hides the hover text bubble every frame while this is on")
    toggleButton("abilities", "Hide ability tooltips:", "Hides the combat ability tooltip.",
        "Hides the ability book tooltip text every frame while this is on")

    page:AddDivider(UI.TIGHT_DIVIDER)
    toggleButton("layers", "Display Layers:", "Puts a labelled box on every layer, to show which layers are drawn in front of the game's tooltips.",
        "Boxes appear at the top left of the game screen")

    page:AddDivider(UI.TIGHT_DIVIDER)
    controls.statusText = page:AddText({ text = "" })
end

-- the plugin has started: the tile highlight comes back on if it was left on
function OverlaysTab.start()
    for key, setting in pairs(COLOUR_SETTING) do colours[key] = Settings.get(setting, colours[key]) end
    if Settings.get("tileOn", 0) == 1 and not on.tile then pcall(turnOn, "tile") end
end

function OverlaysTab.release()
    controls = {}
end

function OverlaysTab.onVarChanged() end
function OverlaysTab.onScanProgress() end

-- the plugin is shutting down: remove everything
function OverlaysTab.shutdown()
    for _, key in ipairs({ "npc", "loc", "box", "hover", "tile", "layers", "tips", "abilities" }) do
        if on[key] then turnOff(key) end
    end
end

return OverlaysTab