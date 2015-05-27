microsim = require './microsim.ls'
Three = require 'three'
$ = require 'jquery'

env = new microsim.LoopMicrosim 1000
for i in [0 til 10]
	#v = (new microsim.BandoVehicle)
	v = (new microsim.IdmVehicle)
	#v = new microsim.Delayer v, 0.3
	env.addVehicle(v)

class LoopPlotter
	(@container, @env) ->

	render: ->
		@container.empty()
		d = @env.radius*2
		relpos = (pos) ->
			(pos + d/2.0)/d*100

		for v, i in @env.vehicles
			pos = @env.position2d(v.position)
			e = $("<div>").css do
				"background-color": "black"
				position: "absolute"
				left: relpos(pos[0]) + "%"
				top: relpos(pos[1]) + "%"
				width: "10px"
				height: "10px"
			if i == 0
				$('#velocity').text v.velocity*3.6
				$('#acceleration').text v.acceleration
				$('#time').text env.time
				e.css "background-color": "red"
			@container.append e

$ ->
	speedup = 10
	el = $('#plothere')
	el.click ->
		env.addVehicle new microsim.IdmVehicle
	plotter = (new LoopPlotter el, env)
	update = ->
		plotter.render()
		for i in [0 til speedup]
			env.step 1/60
		requestAnimationFrame update
	update()
	#console.log env.vehicles[0]
	#env.step 1/60
	#console.log env.vehicles[0]
	#for i in [0 til 60]
	#	update!
	#update()
