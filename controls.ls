P = require 'bluebird'
$ = require 'jquery'
{Signal} = require './signal.ls'

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
		@change = new Signal
		@socket.onmessage = (msg) ~>
			event = JSON.parse msg.data
			for key, value of event
				@change.dispatch key, value
			@ <<< event

	set: (obj) ->
		@socket.send JSON.stringify obj

export class KeyboardController
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		
		@change = new Signal

		UP = 38
		DOWN = 40
		SPACE = 32

		$("body")
		.keydown (e) ~>
			switch e.which
			| UP => @_update \throttle, 1
			| DOWN => @_update \brake, 1
			| SPACE => @_update \blinder, true
		.keyup (e) ~>
			switch e.which
			| UP => @_update \throttle, 0
			| DOWN => @_update \brake, 0
			| SPACE => @_update \blinder, false
	
	_update: (key, value) ->
		@change.dispatch key, value
		@[key] = value

	set: ->

