#Requires AutoHotkey v2.0

; FTL: Multiverse – Save Restorer and Command Runner
; Copyright (C) 2025  mikeInside
; Licensed under GPL-3.0-or-later
; https://www.gnu.org/licenses/gpl-3.0.html
; SPDX-License-Identifier: GPL-3.0-or-later
;
; --- Data Licensing Notice ---
; This program includes a CSV derived from:
; "List of IDs" on the FTL Multiverse Wiki
; https://ftlmultiverse.miraheze.org/wiki/List_of_IDs
; Content is licensed under Creative Commons Attribution-ShareAlike 4.0 International
; (CC BY-SA 4.0). You must provide attribution and share derivative data under the
; same license. See: https://creativecommons.org/licenses/by-sa/4.0/

; === Paths and configuration ===
defaultGameExe := "C:\\Program Files (x86)\\Steam\\steamapps\\common\\FTL Faster Than Light\\FTLGame.exe"
configFile := A_ScriptDir "\FTLSaveRestore.ini"
iconFile := A_ScriptDir "\FTLSaveRestore.ico"

config := LoadConfig()
saveFolder := config.SaveFolder
backupFolder := saveFolder "Backup\"
continueFile := saveFolder "hs_mv_continue.sav"
userScriptsFolder := A_ScriptDir "\UserScripts\"
commandCsvPath := A_ScriptDir "\FTLCommands.csv"

DirCreate(backupFolder)
DirCreate(userScriptsFolder)
checkIntervalMs := Max(1000, config.CheckIntervalSeconds * 1000)
commandDelayMs := Max(0, Round(config.CommandDelaySeconds * 1000))

lastModTime := ""
try
	lastModTime := FileGetTime(continueFile)
catch
	lastModTime := ""

backupSets := []
rowToTimestamp := Map()

global shipLabelCtrl := unset
global shipCombo := unset
global filterLabelCtrl := unset
global filterEdit := unset
global backupListView := unset
global stringView := unset
global restoreBtn := unset
global restoreAllChk := unset
global refreshBtn := unset
global openFolderBtn := unset
global launchBtn := unset
global consoleCommandsBtn := unset
global autoLaunchChk := unset
global checkIntervalLabel := unset
global checkIntervalEdit := unset
global checkIntervalUpDown := unset
global gamePathLabel := unset
global gamePathEdit := unset
global browseGameBtn := unset
global saveFolderLabel := unset
global saveFolderEdit := unset
global browseSaveBtn := unset
global refreshInProgress := false
global tooltipActive := false
global tooltipText := ""
global tooltipEndTime := 0
global checkIntervalMs
global restoreButtonWidth := 220
global resizePending := {Gui: 0, Width: 0, Height: 0, MinMax: 0}
global commandGui := unset
global commandCategoryLabel := unset
global commandEditor := unset
global commandSubcategoryLabel := unset
global commandTopicLabel := unset
global commandListView := unset
global commandCategoryCombo := unset
global commandSubcategoryCombo := unset
global commandTopicCombo := unset
global commandSaveBtn := unset
global commandLoadBtn := unset
global commandRunBtn := unset
global commandStatusLabel := unset
global commandSearchLabel := unset
global commandSearchEdit := unset
global commandRowToIndex := Map()
global commandCatalog := {Commands: [], Error: ""}
global commandCatalogError := ""
global commandFilterRefreshing := false
global commandCategoryAllLabel := "All Categories"
global commandSubcategoryAllLabel := "All Subcategories"
global commandTopicAllLabel := "All Types"
global commandDelayMs
global commandResizePending := {Gui: 0, Width: 0, Height: 0, MinMax: 0}
trayIconSource := GetPreferredIconSource()
TraySetIcon(trayIconSource.Path, trayIconSource.Index)
ReloadCommandCatalog()
mainGui := CreateMainGui()
A_TrayMenu.Delete()
A_TrayMenu.Add("Open Restore Window", ShowMainWindow)
A_TrayMenu.Add("Open Command Editor", ShowCommandEditor)
A_TrayMenu.Add()
A_TrayMenu.Add("Reload This Script", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
OnMessage(0x404, TrayMessage)

ReloadSaveList()

if config.MinimizeGUItoSystrayOnStartup {
	mainGui.Hide()
} else {
	ShowMainWindow()
}

if config.AutoLaunch
	LaunchGame(false)

SetTimer(CheckFileChange, checkIntervalMs)
return

CheckFileChange(*) {
	global continueFile, lastModTime
	current := ""
	try
		current := FileGetTime(continueFile)
	catch
		current := ""
	if (current != "" && current != lastModTime) {
		lastModTime := current
		Sleep(3000)
		BackupSaves()
	}
}

BackupSaves() {
	global saveFolder, backupFolder, continueFile
	info := ParseSaveFile(continueFile)
	shipName := info.ShipName != "" ? info.ShipName : "Unknown Ship"
	shipTag := SanitizeFilePart(shipName)
	tsSource := ""
	try
		tsSource := FileGetTime(continueFile)
	catch
		tsSource := ""
	ts := FormatTime(tsSource != "" ? tsSource : A_Now, "yyyyMMddHHmmss")
	CopySaveSet(shipTag, ts, "*.sav")
	CopySaveSet(shipTag, ts, "*.vdf")
	ReloadSaveList()
}

CopySaveSet(shipTag, ts, pattern) {
	global saveFolder, backupFolder
	Loop Files, saveFolder pattern, "F" {
		destName := shipTag "-" ts "-" A_LoopFileName
		try
			FileCopy(A_LoopFilePath, backupFolder destName, 1)
		catch as e
			MsgBox("Backup failed: " e.Message)
	}
}

ReloadSaveList() {
	global refreshInProgress
	if refreshInProgress
		return
	refreshInProgress := true
	UpdateRestoreButtonState()
	try {
		RefreshBackupList()
		FilterBackups()
	} finally {
		refreshInProgress := false
		UpdateRestoreButtonState()
	}
}

RefreshBackupList() {
	global backupFolder, backupSets
	sets := Map()
	Loop Files, backupFolder "*", "F" {
		if !RegExMatch(A_LoopFileName, "^(.*?)-(\d{14})-(.+)$", &m)
			continue
		shipTag := m[1]
		ts := m[2]
		original := m[3]
		if !sets.Has(ts)
			sets[ts] := {ShipTag: shipTag, Timestamp: ts, Files: [], SavPath: "", ShipName: "", Strings: "UNPARSED"}
		set := sets[ts]
		set.Files.Push({Name: original, Path: A_LoopFileFullPath})
		if (set.SavPath = "" && InStr(StrLower(original), ".sav"))
			set.SavPath := A_LoopFileFullPath
	}
	backupSets := []
	for ts, set in sets {
		; Use ship name from filename tag, no file parsing needed
		set.ShipName := FormatShipTag(set.ShipTag)
		set.Strings := "UNPARSED"  ; Parse on demand
		backupSets.Push(set)
	}
	backupSets := SortBackupSets(backupSets)
	RefreshShipFilter()
}

CompareTimestamps(a, b) {
	if a.Timestamp == b.Timestamp
		return 0
	return a.Timestamp > b.Timestamp ? -1 : 1
}

SortArray(arr, compareFn) {
	n := arr.Length
	loop n - 1 {
		i := A_Index
		loop n - i {
			j := A_Index
			if compareFn(arr[j], arr[j + 1]) > 0 {
				temp := arr[j]
				arr[j] := arr[j + 1]
				arr[j + 1] := temp
			}
		}
	}
}

SortBackupSets(arr) {
	SortArray(arr, CompareTimestamps)
	return arr
}

RefreshShipFilter() {
	global backupSets, shipCombo
	if !IsSet(shipCombo)
		return
	seen := Map()
	ships := []
	for set in backupSets {
		ship := set.ShipName
		if ship = ""
			ship := "Unknown Ship"
		if !seen.Has(ship) {
			seen[ship] := true
			ships.Push(ship)
		}
	}
	SortArray(ships, (a,b) => StrCompare(a,b))
	current := shipCombo.Text
	shipCombo.Delete()
	shipCombo.Add(["All Ships"])
	for ship in ships
		shipCombo.Add([ship])
	if current == "All Ships"
		idx := 1
	else {
		idx := 0
		for i, ship in ships {
			if ship == current {
				idx := i + 1
				break
			}
		}
		if idx == 0
			idx := 1
	}
	shipCombo.Choose(idx)
}

FilterBackups(*) {
	global backupSets, shipCombo, filterEdit, backupListView, rowToTimestamp, stringView
	if !IsSet(backupListView)
		return
	selectedShip := "All Ships"
	if IsSet(shipCombo) && shipCombo.Text != ""
		selectedShip := shipCombo.Text
	textFilter := ""
	if IsSet(filterEdit)
		textFilter := StrLower(Trim(filterEdit.Text))
	backupListView.Delete()
	rowToTimestamp.Clear()
	for set in backupSets {
		shipName := set.ShipName != "" ? set.ShipName : "Unknown Ship"
		if (selectedShip != "All Ships" && !StringEquals(shipName, selectedShip))
			continue
		if (textFilter != "") {
			searchHaystack := StrLower(shipName " " set.Timestamp)
			for file in set.Files
				searchHaystack .= " " StrLower(file.Name)
			if !InStr(searchHaystack, textFilter)
				continue
		}
		displayTime := FormatTime(set.Timestamp, "dddd d MMM yyyy, hh:mm.ss tt")
		fileSummary := set.Files.Length " file" (set.Files.Length = 1 ? "" : "s")
		row := backupListView.Add("", shipName, displayTime, fileSummary)
		rowToTimestamp[row] := set.Timestamp
	}
	backupListView.ModifyCol()
	backupListView.ModifyCol(2, 200)
	backupListView.ModifyCol(3, 80)
	stringView.Value := ""
	UpdateRestoreButtonState()
}

GetSelectedTimestamps() {
	global backupListView, rowToTimestamp
	results := []
	if !IsSet(backupListView)
		return results
	row := 0
	while (row := backupListView.GetNext(row)) {
		if rowToTimestamp.Has(row)
			results.Push(rowToTimestamp[row])
	}
	return results
}

UpdateRestoreButtonState() {
	global restoreBtn, refreshInProgress
	if !IsSet(restoreBtn)
		return
	if refreshInProgress {
		ApplyRestoreButtonStyle("Refreshing Save List...", false, "808080")
		return
	}
	selected := GetSelectedTimestamps()
	count := selected.Length
	if count = 0 {
		ApplyRestoreButtonStyle("Restore Save", false, "808080")
		return
	}
	if count = 1 {
		ApplyRestoreButtonStyle("Restore Save", true, "008000")
		return
	}
	ApplyRestoreButtonStyle("Delete Saves", true, "CC0000")
}

ApplyRestoreButtonStyle(text, enabled, color) {
    global restoreBtn, restoreButtonWidth
    if !IsSet(restoreBtn)
        return
    restoreBtn.Text := text
    restoreBtn.Enabled := enabled
    restoreBtn.SetFont("Bold")
    restoreBtn.Opt("+Background" color)
    restoreBtn.Move(,, restoreButtonWidth)
}

ShowFollowTooltip(text, duration := 3000) {
	global tooltipActive, tooltipText, tooltipEndTime
	tooltipText := text
	tooltipEndTime := A_TickCount + duration
	tooltipActive := true
	TooltipUpdater()
	SetTimer(TooltipUpdater, 50)
}

TooltipUpdater(*) {
	global tooltipActive, tooltipText, tooltipEndTime
	if !tooltipActive {
		ToolTip()
		SetTimer(TooltipUpdater, 0)
		return
	}
	if (A_TickCount >= tooltipEndTime) {
		tooltipActive := false
		ToolTip()
		SetTimer(TooltipUpdater, 0)
		return
	}
	MouseGetPos(&mx, &my)
	ToolTip(tooltipText, mx + 18, my + 18)
}

CreateMainGui() {
    global shipLabelCtrl, shipCombo, filterLabelCtrl, filterEdit
    global backupListView, stringView
	global restoreBtn, restoreAllChk, launchBtn, consoleCommandsBtn, refreshBtn, autoLaunchChk
    global gamePathLabel, gamePathEdit, browseGameBtn
    global checkIntervalLabel, checkIntervalEdit, checkIntervalUpDown
	global saveFolderLabel, saveFolderEdit, browseSaveBtn, openFolderBtn
    global config
    global mainGui
    ; Calculate default size: 80% of screen
    defaultW := Floor(A_ScreenWidth * 0.8)
    defaultH := Floor(A_ScreenHeight * 0.8)
    ; Use saved or default for initial sizing
    w := config.WindowW > 0 ? config.WindowW : defaultW
    h := config.WindowH > 0 ? config.WindowH : defaultH
    options := "+Resize +MinSize700x450"
	mainGui := Gui(options, "FTL: Multiverse Save Restorer")
	mainGui.SetFont("s9", "Segoe UI")
    mainGui.OnEvent("Close", (*) => mainGui.Hide())
    mainGui.OnEvent("Escape", (*) => mainGui.Hide())

    shipLabelCtrl := mainGui.Add("Text", "xm ym", "Ship:")
    shipCombo := mainGui.AddComboBox("vShipFilter x+m w220")
    shipCombo.Add(["All Ships"])
    shipCombo.Choose(1)
    shipCombo.OnEvent("Change", FilterBackups)

    filterLabelCtrl := mainGui.Add("Text", "x+30 yp", "Filter:")
    filterEdit := mainGui.AddEdit("vNameFilter x+m w240")
    filterEdit.OnEvent("Change", FilterBackups)

	backupListView := mainGui.AddListView("vBackupList xm w320 r15 +Multi AltSubmit", ["Ship", "Saved", "Files"])
    backupListView.OnEvent("ItemSelect", OnBackupSelect)
    backupListView.OnEvent("DoubleClick", (*) => RestoreSelected())

    stringView := mainGui.AddEdit("vStringView x+10 w320 r15 ReadOnly WantReturn -Wrap")

	restoreBtn := mainGui.AddButton("vRestoreBtn xm w" restoreButtonWidth, "Restore Save")
    restoreBtn.OnEvent("Click", (*) => RestoreSelected())

	restoreAllChk := mainGui.AddCheckBox("vRestoreAllChk x+10", "Restore all (achievements and progress)")
    restoreAllChk.OnEvent("Click", RestoreAllToggled)
    restoreAllChk.Value := config.RestoreAllAchievementsAndProgress ? 1 : 0

	refreshBtn := mainGui.AddButton("vRefreshBtn x+10 w100", "Refresh")
	refreshBtn.OnEvent("Click", (*) => ReloadSaveList())

    openFolderBtn := mainGui.AddButton("vOpenFolderBtn x+10 w130", "Open Save Folder")
    openFolderBtn.OnEvent("Click", OpenSaveFolder)

	launchBtn := mainGui.AddButton("vLaunchBtn x+10 w120", "Launch Game")
    launchBtn.OnEvent("Click", (*) => LaunchGame(true))

	consoleCommandsBtn := mainGui.AddButton("vConsoleCommandsBtn x+10 w150", "Console Commands")
	consoleCommandsBtn.OnEvent("Click", ShowCommandEditor)

    autoLaunchChk := mainGui.AddCheckBox("vAutoLaunchChk x+20", "Automatically launch game")
    autoLaunchChk.OnEvent("Click", AutoLaunchToggled)
    autoLaunchChk.Value := config.AutoLaunch ? 1 : 0

	gamePathLabel := mainGui.AddText("xm y+m", "Game exe path:")
	gamePathEdit := mainGui.AddEdit("vGamePath xm w360 ReadOnly")
	gamePathEdit.Value := config.GamePath
	browseGameBtn := mainGui.AddButton("x+10 w90", "Browse")
	browseGameBtn.OnEvent("Click", BrowseForGameExe)

	saveFolderLabel := mainGui.AddText("xm y+m", "Save folder path:")
	saveFolderEdit := mainGui.AddEdit("vSaveFolder xm w360 ReadOnly")
	saveFolderEdit.Value := config.SaveFolder
	browseSaveBtn := mainGui.AddButton("x+10 w90", "Browse")
	browseSaveBtn.OnEvent("Click", BrowseForSaveFolder)

	checkIntervalLabel := mainGui.AddText("xm y+m", "Check for saves every X seconds:")
	checkIntervalEdit := mainGui.AddEdit("vCheckInterval x+m w70 Number")
	checkIntervalEdit.Value := config.CheckIntervalSeconds
	checkIntervalUpDown := mainGui.Add("UpDown", "Range1-3600", config.CheckIntervalSeconds)
	checkIntervalEdit.OnEvent("LoseFocus", CheckIntervalChanged)
	checkIntervalUpDown.OnEvent("Change", CheckIntervalChanged)

	; Show the GUI off-screen only after all controls exist so Size events
	; won't run while control variables are still uninitialized.
	mainGui.Show("x-10000 y-10000 w" w " h" h)
	mainGui.GetClientPos(,,&clientW,&clientH)
	PositionControls(mainGui, clientW, clientH)
	mainGui.OnEvent("Size", Gui_OnSize)
	mainGui.Hide()  ; Hide after positioning

    return mainGui
}

Gui_OnSize(thisGui, MinMax, Width, Height) {
	global resizePending
	resizePending.Gui := thisGui
	resizePending.Width := Width
	resizePending.Height := Height
	resizePending.MinMax := MinMax
	SetTimer(ResizeDebounced, -150)
}

ResizeDebounced(*) {
	global resizePending, config
	targetGui := resizePending.Gui
	if !IsObject(targetGui)
		return
	w := resizePending.Width
	h := resizePending.Height
	minMax := resizePending.MinMax
	PositionControls(targetGui, w, h)
	; Save window state after repositioning
	config.WindowW := w
	config.WindowH := h
	WinGetPos(&x, &y, , , "ahk_id " targetGui.Hwnd)
	if (x >= 0 && y >= 0) {
		config.WindowX := x
		config.WindowY := y
	}
	config.WindowMax := minMax == 1
	SaveConfig()
}


PositionControls(thisGui, Width, Height) {
	global shipLabelCtrl, shipCombo, filterLabelCtrl, filterEdit
	global backupListView, stringView
	global restoreBtn, restoreAllChk, openFolderBtn, launchBtn, consoleCommandsBtn, refreshBtn, autoLaunchChk
	global gamePathLabel, gamePathEdit, browseGameBtn
	global saveFolderLabel, saveFolderEdit, browseSaveBtn
	global checkIntervalLabel, checkIntervalEdit
	global restoreButtonWidth
	margin := 12
	buttonHeight := 32
	topRowHeight := 32
	minListWidth := 260
	minDetailWidth := 220
	rowSpacing := Floor(margin / 2)
	bottomRows := 5
	bottomSectionHeight := bottomRows * buttonHeight + (bottomRows - 1) * rowSpacing

	availableWidth := Width - margin * 3
	lvWidth := Floor(availableWidth * 0.5)
	if (lvWidth < minListWidth)
		lvWidth := minListWidth
	if (lvWidth > availableWidth - minDetailWidth)
		lvWidth := availableWidth - minDetailWidth
	if (lvWidth < minListWidth)
		lvWidth := minListWidth
	detailWidth := availableWidth - lvWidth
	if (detailWidth < minDetailWidth)
		detailWidth := minDetailWidth

	topY := margin
	shipLabelWidth := 50
	filterLabelWidth := 50
	shipLabelCtrl.Move(margin, topY + 6, shipLabelWidth, 20)
	shipCombo.Move(margin + shipLabelWidth + 5, topY, lvWidth - shipLabelWidth - 5, 24)
	filterLabelCtrl.Move(margin + lvWidth + margin, topY + 6, filterLabelWidth, 20)
	filterEdit.Move(margin + lvWidth + margin + filterLabelWidth + 5, topY, detailWidth - filterLabelWidth - 5, 24)

	listTop := topY + topRowHeight
	availableHeight := Height - listTop - margin - bottomSectionHeight
	if (availableHeight < 120)
		availableHeight := 120

	backupListView.Move(margin, listTop, lvWidth, availableHeight)
	stringView.Move(margin + lvWidth + margin, listTop, detailWidth, availableHeight)

	rowY := listTop + availableHeight + rowSpacing
	restoreBtn.Move(margin, rowY, restoreButtonWidth, buttonHeight)
	restoreAllChk.Move(margin + restoreButtonWidth + margin, rowY + 6)
	refreshBtnX := margin + restoreButtonWidth + margin + 250 + margin  ; Adjust for checkbox width
	refreshBtn.Move(refreshBtnX, rowY, 100, buttonHeight)

	rowY += buttonHeight + rowSpacing
	launchBtn.Move(margin, rowY, 140, buttonHeight)
	consoleCommandsBtn.Move(margin + 140 + margin, rowY, 150, buttonHeight)
	autoLaunchChk.Move(margin + 140 + margin + 150 + margin, rowY + 6)

	rowY += buttonHeight + rowSpacing
	labelWidth := 110
	saveFolderLabel.Move(margin, rowY + 6, labelWidth, 20)
	editWidth := Width - (margin * 2 + labelWidth + margin + 130 + margin + 90 + margin)  ; For edit, browse, open
	if (editWidth < 160)
		editWidth := 160
	saveFolderEdit.Move(margin + labelWidth + margin, rowY, editWidth, buttonHeight)
	openFolderBtn.Move(margin + labelWidth + margin + editWidth + margin, rowY, 130, buttonHeight)
	browseSaveBtn.Move(margin + labelWidth + margin + editWidth + margin + 130 + margin, rowY, 90, buttonHeight)

	rowY += buttonHeight + rowSpacing
	gamePathLabel.Move(margin, rowY + 6, labelWidth, 20)
	editWidth := Width - (margin * 2 + labelWidth + margin + 90 + margin)  ; Added extra margin for right spacing
	if (editWidth < 160)
		editWidth := 160
	gamePathEdit.Move(margin + labelWidth + margin, rowY, editWidth, buttonHeight)
	browseGameBtn.Move(margin + labelWidth + margin + editWidth + margin, rowY, 90, buttonHeight)

	rowY += buttonHeight + rowSpacing
	checkIntervalLabel.Move(margin, rowY + 6, 240, 20)
	checkIntervalEdit.Move(margin + 250, rowY, 80, buttonHeight)
	checkIntervalUpDown.Move(margin + 250 + 80, rowY, 20, buttonHeight)
}

OnBackupSelect(ctrl, rowNumber, selected) {
	global stringView
	UpdateRestoreButtonState()
	selectedTs := GetSelectedTimestamps()
	if selectedTs.Length = 1 {
		ShowStringsForTimestamp(selectedTs[1])
		return
	}
	stringView.Value := ""
}

ShowStringsForTimestamp(ts) {
	global backupSets, stringView
	for set in backupSets {
		if set.Timestamp = ts {
			if set.Strings == "UNPARSED" {
				; Parse strings on demand
				if set.SavPath != "" {
					info := ParseSaveFile(set.SavPath)
					set.Strings := info.Strings
				} else {
					set.Strings := []
				}
			}
			stringView.Value := BuildStringDisplay(set.Strings)
			return
		}
	}
	stringView.Value := ""
}

LoadStringsFromSet(set) {
	if set.SavPath = ""
		return []
	info := ParseSaveFile(set.SavPath)
	set.ShipName := info.ShipName != "" ? info.ShipName : set.ShipName
	return info.Strings
}

BuildStringDisplay(strings) {
	if strings.Length = 0
		return ""
	display := ""
	for index, record in strings {
		value := record.Has("value") ? record["value"] : record
		display .= Format("{1:03d}: {2}`r`n", index, value)
	}
	return RTrim(display, "`r`n")
}

RestoreSelected() {
	global refreshInProgress, config, saveFolder
	if refreshInProgress
		return
	selected := GetSelectedTimestamps()
	count := selected.Length
	if count = 0 {
		MsgBox("Please select a backup.")
		return
	}
	if count > 1 {
		DeleteSelectedSaves(selected)
		return
	}
	ts := selected[1]
	set := GetBackupSet(ts)
	if !IsObject(set) {
		MsgBox("Backup set not found.")
		return
	}
	EnsureCurrentBackupExists()
	restored := 0
	failed := false
	try {
		for file in set.Files {
			if (!config.RestoreAllAchievementsAndProgress && file.Name != "hs_mv_continue.sav")
				continue
			targetName := file.Name
			FileCopy(file.Path, saveFolder targetName, 1)
			restored++
		}
	} catch as e {
		failed := true
		MsgBox("Restore failed: " e.Message)
	}
	if failed
		return
	reloadMsg := "Restored " restored " file" (restored = 1 ? "" : "s") " from " set.ShipName "`n" FormatTime(set.Timestamp, "yyyy-MM-dd HH:mm:ss")
	ShowFollowTooltip(reloadMsg)
	ReloadSaveList()
}

DeleteSelectedSaves(timestamps) {
	if timestamps.Length = 0
		return
	confirm := MsgBox("Delete the selected " timestamps.Length " save set" (timestamps.Length = 1 ? "" : "s") "?", "Delete Saves", "YesNo Icon! Default2")
	if (confirm != "Yes")
		return
	failures := []
	for ts in timestamps {
		set := GetBackupSet(ts)
		if !IsObject(set)
			continue
		for file in set.Files {
			try
				FileDelete(file.Path)
			catch as e
				failures.Push(file.Path " - " e.Message)
		}
	}
	if failures.Length > 0 {
		errMsg := "Some files could not be deleted:`n`n"
		for entry in failures
			errMsg .= entry "`n"
		MsgBox(RTrim(errMsg, "`n"))
	}
	ReloadSaveList()
}

GetBackupSet(ts) {
	global backupSets
	for set in backupSets
		if set.Timestamp = ts
			return set
	return ""
}

EnsureCurrentBackupExists() {
	global backupFolder, continueFile, saveFolder
	currentTime := ""
	try
		currentTime := FileGetTime(continueFile)
	catch
		currentTime := ""
	if (currentTime = "")
		currentTime := A_Now
	ts := FormatTime(currentTime, "yyyyMMddHHmmss")
	existing := false
	Loop Files, backupFolder "*-" ts "-*", "F" {
		existing := true
		break
	}
	if existing
		return ts
	info := ParseSaveFile(continueFile)
	shipName := info.ShipName != "" ? info.ShipName : "Current Ship"
	shipTag := SanitizeFilePart(shipName)
	CopySaveSet(shipTag, ts, "*.sav")
	CopySaveSet(shipTag, ts, "*.vdf")
	return ts
}

OpenSaveFolder(*) {
	global saveFolder
	if !DirExist(saveFolder)
		DirCreate(saveFolder)
	Run(saveFolder)
}

BrowseForGameExe(*) {
	global config, gamePathEdit
	startPath := config.GamePath
	if (startPath = "")
		startPath := A_ScriptDir
	selected := FileSelect("1", startPath, "Select FTLGame.exe", "Executable (*.exe)")
	if (selected = "")
		return
	config.GamePath := selected
	if IsSet(gamePathEdit)
		gamePathEdit.Value := selected
	SaveConfig()
	ApplyIconSource(GetPreferredIconSource())
}

BrowseForSaveFolder(*) {
	global config, saveFolderEdit, saveFolder, backupFolder
	startPath := config.SaveFolder
	if (startPath = "")
		startPath := A_MyDocuments
	selected := DirSelect(startPath, , "Select FTL Save Folder")
	if (selected = "")
		return
	config.SaveFolder := selected
	if IsSet(saveFolderEdit)
		saveFolderEdit.Value := selected
	saveFolder := selected
	backupFolder := saveFolder "Backup\"
	DirCreate(backupFolder)
	SaveConfig()
	ReloadSaveList()
}

LaunchGame(autoPrompt := true) {
	global config, defaultGameExe
	gamePath := config.GamePath
	if (gamePath = "")
		gamePath := defaultGameExe
	if !FileExist(gamePath) {
		if !autoPrompt
			return
		gamePath := FileSelect("1", , "Select FTLGame.exe", "Executable (*.exe)")
		if (gamePath = "")
			return
		config.GamePath := gamePath
		SaveConfig()
	}
	if !FileExist(gamePath) {
		MsgBox("FTLGame.exe not found.")
		return
	}
	if ProcessExist("FTLGame.exe") {
		MsgBox("FTL is already running.")
		return
	}
	SplitPath(gamePath, , &gameDir)
	Run('"' gamePath '"', gameDir)
}

AutoLaunchToggled(ctrl, *) {
	global config
	config.AutoLaunch := ctrl.Value = 1
	SaveConfig()
}

RestoreAllToggled(ctrl, *) {
	global config
	config.RestoreAllAchievementsAndProgress := ctrl.Value = 1
	SaveConfig()
}

CheckIntervalChanged(ctrl, *) {
	global config, checkIntervalEdit, checkIntervalUpDown, checkIntervalMs
	value := checkIntervalUpDown.Value
	seconds := Round(value)
	if (seconds < 1)
		seconds := 1
	checkIntervalUpDown.Value := seconds
	checkIntervalEdit.Value := seconds
	if (seconds = config.CheckIntervalSeconds)
		return
	config.CheckIntervalSeconds := seconds
	checkIntervalMs := seconds * 1000
	SetTimer(CheckFileChange, checkIntervalMs)
	SaveConfig()
}

TrayMessage(wParam, lParam, msg, hwnd) {
	if (lParam = 0x201) ; WM_LBUTTONDOWN
		ShowMainWindow()
}

ShowMainWindow(*) {
	global mainGui, autoLaunchChk, config, gamePathEdit, checkIntervalEdit, checkIntervalUpDown
	ReloadSaveList()
	autoLaunchChk.Value := config.AutoLaunch ? 1 : 0
	if IsSet(gamePathEdit)
		gamePathEdit.Value := config.GamePath
	if IsSet(checkIntervalEdit)
		checkIntervalEdit.Value := config.CheckIntervalSeconds
	if IsSet(checkIntervalUpDown)
		checkIntervalUpDown.Value := config.CheckIntervalSeconds
	; Set position before showing
	defaultW := Floor(A_ScreenWidth * 0.8)
	defaultH := Floor(A_ScreenHeight * 0.8)
	defaultX := Floor((A_ScreenWidth - defaultW) / 2)
	defaultY := Floor((A_ScreenHeight - defaultH) / 2)
	w := config.WindowW > 0 ? config.WindowW : defaultW
	h := config.WindowH > 0 ? config.WindowH : defaultH
	x := config.WindowX >= 0 ? config.WindowX : defaultX
	y := config.WindowY >= 0 ? config.WindowY : defaultY
	; Check if window would be off-screen or invalid
	if (x < 0 || y < 0 || x + w > A_ScreenWidth || y + h > A_ScreenHeight || w > A_ScreenWidth || h > A_ScreenHeight) {
		x := defaultX
		y := defaultY
		w := defaultW
		h := defaultH
		config.WindowX := x
		config.WindowY := y
		config.WindowW := w
		config.WindowH := h
		config.WindowMax := false
		SaveConfig()
	}
	showOptions := "x" x " y" y " w" w " h" h
	if config.WindowMax
		showOptions .= " Maximize"
	mainGui.Show(showOptions)
}


; ============================================================================
; === Command catalog and script editor ======================================
; ============================================================================

ShowCommandEditor(*) {
	targetGui := EnsureCommandEditorGui()
	; Set position before showing, similar to ShowMainWindow
	defaultW := Floor(A_ScreenWidth * 0.7)
	defaultH := Floor(A_ScreenHeight * 0.6)
	defaultX := Floor((A_ScreenWidth - defaultW) / 2)
	defaultY := Floor((A_ScreenHeight - defaultH) / 2)
	x := config.CommandWindowX >= 0 ? config.CommandWindowX : defaultX
	y := config.CommandWindowY >= 0 ? config.CommandWindowY : defaultY
	w := config.CommandWindowW > 0 ? config.CommandWindowW : defaultW
	h := config.CommandWindowH > 0 ? config.CommandWindowH : defaultH
	; Check if window would be off-screen or invalid
	if (x < 0 || y < 0 || x + w > A_ScreenWidth || y + h > A_ScreenHeight || w > A_ScreenWidth || h > A_ScreenHeight) {
		x := defaultX
		y := defaultY
		w := defaultW
		h := defaultH
		config.CommandWindowX := x
		config.CommandWindowY := y
		config.CommandWindowW := w
		config.CommandWindowH := h
		config.CommandWindowMax := false
		SaveConfig()
	}
	showOptions := "x" x " y" y " w" w " h" h
	if config.CommandWindowMax
		showOptions .= " Maximize"
	targetGui.Show(showOptions)
	if !WinActive("ahk_id " targetGui.Hwnd)
		WinActivate("ahk_id " targetGui.Hwnd)
    commandListView.Focus()
}

EnsureCommandEditorGui() {
	global commandGui
	if !IsSet(commandGui) || !IsObject(commandGui) {
		commandGui := CreateCommandEditorGui()
	}
	return commandGui
}

CreateCommandEditorGui() {
	global commandGui
	global commandSearchLabel, commandSearchEdit
	global commandCategoryLabel, commandCategoryCombo
	global commandSubcategoryLabel, commandSubcategoryCombo
	global commandTopicLabel, commandTopicCombo
	global commandListView, commandEditor
	global commandSaveBtn, commandLoadBtn, commandRunBtn, commandClearBtn
	global commandStatusLabel
	global commandSearchLabel, commandSearchEdit

	defaultW := Floor(A_ScreenWidth * 0.7)
	defaultH := Floor(A_ScreenHeight * 0.6)
	options := "+Resize +MinSize700x460"
	guiCmd := Gui(options, "FTL: Command Runner")
	guiCmd.SetFont("s9", "Segoe UI")
	guiCmd.OnEvent("Close", (*) => guiCmd.Hide())
	guiCmd.OnEvent("Escape", (*) => guiCmd.Hide())

	commandSearchLabel := guiCmd.AddText("xm ym", "Filter:")
	commandSearchEdit := guiCmd.AddEdit("vCommandSearch x+m w220")
	commandSearchEdit.OnEvent("Change", CommandSearchChanged)

	commandCategoryLabel := guiCmd.AddText("xm y+m", "Category:")
	commandCategoryCombo := guiCmd.AddDropDownList("vCommandCategory x+m w200")
	commandCategoryCombo.OnEvent("Change", CommandCategoryChanged)

	commandSubcategoryLabel := guiCmd.AddText("x+30 yp", "Subcategory:")
	commandSubcategoryCombo := guiCmd.AddDropDownList("vCommandSubcategory x+m w200")
	commandSubcategoryCombo.OnEvent("Change", CommandSubcategoryChanged)
	commandSubcategoryCombo.Enabled := false

	commandTopicLabel := guiCmd.AddText("x+30 yp", "Type:")
	commandTopicCombo := guiCmd.AddDropDownList("vCommandTopic x+m w200")
	commandTopicCombo.OnEvent("Change", CommandTopicChanged)
	commandTopicCombo.Enabled := false

	commandListView := guiCmd.AddListView("vCommandList xm w320 r15 AltSubmit", ["Command", "Details"])
	commandListView.OnEvent("DoubleClick", OnCommandDoubleClick)

	commandEditor := guiCmd.AddEdit("vCommandEditor x+10 w320 r15 -Wrap WantReturn")
	commandEditor.SetFont("s9", "Consolas")

	commandClearBtn := guiCmd.AddButton("vCommandClearBtn xm w140", "Clear Script")
	commandClearBtn.OnEvent("Click", ClearCommandEditorScript)

	commandSaveBtn := guiCmd.AddButton("vCommandSaveBtn x+10 w140", "Save Script")
	commandSaveBtn.OnEvent("Click", SaveCommandEditorScript)

	commandLoadBtn := guiCmd.AddButton("vCommandLoadBtn x+10 w140", "Load Script")
	commandLoadBtn.OnEvent("Click", LoadCommandEditorScript)

	commandRunBtn := guiCmd.AddButton("vCommandRunBtn x+10 w170", "Run Script")
	commandRunBtn.SetFont("Bold")
	commandRunBtn.OnEvent("Click", RunCommandEditorScript)

	commandStatusLabel := guiCmd.AddText("vCommandStatus xm y+m w400", "")

	guiCmd.Show("x-10000 y-10000 w" defaultW " h" defaultH)
	guiCmd.GetClientPos(,, &clientW, &clientH)
	PositionCommandEditorControls(guiCmd, clientW, clientH)
	guiCmd.OnEvent("Size", CommandEditor_OnSize)
	guiCmd.Hide()

	ResetCommandEditorFilters()
	return guiCmd
}

CommandEditor_OnSize(thisGui, MinMax, Width, Height) {
	global commandResizePending
	if (MinMax = -1)
		return
	commandResizePending.Gui := thisGui
	commandResizePending.Width := Width
	commandResizePending.Height := Height
	commandResizePending.MinMax := MinMax
	SetTimer(CommandResizeDebounced, -120)
}

CommandResizeDebounced(*) {
	global commandResizePending, config
	targetGui := commandResizePending.Gui
	if !IsObject(targetGui)
		return
	if (commandResizePending.MinMax = -1)
		return
	w := commandResizePending.Width
	h := commandResizePending.Height
	minMax := commandResizePending.MinMax
	PositionCommandEditorControls(targetGui, w, h)
	; Save window state after repositioning
	config.CommandWindowW := w
	config.CommandWindowH := h
	WinGetPos(&x, &y, , , "ahk_id " targetGui.Hwnd)
	if (x >= 0 && y >= 0) {
		config.CommandWindowX := x
		config.CommandWindowY := y
	}
	config.CommandWindowMax := minMax == 1
	SaveConfig()
}

PositionCommandEditorControls(thisGui, Width, Height) {
	global commandCategoryLabel, commandCategoryCombo
	global commandSubcategoryLabel, commandSubcategoryCombo
	global commandTopicLabel, commandTopicCombo
	global commandListView, commandEditor
	global commandSaveBtn, commandLoadBtn, commandRunBtn
	global commandStatusLabel

	margin := 12
	rowSpacing := Floor(margin / 2)
	comboSpacing := 6
	groupSpacing := 24
	filterLabelWidth := 96
	categoryLabelWidth := 96
	subcategoryLabelWidth := 96
	topicLabelWidth := 96
	comboMinWidth := 140
	comboHeight := 26
	labelHeight := 20
	comboRowHeight := comboHeight + rowSpacing
	topY := margin
	availableWidth := Width - margin * 3  ; left pane, gap, right pane
	availableHeight := Height - topY - rowSpacing - 32 - rowSpacing  ; minus buttons

	; Left pane: filters stacked vertically, then list view below
	leftPaneWidth := Floor(availableWidth * 0.4)
	minLeftWidth := comboMinWidth + 100 + comboSpacing
	if (leftPaneWidth < minLeftWidth)
		leftPaneWidth := minLeftWidth
	if (leftPaneWidth > availableWidth - 300)  ; ensure right pane at least 300
		leftPaneWidth := availableWidth - 300
	rightPaneWidth := availableWidth - leftPaneWidth

	; Position combos vertically on left
	xLeft := margin
	yPos := topY
	commandSearchLabel.Move(xLeft, yPos + 6, filterLabelWidth, labelHeight)
	commandSearchEdit.Move(xLeft + filterLabelWidth + comboSpacing, yPos, leftPaneWidth - filterLabelWidth - comboSpacing, comboHeight)

	yPos += comboRowHeight
	commandCategoryLabel.Move(xLeft, yPos + 6, categoryLabelWidth, labelHeight)
	commandCategoryCombo.Move(xLeft + categoryLabelWidth + comboSpacing, yPos, leftPaneWidth - categoryLabelWidth - comboSpacing, comboHeight)

	yPos += comboRowHeight
	commandSubcategoryLabel.Move(xLeft, yPos + 6, subcategoryLabelWidth, labelHeight)
	commandSubcategoryCombo.Move(xLeft + subcategoryLabelWidth + comboSpacing, yPos, leftPaneWidth - subcategoryLabelWidth - comboSpacing, comboHeight)

	yPos += comboRowHeight
	commandTopicLabel.Move(xLeft, yPos + 6, topicLabelWidth, labelHeight)
	commandTopicCombo.Move(xLeft + topicLabelWidth + comboSpacing, yPos, leftPaneWidth - topicLabelWidth - comboSpacing, comboHeight)

	; List view below combos on left
	listTop := yPos + comboRowHeight
	listHeight := availableHeight - (listTop - topY)
	if (listHeight < 100)
		listHeight := 100
	commandListView.Move(xLeft, listTop, leftPaneWidth, listHeight)

	; Right pane: script editor full height
	xRight := margin + leftPaneWidth + margin
	commandEditor.Move(xRight, topY, rightPaneWidth, availableHeight)

	; Buttons at bottom
	buttonsTop := topY + availableHeight + rowSpacing
	buttonSpacing := 10
	runBtnX := Width - margin - 190
	commandRunBtn.Move(runBtnX, buttonsTop, 190, 32)
	loadBtnX := runBtnX - buttonSpacing - 140
	commandLoadBtn.Move(loadBtnX, buttonsTop, 140, 32)
	saveBtnX := loadBtnX - buttonSpacing - 140
	commandSaveBtn.Move(saveBtnX, buttonsTop, 140, 32)
	clearBtnX := saveBtnX - buttonSpacing - 140
	commandClearBtn.Move(clearBtnX, buttonsTop, 140, 32)

	; Status inline with buttons on left
	commandStatusLabel.Move(margin, buttonsTop + 6, clearBtnX - margin, 20)
}

PopulateCombo(ctrl, defaultLabel, values, enabled := true) {
	if !IsSet(ctrl)
		return
	ctrl.Delete()
	if (defaultLabel != "")
		ctrl.Add([defaultLabel])
	for value in values
		ctrl.Add([value])
	if (defaultLabel != "" || values.Length > 0)
		ctrl.Choose(1)
	ctrl.Enabled := enabled
	if (!enabled && defaultLabel != "")
		ctrl.Text := defaultLabel
}

ResetCommandEditorFilters() {
	global commandCatalog
	global commandCategoryCombo, commandSubcategoryCombo, commandTopicCombo
	global commandSearchEdit
	global commandFilterRefreshing
	if !IsSet(commandCategoryCombo)
		return
	commandFilterRefreshing := true
	if IsSet(commandSearchEdit)
		commandSearchEdit.Value := ""
	if (commandCatalog.Error != "" || commandCatalog.Commands.Length = 0) {
		PopulateCombo(commandCategoryCombo, "No categories", [], false)
		PopulateCombo(commandSubcategoryCombo, "No subcategories", [], false)
		PopulateCombo(commandTopicCombo, "No topics", [], false)
		commandFilterRefreshing := false
		displayed := RefreshCommandListView()
		UpdateCommandStatusLabel(displayed)
		return
	}
	categories := GetDistinctCategories()
	PopulateCombo(commandCategoryCombo, commandCategoryAllLabel, categories, true)
	PopulateCombo(commandSubcategoryCombo, commandSubcategoryAllLabel, [], false)
	PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
	commandFilterRefreshing := false
	CommandCategoryChanged(commandCategoryCombo)
}

GetSelectedCategory() {
	global commandCategoryCombo, commandCategoryAllLabel
	if !IsSet(commandCategoryCombo) || !commandCategoryCombo.Enabled
		return ""
	text := Trim(commandCategoryCombo.Text)
	if (text = "" || text = commandCategoryAllLabel)
		return ""
	return text
}

GetSelectedSubcategory() {
	global commandSubcategoryCombo, commandSubcategoryAllLabel
	if !IsSet(commandSubcategoryCombo) || !commandSubcategoryCombo.Enabled
		return ""
	text := Trim(commandSubcategoryCombo.Text)
	if (text = "" || text = commandSubcategoryAllLabel)
		return ""
	return text
}

GetSelectedTopic() {
	global commandTopicCombo, commandTopicAllLabel
	if !IsSet(commandTopicCombo) || !commandTopicCombo.Enabled
		return ""
	text := Trim(commandTopicCombo.Text)
	if (text = "" || text = commandTopicAllLabel)
		return ""
	return text
}

RefreshCommandListView() {
	global commandListView, commandRowToIndex
	global commandCatalog
	global commandSearchEdit
	if !IsSet(commandListView)
		return 0
	commandListView.Delete()
	commandRowToIndex.Clear()
	if (commandCatalog.Commands.Length = 0)
		return 0
	category := GetSelectedCategory()
	subcategory := GetSelectedSubcategory()
	topic := GetSelectedTopic()
	searchTerm := ""
	if IsSet(commandSearchEdit)
		searchTerm := StrLower(Trim(commandSearchEdit.Value))
	shown := 0
	for cmd in commandCatalog.Commands {
		if !MatchesCommandFilters(cmd, category, subcategory, topic)
			continue
		if (searchTerm != "" && !CommandMatchesSearch(cmd, searchTerm))
			continue
		details := BuildCommandDetails(cmd)
		row := commandListView.Add("", cmd.Command, details)
		commandRowToIndex[row] := cmd
		shown += 1
	}
	commandListView.ModifyCol()
	commandListView.ModifyCol(1, 240)
	commandListView.ModifyCol(2, 360)
	return shown
}

UpdateCommandStatusLabel(displayedCount := 0) {
	global commandStatusLabel, commandCatalog, commandCsvPath
	if !IsSet(commandStatusLabel)
		return
	if (commandCatalog.Error != "") {
		commandStatusLabel.Text := "Commands unavailable: " commandCatalog.Error
		return
	}
	total := commandCatalog.Commands.Length
	SplitPath(commandCsvPath, &csvName)
	commandStatusLabel.Text := Format("{1} of {2} commands shown ({3})", displayedCount, total, csvName)
}

CommandCategoryChanged(ctrl, *) {
	global commandFilterRefreshing
	global commandSubcategoryCombo, commandTopicCombo
	if commandFilterRefreshing
		return
	selected := Trim(ctrl.Text)
	commandFilterRefreshing := true
	if (selected = "" || selected = commandCategoryAllLabel) {
		PopulateCombo(commandSubcategoryCombo, commandSubcategoryAllLabel, [], false)
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
		commandFilterRefreshing := false
		displayed := RefreshCommandListView()
		UpdateCommandStatusLabel(displayed)
		return
	}
	subs := GetDistinctSubcategories(selected)
	if (subs.Length = 0) {
		PopulateCombo(commandSubcategoryCombo, commandSubcategoryAllLabel, [], false)
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
	} else {
		PopulateCombo(commandSubcategoryCombo, commandSubcategoryAllLabel, subs, true)
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
	}
	commandFilterRefreshing := false
	displayed := RefreshCommandListView()
	UpdateCommandStatusLabel(displayed)
}

CommandSubcategoryChanged(ctrl, *) {
	global commandFilterRefreshing
	global commandTopicCombo
	if commandFilterRefreshing
		return
	if !ctrl.Enabled {
		displayed := RefreshCommandListView()
		UpdateCommandStatusLabel(displayed)
		return
	}
	selected := Trim(ctrl.Text)
	if (selected = "" || selected = commandSubcategoryAllLabel) {
		commandFilterRefreshing := true
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
		commandFilterRefreshing := false
		displayed := RefreshCommandListView()
		UpdateCommandStatusLabel(displayed)
		return
	}
	category := GetSelectedCategory()
	topics := GetDistinctTopics(category, selected)
	commandFilterRefreshing := true
	if (topics.Length = 0)
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, [], false)
	else
		PopulateCombo(commandTopicCombo, commandTopicAllLabel, topics, true)
	commandFilterRefreshing := false
	displayed := RefreshCommandListView()
	UpdateCommandStatusLabel(displayed)
}

CommandTopicChanged(ctrl, *) {
	if !ctrl.Enabled
		return
	displayed := RefreshCommandListView()
	UpdateCommandStatusLabel(displayed)
}

CommandSearchChanged(ctrl, *) {
	if !IsSet(ctrl)
		return
	displayed := RefreshCommandListView()
	UpdateCommandStatusLabel(displayed)
}

OnCommandDoubleClick(ctrl, rowNumber) {
	global commandRowToIndex
	if (rowNumber <= 0)
		return
	if !commandRowToIndex.Has(rowNumber)
		return
	cmd := commandRowToIndex[rowNumber]
	AddCommandToEditor(cmd.Command)
}

AddCommandToEditor(commandText) {
	global commandEditor
	if !IsSet(commandEditor)
		return
	if (commandText = "")
		return
	hwnd := commandEditor.Hwnd
	ControlSend(commandText "{Enter}", , "ahk_id " hwnd)
}

SaveCommandEditorScript(*) {
	global commandEditor, userScriptsFolder
	if !IsSet(commandEditor)
		return
	if !DirExist(userScriptsFolder)
		DirCreate(userScriptsFolder)
	path := FileSelect("S16", userScriptsFolder, "Save command script", "Text Documents (*.txt)")
	if (path = "")
		return
	if !RegExMatch(StrLower(path), "\.txt$")
		path .= ".txt"
	try {
		file := FileOpen(path, "w", "UTF-8")
		file.Write(commandEditor.Value)
		file.Close()
		ShowFollowTooltip("Script saved to`n" path)
	} catch as e {
		MsgBox("Failed to save script:`n" e.Message)
	}
}

ClearCommandEditorScript(*) {
	global commandEditor
	if !IsSet(commandEditor)
		return
	commandEditor.Value := ""
}

LoadCommandEditorScript(*) {
	global commandEditor, userScriptsFolder
	if !IsSet(commandEditor)
		return
	path := FileSelect("1", userScriptsFolder, "Load command script", "Text Documents (*.txt)")
	if (path = "")
		return
	try
		content := FileRead(path, "UTF-8")
	catch as e {
		MsgBox("Failed to load script:`n" e.Message)
		return
	}
	commandEditor.Value := content
	ShowFollowTooltip("Loaded script from`n" path)
}

RunCommandEditorScript(*) {
    global commandEditor, commandDelayMs
    if !IsSet(commandEditor)
        return
    commands := CollectScriptCommands(commandEditor.Value)
    if (commands.Length = 0) {
        MsgBox("The script is empty after removing comments and blank lines.")
        return
    }
    if !FocusFtlWindow()
        return
    delayMs := GetCommandDelayMs()
    commandDelayMs := Max(100,delayMs)
    Sleep(150)
    for cmd in commands {
        SendInput("{Text}" cmd)
        Sleep(commandDelayMs)
        SendInput("{Enter}")
        Sleep(commandDelayMs)
        SendInput("\")
        Sleep(commandDelayMs)
    }
    ShowFollowTooltip(Format("Sent {1} command{2} to FTL", commands.Length, commands.Length = 1 ? "" : "s"))
}

CollectScriptCommands(text) {
	lines := []
	if (text = "")
		return lines
	clean := StrReplace(text, "`r")
	for line in StrSplit(clean, "`n") {
		trimmed := Trim(line)
		if (trimmed = "")
			continue
		if (SubStr(trimmed, 1, 1) = ";")
			continue
		if (SubStr(trimmed, 1, 1) = "#")
			continue
		if (SubStr(trimmed, 1, 2) = "//")
			continue
		lines.Push(trimmed)
	}
	return lines
}

FocusFtlWindow() {
	winTitle := "ahk_exe FTLGame.exe"
	if !WinExist(winTitle) {
		MsgBox("FTL is not running or its window could not be found.")
		return false
	}
	WinActivate(winTitle)
	if !WinWaitActive(winTitle, , 2) {
		MsgBox("Unable to focus the FTL window.")
		return false
	}
	return true
}

GetCommandDelayMs() {
	global config
	return Max(0, Round(config.CommandDelaySeconds * 1000))
}

ReloadCommandCatalog() {
	global commandCsvPath, commandCatalog, commandCatalogError
	commandCatalog := LoadCommandCatalog(commandCsvPath)
	commandCatalogError := commandCatalog.Error
	if IsSet(commandRowToIndex)
		commandRowToIndex.Clear()
	if IsSet(commandCategoryCombo)
		ResetCommandEditorFilters()
}

LoadCommandCatalog(path) {
	catalog := {Commands: [], Error: "", SourcePath: path}
	if !FileExist(path) {
		catalog.Error := "File not found: " path
		return catalog
	}
	try
		raw := FileRead(path, "UTF-8")
	catch as e {
		catalog.Error := "Could not read commands file: " e.Message
		return catalog
	}
	raw := StrReplace(raw, "`r")
	lines := StrSplit(raw, "`n")
	if (lines.Length = 0) {
		catalog.Error := "Commands file is empty."
		return catalog
	}
	headers := ParseCsvLine(lines[1])
	headerMap := Map()
	for idx, header in headers {
		key := NormalizeCsvHeader(header)
		if (key = "")
			continue
		headerMap[key] := idx
	}
	ApplyHeaderSynonyms(headerMap)
	if !headerMap.Has("command") {
		catalog.Error := "Commands file is missing a 'Command' column."
		return catalog
	}
	rowNumber := 0
	for line in lines {
		rowNumber := A_Index
		if (rowNumber = 1)
			continue
		trimmed := Trim(line)
		if (trimmed = "")
			continue
		fields := ParseCsvLine(line)
		commandText := GetCommandField(fields, headerMap, "command")
		if (commandText = "")
			continue
		cmd := {
			Command: commandText
			, Category: GetCommandField(fields, headerMap, "category")
			, Subcategory: GetCommandField(fields, headerMap, "subcategory")
			, Topic: GetCommandField(fields, headerMap, "subcategory2")
			, Description: GetCommandField(fields, headerMap, "description")
			, SourceLine: rowNumber
		}
		catalog.Commands.Push(cmd)
	}
	return catalog
}

ParseCsvLine(line) {
	values := []
	current := ""
	inQuotes := false
	len := StrLen(line)
	i := 1
	while (i <= len) {
		ch := SubStr(line, i, 1)
		if (ch = '"') {
			next := (i < len) ? SubStr(line, i + 1, 1) : ""
			if (inQuotes && next = '"') {
				current .= '"'
				i += 1
			} else {
				inQuotes := !inQuotes
			}
		} else if (ch = "," && !inQuotes) {
			values.Push(current)
			current := ""
		} else {
			current .= ch
		}
		i += 1
	}
	values.Push(current)
	for idx, item in values
		values[idx] := Trim(item, " `t")
	return values
}

NormalizeCsvHeader(name) {
	return StrLower(RegExReplace(name, "[^a-zA-Z0-9]", ""))
}

ApplyHeaderSynonyms(headerMap) {
	synonyms := [
		{Key: "category", Aliases: ["cat", "categoryname"]}
		, {Key: "subcategory", Aliases: ["subcat", "subcategory1", "subcategoryone"]}
		, {Key: "subcategory2", Aliases: ["topic", "subsubcategory", "topicname", "type"]}
		, {Key: "description", Aliases: ["desc", "details", "info", "notes"]}
		, {Key: "command", Aliases: ["cmd", "text", "commandtext"]}
	]
	for entry in synonyms {
		key := entry.Key
		if headerMap.Has(key)
			continue
		for alias in entry.Aliases {
			if headerMap.Has(alias) {
				headerMap[key] := headerMap[alias]
				break
			}
		}
	}
}

GetCommandField(fields, headerMap, key) {
	if !headerMap.Has(key)
		return ""
	idx := headerMap[key]
	if (idx < 1 || idx > fields.Length)
		return ""
	return Trim(fields[idx], " `t")
}

GetDistinctCategories() {
	global commandCatalog
	seen := Map()
	results := []
	for cmd in commandCatalog.Commands {
		val := Trim(cmd.Category)
		if (val = "")
			continue
		key := StrLower(val)
		if !seen.Has(key) {
			seen[key] := true
			results.Push(val)
		}
	}
	SortArray(results, (a, b) => StrCompare(a, b))
	return results
}

GetDistinctSubcategories(category) {
	global commandCatalog
	seen := Map()
	results := []
	for cmd in commandCatalog.Commands {
		if (category != "" && !StringEquals(cmd.Category, category))
			continue
		val := Trim(cmd.Subcategory)
		if (val = "")
			continue
		key := StrLower(val)
		if !seen.Has(key) {
			seen[key] := true
			results.Push(val)
		}
	}
	SortArray(results, (a, b) => StrCompare(a, b))
	return results
}

GetDistinctTopics(category, subcategory) {
	global commandCatalog
	seen := Map()
	results := []
	for cmd in commandCatalog.Commands {
		if (category != "" && !StringEquals(cmd.Category, category))
			continue
		if (subcategory != "" && !StringEquals(cmd.Subcategory, subcategory))
			continue
		val := Trim(cmd.Topic)
		if (val = "")
			continue
		key := StrLower(val)
		if !seen.Has(key) {
			seen[key] := true
			results.Push(val)
		}
	}
	SortArray(results, (a, b) => StrCompare(a, b))
	return results
}

MatchesCommandFilters(cmd, category, subcategory, topic) {
	if (category != "" && !StringEquals(cmd.Category, category))
		return false
	if (subcategory != "" && !StringEquals(cmd.Subcategory, subcategory))
		return false
	if (topic != "" && !StringEquals(cmd.Topic, topic))
		return false
	return true
}

BuildCommandDetails(cmd) {
	parts := []
	if (Trim(cmd.Subcategory) != "")
		parts.Push(cmd.Subcategory)
	if (Trim(cmd.Topic) != "")
		parts.Push(cmd.Topic)
	if (Trim(cmd.Description) != "")
		parts.Push(cmd.Description)
	return JoinNonEmpty(parts)
}

CommandMatchesSearch(cmd, term) {
	if (term = "")
		return true
	haystack := StrLower(cmd.Command " " cmd.Category " " cmd.Subcategory " " cmd.Topic " " cmd.Description)
	return InStr(haystack, term) > 0
}

JoinNonEmpty(parts, separator := " — ") {
	result := ""
	for part in parts {
		if (part = "")
			continue
		if (result = "")
			result := part
		else
			result .= separator part
	}
	return result
}


GetPreferredIconSource() {
	global config, defaultGameExe, iconFile
	if FileExist(iconFile)
		return {Path: iconFile, Index: 1}
	if (config.GamePath != "" && FileExist(config.GamePath))
		return {Path: config.GamePath, Index: 1}
	if FileExist(defaultGameExe)
		return {Path: defaultGameExe, Index: 1}
	return {Path: "shell32.dll", Index: 4}
}

ApplyIconSource(iconSource) {
	TraySetIcon(iconSource.Path, iconSource.Index)
	if IsSet(mainGui) {
		hIcon := LoadPicture(iconSource.Path, "Icon" iconSource.Index " w32 h32")
		if hIcon
			SendMessage(0x0080, 1, hIcon, mainGui.Hwnd)  ; ICON_BIG
	}
}

LoadConfig() {
	global configFile, defaultGameExe
	cfg := {GamePath: "", SaveFolder: "", AutoLaunch: false, WindowX: -1, WindowY: -1, WindowW: -1, WindowH: -1, WindowMax: false, CheckIntervalSeconds: 25, MinimizeGUItoSystrayOnStartup: false, RestoreAllAchievementsAndProgress: false, CommandDelaySeconds: 0.5, CommandWindowX: -1, CommandWindowY: -1, CommandWindowW: -1, CommandWindowH: -1, CommandWindowMax: false}
	if FileExist(configFile) {
		try {
			cfg.GamePath := IniRead(configFile, "Settings", "GamePath", "")
			cfg.SaveFolder := IniRead(configFile, "Settings", "SaveFolder", "")
			autoVal := IniRead(configFile, "Settings", "AutoLaunch", "0")
			cfg.AutoLaunch := autoVal = "1"
			minimiseVal := IniRead(configFile, "Settings", "MinimizeGUItoSystrayOnStartup", "0")
			cfg.MinimizeGUItoSystrayOnStartup := minimiseVal = "1"
			checkVal := IniRead(configFile, "Settings", "CheckIntervalSeconds", "25")
			cfg.CheckIntervalSeconds := Abs(Round(checkVal))
			restoreAllVal := IniRead(configFile, "Settings", "RestoreAllAchievementsAndProgress", "0")
			cfg.RestoreAllAchievementsAndProgress := restoreAllVal = "1"
			cfg.WindowX := IniRead(configFile, "Window", "X", -1)
			cfg.WindowY := IniRead(configFile, "Window", "Y", -1)
			cfg.WindowW := IniRead(configFile, "Window", "W", -1)
			cfg.WindowH := IniRead(configFile, "Window", "H", -1)
			maxVal := IniRead(configFile, "Window", "Max", "0")
			cfg.WindowMax := maxVal = "1"
			delayVal := IniRead(configFile, "Settings", "CommandDelaySeconds", "0.5")
			delayNum := delayVal + 0
			if (delayNum <= 0)
				delayNum := 0.5
			cfg.CommandDelaySeconds := delayNum
			cfg.CommandWindowX := IniRead(configFile, "CommandWindow", "X", -1)
			cfg.CommandWindowY := IniRead(configFile, "CommandWindow", "Y", -1)
			cfg.CommandWindowW := IniRead(configFile, "CommandWindow", "W", -1)
			cfg.CommandWindowH := IniRead(configFile, "CommandWindow", "H", -1)
			cmdMaxVal := IniRead(configFile, "CommandWindow", "Max", "0")
			cfg.CommandWindowMax := cmdMaxVal = "1"
		}
	}
	if (cfg.GamePath = "" && FileExist(defaultGameExe))
		cfg.GamePath := defaultGameExe
	if (cfg.SaveFolder = "")
		cfg.SaveFolder := A_MyDocuments "\My Games\FasterThanLight\"
	if (cfg.CheckIntervalSeconds < 1)
		cfg.CheckIntervalSeconds := 25
	if (cfg.CommandDelaySeconds < 0)
		cfg.CommandDelaySeconds := 0.5
	return cfg
}

SaveConfig() {
	global config, configFile
	try {
		IniWrite(config.GamePath, configFile, "Settings", "GamePath")
		IniWrite(config.SaveFolder, configFile, "Settings", "SaveFolder")
		IniWrite(config.AutoLaunch ? "1" : "0", configFile, "Settings", "AutoLaunch")
		IniWrite(config.MinimizeGUItoSystrayOnStartup ? "1" : "0", configFile, "Settings", "MinimizeGUItoSystrayOnStartup")
		IniWrite(config.CheckIntervalSeconds, configFile, "Settings", "CheckIntervalSeconds")
		IniWrite(config.RestoreAllAchievementsAndProgress ? "1" : "0", configFile, "Settings", "RestoreAllAchievementsAndProgress")
		IniWrite(config.CommandDelaySeconds, configFile, "Settings", "CommandDelaySeconds")
		IniWrite(config.WindowX, configFile, "Window", "X")
		IniWrite(config.WindowY, configFile, "Window", "Y")
		IniWrite(config.WindowW, configFile, "Window", "W")
		IniWrite(config.WindowH, configFile, "Window", "H")
		IniWrite(config.WindowMax ? "1" : "0", configFile, "Window", "Max")
		IniWrite(config.CommandWindowX, configFile, "CommandWindow", "X")
		IniWrite(config.CommandWindowY, configFile, "CommandWindow", "Y")
		IniWrite(config.CommandWindowW, configFile, "CommandWindow", "W")
		IniWrite(config.CommandWindowH, configFile, "CommandWindow", "H")
		IniWrite(config.CommandWindowMax ? "1" : "0", configFile, "CommandWindow", "Max")
	}
}

ParseSaveFile(path) {
	info := {ShipName: "", ShipClass: "", Strings: []}
	if !FileExist(path)
		return info
	try
		rawData := FileRead(path, "RAW")
	catch
		return info
	if !IsObject(rawData)
		return info
	totalSize := rawData.Size
	ptr := rawData.Ptr
	stringRecords := extractPrintableStrings(ptr, totalSize, 3)
	info.Strings := stringRecords
	for record in stringRecords {
		s := record["value"]
		if (info.ShipName = "" && StrLen(s) >= 3 && RegExMatch(s, "^[A-Za-z0-9 _-]+$") && RegExMatch(s, "[a-z]")) {
			info.ShipName := s
			continue
		}
		if (info.ShipClass = "" && RegExMatch(s, "^[A-Z0-9_]*SHIP[A-Z0-9_]*$")) {
			info.ShipClass := s
			continue
		}
		if (info.ShipName != "" && info.ShipClass != "")
			break
	}
	return info
}

extractPrintableStrings(ptr, totalSize, minLen := 1) {
	list := []
	current := ""
	start := -1
	loop totalSize {
		idx := A_Index - 1
		b := NumGet(ptr + idx, 0, "UChar")
		if (b >= 32 && b <= 126) {
			if (start = -1)
				start := idx
			current .= Chr(b)
		} else {
			if (current != "" && StrLen(current) >= minLen)
				list.Push(Map("value", current, "offset", start, "length", StrLen(current)))
			current := ""
			start := -1
		}
	}
	if (current != "" && StrLen(current) >= minLen)
		list.Push(Map("value", current, "offset", start, "length", StrLen(current)))
	return list
}

SanitizeFilePart(str) {
	if str = ""
		return "Unknown"
	sanitized := RegExReplace(str, "[\\/:*?`"<>|]", "_")
	sanitized := Trim(sanitized)
	if sanitized = ""
		sanitized := "Unknown"
	return sanitized
}

FormatShipTag(tag) {
	if tag = ""
		return "Unknown Ship"
	return StrReplace(tag, "_", " ")
}

GetEditSelection(ctrl, &start, &end) {
	; Provide safe defaults
	start := 0
	end := 0
	if !IsObject(ctrl)
		return
	; Try to get HWND from control object
	hwnd := 0
	try
		hwnd := ctrl.Hwnd
	catch
		hwnd := 0
	if !hwnd
		return
	; EM_GETSEL message (0x00B0) fills start and end when passed pointers.
	; SendMessage can accept the addresses of variables; use & to pass address.
	; start and end are ByRef parameters, so passing their addresses lets the control fill the caller's variables.
	try {
		SendMessage(0x00B0, &start, &end, "ahk_id " hwnd)
		; Ensure numeric values
		start := start + 0
		end := end + 0
	} catch {
		; Fall back to zeros on error
		start := 0
		end := 0
	}
}

StringEquals(a, b) {
	return StrLower(a) = StrLower(b)
}

