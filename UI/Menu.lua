LoadoutLocker = LoadoutLocker or {}
local Menu = {}
LoadoutLocker.Menu = Menu
local Shell = LoadoutLocker.MenuShell
local Widgets = LoadoutLocker.MenuWidgets
local C = LoadoutLocker.Constants
local DB = LoadoutLocker.DB
local Loadout = LoadoutLocker.Loadout
local Gear = LoadoutLocker.Gear
local Dungeons = LoadoutLocker.Dungeons
local Raids = LoadoutLocker.Raids
local Delves = LoadoutLocker.Delves
local PvP = LoadoutLocker.PvP
local subTabBuildToken = { dungeons = 0, delves = 0 }
local subTabButtons = { dungeons = {}, delves = {} }
local selectedSubTabSectionKey = { dungeons = nil, delves = nil }
local HELP_TEXT = "Equip gear, select a talent loadout, then save with the talent panel button or |cffffffff/locker save|r. Changing loadouts automatically equips the saved gear set.\n\n"
    .. "|cffffffffCommands|r\n"
    .. "/locker - open this menu\n"
    .. "/locker save - save equipped gear to the active loadout\n"
    .. "/locker list - list saved gear sets\n"
    .. "/locker scan - check bags for upgrades\n"
    .. "/locker delete - remove saved gear for the active loadout\n\n"
    .. "Also available under |cffffffffEsc > Options > AddOns|r."
local TAB_INTRO = {
    general = "LoadoutLocker saves your equipped gear to each talent loadout and swaps it when you change builds.",
    priority = "When upgrade prompts appear, higher stats at the top break ties between same item level and track.",
    loadouts = "Manage saved gear sets for your current specialization, including ignored upgrade slots and copying between loadouts.",
    dungeons = "Set a default talent loadout and optional per-dungeon overrides. Use the category buttons above to browse season and expansion dungeons.",
    raids = "Set a default raid loadout and optional per-boss overrides. In-game prompts respect your lockout progress.",
    delves = "Set a default delve loadout and optional per-delve overrides. Use the Midnight or TWW buttons above to browse delves.",
    pvp = "Set a default PvP loadout and optional overrides for arenas and battlegrounds.",
}
local selectedManageConfigID
local selectedCopySourceConfigID
local selectedCopyTargetConfigID
local RefreshUI = LoadoutLocker.RefreshUI
local function RequestTabRefresh(tabID)
    if Shell.activeTab == tabID then
        Shell:RefreshTab(tabID)
    else
        Shell:SelectTab(tabID)
    end
end
local function FindListEntry(list, configID)
    for _, entry in ipairs(list) do
        if entry.configID == configID then
            return entry
        end
    end
end
local function SelectFirstExcluding(list, excludeID)
    for _, entry in ipairs(list) do
        if entry.configID ~= excludeID then
            return entry.configID
        end
    end
end
local function GetOverrideDropdownState(overrideList, override)
    return override and tostring(override) or "default", overrideList
end
local function BuildConfigDropdownList(entries, options)
    options = options or {}
    local list = {}
    if options.includeNone then
        list[""] = "None"
    end
    if options.includeUseDefault then
        list.default = "Use default"
    end
    if options.emptyLabel then
        list[""] = options.emptyLabel
        return list
    end
    for _, entry in ipairs(entries) do
        local name = entry.name
        if options.markSaved and entry.hasSavedGear then
            name = name .. " (saved)"
        end
        list[tostring(entry.configID)] = name
    end
    return list
end
local function BuildLoadoutDropdownList(specID, includeNone, includeUseDefault, configList)
    return BuildConfigDropdownList(
        configList or (specID and Loadout.GetConfigList(specID) or {}),
        { includeNone = includeNone, includeUseDefault = includeUseDefault }
    )
end
local function AddDefaultLoadoutDropdown(builder, specID, configList, getDefault, setDefault)
    if specID then
        return Widgets.AddDropdown(
            builder,
            220,
            BuildLoadoutDropdownList(specID, true, false, configList),
            tostring(getDefault(specID) or ""),
            function(value)
                setDefault(specID, value ~= "" and tonumber(value) or nil)
            end
        )
    end
    Widgets.AddEmptyDropdown(builder, 220, "No specialization", true)
    return builder
end
local function ResolveManageConfigID(savedSets)
    if #savedSets == 0 then
        return nil
    end
    if not selectedManageConfigID or not FindListEntry(savedSets, selectedManageConfigID) then
        selectedManageConfigID = savedSets[1].configID
    end
    return selectedManageConfigID
end
local function ResolveCopyConfigIDs(specID, savedSets)
    local loadouts = Loadout.GetConfigList(specID)
    if #savedSets == 0 then
        selectedCopySourceConfigID = nil
    elseif not selectedCopySourceConfigID or not FindListEntry(savedSets, selectedCopySourceConfigID) then
        selectedCopySourceConfigID = savedSets[1].configID
    end
    if #loadouts == 0 then
        selectedCopyTargetConfigID = nil
    elseif not selectedCopyTargetConfigID
        or not FindListEntry(loadouts, selectedCopyTargetConfigID)
        or selectedCopyTargetConfigID == selectedCopySourceConfigID
    then
        selectedCopyTargetConfigID = SelectFirstExcluding(loadouts, selectedCopySourceConfigID)
    end
    return loadouts
end
local function BuildGeneralTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.general)
    Widgets.AddHeading(builder, "Prompts")
    Widgets.AddCheckbox(builder, "Offer upgrade prompts when swapping loadouts", DB:AreUpgradeChecksEnabled(), function(value)
        DB:SetUpgradeChecksEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering dungeons", DB:AreDungeonPromptsEnabled(), function(value)
        DB:SetDungeonPromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering raids or after boss kills", DB:AreRaidPromptsEnabled(), function(value)
        DB:SetRaidPromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering delves", DB:AreDelvePromptsEnabled(), function(value)
        DB:SetDelvePromptsEnabled(value)
    end)
    Widgets.AddCheckbox(builder, "Prompt to switch loadouts when entering PvP", DB:ArePvPPromptsEnabled(), function(value)
        DB:SetPvPPromptsEnabled(value)
    end)
    Widgets.AddGap(builder, 12)
    Widgets.AddHeading(builder, "Commands")
    Widgets.AddLabel(builder, HELP_TEXT)
    Widgets.FinishBuilder(builder)
end
local function RefreshPriorityRows(content)
    local priority = DB:GetTertiaryPriority()
    for index, field in ipairs(priority) do
        local row = content.priorityRows[index]
        if row then
            row:Refresh(index, C.GetTertiarySettingLabel(field), index <= 1, index >= #priority)
        end
    end
end
local function BuildPriorityTab(content)
    if content.priorityRows then
        RefreshPriorityRows(content)
        return
    end
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    Widgets.AddTabIntro(builder, TAB_INTRO.priority)
    Widgets.AddHeading(builder, "Tertiary stat priority")
    content.priorityRows = {}
    local priority = DB:GetTertiaryPriority()
    for index, field in ipairs(priority) do
        local _, row = Widgets.AddPriorityRow(
            builder,
            index,
            C.GetTertiarySettingLabel(field),
            function()
                local currentField = DB:GetTertiaryPriority()[index]
                if currentField and DB:MoveTertiaryPriority(currentField, "up") then
                    RequestTabRefresh("priority")
                end
            end,
            function()
                local currentField = DB:GetTertiaryPriority()[index]
                if currentField and DB:MoveTertiaryPriority(currentField, "down") then
                    RequestTabRefresh("priority")
                end
            end,
            index <= 1,
            index >= #priority
        )
        content.priorityRows[index] = row
    end
    Widgets.AddButton(builder, "Reset Priority", 140, function()
        DB:ResetTertiaryPriority()
        content.priorityRows = nil
        RequestTabRefresh("priority")
    end)
    Widgets.FinishBuilder(builder)
end
local function BuildLoadoutOverviewRows(loadouts, specID, activeConfigID)
    local rows = {}
    for _, entry in ipairs(loadouts) do
        local dbEntry = DB:GetEntry(specID, entry.configID)
        rows[#rows + 1] = {
            name = entry.name,
            equipmentSetName = dbEntry and dbEntry.equipmentSetName or "",
            hasSavedGear = entry.hasSavedGear,
            isActive = entry.configID == activeConfigID,
        }
    end
    return rows
end
local function BuildLoadoutsTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    local specID = Loadout.GetSpecID()
    if not specID then
        Widgets.AddTabIntro(builder, TAB_INTRO.loadouts)
        Widgets.AddLabel(builder, "No specialization available.")
        Widgets.FinishBuilder(builder)
        return
    end
    local loadouts = Loadout.GetConfigList(specID)
    local activeConfigID = Loadout.GetLoadoutConfigID(specID)
    Widgets.AddTabIntro(builder, TAB_INTRO.loadouts)
    Widgets.AddHeading(builder, "Overview")
    Widgets.AddLoadoutOverviewTable(builder, BuildLoadoutOverviewRows(loadouts, specID, activeConfigID))
    Widgets.AddGap(builder, 16)
    local savedSets = DB:GetSavedGearSetList(specID)
    local manageConfigID = ResolveManageConfigID(savedSets)
    loadouts = ResolveCopyConfigIDs(specID, savedSets)
    Widgets.AddHeading(builder, "Manage saved gear set")
    if #savedSets == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No saved gear sets")
    else
        Widgets.AddDropdownButtonRow(
            builder,
            220,
            BuildConfigDropdownList(savedSets),
            tostring(manageConfigID),
            function(value)
                selectedManageConfigID = tonumber(value)
                RequestTabRefresh("loadouts")
            end,
            "Delete Gear Set",
            120,
            function()
                if manageConfigID and Gear.DeleteSavedGear(manageConfigID) then
                    RequestTabRefresh("loadouts")
                end
            end,
            not manageConfigID
        )
    end
    Widgets.AddLabel(builder, "Ignored upgrade slots")
    local slots = manageConfigID and DB:GetIgnoredUpgradeSlotList(specID, manageConfigID) or {}
    local ignoredPanelWidth = math.floor((builder.parent:GetWidth() - 8) / 2)
    Widgets.AddInsetPanel(builder, function(panel)
        if #slots == 0 then
            Widgets.AddLabel(panel, "No ignored upgrade prompts for this loadout.")
        else
            for _, slot in ipairs(slots) do
                Widgets.AddSlotClearRow(panel, C.GetSlotLabel(slot), function()
                    if manageConfigID then
                        DB:ClearIgnoredUpgradeSlot(specID, manageConfigID, slot)
                        RequestTabRefresh("loadouts")
                    end
                end)
            end
        end
    end, 40, ignoredPanelWidth)
    Widgets.AddGap(builder, 8)
    Widgets.AddButton(builder, "Clear All Ignored", 150, function()
        if manageConfigID and DB:ClearAllIgnoredUpgradeSlots(specID, manageConfigID) then
            RequestTabRefresh("loadouts")
        end
    end, #slots == 0)
    Widgets.AddGap(builder, 24)
    Widgets.AddHeading(builder, "Copy gear set")
    local canCopy = selectedCopySourceConfigID
        and selectedCopyTargetConfigID
        and selectedCopySourceConfigID ~= selectedCopyTargetConfigID
    if #savedSets == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No saved gear sets")
    else
        Widgets.AddDropdownButtonRow(
            builder,
            220,
            BuildConfigDropdownList(savedSets),
            tostring(selectedCopySourceConfigID),
            function(value)
                selectedCopySourceConfigID = tonumber(value)
                RequestTabRefresh("loadouts")
            end,
            "Copy Gear Set",
            120,
            function()
                if Gear.CopyGearSetToLoadout(selectedCopySourceConfigID, selectedCopyTargetConfigID) then
                    RefreshUI()
                    RequestTabRefresh("loadouts")
                end
            end,
            not canCopy
        )
    end
    Widgets.AddLabel(builder, "To")
    if #loadouts == 0 then
        Widgets.AddEmptyDropdown(builder, 220, "No loadouts found")
    else
        Widgets.AddDropdown(builder, 220, BuildConfigDropdownList(loadouts, { markSaved = true }), tostring(selectedCopyTargetConfigID), function(value)
            selectedCopyTargetConfigID = tonumber(value)
            RequestTabRefresh("loadouts")
        end)
    end
    Widgets.FinishBuilder(builder)
end
local function IsAssignmentSectionBuildValid(token, tabID)
    return Shell.activeTab == tabID and token == subTabBuildToken[tabID]
end
local function BuildAssignmentSection(scrollChild, specID, items, overrideList, token, tabID, assignmentKey, getAssignments, clearConfigID, setConfigID, onChanged)
    if not IsAssignmentSectionBuildValid(token, tabID) then
        return
    end
    local builder = Widgets.NewBuilder(scrollChild)
    local assignments = specID and getAssignments(specID) or nil
    local overrides = assignments and assignments[assignmentKey]
    for _, item in ipairs(items) do
        if not IsAssignmentSectionBuildValid(token, tabID) then
            return
        end
        Widgets.AddAssignmentRow(
            builder,
            item.name,
            function()
                return GetOverrideDropdownState(overrideList, overrides and overrides[item.key])
            end,
            function(key)
                if key == "default" then
                    clearConfigID(specID, item.key)
                else
                    setConfigID(specID, item.key, tonumber(key))
                end
                if onChanged then
                    onChanged()
                end
            end
        )
    end
    Widgets.FinishBuilder(builder)
end
local function SelectAssignmentSection(content, section, specID, overrideList, opts)
    opts.bumpToken()
    local token = opts.getToken()
    Shell:ClearScroll(content.scrollChild)
    for _, button in ipairs(opts.buttons) do
        button:SetSelected(button.sectionKey == section.key)
    end
    if section then
        if opts.setSelectedKey then
            opts.setSelectedKey(section.key)
        end
        BuildAssignmentSection(
            content.scrollChild,
            specID,
            section[opts.itemsKey],
            overrideList,
            token,
            opts.tabID,
            opts.assignmentKey,
            opts.getAssignments,
            opts.clearConfigID,
            opts.setConfigID,
            opts.onChanged
        )
    end
end
local SUB_TAB_CONFIG = {
    dungeons = {
        tabID = "dungeons",
        intro = TAB_INTRO.dungeons,
        defaultLoadoutLabel = "Default dungeon loadout",
        subBarRows = 2,
        itemsKey = "dungeons",
        assignmentKey = "dungeons",
        getSections = Dungeons.GetMenuSections,
        getDefaultConfigID = function(spec)
            return DB:GetDungeonDefaultConfigID(spec)
        end,
        setDefaultConfigID = function(spec, value)
            DB:SetDungeonDefaultConfigID(spec, value)
        end,
        getAssignments = function(spec)
            return DB:GetDungeonAssignmentsIfExists(spec)
        end,
        clearConfigID = function(spec, key)
            DB:ClearDungeonConfigID(spec, key)
        end,
        setConfigID = function(spec, key, value)
            DB:SetDungeonConfigID(spec, key, value)
        end,
        onAssignmentChanged = function()
            RequestTabRefresh("dungeons")
        end,
    },
    delves = {
        tabID = "delves",
        intro = TAB_INTRO.delves,
        defaultLoadoutLabel = "Default delve loadout",
        subBarRows = 1,
        itemsKey = "delves",
        assignmentKey = "delves",
        getSections = Delves.GetMenuSections,
        getDefaultConfigID = function(spec)
            return DB:GetDelveDefaultConfigID(spec)
        end,
        setDefaultConfigID = function(spec, value)
            DB:SetDelveDefaultConfigID(spec, value)
        end,
        getAssignments = function(spec)
            return DB:GetDelveAssignmentsIfExists(spec)
        end,
        clearConfigID = function(spec, key)
            DB:ClearDelveConfigID(spec, key)
        end,
        setConfigID = function(spec, key, value)
            DB:SetDelveConfigID(spec, key, value)
        end,
    },
}
local function LayoutSubTabButtons(subBar, sections, subBarRows, buttons, onClick)
    local subRowHeight = 28
    local subRowGap = 4
    wipe(buttons)

    local function addButton(index, section, x, y)
        local tabLabel = section.shortTabText or section.tabText
        local buttonWidth = math.min(118, math.max(68, #tabLabel * 7 + 18))
        local button = Widgets.CreateHeaderButton(subBar, section.tabText, buttonWidth, subRowHeight)
        button:SetPoint("TOPLEFT", subBar, "TOPLEFT", x, y)
        button.sectionKey = section.key
        button:SetScript("OnClick", function()
            onClick(section)
        end)
        if tabLabel ~= section.tabText then
            button.label:SetText(tabLabel)
        end
        buttons[index] = button
        return buttonWidth + 4
    end

    if subBarRows <= 1 then
        local x = 4
        for index, section in ipairs(sections) do
            x = x + addButton(index, section, x, -2)
        end
        return
    end

    local splitAt = math.ceil(#sections / 2)
    local rowX = { 4, 4 }
    local rowY = { -2, -(subRowHeight + subRowGap + 2) }
    for index, section in ipairs(sections) do
        local row = index <= splitAt and 1 or 2
        rowX[row] = rowX[row] + addButton(index, section, rowX[row], rowY[row])
    end
end
local function SelectSubTabSection(content, section, specID, overrideList, config)
    SelectAssignmentSection(content, section, specID, overrideList, {
        tabID = config.tabID,
        itemsKey = config.itemsKey,
        assignmentKey = config.assignmentKey,
        buttons = subTabButtons[config.tabID],
        bumpToken = function()
            subTabBuildToken[config.tabID] = subTabBuildToken[config.tabID] + 1
        end,
        getToken = function()
            return subTabBuildToken[config.tabID]
        end,
        setSelectedKey = function(key)
            selectedSubTabSectionKey[config.tabID] = key
        end,
        getAssignments = config.getAssignments,
        clearConfigID = config.clearConfigID,
        setConfigID = config.setConfigID,
        onChanged = config.onAssignmentChanged,
    })
end
local function BuildSubTabAssignmentsTab(content, config)
    local tabID = config.tabID
    Shell:ClearFrame(content.subBar)
    Shell:ClearFrame(content.header)
    local specID = Loadout.GetSpecID()
    local configList = specID and Loadout.GetConfigList(specID) or nil
    local overrideList = specID and BuildLoadoutDropdownList(specID, false, true, configList) or nil
    local sections = config.getSections()
    LayoutSubTabButtons(content.subBar, sections, config.subBarRows, subTabButtons[tabID], function(section)
        SelectSubTabSection(content, section, specID, overrideList, config)
    end)
    local headerBuilder = Widgets.NewBuilder(content.header)
    Widgets.AddLabel(headerBuilder, config.intro)
    Widgets.AddLabel(headerBuilder, config.defaultLoadoutLabel)
    AddDefaultLoadoutDropdown(headerBuilder, specID, configList, config.getDefaultConfigID, config.setDefaultConfigID)
    Widgets.FinishBuilder(headerBuilder)
    content.header:SetHeight(math.max(headerBuilder.y + 8, 1))
    Shell:LayoutSubTabContent(content, config.subBarRows)
    local activeSection = sections[1]
    local selectedKey = selectedSubTabSectionKey[tabID]
    if selectedKey then
        for _, section in ipairs(sections) do
            if section.key == selectedKey then
                activeSection = section
                break
            end
        end
    end
    if activeSection then
        SelectSubTabSection(content, activeSection, specID, overrideList, config)
    end
end
local function BuildDungeonsTab(content)
    BuildSubTabAssignmentsTab(content, SUB_TAB_CONFIG.dungeons)
end
local function BuildRaidsTab(content)
    Shell:ClearScroll(content.scrollChild)
    local builder = Widgets.NewBuilder(content.scrollChild)
    local specID = Loadout.GetSpecID()
    local configList = specID and Loadout.GetConfigList(specID) or nil
    Widgets.AddTabIntro(builder, TAB_INTRO.raids)
    Widgets.AddLabel(builder, "Default raid loadout")
    AddDefaultLoadoutDropdown(builder, specID, configList, function(spec)
        return DB:GetRaidDefaultConfigID(spec)
    end, function(spec, value)
        DB:SetRaidDefaultConfigID(spec, value)
    end)
    Widgets.AddGap(builder, 10)
    local overrideList = specID and BuildLoadoutDropdownList(specID, false, true, configList) or nil
    for _, section in ipairs(Raids.GetMenuSections()) do
        Widgets.AddHeading(builder, section.header)
        for raidIndex, raid in ipairs(section.raids) do
            local raidAssignment = specID and DB:GetRaidAssignmentIfExists(specID, raid.key) or nil
            if raidIndex > 1 then
                Widgets.AddSeparator(builder)
                Widgets.AddGap(builder, 6)
            end
            Widgets.AddHeading(builder, raid.name)
            for _, boss in ipairs(raid.bosses) do
                Widgets.AddAssignmentRow(
                    builder,
                    boss.name,
                    function()
                        return GetOverrideDropdownState(overrideList, raidAssignment and raidAssignment.bosses[boss.key])
                    end,
                    function(key)
                        if key == "default" then
                            DB:ClearRaidBossConfigID(specID, raid.key, boss.key)
                        else
                            DB:SetRaidBossConfigID(specID, raid.key, boss.key, tonumber(key))
                        end
                    end
                )
            end
        end
    end
    Widgets.FinishBuilder(builder)
end
local function BuildContentAssignmentsTab(builder, specID, configList, intro, getDefaultConfigID, setDefaultConfigID, getSections, getOverride, clearConfigID, setConfigID, collectionKey)
    Widgets.AddTabIntro(builder, intro)
    Widgets.AddLabel(builder, "Default loadout")
    AddDefaultLoadoutDropdown(builder, specID, configList, getDefaultConfigID, setDefaultConfigID)
    Widgets.AddGap(builder, 10)
    local overrideList = specID and BuildLoadoutDropdownList(specID, false, true, configList) or nil
    for _, section in ipairs(getSections()) do
        Widgets.AddHeading(builder, section.header)
        for _, item in ipairs(section[collectionKey]) do
            Widgets.AddAssignmentRow(
                builder,
                item.name,
                function()
                    return GetOverrideDropdownState(overrideList, specID and getOverride(specID, item.key))
                end,
                function(key)
                    if key == "default" then
                        clearConfigID(specID, item.key)
                    else
                        setConfigID(specID, item.key, tonumber(key))
                    end
                end
            )
        end
    end
    Widgets.FinishBuilder(builder)
end
local function BuildDelvesTab(content)
    BuildSubTabAssignmentsTab(content, SUB_TAB_CONFIG.delves)
end
local function BuildPvPTab(content)
    Shell:ClearScroll(content.scrollChild)
    local specID = Loadout.GetSpecID()
    local configList = specID and Loadout.GetConfigList(specID) or nil
    local builder = Widgets.NewBuilder(content.scrollChild)
    BuildContentAssignmentsTab(
        builder,
        specID,
        configList,
        TAB_INTRO.pvp,
        function(spec)
            return DB:GetPvPDefaultConfigID(spec)
        end,
        function(spec, value)
            DB:SetPvPDefaultConfigID(spec, value)
        end,
        PvP.GetMenuSections,
        function(spec, key)
            local assignments = DB:GetPvPAssignments(spec)
            return assignments and assignments.modes[key]
        end,
        function(spec, key)
            DB:ClearPvPConfigID(spec, key)
        end,
        function(spec, key, value)
            DB:SetPvPConfigID(spec, key, value)
        end,
        "modes"
    )
end
local TAB_BUILDERS = {
    general = BuildGeneralTab,
    priority = BuildPriorityTab,
    loadouts = BuildLoadoutsTab,
    dungeons = BuildDungeonsTab,
    raids = BuildRaidsTab,
    delves = BuildDelvesTab,
    pvp = BuildPvPTab,
}
local function OnTabSelected(content, tabID)
    subTabBuildToken.dungeons = subTabBuildToken.dungeons + 1
    subTabBuildToken.delves = subTabBuildToken.delves + 1
    if tabID == "dungeons" or tabID == "delves" then
        Shell:EnsureSubTabContent(content)
    else
        Shell:EnsurePlainContent(content)
    end
    local builder = TAB_BUILDERS[tabID]
    if builder then
        builder(content)
    end
end
Shell:SetOnTabSelected(OnTabSelected)
function Menu.Show(tabID)
    selectedManageConfigID = Loadout.GetLoadoutConfigID()
    Shell:Show(tabID or "general")
end
function Menu.IsShown()
    return Shell:IsShown()
end
local optionsPanel
local optionsCategory
local optionsRegistered
local function EnsureOptionsPanel()
    if optionsPanel then
        return optionsPanel
    end
    local panel = CreateFrame("Frame", "LoadoutLockerOptionsPanel")
    panel.name = "LoadoutLocker"
    panel:SetScript("OnShow", function()
        C_Timer.After(0, function()
            if SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
            Menu.Show()
        end)
    end)
    optionsPanel = panel
    return panel
end
function Menu.RegisterWithSettings()
    if optionsRegistered then
        return
    end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local panel = EnsureOptionsPanel()
    optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, "LoadoutLocker")
    optionsCategory.ID = "LoadoutLocker"
    Settings.RegisterAddOnCategory(optionsCategory)
    optionsRegistered = true
end
