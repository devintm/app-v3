Page = require "../Page"
SitePage = require './SitePage'
SitesLayer = require '../map/SitesLayer'
SiteLayerCreators = require '../map/SiteLayerCreators'
LocationDisplay = require '../map/LocationDisplay'
LocationFinder = require '../LocationFinder'
ContextMenu = require '../map/ContextMenu'
BaseLayers = require '../map/BaseLayers'
offlineMap = require 'offline-leaflet-map'
CacheProgressControl = require '../map/CacheProgressControl'
GeoJSON = require '../GeoJSON'

# Map of sites. Options include:
# initialGeo: Geometry to zoom to. Point only supported.
class SiteMapPage extends Page
  events:
    "click #goto_my_location": "gotoMyLocation"
    "click #new_site": -> 
      # defer to Allow menu to close first
      _.defer => @pager.openPage(require("./NewSitePage"))
    "click #new_survey": ->
      # defer to Allow menu to close first
      _.defer => @pager.openPage(require("./NewSurveyPage"))
    "click #new_test": -> 
      # defer to Allow menu to close first
      _.defer => @pager.openPage(require("./NewTestPage"))

  create: ->
    @setTitle T("Site Map")

    # Calculate height
    @$el.html require('./SiteMapPage.hbs')()

    # If initialGeo specified, use it
    if @options.initialGeo and @options.initialGeo.type == "Point"
      @createMap(L.GeoJSON.coordsToLatLng(@options.initialGeo.coordinates), 15)
      return

    # If saved view
    if window.localStorage['SiteMapPage.lastView']
      lastView = JSON.parse(window.localStorage['SiteMapPage.lastView'])
      @createMap(lastView.center, lastView.zoom, lastView.scope)
      return

    # Get current position if quickly available
    currentLatLng = null
    locationFinder = new LocationFinder()
    locationFinder.getLocation (pos) =>
      currentLatLng = new L.LatLng(pos.coords.latitude, pos.coords.longitude)

      @cacheNearbySites(pos)
    , ->
      # Do nothing on error
      currentLatLng = null

    # Wait very short time for location
    setTimeout =>
      if not @destroyed
        # If no location, create map with no location
        if currentLatLng
          @createMap(currentLatLng, 14)
        else
          @createMap()
    , 500

  # Since most uses use the map only, we need to cache local sites to the database.
  # This is done by simply querying them
  cacheNearbySites: (pos) ->
    selector = geo: 
      $near: { $geometry: GeoJSON.posToPoint(pos) }

    # Query database for near sources
    @db.sites.find(selector, { limit: 200 }).fetch (sites) =>
      # Just cache them
      return
    , @error

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

    onError = (errorType, errorData) =>
      if errorType == "COULD_NOT_CREATE_DB"
        console.log("Could not created DB.")
        @noDb = true
      else
        if @cacheProgressControl?
          if not @cacheProgressControl.cancelling
            @cacheProgressControl.cancel();
            
        if errorType == "NETWORK_ERROR"
          errorMsg = errorType + ":" + errorData
          console.log(errorMsg)
          @pager.flash(T("Network error. Unable to save image."), "danger")
        else if errorType == "ZOOM_LEVEL_TOO_LOW"
          alert(T("You are trying to save too large of a region of the map. Please zoom in further."))
        else if errorType == "SYSTEM_BUSY"
          alert(T("System is busy"))
        else
          errorMsg = errorType + ":" + errorData
          throw Error(errorMsg)

    # Setup base layers
    @osmLayer = BaseLayers.createOSMLayer(onReady, onError)
    @noDb = not @osmLayer.useDB()

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
      siteLayerCreator = new SiteLayerCreators.SimpleSitesLayerCreator @ctx, (_id) =>
        @pager.openPage(SitePage, {_id: _id})
      @sitesLayer = new SitesLayer(siteLayerCreator, @db.sites, scope).addTo(@map)
      # TODO remove legend
      # # Add legend
      # @legend = L.control({position: 'bottomright'});
      # @legend.onAdd = (map) ->
      #   return siteLayerCreator.createLegend()
      # @legend.addTo(@map)

      # Add My Location control
      @myLocation = L.control({position: 'topright'})
      @myLocation.onAdd = (map) ->
        html = '''
        <img id="goto_my_location" class="image-control" src="img/goto-my-location.png">
        '''
        return $(html).get(0)
      @myLocation.addTo(@map)

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
  getSiteScopeOptions: =>
    options = [{ display: T("All Sites"), type: "all", value: {} }]
    # Only show groups choice if user has groups
    if @login?
      if @login.groups.length > 0
        options.push { 
          display: T("Only My Groups")
          type: "groups"
          value: { "created.for": { $in: @login.groups } }
        }

      if @login.user?
        options.push { display: T("Only Mine"), type: "user", value: { "created.by": @login.user } }
    return options

  # Filter the sites by all, groups, or user
  updateSiteScope: (scope) => 
    # Update Map
    @sitesLayer.setScope scope.value
    @sitesLayer.update()

    # Update UI
    @configureButtonBars()

    # Persist the view
    @saveView()
    return

  saveView: => 
    window.localStorage['SiteMapPage.lastView'] = JSON.stringify({
      center: @map.getCenter() 
      zoom: @map.getZoom()
      scope: @sitesLayer.scope
    })

  gotoMyLocation: ->
    # Goes to current location
    locationHasBeenSetAtLeastOnce = false
    locationFinder = new LocationFinder()
    locationFinder.getLocation (pos) =>
      if not @destroyed
        latLng = new L.LatLng(pos.coords.latitude, pos.coords.longitude)
        # if the view has been set at least once (by a lower accuracy location)
        if locationHasBeenSetAtLeastOnce
          # do not set the view again if the higher accuracy location is inside the current view
          # the idea is to avoid setting the map view many times
          if @map.getBounds().contains(latLng)
            return

        zoom = @map.getZoom()
        @map.setView(latLng, if zoom > 15 then zoom else 15)
        locationHasBeenSetAtLeastOnce = true
    , =>
      if not @destroyed
        @pager.flash(T("Unable to determine location"), "warning")


  configureButtonBars: ->
    # Configure gear menu
    # Get the current scope to be used to set the active dropdown item
    currentScope = if @sitesLayer and @sitesLayer.scope then @sitesLayer.scope else {}

    # Create a dropdown menu using the Site Scope Options
    menu = @getSiteScopeOptions().map((scope) =>
      text: scope.display
      id: "site_scope_" + scope.type
      click: => @updateSiteScope scope
      checked: (JSON.stringify(currentScope) == JSON.stringify(scope.value))      
    )
    if not @noDb
      menu.push { separator: true }
      menu.push {
        text: T("Make Available Offline")
        click: => @cacheTiles()
      }

    @$("#gear_menu").html(require("./SiteMapPage_gearmenu.hbs")(menu: menu))

    @setupButtonBar [
      { icon: "buttonbar-gear.png", menu: menu }
      { text: T("List"), click: => @pager.closePage(require("./SiteListPage"))}  
    ]

  activate: ->
    @configureButtonBars()

    @resizeMap()
    
    # Update markers
    if @sitesLayer and @needsRefresh
      @sitesLayer.reset()
      @sitesLayer.update()
      needsRefresh = false

  deactivate: ->
    @needsRefresh = true

  destroy: ->
    if @cacheProgressControl 
      @cacheProgressControl.cancel()
      
    $(window).off('resize', @resizeMap)
    if @locationDisplay
      @locationDisplay.stop()

    # Destroy map
    if @map
      @map.remove()

  resizeMap: =>
    # TODO why does this prevent crashes?
    if not @map
      return

    # Calculate map height
    mapHeight = $("html").height() - 50 - 50
    $("#map").css("height", mapHeight + "px")
    @map.invalidateSize()

  cachingCompleted: ->
    @cacheProgressControl = null

  # Caches tiles and makes them available offline
  cacheTiles: ->
    if @cacheProgressControl?
      return
    maxNbTiles = 10000

    nbTiles = @osmLayer.calculateNbTiles();
    # nbTiles of -1 means an error occurred
    if nbTiles == -1
      return
    console.log("Would be saving: " + nbTiles + " tiles")

    zoomLimit = @map.getMaxZoom()
    console.log("Trying to save: " + nbTiles)

    minZoomLimit = 15
    while zoomLimit > minZoomLimit && nbTiles > maxNbTiles
      nbTiles /= 4
      zoomLimit--
      console.log("Lowered zoom level to: " + zoomLimit)
      console.log("Would now save: " + nbTiles)

    if nbTiles < maxNbTiles
      if not confirm T("Download approximately {0} MB of map data and make available offline?", Math.ceil(nbTiles*0.01))
        return

      # Add progress/cancel display
      @cacheProgressControl = new CacheProgressControl(@map, @osmLayer, this)

      # Save the tiles
      @cacheProgressControl.saveTiles(zoomLimit)
    else
      alert(T("You are trying to save too large of a region of the map. Please zoom in further."))


setupMapTiles = ->
  mapquestUrl = 'http://{s}.mqcdn.com/tiles/1.0.0/osm/{z}/{x}/{y}.png'
  subDomains = ['otile1','otile2','otile3','otile4']
  mapquestAttrib = 'Data, imagery and map information provided by <a href="http://open.mapquest.co.uk" target="_blank">MapQuest</a>, <a href="http://www.openstreetmap.org/" target="_blank">OpenStreetMap</a> and contributors.'
  return new L.TileLayer(mapquestUrl, {maxZoom: 18, attribution: mapquestAttrib, subdomains: subDomains})


module.exports = SiteMapPage