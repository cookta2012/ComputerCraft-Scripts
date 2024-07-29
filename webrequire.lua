-- Global table to cache loaded scripts
local loadedScripts = {}

-- Function to extract the base path from a URL
local function getBasePath(url)
    return url:match("(.-)[^/]+$")
end

local function getModuleFromURL(url)
    return url:match("/([^%s/]+)[%.lua]?$")
end

local function getModuleFromURLLUA(url)
    return url:match("/([^%s/]+)%.lua$")
end

local function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end


local function dump(data)
    local file = io.open("dump.lua", "w")
    file:write(data)
    file:close()
end

-- Function to convert dot notation to forward slashes and ensure .lua extension
local function convertToPath(module)
    -- Strip .lua extension if it exists
    local hasLuaExtension = module:match("%.lua$")
    if hasLuaExtension then
        module = module:sub(1, -5)
    end
    -- Add .lua extension back
    module = module .. ".lua"
    
    return module
end

-- Function to create a custom webrequire function
local function createWebRequire(globalRequire)
    -- Custom webrequire function
    local function webrequire(module,data)
        local module = module

        local modulename = getModuleFromURL(module)
        --print(modulename)


        -- Convert the module name to a URL-friendly path
        if loadedScripts[modulename] then
            return loadedScripts[modulename]
        end

        -- Cache the result
        local status, instance_or_err = pcall(globalRequire,modulename)
        if status then
            loadedScripts[modulename] = instance_or_err
            return loadedScripts[modulename]
        end
        -- regex for getting the name of the module
        -- \/(.*[^\s])(:?\.lua)?

        do
            -- Define the custom header to be added to each script
            local header = string.format([[
                local basePath = %q or ""
                local global_require = ...
                local function getBasePath(url)
                    return url:match("https?(.-)[^/]+$")
                end
                local function modified_require(module)
                    if getBasePath(module) then
                        --print("Path Found")
                        --print(module)
                        return global_require(module)
                    end
                    return global_require(basePath .. module)
                end
                require = modified_require
            ]], getBasePath(module))

            local mmodule = module

            if getModuleFromURLLUA(module) == nil then
                local base = getBasePath(mmodule)
                local parts = split(modulename,".")
                mmodule = base .. table.concat(parts, ".", 2, #parts):gsub("%.", "/")
                mmodule = mmodule .. ".lua"
                --io.open("link.txt","w"):write(mmodule):close()
            end
            --print(mmodule)

            -- Try to fetch the script from the given URL
            local response = http.get(mmodule)
            if not response or (response.getResponseCode() ~= 200) then
                -- If fetching fails, fall back to the regular require
                error("Url: " .. mmodule .. " returned nil")
            end
            -- Read the script content
            local script_content = response.readAll()
            response.close()

            -- Prepend the header to the script content
            local modified_script = header .. "\n" .. script_content
            -- Load and execute the modified script
            --dump(modified_script)
            local script_chunk, load_err = load(modified_script)
            if not script_chunk then
                error("Failed to load script: " .. url .. "\r\n" .. load_err)
            end

            -- Execute the script, passing the global require function
            local status, instance_or_err = true, script_chunk(webrequire)
            if status then
                loadedScripts[modulename] = instance_or_err
                return loadedScripts[modulename]
            end
        end
        assert(false, "We should never reach this")
    end

    return webrequire
end

-- Return the function to create a webrequire function
return createWebRequire
