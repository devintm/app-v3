# Page that is displayed by the Pager. Pages have the following lifecycle:
# create, activate, [deactivate, activate...], deactivate, destroy
# Context is mixed in to the page object
# Static method "canOpen(ctx)", if present, can forbid opening page if it returns false
# Useful for displaying menus with page lists.
# destroyed is set true once page is destroyed

class Page extends Backbone.View
  constructor: (ctx, options={}) ->
    super(options)

    @destroyed = false

    # Save options
    @options = options

    # Save context
    @ctx = ctx

    # Mix in context for convenience
    _.defaults(@, ctx) 

    # Store subviews
    @_subviews = []

    # Setup default button bar
    @buttonBar = new ButtonBar()

    # Setup default context menu
    @contextMenu = new ContextMenu()

  className: "page"

  @canOpen: (ctx) -> true
  create: ->
  activate: ->
  deactivate: ->
  destroy: ->
  remove: ->
    @removeSubviews()
    super()

  getTitle: -> @title

  setTitle: (title) ->
    @title = title
    @trigger 'change:title'

  addSubview: (view) ->
    @_subviews.push(view)

  removeSubviews: ->
    for subview in @_subviews
      subview.remove()

  getButtonBar: ->
    return @buttonBar

  getContextMenu: ->
    return @contextMenu

  setupButtonBar: (items) ->
    # Setup button bar
    @buttonBar.setup(items)

  setupContextMenu: (items) ->
    # Setup context menu
    @contextMenu.setup(items)

# Standard button bar. Each item
# has optional "text", optional "icon" and "click" (action).
# For submenu, add array to "menu". One level nesting only. Submenu items can have "checked" true
# to check the item or "separator" true to put a separator instead
class ButtonBar extends Backbone.View
  events: 
    "click .menuitem" : "clickMenuItem"
    "click .buttonbar-item" : "clickMenuItem"

  setup: (items) ->
    # Because right floating reverses natural order
    @items = items.reverse()
    @itemMap = {}

    # Add id to all items if not present
    id = 1
    for item in items
      if not item.id?
        item.id = id
        id=id+1
      @itemMap[item.id] = item

      # Add to submenu
      if item.menu
        for subitem in item.menu
          if not subitem.id?
            subitem.id = id.toString()
            id=id+1
          @itemMap[subitem.id] = subitem

    @render()

  render: ->
    @$el.html require('./ButtonBar.hbs')(items: @items)

  clickMenuItem: (e) ->
    id = e.currentTarget.id
    item = @itemMap[id]
    if item.click?
      item.click()

# Context menu to go in slide menu
# Standard button bar. Each item "text", optional "glyph" (bootstrap glyph without glyphicon- prefix) and "click" (action).
class ContextMenu extends Backbone.View
  events: 
    "click .menuitem" : "clickMenuItem"

  setup: (items) ->
    @items = items
    @itemMap = {}

    # Add id to all items if not present
    id = 1
    for item in items
      if not item.id?
        item.id = id
        id=id+1
      @itemMap[item.id] = item

    @render()

  render: ->
    @$el.html require('./ContextMenu.hbs')(items: @items)

  clickMenuItem: (e) ->
    id = e.currentTarget.id
    item = @itemMap[id]
    if item.click?
      item.click()

module.exports = Page