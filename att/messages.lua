-- messages.lua
-- Centralized configuration for chat announcements (LS/LS2)

local messages = {}

-- Message Templates
-- %s placeholders are replaced by the addon logic.

-- When Self-Attendance starts (/att sa <event>)
-- Params: Event Name
messages.SA_START = "Self-attendance started for %s. Type !here or !present to confirm your attendance"

-- When attendance is written to file (HNM mode)
-- Params: Event Name
messages.HNM_TAKEN = "HNM Attendance taken for: %s"

-- When attendance is written to file (Event mode)
-- Params: Event Name
messages.EVENT_TAKEN = "Event Attendance taken for: %s"

-- When showing pending self-attendance list in LS chat
-- Params: List of names (comma separated)
messages.PENDING_LIST = "Pending: %s"

return messages
