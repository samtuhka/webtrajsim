$ = require 'jquery'
P = require 'bluebird'
Co = P.coroutine
{template} = require 'lodash'
seqr = require './seqr.ls'

#NP = (...args) -> new P(...args)
#
#
export waitFor = (f) -> new P (accept) -> f (accept)
export sleep = (duration) -> new P (accept) -> setTimeout accept, duration*1000

configTemplate = (data, config, parent) ->
	el = $ data
	if parent?
		parent.append el
	api = (name) -> el.find ".#name"
	api.el = el
	api.result = config.apply api, [el]
	return api

export gauge = ({notifications, uiUpdate}, {name, unit='', range, value, format=(v) -> v}) ->
	result = configTemplate (require './templates/gauge.lo.html!text'), ->
		@ \name .text name
		@ \unit .text unit
	notifications?append result.el
	valel = result \value
	uiUpdate ->
		valel.text format value!
	if range
		bar = result \value-bar
		.show()
		.find('progress')
		.attr(min: range[0], max: range[1])
		uiUpdate ->
			val = value!
			if val? and isFinite val
				bar.val val
			else
				bar.val ""



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

	btn.one "click", ~> @let \accept
	controls.change (btn, isOn) !~>
		if btn == 'catch' and isOn
			@let \accept
			return false
	yield @get \accept

	yield new P (accept) -> background.fadeOut accept
	background.remove()

export inputDialog = seqr.bind ({container, controls, logger}, cb) ->*
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

	canceled = false
	api(\cancel-button).click ->
		canceled := true

	yield waitFor background~fadeIn
	form.on "submit" (e) ~>
		result =
			canceled: canceled
			formData: form.serializeArray()
		logger.write result
		@let \result, result

	result = yield @get \result
	yield new P (accept) -> background.fadeOut accept
	background.remove()
	return result

export taskDialog = Co ({notifications}, cb) ->*
	{el, result} = api = configTemplate (require './templates/helper.lo.html!text'), cb
	el.hide()
	notifications?append el
	yield waitFor el~fadeIn
	yield P.resolve result
	yield waitFor el~fadeOut
	el.remove()



