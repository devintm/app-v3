Page = require "../Page"
ECPlates = require '../forms/ECPlates'
cordovaSetup = require '../cordovaSetup'
async = require 'async'
login = require '../login'
context = require '../context'

class SettingsPage extends Page
  events: 
    "click #reset" : "reset"
    "click #request_site_codes": "requestSiteCodes"
    "click #test_ecplates" : "testECPlates"
    # "click #weinre" : "startWeinre"
    "change #locale": "setLocale"
    "click #update": "updateApp"
    "click #logout": "logout"
    "click #test_barcode_scanner": "testBarcodeScanner"

  activate: ->
    @setTitle T("Settings")
    @render()

    # Listen to events from app updater
    if cordovaSetup.appUpdater
      @listenTo cordovaSetup.appUpdater, "success error progress start", =>
        @render()

    # Rerender on error/success of sync
    if @dataSync?
      @listenTo @dataSync, "success error", =>
        @render()

    if @imageSync?
      @listenTo @imageSync, "success error", =>
        @render()

  render: ->
    # Determine if base app out of date
    if @baseVersion and @baseVersion.match(/^3\.[0-9]\./)
      outdated = true

    # Determine data sync status
    if @dataSync?
      if @dataSync.inProgress
        dataSyncText = T("In progress...")
        dataSyncClass = "muted"
      else if @dataSync.lastError
        # Check if jQuery ajax error
        if @dataSync.lastError.status?
          # If connection error
          if @dataSync.lastError.status == 0
            dataSyncText = T("No connection")
            dataSyncClass = "warning"
          else if @dataSync.lastError.status >= 500
            dataSyncText = T("Server error")
            dataSyncClass = "danger"
          else if @dataSync.lastError.status >= 400
            dataSyncText = T("Upload error")
            dataSyncClass = "danger"
        else
          dataSyncText = @dataSync.lastError
          dataSyncClass = "danger"
      else
        dataSyncText = T("Complete")
        dataSyncClass = "success"

    data = {
      login: @login
      version: @version
      baseVersion: @baseVersion
      lastSyncDate: @dataSync.lastSuccessDate if @dataSync?
      imagesRemaining: @imageSync.lastSuccessMessage if @imageSync? and @imageSync.lastSuccessMessage > 0
      dataSyncText: dataSyncText
      dataSyncClass: dataSyncClass
      outdated: outdated
      offlineSiteCodes: if @siteCodesManager then @siteCodesManager.getNumberAvailableCodes() else null
      locales: @localizer.getLocales()
    }

    appUpdater = cordovaSetup.appUpdater
    if appUpdater?
      data.showUpdates = true
      data.updating = appUpdater.inProgress
      if appUpdater.inProgress
        data.updateProgress = appUpdater.progress or 0
        data.updateText = T("Updating...")
        data.updateClass = "info"
      else if appUpdater.lastSuccessMessage == "noconnection"
        data.updateText = T("No Connection")
        data.updateClass = "warning"
      else if appUpdater.lastSuccessMessage == "uptodate"
        data.updateText = T("Up to date")
        data.updateClass = "success"
      else if appUpdater.lastError
        data.updateText = T("Error updating")
        data.updateClass = "danger"
      else
        data.updateText = T("Unknown")
        data.updateClass = "muted"

    @$el.html require('./SettingsPage.hbs')(data)

    # Select current locale
    @$("#locale").val(@localizer.locale)

    # Show EC plates test if available
    @$("#test_ecplates").hide()
    ECPlates.isAvailable (available) =>
      if available
        @$("#test_ecplates").show()
    , @error

    # Setup debugging buttons
    if window.debug
      @$("#weinre_details").html(T("Debugging with code <b>{0}</b>", window.debug.code))
      @$("#weinre").attr("disabled", true)

  logout: ->
    if not confirm(T("Logout of app? You will need an internet connection to log back in."))
      return
      
    login.setLogin(@storage, null)
    
    # Update context, first stopping old one
    @ctx.stop()
    context.createAnonymousContext (ctx) =>
      _.extend @ctx, ctx
      @pager.closeAllPages(require("./LoginPage"))

  updateApp: ->
    if cordovaSetup.appUpdater
      cordovaSetup.appUpdater.perform()
      @render()

  setLocale: ->
    @localizer.locale = @$("#locale").val()
    @storage.set('locale', @localizer.locale)
    @render()

  reset: ->
    if confirm(T("Completely discard local data, logout and lose unsubmitted changes?"))
      # Clear local storage
      @storage.clear()

      # Finish up
      finish = () =>
        @pager.closeAllPages(require("./LoginPage"))

      # Clear all collections from database
      if not @db.localDb
        return finish()


      # Reset local db
      localDb = @db.localDb
      cols = _.keys(@db.collections)
      async.eachSeries cols, (col, callback) =>
        localDb.removeCollection col, =>
          localDb.addCollection col, =>
            callback()
          , (err) =>
            callback("Failed to add collection")
        , (err) =>
          callback("Failed to remove collection")
      , (err) =>
        if (err)
          alert(T("Error resetting database"))
        else
          alert(T("Reset successful"))

        finish()

  requestSiteCodes: ->
    @siteCodesManager.replenishCodes @siteCodesManager.getNumberAvailableCodes() + 5, =>
      @render()
    , ->
      alert("Unable to contact server")

  testECPlates: ->
    # Get camera image
    navigator.camera.getPicture (imgUrl) ->
      ECPlates.processImage imgUrl, (args) =>
        if args.error
          res = T("Error") + ": " + args.error
        else
          res = T("E.Coli") + ": " + args.ecoli + "\n" + T("Total Coliform") + ": " + args.tc + "\n" + T("Algorithm") + ": " + args.algorithm
        alert res
      , @error


  testBarcodeScanner: ->
    if window.cordova and window.cordova.plugins and window.cordova.plugins.barcodeScanner
      window.cordova.plugins.barcodeScanner.scan(
        (result) ->
            alert("We got a barcode\n" +
                  "Result: " + result.text + "\n" +
                  "Format: " + result.format + "\n" +
                  "Cancelled: " + result.cancelled)
      , (error) ->
        alert("Scanning failed: " + error)
      )
    else
      alert("Not supported")
  # startWeinre: ->
  #   if confirm(T("Start remote debugger (this will give developers temporary access to the app on your phone)?"))
  #     # Disable to prevent double-click
  #     @$("#weinre").attr("disabled", true)

  #     code = (if @login then @login.user else "anon") + Math.floor(Math.random()*1000)
  #     console.log "weinre code #{code}"
  #     script = document.createElement("script")
  #     script.onload = () =>
  #       window.debug = {
  #         code: code
  #         ctx: @ctx
  #         require: require
  #       }
  #       @render()
  #       alert(T("Debugger started with code {0}", code))
  #     script.onerror = ->
  #       error(T("Failed to load weinre"))
  #       @render()
  #     script.src = "http://weinre.mwater.co/target/target-script-min.js#" + code
  #     document.head.appendChild(script)

module.exports = SettingsPage