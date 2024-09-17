local script_version = "1.0"
-- Import necessary modules

local x25519 = require  "ccryptolib.x25519"
local chacha20 = require "ccryptolib.chacha20"
local poly1305 = require "ccryptolib.poly1305"
local util = require "ccryptolib.util"
local random = require "ccryptolib.random"
random.initWithTiming()

--- Generates a random 32-byte private key for EC25519
--- @return string private_key A string representing a 32-byte EC25519 compliant private key
local function generate_ec25519_compliant_private_key()
    local key = {}
    for i = 1, 32 do
        -- Generate a random byte
        local byte = math.random(0, 255)
        -- Insert the byte into the key table
        table.insert(key, byte)
    end

    -- Perform necessary bit manipulations for EC25519
    key[1] = bit.band(key[1], 248)      -- Clear the last 3 bits
    key[32] = bit.band(key[32], 127)    -- Clear the first bit
    key[32] = bit.bor(key[32], 64)      -- Set the second highest bit

    local key_str = ""
    for i = 1, #key do
        key_str = key_str .. string.char(key[i])
    end
    return util.toHex(key_str)
end

--- Generates a public key from a given private key
--- @param private_key string A string representing a 32-byte EC25519 compliant private key
--- @return string public_key A string representing the public key
local function generate_public_key(private_key)
    return util.toHex(x25519.publicKey(private_key))
end

--- Generates an EC25519 keypair
--- @return table keys A table containing a public_key and a private_key
local function generate_keypair()
    local private_key = generate_ec25519_compliant_private_key()
    local public_key = generate_public_key(util.fromHex(private_key))
    return { public_key = public_key, private_key = private_key }
end

--- Generates a nonce
--- @return string nonce A string representing a i-byte nonce
local function generate_nonce(bytes_len)
    -- Generate i random bytes
    local random_bytes = {}
    for i = 1, bytes_len do
        table.insert(random_bytes, math.random(0, 255))
    end

    -- Get the timestamp
    local data = http.get("https://cookta2012.com/minecraft/cc/epoch.php")
    local time = data.readAll() 
    local unix_time = tonumber(time)

    -- Convert timestamp to byte string
    local timestamp_bytes = {}
    for i = 1, 8 do
        table.insert(timestamp_bytes, 1, unix_time % 256)
        unix_time = math.floor(unix_time / 256)
    end
    -- Pad the timestamp bytes to bytes bytes if necessary
    while #timestamp_bytes < bytes_len do
        table.insert(timestamp_bytes, 1, math.random(0, 255))
    end

    -- XOR the random bytes with the timestamp bytes
    local nonce = ""
    for i = 1, bytes_len do
        local random_byte = random_bytes[i]
        local timestamp_byte = timestamp_bytes[i]
        local xor_byte = bit.bxor(random_byte, timestamp_byte)
        nonce = nonce .. string.char(xor_byte)
    end

    return nonce
end

--- Encrypts a plaintext message using ChaCha20 and generates a MAC with Poly1305
--- @param plain_text string A string representing the plaintext to encrypt
--- @param nonce string A string representing the nonce
--- @param shared_key string A string representing the shared key
--- @return table datastruct #string mac, string nonce, string cipher_text A multivalue return of mac, nonce, and ciphertext
local function secretbox(plain_text, nonce, shared_key)
    local shared_key = util.fromHex(shared_key)
    local cipher_text = chacha20.crypt(shared_key, nonce, plain_text, 20)
    local mac = poly1305.mac(shared_key, cipher_text)
    return {mac = mac, nonce = nonce, cipher_text = cipher_text}
end

--- Decrypts a ciphertext message using ChaCha20 and verifies the MAC with Poly1305
--- @param cipher_text string A string representing the ciphertext to decrypt
--- @param nonce string A string representing the nonce
--- @param mac string A string representing the MAC
--- @param shared_key string A string representing the shared key
--- @return string|nil plain_text, nil|string error A string representing the plaintext if the MAC is valid, otherwise nil and an error message
local function secretbox_open(cipher_text, nonce, mac, shared_key)
    local shared_key = util.fromHex(shared_key)
    local mac2 = poly1305.mac(shared_key, cipher_text)
    if mac2 ~= mac then return nil, "Message has been tampered with" end
    local plain_text = chacha20.crypt(shared_key, nonce, cipher_text, 20)
    return plain_text
end

--- Generates a shared key from a private key and a public key using X25519
--- @param private_key string A string representing a 32-byte private key
--- @param public_key string A string representing the public key
--- @return string shared_key A string representing the shared key
local function generate_shared_key(private_key, public_key)
    return util.toHex(x25519.exchange(util.fromHex(private_key), util.fromHex(public_key)))
end

--- Encrypts a plaintext message using X25519 and ChaCha20-Poly1305
--- @param plain_text string A string representing the plaintext to encrypt
--- @param private_key string A string representing a 32-byte private key
--- @param public_key string A string representing the public key
--- @return table datastruct A multivalue return of mac, nonce, and ciphertext
local function box(plain_text, private_key, public_key)
    return secretbox(plain_text, generate_nonce(12), generate_shared_key(private_key, public_key))
end

--- Decrypts a ciphertext message using X25519 and ChaCha20-Poly1305
--- @param cipher_text string A string representing the ciphertext to decrypt
--- @param nonce string A string representing the nonce
--- @param private_key string A string representing a 32-byte private key
--- @param public_key string A string representing the public key
--- @return string|nil plain_text, nil|string error A string representing the plaintext if the MAC is valid, otherwise nil and an error message
local function box_open(cipher_text, nonce, mac, private_key, public_key)
    return secretbox_open(cipher_text, nonce, mac, generate_shared_key(private_key, public_key))
end

return {
    generate_keypair = generate_keypair,
    generate_public_key = generate_public_key,
    generate_nonce = generate_nonce,
    secretbox = secretbox,
    secretbox_open = secretbox_open,
    generate_shared_key = generate_shared_key,
    box = box,
    box_open = box_open,
}
