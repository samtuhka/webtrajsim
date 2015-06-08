P = require 'bluebird'

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

