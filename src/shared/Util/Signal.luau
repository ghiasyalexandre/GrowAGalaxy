--!strict
-- Small signal for module-to-module events (e.g. "profile loaded"). Listeners
-- run in their own threads, so one that errors or yields cannot block others.

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, listener: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { (T...) -> () } = {}

	local signal = {}

	function signal.Connect(_self: any, listener: (T...) -> ()): Connection
		table.insert(listeners, listener)
		local connection = {}
		function connection.Disconnect(_: any)
			local index = table.find(listeners, listener)
			if index then
				table.remove(listeners, index)
			end
		end
		return connection :: any
	end

	function signal.Fire(_self: any, ...: T...)
		for _, listener in table.clone(listeners) do
			task.spawn(listener, ...)
		end
	end

	return signal :: any
end

return Signal
