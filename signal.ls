export Signal = ({onAdd=->}={}) ->
	listeners = []

	signal = (cb) ->
		return if onAdd(cb) === false
		listeners.push cb

	signal.add = signal
	signal.dispatch = (...args) !->
		oldListeners = listeners
		listeners := []
		survivors = [.. for oldListeners when (.. ...args) !== false]
		listeners := survivors.concat listeners
	signal.destroy = ->
		listeners := []
		signal.dispatch = -> false
	return signal
