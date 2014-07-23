cordovaSetup = require './cordovaSetup'

class Pager extends Backbone.View
  id: 'pager'

  # ctx can be undefined and set later via setContext
  constructor: (ctx) ->
    super()

    if ctx
      @setContext(ctx)

    # Create empty stack
    @stack=[]

    # Create button bar and context menu that change with page loads
    @buttonBar = new Backbone.View()
    @contextMenu = new Backbone.View()
    @listenTo this, 'change', =>
      # Swap items out for new page
      @buttonBar.$el.children().detach()
      @buttonBar.$el.append(_.last(@stack).getButtonBar().el)
 
      @contextMenu.$el.children().detach()
      @contextMenu.$el.append(_.last(@stack).getContextMenu().el)

    # Listen to backbutton
    document.addEventListener "backbutton", =>
      @closePage()
    , false

  setContext: (ctx) ->
    # Context contains pager
    ctx.pager = this

    # Save context
    @ctx = ctx

  # Adds a page from a constructor
  openPage: (pageClass, options) ->
    # Check canOpen
    if pageClass.canOpen
      if not pageClass.canOpen(@ctx)
        return
        
    # Create page
    page = new pageClass(@ctx, options)
    
    # Deactivate current page
    if @stack.length > 0
      _.last(@stack).deactivate()
      _.last(@stack).$el.detach()

    # Activate new page
    @stack.push(page)
    @$el.append(page.el)

    # Scroll to top
    window.scrollTo(0, 0)

    # Listen to page changes and bubble up
    @listenTo page, 'change', (options) ->
      @trigger 'change', options

    page.create()
    page.activate()

    console.log "Opened page #{pageClass.name} (" + JSON.stringify(options) + ")"

    # Indicate page change
    @trigger 'change'

  closePage: (replaceWith, options) ->
    # Prevent closing last page
    if not replaceWith and @stack.length <= 1
      return

    # Destroy current page
    page = _.last(@stack)

    console.log "Closing page #{page.constructor.name}"

    page.deactivate()
    page.destroyed = true
    page.destroy()
    page.remove()

    @stack.pop()

    # Scroll to top
    window.scrollTo(0, 0)

    # Open replaceWith
    if replaceWith
      @openPage replaceWith, options
    else
      page = _.last(@stack)

      @$el.append(page.el)
      page.activate()
      
    # Indicate page change
    @trigger 'change'

  # Close all pages and replace with
  closeAllPages: (replaceWith, options) ->
    while @multiplePages()
      @closePage()
    @closePage(replaceWith, options)

  # Gets page next down on the stack
  getParentPage: ->
    if @stack.length > 1
      return @stack[@stack.length - 2]
    return null

  # Get title of active page
  getTitle: ->
    _.last(@stack).getTitle()

  # Get buttonbar of active page
  getButtonBar: -> 
    return @buttonBar

  # Get context menu of active page
  getContextMenu: ->
    return @contextMenu

  # Determine if has multiple pages
  multiplePages: ->
    @stack.length > 1

  # Flash a message
  flash: (text, style="info", delay=3000) ->
    # Create flash message
    msg = $(_.template('''<div class="alert <% if (style) { %>alert-<%=style%><% } %> flash"><button type="button" class="close" data-dismiss="alert" aria-hidden="true">&times;</button><%=text%></div>''', { text:text, style:style }))

    # Add to pager
    @$el.prepend(msg)

    # Fade after x seconds
    setTimeout => 
      msg.slideUp(400, => msg.remove())
    , delay

module.exports = Pager