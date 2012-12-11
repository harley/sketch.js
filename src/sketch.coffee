# # Sketch.js (v0.0.2)
#
# **Sketch.js** is a simple jQuery plugin for creating drawable canvases
# using HTML5 Canvas. It supports multiple browsers including mobile
# devices (albeit with performance penalties).
#
# Sketch was originally written by Michael Bleigh from Intridea, Inc. More features are being added by Harley Trung, including tools to insert lines, rectangles, circles, text as well as additional operations for undoing, redoing and clearing the canvas

(($)->
  # ### jQuery('#mycanvas').sketch(options)
  #
  # Given an ID selector for a `<canvas>` element, initialize the specified
  # canvas as a drawing canvas. See below for the options that may be passed in.
  $.fn.sketch = (key, args...)->
    $.error('Sketch.js can only be called on one element at a time.') if this.length > 1
    sketch = this.data('sketch')

    # If a canvas has already been initialized as a sketchpad, calling
    # `.sketch()` will return the Sketch instance (see documentation below)
    # for the canvas. If you pass a single string argument (such as `'color'`)
    # it will return the value of any set instance variables. If you pass
    # a string argument followed by a value, it will set an instance variable
    # (e.g. `.sketch('color','#f00')`.
    if typeof(key) == 'string' && sketch
      if sketch[key]
        if typeof(sketch[key]) == 'function'
          sketch[key].apply sketch, args
        else if args.length == 0
          sketch[key]
        else if args.length == 1
          sketch[key] = args[0]
      else
        $.error('Sketch.js did not recognize the given command.')
    else if sketch
      sketch
    else
      this.data('sketch', new Sketch(this.get(0), key))
      this

  # ## Sketch
  #
  # The Sketch class represents an activated drawing canvas. It holds the
  # state, all relevant data, and all methods related to the plugin.
  class Sketch
    # ### new Sketch(el, opts)
    #
    # Initialize the Sketch class with a canvas DOM element and any specified
    # options. The available options are:
    #
    # * `toolLinks`: If `true`, automatically turn links with href of `#mycanvas`
    #   into tool action links. See below for a description of the available
    #   tool links.
    # * `defaultTool`: Defaults to `marker`, the tool is any of the extensible
    #   tools that the canvas should default to.
    # * `defaultColor`: The default drawing color. Defaults to black.
    # * `defaultSize`: The default stroke size. Defaults to 5.
    constructor: (el, opts)->
      @el = el
      @canvas = $(el)
      @context = el.getContext '2d'
      @options = $.extend {
        toolLinks: true
        defaultTool: 'marker'
        defaultColor: '#000000'
        defaultSize: 5
      }, opts
      @painting = false
      @color = @options.defaultColor
      @size = @options.defaultSize
      @tool = @options.defaultTool
      @actions = []
      @action = []
      @undone = []

      @canvas.bind 'click mousedown mouseup mousemove mouseleave touchstart touchmove touchend touchcancel mouseenter', @onEvent

      # ### Tool Links
      #
      # Tool links automatically bind `a` tags that have an `href` attribute
      # of `#mycanvas` (mycanvas being the ID of your `<canvas>` element to
      # perform actions on the canvas.
      if @options.toolLinks
        $('body').delegate "a[href=\"##{@canvas.attr('id')}\"]", 'click', (e)->
          $this = $(this)
          $canvas = $($this.attr('href'))
          sketch = $canvas.data('sketch')
          # Tool links are keyed off of HTML5 `data` attributes. The following
          # attributes are supported:
          #
          # * `data-tool`: Change the current tool to the specified value.
          # * `data-color`: Change the draw color to the specified value.
          # * `data-size`: Change the stroke size to the specified value.
          # * `data-font`: Font to use when data-tool='text' is used.
          # * `data-text`: Text to insert when data-tool='text' is used.
          # * `data-download`: Trigger a sketch download in the specified format.
          for key in ['color', 'size', 'tool', 'font', 'text']
            if $this.attr("data-#{key}")
              sketch.set key, $(this).attr("data-#{key}")
          if $(this).attr('data-download')
            sketch.download $(this).attr('data-download')
          if $(this).attr('data-operation')
            sketch.operation $(this).attr('data-operation')
          false

    # ### sketch.download(format)
    #
    # Cause the browser to open up a new window with the Data URL of the current
    # canvas. The `format` parameter can be either `png` or `jpeg`.
    download: (format)->
      window.open this.save(format)

    # ### sketch.save(format)
    #
    # Returns Data URL of the current canvas. The `format` parameter can be either
    # `png` or `jpeg`.
    save: (format)->
      format or= "png"
      format = "jpeg" if format == "jpg"
      mime = "image/#{format}"

      @el.toDataURL(mime)

    # ### sketch.set(key, value)
    #
    # *Internal method.* Sets an arbitrary instance variable on the Sketch instance
    # and triggers a `changevalue` event so that any appropriate bindings can take
    # place.
    set: (key, value)->
      this[key] = value
      @canvas.trigger("sketch.change#{key}", value)

    # ### sketch.startPainting()
    #
    # *Internal method.* Called when a mouse or touch event is triggered
    # that begins a paint stroke.
    startPainting: ->
      unless @painting
        @painting = true
        @action = {
          tool: @tool
          color: @color
          size: parseFloat(@size)
          events: []
        }

    # ### sketch.stopPainting()
    #
    # *Internal method.* Called when the mouse is released or leaves the canvas.
    stopPainting: ->
      @painting = false
      if @action
        @actions.push @action
        @action = null
        @redraw()

    # ### sketch.onEvent(e)
    #
    # *Internal method.* Universal event handler for the canvas. Any mouse or
    # touch related events are passed through this handler before being passed
    # on to the individual tools.
    onEvent: (e)->
      if e.originalEvent && e.originalEvent.targetTouches
        e.pageX = e.originalEvent.targetTouches[0].pageX
        e.pageY = e.originalEvent.targetTouches[0].pageY
      $.sketch.tools[$(this).data('sketch').tool].onEvent.call($(this).data('sketch'), e)
      e.preventDefault()
      false

    # ### sketch.redraw()
    #
    # *Internal method.* Redraw the sketchpad from scratch using the aggregated
    # actions that have been stored as well as the action in progress if it has
    # something renderable.
    redraw: ->
      @el.width = @canvas.width()
      @context = @el.getContext '2d'
      sketch = this
      $.each @actions, ->
        if this.tool
          $.sketch.tools[this.tool].draw.call sketch, this
      $.sketch.tools[@action.tool].draw.call sketch, @action if @painting && @action

    setupLine: (action)->
      @context.lineJoin = "round"
      @context.lineCap = "round"
      @context.lineWidth = action.size
      @context.strokeStyle = getColor action
      @context.fillStyle = getColor action

    # ### sketch.operation(mode)
    #
    # Support modes:
    # - clear: Clear all drawing on the canvas
    # - undo: Undo the most recent action
    # - redo: Redo an action if it has been undone before that
    operation: (mode)->
      switch mode
        when "clear"
          @actions = []
        when "undo"
          if @actions and @actions.length > 0
            @undone.push @actions.pop()
            # console.log "undoing", @undone
          else
            alert "Nothing to undo"
        when "redo"
          if @undone and @undone.length > 0
            @actions.push @undone.pop()
            # console.log "redoing", @actions
          else
            alert "Nothing to redo"

      @redraw()

  # # Tools
  #
  # Sketch.js is built with a pluggable, extensible tool foundation. Each tool works
  # by accepting and manipulating events registered on the sketch using an `onEvent`
  # method and then building up **actions** that, when passed to the `draw` method,
  # will render the tool's effect to the canvas. The tool methods are executed with
  # the Sketch instance as `this`.
  #
  # Tools can be added simply by adding a new key to the `$.sketch.tools` object.
  $.sketch = { tools: {} }

  # ## marker
  #
  # The marker is the most basic drawing tool. It will draw a stroke of the current
  # width and current color wherever the user drags his or her mouse.
  $.sketch.tools.marker =
    onEvent: (e)->
      #console.log e.type
      switch e.type
        when 'mousedown', 'touchstart'
          @startPainting()
        when 'mouseup', 'touchend', 'touchcancel'
          @stopPainting()
        #when 'mouseleave'
          #@mouse_outside = true
        #when 'mouseenter'
          #@mouse_outside = false
          # when 'mouseout'
          # ignore mouseout/mouseover
          # difference between mouseleave and mouseout don't apply here
          # http://www.mkyong.com/jquery/different-between-mouseout-and-mouseleave-in-jquery/

      if @painting
        @action.events.push
          x: e.pageX - @canvas.offset().left
          y: e.pageY - @canvas.offset().top
          event: e.type

        @redraw()

    draw: (action)->
      @setupLine action
      @context.beginPath()

      if action.events.length > 1
        @context.moveTo action.events[0].x, action.events[0].y
        for event in action.events
          @context.lineTo event.x, event.y
        @context.stroke()
      else if not @erasing
        # draw a single dot
        x = action.events[0].x
        y = action.events[0].y
        #@context.fillRect(x, y, action.size, action.size)
        @context.arc(x, y, action.size / 2, 0, Math.PI*2, true)
        @context.closePath()
        @context.fill()

  # ## eraser
  #
  # The eraser does just what you'd expect: removes any of the existing sketch.
  $.sketch.tools.eraser =
    onEvent: (e)->
      $.sketch.tools.marker.onEvent.call this, e
    draw: (action)->
      @erasing = true
      old_color  = action.color
      oldcomposite = @context.globalCompositeOperation
      @context.globalCompositeOperation = "copy"
      action.color = "rgba(0,0,0,0)"
      $.sketch.tools.marker.draw.call this, action
      @context.globalCompositeOperation = oldcomposite
      @erasing = false
      action.color = old_color

  # ## rectangle
  #
  # Draw a rectangle from the point clicked to the point released
  $.sketch.tools.rectangle =
    onEvent: $.sketch.tools.marker.onEvent
    draw: (action)->
      @setupLine action

      original = action.events[0]
      @context.moveTo original.x, original.y

      # only care about the last event
      event = action.events[action.events.length - 1]
      width = event.x - original.x
      height = event.y - original.y

      @context.strokeRect(original.x, original.y, width, height)

  # ## line
  #
  # Draw a line between mouseclicks
  $.sketch.tools.line =
    onEvent: $.sketch.tools.marker.onEvent
    draw: (action)->
      @setupLine action

      event = action.events[action.events.length - 1]

      @context.beginPath()
      @context.moveTo action.events[0].x, action.events[0].y
      @context.lineTo event.x, event.y
      @context.stroke()

  $.sketch.tools.circle =
    onEvent: $.sketch.tools.marker.onEvent

    draw: (action)->
      @setupLine action

      original = action.events[0]
      @context.moveTo action.events[0].x, action.events[0].y

      # only care about the last event
      event = action.events[action.events.length - 1]

      centerX = (event.x + original.x) / 2
      centerY = (event.y + original.y) / 2
      distance = Math.sqrt(Math.pow(event.x - original.x, 2) + Math.pow(event.y - original.y, 2)) / 2

      @context.beginPath()
      @context.arc(centerX, centerY, distance, Math.PI*2, 0, true)
      @context.stroke()
      @context.closePath()

  # ### Text
  #
  # Prompt for text to input at the position of cursor when clicking on canvas
  $.sketch.tools.text =
    onEvent: (e)->
      switch e.type
        when 'mouseup', 'touchend'
          @action = {
            tool: @tool
            color: @color
            size: parseFloat(@size)
            font: @font || 'normal 20px sans-serif'
            events: []
          }

          @action.events.push
            x: e.pageX - @canvas.offset().left
            y: e.pageY - @canvas.offset().top
            event: e.type
            text: @text || prompt("Enter text to insert")

          @actions.push @action
          @redraw()

    draw: (action) ->
      event = action.events[0]
      if event.text
        @setupLine action
        @context.font = action.font

        @context.fillStyle = getColor action

        @context.textBaseline = "middle"
        @context.fillText(event.text, event.x, event.y)

  randomNumber = ->
    Math.floor(Math.random() * 256)

  pickRandomColor = ->
    "rgb("+ randomNumber() + "," + randomNumber() + "," + randomNumber() + ")"

  getColor = (action)->
    if action.color == 'random'
      pickRandomColor()
    else
      action.color

)(jQuery)
