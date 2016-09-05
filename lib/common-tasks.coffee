assert      = require 'assert'
path        = require 'path'
fs          = require 'fs'
gulp        = require 'gulp'
changed     = require 'gulp-changed'
extract     = require 'gulp-riff-extractor'
tap         = require 'gulp-tap'
uuid        = require 'uuid'
_           = require 'underscore'
builder     = require './riff-builder.coffee'
msgpack     = require 'msgpack-lite'
beautify    = require 'js-beautify'

util        = require './util.coffee'
$           = require '../config.coffee'

module.exports =

  # prepairing tasks
  # --------------------------------

  # generate default parameter mapping file
  generate_default_mapping: (dir) ->
    gulp.src ["#{$.NI.userContent}/#{dir}/_Default.nksf"]
      .pipe changed "src/#{dir}/mappings",
        hasChanged: (stream, cb, file, dest) ->
          dest = path.join (path.dirname dest), 'default.json'
          changed.compareLastModifiedTime stream, cb, file, dest
      .pipe extract
        chunk_ids: ['NICA']
        filename_template: "default.json"
      .pipe tap (file) ->
        file.contents = new Buffer _deserialize file
      .pipe gulp.dest "src/#{dir}/mappings"

  # print default NISI chunk as JSON
  print_default_meta: (dir) ->
    console.info "#{$.NI.userContent}/#{dir}/_Default.nksf"
    gulp.src ["#{$.NI.userContent}/#{dir}/_Default.nksf"]
      .pipe extract
        chunk_ids: ['NISI']
      .pipe tap (file) ->
        console.info _deserialize file

  # print default NACA chunk as JSON
  print_default_mapping: (dir) ->
    gulp.src ["#{$.NI.userContent}/#{dir}/_Default.nksf"]
      .pipe extract
        chunk_ids: ['NICA']
      .pipe tap (file) ->
        console.info _deserialize file

  # print PLID chunk as JSON
  print_plid: (dir) ->
    gulp.src ["#{$.NI.userContent}/#{dir}/_Default.nksf"]
      .pipe extract
        chunk_ids: ['PLID']
      .pipe tap (file) ->
        magic = _deserializeMagic file
        console.info "magic: '#{magic}'"

  # extract PCHK chunk
  extract_raw_presets: (srcs, dest) ->
    gulp.src srcs
      .pipe extract
        chunk_ids: ['PCHK']
      .pipe gulp.dest dest

  #
  # dist
  # --------------------------------

  # copy image resources to dist folder
  dist_image: (dir, vendor) ->
    d = util.normalizeDirname dir.toLowerCase()
    v = vendor.toLowerCase()
    gulp.src ["src/#{dir}/resources/image/**/*.{json,meta,png}"]
      .pipe gulp.dest "dist/#{dir}/NI Resources/image/#{v}/#{d}"

  # copy database resources to dist folder
  dist_database: (dir, vendor) ->
    d = util.normalizeDirname dir.toLowerCase()
    v = vendor.toLowerCase()
    gulp.src ["src/#{dir}/resources/dist_database/**/*.{json,meta,png}"]
      .pipe gulp.dest "dist/#{dir}/NI Resources/dist_database/#{v}/#{d}"

  # build presets file to dist folder
  # callback(file) optional
  #   -  do something file.contents
  #   -  return preset mapping filepath or mapping object.
  #   -  return null or undefine for use default.json
  dist_presets: (dir, magic, callback) ->
    presets = "src/#{dir}/presets"
    mappings = "src/#{dir}/mappings"
    dist = "dist/#{dir}/User Content/#{dir}"
    defaultMapping = undefined
    defaultMapping = if fs.existsSync "#{mappings}/default.json"
      _serialize util.readJson "#{mappings}/default.json"
    pluginId = _serializeMagic magic
    gulp.src ["#{presets}/**/*.pchk"], read: true
      .pipe tap (file) ->
        mapping = defaultMapping
        mapping = if _.isFunction callback
          m = callback file
          switch
            when _.isString m
              _serialize util.readJson m
            when _.isObject m and m.ni8
              _serialize m
            else
              defaultMapping
        else
          defaultMapping
        riff = builder 'NIKS'
        # NISI chunk -- metadata
        meta = _serialize util.readJson "#{presets}/#{file.relative[..-5]}meta"
        riff.pushChunk 'NISI', meta
        # NACA chunk -- mapping
        riff.pushChunk 'NICA', mapping
        # PLID chunk -- plugin id
        riff.pushChunk 'PLID', pluginId
        # PCHK chunk -- raw preset (pluginstates)
        riff.pushChunk 'PCHK', file.contents
        # output file contents
        file.contents = riff.buffer()
        # .pchk -> .nksf
        file.path = "#{file.path[..-5]}nksf"
      .pipe gulp.dest dist

  # print all presets
  check_dist_presets: (dir, PLID) ->
    dist = "dist/#{dir}/User Content/#{dir}"
    gulp.src ["#{dist}/**/*.nksf"], read: true
      .pipe extract
        chunk_ids: ['NISI', 'NICA', 'PLID']
      .pipe tap (file) ->
        console.info _deserialize file
  #
  # deploy
  # --------------------------------

  # copy resources to local environment
  deploy_resources: (dir) ->
    gulp.src ["dist/#{dir}/NI Resources/**/*.{json,meta,png}"]
      .pipe gulp.dest $.NI.resources

  # copy presets to local environment
  deploy_presets: (dir) ->
    gulp.src ["dist/#{dir}/User Content/**/*.nksf"]
      .pipe gulp.dest $.NI.userContent

  #
  # release
  # --------------------------------

  # zip dist file and copy to dropbox.
  release: (dir) ->
    gulp.src ["dist/#{dir}/**/*.{json,meta,png,nksf}"]
      .pipe zip "#{dir}.zip"
      .pipe gulp.dest $.release

#
# routines
# --------------------------------

# desrilize to json string
_deserialize = (file) ->
  ver = file.contents.readUInt32LE 0
  assert.ok (ver is $.chunkVer), "Unsupported chunk format version. version:#{ver}"
  util.beautify msgpack.decode file.contents.slice 4

# desrilize to magic string
_deserializeMagic = (file) ->
  ver = file.contents.readUInt32LE 0
  assert.ok (ver is $.chunkVer), "Unsupported chunk format version. version:#{ver}"
  json = msgpack.decode file.contents.slice 4
  magic = json['VST.magic']
  buffer = new Buffer 4
  buffer.writeUInt32BE magic
  buffer.toString()

# esrilize to PLID chunk
_serializeMagic = (magic) ->
  buffer = new Buffer 4
  buffer.write magic, 0, 4, 'ascii'
  x = buffer.readUInt32BE 0
  _serialize
    "VST.magic": buffer.readUInt32BE 0

# srilize to chunk
_serialize = (json) ->
  ver = new Buffer 4
  ver.writeUInt32LE $.chunkVer
  Buffer.concat [ver, msgpack.encode json]