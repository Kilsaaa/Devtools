local Preferences = require("finder/src/services/preferences")

local FinderOptions = {}

FinderOptions.PREFERENCES_NAME = "options"
FinderOptions.GROUP_VARIANTS = "groupVariants"
FinderOptions.HIDE_CLUTTER = "hideClutter"
FinderOptions.CHOICES = {
    { value = FinderOptions.GROUP_VARIANTS, text = "Group numbered variants" },
    { value = FinderOptions.HIDE_CLUTTER, text = "Hide mobile and language copies" },
}

local current = nil

function FinderOptions.Current()
    if current == nil then
        local saved = Preferences.Load(FinderOptions.PREFERENCES_NAME) or {}
        current = {}
        for _, choice in ipairs(FinderOptions.CHOICES) do
            current[choice.value] = saved[choice.value] ~= false
        end
    end
    return current
end

function FinderOptions.Set(optionName, selected)
    local options = FinderOptions.Current()
    local enabled = selected == true
    if options[optionName] == nil or options[optionName] == enabled then
        return false
    end
    options[optionName] = enabled
    Preferences.Save(FinderOptions.PREFERENCES_NAME, options)
    return true
end

return FinderOptions
