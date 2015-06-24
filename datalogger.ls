dbjs = require 'db.js'

export Sessions = (name) ->
	dbjs.open do
		server: name
		version: 1
		schema:
			sessions: key: {keyPath: 'sessionSurrogateId', autoIncrement: true}
			entries: key: {autoIncrement: true}
	.then (db) ->
		return new _Sessions db

class _Sessions
	(@db) ->

	create: (info) ->
		@db.sessions.add info
		.then (entry) ~>
			return new Session @db, entry.sessionSurrogateId

class Session
	(@db, @sessionId) ->

	write: (data) ->
		@db.entries.add do
			sessionId: @sessionId
			time: Date.now() / 1000
			data: data
