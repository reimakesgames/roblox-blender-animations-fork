-- Rbx Animations plugin, export/import between Blender and Roblox
-- Written by Den_S/@DennisRBLX

local KSP = game:GetService("KeyframeSequenceProvider")
local RS = game:GetService("RunService")
local Rig = require(script.Rig)
local BaseXX = require(script.BaseXX)
local DeflateLua = require(script.DeflateLua)

local activeRigModel = nil
local activeAnimator = nil
local activeRig = nil
local activeAnimTrack = nil
local active = false

local gui = script.PluginGui:Clone()
gui.Archivable = false
local guiHintLabel = gui.HintMessage
local guiHintLabelShowTime = 0
local metaParts
local importScript
local rigSelectionEvent
local activateButton
local updateAnimationOptionsGui
local keyframeNameTemplate = script.KeyframeNameTemplate
keyframeNameTemplate.Parent = nil
local keyframeNamesContainer
local addRigLoadingMessage
local clearRigLoadingMessages
local boneWeightsList

local CollapsibleTitledSection = require(script.Parent.StudioWidgets.CollapsibleTitledSection)
local CustomTextButton = require(script.Parent.StudioWidgets.CustomTextButton)
local VerticallyScalingListFrame = require(script.Parent.StudioWidgets.VerticallyScalingListFrame)
local LabeledCheckbox = require(script.Parent.StudioWidgets.LabeledCheckbox)
local GuiUtilities = require(script.Parent.StudioWidgets.GuiUtilities)

local dockGui = plugin:CreateDockWidgetPluginGui(
	"RbxAnimations_Dock",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, false, true, 400, 600)
)
dockGui.Title = "Blender Animations"
local dockGuiPreviousEnabled = false

local scrollingFrame = Instance.new("ScrollingFrame")
scrollingFrame.Parent = dockGui
scrollingFrame.BorderSizePixel = 0
scrollingFrame.BackgroundColor3 = Color3.new(1, 1, 1)
scrollingFrame.BottomImage = "rbxasset://textures/ui/scrollbuttonDown.png"
scrollingFrame.MidImage = "rbxasset://textures/ui/scrollbar.png"
scrollingFrame.TopImage = "rbxasset://textures/ui/scrollbuttonUp.png"
scrollingFrame.Size = UDim2.new(1, 0, 1, 0)
scrollingFrame.ScrollBarThickness = 16

local scrollingFramePadding = Instance.new("UIPadding")
scrollingFramePadding.PaddingRight = UDim.new(0, 16)
scrollingFramePadding.Parent = scrollingFrame

local mainList = VerticallyScalingListFrame.new("Root")
mainList:GetFrame().Parent = scrollingFrame
mainList:GetFrame():GetPropertyChangedSignal("Size"):connect(function()
	scrollingFrame.CanvasSize = mainList:GetFrame().Size
	scrollingFramePadding.PaddingRight =
		UDim.new(0, scrollingFrame.AbsoluteWindowSize.Y < scrollingFrame.CanvasSize.Y.Offset and 16 or 0)
end)

scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):connect(function()
	scrollingFramePadding.PaddingRight =
		UDim.new(0, scrollingFrame.AbsoluteWindowSize.Y < scrollingFrame.CanvasSize.Y.Offset and 16 or 0)
end)

local buttonSize = UDim2.new(1, 0, 0, 30)
local padding = 5

local function clearMetaParts()
	if metaParts then
		for _, metaPart in pairs(metaParts) do
			metaPart:Destroy()
		end
		metaParts = nil
	end
end

local function stopAnimation()
	if activeAnimTrack then
		activeAnimTrack:Stop(0.001)
		activeAnimTrack:Destroy()
		activeAnimTrack = nil
	end
end

local function showHint(text, ...)
	local showTime = tick()
	guiHintLabel.Visible = true
	guiHintLabel.Text = text:format(...)
	guiHintLabelShowTime = showTime

	spawn(function()
		wait(2)
		if guiHintLabelShowTime == showTime then
			guiHintLabel.Visible = false
		end
	end)
end

local function loadRig()
	stopAnimation()

	local kfs = activeRig:ToRobloxAnimation()
	local asset = KSP:RegisterKeyframeSequence(kfs)

	local animation = Instance.new("Animation")
	animation.AnimationId = asset

	activeAnimTrack = activeAnimator:LoadAnimation(animation)
	activeAnimTrack.KeyframeReached:connect(function(kfName)
		print(('Playing animation reached keyframe "%s"'):format(kfName))
	end)
	activeAnimTrack:Play(0)

	--[[for _, kf in pairs(kfs:GetChildren()) do
		local tr = kf.HumanoidRootPart.Ax1.CFrame;
		activeRigModel.Axle1.PrimaryPart.CFrame = tr;
		game["Run Service"].RenderStepped:wait();
		game["Run Service"].RenderStepped:wait();
	end]]
end

local function uploadAnimation()
	-- should be cleaned up at some point, but no proper way to detect that?
	local kfs = activeRig:ToRobloxAnimation()
	kfs.Parent = game.Workspace
	game.Selection:Set({ kfs })
	plugin:SaveSelectedToRoblox()
end

-- reencodes a joint s.t. it can be serialized to json properly
local function reencodeJointMetadata(rigNode, partEncodeMap)
	-- round transform matrices (compresses data)
	for _, transform in pairs({ "transform", "jointtransform0", "jointtransform1" }) do
		if rigNode[transform] then
			for i = 1, #rigNode[transform] do
				rigNode[transform][i] = math.floor(rigNode[transform][i] * 10000 + 0.5) / 10000
			end
		end
	end

	rigNode.pname = partEncodeMap[rigNode.inst]
	rigNode.inst = nil
	local realAux = rigNode.aux
	rigNode.aux = {} -- named aux

	for _, aux in pairs(realAux) do
		rigNode.aux[#rigNode.aux + 1] = partEncodeMap[aux]
	end

	for _, child in pairs(rigNode.children) do
		reencodeJointMetadata(child, partEncodeMap)
	end
end

-- serializes the neutral rig state to a table that can be serialized to json safely
-- normalized the model part names as well
local function generateMetadata(rigModelToExport)
	assert(activeRig)

	local partNames = {}
	local partEncodeMap = {}

	local usedModelNames = {}
	local partCount = 0

	local originalDescendants = activeRig.model:GetDescendants()
	for descIdx, desc in ipairs(rigModelToExport:GetDescendants()) do
		if desc:IsA("BasePart") then
			partCount = partCount + 1

			-- uniqify the name
			local baseName = desc.Name
			local retryCount = 0
			while usedModelNames[desc.Name] do
				retryCount = retryCount + 1
				desc.Name = baseName .. retryCount
			end

			usedModelNames[desc.Name] = true
			partNames[#partNames + 1] = desc.Name
			partEncodeMap[originalDescendants[descIdx]] = desc.Name
			desc.Name = rigModelToExport.Name .. partCount
		elseif desc:IsA("Humanoid") then
			-- Get rid of all humanoids so that they do not affect naming...
			desc:Destroy()
		end
	end

	local encodedRig = activeRig:EncodeRig()
	reencodeJointMetadata(encodedRig, partEncodeMap)

	return { rigName = activeRig.model.Name, parts = partNames, rig = encodedRig }
end

-- serialized rig, triggers export dialog for the rig
local function exportRig()
	assert(activeRig)

	clearMetaParts()

	-- Clone the rig model, then rename all baseparts to the rig name (let the export flow handle unique indices)
	local rigModelToExport = activeRigModel:Clone()
	rigModelToExport.Parent = activeRigModel.Parent
	rigModelToExport.Archivable = false

	metaParts = { rigModelToExport }

	local meta = generateMetadata(rigModelToExport)

	-- store encoded metadata in a bunch of auxiliary part names
	local metaEncodedJson = game.HttpService:JSONEncode(meta)
	local metaEncoded = BaseXX.to_base32(metaEncodedJson):gsub("=", "0")
	local idx = 1
	local segLen = 45
	for begin = 1, #metaEncoded + 1, segLen do
		local metaPart = Instance.new("Part", game.Workspace)
		metaPart.Name = ("meta%dq1%sq1"):format(idx, metaEncoded:sub(begin, begin + segLen - 1))
		metaParts[#metaParts + 1] = metaPart
		metaPart.Anchored = true
		metaPart.Archivable = false
		idx = idx + 1
	end
	game.Selection:Set(metaParts)
	PluginManager():ExportSelection() -- hah deprecated
end

-- given encoded rig data, decodes it and loads the animation
local function loadAnim(data)
	local animDataEncoded = BaseXX.from_base64(data)
	local unpackSeq = {}
	local unpackSeqIdx = 1
	DeflateLua.inflate_zlib({
		disable_crc = true,
		input = animDataEncoded,
		output = function(streamByte)
			unpackSeq[unpackSeqIdx] = string.char(streamByte)
			unpackSeqIdx = unpackSeqIdx + 1
		end,
	})
	local animDataEncodedJson = table.concat(unpackSeq, "")
	local animData = game.HttpService:JSONDecode(animDataEncodedJson)

	activeRig:LoadAnimation(animData)
end

local function previewAnimationAsRobloxAnim()
	loadRig()
end

-- TODO
local function recollectKeyframeNames()
	local pos = keyframeNameTemplate.Position
	local kfdefs = {}
	for _, kfnui in pairs(keyframeNamesContainer:GetChildren()) do
		if kfnui.Name == "KeyframeNameTemplate" then
			kfnui.Position = pos
			pos = pos + UDim2.new(0, 0, 0, 35)

			local t = tonumber(kfnui.KfTime.Text)
			-- anything with this t already exists?
			for _, kfdef in pairs(kfdefs) do
				if kfdef.t == t then
					t = nil
					break
				end
			end
			-- convert
			if t then
				kfdefs[#kfdefs + 1] = { t = t, name = kfnui.KfName.Text }
				kfnui.KfTime.BackgroundColor3 = keyframeNameTemplate.KfTime.BackgroundColor3
			else
				kfnui.KfTime.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
			end
		end
	end
	table.sort(kfdefs, function(a, b)
		return a.t < b.t
	end)
	activeRig.keyframeNames = kfdefs
	loadRig()
end

-- TODO
local function clearKeyframeNames()
	for _, kfnui in pairs(keyframeNamesContainer:GetChildren()) do
		if kfnui.Name == "KeyframeNameTemplate" then
			kfnui:Destroy()
		end
	end
	recollectKeyframeNames()
end

-- loads a rig model
local function setRig(rigModel)
	assert(rigModel)

	if not rigModel.PrimaryPart then
		showHint("Rig has no PrimaryPart set.")
		return false
	end

	if not rigModel.PrimaryPart.Anchored then
		showHint("Rig PrimaryPart must be anchored when creating animations.")
		return false
	end

	activeRigModel = rigModel
	activeAnimator = rigModel:FindFirstChildOfClass("Humanoid") or rigModel:FindFirstChildOfClass("AnimationController")
	if not activeAnimator then
		showHint("Invalid rig, no Humanoid or AnimationController exists.")
		activeRigModel = nil
		return false
	end

	-- We can load it, but check for potential issues...
	clearRigLoadingMessages()
	local warnCount = 0

	if settings()["Rendering"].ExportMergeByMaterial then
		addRigLoadingMessage("Warning: ExportMergeByMaterial should be disabled!")
		addRigLoadingMessage("  note: Disable under Studio settings -> Rendering")
		warnCount = warnCount + 1
	end

	if rigModel.Name:match("[^a-zA-Z0-9]") then
		addRigLoadingMessage("Warning: Model name should only contain a-z A-Z 0-9 symbols!")
		warnCount = warnCount + 1
	end

	for _, inst in pairs(rigModel:GetDescendants()) do
		if inst:IsA("Decal") then
			addRigLoadingMessage("Warning: Decal instances sometimes cause issues during export!")
			addRigLoadingMessage(("  note: at %s"):format(inst:GetFullName()))
			warnCount = warnCount + 1
		end
		if inst:IsA("Texture") then
			addRigLoadingMessage("Warning: Texture instances sometimes cause issues during export!")
			addRigLoadingMessage(("  note: at %s"):format(inst:GetFullName()))
			warnCount = warnCount + 1
		end
	end

	addRigLoadingMessage(("(%d warnings)"):format(warnCount))

	activeRig = Rig.new(rigModel)
	showHint("Set active rig to %s.", rigModel.Name)
	updateAnimationOptionsGui()
	return true
end

local function loadAnimDataFromText(text)
	local ok, err = pcall(loadAnim, text)
	if ok then
		loadRig()
		showHint("Animation loaded.")
	else
		showHint("Failed to load animation: %s.", tostring(err))
	end
end

local function deactivate()
	dockGui.Enabled = false
	stopAnimation()
	game.Selection:Set({})
	wait()
	RS:Stop()
	wait()
	clearMetaParts()
	active = false
	activateButton:SetActive(false)
	gui.Parent = nil
	if rigSelectionEvent then
		rigSelectionEvent:disconnect()
		rigSelectionEvent = nil
	end
end

-- TODO
local function createUI()
	-- Rig loading warnings
	do
		local panelLoad = CollapsibleTitledSection.new("Core", "Rig loading warnings", true, true, false)
		mainList:AddChild(panelLoad:GetSectionFrame())

		local loadList = VerticallyScalingListFrame.new("Core")
		loadList._uiListLayout.Padding = UDim.new(0, padding)
		loadList:GetFrame().Parent = panelLoad:GetContentsFrame()

		local corePadding = Instance.new("UIPadding", loadList:GetFrame())
		corePadding.PaddingBottom = UDim.new(0, padding)
		corePadding.PaddingLeft = UDim.new(0, padding)
		corePadding.PaddingRight = UDim.new(0, padding)
		corePadding.PaddingTop = UDim.new(0, padding)

		local shownLabels = {}

		addRigLoadingMessage = function(message)
			local label = GuiUtilities.MakeStandardPropertyLabel(message)
			label.Position = UDim2.new(0, 0, 0, 0)
			label.Size = UDim2.new(1, 0, 0, 20)
			label.AnchorPoint = Vector2.new()
			loadList:AddChild(label)

			shownLabels[label] = true
		end

		clearRigLoadingMessages = function(message)
			for label in pairs(shownLabels) do
				label:Destroy()
			end
			shownLabels = {}
		end
	end

	-- Export/Import
	do
		local panelCore = CollapsibleTitledSection.new("Core", "Export/Import", true, true, false)
		mainList:AddChild(panelCore:GetSectionFrame())

		local coreList = VerticallyScalingListFrame.new("Core")
		coreList._uiListLayout.Padding = UDim.new(0, padding)
		coreList:GetFrame().Parent = panelCore:GetContentsFrame()

		local corePadding = Instance.new("UIPadding", coreList:GetFrame())
		corePadding.PaddingBottom = UDim.new(0, padding)
		corePadding.PaddingLeft = UDim.new(0, padding)
		corePadding.PaddingRight = UDim.new(0, padding)
		corePadding.PaddingTop = UDim.new(0, padding)

		local exportButton = CustomTextButton.new("Export", "Export rig")
		exportButton:getButton().Size = buttonSize
		coreList:AddChild(exportButton:getButton())

		exportButton:getButton().MouseButton1Click:connect(function()
			exportRig()
			showHint("Done.")
		end)

		local cleanButton = CustomTextButton.new("Clean", "Clean meta parts")
		cleanButton:getButton().Size = buttonSize
		coreList:AddChild(cleanButton:getButton())

		cleanButton:getButton().MouseButton1Click:connect(function()
			clearMetaParts()
			showHint("Done.")
		end)

		local importButton = CustomTextButton.new("Import", "Import animation")
		importButton:getButton().Size = buttonSize
		coreList:AddChild(importButton:getButton())

		local importScriptText = "Paste the animation data below this line"
		importButton:getButton().MouseButton1Click:connect(function()
			clearMetaParts()
			if importScript then
				importScript:Destroy()
			end
			importScript = Instance.new("Script", game.Workspace)
			importScript.Archivable = false
			importScript.Source = "-- " .. importScriptText .. "\n"
			plugin:OpenScript(importScript, 2)
			importScript.Changed:connect(function(prop)
				if prop == "Source" then
					local animData =
						select(3, string.find(importScript.Source, "^%-%- " .. importScriptText .. "\n(.*)$"))
					importScript:Destroy()
					importScript = nil
					loadAnimDataFromText(animData)
				end
			end)
		end)
	end

	-- Animation options
	do
		local panelAnim = CollapsibleTitledSection.new("Loaded", "Loaded animation", true, true, false)
		mainList:AddChild(panelAnim:GetSectionFrame())

		local animList = VerticallyScalingListFrame.new("Core")
		animList._uiListLayout.Padding = UDim.new(0, padding)
		animList:GetFrame().Parent = panelAnim:GetContentsFrame()

		local corePadding = Instance.new("UIPadding", animList:GetFrame())
		corePadding.PaddingBottom = UDim.new(0, padding)
		corePadding.PaddingLeft = UDim.new(0, padding)
		corePadding.PaddingRight = UDim.new(0, padding)
		corePadding.PaddingTop = UDim.new(0, padding)

		local exportButton = CustomTextButton.new("Upload", "Upload animation to Roblox")
		exportButton:getButton().Size = buttonSize
		animList:AddChild(exportButton:getButton())

		exportButton:getButton().MouseButton1Click:connect(uploadAnimation)

		local restartButton = CustomTextButton.new("Restart", "Restart/reload animation")
		restartButton:getButton().Size = buttonSize
		animList:AddChild(restartButton:getButton())

		restartButton:getButton().MouseButton1Click:connect(loadRig)

		local loopingButton = CustomTextButton.new("Looping", "Animation looping")
		loopingButton:getButton().Size = buttonSize
		animList:AddChild(loopingButton:getButton())

		loopingButton:getButton().MouseButton1Click:connect(function()
			activeRig.loop = not activeRig.loop
			updateAnimationOptionsGui()
			loadRig()
		end)

		local priorityButton = CustomTextButton.new("Priority", "Animation priority")
		priorityButton:getButton().Size = buttonSize
		animList:AddChild(priorityButton:getButton())

		priorityButton:getButton().MouseButton1Click:connect(function()
			local items = Enum.AnimationPriority:GetEnumItems()
			for i = 1, #items do
				if items[i] == activeRig.priority then
					activeRig.priority = items[i % #items + 1]
					break
				end
			end
			updateAnimationOptionsGui()
			loadRig()
		end)

		updateAnimationOptionsGui = function()
			loopingButton._label.Text = ("Animation looping [%s]"):format(activeRig.loop and "Yes" or "No")
			priorityButton._label.Text = ("Animation priority [%s]"):format(activeRig.priority.Name)
		end
	end

	-- Keyframe naming
	do
		local panelKfs = CollapsibleTitledSection.new("Names", "Named keyframes", true, true, false)
		mainList:AddChild(panelKfs:GetSectionFrame())

		local kfsList = VerticallyScalingListFrame.new("Core")
		kfsList._uiListLayout.Padding = UDim.new(0, padding)
		kfsList:GetFrame().Parent = panelKfs:GetContentsFrame()

		local corePadding = Instance.new("UIPadding", kfsList:GetFrame())
		corePadding.PaddingBottom = UDim.new(0, padding)
		corePadding.PaddingLeft = UDim.new(0, padding)
		corePadding.PaddingRight = UDim.new(0, padding)
		corePadding.PaddingTop = UDim.new(0, padding)

		local addButton = CustomTextButton.new("AddKF", "Add named keyframe")
		addButton:getButton().Size = buttonSize
		kfsList:AddChild(addButton:getButton())

		local headerFrame = Instance.new("Frame")
		headerFrame.Size = buttonSize
		headerFrame.BackgroundTransparency = 1
		kfsList:AddChild(headerFrame)

		local header1 = GuiUtilities.MakeStandardPropertyLabel("Time (s)")
		header1.Position = UDim2.new(0, 0, 0, 0)
		header1.AnchorPoint = Vector2.new()
		header1.Parent = headerFrame

		local header2 = GuiUtilities.MakeStandardPropertyLabel("Keyframe name")
		header2.Position = UDim2.new(0.3, 0, 0, 0)
		header2.AnchorPoint = Vector2.new()
		header2.Parent = headerFrame

		local header3 = GuiUtilities.MakeStandardPropertyLabel("Erase")
		header3.Position = UDim2.new(0.8, 0, 0, 0)
		header3.AnchorPoint = Vector2.new()
		header3.Parent = headerFrame

		addButton:getButton().MouseButton1Click:connect(function()
			local kfn = keyframeNameTemplate:Clone()
			kfn.KfName.FocusLost:connect(recollectKeyframeNames)
			kfn.KfTime.FocusLost:connect(recollectKeyframeNames)

			local eraseButton = CustomTextButton.new("Erase", "Erase")
			eraseButton:getButton().Size = UDim2.new(0.2, 0, 1, 0)
			eraseButton:getButton().Position = UDim2.new(0.8, 0, 0, 0)
			eraseButton:getButton().Parent = kfn
			eraseButton:getButton().MouseButton1Click:connect(function()
				kfn:Destroy()
				recollectKeyframeNames()
			end)

			kfsList:AddChild(kfn)
			recollectKeyframeNames()
		end)

		keyframeNamesContainer = kfsList:GetFrame()
	end

	-- Enable/disable bones
	do
		local panelWeight =
			CollapsibleTitledSection.new("Weight", "Enable/disable joint for animation", true, true, false)
		mainList:AddChild(panelWeight:GetSectionFrame())

		local boneList = VerticallyScalingListFrame.new("Core")
		boneList._uiListLayout.Padding = UDim.new(0, padding)
		boneList:GetFrame().Parent = panelWeight:GetContentsFrame()

		local corePadding = Instance.new("UIPadding", boneList:GetFrame())
		corePadding.PaddingBottom = UDim.new(0, padding)
		corePadding.PaddingLeft = UDim.new(0, padding)
		corePadding.PaddingRight = UDim.new(0, padding)
		corePadding.PaddingTop = UDim.new(0, padding)

		boneWeightsList = boneList
	end
end

-- TODO
local function addChildRigParts(parent, elemsLeft)
	for itr, child in pairs(parent.children) do
		local boneFrame = Instance.new("Frame")
		boneFrame.Size = buttonSize
		boneFrame.BackgroundTransparency = 1
		boneFrame.Name = "BoneWeightFrame"
		boneWeightsList:AddChild(boneFrame)

		for i = 1, #elemsLeft do
			local dirLbl = Instance.new("TextLabel")
			dirLbl.Text = elemsLeft[i] >= 1 and (i == #elemsLeft and (elemsLeft[i] == 1 and "└" or "├") or "│")
				or " "
			dirLbl.TextSize = 26
			dirLbl.BackgroundTransparency = 1
			dirLbl.Position = UDim2.new(0, (i - 1) * 20 + (i == #elemsLeft and -1 or 0), 0, 0)
			dirLbl.Size = UDim2.new(0, 20, 1, 0)
			dirLbl.Parent = boneFrame
		end
		elemsLeft[#elemsLeft] = elemsLeft[#elemsLeft] - 1

		local toggleButton = CustomTextButton.new("Toggle", ("%s %s"):format("[✔️]", child.part.Name))
		toggleButton:getButton().Size = UDim2.new(1, -#elemsLeft * 20, 1, 0)
		toggleButton:getButton().Position = UDim2.new(0, #elemsLeft * 20, 0, 0)
		toggleButton:getButton().Parent = boneFrame
		toggleButton:getButton().MouseButton1Click:connect(function()
			child.enabled = not child.enabled
			toggleButton._label.Text = ("%s %s"):format(child.enabled and "[✔️]" or "[❌]", child.part.Name)
			loadRig()
		end)

		elemsLeft[#elemsLeft + 1] = #child.children
		addChildRigParts(child, { unpack(elemsLeft) })
		elemsLeft[#elemsLeft] = nil
	end
end

-- TODO
local function rebuildBoneWeightsContainer()
	for _, elem in pairs(boneWeightsList:GetFrame():GetChildren()) do
		if elem.Name == "BoneWeightFrame" then
			elem:Destroy()
		end
	end

	local label = GuiUtilities.MakeStandardPropertyLabel(activeRig.root.part.Name)
	label.Position = UDim2.new(0, 0, 0, 0)
	label.Size = UDim2.new(1, 0, 0, 20)
	label.AnchorPoint = Vector2.new()
	label.Name = "BoneWeightFrame"
	boneWeightsList:AddChild(label)

	addChildRigParts(activeRig.root, { #activeRig.root.children })
end

local function init()
	local toolbar = plugin:CreateToolbar("Blender Animations")
	activateButton = toolbar:CreateButton(
		"Blender Animations",
		"Import and export Blender animations",
		"http://www.roblox.com/asset/?id=4510352246"
	)

	activateButton.Click:connect(function()
		if active then
			deactivate()
			return
		end

		plugin:Activate(false)
		activateButton:SetActive(true)
		plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())

		active = true
		gui.Parent = game.CoreGui
		activeRig = nil
		plugin:Activate(true)
		activateButton:SetActive(true)
		game.Selection:Set({})
		if rigSelectionEvent then
			rigSelectionEvent:disconnect()
		end
		rigSelectionEvent = game.Selection.SelectionChanged:connect(function()
			if game.Selection:Get()[1] and setRig(game.Selection:Get()[1]) then
				rigSelectionEvent:disconnect()
				rigSelectionEvent = nil
				dockGui.Enabled = true
				clearKeyframeNames()
				rebuildBoneWeightsContainer()
				wait()
				RS:Run()
			end
		end)

		showHint("Select the rig model")
	end)

	createUI()

	dockGui:GetPropertyChangedSignal("Enabled"):connect(function()
		if dockGui.Enabled ~= dockGuiPreviousEnabled then
			dockGuiPreviousEnabled = dockGui.Enabled
			if not dockGui.Enabled and active then
				deactivate()
			end
		end
	end)
end

init()
