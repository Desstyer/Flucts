-- Modified by @Desstyer
-- Added Signal.Is

local FreeRunnerThread: thread?

-- Private Functions --

--[[
	Yield-safe coroutine reusing by stravant;
	Sources:
	https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063
	https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f
--]]

local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquired_runner_thread = FreeRunnerThread
	FreeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	FreeRunnerThread = acquired_runner_thread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

-- Types --

export type Connection = {
	Disconnect: (self: Connection) -> (),
	IsConnected: boolean,
}

export type Signal<T...> = {
	Connect: (self: any, fn: (T...) -> ()) -> Connection,
	Wait: (self: any) -> T...,
	Fire: (self: any, T...) -> (),
	FireUntil: (self: any, continue_callback: () -> boolean, T...) -> (),
}

-- Constants --

local Connection = {}
Connection.__index = Connection

local Signal = {}
Signal.__index = Signal

-- Public Functions --

function Signal.Is(object: any): boolean
	return getmetatable(object) == Signal
end

function Signal.New<T...>(): Signal<T...>

	local self = {
		head = nil,
	}
	setmetatable(self, Signal)

	return self
end

-- Class Methods --

function Connection:Disconnect()
	if self.IsConnected == false then
		return
	end

	local signal = self.signal
	self.IsConnected = false

	if signal.head == self then
		signal.head = self.next
	else
		local prev = signal.head
		while prev ~= nil and prev.next ~= self do
			prev = prev.next
		end
		if prev ~= nil then
			prev.next = self.next
		end
	end
end

function Signal:Connect(listener: (...any) -> ())
	if type(listener) ~= "function" then
		error(`[{script.Name}]: \"listener\" must be a function; got '{typeof(listener)}'`)
	end

	local connection = {
		listener = listener,
		signal = self,
		next = self.head,
		IsConnected = true,
	}
	setmetatable(connection, Connection)

	self.head = connection

	return connection
end

function Signal:Fire(...)
	local item = self.head
	while item ~= nil do
		if item.IsConnected == true then
			if not FreeRunnerThread then
				FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
			end
			task.spawn(FreeRunnerThread :: thread, item.listener, ...)
		end
		item = item.next
	end
end

function Signal:Wait()
	local co = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(co, ...)
	end)
	return coroutine.yield()
end

function Signal:FireUntil(continue_callback: () -> boolean, ...)

	if type(continue_callback) ~= "function" then
		error(`[{script.Name}]: \"continue_callback\" must be a function; got '{typeof(continue_callback)}'`)
	end

	local items = {}
	local args = table.pack(...)

	local item = self.head
	while item ~= nil do
		table.insert(items, item)
		item = item.next
	end

	task.spawn(function()
		for _, check_item in ipairs(items) do
			if check_item.IsConnected == true then
				check_item.listener(table.unpack(args))
				if continue_callback() ~= true then
					return
				end
			end
		end
	end)

end

return table.freeze({
	New = Signal.New,
	Is = Signal.Is
})
