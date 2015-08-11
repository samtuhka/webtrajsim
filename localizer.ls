$ = require 'jquery'
seqr = require './seqr.ls'
livescript = require 'LiveScript'


module.exports = localizer = ->
	self = (msg, ...args) ->
		handler = self.mapping[msg] ? msg
		if not handler.apply?
			return handler
		return handler.apply self, args

	self <<<
		mapping: {}
		load: seqr.bind (file) ->*
			data = yield $.ajax file, dataType: "text"
			self.mapping <<< eval livescript.compile data,
				bare: true
				header: false
				filename: file
	return self

