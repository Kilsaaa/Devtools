local SearchText = {}

function SearchText.Normalise(text)
    local unified = string.gsub(string.upper(text), "[%s%-_]+", "_")
    local withoutLeading = string.gsub(unified, "^_+", "")
    local trimmed = string.gsub(withoutLeading, "_+$", "")
    return trimmed
end

function SearchText.Words(normalised)
    local words = {}
    for word in string.gmatch(normalised, "[^_]+") do
        words[#words + 1] = word
    end
    return words
end

function SearchText.StartsWith(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

function SearchText.EndsWith(text, suffix)
    return #text >= #suffix and string.sub(text, #text - #suffix + 1) == suffix
end

function SearchText.Contains(text, part)
    return string.find(text, part, 1, true) ~= nil
end

function SearchText.HasWholeWord(name, word)
    return SearchText.Contains("_" .. name .. "_", "_" .. word .. "_")
end

function SearchText.HasWordStartingWith(text, word)
    return SearchText.StartsWith(text, word) or SearchText.Contains(text, "_" .. word)
end

return SearchText
