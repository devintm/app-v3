async = require 'async'
Page = require("../Page")
SourcePage = require("./SourcePage")
LocationFinder = require '../LocationFinder'
GeoJSON = require '../GeoJSON'


# Lists nearby and unlocated sources
# Options: onSelect - function to call with source doc when selected
module.exports = class SourceListPage extends Page
  events: 
    'click tr.tappable' : 'sourceClicked'
    'click #search_cancel' : 'cancelSearch'

  create: ->
    @setTitle T('Nearby Sources')

    # Create cache of thumbnail urls by image id
    @thumbnailUrls = {}

  activate: ->
    @$el.html require('./SourceListPage.hbs')()
    @nearSources = []
    @unlocatedSources = []

    # Find location
    @locationFinder = new LocationFinder()
    @locationFinder.getLocation(@locationFound, @locationError)
    @$("#location_msg").show()

    @setupButtonBar [
      { icon: "search.png", click: => @search() }
      { icon: "plus.png", click: => @addSource() }
    ]

    # Query database for unlocated sources
    if @login
      @db.sources.find(geo: { $exists: false }, user: @login.user).fetch (sources) =>
        @unlocatedSources = sources
        @renderList()

    @performSearch()

  addSource: ->
    # Wrap onSelect
    onSelect = undefined
    if @options.onSelect
      onSelect = (source) =>
        @pager.closePage()
        @options.onSelect(source)
    @pager.openPage(require("./NewSourcePage"), {onSelect: onSelect})
    
  locationFound: (pos) =>
    @$("#location_msg").hide()

    # Save position
    @pos = pos
    selector = geo: 
      $near: 
        $geometry: GeoJSON.posToPoint(pos)

    # Query database for near sources
    @db.sources.find(selector, { limit: 100 }).fetch (sources) =>
      @nearSources = sources
      @renderList()

  renderList: ->
    # Append located and unlocated sources
    if not @searchText
      sources = @unlocatedSources.concat(@nearSources)
    else
      sources = @searchSources

    # If there are photos, use the first one as the thumbnail
    sources.forEach (source) ->
      source.thumbnail = if source.photos and source.photos.length then source.photos[0].id else null
    
    # Query for source types
    @db.source_types.find({}).fetch (sourceTypes) =>
      # Create map of types
      typeMap = _.object(_.pluck(sourceTypes, "code"), sourceTypes)

      for source in sources
        type = typeMap[source.type]
        if type
          source.typeName = type.name
      @$("#table").html require('./SourceListPage_items.hbs')(sources:sources)

      # Look up image thumbnails
      async.eachLimit sources, 4, (source, callback) =>
        if source.thumbnail
          imageId = source.thumbnail
          do (imageId) =>
            if @thumbnailUrls[imageId]
              @$("#" + imageId).attr("src", @thumbnailUrls[imageId])
              callback()
            else
              @imageManager.getImageThumbnailUrl imageId, (imageUrl) =>
                @thumbnailUrls[imageId] = imageUrl
                @$("#" + imageId).attr("src", imageUrl)
                callback()
              , =>
                # Display this image on error
                @$("#" + imageId).attr("src", "img/no-image-icon.jpg")
                callback()
        else
          callback()

  locationError: (pos) =>
    @$("#location_msg").hide()
    @pager.flash T("Unable to determine location"), "danger"

  sourceClicked: (ev) ->
    # Wrap onSelect
    onSelect = undefined
    if @options.onSelect
      onSelect = (source) =>
        @pager.closePage()
        @options.onSelect(source)
    @pager.openPage(SourcePage, { _id: ev.currentTarget.id, onSelect: onSelect})

  search: ->
    # Prompt for search
    @searchText = prompt(T("Enter search text or ID of water source"))
    @performSearch()

  performSearch: ->
    @$("#search_bar").toggle(@searchText and @searchText.length>0)
    @$("#search_text").text(@searchText)
    if @searchText
      # If digits, search for code
      if @searchText.match(/^\d+$/)
        selector = { code: @searchText }
      else
        selector = { $or: [ { name: { $regex : @searchText,  $options: 'i' } }, { desc: { $regex : @searchText,  $options: 'i' } } ] }
        
      @db.sources.find(selector, {limit: 100}).fetch (sources) =>
        sourceScorer = (s) =>
          # Calculate score
          score = 0

          # Unlocated goes first
          if not s.geo?
            score += 1000000

          # Relative distance removes one point per km
          if s.geo? and @pos
            dist = GeoJSON.getDistance(s.geo, GeoJSON.posToPoint(@pos))
            score -= dist/1000

          # Name match is a 100000 bump
          if s.name.match(new RegExp(@searchText, "i"))
            score += 100000

          # Since sorts by score ascending
          return -score

        sources = _.sortBy sources, sourceScorer
        @searchSources = sources
        @renderList()
    else
      @renderList()

  cancelSearch: ->
    @searchText = ""
    @performSearch()

