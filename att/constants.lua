-- constants.lua
local constants = {}

constants.STRIDE_CANDIDATES = { 0x4C, 0x50 }
constants.NAME_OFFSETS      = { 0x08, 0x04 }
constants.ZONE_OFFSETS      = { 0x2C, 0x28 }
constants.MJ_OFFSETS        = { 0x24, 0x20 }
constants.SJ_OFFSETS        = { 0x25, 0x21 }
constants.NAME_LENGTHS      = { 16, 15 }

constants.DEFAULT_SA_DURATION = 300
constants.CONFIRM_COMMANDS    = { 'here', 'present', 'herebrother' }

return constants
