$ = require 'jquery'
P = require 'bluebird'
seqr = require './seqr.ls'
{sum, sortBy, zip} = require 'prelude-ls'

loadBuffer = (url) -> new Promise (accept, reject) ->
	xhr = new XMLHttpRequest()
	xhr.open('GET', url, true);
	xhr.responseType = 'arraybuffer';

	xhr.onload = (e) ->
		accept xhr.response
	xhr.onerror = (e) ->
		reject e
	xhr.send()

loadAudio = (context, url) ->
	p = loadBuffer url
	p.then (data) -> new Promise (accept, reject) ->
		context.decodeAudioData data, (buffer) ->
			if not buffer
				reject "Failed to decode '#url'"
			accept buffer

export SoundInterpolator = (ctx, sampleTbl) -> new Promise (accept, reject) ->
	sources = []
	master = ctx.createBiquadFilter()
	master.type = 'lowpass'
	master.frequency.value = 300
	for value, buffer of sampleTbl
		sample = ctx.createBufferSource()
		sample.buffer = buffer
		sample.loop = 1
		source = ctx.createGain()
		sample.connect source
		source.sample = sample
		sources.push [parseFloat(value), source]
		source.connect master
	sources = sortBy (.0), sources
	master.start = ->
		for [value, source] in sources
			source.sample.start()
	master.stop = ->
		for [value, source] in sources
			source.sample.stop()
	master.setPitch = (pitch) ->
		gains = []
		for [value, source] in sources
			gains.push Math.exp -Math.abs((value - pitch)/1000)
		totalGain = sum gains
		gains = for gain in gains
			gain/totalGain
		for [gain, [value, source]] in zip gains, sources
			source.gain.value = gain
			source.sample.playbackRate.value = pitch/value

	master.setPitch sources[0][0]
	accept master

export DefaultEngineSound = (ctx) ->
	f = (name) -> loadAudio ctx, "./res/sounds/engine/#name.wav"
	P.props do
		780: f 'idle'
		1000: f '1000rpm'
		1700: f '1700rpm'
		2350: f '2350rpm'
		2600: f '2600rpm'
		3000: f '3000rpm'
	.then (samples) -> SoundInterpolator ctx, samples

export WarningSound = seqr.bind (env, {gain=0.1}={}) ->*
	{audioContext} = env
	buffer = yield loadAudio audioContext, './res/sounds/beep.wav'
	source = void
	self =
		start: ->
			return if source?
			source := audioContext.createBufferSource()
			source.buffer = buffer
			source.loop = true
			gainNode = audioContext.createGain()
			gainNode.gain.value = gain
			source.connect gainNode
			gainNode.connect audioContext.destination
			source.start()
		stop: ->
			return if not source?
			source.stop()
			source := void

		isPlaying:~ -> source?
	return self


export BellPlayer = seqr.bind ({audioContext}) ->*
	ctx = audioContext
	buffer = yield loadAudio audioContext, './res/sounds/bell.ogg'
	seqr.bind ({gain=1.0}={}) ->*
		sample = ctx.createBufferSource()
		sample.buffer = buffer
		source = ctx.createGain()
		source.gain.value = gain
		sample.connect source
		source.connect audioContext.destination
		sample.start()
		yield new P (accept) ->
			sample.onended = accept

export NoisePlayer = seqr.bind ({audioContext}) ->*
	ctx = audioContext
	buffer = yield loadAudio audioContext, './res/sounds/noiseburst.wav'
	seqr.bind ({gain=1.0}={}) ->*
		sample = ctx.createBufferSource()
		sample.buffer = buffer
		source = ctx.createGain()
		source.gain.value = gain
		sample.connect source
		source.connect audioContext.destination
		sample.start()
		yield new P (accept) ->
			sample.onended = accept
