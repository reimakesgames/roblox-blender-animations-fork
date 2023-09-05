local RigPart = require(script.Parent.RigPart)

local Rig = {}
Rig.__index = Rig


function Rig.new(model)
	local self = {
		model = model,
		root = nil,
		animTime = 10,
		loop = true,
		priority = Enum.AnimationPriority.Action,
		keyframeNames = {}, -- table with values each in the format: {t = number, name = string}
	}
	setmetatable(self, Rig)

	self.root = RigPart.new(self, model.PrimaryPart, nil)

	return self
end

function Rig:GetRigParts()
	local parts = {}

	local function finder(part)
		for _, child in pairs(part.children) do
			parts[#parts + 1] = child
			finder(child)
		end
	end

	finder(self.root)

	return parts
end

function Rig:FindRigPart(name, from)
	from = from or self.root
	if from.part.Name == name then
		return from
	end
	for _, child in pairs(from.children) do
		local found = self:FindRigPart(name, child)
		if found then
			return found
		end
	end
	return nil
end

function Rig:ClearPoses()
	for _, rigPart in pairs(self:GetRigParts()) do
		rigPart.poses = {}
	end
end

function Rig:LoadAnimation(data)
	self:ClearPoses()

	local rigParts = self:GetRigParts()

	self.animTime = data.t

	for _, kfdef in pairs(data.kfs) do
		for _, rigPart in pairs(rigParts) do
			if kfdef.kf[rigPart.part.Name] then
				local cfc = kfdef.kf[rigPart.part.Name]

				-- normalize each rotation vector
				for axis = 0, 2 do
					local normvec = Vector3.new(cfc[4 + axis], cfc[7 + axis], cfc[10 + axis]).Unit
					cfc[4 + axis], cfc[7 + axis], cfc[10 + axis] = normvec.X, normvec.Y, normvec.Z
				end

				rigPart:AddPose(kfdef.t, CFrame.new(unpack(cfc)))
			else
				rigPart:AddPose(kfdef.t, CFrame.new())
			end
		end
	end
end

function Rig:ToRobloxAnimation(useFramesForTime: boolean)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Loop = self.loop
	kfs.Priority = self.priority
	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if humanoid then -- otherwise just use default/is anim controller/...
		kfs.AuthoredHipHeight = humanoid.HipHeight
	end
	local t = 0
	local rigParts = self:GetRigParts()
	local nextKfNameIdx = 1
	while true do
		-- Serialize t
		local kf = Instance.new("Keyframe")
		kf.Time = t
		kf.Parent = kfs

		-- if useFramesForTime then
		-- else
			if self.keyframeNames[nextKfNameIdx] and self.keyframeNames[nextKfNameIdx].t <= t then
				kf.Name = self.keyframeNames[nextKfNameIdx].name
				nextKfNameIdx = nextKfNameIdx + 1
			end
		-- end

		local pose = self.root:PoseToRobloxAnimation(t)
		pose.Parent = kf

		-- Find next t to serialize
		local nextT = math.huge
		for _, rigPart in pairs(rigParts) do
			for poseT, pose in pairs(rigPart.poses) do
				if poseT > t and poseT < nextT then
					nextT = poseT
				end
			end
		end

		if nextT == math.huge then
			break
		end

		t = nextT
	end

	return kfs
end

function Rig:EncodeRig()
	-- Actually encoded the rig itself
	return self.root:Encode({})
end

export type Type = typeof(Rig.new())

return Rig
