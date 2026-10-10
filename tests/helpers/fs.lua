local Fs = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function ReadLines(command)
    local handle = assert(io.popen(command))
    local lines = {}
    for line in handle:lines() do
        table.insert(lines, (line:gsub("\r$", "")))
    end
    handle:close()
    return lines
end

---Lists every file under the current directory as a relative, forward-slash path, skipping .git.
---@return string[]
function Fs.ListFiles()
    local root, lines
    if IS_WINDOWS then
        root = ReadLines("cd")[1]
        lines = ReadLines("dir /s /b /a-d")
    else
        root = "."
        lines = ReadLines("find . -type f")
    end
    local files = {}
    for _, line in ipairs(lines) do
        local path = line:sub(#root + 2):gsub("\\", "/")
        if not path:find("^%.git/") then
            table.insert(files, path)
        end
    end
    table.sort(files)
    return files
end

---@param path string
---@return string
function Fs.ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

---@param path string
---@return boolean
function Fs.Exists(path)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return true
    end
    return false
end

return Fs
