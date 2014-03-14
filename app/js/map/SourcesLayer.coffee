GeoJSON = require '../GeoJSON'

module.exports = class SourcesLayer extends L.LayerGroup
  constructor: (sourceLayerCreator, sourcesDb) ->
    super()
    @sourceLayerCreator = sourceLayerCreator
    @sourcesDb = sourcesDb

    # Layers, by _id
    @layers = {}

  scope: {}

  onAdd: (map) =>
    super(map)
    @map = map
    map.on 'moveend', @update

  onRemove: (map) =>
    super(map)
    map.off 'moveend', @update

  update: =>
    # Pad to ensure scrolling shows nearby ones
    bounds = @map.getBounds().pad(0.1)
    selector = {}
    @boundsQuery bounds, selector
    @scopeQuery @scope, selector
    # TODO pass error?
    @getSources selector, @updateFromList

  reset: =>
    @clearLayers()
    @layers = {}    

  updateFromList: (sources, success, error) =>
    for source in sources
      # If layer exists, ignore
      if source._id of @layers
        continue

      # Call creator
      @sourceLayerCreator.createLayer source, (result) =>
        # Remove layer if exists
        if result.source._id of @layers
          @removeLayer(@layers[result.source._id])
          delete @layers[result.source._id]

        # Add layer
        @layers[result.source._id] = result.layer
        @addLayer(result.layer)
      , error

    # Remove layers not present
    sourceMap = _.object(_.pluck(sources, '_id'), sources)
    toRemove = []
    for id, layer of @layers
      if not (id of sourceMap)
        toRemove.push(id)

    for id in toRemove
      @removeLayer(@layers[id])
      delete @layers[id]

    success() if success?

  getSources: (selector, success, error) =>
    _this = this
    queryOptions =
      sort: ["_id"]
      limit: 200
      mode: "remote"
      fields:
        name: 1
        code: 1
        geo: 1
        type: 1
        org: 1
        user: 1

    @sourcesDb.find(selector, queryOptions).fetch success, error

  scopeQuery: (scope, selector) =>
    return unless scope
    if scope.user
      selector.user = scope.user
    else selector.org = scope.org  if scope.org
    return

  boundsQuery: (bounds, selector) =>
    return  unless bounds.isValid()
    return  if bounds.getWest() is bounds.getEast() or bounds.getNorth() is bounds.getSouth()
    boundsGeoJSON = GeoJSON.latLngBoundsToGeoJSON(bounds)
    if (boundsGeoJSON.coordinates[0][2][0] - boundsGeoJSON.coordinates[0][0][0]) >= 180
      return
    else if (boundsGeoJSON.coordinates[0][2][1] - boundsGeoJSON.coordinates[0][0][1]) >= 180
      return
    else if boundsGeoJSON.coordinates[0][0][0] < -180 or boundsGeoJSON.coordinates[0][0][0] > 180
      return
    else if boundsGeoJSON.coordinates[0][2][0] < -180 or boundsGeoJSON.coordinates[0][2][0] > 180
      return
    else if boundsGeoJSON.coordinates[0][0][1] < -90 or boundsGeoJSON.coordinates[0][0][1] > 90
      return
    else if boundsGeoJSON.coordinates[0][2][1] < -90 or boundsGeoJSON.coordinates[0][2][1] > 90
      return
    else
      selector.geo = $geoIntersects:
        $geometry: boundsGeoJSON
    return

  updateFromBounds: (bounds, success, error) =>
    # Success on empty/invalid bounds
    if not bounds.isValid()
      success() if success?
      return
    if bounds.getWest() == bounds.getEast() or bounds.getNorth() == bounds.getSouth()
      success() if success?
      return

    boundsGeoJSON = GeoJSON.latLngBoundsToGeoJSON(bounds)

    # Spherical Polygons must fit within a hemisphere.
    # Any geometry specified with GeoJSON to $geoIntersects or $geoWithin queries, must fit within a single hemisphere.
    # MongoDB interprets geometries larger than half of the sphere as queries for the smaller of the complementary geometries.
    # So... don't bother intersection if large
    # Also don't use intersection if outside of normal bounds (lat: [-90, 90], lng: [-180, 180])
    if (boundsGeoJSON.coordinates[0][2][0] - boundsGeoJSON.coordinates[0][0][0]) >= 180
      selector = {}
    else if (boundsGeoJSON.coordinates[0][2][1] - boundsGeoJSON.coordinates[0][0][1]) >= 180
      selector = {}
    else if boundsGeoJSON.coordinates[0][0][0] < -180 or boundsGeoJSON.coordinates[0][0][0] > 180
      selector = {}
    else if boundsGeoJSON.coordinates[0][2][0] < -180 or boundsGeoJSON.coordinates[0][2][0] > 180
      selector = {}
    else if boundsGeoJSON.coordinates[0][0][1] < -90 or boundsGeoJSON.coordinates[0][0][1] > 90
      selector = {}
    else if boundsGeoJSON.coordinates[0][2][1] < -90 or boundsGeoJSON.coordinates[0][2][1] > 90
      selector = {}
    else
      selector = { geo: { $geoIntersects: { $geometry: boundsGeoJSON } } }

    # Query sources with projection. Use remote mode so no caching occurs
    queryOptions = 
      sort: ["_id"]
      limit: 200
      mode: "remote"
      fields: { name: 1, code: 1, geo: 1, type: 1, org: 1, user: 1 }

    @sourcesDb.find(selector, queryOptions).fetch (sources) =>
      @updateFromList(sources, success, error)
