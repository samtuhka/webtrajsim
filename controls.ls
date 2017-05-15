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

	close: ->
		@socket.onmessage = null
		@socket.close()

export class KeyboardController
	->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

		@throttleTarget = 0
		@brakeTarget = 0
		@steeringLeft = 0
		@steeringRight = 0

		@up = 0
		@down = 0
		@left = 0
		@right = 0

		changeSpeed = 2

		nudge = (dt, name, target) ~>
			return if not isFinite dt
			diff = target - @[name]
			change = dt*changeSpeed*Math.sign(diff)
			if diff < 0
				change = Math.max change, diff
			else
				change = Math.min change, diff
			@[name] += change

		@_closed = false
		prevTime = undefined
		tick = ~>
			return if @_closed
			time = Date.now()
			dt = (time - prevTime)/1000
			prevTime := time
			nudge dt, \throttle, @throttleTarget
			nudge dt, \brake, @brakeTarget
			nudge dt, \steering, (@steeringLeft - @steeringRight)
			requestAnimationFrame tick
		tick()
		@change = new Signal

		UP = 38
		DOWN = 40
		SPACE = 32
		LEFT = 37
		RIGHT = 39
		CTRL = 17
		Q = 81
		W = 87

		$("body")
		.keydown @_keydown = (e) ~>
			switch e.which
			| UP => @throttleTarget = 1 ; @_update 'up', 1
			| DOWN => @brakeTarget = 1 ; @_update 'down', 1
			| LEFT => @steeringLeft = 1; @_update 'left', 1
			| RIGHT => @steeringRight = 1; @_update 'right', 1
			| CTRL => @_update \blinder, true
			| SPACE => @_update \catch, true

		.keyup @_keyup = (e) ~>
			switch e.which
			| UP => @throttleTarget = 0 ; @_update 'up', 0
			| DOWN => @brakeTarget = 0 ; @_update 'down', 0
			| LEFT => @steeringLeft = 0 ; @_update 'left', 0
			| RIGHT => @steeringRight = 0 ; @_update 'right', 0
			| CTRL => @_update \blinder, false
			| SPACE => @_update \catch, false



	_update: (key, value) ->
		return if @[key] == value
		@change.dispatch key, value
		@[key] = value

	set: ->

	close: ->
		@_closed = true
		$("body")
		.off "keydown", @_keydown
		.off "keyup", @_keyup

export NonSteeringControl = (orig) ->
	ctrl = ^^orig
	ctrl.steering = 0
	return ctrl



export class TargetSpeedController
	(@target=0) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

	tick: (speed, dt, ang) ->
		delta = @target - speed
		force = Math.tanh delta
		if force > 0
			@throttle = force
			@brake = 0
		else
			@brake = force
			@throttle = 0
		@steering = ang

	set: ->


export class TargetSpeedController2
	(@target=0) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1

	tick: (speed, targetAccel, steerAng, idm, dt) ->
		force = DumbEngineModel targetAccel

		if idm == false 
			delta = @target - speed
			force = Math.tanh delta
		
		force = Math.max force, -1
		force = Math.min force, 1

		if force > 0
			@throttle = force
			@brake = 0
		else
			@brake = -force
			@throttle = 0
		@steering = steerAng

	set: ->


export class linearTargetSpeedController
	(@target=0, @accelParams=[1.0, 0.1], @targetAccelMs=2.0, @environment) ->
		@throttle = 0
		@brake = 0
		@steering = 0
		@direction = 1
		@_accel = 0
		@_speed = 0
		@_force = 0
		@_cumulative_error = 0
		@_pid_derivative = 0
		@_speedDelta = 0

		@_currentTarget = 0
		@_previousTarget = 0
		@_cumulativeTarget = 0

	tick: (speed, targAccel, steerAng, idm, dt) ->
		@_accel = (@_speed - speed)/dt
		@_speed = speed
		kp = @accelParams[0]
		ki = @accelParams[1]

		if @target != @_currentTarget
			@_previousTarget = @_currentTarget
			@_currentTarget = @target
			@_cumulativeTarget = @_previousTarget

		if (Math.abs @_currentTarget - @_cumulativeTarget) < 0.2 # at limit
			@_cumulativeTarget = @target
		else if @_currentTarget < @_previousTarget # decelerating
			@_cumulativeTarget -= @targetAccelMs * dt		
		else if @_currentTarget > @_previousTarget # accelerating
			@_cumulativeTarget += @targetAccelMs * dt

		target = @_cumulativeTarget


		speedDelta = target - speed
		errorDelta = @_speedDelta - speedDelta
		@_speedDelta = speedDelta
		@_pid_derivative = errorDelta / dt

		if target != 0
			@_cumulative_error += speedDelta * dt

		if target == 0 and speedDelta < 0.1 # stopping hack
			@_force = -0.5
		else
			targetAccel = kp * speedDelta + ki * @_cumulative_error			
			#targetAccel += 0.1 * @_cumulative_error #+ 2.0 * @_pid_derivative
			@_force = DumbEngineModel targetAccel

		if idm
			targetAccel = targAccel
			@_force = DumbEngineModel targetAccel
			
				
		@_force = Math.max @_force, -1
		@_force = Math.min @_force, 1
		if @_force > 0
			@throttle = @_force
			@brake = 0
		else
			@brake = -@_force
			@throttle = 0

		@steering = steerAng

		controllerInfo =
			targetSpeed: target
		@environment.logger.write controllerInfo

		#console.log 'speed', @_speed
		#console.log 'cumtarget', @_cumulativeTarget
		#console.log 'currentTarget', @_currentTarget
		#console.log 'previousTarget', @_previousTarget
		#console.log 'acceltarget', @targetAccelMs
		#console.log 'target', target
		#console.log 'kp, ki', kp, ki
		#console.log 'force', @_force

	set: ->

DumbEngineModel = (targetAccel) ->
	knots = [[-19.150852756939567, -0.86960922500437798], 
				[-10.0, -0.67314024428906383], 
				[-4.0, -0.53092823365752206], 
				[-2.5, -0.34978573520149692], 
				[-1.7, -0.097415037510977784], 
				[-1.2, 0.031117285095661945], 
				[0.0, 0.26398121786496032], 
				[3.0, 0.71245888265216406], 
				[5.2096257357368652, 0.93516331581155065]]

	if targetAccel < knots[0][0]
		force = knots[0][1]
	else if targetAccel > knots[knots.length-1][0]
		force = knots[knots.length-1][1]
	else
		for k, i in knots
			if k[0] > targetAccel
				break
		before = knots[i-1]
		after = knots[i]

		force = (targetAccel - before[0]) / (after[0] - before[0]) * (after[1] - before[1]) + before[1]
					
	#console.log targetAccel, force
	return force
