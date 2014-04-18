Page = require "../Page"
SourcePage = require './SourcePage'
SourcesLayer = require '../map/SourcesLayer'
SourceLayerCreators = require '../map/SourceLayerCreators'
LocationDisplay = require '../map/LocationDisplay'
LocationFinder = require '../LocationFinder'
ContextMenu = require '../map/ContextMenu'
BaseLayers = require '../map/BaseLayers'
offlineMap = require 'offline-leaflet-map'
CacheProgressControl = require '../map/CacheProgressControl'

# Map of water sources. Options include:
# initialGeo: Geometry to zoom to. Point only supported.
class SourceMapPage extends Page
  create: ->
    @setTitle T("Source Map")

    # Calculate height
    @$el.html require('./SourceMapPage.hbs')()

    # If initialGeo specified, use it
    if @options.initialGeo and @options.initialGeo.type=="Point"
      @createMap(L.GeoJSON.coordsToLatLng(@options.initialGeo.coordinates), 15)
      return

    # If saved view
    if window.localStorage['SourceMapPage.lastView']
      lastView = JSON.parse(window.localStorage['SourceMapPage.lastView'])
      @createMap(lastView.center, lastView.zoom, lastView.scope)
      return

    # Get current position if quickly available
    currentLatLng = null
    locationFinder = new LocationFinder()
    locationFinder.getLocation (pos) =>
      currentLatLng = new L.LatLng(pos.coords.latitude, pos.coords.longitude)
    , ->
      # Do nothing on error
      currentLatLng = null

    # Wait very short time for location
    setTimeout =>
      # If no location, create map with no location
      if currentLatLng
        @createMap(currentLatLng, 14)
      else
        @createMap()
    , 500

  createMap: (center, zoom, scope) ->
    # Fix leaflet image path
    L.Icon.Default.imagePath = "img/leaflet"

    options = {}
    # See issue https://github.com/mWater/app-v3/issues/103
    if navigator.userAgent.toLowerCase().indexOf('android 4.1.1') != -1 or navigator.userAgent.toLowerCase().indexOf('android 4.0.4') != -1
      options.touchZoom = false
      options.fadeAnimation = false

    options.minZoom = 2

    @map = L.map(this.$("#map")[0], options)
    L.control.scale(imperial:false).addTo(@map)
    @resizeMap()

    # Recalculate on resize
    $(window).on('resize', @resizeMap)

    onReady = () =>
      @osmLayer.addTo(@map)

    onError = (errorType, errorData1, errorData2) =>
      if @cacheProgressControl
        if not @cacheProgressControl.cancelling
          @cacheProgressControl.cancel();
          if errorType == "INDEXED_DB_BATCH"
            errorMsg = errorType
            throw Error(errorMsg)
          if errorType == "INDEXED_DB_GET"
            errorMsg = errorType + ":" + errorData1
            throw Error(errorMsg)
          if errorType == "GET_STATUS_ERROR"
            errorMsg = errorType + ":" + errorData1 + ":" + errorData2
            console.log(errorMsg)
          if errorType == "NETWORK_ERROR"
            errorMsg = errorType + ":" + errorData1 + ":" + errorData2
            console.log(errorMsg)
          alert(errorMsg)

    # Setup base layers
    @osmLayer = BaseLayers.createOSMLayer(onReady, onError)

    # satelliteLayer = BaseLayers.createSatelliteLayer() # TODO re-add

    # baseLayers = 
    #   "OpenStreetMap": osmLayer
    #   "Satellite": satelliteLayer

    # # Create layer control 
    # L.control.layers(baseLayers).addTo(@map)

    # # Create geocoder TODO READD
    # osmGeocoder = new L.Control.OSMGeocoder()
    # @map.addControl(osmGeocoder)

    # Setup marker display when map is loaded
    @map.whenReady =>
      ecoliAnalyzer = new SourceLayerCreators.EColiAnalyzer(@db)

      sourceLayerCreator = new SourceLayerCreators.EColi ecoliAnalyzer, (_id) =>
        @pager.openPage(SourcePage, {_id: _id})
      @sourcesLayer = new SourcesLayer(sourceLayerCreator, @db.sources, scope).addTo(@map)
      # Add legend
      @legend = L.control({position: 'bottomright'});
      @legend.onAdd = (map) ->
        return sourceLayerCreator.createLegend()
      @legend.addTo(@map)

    # Setup context menu
    contextMenu = new ContextMenu(@map, @ctx)
    
    # Setup initial zoom
    if center
      @map.setView(center, zoom)
    else
      @map.fitWorld()

    # Save view
    @map.on 'moveend', @saveView

    # Setup location display
    @locationDisplay = new LocationDisplay(@map)

  # Options for the dropdown menu
  getSourceScopeOptions: =>
    options = [{ display: T("All Sources"), type: "all", value: {} }]
    # Only show Organization choice if user has an org
    if @login?
      if @login.org?
        options.push { display: T("Only My Organization"), type: "org", value: { org: @login.org } }

      if @login.user?
        options.push { display: T("Only Mine"), type: "user", value: { user: @login.user } }
    return options

  # Filter the sources by all, org, or user
  updateSourceScope: (scope) => 
    # Update UI
    @getButtonBar().$(".dropdown-menu .menuitem.active").removeClass("active")
    @getButtonBar().$("#source-scope-" + scope.type).addClass("active")
    
    # Update Map
    @sourcesLayer.setScope scope.value
    @sourcesLayer.update()

    # Persist the view
    @saveView()
    return

  saveView: => 
    window.localStorage['SourceMapPage.lastView'] = JSON.stringify({
      center: @map.getCenter() 
      zoom: @map.getZoom()
      scope: @sourcesLayer.scope
    })

  gotoMyLocation: ->
    # Goes to current location
    locationFinder = new LocationFinder()
    locationFinder.getLocation (pos) =>
      latLng = new L.LatLng(pos.coords.latitude, pos.coords.longitude)
      zoom = @map.getZoom()
      @map.setView(latLng, if zoom > 15 then zoom else 15)
    , =>
      @pager.flash(T("Unable to determine location"), "warning")

  activate: ->
    # Get the current scope to be used to set the active dropdown item
    currentScope = if @sourcesLayer and @sourcesLayer.scope then @sourcesLayer.scope else {}
    # Create a dropdown menu using the Source Scope Options
    menu = @getSourceScopeOptions().map((scope) =>
      text: scope.display
      id: "source-scope-" + scope.type
      click: => @updateSourceScope scope
      checked: (JSON.stringify(currentScope) == JSON.stringify(scope.value))      
    )
    menu.push { separator: true }
    menu.push {
      text: T("Make Available Offline")
      click: => @cacheTiles()
    }

    @setupButtonBar [
      { icon: "gear.png", menu: menu }
      { icon: "goto-my-location.png", click: => @gotoMyLocation() }
    ]
    
    # Update markers
    if @sourcesLayer and @needsRefresh
      @sourcesLayer.reset()
      @sourcesLayer.update()
      needsRefresh = false

  deactivate: ->
    @needsRefresh = true

  destroy: ->
    $(window).off('resize', @resizeMap)
    if @locationDisplay
      @locationDisplay.stop()

  resizeMap: =>
    # Calculate map height
    mapHeight = $("html").height() - 50
    $("#map").css("height", mapHeight + "px")
    @map.invalidateSize()

  # Caches tiles and makes them available offline
  cacheTiles: ->
    nbTiles = @osmLayer.calculateNbTiles();
    console.log("Would be saving: " + nbTiles + " tiles")

    zoomLimit = @map.getMaxZoom()
    console.log("Trying to save: " + nbTiles)

    maxNbTiles = 10000
    minZoomLimit = 15
    while zoomLimit > minZoomLimit && nbTiles > maxNbTiles
      nbTiles /= 4
      zoomLimit--
      console.log("Lowered zoom level to: " + zoomLimit)
      console.log("Would now save: " + nbTiles)

    if nbTiles < 10000
      if not confirm T("Download approximately {0} K of map data and make available offline?", Math.ceil(nbTiles*10))
        return

      # Add progress/cancel display
      @cacheProgressControl = new CacheProgressControl(@map, @osmLayer)

      # Save the tiles
      @osmLayer.saveTiles(zoomLimit)
    else
      alert(T("You are trying to save too large of a region of the map. Please zoom in further."))


setupMapTiles = ->
  mapquestUrl = 'http://{s}.mqcdn.com/tiles/1.0.0/osm/{z}/{x}/{y}.png'
  subDomains = ['otile1','otile2','otile3','otile4']
  mapquestAttrib = 'Data, imagery and map information provided by <a href="http://open.mapquest.co.uk" target="_blank">MapQuest</a>, <a href="http://www.openstreetmap.org/" target="_blank">OpenStreetMap</a> and contributors.'
  return new L.TileLayer(mapquestUrl, {maxZoom: 18, attribution: mapquestAttrib, subdomains: subDomains})


module.exports = SourceMapPage