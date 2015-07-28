{Sessions} = require './datalogger.ls'
$ = require 'jquery'
{saveAs} = require './vendor/FileSaver.js'

dump = (db, session) ->
	db.entries.query().filter("sessionId", session.sessionSurrogateId).execute()
	.then (entries) ->
		blob = new Blob [JSON.stringify(entries)], type: "text/plain;charset=utf-8"
		saveAs blob, "#{session.name}_#{session.date}.json"

$ ->
	db = undefined
	Sessions("wtsSessions").then (sessions) ->
		db := sessions.db
		db.sessions.query().all().execute()
	.then (listing) ->
		el = $('#sessionListing')
		for let session in listing
			link = $('<a href="#">').click -> dump db, session
			link.text "#{session.name}_#{session.date}"
			$("<li>").appendTo el .append link
