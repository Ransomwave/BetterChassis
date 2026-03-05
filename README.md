# BetterChassis - Fork of A-Chassis

BetterChassis is `A-Chassis` (version 6.52S2) with a focus on modularity. Instead of copy-pasting the system into every vehicle in your game, you can use `BetterChassis` as the base for all your vehicles.

## What's included?

- The core `BetterChassis` module, which contains the main logic for the system.
- A `ConfigTemplate` module, which serves as a template for the configuration of your vehicles
- `ChassisUtils`, a module containing utility functions for the system.

### Built-in Plugins

- **Sound**: A plugin that adds engine sounds to your vehicle.
- **Mobile Controls**: Rather than a plugin per-say, this has been built into the core of the system. It a mobile-friendly control scheme to your vehicle.

## Syntax

```lua
local BetterChassis = require(ReplicatedStorage.BetterChassis)

local car = workspace.Car
local config = car.Config -- ModuleScript containing the configuration for the vehicle. See "ConfigTemplate" for an example.

local chassis = BetterChassis.new(car, config)
chassis:Init() -- Initializes the system for the specified vehicle.
```

## Get started

This project has been bootstrapped with [Azul](https://github.com/Ransomwave/azul), the easiest two-way sync tool.

Use `azul push` to get this library into your Roblox project:

```ps1
azul push -s .\sync\ReplicatedStorage -d "ReplicatedStorage"
```

This will push the library to `ReplicatedStorage`. You can change the destination to any service (i.e. `ServerStorage`, `ServerScriptService`, etc.).

## Credits

- [Original A-Chassis module](https://github.com/lisphm/A-Chassis)
