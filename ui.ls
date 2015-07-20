$ = require 'jquery'
P = require 'bluebird'
Co = P.coroutine
{template} = require 'lodash'
seqr = require './seqr.ls'

#NP = (...args) -> new P(...args)
#
#
export waitFor = (f) -> new P (accept) -> f (accept)

configTemplate = (data, config) ->
	el = $ data
	api = (name) -> el.find ".#name"
	api.el = el
	api.result = config.apply api, [el]
	return api

export gauge = ({notifications, uiUpdate}, {name, unit, range, value}) ->
	result = configTemplate (require './templates/gauge.lo.html!text'), ->
		@ \name .text name
		@ \unit .text unit
	notifications?append result.el
	uiUpdate ->
		result \value .text value!
	return result

#instructionTemplate = template require './templates/instruction.lo.html!text'
export instructionScreen = seqr.bind ({container, controls}, cb) ->*
	api = configTemplate (require './templates/instruction.lo.html!text'), cb
	el = api.el
	background = $('<div class="overlay-screen">')
	background.append el
	container.append background
	background.hide()

	btn = api \accept-button
	btn.prop "disabled", true
	api \accept .hide()

	yield waitFor background~fadeIn
	yield @get 'ready'

	btn.prop "disabled", false
	btn.focus()
	api \loading .hide()
	api \accept .show()

	yield new P (accept) -> btn.one "click", accept
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
