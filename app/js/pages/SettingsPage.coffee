Page = require "../Page"
ECPlates = require '../forms/ECPlates'
cordovaSetup = require '../cordovaSetup'

class SettingsPage extends Page
  events: 
    "click #reset_db" : "resetDb"
    "click #request_source_codes": "requestSourceCodes"
    "click #test_ecplates" : "testECPlates"
    "click #weinre" : "startWeinre"
    "change #locale": "setLocale"
    "click #update": "updateApp"

  activate: ->
    @setTitle T("Settings")
    @render()

    # Listen to events from app updater
    if cordovaSetup.appUpdater
      @listenTo cordovaSetup.appUpdater, "success error progress start", =>
        @render()

  render: ->
    appUpdater = cordovaSetup.appUpdater

    data = {
      offlineSourceCodes: if @sourceCodesManager then @sourceCodesManager.getNumberAvailableCodes() else null
      locales: @localizer.getLocales()
      showUpdates: appUpdater?
    }

    if appUpdater?
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

  setLocale: ->
    @localizer.locale = @$("#locale").val()
    @localizer.saveCurrentLocale()
    @render()

  resetDb: ->
    if confirm(T("Completely discard local data, logout and lose unsubmitted changes?"))
      window.localStorage.clear()
      while @pager.multiplePages()
        @pager.closePage()
      @pager.closePage(require("./LoginPage"))

  requestSourceCodes: ->
    @sourceCodesManager.replenishCodes @sourceCodesManager.getNumberAvailableCodes() + 5, =>
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
          res = T("E.Coli") + ": " + args.ecoli + "\n" + T("TC") + ": " + args.tc + "\n" + T("Algorithm") + ": " + args.algorithm
        alert res
      , @error

  startWeinre: ->
    if confirm(T("Start remote debugger (this will give developers temporary access to the app on your phone)?"))
      # Disable to prevent double-click
      @$("#weinre").attr("disabled", true)

      code = (if @login then @login.user else "anon") + Math.floor(Math.random()*1000)
      console.log "weinre code #{code}"
      script = document.createElement("script")
      script.onload = () =>
        window.debug = {
          code: code
          ctx: @ctx
          require: require
        }
        @render()
        alert(T("Debugger started with code {0}", code))
      script.onerror = ->
        error(T("Failed to load weinre"))
        @render()
      script.src = "http://weinre.mwater.co/target/target-script-min.js#" + code
      document.head.appendChild(script)

module.exports = SettingsPage