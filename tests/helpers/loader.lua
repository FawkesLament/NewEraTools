local EventFrames = require("helpers.event_frames")
local Fs = require("helpers.fs")

local Loader = {}

Loader.ADDON_NAME = "NewEraTools"
Loader.TOC_PATH = "NewEraTools.toc"

local FAKES_PATH = "tests/helpers/fakes/"

---@class LoadOrderEntry
---@field path string  Forward-slash path from the addon folder.
---@field listedBy string  The TOC or XML manifest that references it.

local function Normalize(path)
    return (path:gsub("\\", "/"))
end

local function DirectoryOf(path)
    return path:match("^(.*/)") or ""
end

local AddEntry

local function ReadManifest(path, entries)
    local source = Fs.ReadFile(path):gsub("<!%-%-.-%-%->", "")
    local directory = DirectoryOf(path)
    for tag, file in source:gmatch('<(%a+)%s+file%s*=%s*"([^"]+)"') do
        if tag == "Script" or tag == "Include" then
            AddEntry(directory .. Normalize(file), path, entries)
        end
    end
end

function AddEntry(path, listedBy, entries)
    table.insert(entries, { path = path, listedBy = listedBy })
    if path:find("%.xml$") and Fs.Exists(path) then
        ReadManifest(path, entries)
    end
end

---Every file the TOC loads, in load order, following XML manifests through <Script> and <Include>.
---Manifests appear before the files they list. Missing files are included so callers can report them.
---@return LoadOrderEntry[]
function Loader.ReadLoadOrder()
    local entries = {}
    for line in io.lines(Loader.TOC_PATH) do
        line = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:find("^#") then
            AddEntry(Normalize(line), Loader.TOC_PATH, entries)
        end
    end
    return entries
end

---@return string[]  Lua files in load order.
function Loader.ReadLuaFiles()
    local files = {}
    for _, entry in ipairs(Loader.ReadLoadOrder()) do
        if entry.path:find("%.lua$") then
            table.insert(files, entry.path)
        end
    end
    return files
end

local function IsSkipped(path)
    -- Pure data / helpers (no frames); logic modules may use them under test.
    if path == "ui/Assets.lua" or path == "ui/Position.lua" or path == "ui/Color.lua" then
        return false
    end
    -- Top-level ui/, feature-local ui/ directories, and legacy *UI.lua names.
    return path == "Main.lua" or path:find("^ui/") ~= nil or path:find("/ui/") ~= nil or path:find("UI%.lua$") ~= nil
end

-- Production api files loaded under test. Encounter.WhileIn runs for real and only needs
-- GameEvents; tests/helpers/fakes/Encounter.lua adds FireStart/FireEnd/FireWarning afterward.
-- MessageProtocolComm is tested against the AddonMessage fake. Aura is loaded as written.
local REAL_API_FILES = {
    Aura = true,
    Encounter = true,
    MessageProtocolComm = true,
}

---Loads the addon into a fresh namespace the way WoW does, replacing each api/ file with its fake
---from tests/helpers/fakes/ except REAL_API_FILES, and skipping UI files and Main.lua.
---@return table ns
function Loader.Load()
    EventFrames.Reset()
    if CreateFrame == nil or CreateFrame == EventFrames.CreateFrame then
        CreateFrame = EventFrames.CreateFrame
    end
    local ns = {}
    for _, path in ipairs(Loader.ReadLuaFiles()) do
        local apiName = path:match("^api/(.+)%.lua$")
        if apiName and REAL_API_FILES[apiName] then
            assert(loadfile(path))(Loader.ADDON_NAME, ns)
            if apiName == "Encounter" then
                dofile(FAKES_PATH .. "Encounter.lua")(ns.Api.Encounter, ns.Api.GameEvents)
            end
        elseif apiName then
            ns.Api[apiName] = dofile(FAKES_PATH .. apiName .. ".lua")()
        elseif not IsSkipped(path) then
            assert(loadfile(path))(Loader.ADDON_NAME, ns)
        end
    end
    return ns
end

return Loader
