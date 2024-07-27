
-- Global table to cache loaded scripts
local loadedScripts = {}

-- Function to extract the base path from a URL
local function getBasePath(url)
    return url:match("(.-)[^/]+$")
end

local function dump(data)
    local file = io.open("dump.bin","w")
    file:write(textutils.seralise(data))
    file:close()
end

-- Function to convert dot notation to forward slashes
local function convertToPath(module)
    return module:gsub("%.", "/")
end

-- Function to create a custom webrequire function
local function createWebRequire(globalRequire)
    -- Custom webrequire function
    local function webrequire(module)
        -- Convert the module name to a URL-friendly path
        local url = module
        if not url:match("^http") then
            url = convertToPath(module)
        end

        -- Check if the script is already cached
        if loadedScripts[url] then
            return loadedScripts[url]
        end

        -- Derive the base path for the URL
        local basePath = getBasePath(url)

        -- Define the custom header to be added to each script
        local header = string.format([[
            local basePath = %q
            local global_require = ...
            local function modified_require(module)
                module = module:gsub("%%.", "/") -- Convert dot notation to forward slashes
                if module:sub(1, 4) == "http" or module:sub(1, 1) == "/" then
                    return global_require(module)
                else
                    return global_require(basePath .. module)
                end
            end
            require = modified_require
        ]], basePath)

        -- Try to fetch the script from the given URL
        local response = http.get(url)
        if not response then
            -- If fetching fails, fall back to the regular require
            return globalRequire(module)
        end

        -- Read the script content
        local script_content = response.readAll()
        response.close()

        -- Prepend the header to the script content
        local modified_script = header .. "\n" .. script_content

        -- Load and execute the modified script
        dump(modified_script)
        local script_chunk, load_err = loadstring(modified_script)
        if not script_chunk then
            error("Failed to load script: " .. load_err)
        end

        -- Execute the script, passing the global require function
        local result = script_chunk(globalRequire)

        -- Cache the result
        loadedScripts[url] = result

        return result
    end

    return webrequire
end

-- Return the function to create a webrequire function
return createWebRequire
