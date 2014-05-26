Page = require("../Page")

# Lists detected sensors
module.exports = class SensorListPage extends Page
  events: 
    'click tr.tappable' : 'sensorClicked'

  create: ->
    @setTitle T('Sensors')

  activate: ->
    if not window.bluetooth or not window.bluetooth.isConnectionManaged
      alert(T("Only available on Android app"))
      return @pager.closePage()

    # Start with no devices. Key by address
    @devices = {}

    # Store discovery attempt number
    @discoveryAttempt = 0

    @discoverDevices()

  deactivate: ->
    if @discovering
      window.bluetooth.stopDiscovery () =>
        # Do nothing
        return
      , @error

  discoverDevices: ->
    @discovering = true
    @discoveryAttempt += 1
    window.bluetooth.startDiscovery(@onDeviceDiscovered, @onDiscoveryFinished, @onDiscoveryError)
    @render()

  onDiscoveryFinished: =>
    @discovering = false
    @render()
    @discoverDevices()

  onDiscoveryError: (error) =>
    @bluetoothError = T("Unable to connect to Bluetooth")
    @render()

  onDeviceDiscovered: (device) =>
    # Store discovery attempt number to cull old ones
    device.attempt = @discoveryAttempt
    @devices[device.address] = device
    @render()

  render: ->
    data = {
      devices: _.values(@devices)
      error: @bluetoothError
      attempt: @discoveryAttempt
    }
    @$el.html require('./SensorListPage.hbs')(data)

  sensorClicked: (ev) ->
    @pager.openPage(require("./SensorPage"), { address: ev.currentTarget.id})
    return

