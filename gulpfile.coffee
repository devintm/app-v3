gulp = require 'gulp'
browserify = require 'browserify'
del = require 'del'
source = require 'vinyl-source-stream'
rework = require 'gulp-rework'
reworkNpm = require 'rework-npm'
concat = require 'gulp-concat'
uglify = require 'gulp-uglify'
makeBuffer = require 'gulp-buffer'
awspublish = require 'gulp-awspublish'
fs = require 'fs'
glob = require 'glob'
gutil = require 'gulp-util'
manifest = require 'gulp-manifest'
rename = require 'gulp-rename'
JsonClient = require('request-json').JsonClient
replace = require 'gulp-replace'
merge = require 'merge-stream'
exec = require('child_process').exec
extractor = require 'ez-localize/extractor'

gulp.task 'manifest', ->
  return gulp.src(['dist/**'])
    .pipe(manifest({
      preferOnline: true
      network: ['*']
      timestamp: true
      filename: 'manifest.appcache'
      exclude: 'manifest.appcache'
     }))
    .pipe(gulp.dest('dist/'))

gulp.task 'watch', ->
  return gulp.watch ['app/**'], ['default']

deployS3 = (bucket) ->
  # Read credentials
  aws = JSON.parse(fs.readFileSync("/home/clayton/.ssh/aws-credentials.json"))
  console.log "Publishing to bucket #{bucket}"
  aws.bucket = bucket

  publisher = awspublish.create(aws)
  
  # Publish all but manifest
  headers = { 'Cache-Control': 'no-cache, must-revalidate' }
  
  stream1 = gulp.src(['./dist/**', '!./dist/manifest.appcache'])
    .pipe(awspublish.gzip())
    .pipe(publisher.publish(headers))
    .pipe(publisher.cache())
    .pipe(awspublish.reporter())

  # Publish manifest, which requires no-store for some browsers (older iPhone and Galaxy S3 at least)
  manifestHeaders = { 'Cache-Control': 'no-cache, no-store, must-revalidate' }

  stream2 = gulp.src('./dist/manifest.appcache')
    .pipe(awspublish.gzip())
    .pipe(publisher.publish(manifestHeaders))
    .pipe(awspublish.reporter())

  return merge(stream1, stream2)

# Runs a shell script, piping output to stdout. Returns a function that takes a callback
run = (cmd, options) ->
  return (cb) ->
    child = exec cmd, options, (error, stdout, stderr) -> cb(error)
    child.stdout.on 'data', (data) -> process.stdout.write(data)
    child.stderr.on 'data', (data) -> process.stderr.write(data)
    return

# Shim non-browserify friendly libraries to allow them to be 'require'd
shim = (instance) ->
  shims = {
    jquery: './app/js/jquery-shim'
    lodash: './app/js/lodash-shim'
    underscore: './app/js/underscore-shim'
    backbone: './app/js/backbone-shim' 
  }

  # Add shims
  for name, path of shims
    instance.require(path, {expose: name})

  return instance

gulp.task 'browserify_index', ->
  return shim(browserify([], { extensions: ['.js', '.coffee'] }))
    .require('./app/js/run.coffee', {expose: 'run'})
    .require('./app/js/forms/index.coffee', {expose: 'forms'})
    .transform(require('./versionXform'))
    .bundle()
    .on('error', gutil.log)
    .on('error', -> throw "Failed")
    .pipe(source('app.js'))
    .pipe(gulp.dest('./dist/js/'))

gulp.task 'browserify_preload', ->
  return browserify(['./app/js/preload.coffee'], { extensions: ['.js', '.coffee'] })
    .bundle()
    .on('error', gutil.log)
    .on('error', -> throw "Failed")
    .pipe(source('preload.js'))
    .pipe(gulp.dest('./dist/js/'))

gulp.task 'browserify', gulp.parallel('browserify_index', 'browserify_preload')

gulp.task 'clean', (cb) ->
  del(['dist/**', '!dist/js/.gitkeep'], cb)

gulp.task 'libscss', ->
  return gulp.src([
    'vendor/bootstrap/css/bootstrap.min.css'
    'vendor/mobiscroll.custom-2.5.4.min.css'  # To remove when old forms DateQuestion is gone
    'vendor/esri/esri-leaflet-geocoder.css'
    "bower_components/css-social-buttons/css/zocial.css"
    'vendor/leaflet/leaflet.css'    
    ])
    .pipe(concat('libs.css'))
    .pipe(gulp.dest('dist/css/'))

gulp.task 'libsjs', ->
  return gulp.src([
    'bower_components/jquery/dist/jquery.js' 
    'bower_components/lodash/dist/lodash.js' 
    'bower_components/backbone/backbone.js' 
    'vendor/bootstrap/js/bootstrap.js'  # Custom bootstrap with larger fonts
    'bower_components/handlebars/handlebars.runtime.js'
    'bower_components/swag/lib/swag.js'
    'bower_components/overthrow-dist/overthrow.js'
    'vendor/mobiscroll.custom-2.5.4.min.js' # To remove when old forms DateQuestion is gone
    'vendor/jquery.scrollintoview.min.js'
    'vendor/leaflet/leaflet-src.js'
    'vendor/esri/esri-leaflet-core.js'
    'vendor/esri/esri-leaflet-geocoder.js'
    ])
    .pipe(concat('libs.js'))
    .pipe(uglify())
    .pipe(gulp.dest('dist/js/'))

gulp.task 'appcss', ->
  return gulp.src('app/css/index.css')
    .pipe(rework(reworkNpm()))
    .pipe(rename("app.css"))
    .pipe(gulp.dest('./dist/css/'))


gulp.task 'copy_html', ->
  return gulp.src("app/html/*")
    .pipe(replace("timestamp", new Date().getTime() + ""))
    .pipe(gulp.dest('dist/'))

gulp.task 'copy_app_images', ->
  return gulp.src("app/img/*")
    .pipe(gulp.dest('dist/img/'))

gulp.task 'copy_bootstrap_fonts', ->
  return gulp.src("vendor/bootstrap/fonts/*")
    .pipe(gulp.dest('dist/fonts/'))

gulp.task 'copy_leaflet_images', ->
  return gulp.src("vendor/leaflet/images/*")
  .pipe(gulp.dest('dist/img/leaflet/'))

gulp.task 'copy_social_fonts', ->
  return gulp.src([
    "bower_components/css-social-buttons/css/zocial-regular*.*"])
    .pipe(gulp.dest('dist/css/'))

gulp.task 'copy_esri_images', ->
  return gulp.src("vendor/esri/img/*")
  .pipe(gulp.dest('dist/css/img/'))

gulp.task 'copy', gulp.parallel('copy_html', 'copy_app_images', 'copy_bootstrap_fonts', 'copy_leaflet_images', 'copy_social_fonts', 'copy_esri_images')

gulp.task 'prepareTests', gulp.series('libsjs', ->
  files = glob.sync("./test/**/*Tests.coffee")
  bundler = shim(browserify({ entries: files, extensions: [".js", ".coffee"] }))
  bundler.require("./app/js/forms/index.coffee", { expose: "forms"})

  return bundler.bundle()
    .pipe(source('browserified.js'))
    .pipe(gulp.dest('./test'))
  )

gulp.task 'seeds', (cb) ->
  # Query database for rows
  seeds = {}

  jsonClient = new JsonClient("https://api.mwater.co/v3/")

  # Only get tests
  jsonClient.get 'forms?selector={"type": "WaterTest"}', (err, res, body) ->
    if res.statusCode != 200
      return cb(new Error("Server error"))

    seeds.forms = body

    # Get entity types
    jsonClient.get 'entity_types', (err, res, body) ->
      if res.statusCode != 200
        return cb(new Error("Server error"))

      entity_types = body

      # Get properties
      jsonClient.get 'properties', (err, res, body) ->
        if res.statusCode != 200
          return cb(new Error("Server error"))

        properties = body

        # Get units
        jsonClient.get 'units', (err, res, body) ->
          if res.statusCode != 200
            return cb(new Error("Server error"))

          units = body
          
          fs.writeFileSync('dist/js/seeds.js', 'seeds=' + JSON.stringify(seeds) + '; entity_types=' + JSON.stringify(entity_types) + '; properties=' + JSON.stringify(properties) + '; units=' + JSON.stringify(units) + ";")
          cb()
  return

gulp.task 'localization', (cb) ->
  options = { 
    extensions: ['.js', '.coffee']
    externalModules: ["mwater-forms", "mwater-common"]
    transformKey: [ 'browserify', 'transform' ]
  }

  extractor.updateLocalizationFile "app/js/run.coffee", "app/js/localizations.json", options, -> 
    cb()

# Builds the web app
gulp.task 'build', gulp.series('browserify', 'appcss', 'libscss', 'libsjs', 'copy', 'seeds', 'manifest')

gulp.task 'bump_version', run('npm version patch')

# Individual deployment tasks
gulp.task 'deploy_app_mwater_co', -> deployS3('app-mwater-co')
gulp.task 'deploy_trainingapp_mwater_co', -> deployS3('trainingapp.mwater.co')
gulp.task 'deploy_app_mwater_org', -> deployS3('app.mwater.org')
gulp.task 'deploy_beta_mwater_co', -> deployS3('beta.mwater.co')
gulp.task 'deploy_demo_mwater_co', -> deployS3('demo.mwater.co')
gulp.task 'deploy_map_mwater_co', -> deployS3('map.mwater.co')
gulp.task 'deploy_map_mwater_org', -> deployS3('map.mwater.org')

gulp.task 'deploy', gulp.series([
  'bump_version'
  'build'
  'deploy_app_mwater_co'
  'deploy_app_mwater_org'
  'deploy_trainingapp_mwater_co'
  ])

gulp.task 'default', gulp.series('build')

# Include cordova tasks
require './gulpfile_cordova'

