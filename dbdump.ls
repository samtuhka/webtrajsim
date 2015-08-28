{Sessions} = require './datalogger.ls'
$ = require 'jquery'
{saveAs} = require './vendor/FileSaver.js'
JSZip = require 'jszip'
seqr = require './seqr.ls'

getSessionData = (db, session) ->
	db.entries.query().filter("sessionId", session.sessionSurrogateId).execute()

dump = (db, session) ->
	getSessiondata db, session
	.then (entries) ->
		blob = new Blob [JSON.stringify(entries)], type: "text/plain;charset=utf-8"
		saveAs blob, "#{session.name}_#{session.date}.json"

dumpAll = seqr.bind (db) ->*
	output = new JSZip()
	listing = yield db.sessions.query().all().execute()
	output.file('sessions.json', JSON.stringify(listing))
	for session in listing
		name = "#{session.name}_#{session.date}.json"
		console.log "Dumping", name
		data = yield getSessionData db, session
		output.file name, JSON.stringify data

	content = output.generate type: 'blob'
	saveAs content, "dbdump.zip"
$ ->
	db = undefined
	Sessions("wtsSessions").then (sessions) ->
		db := sessions.db
		$('#downloadAll').click ->
			dumpAll db
		db.sessions.query().all().execute()
	.then (listing) ->
		el = $('#sessionListing')
		for let session in listing
			link = $('<a href="#">').click -> dump db, session
			link.text "#{session.name}_#{session.date}"
			$("<li>").appendTo el .append link
