local calculateAngle = function(vector1, vector2)
	local dotProduct = vector1.x * vector2.x + vector1.y * vector2.y + vector1.z * vector2.z
	local magnitude1 = math.sqrt(vector1.x^2 + vector1.y^2 + vector1.z^2)
	local magnitude2 = math.sqrt(vector2.x^2 + vector2.y^2 + vector2.z^2)
	if magnitude1 == 0 or magnitude2 == 0 then return 0 end
	local cosineTheta = math.max(-1, math.min(1, dotProduct / (magnitude1 * magnitude2)))
	return math.deg(math.acos(cosineTheta))
end

local homingDegree = 0.5

local function navigateMissile(object)
	if
		object.SpellType == 9 or object.SpellType == 15 or object.SpellType == 22
		or object.SpellType == 24 or object.SpellType == 32 or object.SpellType == 93
	then
		return
	end

	local ownerKind = bit.band(object.Owner, 7)
	local targetKind = bit.band(object.Target, 7)
	local targetIndex = bit.rshift(object.Target, 3)

	if targetIndex > Map.Monsters.high then return end

	local currentPosition = { X = object.X, Y = object.Y, Z = object.Z }
	local targetPosition

	if ownerKind == const.ObjectRefKind.Party and targetKind == const.ObjectRefKind.Monster then
		local mapMonster = Map.Monsters[targetIndex]
		if mapMonster.HitPoints <= 0 then return end
		targetPosition = { X = mapMonster.X, Y = mapMonster.Y, Z = mapMonster.Z + mapMonster.BodyHeight * 0.75 }
	elseif ownerKind == const.ObjectRefKind.Monster or ownerKind == 2 then
		local delta = { x = Party.X - object.X, y = Party.Y - object.Y, z = 0 }
		local angle = calculateAngle({ x = delta.x, y = delta.y, z = 0 }, { x = object.VelocityX, y = object.VelocityY, z = 0 })
		if angle >= homingDegree then return end
		targetPosition = { X = Party.X, Y = Party.Y, Z = Party.Z + 120 }
	else
		return
	end

	local speed = math.sqrt(object.VelocityX^2 + object.VelocityY^2 + object.VelocityZ^2)
	if speed == 0 then return end

	local dir = { X = targetPosition.X - currentPosition.X, Y = targetPosition.Y - currentPosition.Y, Z = targetPosition.Z - currentPosition.Z }
	local dirLen = math.sqrt(dir.X^2 + dir.Y^2 + dir.Z^2)
	if dirLen == 0 then return end
	local k = speed / dirLen

	object.VelocityX = k * dir.X
	object.VelocityY = k * dir.Y
	object.VelocityZ = k * dir.Z
end

function events.Tick()
	if not Game.ProjectileTrackingEnabled then return end
	for i = 0, Map.Objects.high do
		navigateMissile(Map.Objects[i])
	end
end
