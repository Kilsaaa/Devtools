local TextFit = {}

TextFit.ELLIPSIS = "..."

local function fits(text, maximumWidth, measure)
    local width = measure(text)
    return width ~= nil and width <= maximumWidth
end

local function longestFittingPrefix(text, maximumWidth, measure, suffix)
    local shortest = 0
    local longest = #text
    while shortest < longest do
        local middle = math.ceil((shortest + longest) / 2)
        if fits(string.sub(text, 1, middle) .. suffix, maximumWidth, measure) then
            shortest = middle
        else
            longest = middle - 1
        end
    end
    return shortest
end

function TextFit.Fit(text, maximumWidth, measure)
    if measure(text) == nil or fits(text, maximumWidth, measure) then
        return text
    end
    local length = longestFittingPrefix(text, maximumWidth, measure, TextFit.ELLIPSIS)
    return string.sub(text, 1, length) .. TextFit.ELLIPSIS
end

local function namePieces(text)
    local pieces = {}
    for piece in string.gmatch(text, "_*[^_]+_*") do
        pieces[#pieces + 1] = piece
    end
    if #pieces == 0 then
        pieces[1] = text
    end
    return pieces
end

function TextFit.Wrap(text, maximumWidth, measure, maximumLines)
    if measure(text) == nil or fits(text, maximumWidth, measure) then
        return { text }
    end
    local lines = {}
    local current = ""
    for _, piece in ipairs(namePieces(text)) do
        if fits(current .. piece, maximumWidth, measure) then
            current = current .. piece
        else
            if current ~= "" then
                lines[#lines + 1] = current
            end
            current = piece
            while not fits(current, maximumWidth, measure) do
                local length = math.max(1, longestFittingPrefix(current, maximumWidth, measure, ""))
                lines[#lines + 1] = string.sub(current, 1, length)
                current = string.sub(current, length + 1)
            end
        end
    end
    if current ~= "" then
        lines[#lines + 1] = current
    end
    if #lines > maximumLines then
        local kept = {}
        for position = 1, maximumLines - 1 do
            kept[position] = lines[position]
        end
        kept[maximumLines] =
            TextFit.Fit(table.concat(lines, "", maximumLines), maximumWidth, measure)
        return kept
    end
    return lines
end

return TextFit
