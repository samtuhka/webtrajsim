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

		@throttleTarget = 0
		@brakeTarget = 0
		@steeringTarget = 0

		prevTime = undefined
		tick = ~>
			time = Date.now()
			dt = (time - prevTime)/1000
			prevTime := time
			# TODO: Should depend on dt
			@throttle = @throttle*0.9 + @throttleTarget*0.1
			@brake = @brake*0.9 + @brakeTarget*0.1
			@steering = @steering*0.9 + @steeringTarget*0.1
			requestAnimationFrame tick
		tick()
		@change = new Signal

		UP = 38
		DOWN = 40
		SPACE = 32

		$("body")
		.keydown (e) ~>
			switch e.which
			| UP => @_update \throttleTarget, 1
			| DOWN => @_update \brakeTarget, 1
			| SPACE => @_update \blinder, true
		.keyup (e) ~>
			switch e.which
			| UP => @_update \throttleTarget, 0
			| DOWN => @_update \brakeTarget, 0
			| SPACE => @_update \blinder, false



	_update: (key, value) ->
		@change.dispatch key, value
		@[key] = value

	set: ->

