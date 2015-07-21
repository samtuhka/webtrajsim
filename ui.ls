$ = require 'jquery'
P = require 'bluebird'
Co = P.coroutine
{template} = require 'lodash'
seqr = require './seqr.ls'

#NP = (...args) -> new P(...args)
#
#
export waitFor = (f) -> new P (accept) -> f (accept)

configTemplate = (data, config, parent) ->
	el = $ data
	if parent?
		parent.append el
	api = (name) -> el.find ".#name"
	api.el = el
	api.result = config.apply api, [el]
	return api

export gauge = ({notifications, uiUpdate}, {name, unit='', range, value}) ->
	result = configTemplate (require './templates/gauge.lo.html!text'), ->
		@ \name .text name
		@ \unit .text unit
	notifications?append result.el
	valel = result \value
	uiUpdate ->
		valel.text value!
	result <<<
		normal: ->
			result.el.css "background-color": ""
		warning: ->
			result.el.css "background-color": "rgba(242, 10, 10, 0.8)"

	return result

export instructionScreen = seqr.bind ({container, controls}, cb) ->*
	background = $('<div class="overlay-screen">')
	container.append background
	api = configTemplate (require './templates/instruction.lo.html!text'), cb, background

	btn = api \accept-button
	btn.prop "disabled", true
	api \accept .hide()

	yield waitFor background~fadeIn
	yield P.resolve api.result

	btn.prop "disabled", false
	btn.focus()
	api \loading .hide()
	api \accept .show()

	yield new P (accept) -> btn.one "click", accept
	yield new P (accept) -> background.fadeOut accept
	background.remove()

export inputDialog = seqr.bind ({container, controls}, cb) ->*
	api = configTemplate (require './templates/inputDialog.html!text'), cb
	el = api.el
	form = el.find "form"
	form.submit (e) ->
		e.preventDefault()
	background = $('<div class="overlay-screen">')
	background.append el
	container.append background
	background.hide()

	btn = api \accept-button
	yield waitFor background~fadeIn

	yield new P (a) ->
		btn.one "click", a
		form.one "submit", a
	yield new P (accept) -> background.fadeOut accept
	background.remove()

export taskDialog = Co ({notifications}, cb) ->*
	{el, result} = api = configTemplate (require './templates/helper.lo.html!text'), cb
	el.hide()
	notifications?append el
	yield waitFor el~fadeIn
	yield P.resolve result
	yield waitFor el~fadeOut
	el.remove()
