local WholeNumber = {}

function WholeNumber.From(value)
    if type(value) ~= "number" then
        return nil
    end
    local integer = math.tointeger(value)
    if integer == nil or integer < 0 then
        return nil
    end
    return integer
end

return WholeNumber
