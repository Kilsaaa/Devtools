local NumberText = {}

function NumberText.Describe(value)
    if type(value) ~= "number" then
        return tostring(value)
    end
    if value ~= value then
        return "nan"
    end
    if value == math.huge then
        return "inf"
    end
    if value == -math.huge then
        return "-inf"
    end
    return tostring(value)
end

return NumberText
