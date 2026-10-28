local rsprite = require("rsprite/src/app/init").Public
local Client = require("finder/src/services/client")
local SizeButtons = require("finder/src/components/size_buttons")
local TextBox = require("finder/src/components/text_box")
local FinderState = require("finder/src/features/finder/finder_state")
local HiddenSprite = require("finder/src/utils/hidden_sprite")
local TextFit = require("finder/src/utils/text_fit")
local Theme = require("finder/src/utils/theme")

local DetailPanel = {}

local PREVIEW_BOX = 96
local CONTROL_SIZE = 24
local BACKGROUND_BUTTON_SIZE = 18
local STEPPER_GAP = 6
local VARIANT_GAP = 2
local VARIANT_HEIGHT = 16
local SIZE_BUTTON_WIDTH = 44
local SIZE_BUTTON_GAP = 3
local SIZE_BUTTON_HEIGHT = 24
local NAME_LINES = 3
local NAME_LINE_HEIGHT = 16
local FACT_GAP = 2
local LINE_HEIGHT = 17
local FACT_LABEL_WIDTH = 56
local LABEL_HEIGHT = 14
local FIELD_HEIGHT = 24
local FIELD_GAP = 4
local HINT_HEIGHT = 16
local SECTION_GAP = 6
local UNKNOWN_SIZE = "Unknown"
local NONE = "None"
local NOTHING_SELECTED = "Pick a sprite"
local HINT = "Click a box, then Ctrl+A and Ctrl+C"
local FACT_LABELS = { "Id", "Size", "Tags", "Aliases" }
local COPY_LABELS = { "Name", "Get", "Draw", "PrettyUI" }
local COPY_ROW_HEIGHT = LABEL_HEIGHT + FIELD_HEIGHT + FIELD_GAP

DetailPanel.ADD_FAVOURITE = "Add to favourites"
DetailPanel.REMOVE_FAVOURITE = "Remove from favourites"
DetailPanel.BACKGROUND_TOOLTIP = "Preview background"
DetailPanel.CHECKER_RESOURCE = "checker"
DetailPanel.CONTROL_SIZE = CONTROL_SIZE

DetailPanel.HEIGHT = PREVIEW_BOX
    + VARIANT_GAP
    + VARIANT_HEIGHT
    + SECTION_GAP
    + SIZE_BUTTON_HEIGHT
    + SECTION_GAP
    + NAME_LINES * NAME_LINE_HEIGHT
    + FACT_GAP
    + #FACT_LABELS * LINE_HEIGHT
    + SECTION_GAP
    + #COPY_LABELS * COPY_ROW_HEIGHT
    + HINT_HEIGHT

local function joined(items)
    if items == nil or #items == 0 then
        return NONE
    end
    return table.concat(items, ", ")
end

local function sizeText(entry)
    if entry.width == nil or entry.height == nil then
        return UNKNOWN_SIZE
    end
    return string.format("%d x %d", entry.width, entry.height)
end

local function measureWith(fontId)
    return function(text)
        if fontId == nil then
            return nil
        end
        return Client.TextWidth(fontId, text)
    end
end

local function copyTexts(name, previewSize)
    return {
        Name = name,
        Get = FinderState.GetText(name),
        Draw = FinderState.DrawText(name, previewSize),
        PrettyUI = FinderState.PrettyText(name, previewSize),
    }
end

local function buildBackgrounds(parent, square)
    local function layer(colour, hidden)
        return Client.NewRectangle(parent, {
            x = square.x,
            y = square.y,
            width = square.width,
            height = square.height,
            colour = colour,
            hidden = hidden,
        })
    end
    local backgrounds = {
        dark = layer(Theme.TILE, false),
        light = layer(Theme.PREVIEW_LIGHT, true),
        checker = Client.NewSprite(parent, {
            x = square.x,
            y = square.y,
            width = square.width,
            height = square.height,
            tiling = true,
        }),
    }
    Client.Set(backgrounds.checker, "sprite", Client.OwnResource(DetailPanel.CHECKER_RESOURCE))
    Client.Set(backgrounds.checker, "hidden", true)
    return backgrounds
end

function DetailPanel.New(parent, layout, handlers)
    local panel = {
        previews = {},
        nameLines = {},
        factValues = {},
        copyFields = {},
        copyTexts = {},
    }
    local x = layout.x
    local width = layout.width
    local bodyFont = Client.Font(Theme.BODY_FONT)
    local nameFont = Client.Font(Theme.NAME_FONT)
    local measureBody = measureWith(bodyFont)
    local measureName = measureWith(nameFont)
    local valueWidth = width - FACT_LABEL_WIDTH

    local boxX = x + math.floor((width - PREVIEW_BOX) / 2)
    local y = layout.y
    panel.backgrounds =
        buildBackgrounds(parent, { x = boxX, y = y, width = PREVIEW_BOX, height = PREVIEW_BOX })
    for _, size in ipairs(FinderState.PREVIEW_SIZES) do
        local offset = math.floor((PREVIEW_BOX - size) / 2)
        panel.previews[size] =
            Client.Call("drawing a preview", rsprite.Draw, parent, HiddenSprite.SOURCE, {
                x = boxX + offset,
                y = y + offset,
                size = size,
                placeholder = false,
            })
    end

    local stepperY = y + math.floor((PREVIEW_BOX - CONTROL_SIZE) / 2)
    local previousVariantX = boxX - STEPPER_GAP - CONTROL_SIZE
    local nextVariantX = boxX + PREVIEW_BOX + STEPPER_GAP
    panel.star = Client.Call(
        "creating the favourite star",
        prettyui.SpriteButton.new,
        parent,
        "STAR",
        function(_, enabled)
            handlers.onStar(enabled)
        end,
        {
            x = x,
            y = layout.y,
            size = CONTROL_SIZE,
            toggleable = true,
            disabled = true,
            tooltip = DetailPanel.ADD_FAVOURITE,
        }
    )
    panel.backgroundButton = Client.Call(
        "creating the preview background button",
        prettyui.SpriteButton.new,
        parent,
        "SWAP",
        function()
            handlers.onCycleBackground()
        end,
        {
            x = x + width - BACKGROUND_BUTTON_SIZE,
            y = layout.y,
            size = BACKGROUND_BUTTON_SIZE,
            tooltip = DetailPanel.BACKGROUND_TOOLTIP,
        }
    )

    y = y + PREVIEW_BOX + VARIANT_GAP
    panel.variantText = Client.NewText(parent, {
        x = x,
        y = y,
        width = width,
        height = VARIANT_HEIGHT,
        font = bodyFont,
        colour = Theme.TEXT,
        centred = true,
        hidden = true,
    })

    y = y + VARIANT_HEIGHT + SECTION_GAP
    panel.sizeButtons = SizeButtons.New(parent, {
        x = x,
        y = y,
        buttonWidth = SIZE_BUTTON_WIDTH,
        gap = SIZE_BUTTON_GAP,
        height = SIZE_BUTTON_HEIGHT,
    }, FinderState.PREVIEW_SIZES, handlers.onPreviewSize)

    y = y + SIZE_BUTTON_HEIGHT + SECTION_GAP
    for line = 1, NAME_LINES do
        panel.nameLines[line] = Client.NewText(parent, {
            x = x,
            y = y + (line - 1) * NAME_LINE_HEIGHT,
            width = width,
            height = NAME_LINE_HEIGHT,
            font = nameFont,
            colour = Theme.GOLD,
        })
    end

    y = y + NAME_LINES * NAME_LINE_HEIGHT + FACT_GAP
    for position, label in ipairs(FACT_LABELS) do
        local rowY = y + (position - 1) * LINE_HEIGHT
        Client.NewText(parent, {
            x = x,
            y = rowY,
            width = FACT_LABEL_WIDTH,
            height = LINE_HEIGHT,
            text = label,
            font = bodyFont,
            colour = Theme.MUTED,
        })
        panel.factValues[label] = Client.NewText(parent, {
            x = x + FACT_LABEL_WIDTH,
            y = rowY,
            width = valueWidth,
            height = LINE_HEIGHT,
            font = bodyFont,
            colour = Theme.TEXT,
        })
    end

    y = y + #FACT_LABELS * LINE_HEIGHT + SECTION_GAP
    for position, label in ipairs(COPY_LABELS) do
        local labelY = y + (position - 1) * COPY_ROW_HEIGHT
        Client.NewText(parent, {
            x = x,
            y = labelY,
            width = width,
            height = LABEL_HEIGHT,
            text = label,
            font = bodyFont,
            colour = Theme.MUTED,
        })
        panel.copyTexts[label] = ""
        local field
        field = TextBox.New(parent, {
            x = x,
            y = labelY + LABEL_HEIGHT,
            width = width,
            height = FIELD_HEIGHT,
        }, function(text)
            local expected = panel.copyTexts[label]
            if text ~= expected then
                field.SetText(expected)
            end
        end)
        panel.copyFields[label] = field
    end

    y = y + #COPY_LABELS * COPY_ROW_HEIGHT
    panel.hintText = Client.NewText(parent, {
        x = x,
        y = y,
        width = width,
        height = HINT_HEIGHT,
        text = HINT,
        font = bodyFont,
        colour = Theme.MUTED,
    })

    function panel.WriteCopyFields()
        for label, field in pairs(panel.copyFields) do
            field.SetText(panel.copyTexts[label])
        end
    end

    function panel.ShowBackground(background)
        for name, component in pairs(panel.backgrounds) do
            Client.Set(component, "hidden", name ~= background)
        end
    end

    local function variantButton(spriteName, step, buttonX)
        return Client.Call(
            "creating a variant button",
            prettyui.SpriteButton.new,
            parent,
            spriteName,
            function()
                handlers.onStepVariant(step)
            end,
            { x = buttonX, y = stepperY, size = CONTROL_SIZE }
        )
    end

    local function removeVariantButtons()
        for _, key in ipairs({ "previousVariant", "nextVariant" }) do
            local button = panel[key]
            panel[key] = nil
            if button ~= nil then
                Client.Call("removing a variant button", function()
                    button:Destroy()
                end)
            end
        end
    end

    local function showStepper(step)
        Client.Set(panel.variantText, "hidden", step == nil)
        if step == nil then
            removeVariantButtons()
            return
        end
        if panel.previousVariant == nil then
            panel.previousVariant = variantButton("ARROW_LEFT", -1, previousVariantX)
            panel.nextVariant = variantButton("ARROW_RIGHT", 1, nextVariantX)
        end
        Client.Set(panel.variantText, "content", FinderState.VariantLabel(step))
        Client.Call("updating the variant buttons", function()
            panel.previousVariant:SetDisabled(step.index <= 1)
            panel.nextVariant:SetDisabled(step.index >= step.count)
        end)
    end

    local function showName(text)
        local lines = TextFit.Wrap(text, width, measureName, NAME_LINES)
        for line, component in ipairs(panel.nameLines) do
            Client.Set(component, "content", lines[line] or "")
        end
    end

    local function showStar(starred)
        Client.Call("updating the favourite star", function()
            panel.star:SetDisabled(not starred)
            panel.star:SetTooltip(
                starred and DetailPanel.REMOVE_FAVOURITE or DetailPanel.ADD_FAVOURITE
            )
        end)
    end

    function panel.Show(entry, details)
        local previewSize = details.previewSize
        for size, preview in pairs(panel.previews) do
            if entry ~= nil and size == previewSize then
                Client.Call("showing the preview", rsprite.SetSource, preview, entry.name)
            else
                Client.Call(
                    "hiding a preview",
                    rsprite.SetSource,
                    preview,
                    HiddenSprite.SOURCE,
                    HiddenSprite.OPTIONS
                )
            end
        end
        panel.sizeButtons.Light(previewSize)
        panel.ShowBackground(details.background)
        showStepper(entry ~= nil and details.variantStep or nil)
        showStar(entry ~= nil and details.starred == true)
        if entry == nil then
            showName(NOTHING_SELECTED)
            for _, value in pairs(panel.factValues) do
                Client.Set(value, "content", "")
            end
            for label in pairs(panel.copyTexts) do
                panel.copyTexts[label] = ""
            end
        else
            showName(entry.name)
            local facts = {
                Id = tostring(entry.id),
                Size = sizeText(entry),
                Tags = joined(entry.tags),
                Aliases = joined(entry.aliases),
            }
            for label, value in pairs(panel.factValues) do
                Client.Set(value, "content", TextFit.Fit(facts[label], valueWidth, measureBody))
            end
            panel.copyTexts = copyTexts(entry.name, previewSize)
        end
        panel.WriteCopyFields()
    end

    return panel
end

return DetailPanel
