P = require 'bluebird'
$ = require 'jquery'

export class WsController
	@Connect = (url) -> new P (resolve, reject) ->
		socket = new WebSocket url
		socket.onopen = ->
			resolve new WsController socket

	(@socket) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		@socket.onmessage = (msg) ~>
			@ <<< JSON.parse msg.data

	set: (obj) ->
		@socket.send JSON.stringify obj

export class KeyboardController
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

		UP = 38
		DOWN = 40

		$("body")
		.keydown (e) ~>
			switch e.which
			| UP => @throttle = 1
			| DOWN => @brake = 1
		.keyup (e) ~>
			switch e.which
			| UP => @throttle = 0
			| DOWN => @brake = 0

	set: ->

