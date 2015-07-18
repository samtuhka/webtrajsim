{coroutine} = P = require 'bluebird'

defer = ->
	accept = void
	reject = void
	promise = new P (a, r) ->
		accept := a
		reject := r
	resolve: accept
	reject: reject
	promise: promise

seqr = (stepr) -> (...args) ->
	thunks = {}
	thunk = (name) ->
		thunks[name] ? thunks[name] = defer()

	ch =
		get: (name) -> thunk name .promise
		let: (name, value) -> thunk name .resolve value

	task = (coroutine stepr) ch, ...args
	task.finally ->
		for name, thunk of thunks
			if thunk.promise.isPending()
				thunk.reject "No value for '#name'"

	return task <<< ch

seqr.seqr = seqr
seqr.bind = bind = (g) -> seqr (ch, ...args) ->*
	yield from g.apply(ch, args)
module.exports = seqr
