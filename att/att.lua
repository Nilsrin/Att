addon.name      = 'att';
addon.author    = 'literallywho, edited by Nils';
addon.version   = '1.1';
addon.desc      = 'takes attendance';

require('common');
local chat = require('chat');
local zoneList = {}
local jobList = {}

local shortNames = {

	['default'] = "Current Zone",
	[''] = "Current Zone",
    ['faf'] = "Fafnir/Nidhogg",
	['fafnir'] = "Fafnir/Nidhogg",
    ['nid'] = "Fafnir/Nidhogg",
	['nidhogg'] = "Fafnir/Nidhogg",
    ['fafhogg'] = "Fafnir/Nidhogg",
    ['jorm'] = "Jormungand",
    ['shiki'] = "Shikigami Weapon",
	['shikigami'] = "Shikigami Weapon",
    ['tiamat'] = "Tiamat",
    ['tia'] = "Tiamat",
    ['vrtra'] = "Vrtra",
    ['ka'] = "King Arthro",
    ['kv'] = "King Vinegarroon",
    ['kb'] = "(King) Behemoth",
    ['behe'] = "(King) Behemoth",
    ['turtle'] = "Aspidochelone/Adamantoise",
    ['aspi'] = "Aspidochelone/Adamantoise",
    ['aspid'] = "Aspidochelone/Adamantoise",
    ['kirin'] = "Sky/Kirin",
    ['sky'] = "Sky/Kirin",
    ['dyna'] = "Dynamis",
	['xolo'] = "Xolotl",
	['xolotl'] = "Xolotl",
	['bloodsucker'] = "Bloodsucker",
	['bs'] = "Bloodsucker",
	['ouryu'] = "Ouryu",
	['bahav2'] = "Bahamut",
	['baha'] = "Bahamut",
	['bahamut'] = "Bahamut",
	['sea'] = "Sea",
	['limbus'] = "Limbus",
	['Default'] = "Current Zone",
    ['Faf'] = "Fafnir/Nidhogg",
	['Fafnir'] = "Fafnir/Nidhogg",
    ['Nid'] = "Fafnir/Nidhogg",
	['Nidhogg'] = "Fafnir/Nidhogg",
    ['Fafhogg'] = "Fafnir/Nidhogg",
    ['Jorm'] = "Jormungand",
    ['Shiki'] = "Shikigami Weapon",
	['Shikigami'] = "Shikigami Weapon",
    ['Tiamat'] = "Tiamat",
    ['Tia'] = "Tiamat",
    ['Vrtra'] = "Vrtra",
    ['Ka'] = "King Arthro",
    ['Kv'] = "King Vinegarroon",
	['KV'] = "King Vinegarroon",
    ['Kb'] = "(King) Behemoth",
    ['Behe'] = "(King) Behemoth",
    ['Turtle'] = "Aspidochelone/Adamantoise",
    ['Aspi'] = "Aspidochelone/Adamantoise",
    ['Aspid'] = "Aspidochelone/Adamantoise",
    ['Kirin'] = "Sky/Kirin",
    ['Sky'] = "Sky/Kirin",
    ['Dyna'] = "Dynamis",
	['Xolo'] = "Xolotl",
	['Xolotl'] = "Xolotl",
	['Bloodsucker'] = "Bloodsucker",
	['Bs'] = "Bloodsucker",
	['Ouryu'] = "Ouryu",
	['Bahav2'] = "Bahamut",
	['Baha'] = "Bahamut",
	['Bahamut'] = "Bahamut",
	['Sea'] = "Sea",
	['Limbus'] = "Limbus",
	['simurgh'] = "Simurgh",
	['Simurgh'] = "Simurgh",
	['OA'] = "Overlord Arthro",
	['RR'] = "Ruinous Rocs",
	['SS'] = "Sacred Scorpions",
	['henmcrab'] = "Overlord Arthro",
	['henmbirds'] = "Ruinous Rocs",
	['henmscorps'] = "Sacred Scorpions",
	['crab'] = "Overlord Arthro",
	['rocs'] = "Ruinous Rocs",
	['scorps'] = "Sacred Scorpions",
	['oa'] = "Overlord Arthro",
	['rr'] = "Ruinous Rocs",
	['ss'] = "Sacred Scorpions",
	['HENMCrab'] = "Overlord Arthro",
	['HENMRocs'] = "Ruinous Rocs",
	['HENMScorps'] = "Sacred Scorpions",
	['Crab'] = "Overlord Arthro",
	['Rocs'] = "Ruinous Rocs",
	['Scorps'] = "Sacred Scorpions",
	['Mammet'] = "Mammet-9999",
	['mammet'] = "Mammet-9999",
	['9999'] = "Mammet-9999",
	['Mam'] = "Mammet-9999",
	['mam'] = "Mammet-9999",
	['Ultimega'] = "Ultimega",
	['ultimega'] = "Ultimega",
	['UO'] = "Ultimega",
	['uo'] = "Ultimega",
	['Tonberry'] = "Tonberry Sovereign",
	['tonberry'] = "Tonberry Sovereign",
	['Ton'] = "Tonberry Sovereign",
	['ton'] = "Tonberry Sovereign",
	['Sov'] = "Tonberry Sovereign",
	['sov'] = "Tonberry Sovereign"
	
};

local creditNames = {
	['Current Zone'] = {  },
	['Fafnir/Nidhogg'] = { "Dragons_Aery"},
	['Jormungand'] = { "Uleguerand_Range" },
	['Shikigami Weapon'] = { "RoMaeve" },
	['Tiamat'] = { "Attohwa_Chasm"},
	['Vrtra'] = { "King_Ranperres_Tomb" },
	['King Arthro'] = { "Jugner_Forest" }, 
	['King Vinegarroon'] = { "Western_Altepa_Desert" }, 
	['(King) Behemoth'] = { "Behemoths_Dominion"}, 
	['Aspidochelone/Adamantoise'] = { "Valley_of_Sorrows"}, 
	['Sky/Kirin'] = { "RuAun_Gardens", "The_Shrine_of_RuAvitau", "VeLugannon_Palace", "LaLoff_Amphitheater", "Stellar_Fulcrum", "The_Celestial_Nexus" },
	['Dynamis'] = { "Dynamis-Valkurm", "Dynamis-Buburimu", "Dynamis-Qufim", "Dynamis-Tavnazia", "Dynamis-Beaucedine", "Dynamis-Xarcabard", "Dynamis-San_dOria", "Dynamis-Bastok", "Dynamis-Windurst", "Dynamis-Jeuno" },
	['Bloodsucker'] = { "Bostaunieux_Oubliette" },
	['Simurgh'] = { "Rolanberry_Fields" },
	['Serket'] = { "Garlaige_Citadel" },
    ['Sea'] = { "Al'Taieu", "Grand_Palace_of_Hu'Xzoi", "The_Garden_of_Ru'Hmet" },
	['Bahamut'] = { "Riverne-Site_B01", "Lufaise_Meadows" },
	['Ouryu'] = { "Riverne-Site_A01", "Lufaise_Meadows" },
	['Sea'] = { "Sealions_Den", "AlTaieu", "The_Garden_of_RuHmet", "Grand_Palace_of_HuXzoi", "Empyreal_Paradox" },
	['Limbus'] = { "Temenos", "Apollyon" },
	['Overlord Arthro'] = { "Jugner_Forest" },
	['Ruinous Rocs'] = { "Rolanberry_Fields" },
	['Sacred Scorpions'] = { "Sauromugue_Champaign" },
	['Xolotl'] = { "Attohwa_Chasm" },
	['Mammet-9999'] = { "Misareaux_Coast" },
	['Ultimega'] = { "Lufaise_Meadows" },
	['Tonberry Sovereign'] = { "Yhoator_Jungle" },
	
};

local function has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

local function value_index (tab, val)
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
	
end);

ashita.events.register('load', 'load_cb', function ()
    for line in io.lines(addon.path + "zones.csv") do
		local index, name = line:match("%i*(.-),%s*(.-),")
		table.insert(zoneList, index, name)
	end
	
	for line in io.lines(addon.path + "jobs.csv") do
		local index, name = line:match("%i*(.-),%s*(.-),")
		table.insert(jobList, index, name)
	end
	
end);

ashita.events.register('command', 'command_cb', function (e)
	local args = e.command:args();
	local usedArgc = 2;
	local modifier;
	local eventName;
	local startIndex = 0;
	
    if (#args == 0 or args[1] ~= '/att') then
        return;
    end
    
    if (#args >= 1) then
		
		local eventMode = has_value(args, 'e');
    
		local date = os.date('*t');
		local time = os.date("*t");
		local printTime = os.date(("%02d.%02d.%02d"):format(time.hour, time.min, time.sec));
		local filePath = addon.path + "\\Logs\\" + os.date("%A %d %B %Y") + " " + printTime + ".csv";
		local file = io.open(filePath, "a");

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
		local modSpecified = has_value(args, 'm');
		local regionMode = has_value(args, 'r');
		local eventMode = has_value(args, 'e');
		
		if (#args == 1) then
			print("Running in basic mode.");
			startIndex = 1;
			numResults = numResults + 2;
		end;
		
		if (lsMode) then
			print("Running in LS mode. LS mode supports over 40 players.");
			startIndex = 0;
		end;
		
		eventName = 'Current Zone';
		if (eventMode) then
			eventName = value_index(args, 'e');
			eventName = eventName + 1;
			eventName = shortNames[args[eventName]];
			print("Running in event mode.");
			
			   if eventName then
                -- Send a message to linkshell chat after a slight delay
                local message = "" .. " Attendance taken: " .. eventName .. "";
                AshitaCore:GetChatManager():QueueCommand(1, '/l ' ..message) coroutine.sleep(1.5);
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
				print("Error: Search results, and therefor attendance data, is truncated! Use the linkshell mode along with the linkshell menu instead (/att ls).");
			end;
		end;
			
		for i = startIndex, numResults, 1 do
			if (i == numResults) then break;
			end;
			
			isAnon[i] = ashita.memory.read_int8(0x04 + listPointerAddr + 0x0);					-- 7F: normal,	43: anon

			names[i] = ashita.memory.read_string(0x04 + listPointerAddr + 0x4, 15);				-- length 13, names get truncated!
			zones[i] = zoneList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x28)];		-- zoneID file included
			
			jobsMain[i] = jobList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x20)];
			jobsSub[i] = jobList[ashita.memory.read_uint8(0x04 + listPointerAddr + 0x21)];	
			
			jobsMainLvl[i] = ashita.memory.read_uint8(0x04 + listPointerAddr + 0x22);
			jobsSubLvl[i] = ashita.memory.read_uint8(0x04 + listPointerAddr + 0x23);	

			if (has_value(creditNames[eventName], zones[i])) then
				pCounter = pCounter + 1;
				file:write(names[i] + "," + jobsMain[i] + "," + os.date("%m/%d/%Y") + "," + os.date(("%02d:%02d:%02d"):format(time.hour, time.min, time.sec)) + "," + zones[i] + "," + eventName + "\n");
			end;
			
			listPointerAddr = listPointerAddr + 76;												--each entry is 76 bytes large
			
		end;        


        print(pCounter + " players accounted for.");
        print("Attendance Filename: " + os.date("%A %d %B %Y") + " " + os.date(("%02d:%02d:%02d"):format(time.hour, time.min, time.sec)) + ".csv");

        file:close();
        return;
    end;
end);