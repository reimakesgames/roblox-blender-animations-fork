local RigPart = {}
RigPart.__index = RigPart

local Pose = require(script.Parent.Pose)

local function findAll(instance, func, resTab)
	resTab = resTab or {}
	if func(instance) then
		resTab[#resTab + 1] = instance
	end
	for _, child in pairs(instance:GetChildren()) do
		findAll(child, func, resTab)
	end

	return resTab
end

local function find(instance, func)
	return findAll(instance, func)[1]
end

function RigPart.new(rig, part, parent)
	local self = {
		rig = rig,
		part = part,
		parent = parent,
		joint = nil,
		poses = {},
		children = {},
		enabled = true,
	}
	setmetatable(self, RigPart)

	if parent then
		self.joint = find(rig.model, function(joint)
			return joint:IsA("Motor6D") and joint.Part0 == parent.part and joint.Part1 == part
		end)
	end

	for _, subpart in pairs(part:GetConnectedParts()) do
		local nextJoint = find(rig.model, function(joint)
			return joint:IsA("Motor6D") and joint.Part0 == part and joint.Part1 == subpart
		end)
		if nextJoint then
			self.children[#self.children + 1] = RigPart.new(rig, subpart, self)
		end
	end

	return self
end

function RigPart:AddPose(kft, transform)
	self.poses[kft] = Pose.new(self, transform)
end

function RigPart:PoseToRobloxAnimation(t)
	local pose = Instance.new("Pose")
	pose.Name = self.part.Name
	pose.Weight = self.enabled and 1 or 0

	if self.poses[t] then
		pose.CFrame = self.poses[t].transform
	elseif not next(self.poses) then
		-- no transforms at all, use identity
		pose.CFrame = CFrame.new()
	else
		error("no pose at time " .. t .. " for " .. self.part.Name) -- todo: lerp
	end

	for _, child in pairs(self.children) do
		local subpose = child:PoseToRobloxAnimation(t)
		subpose.Parent = pose
	end

	return pose
end

function RigPart:FindAuxParts()
	local jointSet = findAll(self.rig.model, function(joint)
		return joint:IsA("JointInstance")
			and not joint:IsA("Motor6D")
			and (joint.Part0 == self.part or joint.Part1 == self.part)
	end)

	local instSet = {}
	for i, joint in pairs(jointSet) do
		instSet[i] = joint.Part0 == self.part and joint.Part1 or joint.Part0
	end
	instSet[#instSet + 1] = self.part

	return instSet
end

function RigPart:Encode(handledParts)
	handledParts[self.part] = true

	local elem = { inst = self.part, jname = self.part.Name, children = {}, aux = self:FindAuxParts() }

	if self.parent then
		-- is not root, so find joint that connects the two...
		local childs = self.parent.part:GetChildren()
		for _, child2 in pairs(self.part:GetChildren()) do
			childs[#childs + 1] = child2
		end

		for _, joint in pairs(childs) do
			if joint:IsA("Motor6D") and joint.Part0 == self.parent.part and joint.Part1 == self.part then
				elem.jointtransform0 = { joint.C0:components() }
				elem.jointtransform1 = { joint.C1:components() }
			end
		end
		assert(
			elem.jointtransform0 and elem.jointtransform1,
			"Joint connecting " .. self.part.Name .. " to " .. self.parent.part.Name .. " not found"
		)
	end

	elem.transform = { self.part.CFrame:components() }

	for _, subrigpart in pairs(self.children) do
		if not handledParts[subrigpart.part] then
			elem.children[#elem.children + 1] = subrigpart:Encode(handledParts)
		end
	end

	return elem
end

return RigPart
