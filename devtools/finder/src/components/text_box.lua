local ClearButton = require("finder/src/components/clear_button")
local Client = require("finder/src/services/client")
local Theme = require("finder/src/utils/theme")

local TextBox = {}

TextBox.BACKGROUND_RESOURCE = "text_field"

local MAXIMUM_LENGTH = 200
local TOP_INSET = 3
local CLEAR_GAP = 4

TextBox.CLEAR_ROOM = ClearButton.SIZE + CLEAR_GAP
local CHANGE_KEY = "rsprite-finder:text-box"
local TYPING_LABELS = { listening = "listening for typing", handling = "handling typing" }

function TextBox.New(parent, layout, onChange, onClear)
    local box = {}
    local rightMargin = Theme.FIELD_MARGIN
    if onClear ~= nil then
        rightMargin = rightMargin + TextBox.CLEAR_ROOM
    end
    box.component = Client.NewInputField(parent, {
        x = layout.x,
        y = layout.y,
        width = layout.width,
        height = layout.height,
        maxLength = MAXIMUM_LENGTH,
        placeholder = layout.placeholder,
        margin = Theme.FIELD_MARGIN,
        rightMargin = rightMargin,
        topInset = TOP_INSET,
        font = Client.Font(Theme.BODY_FONT),
        colour = Theme.FIELD_TEXT,
        placeholderColour = Theme.FIELD_PLACEHOLDER,
        caretColour = Theme.FIELD_CARET,
        selectionColour = Theme.FIELD_SELECTED,
        background = Client.OwnResource(TextBox.BACKGROUND_RESOURCE),
    })

    function box.GetText()
        return Client.Call("reading a text box", function()
            return box.component.content
        end) or ""
    end

    local function showClearButton(text)
        if box.clearButton ~= nil then
            box.clearButton.SetVisible(text ~= nil and text ~= "")
        end
    end

    function box.SetText(text)
        Client.Set(box.component, "content", text)
        showClearButton(text)
    end

    if onClear ~= nil then
        box.clearButton = ClearButton.New(parent, {
            x = layout.x + layout.width - Theme.FIELD_MARGIN - ClearButton.SIZE,
            y = layout.y + math.floor((layout.height - ClearButton.SIZE) / 2),
            tooltip = layout.clearTooltip,
        }, function()
            box.SetText("")
            onClear()
        end)
    end

    Client.OnHook(
        box.component,
        "ONCONTENTCHANGED",
        CHANGE_KEY,
        TYPING_LABELS,
        function(_, _, content)
            local text = content or box.GetText()
            showClearButton(text)
            onChange(text)
        end
    )

    return box
end

return TextBox
