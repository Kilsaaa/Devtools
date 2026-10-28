local Client = require("finder/src/services/client")
local Theme = require("finder/src/utils/theme")

local DropDown = {}

DropDown.ENTRY_HEIGHT = 20
DropDown.VISIBLE_ENTRIES = 10

local CHANGE_KEY = "rsprite-finder:drop-down"
local CHOICE_LABELS =
    { listening = "listening for dropdown choices", handling = "handling a dropdown choice" }

function DropDown.New(parent, layout, entries, selectedId, onChoose)
    local dropDown = {}
    dropDown.component = Client.NewComboField(parent, {
        x = layout.x,
        y = layout.y,
        width = layout.width,
        height = layout.height,
        entryHeight = DropDown.ENTRY_HEIGHT,
        visibleEntries = DropDown.VISIBLE_ENTRIES,
        margin = Theme.FIELD_MARGIN,
        font = Client.Font(Theme.BODY_FONT),
        colour = Theme.FIELD_TEXT,
        hoverColour = Theme.FIELD_HOVER,
        selectedColour = Theme.FIELD_SELECTED,
        disabledColour = Theme.FIELD_DISABLED,
        caretColour = Theme.FIELD_CARET,
    })

    local idByLabel = {}
    for _, entry in ipairs(entries) do
        idByLabel[entry.label] = entry.id
    end
    Client.Call("filling a dropdown", function()
        dropDown.component:SetEntries(idByLabel, selectedId)
    end)

    function dropDown.SelectedId()
        return Client.Call("reading a dropdown", function()
            if dropDown.component.hasSelection then
                return dropDown.component.selectedID
            end
            return nil
        end)
    end

    function dropDown.Select(entryId)
        Client.Call("selecting a dropdown entry", function()
            dropDown.component:Select(entryId, false)
        end)
    end

    Client.OnHook(
        dropDown.component,
        "ONSELECTIONCHANGED",
        CHANGE_KEY,
        CHOICE_LABELS,
        function(_, entryId)
            onChoose(dropDown.SelectedId() or entryId)
            return false
        end
    )

    return dropDown
end

return DropDown
