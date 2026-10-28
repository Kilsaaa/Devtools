local Arguments = require("rsprite/src/utils/arguments")
local Curation = require("rsprite/src/data/curation")
local NameIndex = require("rsprite/src/features/search/name_index")
local SearchText = require("rsprite/src/utils/search_text")

local SpriteSearch = {}

local DEFAULT_LIMIT = 50
local FIND_OPTION_TYPES = { tags = "table", limit = "number", offset = "number" }
local EMPTY = {}

local RANK_EXACT_NAME = 1
local RANK_EXACT_ALIAS = 2
local RANK_PREFIX = 3
local RANK_TAG = 4
local RANK_WHOLE_WORD = 5
local RANK_SUBSTRING = 6

local CURATED_GROUP = 1
local UNCURATED_GROUP = 2
local BROWSE_LENGTH = 0

local prepared = nil

local function normaliseAll(texts)
    local normalised = {}
    for position, text in ipairs(texts or EMPTY) do
        normalised[position] = SearchText.Normalise(text)
    end
    return normalised
end

local function prepare()
    if prepared ~= nil then
        return prepared
    end
    local rules = {}
    for _, rule in ipairs(Curation.rules) do
        rules[#rules + 1] = {
            prefix = rule.prefix,
            contains = rule.contains,
            suffix = rule.suffix,
            tags = rule.tags,
            normalisedTags = normaliseAll(rule.tags),
        }
    end
    local curated = {}
    for name, entry in pairs(Curation.curated) do
        curated[name] = {
            tags = entry.tags or EMPTY,
            aliases = entry.aliases or EMPTY,
            width = entry.width,
            height = entry.height,
            normalisedTags = normaliseAll(entry.tags),
            normalisedAliases = normaliseAll(entry.aliases),
        }
    end
    prepared = { rules = rules, curated = curated }
    return prepared
end

local function ruleApplies(rule, name)
    return (rule.prefix == nil or SearchText.StartsWith(name, rule.prefix))
        and (rule.suffix == nil or SearchText.EndsWith(name, rule.suffix))
        and (rule.contains == nil or SearchText.Contains(name, rule.contains))
end

local function anyRuleApplies(rules, name)
    for _, rule in ipairs(rules) do
        if ruleApplies(rule, name) then
            return true
        end
    end
    return false
end

local function anyText(texts, predicate)
    for _, text in ipairs(texts) do
        if predicate(text) then
            return true
        end
    end
    return false
end

local function rulesWithTag(rules, predicate)
    local selected = {}
    for _, rule in ipairs(rules) do
        if anyText(rule.normalisedTags, predicate) then
            selected[#selected + 1] = rule
        end
    end
    return selected
end

local function hasExactTag(name, curatedEntry, normalisedTag, taggingRules)
    local function equalsTag(tag)
        return tag == normalisedTag
    end
    if curatedEntry ~= nil and anyText(curatedEntry.normalisedTags, equalsTag) then
        return true
    end
    return anyRuleApplies(taggingRules, name)
end

local function matchesWord(name, curatedEntry, word, taggingRules)
    if SearchText.Contains(name, word) then
        return true
    end
    if curatedEntry ~= nil then
        local containsWord = function(alias)
            return SearchText.Contains(alias, word)
        end
        local tagStartsWithWord = function(tag)
            return SearchText.HasWordStartingWith(tag, word)
        end
        if
            anyText(curatedEntry.normalisedAliases, containsWord)
            or anyText(curatedEntry.normalisedTags, tagStartsWithWord)
        then
            return true
        end
    end
    return anyRuleApplies(taggingRules, name)
end

local function matchesAllWords(name, curatedEntry, query)
    for position, word in ipairs(query.words) do
        if not matchesWord(name, curatedEntry, word, query.wordRules[position]) then
            return false
        end
    end
    return true
end

local function passesFilters(name, curatedEntry, filters)
    for _, filter in ipairs(filters) do
        if not hasExactTag(name, curatedEntry, filter.tag, filter.rules) then
            return false
        end
    end
    return true
end

local function rankOf(name, curatedEntry, query)
    if query.text == "" then
        return RANK_SUBSTRING
    end
    if name == query.text or name == query.upperText then
        return RANK_EXACT_NAME
    end
    local aliases = curatedEntry ~= nil and curatedEntry.normalisedAliases or EMPTY
    local function equalsQuery(alias)
        return alias == query.text
    end
    local function startsWithQuery(alias)
        return SearchText.StartsWith(alias, query.text)
    end
    if anyText(aliases, equalsQuery) then
        return RANK_EXACT_ALIAS
    end
    if SearchText.StartsWith(name, query.text) or anyText(aliases, startsWithQuery) then
        return RANK_PREFIX
    end
    if hasExactTag(name, curatedEntry, query.text, query.exactTagRules) then
        return RANK_TAG
    end
    for _, word in ipairs(query.words) do
        if not SearchText.HasWholeWord(name, word) then
            return RANK_SUBSTRING
        end
    end
    return RANK_WHOLE_WORD
end

local function pixelSize(name)
    local pixels = string.match(name, "_(%d+)PX_") or string.match(name, "_(%d+)PX$")
    return pixels and tonumber(pixels) or nil
end

local function buildEntry(name, spriteId, curatedEntry, rules)
    local tags = {}
    local seen = {}
    local function addTag(tag)
        if not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
        end
    end
    for _, rule in ipairs(rules) do
        if ruleApplies(rule, name) then
            for _, tag in ipairs(rule.tags) do
                addTag(tag)
            end
        end
    end
    local aliases = {}
    local width = nil
    local height = nil
    if curatedEntry ~= nil then
        for _, tag in ipairs(curatedEntry.tags) do
            addTag(tag)
        end
        for position, alias in ipairs(curatedEntry.aliases) do
            aliases[position] = alias
        end
        width = curatedEntry.width
        height = curatedEntry.height
    end
    local pixels = pixelSize(name)
    return {
        name = name,
        id = spriteId,
        tags = tags,
        aliases = aliases,
        width = width or pixels,
        height = height or pixels,
    }
end

local function buildQuery(text, rules)
    local normalised = SearchText.Normalise(text)
    local query = {
        text = normalised,
        upperText = string.upper(text),
        words = SearchText.Words(normalised),
        wordRules = {},
    }
    for position, word in ipairs(query.words) do
        query.wordRules[position] = rulesWithTag(rules, function(tag)
            return SearchText.HasWordStartingWith(tag, word)
        end)
    end
    query.exactTagRules = rulesWithTag(rules, function(tag)
        return tag == normalised
    end)
    return query
end

local function buildFilters(tags, rules)
    local filters = {}
    for _, tag in ipairs(tags or EMPTY) do
        local normalisedTag = SearchText.Normalise(tag)
        filters[#filters + 1] = {
            tag = normalisedTag,
            rules = rulesWithTag(rules, function(ruleTag)
                return ruleTag == normalisedTag
            end),
        }
    end
    return filters
end

local function addToBucket(buckets, rank, group, length, position)
    buckets[rank] = buckets[rank] or {}
    buckets[rank][group] = buckets[rank][group] or {}
    local byLength = buckets[rank][group]
    byLength[length] = byLength[length] or {}
    local positions = byLength[length]
    positions[#positions + 1] = position
end

local function orderedPositions(buckets, offset, limit)
    local page = {}
    local skipped = 0
    for rank = RANK_EXACT_NAME, RANK_SUBSTRING do
        for group = CURATED_GROUP, UNCURATED_GROUP do
            local byLength = buckets[rank] and buckets[rank][group]
            if byLength ~= nil then
                local lengths = {}
                for length in pairs(byLength) do
                    lengths[#lengths + 1] = length
                end
                table.sort(lengths)
                for _, length in ipairs(lengths) do
                    for _, position in ipairs(byLength[length]) do
                        if #page >= limit then
                            return page
                        end
                        if skipped < offset then
                            skipped = skipped + 1
                        else
                            page[#page + 1] = position
                        end
                    end
                end
            end
        end
    end
    return page
end

local function tagsProblem(options)
    if options == nil or type(options.tags) ~= "table" then
        return nil
    end
    for position, tag in ipairs(options.tags) do
        if type(tag) ~= "string" then
            return string.format(
                "rsprite.Find: option tags must be an array of strings, got %s at position %d",
                type(tag),
                position
            )
        end
    end
    return nil
end

function SpriteSearch.Find(text, options)
    if type(text) ~= "string" then
        error(string.format("rsprite.Find: text must be a string, got %s", type(text)), 2)
    end
    local problem = Arguments.OptionsProblem("rsprite.Find", options, FIND_OPTION_TYPES)
        or Arguments.WholeNumberOptionProblem("rsprite.Find", options, "limit")
        or Arguments.WholeNumberOptionProblem("rsprite.Find", options, "offset")
        or tagsProblem(options)
    if problem ~= nil then
        error(problem, 2)
    end
    local resolvedOptions = options or EMPTY
    local data = prepare()
    local query = buildQuery(text, data.rules)
    local filters = buildFilters(resolvedOptions.tags, data.rules)
    local index = NameIndex.Entries()

    local buckets = {}
    local total = 0
    for position, name in ipairs(index.names) do
        local curatedEntry = data.curated[name]
        if
            passesFilters(name, curatedEntry, filters)
            and matchesAllWords(name, curatedEntry, query)
        then
            total = total + 1
            local group = curatedEntry ~= nil and CURATED_GROUP or UNCURATED_GROUP
            local length = query.text == "" and BROWSE_LENGTH or #name
            addToBucket(buckets, rankOf(name, curatedEntry, query), group, length, position)
        end
    end

    local entries = {}
    local page = orderedPositions(
        buckets,
        resolvedOptions.offset or 0,
        resolvedOptions.limit or DEFAULT_LIMIT
    )
    for _, position in ipairs(page) do
        local name = index.names[position]
        entries[#entries + 1] =
            buildEntry(name, index.ids[position], data.curated[name], data.rules)
    end
    return entries, total
end

function SpriteSearch.Tags()
    local data = prepare()
    local seen = {}
    local tags = {}
    local function addTags(tagList)
        for _, tag in ipairs(tagList) do
            if not seen[tag] then
                seen[tag] = true
                tags[#tags + 1] = tag
            end
        end
    end
    for _, rule in ipairs(data.rules) do
        addTags(rule.tags)
    end
    for _, entry in pairs(data.curated) do
        addTags(entry.tags)
    end
    table.sort(tags)
    return tags
end

return SpriteSearch
