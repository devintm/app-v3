### 

Creates the context used for the app

Note: There should only every be one context object. It should be modified, rather than creating a whole new object
as components like the PageMenu may be depending on it. 

Contexts have fixed members that have to be present.

db: database (LocalDb, HybridDb or RemoteDb)
imageManager: Simple or Cached Image manager
camera: Camera that has a single function: takePicture(success, error). 
  success is called with url to be passed to imageManager.addImage(url, success, error)
  error: error function to be called with unexpected errors
auth: see auth module
login: { user: <username>, groups: [<groupname>], client: <client id> }. Can be null if not logged in.
dataSync: synchronizer for data including db and site codes. Success message is to be displayed.
imageSync: synchronizer for images. Success message is to be displayed.
imageAcquirer: source of images (either camera or file selection). Has single function: acquire(success, error)
  that calls success with id of image. If not present, not available.
apiUrl: URL of API e.g. https://api.mwater.co/v3/
localizer: Localizer class, already registered as global T
updateGroupsList: function to asynchronously update login groups

stop(): must be called when context is no longer needed, or before setup of a new user

TODO fill in
TODO should any items be null of context?

###

async = require 'async'
minimongo = require 'minimongo'
loginUtils = require './login'

SimpleImageManager = require './images/SimpleImageManager'
CachedImageManager = require './images/CachedImageManager'
authModule = require './auth'
siteCodes = require './siteCodes'
syncModule = require './sync'
Camera = require './Camera'
cordovaSetup = require './cordovaSetup'
ImageUploader = require './images/ImageUploader'
ProblemReporter = require './ProblemReporter'
storageUtils = require './storage'

collectionNames = ['sites', 'forms', 'groups', 'group_members', 'responses', 'tests', 'source_notes', 'sensors', 'sensor_data']

# Gets a query parameter from the query string of the current page
getQueryParameterByName = (name) ->
  match = RegExp('[?&]' + name + '=([^&]*)').exec(window.location.search)
  return match && decodeURIComponent(match[1].replace(/\+/g, ' '))

# Set up API, routing differently if training server ("training") in domain
if getQueryParameterByName("apiUrl")
  apiUrl = getQueryParameterByName("apiUrl") 
else if window.location.host.match(/training/)
  apiUrl = 'https://api.mwater.co/v3training/'
  alert("Note: App is running in training mode. Changes do not affect main server.")
else
  apiUrl = 'https://api.mwater.co/v3/'

# TODO this is not a pretty way to set these. But it is somewhat decoupled.
temporaryFs = null
persistentFs = null
storage = storageUtils.getStorage()

exports.setupFileSystems = (tempFs, persFs) ->
  temporaryFs = tempFs
  persistentFs = persFs

displayErrorAlert = _.debounce (msg) ->
  alert(T("Internal error") + ": " + msg)
, 5000, true

error = (err) ->
  str = if err? and err.message then err.message else err
  if typeof str != "string"
    str = JSON.stringify(str)

  if err? and err.code
    str = str + " code: #{err.code}"

  console.error("Internal Error Callback: " + str)
  displayErrorAlert(str)
  
  # Call default problem reporter if present
  if ProblemReporter.default?
    ProblemReporter.default.reportProblem(str)

# Base context
createBaseContext = () ->
  camera = if Camera.hasCamera() then Camera else null

  baseContext = {
    error: error
    apiUrl: apiUrl
    camera: camera
    version: '//VERSION//'
    baseVersion: cordovaSetup.baseVersion()
    localizer: T.localizer
    storage: storage
    stop: ->
    # db: null
    # imageManager: null
    # auth: null 
    # login: null
    # siteCodesManager: null
    # dataSync: null
    # imageSync: null
  }

  return baseContext

createLocalDb = (namespace, success, error) ->
  if namespace
    # Autoselect database
    minimongo.utils.autoselectLocalDb { namespace: namespace }, (localDb) =>
      success(localDb)
    , (err) =>
      console.log "Error selecting database"
      error(err)
  else
    # No local storage
    localDb = new minimongo.MemoryDb() 
    success(localDb)


# # Slow JSON http client for testing
# slowHttpClient = (method, url, params, data, success, error) ->
#   # Append 
#   fullUrl = url + "?" + $.param(params)

#   if method == "GET"
#     req = $.getJSON(fullUrl)
#   else if method == "DELETE"
#     req = $.ajax(fullUrl, { type : 'DELETE'})
#   else if method == "POST" or method == "PATCH"
#     req = $.ajax(fullUrl, {
#       data : JSON.stringify(data),
#       contentType : 'application/json',
#       type : method})

#   req.done (response, textStatus, jqXHR) =>
#     setTimeout ->
#       success(response or null)
#     , 10000
#   req.fail (jqXHR, textStatus, errorThrown) =>
#     if error
#       error(jqXHR)

# Setup database
createDb = (login, success) ->
  if login
    # Namespace includes username to be safe
    namespace = "v3.db.#{login.user}"
  else
    namespace = null

  createLocalDb namespace, (localDb) =>
    remoteDb = new minimongo.RemoteDb(apiUrl, (if login then login.client else undefined))
    db = new minimongo.HybridDb(localDb, remoteDb)

    # Add collections
    for col in collectionNames
      localDb.addCollection(col)
      remoteDb.addCollection(col)
      db.addCollection(col)

    # Add entity collections
    for col in _.pluck(window.entity_types, "code")
      localDb.addCollection(col)
      
       # Override url for entity collections
      remoteDb.addCollection(col, { url: apiUrl + "entities/#{col}" })
      db.addCollection(col)

    # Seed local db with startup documents
    if window.seeds
      async.eachSeries _.keys(window.seeds), (col, callback) =>
        async.eachSeries window.seeds[col], (doc, callback2) =>
          localDb[col].seed doc, =>
            callback2()
          , callback2
        , callback
      , (err) =>
        if err
          return error(err)
        success(db)
    else
      success(db)
  , error

exports.createContext = (withCtx) ->
  login = loginUtils.getLogin(storage)
  if login
    createLoginContext(login, withCtx)
  else
    createAnonymousContext(withCtx)

# Anonymous context for not logged in
exports.createAnonymousContext = createAnonymousContext = (success) ->
  createDb null, (db) =>
    # Allow nothing
    auth = new authModule.NoneAuth()

    imageManager = new SimpleImageManager(apiUrl)

    ctx = _.extend createBaseContext(), {
      db: db
      imageManager: imageManager
      auth: auth 
      login: null
      siteCodesManager: null
      dataSync: null
      imageSync: null
    }
    success(ctx)

exports.createDemoContext = (success) ->
  createDb null, (db) =>
    # Allow caching in demo mode in non-persistent storage
    if temporaryFs
      # Silently disable upload 
      fileTransfer = new FileTransfer()
      fileTransfer.upload = (filePath, server, successCallback, errorCallback, options) =>
        successCallback()

      imageManager = new CachedImageManager(temporaryFs, apiUrl, "images", "", fileTransfer) 
    else
      imageManager = new SimpleImageManager(apiUrl)

    baseContext = createBaseContext()

    # Create image acquirer with camera and imageManager if temporaryFs and camera
    if baseContext.camera? and temporaryFs
      imageAcquirer = {
        acquire: (success, error) ->
          baseContext.camera.takePicture (url) ->
            # Add image
            imageManager.addImage url, (id) =>
              success(id)
          , (err) ->
            alert(T("Failed to take picture"))
      }
    else 
      # Use ImageUploader
      imageAcquirer = {
        acquire: (success, error) ->
          ImageUploader.acquire(apiUrl, login.client, success, error) 
      }

    # Allow everything
    auth = new authModule.AllAuth()

    # No client 
    login = { user: "demo", groups: [] }

    siteCodesManager = new siteCodes.DemoSiteCodesManager()

    ctx = _.extend baseContext, {
      db: db 
      imageManager: imageManager
      auth: auth
      login: login
      siteCodesManager: siteCodesManager
      dataSync: null
      imageSync: null
      imageAcquirer: imageAcquirer
    }
    success(ctx)

# login must contain user, client, email members. "user" is username. 
# login can be obtained by posting to api /clients
exports.createLoginContext = createLoginContext = (login, success) ->
  createDb login, (db) =>
    if persistentFs
      fileTransfer = new FileTransfer()
      imageManager = new CachedImageManager(persistentFs, apiUrl, "Android/data/co.mwater.clientapp/images", login.client, fileTransfer)  
    else
      imageManager = new SimpleImageManager(apiUrl)

    baseContext = createBaseContext()

    auth = new authModule.UserAuth(login.user, login.groups)
    siteCodesManager = new siteCodes.SiteCodesManager({url: apiUrl + "site_codes?client=#{login.client}", storage: baseContext.storage})
    dataSync = new syncModule.DataSync(db, siteCodesManager)
    imageSync = new syncModule.ImageSync(imageManager)

    # Ensure that login groups are present (https://github.com/mWater/app-v3/issues/465)
    if not login.groups
      login.groups = []
      
    # Start synchronizing
    dataSync.start(15*1000)  # Every 15 seconds
    imageSync.start(30*1000)  # Every 30 seconds

    # Perform sync immediately
    dataSync.perform()
    imageSync.perform()

    stop = ->
      dataSync.stop()
      imageSync.stop()

    # Create image acquirer with camera and imageManager if persistentFs and camera
    if baseContext.camera? and persistentFs
      imageAcquirer = {
        acquire: (success, error) ->
          baseContext.camera.takePicture (url) ->
            # Add image
            imageManager.addImage url, (id) =>
              success(id)
          , (err) ->
            alert(T("Failed to take picture"))
      }
    else 
      # Use ImageUploader
      imageAcquirer = {
        acquire: (success, error) ->
          ImageUploader.acquire(apiUrl, login.client, success, error) 
      }

    ctx = _.extend baseContext, {
      db: db 
      imageManager: imageManager
      auth: auth
      login: login
      siteCodesManager: siteCodesManager
      dataSync: dataSync
      imageSync: imageSync
      stop: stop
      imageAcquirer: imageAcquirer
    }

    # Add function to asynchronously update groups list 
    ctx.updateGroupsList = () ->
      # Getting client returns groups in response
      $.getJSON(apiUrl + "clients/" + login.client).done (response) =>
        # Update login groups and save
        login.groups = response.groups
        loginUtils.setLogin(storage, login)

        # Update auth
        ctx.auth = new authModule.UserAuth(login.user, login.groups)

    # Always update immediately
    ctx.updateGroupsList()

    success(ctx)
