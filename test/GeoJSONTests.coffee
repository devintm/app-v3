assert = chai.assert
GeoJSON = require "../app/js/GeoJSON"

describe 'GeoJSON', ->
  it 'returns a proper polygon', ->
    southWest = new L.LatLng(10, 20)
    northEast = new L.LatLng(13, 23)
    bounds = new L.LatLngBounds(southWest, northEast)

    json = GeoJSON.latLngBoundsToGeoJSON(bounds)
    assert _.isEqual json, {
      type: "Polygon",
      coordinates: [
        [[20,10],[20,13],[23,13],[23,10],[20,10]]
      ]
    }

  it 'gets relative location N', ->
    from = { type: "Point", coordinates: [10, 20]}
    to = { type: "Point", coordinates: [10, 21]}
    str = GeoJSON.getRelativeLocation(from, to)
    assert.equal str, '111.2km N'

  it 'gets relative location S', ->
    from = { type: "Point", coordinates: [10, 20]}
    to = { type: "Point", coordinates: [10, 19]}
    str = GeoJSON.getRelativeLocation(from, to)
    assert.equal str, '111.2km S'
