local script_version = "1.0"

-- SPDX-FileCopyrightText: 2017 Daniel Ratcliffe
--
-- SPDX-License-Identifier: LicenseRef-CCPL

--[[
--header for use
local wrv2
if not fs.exist("/lib/wrv2.lua") then
    local script = http.get("https://raw.githubusercontent.com/cookta2012/ComputerCraft-Scripts/main/lib/wrv2.lua")
    wrv2 = loadstring(script.readAll())()
    require = wrv2.make(_ENV, "/", "from_web_to_file_updater", 
        {"https://raw.githubusercontent.com/cookta2012/ComputerCraft-Scripts/main/"}) 
end
wrv2 = require "lib.wrv2"
require = wrv2.make(_ENV, "/", "from_web_to_file_updater", 
{"https://raw.githubusercontent.com/cookta2012/ComputerCraft-Scripts/main/",
"https://raw.githubusercontent.com/migeyel/ccryptolib/main/",
"https://raw.githubusercontent.com/Wendelstein7/DiscordHook-CC/master/"})

require("DiscordHook")
--]]

local expect = require and require("cc.expect") or dofile("rom/modules/main/cc/expect.lua")
local expect = expect.expect

local function preload(package)
    return function(name)
        if package.preload[name] then
            return package.preload[name]
        else
            return nil, "no field package.preload['" .. name .. "']"
        end
    end
end

local function from_file(package, env)
    return function(name)
        local sPath, sError = package.searchpath(name, package.path)
        if not sPath then
            return nil, sError
        end
        local fnFile, sError = loadfile(sPath, nil, env)
        if fnFile then
            return fnFile, sPath
        else
            return nil, sError
        end
    end
end

local function from_web(package, env)
    return function(name)
        local sPath, sError = package.websearchpath(name, package.path)
        if not sPath then
            return nil, sError
        end
        local fnFile, sError = load(sPath, nil, "t", env)
        if fnFile then
            return fnFile, sPath
        else
            return nil, sError
        end
    end
end

local function from_web_to_file(package, env, dir)
    return function(name)
        local function ensure_directories(path)
            -- Get the directory portion of the path (removes the filename part)
            local dir = fs.getDir(path)
            
            -- Split the directory path into components and build it progressively
            local current_path = ""
            for part in string.gmatch(dir, "[^/]+") do
                -- Build up the current directory path
                current_path = fs.combine(current_path, part)
                -- If the directory doesn't exist, create it
                if not fs.exists(current_path) then
                    print("making dir: "..current_path)
                    fs.makeDir(current_path)
                end
            end
        end
        
        local sPath, sError = package.websearchpath(name, package.path)
        if not sPath then
            return nil, sError
        end
        local libdir = fs.combine(dir, "lib")
        if not fs.exists(libdir) then
            print("making dir: "..libdir)
            fs.makeDir(libdir)
        end
        local sep = expect(3, sep, "string", "nil") or "."
        local fname = string.gsub(name, sep:gsub("%.", "%%%."), "/")
        local filePath = fs.combine(libdir, fname)
        ensure_directories(filePath)

        if not fs.exists(filePath) then
            io.open(filePath .. ".lua", "w"):write(sPath):close()
        end
        local fnFile, sError = loadfile(filePath .. ".lua", nil, env)
        if fnFile then
            return fnFile, sPath
        else
            return nil, sError
        end
    end
end

local function from_web_to_file_updater(package, env, dir)
    return function(name)
        local function ensure_directories(path)
            -- Get the directory portion of the path (removes the filename part)
            local dir = fs.getDir(path)
            
            -- Split the directory path into components and build it progressively
            local current_path = ""
            for part in string.gmatch(dir, "[^/]+") do
                -- Build up the current directory path
                current_path = fs.combine(current_path, part)
                -- If the directory doesn't exist, create it
                if not fs.exists(current_path) then
                    print("making dir: "..current_path)
                    fs.makeDir(current_path)
                end
            end
        end
        
        local sPath, sError = package.websearchpath(name, package.path)
        if not sPath then
            return nil, sError
        end
        local libdir = fs.combine(dir, "lib")
        if not fs.exists(libdir) then
            print("making dir: "..libdir)
            fs.makeDir(libdir)
        end
        local sep = expect(3, sep, "string", "nil") or "."
        local fname = string.gsub(name, sep:gsub("%.", "%%%."), "/")
        local filePath = fs.combine(libdir, fname)
        ensure_directories(filePath)
        filePath = filePath .. ".lua"

        if not fs.exists(filePath) then
            io.open(filePath, "w"):write(sPath):close()
        else
            local script_io = io.open(filePath, "r")
            local local_version_line = script_io:read()
            script_io:close()

            local function getVersionNumbers(first_line)
                local major, minor, patch = first_line:match("local script_version = \"(%d+)%.(%d+)\"")
                return {tonumber(major) or 0, tonumber(minor) or 0}
            end
            local local_version = getVersionNumbers(local_version_line)
            local sPath1st = string.match(sPath, "([^\n]+)")
            local script_version = getVersionNumbers(sPath1st)
            if script_version[1] > local_version[1] or (script_version[1] == local_version[1] and script_version[2] > local_version[2]) then
                io.open(filePath, "w"):write(sPath):close()
            end

        end

        local fnFile, sError = loadfile(filePath, nil, env)
        if fnFile then
            return fnFile, sPath
        else
            return nil, sError
        end
    end
end

local function make_websearchpath(dirs)
    return function(name, path, sep, rep)
        expect(1, name, "string")
        expect(2, path, "string")
        sep = expect(3, sep, "string", "nil") or "."
        rep = expect(4, rep, "string", "nil") or "/"
        local fname = string.gsub(name, sep:gsub("%.", "%%%."), rep)
        local sError = ""
        
        -- Iterate over each directory in the dirs list
        for _, dir in ipairs(dirs) do
            for pattern in string.gmatch(path, "[^;]+") do
                local sPath = string.gsub(pattern, "%?", fname)
                local response = http.get(dir .. sPath)
                
                if response and response.getResponseCode() == 200 then
                    return response.readAll()
                else
                    if #sError > 0 then
                        sError = sError .. "\n  "
                    end
                    sError = sError .. "Url: '" .. dir .. sPath .. "' returned nil or error"
                end
            end
        end
        
        return nil, sError
    end
end


local function make_searchpath(dir)
    return function(name, path, sep, rep)
        sleep()
        expect(1, name, "string")
        expect(2, path, "string")
        sep = expect(3, sep, "string", "nil") or "."
        rep = expect(4, rep, "string", "nil") or "/"

        local fname = string.gsub(name, sep:gsub("%.", "%%%."), rep)
        local sError = ""
        for pattern in string.gmatch(path, "[^;]+") do
            local sPath = string.gsub(pattern, "%?", fname)
            if sPath:sub(1, 1) ~= "/" then
                sPath = fs.combine(dir, sPath)
            end
            if fs.exists(sPath) and not fs.isDir(sPath) then
                return sPath
            else
                if #sError > 0 then
                    sError = sError .. "\n  "
                end
                sError = sError .. "no file '" .. sPath .. "'"
            end
        end
        return nil, sError
    end
end

local function make_require(package)
    local sentinel = {}
    return function(name)
        sleep()
        expect(1, name, "string")

        if package.loaded[name] == sentinel then
            error("loop or previous error loading module '" .. name .. "'", 0)
        end

        if package.loaded[name] then
            return package.loaded[name]
        end

        local sError = "module '" .. name .. "' not found:"
        for _, searcher in ipairs(package.loaders) do
            local loader = table.pack(searcher(name))
            if loader[1] then
                package.loaded[name] = sentinel
                local result = loader[1](name, table.unpack(loader, 2, loader.n))
                if result == nil then result = true end
                package.loaded[name] = result
                return result
            else
                sError = sError .. "\n  " .. loader[2]
            end
        end
        error(sError, 2)
    end
end

--- Build an implementation of Lua's [`package`] library, and a [`require`]
-- function to load modules within it.
--
-- @tparam table env The environment to load packages into.
-- @tparam string dir The directory that relative packages are loaded from.
-- @treturn function The new [`require`] function.
-- @treturn table The new [`package`] library.
local function make_package(env, dir, priority, webdir)
    expect(1, env, "table")
    expect(2, dir, "string")
    expect(3, priority, "string")

    local package = {}
    package.loaded = {
        _G = _G,
        package = package,
    }

    -- Copy everything from the global package table to this instance.
    --
    -- This table is an internal implementation detail - it is NOT intended to
    -- be extended by user code.
    local registry = debug.getregistry()
    if registry and type(registry._LOADED) == "table" then
        for k, v in next, registry._LOADED do
            if type(k) == "string" then
                package.loaded[k] = v
            end
        end
    end

    package.path = "?;?.lua;?/init.lua;/rom/modules/main/?;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua;/lib/?;/lib/?.lua;/lib/?/init.lua"
    if turtle then
        package.path = package.path .. ";/rom/modules/turtle/?;/rom/modules/turtle/?.lua;/rom/modules/turtle/?/init.lua"
    elseif commands then
        package.path = package.path .. ";/rom/modules/command/?;/rom/modules/command/?.lua;/rom/modules/command/?/init.lua"
    end
    package.config = "/\n;\n?\n!\n-"
    package.preload = {}
    if priority == "from_web_to_file" then
        package.loaders = { preload(package), from_file(package, env), from_web_to_file(package, env, dir)}
    elseif priority == "from_web_to_file_updater" then
        package.loaders = { preload(package), from_web_to_file_updater(package, env), from_file(package, env)}
    elseif priority == "from_file_or_web" then
        package.loaders = { preload(package), from_file(package, env), from_web(package, env)}
    elseif priority == "from_file" then
        package.loaders = { preload(package), from_file(package, env)}
    elseif priority == "from_web" then
        package.loaders = { preload(package), from_web(package, env), from_file(package, env)}
    end
    if not package.loaders then error("priority is not a valid priority: " .. priority) end
    package.searchpath = make_searchpath(dir)
    package.websearchpath = make_websearchpath(webdir)

    return make_require(package), package
end

return { make = make_package }