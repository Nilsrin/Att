addon.name      = 'att';
addon.author    = 'literallywho, edited by Nils';
addon.version   = '1.2';
addon.desc      = 'takes attendance';

require('common');
local chat = require('chat');
local zoneList = {}
local jobList = {}

local shortNames = {
    ['default'] = "Current Zone",
    [''] = "Current Zone",
    ['Default'] = "Current Zone",
    ['faf'] = "Fafnir/Nidhogg",
    ['fafnir'] = "Fafnir/Nidhogg",
    ['nid'] = "Fafnir/Nidhogg",
    ['nidhogg'] = "Fafnir/Nidhogg",
    ['fafhogg'] = "Fafnir/Nidhogg",
    ['Faf'] = "Fafnir/Nidhogg",
    ['Fafnir'] = "Fafnir/Nidhogg",
    ['Nid'] = "Fafnir/Nidhogg",
    ['Nidhogg'] = "Fafnir/Nidhogg",
    ['Fafhogg'] = "Fafnir/Nidhogg",
    ['jorm'] = "Jormungand",
    ['Jorm'] = "Jormungand",
    ['shiki'] = "Shikigami Weapon",
    ['shikigami'] = "Shikigami Weapon",
    ['Shiki'] = "Shikigami Weapon",
    ['Shikigami'] = "Shikigami Weapon",
    ['tiamat'] = "Tiamat",
    ['tia'] = "Tiamat",
    ['Tiamat'] = "Tiamat",
    ['Tia'] = "Tiamat",
    ['vrtra'] = "Vrtra",
    ['Vrtra'] = "Vrtra",
    ['ka'] = "King Arthro",
    ['Ka'] = "King Arthro",
    ['kv'] = "King Vinegarroon",
    ['Kv'] = "King Vinegarroon",
    ['KV'] = "King Vinegarroon",
    ['kb'] = "(King) Behemoth",
    ['behe'] = "(King) Behemoth",
    ['Kb'] = "(King) Behemoth",
    ['Behe'] = "(King) Behemoth",
    ['turtle'] = "Aspidochelone/Adamantoise",
    ['aspi'] = "Aspidochelone/Adamantoise",
    ['aspid'] = "Aspidochelone/Adamantoise",
    ['Turtle'] = "Aspidochelone/Adamantoise",
    ['Aspi'] = "Aspidochelone/Adamantoise",
    ['Aspid'] = "Aspidochelone/Adamantoise",
    ['kirin'] = "Sky/Kirin",
    ['sky'] = "Sky/Kirin",
    ['Kirin'] = "Sky/Kirin",
    ['Sky'] = "Sky/Kirin",
    ['dyna'] = "Dynamis",
    ['Dyna'] = "Dynamis",
    ['xolo'] = "Xolotl",
    ['xolotl'] = "Xolotl",
    ['Xolo'] = "Xolotl",
    ['Xolotl'] = "Xolotl",
    ['bloodsucker'] = "Bloodsucker",
    ['bs'] = "Bloodsucker",
    ['Bloodsucker'] = "Bloodsucker",
    ['Bs'] = "Bloodsucker",
    ['ouryu'] = "Ouryu",
    ['Ouryu'] = "Ouryu",
    ['bahav2'] = "Bahamut",
    ['baha'] = "Bahamut",
    ['bahamut'] = "Bahamut",
    ['Bahav2'] = "Bahamut",
    ['Baha'] = "Bahamut",
    ['Bahamut'] = "Bahamut",
    ['sea'] = "Sea",
    ['Sea'] = "Sea",
    ['limbus'] = "Limbus",
    ['Limbus'] = "Limbus",
    ['simurgh'] = "Simurgh",
    ['Simurgh'] = "Simurgh",
    ['oa'] = "Overlord Arthro",
    ['OA'] = "Overlord Arthro",
    ['henmcrab'] = "Overlord Arthro",
    ['crab'] = "Overlord Arthro",
    ['HENMCrab'] = "Overlord Arthro",
    ['Crab'] = "Overlord Arthro",
    ['rr'] = "Ruinous Rocs",
    ['RR'] = "Ruinous Rocs",
    ['henmbirds'] = "Ruinous Rocs",
    ['rocs'] = "Ruinous Rocs",
    ['HENMRocs'] = "Ruinous Rocs",
    ['Rocs'] = "Ruinous Rocs",
    ['ss'] = "Sacred Scorpions",
    ['SS'] = "Sacred Scorpions",
    ['henmscorps'] = "Sacred Scorpions",
    ['scorps'] = "Sacred Scorpions",
    ['HENMScorps'] = "Sacred Scorpions",
    ['Scorps'] = "Sacred Scorpions",
    ['mammet'] = "Mammet-9999",
    ['9999'] = "Mammet-9999",
    ['Mam'] = "Mammet-9999",
    ['Mammet'] = "Mammet-9999",
    ['mam'] = "Mammet-9999",
    ['ultimega'] = "Ultimega",
    ['Ultimega'] = "Ultimega",
    ['UO'] = "Ultimega",
    ['uo'] = "Ultimega",
    ['tonberry'] = "Tonberry Sovereign",
    ['Tonberry'] = "Tonberry Sovereign",
    ['Ton'] = "Tonberry Sovereign",
    ['ton'] = "Tonberry Sovereign",
    ['Sov'] = "Tonberry Sovereign",
    ['sov'] = "Tonberry Sovereign"
};

local creditNames = {
    ['Current Zone'] = {},
    ['Fafnir/Nidhogg'] = {"Dragons_Aery"},
    ['Jormungand'] = {"Uleguerand_Range"},
    ['Shikigami Weapon'] = {"RoMaeve"},
    ['Tiamat'] = {"Attohwa_Chasm"},
    ['Vrtra'] = {"King_Ranperres_Tomb"},
    ['King Arthro'] = {"Jugner_Forest"},
    ['King Vinegarroon'] = {"Western_Altepa_Desert"},
    ['(King) Behemoth'] = {"Behemoths_Dominion"},
    ['Aspidochelone/Adamantoise'] = {"Valley_of_Sorrows"},
    ['Sky/Kirin'] = {"RuAun_Gardens", "The_Shrine_of_RuAvitau", "VeLugannon_Palace", "LaLoff_Amphitheater", "Stellar_Fulcrum", "The_Celestial_Nexus"},
    ['Dynamis'] = {"Dynamis-Valkurm", "Dynamis-Buburimu", "Dynamis-Qufim", "Dynamis-Tavnazia", "Dynamis-Beaucedine", "Dynamis-Xarcabard", "Dynamis-San_dOria", "Dynamis-Bastok", "Dynamis-Windurst", "Dynamis-Jeuno"},
    ['Bloodsucker'] = {"Bostaunieux_Oubliette"},
    ['Simurgh'] = {"Rolanberry_Fields"},
    ['Ouryu'] = {"Riverne-Site_A01", "Lufaise_Meadows"},
    ['Bahamut'] = {"Riverne-Site_B01", "Lufaise_Meadows"},
    ['Sea'] = {"Sealions_Den", "AlTaieu", "The_Garden_of_RuHmet", "Grand_Palace_of_HuXzoi", "Empyreal_Paradox"},
    ['Limbus'] = {"Temenos", "Apollyon"},
    ['Overlord Arthro'] = {"Jugner_Forest"},
    ['Ruinous Rocs'] = {"Rolanberry_Fields"},
    ['Sacred Scorpions'] = {"Sauromugue_Champaign"},
    ['Xolotl'] = {"Attohwa_Chasm"},
    ['Mammet-9999'] = {"Misareaux_Coast"},
    ['Ultimega'] = {"Lufaise_Meadows"},
    ['Tonberry Sovereign'] = {"Yhoator_Jungle"}
};

local function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local function value_index(tab, val)
    local i = 0;
    for index, value in ipairs(tab) do
        i = i + 1;
        if value == val then
            return i;
        end
    end
    return i;
end

ashita.events.register('unload', 'unload_cb', function ()
    -- Cleanup if needed
end);

ashita.events.register('load', 'load_cb', function ()
    for line in io.lines(addon.path .. "zones.csv") do
        local index, name = line:match("%i*(.-),%s*(.-),")
        table.insert(zoneList, index, name)
    end

    for line in io.lines(addon.path .. "jobs.csv") do
        local index, name = line:match("%i*(.-),%s*(.-),")
        table.insert(jobList, index, name)
    end
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    
    if (#args == 0 or args[1] ~= '/att') then
        return;
    end

    if (#args >= 1) then
        local date = os.date('*t');
        local time = os.date("*t");
        local printTime = os.date(("%02d.%02d.%02d"):format(time.hour, time.min, time.sec));
        local filePath;

        local isAnon = {};
        local names = {};
        local zones = {};
        local jobsMain = {};
        local jobsSub = {};
        local jobsMainLvl = {};
        local jobsSubLvl = {};
        local currZone = "";
        local pCounter = 0;

        local basePointerAddr = ashita.memory.read_int32(ashita.memory.find('FFXiMain.dll', 0, '??', 0x62D014, 0));
        basePointerAddr = basePointerAddr + 12;    
        local numResults = ashita.memory.read_int32(basePointerAddr);
        basePointerAddr = basePointerAddr + 20;
        local listPointerAddr = ashita.memory.read_int32(basePointerAddr);
        currZone = zoneList[ashita.memory.read_uint8(ashita.memory.find('FFXiMain.dll', 0, '??', 0x452818, 0))];
        
        creditNames['Current Zone'][1] = currZone;

        local lsMode = has_value(args, 'ls');
        local eventMode = has_value(args, 'e');
        local hMode = has_value(args, 'h'); -- Check for the 'h' argument

        -- Set the file path based on the argument
        if hMode then
            filePath = addon.path .. "\\HNM Logs\\" .. os.date("%A %d %B %Y") .. " " .. printTime .. ".csv";
        else
            filePath = addon.path .. "\\Event Logs\\" .. os.date("%A %d %B %Y") .. " " .. printTime .. ".csv";
        end

        local file = io.open(filePath, "a");

        -- Determine the start index and mode
        local startIndex = 0;
        if (#args == 1) then
            print("Running in basic mode.");
            startIndex = 1;
            numResults = numResults + 2;
        elseif (lsMode) then
            print("Running in LS mode. LS mode supports over 40 players.");
            startIndex = 0;
        end
        
        local eventName = 'Current Zone';
        if (eventMode or hMode) then -- Check for both event mode and hMode
            eventName = value_index(args, 'e');
            if has_value(args, 'h') then
                eventName = value_index(args, 'h');
            end
            eventName = eventName + 1; -- Move to the actual event name
            local shortName = args[eventName]; -- Get the short name argument
            eventName = shortNames[shortName]; -- Get the full event name
            
            print("Running in event mode.");
            if eventName then
                -- Determine the message based on the command used
                local messagePrefix = hMode and "HNM Attendance has been taken for: " or "Event Attendance has been taken for: ";
                local message = messagePrefix .. eventName;
                
                AshitaCore:GetChatManager():QueueCommand(1, '/l ' .. message)
                coroutine.sleep(1.5);
            else
                print("Invalid event name specified.");
            end
        end;
        
        print("Eligible zones for attendance: ");
        for i = 1, #creditNames[eventName], 1 do
            print(creditNames[eventName][i]);
        end;
        
        if (numResults > 40) then
            if (lsMode == false) then
                print("Error: Search results, and therefore attendance data, is truncated! Use the linkshell mode along with the linkshell menu instead (/att ls).");
            end;
        end;

        for i = startIndex, numResults, 1 do
            if (i == numResults) then break; end;
            
            isAnon[i] = ashita.memory.read_int8(0x04 + listPointerAddr + 0x0); -- 7F: normal, 43: anon

            names[i] = ashita.memory.read_string(0x04 + listPointerAddr + 0x4, 15); -- length 13, names get truncated!
            zones[i] = zoneList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x28)]; -- zoneID file included
            
            jobsMain[i] = jobList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x20)];
            jobsSub[i] = jobList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x21)];    
            
            jobsMainLvl[i] = ashita.memory.read_uint8(0x04 + listPointerAddr + 0x22);
            jobsSubLvl[i] = ashita.memory.read_uint8(0x04 + listPointerAddr + 0x23);    

            if (has_value(creditNames[eventName], zones[i])) then
                pCounter = pCounter + 1;
                file:write(names[i] .. "," .. jobsMain[i] .. "," .. os.date("%m/%d/%Y") .. "," .. os.date(("%02d:%02d:%02d"):format(time.hour, time.min, time.sec)) .. "," .. zones[i] .. "," .. eventName .. "\n");
            end;
            
            listPointerAddr = listPointerAddr + 76; -- each entry is 76 bytes large
        end;        

        print(pCounter .. " players accounted for.");
        print("Attendance Filename: " .. os.date("%A %d %B %Y") .. " " .. os.date(("%02d:%02d:%02d"):format(time.hour, time.min, time.sec)) .. ".csv");

        file:close();
        return;
    end;
end);
