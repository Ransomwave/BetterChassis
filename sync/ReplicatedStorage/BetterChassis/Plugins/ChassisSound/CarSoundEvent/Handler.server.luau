--!strict
local car = script.Parent.Parent
local driveSeat = car:WaitForChild("DriveSeat") :: VehicleSeat

local remote: RemoteEvent = script.Parent
local Sounds: { [string]: Sound } = {}
local chassisSound = {}

local SET_PITCH = 0.05
local SET_REV = 1.4

local revTemplate: Sound = script:WaitForChild("Rev")
remote:SetAttribute("RevVolume", revTemplate.Volume)
remote:SetAttribute("RevSetPitch", SET_PITCH)
remote:SetAttribute("RevSetRev", SET_REV)

chassisSound.createRevSound = function()
	local existing = Sounds.Rev
	if existing then
		existing:Stop()
		existing:Destroy()
	end

	local soundClone = revTemplate:Clone()
	soundClone.Parent = car:WaitForChild("DriveSeat")
	Sounds[soundClone.Name] = soundClone
	print(
		`{script} :: Created rev sound with ID {soundClone.SoundId} and volume {soundClone.Volume}`,
		soundClone:GetFullName()
	)
end

chassisSound.updateSound = function(sound, pit, vol)
	local sn = Sounds[sound]
	if not sn then return end
	if pit ~= sn.PlaybackSpeed then sn.PlaybackSpeed = pit end
	if vol ~= sn.Volume then sn.Volume = vol end
end

chassisSound.playSound = function(sound)
	if not Sounds[sound] then return end
	Sounds[sound]:Play()
end

chassisSound.pauseSound = function(sound)
	if not Sounds[sound] then return end
	Sounds[sound]:Pause()
end

chassisSound.stopSound = function(sound)
	if not Sounds[sound] then return end
	Sounds[sound]:Stop()
end

chassisSound.removeSound = function(sound)
	local sn = Sounds[sound]
	if not sn then return end
	sn:Stop()
	sn:Destroy()
	Sounds[sound] = nil
end

local remoteConnection = remote.OnServerEvent:Connect(function(pl, Fnc, ...)
	-- print(`{script} :: Received event from {pl.Name} with function {Fnc} and arguments:`, ...)
	local fn = chassisSound[Fnc]
	if fn then fn(...) end
end)

local childRemovedConnection = driveSeat.ChildRemoved:Connect(function(child)
	if child.Name == "SeatWeld" then chassisSound.removeSound("Rev") end
end)

car.Destroying:Connect(function()
	remoteConnection:Disconnect()
	childRemovedConnection:Disconnect()
end)
