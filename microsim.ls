{sortBy, maximumBy} = require 'prelude-ls'

# OMG! https://code.google.com/p/v8/issues/detail?id=3495
tanh = (x) ->
	r = Math.tanh x
	if r != r
		return Math.sign x
	return r

# http://arxiv.org/pdf/patt-sol/9805002
export class BandoVehicle
	(@aMultiplier=2.0) ->
		# TODO: Allow parametrization

	step: ({dx, v}) ->
		targetV = 16.8*tanh(0.0860*(dx - 25)) + 0.913
		a = @aMultiplier*(targetV - v)
		return a

#http://arxiv.org/pdf/cond-mat/0002177v2.pdf
export class IdmVehicle
	({
		@targetV=120/3.6
		@timeHeadway=1.6
		@minimumGap=2.0
		#@a=0.73
		@a=2.0
		@b=3.0
		@accelExp=4.0
	}={}) ->

	step: ({dx, dv, v}) ->
		freeAccel = (v/@targetV)**@accelExp
		desiredGap = @minimumGap + @timeHeadway*v + v*dv/(2*Math.sqrt(@a*@b))
		a = @a*(1 - freeAccel - (desiredGap/dx)**2)
		return a

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
			v.acceleration = v.step do
				dt: dt
				dx: v.headway
				v: v.velocity
				dv: v.velocityDiff
			v.velocity += v.acceleration*dt
			v.position += v.velocity*dt
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

