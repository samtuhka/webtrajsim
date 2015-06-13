export class Signal
	->
		@listeners = []

	add: (cb) ->
		@listeners.push cb

	dispatch: (...args) ->
		for listener in @listeners
			listener ...args

