microsim = require './microsim.ls'
Three = require 'three'
$ = require 'jquery'
{jStat} = require 'jstat'
{sum, map} = require 'prelude-ls'

vGen = jStat.normal(100, 20)~sample
aGen = jStat.gamma(1.5, 1)~sample
n = 100
spacePerVehicle = 5
env = new microsim.LoopMicrosim n*spacePerVehicle
for i in [0 til n]
	#v = (new microsim.BandoVehicle)
	a = 1.5
	a = aGen!
	v = new microsim.IdmVehicle do
		#targetV: vGen!/3.6
		a: a
	#v = new microsim.Delayer v, 0.3
	v.position = i*env.radius/n
	env.addVehicle(v)



$ ->
	speedup = 100
	el = $('#plothere')
	v = env.vehicles[0]
	v.origTargetV = v.targetV
	el.click ->
		if v.targetV == 0
			v.targetV = v.origTargetV
		else
			v.targetV = 0
		#env.addVehicle new microsim.IdmVehicle
	plotter = (new microsim.LoopPlotter el, env)
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
