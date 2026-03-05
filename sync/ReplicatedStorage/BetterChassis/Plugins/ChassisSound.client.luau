--!strict
local RunService = game:GetService("RunService")

local car = script.Parent.Car.Value :: Model
local handler = car:WaitForChild("CarSoundEvent") :: UnreliableRemoteEvent

local success, _Tune = pcall(require, car:FindFirstChildOfClass("ModuleScript"))

if not success then
	error(
		`Failed to load chassis config (ModuleScript) for "{car.Name}". Make sure it exists and it's properly formatted.`
	)
end

local function waitForAttribute(inst: Instance, name: string)
	while inst:GetAttribute(name) == nil do
		print(`{script} :: Waiting for attribute "{name}" on instance "{inst:GetFullName()}"...`)
		task.wait()
	end
	return inst:GetAttribute(name)
end

-- Pull audio config from server-owned attributes so no local Sounds are needed.
local REV_VOLUME = waitForAttribute(handler, "RevVolume") :: number
local REV_SET_PITCH = waitForAttribute(handler, "RevSetPitch") :: number
local REV_SET_REV = waitForAttribute(handler, "RevSetRev") :: number

local on = 0
local throt = 0
local redline = 0

-- Throttle remote updates to avoid spamming the server while still keeping sound responsive.
local UPDATE_INTERVAL = 0.05
local PITCH_EPSILON = 0.01
local lastPitch
local lastVolume
local accumulator = 0

handler:FireServer("createRevSound")
handler:FireServer("playSound", "Rev")

print(
	`{script} :: CarSoundEvent handler initialized for car "{car.Name}" volume {REV_VOLUME}, pitch settings ({REV_SET_PITCH}, {REV_SET_REV})`
)

local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < UPDATE_INTERVAL then return end
	accumulator = 0

	local _RPM = script.Parent.Values.RPM.Value

	if script.Parent.Values.Throttle.Value <= _Tune.IdleThrottle / 100 then
		throt = math.max(0.3, throt - 0.2)
	else
		throt = math.min(1, throt + 0.1)
	end
	if
		script.Parent.Values.RPM.Value > _Tune.Redline - _Tune.RevBounce / 4
		and script.Parent.Values.Throttle.Value > _Tune.IdleThrottle / 100
	then
		redline = 0.5
	else
		redline = 1
	end
	if not script.Parent.IsOn.Value then
		on = math.max(on - 0.015, 0)
	else
		on = 1
	end

	local pitch = math.max(((REV_SET_PITCH + REV_SET_REV * _RPM / _Tune.Redline) * on ^ 2), REV_SET_PITCH)
	local volume = REV_VOLUME

	if lastPitch and math.abs(pitch - lastPitch) < PITCH_EPSILON and lastVolume == volume then return end

	handler:FireServer("updateSound", "Rev", pitch, volume)
	lastPitch = pitch
	lastVolume = volume
end)

car.Destroying:Connect(function()
	heartbeatConnection:Disconnect()
end)
