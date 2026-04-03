--[[
 AAExport.lua
 Converted from AAExport.mac with ImGui GUI
 v1.0 - 20260104
 v1.1 - 20260125 - add purchased argument
 v2.0 - 20260207 - converted to Lua
 v2.1 - 20260207 - added ImGui GUI for viewing and comparing exports
 v2.2 - 20262022 - add Char Select, add Edit Mode
 
 Usage: /lua run AAExport
--]]

local mq = require('mq')
local imgui = require('ImGui')
local PackageMan = require('mq/PackageMan')
local lfs = PackageMan.Require('luafilesystem', 'lfs')

-- GUI State
local openGUI = true
local shouldDrawGUI = true
local exportFiles = {}
local allExportFiles = {} -- Store all files before filtering
local characterNames = {} -- List of unique character names
local selectedCharacter = 1 -- Index in characterNames (1 = "All Characters")
local selectedTab = 1
local possibleTabs = { "General", "Archetype", "Class", "Special" }
local selectedFile1 = nil
local selectedFile2 = nil
local fileData1 = {}
local fileData2 = {}
local exportRunning = false
local pendingExport = nil
local scanRunning = false
local pendingScan = false
local importRunning = false
local pendingImport = false
local editMode = false -- Track if we're in edit mode
local fileData1Modified = false -- Track if fileData1 has been modified
local saveSuffix = "" -- Suffix for saving modified file
local changedFileContents = false



-- Export directory path
local exportDir = mq.luaDir .. '/AAExport/exports'

-- Function to parse character name from filename
-- Format: AA_CharacterName_ExportType_timestamp.ini
local function getCharacterFromFilename(filename)
    local parts = {}
    for part in string.gmatch(filename, "([^_]+)") do
        table.insert(parts, part)
    end
    
    if #parts >= 2 then
        return parts[2] -- Character name is the second part
    end
    return "Unknown"
end

-- Function to filter files by selected character
local function filterFilesByCharacter()
    exportFiles = {}
    
    if selectedCharacter == 1 then
        -- "All Characters" selected - show all files
        for _, filename in ipairs(allExportFiles) do
            table.insert(exportFiles, filename)
        end
    else
        -- Specific character selected - filter by that character
        local charName = characterNames[selectedCharacter]
        for _, filename in ipairs(allExportFiles) do
            if getCharacterFromFilename(filename) == charName then
                table.insert(exportFiles, filename)
            end
        end
    end
    
    -- Reset file selections if they're now out of range
    if selectedFile1 and selectedFile1 > #exportFiles then
        selectedFile1 = nil
        fileData1 = {}
    end
    if selectedFile2 and selectedFile2 > #exportFiles then
        selectedFile2 = nil
        fileData2 = {}
    end
end

-- Function to scan for export files
local function scanExportFiles()
    allExportFiles = {}
    characterNames = {"All Characters"} -- Start with "All" option
    local charSet = {}

	for filename in lfs.dir(exportDir) do
		if filename and filename ~= '' then
			table.insert(allExportFiles, filename)
			
			-- Extract character name
			local charName = getCharacterFromFilename(filename)
			if charName ~= "Unknown" and not charSet[charName] then
				charSet[charName] = true
				table.insert(characterNames, charName)
			end
		end
	end
	
    -- Sort character names alphabetically (skip first entry "All Characters")
    local sortedChars = {}
    for i = 2, #characterNames do
        table.insert(sortedChars, characterNames[i])
    end
    table.sort(sortedChars)
    
    -- Rebuild characterNames with "All Characters" first
    characterNames = {"All Characters"}
    for _, char in ipairs(sortedChars) do
        table.insert(characterNames, char)
    end
    
    table.sort(allExportFiles, function(a, b) return a > b end) -- Sort newest first
    
    -- Apply current filter
    filterFilesByCharacter()
end

-- Function to parse an export file
local function parseExportFile(filename)
    local data = {}
    local filepath = exportDir .. '\\' .. filename
    local file = io.open(filepath, 'r')
    
    if not file then
        return data
    end
    
    local inAASection = false
    for line in file:lines() do
        -- Check for [AA] section header
        if line:match("^%[AA%]") then
            inAASection = true
        elseif line:match("^%[.+%]") then
            -- Different section, stop reading
            inAASection = false
        elseif inAASection then
            -- Parse lines like: AA1=General|Spirit of Wolf|1|1|1|12345|Description
            local key, value = line:match("^AA(%d+)=(.+)$")
            if key and value then
                local parts = {}
                for part in string.gmatch(value, "([^|]+)") do
                    table.insert(parts, part)
                end
                
                if #parts >= 3 then
                    table.insert(data, {
                        tab = parts[1],
                        name = parts[2],
                        currentRank = tonumber(parts[3]) or 0,
                        maxRanks = tonumber(parts[4]) or 0,
                        cost = tonumber(parts[5]) or 0,
                        id = tonumber(parts[6]) or 0,
                        description = parts[7] or ''
                    })
                end
            end
        end
    end
    
    file:close()
    return data
end

-- Function to load a file's data
local function loadFileData(fileIndex, targetTable)
    if fileIndex and exportFiles[fileIndex] then
        local filename = exportFiles[fileIndex]
        local data = {}
		if not changedFileContents then
			data = parseExportFile(filename)
			
			for k in pairs(targetTable) do
				targetTable[k] = nil
			end
			for i, v in ipairs(data) do
				targetTable[i] = v
			end
		end
    end
end

-- Function to save modified file data
local function saveModifiedFile(suffix)
    if not selectedFile1 or not exportFiles[selectedFile1] then
        print('\arNo file selected to save')
        return false
    end
    
    -- Parse original filename to build new filename
    local originalFilename = exportFiles[selectedFile1]
    local parts = {}
    for part in string.gmatch(originalFilename, "([^_]+)") do
        table.insert(parts, part)
    end
    
    if #parts < 4 then
        print('\arInvalid filename format')
        return false
    end
    
    -- Build new filename: AA_CharacterName_ExportType_timestamp_suffix.ini
    local characterName = parts[2]
    local exportType = parts[3]
    local timestamp = parts[4]:gsub("%.ini$", "") -- Remove .ini extension
    
    local newFilename = string.format("AA_%s_%s_%s_%s.ini", characterName, exportType, timestamp, suffix)
    local filepath = exportDir .. '\\' .. newFilename
    
    -- Create the file
    local file = io.open(filepath, 'w')
    if not file then
        print('\arFailed to create file: ' .. newFilename)
        return false
    end
    
    -- Write [AA] section header
    file:write('[AA]\r\n')
    
    -- Write each AA entry
    for i, aa in ipairs(fileData1) do
        local iniKey = string.format('AA%d', 1000 + i - 1)
        local iniValue = string.format('%s|%s|%d|%d|%s|%d|%s',
            aa.tab,
            aa.name,
            aa.currentRank,
            aa.maxRanks,
            tostring(aa.cost),
            aa.id,
            aa.description or ''
        )
        file:write(string.format('%s=%s\r\n', iniKey, iniValue))
    end
    
    file:close()
    
    print(string.format('\atSuccessfully saved file: \ag%s', newFilename))
    fileData1Modified = false
    pendingScan = true -- Refresh file list
    return true
end


-- Function to perform AA export
local function performExport(exportTypeArg)
    exportRunning = true
    
    local counter = 1
    local tab = 1
    local aaCnt = 1000
    local aaCntExported = 0
    
    -- Generate filename with timestamp
    local dateStr = os.date('%Y%m%d')
    local timeStr = os.date('%H%M%S')
    local filename = string.format('AA_%s_%s_%s_%s.ini', mq.TLO.Me.Name(), exportTypeArg, dateStr, timeStr)
    local aaIniFile = exportDir .. '/' .. filename
    
    print(string.format('\atBeginning AA Export for level %d %s %s. Output file: \ag%s',
        mq.TLO.Me.Level(), mq.TLO.Me.Class(), mq.TLO.Me.Name(), aaIniFile))
    
    -- Handle export type filter settings
    if exportTypeArg == 'all' or exportTypeArg == 'descriptions' then
        if mq.TLO.Window('AAWindow').Child('CanPurchaseFilter').Checked() then
            mq.cmd('/nomodkey /notify AAWindow CanPurchaseFilter leftmouseup')
        end
    elseif exportTypeArg == 'canpurchase' then
        if not mq.TLO.Window('AAWindow').Child('CanPurchaseFilter').Checked() then
            mq.cmd('/nomodkey /notify AAWindow CanPurchaseFilter leftmouseup')
        end
    elseif exportTypeArg == 'purchased' then
        if mq.TLO.Window('AAWindow').Child('CanPurchaseFilter').Checked() then
            mq.cmd('/nomodkey /notify AAWindow CanPurchaseFilter leftmouseup')
        end
    end
    
    -- Main loop to iterate through all AA tabs and entries
    while true do
        local listName = 'List' .. tab
        local listItem = mq.TLO.Window('AAWindow').Child(listName).List(counter)
        
        if listItem.Length() and listItem.Length() > 0 then
            local aaName = mq.TLO.Window('AAWindow').Child(listName).List(counter, 1)()
            local aaRankStr = mq.TLO.Window('AAWindow').Child(listName).List(counter, 2)()
            local aaCost = mq.TLO.Window('AAWindow').Child(listName).List(counter, 3)() or 0
			
			if aaCost == '' then
				aaCost = 0
			end
            
            local aaCurrentRank = 0
            local aaMaxRanks = 0
            if aaRankStr then
                local ranks = {}
                for rank in string.gmatch(aaRankStr, "[^/]+") do
                    table.insert(ranks, tonumber(rank) or 0)
                end
                aaCurrentRank = ranks[1] or 0
                aaMaxRanks = ranks[2] or 0
            end
            
            local altActCode = mq.TLO.AltAbility(aaName).ID() or 0
            
            if exportTypeArg == 'purchased' and aaCurrentRank == 0 then
                counter = counter + 1
                goto continue
            end
            
            local aaTab = ''
            if tab == 1 then
                aaTab = 'General'
            elseif tab == 2 then
                aaTab = 'Archetype'
            elseif tab == 3 then
                aaTab = 'Class'
            elseif tab == 4 then
                aaTab = 'Special'
            end
		   
			mq.cmd('/nomodkey /notify AAWindow AAW_Subwindows tabselect ' .. tab)
                
			local listIndex = mq.TLO.Window('AAWindow').Child(listName).List('=' .. aaName)()
			if listIndex then
				mq.cmd('/nomodkey /notify AAWindow ' .. listName .. ' listselect ' .. listIndex)
			else
				counter = counter + 1
				goto continue
			end
			
            local exportStr = ''
            if exportTypeArg == 'descriptions' or exportTypeArg == 'canpurchase' then
                local aaDescription = mq.TLO.Window('AAWindow').Child('AAW_Description').Text() or ''
                exportStr = string.format('%s|%s|%d|%d|%d|%d|%s',
                    aaTab, aaName, aaCurrentRank, aaMaxRanks, aaCost, altActCode, aaDescription)
            else
                exportStr = string.format('%s|%s|%d|%d|%d|%d',
                    aaTab, aaName, aaCurrentRank, aaMaxRanks, aaCost, altActCode)
            end
			
            print(exportStr)
            mq.cmdf('/ini "%s" AA AA%d "%s"', aaIniFile, aaCnt, exportStr)
            
            aaCnt = aaCnt + 1
            counter = counter + 1
            
            ::continue::
        elseif tab < 4 then
            tab = tab + 1
            counter = 1
        else
            aaCntExported = aaCnt - 1000
            print(string.format('\atFinished export of %d AA to file: \ag%s', aaCntExported, filename))
            break
        end
    end
    
    exportRunning = false
    pendingScan = true -- Refresh file list
end

-- Helper function to select an AA
local function selectAA(aaTab, aaName)
    mq.cmd('/nomodkey /notify AAWindow AAW_Subwindows tabselect ' .. aaTab)
    
    local listName = 'List' .. aaTab
    local listIndex = mq.TLO.Window('AAWindow').Child(listName).List('=' .. aaName)()
    
    if listIndex and listIndex > 0 then
        mq.cmd('/nomodkey /notify AAWindow ' .. listName .. ' listselect ' .. listIndex)
        mq.cmd('/nomodkey /notify AAWindow ' .. listName .. ' leftmouse ' .. listIndex)
        mq.delay(1)
        return true
    else
        print(string.format('\ay%s\at not found, likely due to inconsistent rebirth AA names. Ignoring and continuing.', aaName))
        return false
    end
end

-- Helper function to purchase AA ranks
local function purchaseAA(numRanks)
    local purchasedRanks = 0
    
    while purchasedRanks < numRanks do
        mq.cmd('/nomodkey /notify AAWindow TrainButton leftmouseup')
        mq.delay('2s', function() return mq.TLO.Window('AAWindow').Child('TrainButton').Enabled() end)
        
        -- If fast AA purchase is not on, accept the purchase
        if not mq.TLO.Window('OptionsWindow').Child('OptionsGeneralPage').Child('OGP_AANoConfirmCheckbox').Checked() then
            -- Wait for confirmation dialog
            mq.delay('10s', function() return mq.TLO.Window('ConfirmationDialogBox').Open() end)
            
            if mq.TLO.Window('ConfirmationDialogBox').Open() then
                mq.delay('2s')
                mq.cmd('/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup')
                mq.delay('2s')
            end
        end
        
        purchasedRanks = purchasedRanks + 1
    end
end

-- Function to perform AA import from selected file
local function performImport()
    if not selectedFile1 or not exportFiles[selectedFile1] then
        print('\arNo file selected for import')
        return
    end
    
    local filename = exportFiles[selectedFile1]
    local filepath = exportDir .. '\\' .. filename
    
    print(string.format('\awAAImport initialized using import file %s', filename))
    
    -- Turn off Can Purchase filter if it's on
    if mq.TLO.Window('AAWindow').Child('CanPurchaseFilter').Checked() then
        mq.cmd('/nomodkey /notify AAWindow CanPurchaseFilter leftmouseup')
    end
    mq.delay(10)
    
    local failures = 0
    local retryLoop = true
	local numRetries = 0
    
    while retryLoop do
        failures = 0
        
        -- Read the INI file
        for counter = 1000, 2000 do
            local iniKey = string.format('AA%d', counter)
            local iniRow = mq.TLO.Ini(filepath, 'AA', iniKey)()
            
            if iniRow and iniRow ~= '' then
                -- Parse the row: AATab|AAName|CurrentRank|MaxRank|Cost|ID
                local parts = {}
                for part in string.gmatch(iniRow, "([^|]+)") do
                    table.insert(parts, part)
                end
                
                if #parts >= 3 then
                    local aaTab = parts[1]
                    local aaName = parts[2]
                    local aaRanksToBuy = tonumber(parts[3]) or 0
                    
                    -- Determine tab number
                    local tab = 1
                    if aaTab == 'General' then
                        tab = 1
                    elseif aaTab == 'Archetype' then
                        tab = 2
                    elseif aaTab == 'Class' then
                        tab = 3
                    elseif aaTab == 'Special' then
                        tab = 4
                    end
                    
                    -- Get current rank from AA window
                    local listName = 'List' .. tab
                    local currentRankStr = mq.TLO.Window('AAWindow').Child(listName).List(
                        mq.TLO.Window('AAWindow').Child(listName).List('=' .. aaName)(), 2
                    )()
                    
                    local currentRank = 0
                    if currentRankStr then
                        local ranks = {}
                        for rank in string.gmatch(currentRankStr, "[^/]+") do
                            table.insert(ranks, tonumber(rank) or 0)
                        end
                        currentRank = ranks[1] or 0
                    end
                    
                    local actualRanksToBuy = aaRanksToBuy - currentRank
                    
                    if actualRanksToBuy > 0 then
                        print(string.format('\atAttempting to purchase %d ranks of \ay%s\at to reach rank %d on tab %s',
                            actualRanksToBuy, aaName, aaRanksToBuy, aaTab))
                        
                        -- Select the AA
                        local success = selectAA(tab, aaName)
                        
                        if success then
                            mq.delay(1)
                            
                            -- Check if Train button is enabled
                            if mq.TLO.Window('AAWindow').Child('TrainButton').Enabled() then
                                purchaseAA(actualRanksToBuy)
                                
                                -- Verify purchase
                                currentRankStr = mq.TLO.Window('AAWindow').Child(listName).List(
                                    mq.TLO.Window('AAWindow').Child(listName).List('=' .. aaName)(), 2
                                )()
                                
                                if currentRankStr then
                                    local ranks = {}
                                    for rank in string.gmatch(currentRankStr, "[^/]+") do
                                        table.insert(ranks, tonumber(rank) or 0)
                                    end
                                    currentRank = ranks[1] or 0
                                end
                                
                                if currentRank == aaRanksToBuy then
                                    print(string.format('\ag...Successfully\at purchased %d ranks of \ay%s', currentRank, aaName))
                                else
                                    print(string.format('\ar...Failure\at in AA \ay%s\at, current rank %d. Added to retry list.', 
                                        aaName, currentRank))
                                    failures = failures + 1
                                end
                            else
                                print(string.format('\ao...Prereqs required, \ay%s \atadded to retry list, current rank %d.', 
                                    aaName, currentRank))
                                failures = failures + 1
                            end
                        end
                    end
                end
            end
        end
        
        -- Check if we need to retry. Limit number of retries to 20 to prevent endless loops
        if failures > 0 and numRetries < 20 then
			numRetries = numRetries + 1
            print('\aw------------------------------------------')
            print(string.format('\awRetrying \ao%d\aw failures...', failures))
            print('\aw------------------------------------------')
        else
            retryLoop = false
        end
    end
    
    print('\agImport complete!')
end

local function HSV(h, s, v)
    local r, g, b
    r, g, b = ImGui.ColorConvertHSVtoRGB(h, s, v)
    return ImVec4(r, g, b, 1.0)
end

local function removeTableRow(targetTable, rowIndex)
	print(string.format('\arRemoving AA: %s', rowIndex, targetTable[rowIndex].name))
	table.remove(targetTable, rowIndex)
end

local function addTableRow(targetTable)
	print('\agAdding new row')
	table.insert(targetTable, {
		tab = 'Special',
		name = 'New AA',
		currentRank = 0,
		maxRanks = 100,
		cost = 0,
		id = 0,
		description = ''
	})
end

local function indexOf(array, value)
    for i, v in ipairs(array) do
        if v == value then
            return i
        end
    end
    return nil
end

-- ImGui render function
local function renderGUI()
	imgui.SetNextWindowSize(ImVec2(900, 800), ImGuiCond.Appearing)
    openGUI, shouldDrawGUI = imgui.Begin('AA Import/Export Tool', openGUI, ImGuiWindowFlags.None)
    
	if not shouldDrawGUI then
        imgui.End()
        return
    end
	
	local exportLabels = {
		[0] = "Export Purchased",
		[1] = "Export All",
		[2] = "Export Can Purchase",
		[3] = "Export Descriptions"
	}
	
	local exportStrings = {
		[0] = "purchased",
		[1] = "all",
		[2] = "canpurchase",
		[3] = "descriptions"
	}
	
	-- Export controls
	imgui.SeparatorText('Export Controls:')
	local buttonColor = 0
	if exportRunning then
		imgui.Text('Export in progress...')
	else
	    for i = 0, 3 do
			if i > 0 then imgui.SameLine() end
			if i > 0 then buttonColor = 4 else buttonColor = 3 end
			imgui.PushID(i)
			imgui.PushStyleColor(ImGuiCol.Button, HSV(buttonColor / 7.0, 0.6, 0.6))
			imgui.PushStyleColor(ImGuiCol.ButtonHovered, HSV(buttonColor / 7.0, 0.7, 0.7))
			imgui.PushStyleColor(ImGuiCol.ButtonActive, HSV(buttonColor /  7.0, 0.8, 0.8))
			if imgui.Button(exportLabels[i], 170, 0) then 
				pendingExport = exportStrings[i]
			end
			imgui.PopStyleColor(3)
			imgui.PopID()
		end
		
		imgui.SameLine()
		if imgui.Button('Refresh File List', 170, 0) then
			pendingScan = true
		end
	end
	
	imgui.Spacing()
		
	-- File selection
	imgui.SeparatorText('Select Files to View/Compare:')
	
	-- Character filter dropdown
	imgui.Text('Filter by Character:')
	imgui.SetNextItemWidth(250)
	if imgui.BeginCombo('##CharacterFilter', characterNames[selectedCharacter] or "All Characters") then
		for i, charName in ipairs(characterNames) do
			local isSelected = (selectedCharacter == i)
			local isChanged = false
			isSelected, isChanged = imgui.Selectable(charName, isSelected)
			if isChanged then
				selectedCharacter = i
				filterFilesByCharacter()
			end
			if isSelected then
				imgui.SetItemDefaultFocus()
			end
		end
		imgui.EndCombo()
	end
	
	imgui.Spacing()
	imgui.Separator()
	imgui.Spacing()
	
	imgui.Columns(2, 'FileColumns', true)
	
	-- File 1 selection
	imgui.Text('File 1:')
	if imgui.BeginListBox('##file1', ImVec2(mq.NumericLimits_Float(), 8 * imgui.GetTextLineHeightWithSpacing())) then
		for i, filename in ipairs(exportFiles) do
			local isSelected = (selectedFile1 == i)
			if imgui.Selectable(filename, isSelected) then
				selectedFile1 = i
				if not fileData1Modified then
					loadFileData(selectedFile1, fileData1)
				end
			end
		end
		imgui.EndListBox()
	end
	
	ImGui.NextColumn()
	
	-- File 2 selection
	imgui.Text('File 2 (for comparison):')
	if imgui.BeginListBox('##file2', ImVec2(mq.NumericLimits_Float(), 8 * imgui.GetTextLineHeightWithSpacing())) then
		for i, filename in ipairs(exportFiles) do
			local isSelected = (selectedFile2 == i)
			if imgui.Selectable(filename, isSelected) then
				selectedFile2 = i
				loadFileData(selectedFile2, fileData2)
			end
		end
		imgui.EndListBox()
	end
	
	imgui.Columns(1)
	imgui.Spacing()
	imgui.SeparatorText('Import AA from File 1:')
	imgui.Spacing()
	
	buttonColor = 2
	imgui.PushID(i)
	imgui.PushStyleColor(ImGuiCol.Button, HSV(buttonColor / 7.0, 0.6, 0.6))
	imgui.PushStyleColor(ImGuiCol.ButtonHovered, HSV(buttonColor / 7.0, 0.7, 0.7))
	imgui.PushStyleColor(ImGuiCol.ButtonActive, HSV(buttonColor /  7.0, 0.8, 0.8))
	if imgui.Button("Import Selected", 170, 0) then 
		pendingImport = true
	end
	imgui.PopStyleColor(3)
	imgui.PopID()
	
	imgui.Spacing()
	imgui.Separator()
	imgui.Spacing()
	
	-- Display file contents or comparison with tabbed view
	if selectedFile1 and #fileData1 > 0 and not scanRunning then
		if imgui.BeginTabBar('ViewTabs', ImGuiTabBarFlags.None) then
			-- File 1 Tab
			if imgui.BeginTabItem('File 1: ' .. exportFiles[selectedFile1]) then
				imgui.Text(string.format('Viewing: %s', exportFiles[selectedFile1]))
				imgui.Text(string.format('Total AAs: %d', #fileData1))
				
				-- Edit mode toggle and save controls
				imgui.Spacing()
				editMode = imgui.Checkbox('Edit Mode', editMode)
				
				if editMode then
					imgui.SameLine(0.0, 80)
					if imgui.Button('Add New Row', 150, 0) then
						addTableRow(fileData1)
						fileData1Modified = true
					end
					
					imgui.SameLine(0.0, 80)
					imgui.Text("Enter new file suffix:")
					imgui.SameLine()
					imgui.SetNextItemWidth(150)
					saveSuffix = imgui.InputText('##SaveSuffix', saveSuffix, 64)
					
					imgui.SameLine()
					if imgui.Button('Save As', 80, 0) then
						if not fileData1Modified then
							print('\arNo changes to save detected')
						else
							if saveSuffix and saveSuffix ~= '' then
								saveModifiedFile(saveSuffix)
							else
								print('\arPlease enter a suffix for the new file')
							end
						end
					end
					
					if fileData1Modified then
						imgui.SameLine()
						imgui.TextColored(1.0, 1.0, 0.0, 1.0, '(Modified)')
					end
				end
				
				imgui.Spacing()
				
				-- Table with 6 columns (added Actions column for edit mode)
				local numColumns = editMode and 6 or 5
					if imgui.BeginTable(editMode and "AATable1_Edit" or "AATable1_View", numColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Sortable) then
					imgui.TableSetupScrollFreeze(0, 1)
					imgui.TableSetupColumn('Tab', ImGuiTableColumnFlags.WidthFixed, 80)
					imgui.TableSetupColumn('AA Name', ImGuiTableColumnFlags.WidthStretch)
					imgui.TableSetupColumn('Rank', ImGuiTableColumnFlags.WidthFixed, editMode and 100 or 60)
					imgui.TableSetupColumn('Cost', ImGuiTableColumnFlags.WidthFixed, 60)
					imgui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 60)
					if editMode then
						imgui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, 70)
					end
					imgui.TableHeadersRow()
					
					local rowsToDelete = {}
					for i = 1, #fileData1 do
						local aa = fileData1[i]
						imgui.TableNextRow()
						imgui.TableNextColumn()
						imgui.SetNextItemWidth(80)
						if editMode then
							selectedTab = indexOf(possibleTabs, aa.tab)
							imgui.PushID("TabSelection" .. i)
							if imgui.BeginCombo('##TabSelection', possibleTabs[selectedTab]) then
								for n, tabName in ipairs(possibleTabs) do
									local isSelected = (selectedTab == n)
									local isChanged = false
									isSelected, isChanged = imgui.Selectable(tabName, isSelected)
									if isChanged then
										fileData1[i].tab = possibleTabs[n]
										fileData1Modified = true
									end
									if isSelected then
										imgui.SetItemDefaultFocus()
									end
								end
								imgui.EndCombo()
							end
							imgui.PopID()
						else
							imgui.Text(aa.tab)
						end
						imgui.TableNextColumn()
						
						if editMode then
							imgui.PushID("Name" .. i)
							local newName, changed = imgui.InputText('##aaname', aa.name)
							if changed then
								fileData1[i].name = newName
								fileData1Modified = true
								changed = false
							end
							imgui.PopID()
						else
							imgui.Text(aa.name)
						end
						imgui.TableNextColumn()
						
						-- Editable rank column (only first number)
						if editMode then
							imgui.SetNextItemWidth(50)
							imgui.PushID("Rank" .. i)
							local newRank, changed = imgui.InputInt('##rank', aa.currentRank, 0, 0)
							if changed then
								fileData1[i].currentRank = math.max(0, math.min(newRank, aa.maxRanks))
								fileData1Modified = true
								changed = false
							end
							imgui.PopID()
							imgui.SameLine(0, 2)
							imgui.Text(string.format('/%d', aa.maxRanks))
						else
							imgui.Text(string.format('%d/%d', aa.currentRank, aa.maxRanks))
						end
						
						imgui.TableNextColumn()
						imgui.Text(tostring(aa.cost))
						imgui.TableNextColumn()
						imgui.Text(tostring(aa.id))
						
						-- Delete button in edit mode
						if editMode then
							imgui.TableNextColumn()
							imgui.PushID("Del" .. i)
							imgui.PushStyleColor(ImGuiCol.Button, HSV(0 / 7.0, 0.6, 0.6))
							imgui.PushStyleColor(ImGuiCol.ButtonHovered, HSV(0 / 7.0, 0.7, 0.7))
							imgui.PushStyleColor(ImGuiCol.ButtonActive, HSV(0 /  7.0, 0.8, 0.8))
							if imgui.Button('X', 30, 0) then
								table.insert(rowsToDelete, i)
								fileData1Modified = true
							end
							imgui.PopStyleColor(3)
							imgui.PopID()
						end
					end
					
					-- Delete rows (in reverse order to maintain indices)
					if #rowsToDelete > 0 then
						changedFileContents = true
						for idx = #rowsToDelete, 1, -1 do
							local rowIndex = rowsToDelete[idx]
							removeTableRow(fileData1, rowIndex)
						end
						print(string.format('\arNew total rows: %d', #fileData1))
					end
					
					imgui.EndTable()
				end
				imgui.EndTabItem()
			end
			
			
			
			-- File 2 Tab (only if file 2 is selected)
			if selectedFile2 and #fileData2 > 0 then
				if imgui.BeginTabItem('File 2: ' .. exportFiles[selectedFile2]) then
					imgui.Text(string.format('Viewing: %s', exportFiles[selectedFile2]))
					imgui.Text(string.format('Total AAs: %d', #fileData2))
					imgui.Spacing()
					
					if imgui.BeginTable('AATable2', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Sortable) then
						imgui.TableSetupScrollFreeze(0, 1)
						imgui.TableSetupColumn('Tab', ImGuiTableColumnFlags.WidthFixed, 80)
						imgui.TableSetupColumn('AA Name', ImGuiTableColumnFlags.WidthStretch)
						imgui.TableSetupColumn('Rank', ImGuiTableColumnFlags.WidthFixed, 60)
						imgui.TableSetupColumn('Cost', ImGuiTableColumnFlags.WidthFixed, 60)
						imgui.TableSetupColumn('ID', ImGuiTableColumnFlags.WidthFixed, 60)
						imgui.TableHeadersRow()
						
						for _, aa in ipairs(fileData2) do
							imgui.TableNextRow()
							imgui.TableNextColumn()
							imgui.Text(aa.tab)
							imgui.TableNextColumn()
							imgui.Text(aa.name)
							imgui.TableNextColumn()
							imgui.Text(string.format('%d/%d', aa.currentRank, aa.maxRanks))
							imgui.TableNextColumn()
							imgui.Text(tostring(aa.cost))
							imgui.TableNextColumn()
							imgui.Text(tostring(aa.id))
						end
						
						imgui.EndTable()
					end
					imgui.EndTabItem()
				end
			end
			
			-- Comparison Tab (only if both files selected)
			if selectedFile2 and #fileData2 > 0 then
				if imgui.BeginTabItem('Comparison') then
					imgui.Text('Comparison View:')
					imgui.Text(string.format('File 1 (%s): %d AAs', exportFiles[selectedFile1], #fileData1))
					imgui.Text(string.format('File 2 (%s): %d AAs', exportFiles[selectedFile2], #fileData2))
					imgui.Spacing()
					
					-- Create lookup tables for comparison
					local file1Lookup = {}
					local file2Lookup = {}
					for _, aa in ipairs(fileData1) do
						file1Lookup[aa.name] = aa
					end
					for _, aa in ipairs(fileData2) do
						file2Lookup[aa.name] = aa
					end
					
					-- Display comparison table
					if imgui.BeginTable('ComparisonTable', 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY) then
						imgui.TableSetupScrollFreeze(0, 1)
						imgui.TableSetupColumn('AA Name', ImGuiTableColumnFlags.WidthStretch)
						imgui.TableSetupColumn('File 1 Rank', ImGuiTableColumnFlags.WidthFixed, 80)
						imgui.TableSetupColumn('File 2 Rank', ImGuiTableColumnFlags.WidthFixed, 80)
						imgui.TableSetupColumn('Difference', ImGuiTableColumnFlags.WidthFixed, 80)
						imgui.TableSetupColumn('Tab', ImGuiTableColumnFlags.WidthFixed, 80)
						imgui.TableHeadersRow()
						
						-- Combine all AA names from both files
						local allAANames = {}
						for name, _ in pairs(file1Lookup) do
							allAANames[name] = true
						end
						for name, _ in pairs(file2Lookup) do
							allAANames[name] = true
						end
						
						-- Convert to sorted array
						local sortedNames = {}
						for name, _ in pairs(allAANames) do
							table.insert(sortedNames, name)
						end
						table.sort(sortedNames)
						
						-- Show ALL rows
						for _, aaName in ipairs(sortedNames) do
							local aa1 = file1Lookup[aaName]
							local aa2 = file2Lookup[aaName]
							
							local rank1 = aa1 and aa1.currentRank or 0
							local rank2 = aa2 and aa2.currentRank or 0
							local maxRank1 = aa1 and aa1.maxRanks or 0
							local maxRank2 = aa2 and aa2.maxRanks or 0
							local tab = (aa1 and aa1.tab) or (aa2 and aa2.tab) or 'Unknown'
							local diff = rank1 - rank2
							
							imgui.TableNextRow()
							imgui.TableNextColumn()
							
							-- Color code: green for file1 only, red for file2 only, white for both
							local needsPopColor = false
							if not aa2 then
								-- Exists in file1 but not file2 - GREEN
								imgui.PushStyleColor(ImGuiCol.Text, 0.0, 1.0, 0.0, 1.0)
								needsPopColor = true
							elseif not aa1 then
								-- Exists in file2 but not file1 - RED
								imgui.PushStyleColor(ImGuiCol.Text, 1.0, 0.0, 0.0, 1.0)
								needsPopColor = true
							elseif diff < 0 then
								-- Decreased rank - RED
								imgui.PushStyleColor(ImGuiCol.Text, 1.0, 0.0, 0.0, 1.0)
								needsPopColor = true
							elseif diff > 0 then
								-- Increased rank - GREEN
								imgui.PushStyleColor(ImGuiCol.Text, 0.0, 1.0, 0.0, 1.0)
								needsPopColor = true
							end
							-- else WHITE (default) for exists in both
							
							imgui.Text(aaName)
							imgui.TableNextColumn()
							imgui.Text(aa1 and string.format('%d/%d', rank1, maxRank1) or 'N/A')
							imgui.TableNextColumn()
							imgui.Text(aa2 and string.format('%d/%d', rank2, maxRank2) or 'N/A')
							imgui.TableNextColumn()
							
							if diff > 0 then
								imgui.Text(string.format('+%d', diff))
							elseif diff < 0 then
								imgui.Text(string.format('%d', diff))
							elseif not aa1 then
								imgui.Text('NEW')
							elseif not aa2 then
								imgui.Text('REMOVED')
							else
								imgui.Text('=')
							end
							
							imgui.TableNextColumn()
							imgui.Text(tab)
							
							if needsPopColor then
								imgui.PopStyleColor()
							end
						end
						
						imgui.EndTable()
					end
					imgui.EndTabItem()
				end
			end
			
			imgui.EndTabBar()
		end
	else
		imgui.Text('Select a file to view its contents')
	end
	
	imgui.End()
end

-- GUI mode
print('Starting AA Export GUI...')
if not lfs.attributes(exportDir) then
	lfs.mkdir(exportDir)
end
scanExportFiles()

mq.imgui.init('AAExportViewer', renderGUI)

-- Main loop for GUI
while openGUI do
	-- Process pending export
	if pendingExport and not exportRunning then
		exportRunning = true
		local exportType = pendingExport
		pendingExport = nil
		performExport(exportType)
		exportRunning = false
		mq.delay(10)
		pendingScan = true -- Refresh file list after export
	end
	
	if pendingImport and not importRunning then
		importRunning = true
		pendingImport = false
		performImport()
		importRunning = false
		mq.delay(10)
	end
	
	if pendingScan and not scanRunning then
		scanRunning = true
		scanExportFiles()
		pendingScan = false
		scanRunning = false
		mq.delay(10)
	end
	
	mq.delay(10)
end

mq.imgui.destroy('AAExportViewer')
print('AA Export GUI closed.')