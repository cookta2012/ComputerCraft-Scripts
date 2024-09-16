local completion = require("cc.completion")
local cryptobox = require("crypto.cryptobox")

--- @class cryptonet
--- A class for managing encrypted network communications.
--- @field caller_module_name string This is the name of the module opening this session.
--- @field permissive boolean? SWhether or not to be permissive of non strict complance.
--- @field keys KeyStore Keystore of all keys
local cryptonet = {}



local function merge_dict(table1, table2, ...)
    local _table = table2 or {}
    for i,v in pairs(table1) do
        _table[i] = v
    end
    if ... ~= nil then
        _table = merge_dict(_table, ...)
    end
    return _table
end

--- @class KeyStore
--- @field own table Stores the user's own keys.
--- @field trusted_keys table Stores trusted keys from other users indexed by sender ID.
local KeyStore = {}
KeyStore.__index = KeyStore

function KeyStore.new()
    return setmetatable({own = {}, trusted_keys = {}}, KeyStore)
end

local function load_keyfile(caller_module_name)
    local keys = KeyStore.new()
    if fs.exists(".keys") then
        if fs.exists(".keys/" .. caller_module_name .. ".keys") then
            local file = io.open(".keys/" .. caller_module_name .. ".keys", "r")
            keys = textutils.unserialize(file:read("*a"))
            file:close()
        end
    end
    return keys
end

local function save_keyfile(caller_module_name, keys)
    if not fs.exists(".keys") then
        fs.makeDir(".keys")
    end
    local file = io.open(".keys/" .. caller_module_name .. ".keys", "w")
    ---@diagnostic disable-next-line: need-check-nil
    file:write(textutils.serialize(keys))
    ---@diagnostic disable-next-line: need-check-nil
    file:close()
end

local function reload_keyfile(caller_module_name, keys)
    save_keyfile(caller_module_name, keys)
    return load_keyfile(caller_module_name)
end



local function _ssend(self, receiverID, message, protocol, public_key)
    local error_msg = ""
    local success = nil
    if not public_key then
        return success, "No public key provided for receiver ID: " .. tostring(receiverID)
    end

    -- Include this computer's ID in the message
    local data_to_encrypt = {
        ---@diagnostic disable-next-line: undefined-field
        id = os.getComputerID(),
    }
    data_to_encrypt = merge_dict(data_to_encrypt, message)
    local msg = cryptobox.box(textutils.serialize(data_to_encrypt), self.keys.own.private_key, public_key)
    msg.public_key = self.keys.own.public_key
    success = self:send(receiverID, msg, protocol)
    return success, error_msg
end

local function _sreceive(self, protocolFilter, timeout, public_key)
    
    local sender_id, msg, protocol = self:receive(protocolFilter, timeout)
    if not msg or not msg.cipher_text or not msg.nonce or not msg.mac then
        return sender_id, nil, "No encrypted message/data/nonce received"
    end

    public_key = public_key or msg.public_key

    if not public_key then
        return sender_id, nil, "No public key provided or recieved"
    end

    local decrypted_message, err = cryptobox.box_open(
        msg.cipher_text,
        msg.nonce,
        msg.mac,
        self.keys.own.private_key,
        public_key
    )
    if err then
        return sender_id, nil, err
    end

    decrypted_message = textutils.unserialise(decrypted_message)

    if decrypted_message.id ~= sender_id then
        return sender_id, nil, "Sender did not match encrypted id"
    end

    -- Return the raw decrypted message
    return sender_id, decrypted_message, protocol
end


---
--- Sends a message using rednet and waits for a response from a specific ID.
--- @param data dataTable A table containing the following fields:
--- @return number, string, string The ID, message, and protocol of the received response.
local function _redquery(self, data, public_key)
    _ssend(self, data.id, data.msg, data.sendproto, public_key)
    local attempts = 0
    local id, msg, protocol
    repeat
        id, msg, protocol = _sreceive(self, data.recvproto, 0.1, public_key)
        attempts = attempts+1
    until id == data.id or attempts > 20
    return id, msg, protocol
end


--- init function
--- @param caller_module_name string The name of the caller requesting a instance
--- @param permissive boolean? This tells if it is allowoed to be permissive meaning not sending pubkey
--- @return cryptonet instance Returns true if the channel was successfully opened.
function cryptonet.init(caller_module_name, permissive)
    if type(caller_module_name) ~= "string" then
        error("Error: When calling init you must pass a string which is the name of the instance of your keyfile in .keys keyfiles.")
    end

    local instance = setmetatable({}, { __index = cryptonet })
    instance.caller_module_name = caller_module_name
    instance.keys = load_keyfile(caller_module_name)

    if not instance.keys.own or next(instance.keys.own) == nil then
        instance.keys.own = cryptobox.generate_keypair()
        instance.keys = reload_keyfile(caller_module_name, instance.keys)
    end
    instance.permissive = permissive

    return instance
end

--- learn function
--- @param callback function This is a print callback so i can print to the screen
--- @param id string|[number] Optional this is the id of the computer to send a request to
--- @return boolean success 
--- @return string|nil error_msg Returns true if the channel was successfully opened.
function cryptonet:learn(callback, id)
    local function extract_key_verification_digits(public_key, length)
        return public_key:sub(-length)  -- Get the last `length` digits
    end
    
    local their_public_key
    local their_id
    local complete = false
    local their_complete = false
    local verification_length = 8  -- Number of digits to verify

    -- Ensure a callback is provided.
    if not callback then
        return false, "Callback function is required."
    end

    if not id then
        -- Passive Mode: Wait for a public key reception request.
        callback("Waiting on initial key")
        local sender_id, msg, protocol = self:receive("ssg_recv_pubkey", 10)

        if msg and type(msg.public_key) then
            their_public_key = msg.public_key
        else
            return false, "No message or timed out"
        end

        their_id = sender_id
        -- Extract and display the verification digits
        local key_verification_digits = extract_key_verification_digits(their_public_key, verification_length)
        local tries = 2
        repeat
            callback("Enter the last " .. verification_length .. " digits of their key. Tries left:" .. tries)
            local input = read()
            tries = tries - 1
            if tostring(input) == key_verification_digits then
                complete = true
            elseif tries == 0 then
                return false, "Public key verification failed."
            end
        until tries == 0 or complete


        local success, err = self:send(their_id, {public_key = self.keys.own.public_key}, "ssg_recv_pubkey")
        if not success then
            return false, "Failed to send somehow..."
        end

        -- Now show our key portions
        local our_key_verification_digits = extract_key_verification_digits(self.keys.own.public_key, verification_length)
        callback("The last " .. verification_length .. " digits of our key is: " .. our_key_verification_digits)


        local _, msg, protocol = _sreceive(self, "ssg_send_complete", 300,  their_public_key)
        if msg and type(msg.complete) == "boolean" then
            their_complete = msg.complete
        else
            return false, protocol
        end

        -- Send the final confirmation with the completion status
        local success, err = _ssend(self, sender_id, {complete = complete}, "ssg_send_complete", their_public_key)
        if not success then
            return false, err
        end
    else
        their_id = id
        -- Active Mode: Initiate a request to a specific ID.
        callback("Try to send our pub key")
        local success, err = self:send(their_id, {public_key = self.keys.own.public_key}, "ssg_recv_pubkey")
        if not success then
            return false, err
        end

        -- Now show our key portions
        local our_key_verification_digits = extract_key_verification_digits(self.keys.own.public_key, verification_length)
        callback("The last " .. verification_length .. " digits of our key is: " .. our_key_verification_digits)

        -- Wait for the response with the public key.
        local sender_id, msg, protocol = self:receive("ssg_recv_pubkey", 300)
        if msg and type(msg.public_key) then
            their_public_key = msg.public_key
        else
            return false, "No message or timed out"
        end

        local key_verification_digits = extract_key_verification_digits(their_public_key, verification_length)
        local tries = 2
        repeat
            callback("Enter the last " .. verification_length .. " digits of their key. Tries left:" .. tries)
            local input = read()
            tries = tries - 1
            if tostring(input) == key_verification_digits then
                complete = true
            elseif tries == 0 then
                return false, "Public key verification failed."
            end
        until tries == 0 or complete


        -- Send the final confirmation with the completion status
        local success, err = _ssend(self, their_id, {complete = complete}, "ssg_send_complete", their_public_key)
        if not success then
            return false, err
        end

        local _, msg, protocol = _sreceive(self, "ssg_send_complete", 300,  their_public_key)
        if msg and type(msg.complete) == "boolean" then
            their_complete = msg.complete
        else
            return false, protocol
        end

    end

    if complete and their_complete then
        -- Update and save the trusted keys.
        self.keys.trusted_keys[their_id] = their_public_key
        self.keys = reload_keyfile(self.caller_module_name, self.keys)

        return true, nil  -- Successfully completed the key exchange process.
    else
        return false, "Learning failed: either incomplete or unknown error"
    end
end



--- Opens a communication channel on the specified side.
--- @param side_or_name string The side or name to open (e.g., "top", "left", etc.).
--- @return boolean success Returns true if the channel was successfully opened.
function cryptonet:open(side_or_name)
    local side_or_name = side_or_name
    if self and type(self) ~= "table" then 
        side_or_name = self
    else
        self.modem = side_or_name
    end
    if not rednet.isOpen(side_or_name) then
        rednet.open(side_or_name)
    end
    return rednet.isOpen(side_or_name)
end

--- Closes a communication channel on the specified side.
--- @param side_or_name string The side to close.
--- @return boolean success Returns true if the channel was successfully closed.
function cryptonet:close(side_or_name)
    local side_or_name = side_or_name
    if self and type(self) ~= "table" then 
        ---@diagnostic disable-next-line: cast-local-type
        side_or_name = self
    else
        self.modem = nil
    end
    if rednet.isOpen(side_or_name) then
        rednet.close(side_or_name)
    end
    return not rednet.isOpen(side_or_name)
end

--- Sends an encrypted message to a specified receiver.
--- @param receiverID number The ID of the receiver.
--- @param message any The message to send.
--- @param protocol string (optional) The protocol to use for sending the message.
--- @return boolean success, string error_msg Returns true if the message was successfully sent.
function cryptonet:ssend(receiverID, message, protocol)
    local error_msg = ""
    local success = nil
    repeat
        local public_key = self.keys.trusted_keys[receiverID]
        if not public_key then
            error_msg = "No public key found for receiver ID: " .. tostring(receiverID)
            break
        end

        -- Include this computer's ID in the message
        local data_to_encrypt = {
            ---@diagnostic disable-next-line: undefined-field
            id = os.getComputerID(),
        }
        data_to_encrypt = merge_dict(data_to_encrypt, message)
        local msg = cryptobox.box(textutils.serialize(data_to_encrypt), self.keys.own.private_key, public_key)
        msg.public_key = self.keys.own.public_key
        success = self:send(receiverID, msg, protocol)
    until true
    return success, error_msg
end

--- Securely broadcasts an encrypted message to all trusted receivers.
--- @param message any The message to broadcast.
--- @param protocol string (optional) The protocol to use for broadcasting the message.
--- @return table results Returns a table with each target ID and its corresponding success value.
function cryptonet:sdbroadcast(message, protocol)
    local results = {}

    for receiverID, _ in pairs(self.keys.trusted_keys) do
        local success = self:ssend(receiverID, message, protocol)
        -- Store the result for each receiver
        results[receiverID] = success
    end

    return results
end

--- Receives and decrypts a message from the network.
--- @param protocolFilter string (optional) The protocol to filter received messages by.
--- @param timeout [number] (optional) The timeout in seconds to wait for a message.
--- @return number sender_id The ID of the sender.
--- @return table|nil decrypted_message The decrypted message, or nil if an error occurred.
--- @return string protocol The protocol used for the message.
function cryptonet:sreceive(protocolFilter, timeout)
    
    local sender_id, msg, protocol = self:receive(protocolFilter, timeout)
    if not msg or not msg.cipher_text or not msg.nonce or not msg.mac then
        return sender_id, nil, "No encrypted message/data/nonce received"
    end

    -- Assume the sender ID is correct and try to decrypt
    local key_data = self.keys.trusted_keys[sender_id]
    if not key_data then
        return sender_id, nil, "No public key found for Sender ID: " .. tostring(sender_id)
    end

    if msg.public_key ~= key_data and not self.permissive then
        return sender_id, nil, "Trusted key does not match for Sender ID: " .. tostring(sender_id)
    end

    local decrypted_message, err = cryptobox.box_open(
        msg.cipher_text,
        msg.nonce,
        msg.mac,
        self.keys.own.private_key,
        key_data
    )
    if err then
        return sender_id, nil, err
    end

    decrypted_message = textutils.unserialise(decrypted_message)

    if decrypted_message.id ~= sender_id then
        return sender_id, nil, "Sender did not match encrypted id"
    end

    -- Return the raw decrypted message
    return sender_id, decrypted_message, protocol
end

--- Broadcasts a message to all receivers.
--- @param message any The message to broadcast.
--- @param protocol string (optional) The protocol to use for broadcasting the message.
--- @return boolean success Returns true if the message was successfully broadcasted.
function cryptonet:broadcast(message, protocol)
    local message = message
    local protocol = protocol
    if self and type(self) ~= "table" then
        protocol = message
        message = self
    end
    --- Implement the function to broadcast a message
    return rednet.broadcast(message,protocol)
end

--- Receives a message from the network.
--- @param protocolFilter string|nil (optional) The protocol to filter received messages by.
--- @param timeout number|nil (optional) The timeout in seconds to wait for a message.
--- @return any message, string protocol Returns the received message and the protocol used.
function cryptonet:receive(protocolFilter, timeout)
    local protocolFilter = protocolFilter
    local timeout = timeout
    if self and type(self) ~= "table" then
        ---@diagnostic disable-next-line: cast-local-type
        timeout = protocolFilter
        protocolFilter = self
    end
    --- Implement the function to receive a message
    return rednet.receive(protocolFilter, timeout)
end

--- Sends a message over the network.
--- @param receiverID number|string The ID of the receiver to send the message to.
--- @param msg any The message to send.
--- @param protocol string|nil (optional) The protocol to send the message with.
--- @return boolean success Returns true if the message was sent successfully, otherwise false.
function cryptonet:send(receiverID, msg, protocol)
    local receiverID = receiverID
    local msg = msg
    local protocol = protocol
    if self and type(self) ~= "table" then
        protocol = msg
        msg = receiverID
        receiverID = self
    end
    --- Implement the function to receive a message
    return rednet.send(receiverID, msg, protocol)
end


--- Checks if a communication channel is open on the specified side.
--- @param side string The side to check (e.g., "top", "left", etc.).
--- @return boolean isOpen Returns true if the channel is open.
function cryptonet:isOpen(side)
    if self and type(self) ~= "table" then
        side = self
    end
    --- Implement the function to check if communication is open on the given side
    return rednet.isOpen(side)
end

--- Hosts a service under a specific protocol and hostname.
--- @param protocol string The protocol to host the service under.
--- @param hostname string The hostname to associate with the service.
--- @return boolean success Returns true if the service was successfully hosted.
function cryptonet:host(protocol)
    local protocol = protocol
    local id = nil
    if self and type(self) ~= "table" then
        id = protocol
        protocol = self
    end
    --- Implement the function to host a service
    return rednet.host(protocol, id or tostring(os.getComputerID()))
end

--- Unhosts a service under a specific protocol and hostname.
--- @param protocol string The protocol the service was hosted under.
--- @param hostname string The hostname associated with the service.
--- @return boolean success Returns true if the service was successfully unhosted.
function cryptonet:unhost(protocol)
    --- Implement the function to unhost a service
    local protocol = protocol
    local id = nil
    if self and type(self) ~= "table" then
        id = protocol
        protocol = self
    end
    return rednet.unhost(protocol, id or tostring(os.getComputerID()))
end

--- Looks up a service hosted under a specific protocol and optional hostname.
--- @param protocol string The protocol to search under.
--- @param hostname string (optional) The hostname to search for.
--- @return table services Returns a table of services matching the criteria.
function cryptonet:lookup(protocol, hostname)
    --- Implement the function to lookup services
    local protocol = protocol
    local hostname = hostname
    if self and type(self) ~= "table" then
        hostname = protocol
        protocol = self
    end
    return rednet.lookup(protocol, hostname)
end

return cryptonet
