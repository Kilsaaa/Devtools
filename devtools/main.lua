local DevTools = require("core/devtools")

DevTools.init()

function PluginShutdown()
    DevTools.shutdown()
end
