-- memory.lua
local memory = {}
local memory = {}


-- Constants from Reference Logic
local STRIDE_CANDIDATES = { 0x4C, 0x50 }
local NAME_OFFSETS      = { 0x08, 0x04 }
local ZONE_OFFSETS      = { 0x2C, 0x28 }
local MJ_OFFSETS        = { 0x24, 0x20 }
local SJ_OFFSETS        = { 0x25, 0x21 }
local NAME_LENGTHS      = { 16, 15 }

-- Small helpers
local function trim(s)
    return (tostring(s or ''):gsub('^%s*(.-)%s*$', '%1'))
end

local function sanitize_name(raw)
    if not raw then return '' end
    raw = raw:gsub('%z+$', ''):gsub('[\r\n]+', '')
    return trim(raw)
end

local function is_plausible_name(s)
    s = tostring(s or '')
    return #s >= 2
       and #s <= 15
       and (not s:find('[%z\001-\008\011\012\014-\031]'))
end

-- Safe read helpers
function memory.safe_read_u32(addr)
    local val = 0
    local status = pcall(function()
        val = ashita.memory.read_uint32(addr)
    end)
    if status then return val else return 0 end
end

function memory.safe_read_string(addr, len)
    local str = nil
    local status = pcall(function()
        str = ashita.memory.read_string(addr, len)
    end)
    if status then return str else return nil end
end

-- Player Location (Preserved as requested)
function memory.get_current_zone_id()
    return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
end

-- Reference Logic: Detect Stride
local function detect_stride(count, listPtr)
    local bestStride = STRIDE_CANDIDATES[1]
    local bestScore  = -1

    for _, stride in ipairs(STRIDE_CANDIDATES) do
        local seen, uniq = {}, 0
        -- Reference used full count, but we can limit sample for speed if count > 100
        -- For now, follow reference: iterate logic
        for i = 0, (count > 0 and count - 1 or 0) do
            local entry = listPtr + (i * stride)
            local name  = ''

            for _, noff in ipairs(NAME_OFFSETS) do
                for _, nlen in ipairs(NAME_LENGTHS) do
                    local cand = sanitize_name(memory.safe_read_string(entry + noff, nlen))
                    if is_plausible_name(cand) then name = cand break end
                end
                if name ~= '' then break end
            end

            if name ~= '' and not seen[name] then
                seen[name] = true
                uniq       = uniq + 1
            end
        end

        if uniq > bestScore then
            bestScore  = uniq
            bestStride = stride
        end
    end

    return bestStride
end

-- Reference Logic: Read Cell
local function read_cell(entry)
    local name = ''
    for _, noff in ipairs(NAME_OFFSETS) do
        for _, nlen in ipairs(NAME_LENGTHS) do
            local cand = sanitize_name(memory.safe_read_string(entry + noff, nlen))
            if is_plausible_name(cand) then
                name = cand
                break
            end
        end
        if name ~= '' then break end
    end

    local zid = 0
    for _, zoff in ipairs(ZONE_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + zoff)
        if v ~= nil then
            zid = v
            break
        end
    end

    local mj, sj = 0, 0
    for _, moff in ipairs(MJ_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + moff)
        if v ~= nil then
            mj = v
            break
        end
    end
    for _, soff in ipairs(SJ_OFFSETS) do
        local v = ashita.memory.read_uint8(entry + soff)
        if v ~= nil then
            sj = v
            break
        end
    end

    return name, zid, mj, sj
end

local function is_header_row(name, zid, mj, sj)
    return (name == '' and zid == 0 and mj == 0 and sj == 0)
end

-- Main Scan Function
function memory.scan_zone_list()
    local resultList = {}
    
    -- 1. Get List Pointer
    local mgrPtr = memory.find_entity_list()
    if mgrPtr == 0 then return resultList end
    
    -- 2. Read Structure
    local count   = memory.safe_read_u32(mgrPtr + 0xC)
    local listPtr = memory.safe_read_u32(mgrPtr + 0x20)
    
    if listPtr == 0 then return resultList end
    if count > 4096 then count = 4096 end
    
    -- 3. Detect Stride
    local stride = detect_stride(count, listPtr)
    
    -- 4. Inclusive Scan (loop 0 to count, AND count+1)
    for i = 0, count do
        local entry = listPtr + (i * stride)
        local name, zid, mj, sj = read_cell(entry)
        
        if not is_header_row(name, zid, mj, sj) then
            if name ~= '' then
                 -- Store in result list
                 if not resultList[name] then
                     resultList[name] = { zid = zid, mj = mj, sj = sj }
                 end
            end
        end
    end
    
    -- Check count + 1 just in case (reference does this)
    local entry = listPtr + ((count + 1) * stride)
    local name, zid, mj, sj = read_cell(entry)
    if name ~= '' and not is_header_row(name, zid, mj, sj) then
         if not resultList[name] then
             resultList[name] = { zid = zid, mj = mj, sj = sj }
         end
    end
    
    return resultList
end

-- Offset Management
memory.manual_offset = 0x62F73C -- Verified Horizon/LSB Offset

function memory.get_main_module_base()
    return ashita.memory.find('FFXiMain.dll', 0, '4D5A', 0, 0)
end

function memory.find_entity_list()
    if memory.manual_offset ~= 0 then
        local base = memory.get_main_module_base()
        if base == 0 then base = 0x400000 end
        
        local addr = base + memory.manual_offset
        if memory.manual_offset > 0x10000000 then 
             addr = memory.manual_offset 
        end
        
        return ashita.memory.read_uint32(addr)
    end
    return 0 -- Should not be reached with manual offset set
end

return memory
