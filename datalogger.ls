dbjs = require 'db.js'

export Sessions = (name) ->
	dbjs.open do
		server: name
		version: 2
		schema:
			sessions: key: {keyPath: 'sessionSurrogateId', autoIncrement: true}
			entries:
				key: {autoIncrement: true}
				indexes:
					sessionId: {}
	.then (db) ->
		return new _Sessions db

class _Sessions
	(@db) ->

	create: (info) ->
		@db.sessions.add info
		.then ([entry]) ~>
			return new Session(@db, entry.sessionSurrogateId)

class Session
	(@db, @sessionId) ->
		@_queue = []
		@_pending = void

	write: (data) ~>
		@_queue.push do
			sessionId: @sessionId
			time: Date.now() / 1000
			data: data
		@_flush!

	_flush: ~>
		return if @_pending
		if @_queue.length == 0
			return

		buffer = @_queue
		@_queue = []

		buflen = buffer.length
		startTime = Date.now()
		@_pending = @db.entries.add ...buffer

		reschedule = ~>
			duration = (Date.now() - startTime)/1000
			#console.log "Flushed", buflen, "in", buflen/duration, "entries/second"
			@_pending = void
			setTimeout @_flush, 0
		@_pending.then reschedule, reschedule

