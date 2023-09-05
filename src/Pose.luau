local Pose = {}
Pose.__index = Pose

function Pose.new(rigPart, transform)
	local self = {
		rigPart = rigPart,
		transform = transform,
	}
	setmetatable(self, Pose)

	return self
end

return Pose
