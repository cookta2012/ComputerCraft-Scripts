local json = require "https://raw.githubusercontent.com/rxi/json.lua/master/json.lua" -- this require is enhanced by webrequire

local nonce =  {}
function nonce.generate(bytes)
    -- Generate i random bytes
    local random_bytes = {}
    for i = 1, bytes do
        table.insert(random_bytes, math.random(0, 255))
    end

    -- Get the timestamp
    local data = http.get("https://worldtimeapi.org/api/timezone/Etc/UTC")
    local json_str = data.readAll() 
    local json_obj = json.decode(json_str)
    if not json_obj or not json_obj.unixtime then
        error("Could not get timestamp")
    end
    local unix_time = json_obj.unixtime

    -- Convert timestamp to byte string
    local timestamp_bytes = {}
    for i = 1, 8 do
        table.insert(timestamp_bytes, 1, unix_time % 256)
        unix_time = math.floor(unix_time / 256)
    end
    -- Pad the timestamp bytes to bytes bytes if necessary
    while #timestamp_bytes < bytes do
        table.insert(timestamp_bytes, 1, math.random(0, 255))
    end

    -- XOR the random bytes with the timestamp bytes
    local nonce = ""
    for i = 1, bytes do
        local random_byte = random_bytes[i]
        local timestamp_byte = timestamp_bytes[i]
        local xor_byte = bit.bxor(random_byte, timestamp_byte)
        nonce = nonce .. string.char(xor_byte)
    end

    return nonce
end

return nonce