--!strict
--[[
	-----------------------
	- Flucts   V2         -
	-----------------------
	
	--------------------------
	- By @Desstyer           -
	- Created: 24/9/2025     -
	- Last updated: 24/9/25  -
	--------------------------
	
	Flucts allow to easily create dynamic and changeable values driven by events. They are made up of
	different layers of actors each resolving into a single output value for the fluct.
	
	Flucts and actors only update when necessary and are event-driven, so they are performant.
	
	ACTORS:
	- ResolverTags: Tags read by the resolvers to determine how to interpretate the actor's value
	- Priority: Read by the resolver, determines the output of the fluct. Higher priority usually means more influence over
	final result.
	FLUCTS:
	- Properties: Similar to tags but with individual key-value pairs. Used by some resolvers to change their behavior.
	- Halted: If true, the fluct will not resolve and will keep the value it had when it was halted. When the fluct is unhalted
	and read from again it will automatically resolve again.
	- ValueChanged: Fires every time the fluct's value changes to a different one. Does not fire when created.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Services --
local RunService = game:GetService("RunService")

-- Dependencies --
local Signal = require(ReplicatedStorage.Libraries.Signal)

-- Types --
type FluctValue = number | string | boolean | any

type ActorEntry = {Actor: Actor, Connections: {Signal.Connection}}

export type Resolver = (Fluct) -> (FluctValue)

type CreateActorParams = {
	DefaultValue: FluctValue | (Actor) -> (FluctValue),
	UpdateSignal: Signal.Signal<FluctValue>?,
	Priority: number?,
	ResolverTags: {[string]: any}?
}

type CreateFluctParams<V> = {
	DefaultValue: V,
	Resolver: Resolver
}

export type Fluct<V = FluctValue> = {
	Value: V,
	DefaultValue: V,
	Actors: {ActorEntry},
	Resolver: Resolver,
	
	Properties: {[string]: any}?,
	Halted: boolean?,
	Dirty: boolean?,
	
	ValueChanged: Signal.Signal<FluctValue>,
		
	Read: (self: any) -> (FluctValue),
	RemoveActor: (self: any, actor: Actor) -> (Fluct),
	AddActor: (self: any, actor: Actor) -> (Fluct),
	Halt: (self: any, is_halted: boolean) -> (Fluct),
	Resolve: (self: any) -> (Fluct),
	SetProperties: (self: any, values: {[string]: any}) -> (Fluct),
	GetActors: (self: any) -> ({Actor}),
}

export type Actor = {
	Value: FluctValue | (Actor) -> (FluctValue),
	
	Connection: Signal.Connection?,
	Priority: number?,
	ResolverTags: {[string]: any}?,
	
	ValueChanged: Signal.Signal<FluctValue>,
	
	Update: (self: any, new_value: FluctValue) -> (),
	ListenTo: (self: any, update_signal: Signal.Signal<FluctValue>) -> (),
	ListenToPredicate: (self: any, update_signal: Signal.Signal<...any> | RBXScriptSignal, predicate: (...any) -> (FluctValue?)) -> (),
	Destroy: (self: any) -> (),
	Read: (self: any) -> (FluctValue),
	GetTagValue: (self: any, tag: string) -> (any),
	AddTag: (self: any, tag: string, value: any) -> (),
	RemoveTag: (self: any, tag: string) -> ()
}

-- Constants --
local Fluct = {}
Fluct.__index = Fluct
Fluct.__tostring = function(self: Fluct)
	return `Fluct: {self:Read()}`
end
local Actor = {}
Actor.__index = Actor
Actor.__tostring = function(self: Actor)
	return `Actor: {self.Value}`
end

local Flags = {
	ActorDestroyed = newproxy(true)
}

local Resolvers = {}

-- Resolvers

--[[
	Linear Resolver
	
	Starts with the default value at the lowest priority and works its way up, applying the actors' operations to the value.
	Specify the operation type using the 'Operation' tag, which supports the following values:
	- Set
	- Add
	- Subtract
	- Multiply
	- Divide
]]
function Resolvers.Linear(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	
	-- Shift non-priority actors to the start of the list and keep high-priority actors at the end
	table.sort(actors, function(a: Actor, b: Actor)
		if not a.Priority then return true end
		if not b.Priority then return false end
		return a.Priority < b.Priority
	end)

	local currentValue = fluct.DefaultValue
	
	-- Loop through all actors from lowest priority to highest priority
	for i, actor in ipairs(actors) do
		local operation = actor:GetTagValue("Operation")
		if operation == "Set" then
			currentValue = actor.Value
			continue
		end
		if typeof(currentValue) ~= "number" or typeof(actor.Value) ~= "number" then error(`Only number type supports add/sub/mul/div`) end
		if operation == "Add" then
			currentValue += actor.Value
		elseif operation == "Subtract" then
			currentValue -= actor.Value
		elseif operation == "Multiply" then
			currentValue *= actor.Value
		elseif operation == "Divide" then
			currentValue /= actor.Value
		end
	end

	return currentValue
end

--[[
	AllTrue Resolver
	
	Resolves to true if all actors are true, otherwise resolves to false.
]]
function Resolvers.AllTrue(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	
	local value = true
	for _, actor in ipairs(actors) do
		--if typeof(actor:Read()) ~= "boolean" then error(`Only booleans are supported`) end
		value = value and actor:Read()
	end
	
	return value ~= nil and value ~= false
end

--[[
	AnyTrue Resolver
	
	Resolves to true if any actor is true. If no actor is true then resolves to false.
]]
function Resolvers.AnyTrue(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	
	local value = false
	for _, actor in ipairs(actors) do
		--if typeof(actor:Read()) ~= "boolean" then error(`Only booleans are supported`) end
		value = value or actor:Read()
	end
	
	return value ~= nil and value ~= false
end

--[[
	FirstSet Resolver

	Resolves to the value of the highest-priority actor.
]]
function Resolvers.FirstSet(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	
	-- Shift non-priority actors to the start of the list and keep high-priority actors at the end
	table.sort(actors, function(a: Actor, b: Actor)
		if not a.Priority then return true end
		if not b.Priority then return false end
		return a.Priority < b.Priority
	end)
	
	local highestValue: FluctValue
	for _, actor in ipairs(actors) do
		highestValue = actor:Read()
	end
	
	return highestValue
end

--[[
	LastSet Resolver

	Resolves to the value of the lowest-priority actor.
]]
function Resolvers.LastSet(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()

	-- Shift non-priority actors to the end of the list and keep high-priority actors at the start
	table.sort(actors, function(a: Actor, b: Actor)
		if not a.Priority then return false end
		if not b.Priority then return true end
		return a.Priority > b.Priority
	end)

	local lowestValue: FluctValue
	for _, actor in ipairs(actors) do
		lowestValue = actor:Read()
	end

	return lowestValue
end

--[[
	Single Resolver
	
	Resolves to the only actor present in the fluct. If the given fluct has more than 1 actor then it errors.
]]
function Resolvers.Single(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	
	if #actors > 1 then
		error(`Fluct has more than 1 actor`)
	end
	
	return actors[1]:Read()
end

--[[
	Random Resolver

	Resolves to a random actor present in the fluct. Can also work as a Single Resolver that doesnt error.
]]
function Resolvers.Random(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()
	return actors[math.random(1, #actors)]:Read()
end

--[[
	LinearTable Resolver

	Starts with the default value and applies the actors operations to the table. Goes from lowest priority to highest.
	Specify the operation type using the 'Operation' tag, which supports the following values:
	- "Insert"
	- "Remove" (Finds Actor.Value in the table and removes it if present)
	- "Set"
	- "SetKey={key_name}" (Sets key_name in the table to Actor.Value) 
]]
function Resolvers.LinearTable(fluct: Fluct): FluctValue
	local actors = fluct:GetActors()

	-- Shift non-priority actors to the start of the list and keep high-priority actors at the end
	table.sort(actors, function(a: Actor, b: Actor)
		if not a.Priority then return true end
		if not b.Priority then return false end
		return a.Priority < b.Priority
	end)

	local currentValue: {any} = fluct.DefaultValue
	
	if typeof(currentValue) ~= "table" then
		error(`Only table type is supported`)
	end

	-- Loop through all actors from lowest priority to highest priority
	for i, actor in ipairs(actors) do
		if not actor.ResolverTags then continue end
		if typeof(actor.Value) ~= "table" then error(`Only table type is supported`) end
		local operation = actor:GetTagValue("Operation")
		if operation == "Set" then
			currentValue = actor.Value
		elseif operation == "Remove" then
			local index = table.find(currentValue, actor:Read())
			if index then
				table.remove(currentValue, index)
			end
		elseif operation == "Insert" then
			table.insert(currentValue :: {any}, actor:Read())
		end
		local key = actor:GetTagValue("Key")
		if operation == "SetKey" and key then
			(currentValue :: any)[key] = actor:Read()
		end
	end

	return currentValue
end

-- Public functions

-- Create a new fluct object
-- PARAMETERS:
-- Id: string, DefaultValue: FluctValue, Resolver: (Fluct) -> FluctValue
function CreateFluct<V>(params: CreateFluctParams<V>): Fluct<V>
	assert(params.Resolver and typeof(params.DefaultValue) ~= "nil", `Invalid parameters`)
	
	local self = setmetatable({
		Value = params.DefaultValue,
		DefaultValue = params.DefaultValue,
		Resolver = params.Resolver,
		Actors = {},
		ValueChanged = Signal.New()
	}, Fluct) :: Fluct
	
	return self
end

-- Creates a new actor
-- PARAMETERS:
-- DefaultValue: FluctValue, UpdateSignal: Signal.Signal<FluctValue>?, Priority: number?, ResolverTags: {string}?
function CreateActor(params: CreateActorParams)
	assert(typeof(params.DefaultValue) ~= "nil", `Invalid parameters`)	
	local self = setmetatable({
		Value = params.DefaultValue,
		Priority = params.Priority,
		ResolverTags = params.ResolverTags,
		ValueChanged = Signal.New()
	}, Actor) :: Actor
	
	if params.UpdateSignal and params.UpdateSignal.Connect then
		self:ListenTo(params.UpdateSignal)
	end
	
	return self
end

-- Class Methods --
function Fluct:AddActor(actor: Actor): Fluct
	local self: Fluct = self
	local entry: ActorEntry = {
		Actor = actor,
		Connections = {}
	}
	
	table.insert(self.Actors, entry)
	table.insert(entry.Connections, actor.ValueChanged:Connect(function(new)
		if new == Flags.ActorDestroyed then
			self:RemoveActor(actor)
			return
		end
		if not self.Halted then
			self:Resolve()
		else
			self.Dirty = true
		end
	end))
	
	if not self.Halted then
		self:Resolve()
	else
		self.Dirty = true
	end
	
	return self
end

function Fluct:Resolve(): Fluct
	local self: Fluct = self
	
	if self.Halted then self.Dirty = true error(`Cannot resolve a halted fluct ({self})`) end
	
	self.Dirty = false
	
	local result = self.Resolver(self)
	
	if typeof(result) ~= typeof(self.Value) then self.Dirty = true error(`Could not resolve fluct: {typeof(self.Value)} expected, got  {typeof(result)}`) end
	
	local previous = self.Value
	self.Value = result
	
	-- TODO: Add deep-equal for tables (also update Actor:Update())
	if previous ~= result then
		self.ValueChanged:Fire(result)
	end
	
	return self
end

function Fluct:RemoveActor(actor: Actor): Fluct
	local self: Fluct = self
	local actors = self.Actors
	local entry: ActorEntry, index: number
	for i, v in ipairs(actors) do
		if v.Actor == actor then
			entry = v
			index = i
			break
		end
	end
	if entry then
		table.remove(actors, index)
		for _, v in ipairs(entry.Connections) do
			v:Disconnect()
		end
	end
	
	if not self.Halted then
		self:Resolve()
	else
		self.Dirty = true
	end
	
	return self
end

-- Update certain values within the properties of a fluct
function Fluct:SetProperties(values: {[string]: any})
	local self: Fluct = self
	self.Properties = self.Properties or {}
	if self.Properties then
		for key, value in pairs(values) do
			self.Properties[key] = value
		end
	end
end

function Fluct:Read(): FluctValue
	local self: Fluct = self
	if self.Dirty and not self.Halted then
		self:Resolve()
	end
	local cached = self.Value
	return cached
end

-- Disables the fluct from ever resolving until unhalted
function Fluct:Halt(is_halted: boolean?)
	local self: Fluct = self
	self.Halted = is_halted
	return self
end

function Fluct:GetActors(): {Actor}
	local self: Fluct = self
	local actors = self.Actors
	local actorList = {}
	for _, entry in ipairs(actors) do
		local actor = entry.Actor
		table.insert(actorList, actor)
	end
	return actorList
end

function Actor:ListenTo(update_signal: Signal.Signal<FluctValue>)
	local self: Actor = self
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self.Connection = update_signal:Connect(function(new)
		self:Update(new)
	end)
end

-- Similar to Actor:ListenTo but with a predicate that interpretates the signal's parameters
function Actor:ListenToPredicate(update_signal: Signal.Signal<...any>, predicate: (...any) -> (FluctValue?))
	local self: Actor = self
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self.Connection = update_signal:Connect(function(...)
		local new_value = predicate(...)
		if new_value ~= nil then
			self:Update(new_value)
		end
	end)
end

function Actor:Update(new_value: FluctValue)
	local self: Actor = self
	local oldValue = self.Value
	self.Value = new_value
	if new_value ~= oldValue then
		self.ValueChanged:Fire(new_value)
	end
end

function Actor:Read()
	local self: Actor = self
	if typeof(self.Value) == "function" then
		return self.Value(self)
	end
	return self.Value
end

function Actor:GetTagValue(tag: string)
	local self: Actor = self
	if not self.ResolverTags then return end
	return self.ResolverTags[tag]
end

function Actor:AddTag(tag: string, value: any)
	local self: Actor = self
	if not self.ResolverTags then
		self.ResolverTags = {}
	end
	if self.ResolverTags then
		self.ResolverTags[tag] = value
	end
end

function Actor:RemoveTag(tag: string)
	local self: Actor = self
	if not self.ResolverTags then return end
	self.ResolverTags[tag] = nil
end

function Actor:Destroy()
	local self: Actor = self
	self:Update(Flags.ActorDestroyed)
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

return {
	Fluct = CreateFluct,
	Actor = CreateActor,
	Resolvers = Resolvers
}
