-- messages.lua
-- Centralized configuration for chat announcements (LS/LS2)

local messages = {}

-- FFXI uses Shift-JIS encoding formatting. Standard UTF-8 characters from an editor get 
-- garbled in game. Using string.char sends the exact bytes FFXI needs to render the symbols.
local STAR_SOLID = string.char(129, 154)  -- ★
local STAR_HOLLOW = string.char(129, 153) -- ☆
local DEC_HNM = STAR_SOLID .. STAR_HOLLOW .. STAR_SOLID
local DEC_EV  = STAR_HOLLOW .. STAR_SOLID .. STAR_HOLLOW

-- Message Templates
-- %s placeholders are replaced by the addon logic.

-- When Self-Attendance starts (/att sa <event>)
-- Params: Event Name
messages.SA_START = DEC_EV .. " Self-attendance started for %s. Type !here or !present to confirm your attendance " .. DEC_EV

-- When attendance is written to file (HNM mode)
-- Params: Event Name
messages.HNM_TAKEN = DEC_HNM .. " HNM Attendance taken for: %s " .. DEC_HNM

-- When attendance is written to file (Event mode)
-- Params: Event Name
messages.EVENT_TAKEN = DEC_EV .. " Event Attendance taken for: %s " .. DEC_EV

-- When showing pending self-attendance list in LS chat
-- Params: List of names (comma separated)
messages.PENDING_LIST = STAR_SOLID .. " Pending: %s " .. STAR_SOLID

return messages
