$ = require 'jquery'
P = require 'bluebird'
Co = P.coroutine
{template} = require 'lodash'

#NP = (...args) -> new P(...args)
#
#
export waitFor = (f) -> new P (accept) -> f (accept)

configTemplate = (config, data) ->
	el = $ data
	api = (name) -> el.find ".#name"
	api.el = el
	loader = config.apply api, [el]
	return [api, loader]

#instructionTemplate = template require './templates/instruction.lo.html!text'
export instructionScreen = Co ({container, controls}, cb) ->*
	[api, loader] = configTemplate cb, require './templates/instruction.lo.html!text'
	el = api.el
	background = $('<div class="overlay-screen">')
	background.append el
	container.append background
	background.hide()

	btn = api \accept-button
	btn.prop "disabled", true
	api \accept .hide()

	yield waitFor background~fadeIn
	value = yield P.resolve loader

	btn.prop "disabled", false
	btn.focus()
	api \loading .hide()
	api \accept .show()

	yield new P (accept) -> btn.one "click", accept
	yield new P (accept) -> background.fadeOut accept
	background.remove()
	return value

export taskDialog = Co ({container}, cb) ->*
	[api, loader] = configTemplate cb, require './templates/helper.lo.html!text'
	el = api.el
	el.hide()
	container.append el
	yield waitFor el~fadeIn
	yield P.resolve loader
	yield waitFor el~fadeOut
	el.remove()
