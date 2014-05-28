assert = chai.assert

fail = (err) ->
  console.error err
  assert.ok(false, err)

exports.requestFileSystem  = window.requestFileSystem || window.webkitRequestFileSystem

exports.resolveLocalFileSystemURI = window.resolveLocalFileSystemURI || window.resolveLocalFileSystemURL || window.webkitResolveLocalFileSystemURL

resolveLocalFileSystemURI = exports.resolveLocalFileSystemURI

exports.createFile = (fs, path, text, success) ->
  # If path is a url, handle specially
  if path.match(/:\/\//)
    # Get parent URL
    dir = path.substring( 0, path.lastIndexOf( "/" ) + 1)
    filename = path.substring(path.lastIndexOf( "/" ) + 1)
    resolveLocalFileSystemURI dir, (dirEntry) =>
      dirEntry.getFile filename, { create:true }, (fileEntry) =>
        # Create a FileWriter object for our FileEntry 
        fileEntry.createWriter (fileWriter) =>
          fileWriter.onwriteend = (e) =>
            console.log('Write completed.')

          fileWriter.onerror = (e) =>
            console.log('Write failed: ' + e.toString())
        
          # Create a new Blob and write it to log.txt.
          blob = new Blob([text], {type: 'text/plain'})
          fileWriter.write(blob)
          success(fileEntry.toURL())
        , fail
      , fail
    , fail
  else
    fs.root.getFile path, {create: true}, (fileEntry) =>
      # Create a FileWriter object for our FileEntry 
      fileEntry.createWriter (fileWriter) =>
        fileWriter.onwriteend = (e) =>
          console.log('Write completed.')

        fileWriter.onerror = (e) =>
          console.log('Write failed: ' + e.toString())
      
        # Create a new Blob and write it to log.txt.
        blob = new Blob([text], {type: 'text/plain'})
        fileWriter.write(blob)
        success(fileEntry.toURL())
      , fail
    , fail

exports.readFileEntry = (fileEntry, success) ->
  $.get fileEntry.toURL(), (data) -> 
    success(data)

exports.getTempFileSystem = (success) ->
    # Obtain temp storage
    mode = if window.LocalFileSystem then LocalFileSystem.TEMPORARY else window.TEMPORARY
    exports.requestFileSystem.call window, mode, 0, (fs) =>
      # Clean contents
      fs.root.createReader().readEntries (items) =>
        nukeList items, =>
          success(fs)
      , fail
    , fail

nukeList = (list, success) ->
  if list.length == 0
    return success()

  item = _.first(list)
  if item.isFile
    item.remove ->
      nukeList _.rest(list), success
    , fail
  else
    item.removeRecursively ->
      nukeList _.rest(list), success
    , fail