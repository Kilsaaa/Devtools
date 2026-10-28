local ItemDrawing = require("rsprite/src/features/drawing/item_drawing")
local NameIndex = require("rsprite/src/features/search/name_index")
local SourceChain = require("rsprite/src/features/drawing/source_chain")
local SpriteDrawing = require("rsprite/src/features/drawing/sprite_drawing")
local SpriteLookup = require("rsprite/src/features/lookup/sprite_lookup")
local SpriteSearch = require("rsprite/src/features/search/sprite_search")

local App = {}

App.Public = {
    version = "0.1.2",
    Get = SpriteLookup.Get,
    Name = SpriteLookup.Name,
    Resolve = SourceChain.Resolve,
    Find = SpriteSearch.Find,
    Tags = SpriteSearch.Tags,
    BuildIndex = NameIndex.Build,
    IsIndexReady = NameIndex.IsReady,
    Draw = SpriteDrawing.Draw,
    SetSource = SpriteDrawing.SetSource,
    DrawItem = ItemDrawing.DrawItem,
    SetItem = ItemDrawing.SetItem,
}

function App.Shutdown()
    NameIndex.Shutdown()
end

return App
