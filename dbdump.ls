{Sessions} = require './datalogger.ls'
$ = require 'jquery'
{saveAs} = require './vendor/FileSaver.js'
seqr = require './seqr.ls'
msgpack = require 'msgpack-lite'
pako = require 'pako'

getSessionData = (db, session) ->
	db.entries.query('sessionId').only(session.sessionSurrogateId).execute()

getSerializedSession = (db, session) ->
	console.log "Loading"
	getSessionData db, session
	.then (entries) ->
		console.log "Serializing"
		output = new pako.Deflate gzip: true
		for entry in entries
			output.push msgpack.encode entry
		output.push "", true
		console.log output.result
		return new Blob [output.result], type: "application/x-gzip"
		return new Blob blob, type: "application/x-msgpack"

dump = (db, session) ->
	console.log "Dumping", "#{session.name}_#{session.date}.msgpack"
	getSerializedSession db, session
	.then (blob) -> new Promise (accept, reject) ->
		console.log "Saving"
		accept() # A hack as there seems to be no way of knowing when the saving is done
		saveAs blob, "#{session.name}_#{session.date}.msgpack.gz"


readBlob = (blob) -> new Promise (accept, reject) ->
	reader = new FileReader()
	reader.onload = ->
		accept new Uint8Array @result
	reader.readAsArrayBuffer blob

dumpAll = seqr.bind (db) ->*
	listing = yield db.sessions.query().all().execute()
	#output.file('sessions.json', JSON.stringify(listing))
	for session in listing
		yield dump db, session

	console.log "All done"

	/*
	for session in listing
		name = "#{session.name}_#{session.date}.msgpack"
		console.log "Dumping", name
		blob = yield getSerializedSession db, session
		blob = yield readBlob blob
		if blob.length == 0
			continue
		output.file name, blob

	content = output.generate type: 'blob'
	saveAs content, "dbdump.zip"
	*/
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
