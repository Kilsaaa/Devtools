local TagOptions = {}

TagOptions.ALL_TAGS = "All tags"

function TagOptions.Build(tags)
    local labels = { TagOptions.ALL_TAGS }
    local tagByLabel = {}
    local labelByTag = {}
    for _, tag in ipairs(tags or {}) do
        if labelByTag[tag] == nil then
            labels[#labels + 1] = tag
            tagByLabel[tag] = tag
            labelByTag[tag] = tag
        end
    end
    table.sort(labels)
    local entries = {}
    local positionByLabel = {}
    for position, label in ipairs(labels) do
        entries[position] = { label = label, id = position }
        positionByLabel[label] = position
    end
    return {
        entries = entries,
        labels = labels,
        positionByLabel = positionByLabel,
        tagByLabel = tagByLabel,
        labelByTag = labelByTag,
    }
end

function TagOptions.TagFor(options, label)
    return options.tagByLabel[label]
end

function TagOptions.PositionFor(options, tag)
    local label = tag ~= nil and options.labelByTag[tag] or TagOptions.ALL_TAGS
    return options.positionByLabel[label] or options.positionByLabel[TagOptions.ALL_TAGS]
end

return TagOptions
