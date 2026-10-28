local NumberText = require("rsprite/src/utils/number_text")
local WholeNumber = require("rsprite/src/utils/whole_number")

local Arguments = {}

local TABLE_HINTS = {
    parent = "Pass the component itself, such as a window's content",
    sprite = "Pass the sprite itself, such as the one rsprite.Draw returned",
}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function numberOption(options, optionName)
    local value = options ~= nil and options[optionName] or nil
    if type(value) ~= "number" then
        return nil
    end
    return value
end

function Arguments.CombineTypes(...)
    local combined = {}
    for _, expectedTypes in ipairs({ ... }) do
        for optionName, optionType in pairs(expectedTypes) do
            combined[optionName] = optionType
        end
    end
    return combined
end

function Arguments.ComponentProblem(functionName, argumentName, value)
    local valueType = type(value)
    if valueType == "userdata" then
        return nil
    end
    if valueType == "table" then
        return string.format(
            "%s: %s must be a component, not a table. %s",
            functionName,
            argumentName,
            TABLE_HINTS[argumentName]
        )
    end
    return string.format(
        "%s: %s must be a component, got %s",
        functionName,
        argumentName,
        valueType
    )
end

function Arguments.OptionsProblem(functionName, options, expectedTypes)
    if options == nil then
        return nil
    end
    if type(options) ~= "table" then
        return string.format("%s: options must be a table, got %s", functionName, type(options))
    end
    for optionName, value in pairs(options) do
        local expectedType = expectedTypes[optionName]
        if expectedType == nil then
            return string.format("%s: unknown option %s", functionName, tostring(optionName))
        end
        if type(value) ~= expectedType then
            return string.format(
                "%s: option %s must be a %s, got %s",
                functionName,
                optionName,
                expectedType,
                type(value)
            )
        end
    end
    return nil
end

function Arguments.WholeNumberOptionProblem(functionName, options, optionName)
    local value = options ~= nil and options[optionName] or nil
    if value == nil or WholeNumber.From(value) ~= nil then
        return nil
    end
    return string.format(
        "%s: option %s must be a whole number 0 or above, got %s",
        functionName,
        optionName,
        NumberText.Describe(value)
    )
end

function Arguments.FiniteOptionProblem(functionName, options, optionName)
    local value = numberOption(options, optionName)
    if value == nil or isFinite(value) then
        return nil
    end
    return string.format(
        "%s: option %s must be a finite number, got %s",
        functionName,
        optionName,
        NumberText.Describe(value)
    )
end

function Arguments.SizeOptionProblem(functionName, options, optionName)
    local problem = Arguments.FiniteOptionProblem(functionName, options, optionName)
    if problem ~= nil then
        return problem
    end
    local value = numberOption(options, optionName)
    if value == nil or value > 0 then
        return nil
    end
    return string.format(
        "%s: option %s must be above 0, got %s",
        functionName,
        optionName,
        NumberText.Describe(value)
    )
end

return Arguments
