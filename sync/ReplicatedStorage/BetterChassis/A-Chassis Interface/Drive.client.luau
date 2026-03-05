local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BetterChassis = require(ReplicatedStorage.BetterChassis)

local interface = script.Parent

local car = interface:WaitForChild("Car").Value
local moduleSuccess, _Tune = pcall(require, car:FindFirstChildOfClass("ModuleScript"))

if not moduleSuccess then
	error(
		`Failed to load chassis config (ModuleScript) for "{car.Name}". Make sure it exists and it's properly formatted.`
	)
end

local scooter = BetterChassis.new(car, _Tune, interface)

local driveSuccess, result = pcall(function()
	scooter:Drive()
end)

if not driveSuccess and RunService:IsStudio() then warn(`Drive error for "{car.Name}": {result}`) end
