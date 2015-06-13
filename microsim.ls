{sum, map, sortBy, maximumBy} = require 'prelude-ls'
$ = require 'jquery'

# OMG! https://code.google.com/p/v8/issues/detail?id=3495
tanh = (x) ->
	r = Math.tanh x
	if r != r
		return Math.sign x
	return r

export class Vehicle
	->
		@position = 0
		@velocity = 0
		@acceleration = 0
		@leader = undefined

	step: ->

# http://arxiv.org/pdf/patt-sol/9805002
/*export class BandoVehicle extends Vehicle
	(@aMultiplier=2.0) ->
		# TODO: Allow parametrization

	step: ({dx, v}) ->
		targetV = 16.8*tanh(0.0860*(dx - 25)) + 0.913
		a = @aMultiplier*(targetV - v)
		return a
*/

#http://arxiv.org/pdf/cond-mat/0002177v2.pdf
export class IdmVehicle extends Vehicle
	({
		@targetV=120/3.6
		@timeHeadway=1.6
		@minimumGap=2.0
		#@a=0.73
		@a=1.5
		@b=3.0
		@accelExp=4.0
	}={}) ->

	step: ({dt, dx, dv, v}) ->
		freeAccel = (v/@targetV)**@accelExp
		if freeAccel > 1
			freeAccel = 1
		desiredGap = @minimumGap + @timeHeadway*v + v*dv/(2*Math.sqrt(@a*@b))
		@acceleration = @a*(1 - freeAccel - (desiredGap/dx)**2)
		@velocity += @acceleration*dt
		@position += @velocity*dt



export class Delayer
	(@model, @delay=0.3) ->
		@t = 0
		@buffer = []

	step: (state) ->
		dt = state.dt
		@t += dt
		@buffer.push do
			t: (@t + @delay)
			state: state
		a = 0
		while @buffer.length > 0 and @buffer[0].t <= @t
			old = @buffer.shift!
			a = @model.step old.state
		return a

export class LoopMicrosim
	(@radius=1000) ->
		@vehicles = []
		@time = 0

	_updateCircle: ->
		for v in @vehicles
			fullRounds = Math.floor(v.position/@radius)
			v.circlePosition = v.position - @radius*fullRounds
		sorted = sortBy (.circlePosition), @vehicles
		for i in [0 til sorted.length]
			v = sorted[i]
			v.leader = sorted[(i+1)%sorted.length]
			d = v.leader.circlePosition - v.circlePosition
			if d <= 0
				d += @radius
			v.headway = d
			v.velocityDiff = v.velocity - v.leader.velocity

	step: (dt) ->
		@_updateCircle! # TODO: Not really necessary on every step
		for v in @vehicles
			v.step do
				dt: dt
				dx: v.headway
				v: v.velocity
				dv: v.velocityDiff
		@time += dt

	position2d: (position) ->
		angle = position/@radius*Math.PI*2
		return [Math.sin(angle)*@radius, Math.cos(angle)*@radius]

	bestNewPosition: ->
		@_updateCircle!
		follower = maximumBy (.headway), @vehicles
		if not follower?
			return 0
		return follower.position + follower.headway/2.0

	addVehicle: (v) ->
		v.position ?= @bestNewPosition!
		v.velocity ?= 0
		v.acceleration ?= 0
		@vehicles.push v
		@_updateCircle!

	isInStandstill: ->
		return false if @time == 0
		maxvel = Math.max ...map Math.abs, (map (.velocity), @vehicles)
		maxaccel = Math.max ...map Math.abs, (map (.acceleration), @vehicles)
		return maxaccel < 1 and maxvel < 1

export class LoopPlotter
	(@container, @env) ->

	render: ->
		@container.empty()
		d = @env.radius*2
		relpos = (pos) ->
			(pos + d/2.0)/d*100

		vs = @env.vehicles
		meanVelocity = sum map (.velocity*3.6/vs.length), vs
		for v, i in vs
			pos = @env.position2d(v.position)
			e = $("<div>").css do
				"background-color": "black"
				position: "absolute"
				left: relpos(pos[0]) + "%"
				top: relpos(pos[1]) + "%"
				width: "10px"
				height: "10px"
			if v.higlight
				$('#velocity').text v.velocity*3.6
				$('#acceleration').text v.acceleration
				$('#time').text @env.time
				$('#meanvelocity').text meanVelocity
				e.css "background-color": "red"
			@container.append e
