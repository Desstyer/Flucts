# Flucts

**Version 2.2**

Flucts is a module for making dynamic, event-driven state objects that can be influenced by multiple sources simultaneously.

They allow you to create values that automatically resolve conflicts when multiple sources try to modify them. Each Fluct is made up of **Actors:** individual value sources that are combined using a **Resolver** to produce a single output value (The fluct's value)

Flucts and actors are event driven and only update when necessary, so they provide a really good performance level. If needed you can still manually edit actors values and the fluct will only update when the value is actually changed.

## Example Usage

```lua
local Flucts = require(game.ReplicatedStorage.Libraries.Flucts)

-- Create a Fluct that takes the highest priority value
local healthFluct = Flucts.Fluct({
    DefaultValue = 100,
    Resolver = Flucts.Resolvers.FirstSet
})

-- Create actors that influence the Fluct
local baseHealth = Flucts.Actor({
    DefaultValue = 100,
    Priority = 1
})

local buffHealth = Flucts.Actor({
    DefaultValue = 150,
    Priority = 5  -- Higher priority
})

-- Add actors to the Fluct
healthFluct:AddActor(baseHealth)
healthFluct:AddActor(buffHealth)

-- Read the resolved value
print(healthFluct:Read())  -- Outputs: 150 (buffHealth wins due to higher priority)

-- Listen for changes
healthFluct.ValueChanged:Connect(function(newValue)
    print("Health changed to:", newValue)
end)

-- Remove the buff
healthFluct:RemoveActor(buffHealth)  -- Falls back to 100
```

### Flucts

A Fluct is the main container that holds a value influenced by multiple Actors. It uses a Resolver to determine the final value.

#### Creating a Fluct

```lua
local fluct = Flucts.Fluct({
    DefaultValue = any, -- The starting/fallback value
    Resolver = function -- How to combine actor values, we will see more on resolvers later
})
```

### Actors

Actors are individual sources of influence on a Fluct. They can have priorities and tags that affect how they're resolved.

#### Creating an Actor

```lua
local actor = Flucts.Actor({
    DefaultValue = any,           -- The value this actor provides
    Priority = number,            -- Higher = more influence (optional)
    ResolverTags = table, -- Custom data for resolvers (optional)
    UpdateSignal = Signal -- Auto-update on signal (optional)
})
```

## Resolvers

Resolvers determine how multiple Actors are combined into a single value.

You can make as many custom resolvers as you need, however the Fluct module has many built-in resolvers:

### Linear

Combines values using mathematical operations based on priority order. It starts from the default value, and goes applying each actor's operation to the fluct's value, using the actor's value.

```lua
Resolver = Flucts.Resolvers.Linear
```

**Required Tags:**
- `Operation` - "Set", "Add", "Subtract", "Multiply", or "Divide"

```lua
local damageActor = Flucts.Actor({
    DefaultValue = 10,
    Priority = 4,
    ResolverTags = { Operation = "Add" }
})

local multiplierActor = Flucts.Actor({
    DefaultValue = 1.5,
    Priority = 12,
    ResolverTags = { Operation = "Multiply" }
})

-- Result: (100 + 10) * 1.5 = 165
```

## Yet another example

We can use flucts for UI elements, for example a button that changes color when hovered:

```lua
-- Create a color Fluct for a button
local colorFluct = Flucts.Fluct({
    DefaultValue = Color3.new(0.8, 0.8, 0.8),
    Resolver = Flucts.Resolvers.FirstSet
})

colorFluct.ValueChanged:Connect(function(color)
    button.BackgroundColor3 = color
end)

-- Base state
local baseColor = Flucts.Actor({
    DefaultValue = Color3.new(0.8, 0.8, 0.8),
    Priority = 10
})
colorFluct:AddActor(baseColor)

-- Hover state (higher priority, initially inactive)
local hoverColor = Flucts.Actor({
    DefaultValue = Color3.new(0.9, 0.9, 0.9),
    Priority = 50
})
hoverColor:SetActive(false)  -- Start disabled
colorFluct:AddActor(hoverColor)

button.MouseEnter:Connect(function()
    hoverColor:SetActive(true)  -- Enable hover color
end)

button.MouseLeave:Connect(function()
    hoverColor:SetActive(false)  -- Disable hover color
end)

-- Disabled state (highest priority)
local disabledColor = Flucts.Actor({
    DefaultValue = Color3.new(0.5, 0.5, 0.5),
    Priority = 100
})
disabledColor:SetActive(false)
colorFluct:AddActor(disabledColor)

-- When disabled, this color overrides everything
if disabled then
    disabledColor:SetActive(true)
end
```

### Signal-Driven Actors

Actors have a DefaultValue, however we can change that value via events:

```lua
local hoverSignal = Signal.New()

local hoverActor = Flucts.Actor({
    DefaultValue = false,
    Priority = 50,
    UpdateSignal = hoverSignal  -- Automatically updates when signal fires
})

-- Actor updates automatically
hoverSignal:Fire(true) -- Actor's value will change to the 1st parameter the signal is fired with
```

However you will rarely be using the default way of updating via signals, instead, using the Actor:ListenToPredicate method is way more powerful:

```lua
-- If we wanted to make an actor update the FOV if a frame is opened:
local FovFrameActor = Flucts.Actor({
    DefaultValue = 0,
    Priority = 10,
    ResolverTags = {Operation = "Add"}
})

local signal = MenuFrame:GetPropertyChangedSignal("Visible")

-- The value returned by the predicate will be the new value of the actor
FovFrameActor:ListenToPredicate(signal, function()
    if MagicalVariable then
      return nil -- If we return nil, then the actor doesnt update (The signal is ignored)
    end

    if MenuFrame.Visible then
      return 20 -- If the menu is opened, we add +20 to the current FOV
    else
      return 0
    end
end)
```
