local HttpService = game:GetService("HttpService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local PluginGuiService = game:GetService("PluginGuiService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local BaseXX = require(script.Parent.BaseXX)
local DeflateLua = require(script.Parent.DeflateLua)
local Rig = require(script.Parent.Rig)

local COLORS = {
	BACKGROUND = Color3.fromRGB(15, 15, 19),

	DEFAULT = Color3.fromRGB(64, 66, 88),
	ACCENTED = Color3.fromRGB(71, 78, 104),

	TEXT = Color3.fromRGB(191, 191, 191),
	SECONDARY_TEXT = Color3.fromRGB(107, 114, 142),

	ERROR = Color3.fromRGB(233, 102, 160),
	WARNING = Color3.fromRGB(255, 165, 89),
	BUTTON = Color3.fromRGB(149, 117, 222),
	BUTTON_DEPRESSED = Color3.fromRGB(101, 84, 175)
}

local APP_NAME = "Roblox Blender Animation Tool"
local APP_VERSION = "0.1"


local WARNING_COUNT = "(%d warnings)"
local WARNING_EXPORT_MERGE_BY_MATERIAL = "WARN: ExportMergeByMaterial should be disabled!"
local WARNING_EXPORT_MERGE_BY_MATERIAL_HINT = "► Disable this in Settings > Rendering"
local WARNING_NON_ALPHANUMERIC = "WARN: Non-alphanumeric characters in object name!"
local WARNING_NON_ALPHANUMERIC_HINT = "► Rename the object to only contain a-z, A-Z, and 0-9."
local WARNING_DECAL = "WARN: Decal found!\nDecals could cause issues with exporting."
local WARNING_DECAL_HINT = "► ...%s"
local WARNING_TEXTURE = "WARN: Texture found!\nTextures could cause issues with exporting."
local WARNING_TEXTURE_HINT = "► ...%s"

local ToolbarButton: PluginToolbarButton

local RigSelectionEvent: RBXScriptConnection?
local HintDissapearThread: thread

local ActiveRig: Rig.Type?
local ActiveRigModel: Model?
local ActiveAnimator: Humanoid | AnimationController
local ActiveAnimationTrack: AnimationTrack?

local ActionEditorExportedName: string?

local PotentialIssues = {}
local MetadataParts = {}

local Active = false

local DockGui = plugin:CreateDockWidgetPluginGui(
	APP_NAME,
	DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		true,
		false,
		400,
		600
	)
)
DockGui.Title = APP_NAME
local DockGuiPreviouslyEnabled = false

local function FastInstance(className, properties)
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		if key == "Parent" then
			continue
		end
		instance[key] = value
	end
	if properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

local function TruncatedFullName(parent, child)
	local fullName = child:GetFullName()
	local parentFullName = parent:GetFullName()
	-- should look like "RigName.ChildName" instead of "game.Workspace.RigName.ChildName"
	return parent.Name .. "." .. fullName:sub(#parentFullName + 2)
end

local InViewportGui = FastInstance("ScreenGui", {
	Name = APP_NAME,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
})
local InViewportHint = FastInstance("TextLabel", {
	Name = "Hint",
	Text = "This is a hint.",
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeColor3 = Color3.new(0, 0, 0),
	TextStrokeTransparency = 0,
	TextSize = 24,
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Parent = InViewportGui,
})

local function Print(...)
	print(`[{APP_NAME} v{APP_VERSION}]`, ...)
end

local function ShowHint(text, ...)
	InViewportHint.Text = text
	InViewportHint.Visible = true
	if HintDissapearThread then
		task.cancel(HintDissapearThread)
	end
	HintDissapearThread = coroutine.wrap(function()
		task.wait(3)
		InViewportHint.Visible = false
	end)()
end



local function ClearMetadataParts()
	if #MetadataParts > 0 then
		for _, part in ipairs(MetadataParts) do
			part:Destroy()
		end
		table.clear(MetadataParts)
	end
end

local function StopAnimation()
	if ActiveAnimationTrack then
		ActiveAnimationTrack:Stop(0.001)
		ActiveAnimationTrack:Destroy()
		ActiveAnimationTrack = nil
	end
end




-- why did bro name it like this while being completely irrelevant from what's being done
local function LoadRig()
	StopAnimation()

	if not ActiveRig then
		ShowHint("No rig selected.")
		return
	end
	if not ActiveAnimator then
		ShowHint("No animator found.")
		return
	end

	local KeyframeSequence = ActiveRig:ToKeyframeSequence()
	local Hash = KeyframeSequenceProvider:RegisterKeyframeSequence(KeyframeSequence)

	local Animation = Instance.new("Animation")
	Animation.AnimationId = Hash

	-- why type error??? Humanoid and AnimationController HAVE a LoadAnimation method
	-- i would cast it but meh there should be an Animator inside them anyways
	local Animator = ActiveAnimator:FindFirstChildOfClass("Animator")
	if not Animator then
		ShowHint("No animator found.")
		return
	end
	ActiveAnimationTrack = Animator:LoadAnimation(Animation)
	if not ActiveAnimationTrack then
		ShowHint("Failed to load animation.")
		return
	end -- grrrrrr static analysis
	ActiveAnimationTrack:Play(0.001)
end

local function UploadAnimation()
	-- should be cleaned up at some point, but no proper way to detect that?
	assert(ActiveRig)
	assert(ActiveRigModel)
	assert(ActionEditorExportedName)
	local KeyframeSequence = ActiveRig:ToRobloxAnimation()
	local Folder = workspace:FindFirstChild("AnimationExports") or Instance.new("Folder")
	Folder.Name = "AnimationExports"
	Folder.Parent = workspace
	KeyframeSequence.Name = ActiveRigModel.Name .. "_" .. ActionEditorExportedName
	KeyframeSequence.Parent = Folder
	Selection:Set({ KeyframeSequence })
	plugin:SaveSelectedToRoblox()
end

local function ExportAnimation()
	assert(ActiveRig)
	assert(ActiveRigModel)
	assert(ActionEditorExportedName)
	local KeyframeSequence = ActiveRig:ToRobloxAnimation()
	local Folder = workspace:FindFirstChild("AnimationExports") or Instance.new("Folder")
	Folder.Name = "AnimationExports"
	Folder.Parent = workspace
	KeyframeSequence.Name = ActiveRigModel.Name .. "_" .. ActionEditorExportedName
	KeyframeSequence.Parent = Folder
	Selection:Set({ KeyframeSequence })
end

-- ok i have no expertise with these but i'll copy it 1:1
local function ReencodeJointMetadata(rigNode, partEncodeMap)
	-- round transform matrices (compresses data)
	for _, transform in pairs({ "transform", "jointtransform0", "jointtransform1" }) do
		if rigNode[transform] then
			for i = 1, #rigNode[transform] do
				rigNode[transform][i] = math.floor(rigNode[transform][i] * 10000 + 0.5) / 10000 -- no idea what this does
			end
		end
	end

	rigNode.pname = partEncodeMap[rigNode.inst]
	rigNode.inst = nil
	local realAux = rigNode.aux
	rigNode.aux = {}

	for _, aux in pairs(realAux) do
		table.insert(rigNode.aux, partEncodeMap[aux])
	end

	for _, child in pairs(rigNode.children) do
		ReencodeJointMetadata(child, partEncodeMap)
	end
end

-- no idea for this too, so copy again lol
-- serializes the neutral rig state to a table that can be serialized to json safely
-- normalized the model part names as well
local function GenerateMetadata(rigModelToExport)
	assert(ActiveRig)

	local PartNames = {}
	local PartEncodeMap = {}
	local UsedModelNames = {}
	local PartCount = 0

	local OriginalDescendants = ActiveRig.model:GetDescendants()
	for descIDx, desc in ipairs(rigModelToExport:GetDescendants()) do
		if desc:IsA("BasePart") then
			PartCount += 1

			-- uniqify the name
			local Name = desc.Name
			local RetryCount = 0
			while UsedModelNames[Name] do
				RetryCount += 1
				desc.Name = Name .. RetryCount
			end

			UsedModelNames[desc.Name] = true
			table.insert(PartNames, desc.Name)
			PartEncodeMap[OriginalDescendants[descIDx]] = desc.Name
			desc.Name = rigModelToExport.Name .. PartCount
		elseif desc:IsA("Humanoid") then
			-- Get rid of all humanoids so that they do not affect naming...
			-- what for??
			desc:Destroy()
		end
	end

	local EncodedRig = ActiveRig:EncodeRig()
	ReencodeJointMetadata(EncodedRig, PartEncodeMap)

	return {
		rigName = ActiveRig.model.Name,
		parts = PartNames,
		rig = EncodedRig,
	}
end

-- again, no idea what this does
local function ExportRig()
	assert(ActiveRig)
	assert(ActiveRigModel) -- this isn't added in the original plugin, but static analysis is complaining so i'll add it

	ClearMetadataParts()

	-- Clone the rig model, then rename all baseparts to the rig name (let the export flow handle unique indices)
	local RigModelToExport = ActiveRigModel:Clone()
	RigModelToExport.Parent = ActiveRigModel.Parent
	RigModelToExport.Archivable = false

	MetadataParts = { RigModelToExport }

	local Metadata = GenerateMetadata(RigModelToExport)

	-- store encoded metadata in a bunch of auxiliary part names
	-- what is auxiliary part names?? WHAT is this witchcraft
	local MetadataEncodedJson = HttpService:JSONEncode(Metadata)
	local MetadataEncoded = BaseXX.to_base32(MetadataEncodedJson):gsub("=", "0")
	local IDx = 1
	local SegmentLength = 45 -- oooooooo scary magic number
	for i = 1, #MetadataEncoded + 1, SegmentLength do
		local MetadataPart = Instance.new("Part")
		MetadataPart.Name = ("meta%dq1%sq1"):format(IDx, MetadataEncoded:sub(i, i + SegmentLength - 1))
		MetadataPart.Anchored = true
		MetadataPart.Archivable = false
		table.insert(MetadataParts, MetadataPart)
		IDx += 1
	end
	Selection:Set(MetadataParts)
	PluginManager():ExportSelection() -- hah deprecated
	-- yeah... deprecated, dont care it works and i have no idea what to do with it
end

local function LoadAnimation(data)
	if not ActiveRig then
		ShowHint("No rig selected.")
		return
	end

	local AnimationData = BaseXX.from_base64(data)
	local UnpackedSequence = {}
	local UnpackedSequenceIDx = 1 -- what is IDx??

	DeflateLua.inflate_zlib({
		disable_crc = true,
		input = AnimationData,
		output = function(streamByte)
			UnpackedSequence[UnpackedSequenceIDx] = streamByte
			UnpackedSequenceIDx += 1
		end
	}) -- is this extreme nerd math that i don't understand? probably! who knows, im just remaking the plugin

	local UnpackedSequenceString = table.concat(UnpackedSequence, "")
	local UnpackedSequenceTable = HttpService:JSONDecode(UnpackedSequenceString)

	ActionEditorExportedName = UnpackedSequenceTable["anim_name"] or "Untitled"
	Print("Your Action name (from Blender Action Editor) is:", ActionEditorExportedName)

	ActiveRig:LoadAnimation(UnpackedSequenceTable)
end

local function LoadAnimationDataFromText(data)
	local success, result = pcall(LoadAnimation, data)
	if not success then
		ShowHint("Failed to load animation data.")
		Print("Failed to load animation data.")
		Print(result)
	else
		ShowHint("Loaded animation data.")
		Print("Loaded animation data.")
	end
end

local function CheckForPotentialIssues()
	table.clear(PotentialIssues)
	local WarningCount = 0

	if not ActiveRigModel then
		table.insert(PotentialIssues, "No rig selected.")
	else
		if settings().Rendering.ExportMergeByMaterial then
			table.insert(PotentialIssues, WARNING_EXPORT_MERGE_BY_MATERIAL)
			table.insert(PotentialIssues, WARNING_EXPORT_MERGE_BY_MATERIAL_HINT)
		end

		if ActiveRigModel.Name:match("[^a-zA-Z0-9]") then
			table.insert(PotentialIssues, WARNING_NON_ALPHANUMERIC)
			table.insert(PotentialIssues, WARNING_NON_ALPHANUMERIC_HINT)
		end

		for _, descendant in ActiveRigModel:GetDescendants() do
			if descendant:IsA("Decal") then
				table.insert(PotentialIssues, WARNING_DECAL)
				table.insert(PotentialIssues, WARNING_DECAL_HINT:format(TruncatedFullName(ActiveRigModel, descendant)))
			elseif descendant:IsA("Texture") then
				table.insert(PotentialIssues, WARNING_TEXTURE)
				table.insert(PotentialIssues, WARNING_TEXTURE_HINT:format(TruncatedFullName(ActiveRigModel, descendant)))
			end
		end
	end

	table.insert(PotentialIssues, WARNING_COUNT:format(WarningCount))
	if #PotentialIssues > 0 then
		for _, issue in ipairs(PotentialIssues) do
			Print(issue)
		end
		Print("Fix all issues before exporting.")
	else
		Print("No issues found.")
	end
end

local function SetRig(rig)
	if not rig then
		ShowHint("Nothing selected.")
		return false
	end

	if not rig:IsA("Model") then
		ShowHint("Selected object is not a model.")
		return false
	end

	if not rig.PrimaryPart then
		ShowHint("Rig has no primary part.")
		return false
	end

	if not rig.PrimaryPart.Anchored then
		ShowHint("Rig primary part must be anchored.")
		return false
	end

	ActiveRigModel = rig
	ActiveAnimator = rig:FindFirstChildOfClass("Humanoid") or rig:FindFirstChildOfClass("AnimationController")
	if not ActiveAnimator then
		ShowHint("Rig has no Humanoid or AnimationController.")
		ActiveRigModel = nil
		return false
	end

	ShowHint("Rig set to `" .. rig.Name .. "`.")

	CheckForPotentialIssues()

	ActiveRig = Rig.new(rig)
	ShowHint("Set rig to `" .. rig.Name .. "`.")


	return true
end










-- UI stuff
-- remember to trim this "code smell" later
-- god styleguides are my bane













local function CollectKeyframeNames()
	-- TODO: This block of function USES untrustable io, t calculation uses milisecond stuff
	-- TODO: A short fix is implemented via a "MS" or "Frame" toggle which lets you choose between the two
	-- TODO: MS, is default, and Frame is blender's frame number, which depends on the blender config
	-- TODO: actually implement Frame, cba to modify Rig class

	local KeyframeNames = {}
	for _, keyframeUi: Frame in KeyframeNamesContainer:GetChildren() do
		if keyframeUi:IsA("TextLabel") and keyframeUi.Name == "KFNTemplate" then
			-- reposition in list by changing the layout order


			local Time = tonumber(keyframeUi.TFrameime.Text)
			-- anything with this Time already exists?
			for _, keyframeName in ipairs(KeyframeNames) do
				if keyframeName.t == Time then -- ???
					Time = nil
					return
				end
			end

			-- convert
			if Time then
				table.insert(KeyframeNames, {
					t = Time,
					name = keyframeUi.FrameName.Text,
				})
			else
				keyframeUi.FrameTime.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
			end
		end
	end
end








local function Deactivate()
	DockGui.Enabled = false
	StopAnimation()
	Selection:Set({})
	task.wait()

	RunService:Stop()

	task.wait()

	ClearMetadataParts()
	Active = false
	ToolbarButton:SetActive(false)
	InViewportGui.Parent = nil

	if RigSelectionEvent then
		RigSelectionEvent:Disconnect()
		RigSelectionEvent = nil
	end
end

local function Startup()
	local Toolbar = plugin:CreateToolbar(APP_NAME)
	ToolbarButton = Toolbar:CreateButton(
		"Open GUI",
		"Opens the Utility Widget",
		"rbxassetid://11087437445"
	)

	ToolbarButton.Click:Connect(function()
		if Active then
			Deactivate()
			return
		end

		plugin:Activate(false)
		ToolbarButton:SetActive(true)
		plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())

		Active = true
		ActiveRig = nil
		InViewportGui.Parent = PluginGuiService

		plugin:Activate(true)
		ToolbarButton:SetActive(true)
		Selection:Set({})

		if RigSelectionEvent then
			RigSelectionEvent:Disconnect()
		end
		RigSelectionEvent = Selection.SelectionChanged:Connect(function()
			local Selected = Selection:Get()[1]
			if Selected and SetRig(Selected) then
				if RigSelectionEvent then -- come on luau static analysis
					RigSelectionEvent:Disconnect()
				end
				RigSelectionEvent = nil

				DockGui.Enabled = true
			end
		end)

		Print("Select a rig to begin.")
	end)



	DockGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if DockGui.Enabled ~= DockGuiPreviouslyEnabled then
			DockGuiPreviouslyEnabled = DockGui.Enabled
			if not DockGui.Enabled and Active then
				Deactivate()
			end
		end
	end)
end

Startup()
