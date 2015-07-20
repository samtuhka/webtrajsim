export Signal = ({onAdd=->}={}) ->
	listeners = []

	signal = (cb) ->
		return if onAdd(cb) === false
		listeners.push cb

	signal.add = signal
	signal.dispatch = (...args) !->
		listeners := [.. for listeners when (.. ...args) !== false]
	signal.destroy = ->
		listeners := []
		signal.dispatch = -> false
	return signal
