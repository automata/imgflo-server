#     imgflo-server - Image-processing server
#     (c) 2014 The Grid
#     imgflo-server may be freely distributed under the MIT license

async = require 'async'
pkginfo = (require 'pkginfo')(module, 'version')
path = require 'path'
child_process = require 'child_process'
fs = require 'fs'
crypto = require 'crypto'

installdir = __dirname + '/../install/'
projectdir = __dirname + '/..'

# Interface for Processors
class UnsupportedImageTypeError extends Error
    constructor: (attempt, supported) ->
        @name = 'unsupported-image-type'
        @code = 449
        @message = "Unsupported image type: " + attempt
        @result = { supported: supported, error: @message, code: @name }

class Processor
    constructor: (verbose) ->
        @verbose = verbose

    # FIXME: clean up interface
    # callback should be called with (err, error_string)
    process: (outputFile, outType, graph, iips, inputFile, inputType, callback) ->
        throw new Error 'Processor.process() not implemented'

# Interfaces for caching
class CacheServer
    constructor: (options) ->
        #

    # callback (err, url)
    putFile: (path, key, callback) ->
        #

    # callback (err, url)
    keyExists: (key, callback) ->
        #

# Key used in cache
exports.hashFile = (path) ->
    hash = crypto.createHash 'sha1'
    hash.update path
    return hash.digest 'hex'

exports.keysNotIn = (A, B) ->
    notIn = []
    for a in Object.keys A
        isIn = false
        for b in Object.keys B
            if b == a
                isIn = true
        if not isIn
            notIn.push a
    return notIn

exports.typeFromMime = (mime) ->
    type = null
    if mime == 'image/jpeg'
        type = 'jpg'
    else if mime == 'image/png'
        type = 'png'
    return type

exports.runtimeForGraph = (g) ->
    runtime = 'imgflo'
    if g.properties and g.properties.environment and g.properties.environment.type
        runtime = g.properties.environment.type
    return runtime

# Key used in cache
exports.hashFile = (path) ->
    hash = crypto.createHash 'sha1'
    hash.update path
    return hash.digest 'hex'

exports.keysNotIn = (A, B) ->
    notIn = []
    for a in Object.keys A
        isIn = false
        for b in Object.keys B
            if b == a
                isIn = true
        if not isIn
            notIn.push a
    return notIn

exports.typeFromMime = (mime) ->
    type = null
    if mime == 'image/jpeg'
        type = 'jpg'
    else if mime == 'image/png'
        type = 'png'
    return type

exports.runtimeForGraph = (g) ->
    runtime = 'imgflo'
    if g.properties and g.properties.environment and g.properties.environment.type
        runtime = g.properties.environment.type
    return runtime

clone = (obj) ->
  if not obj? or typeof obj isnt 'object'
    return obj

  if obj instanceof Date
    return new Date(obj.getTime())

  if obj instanceof RegExp
    flags = ''
    flags += 'g' if obj.global?
    flags += 'i' if obj.ignoreCase?
    flags += 'm' if obj.multiline?
    flags += 'y' if obj.sticky?
    return new RegExp(obj.source, flags)

  newInstance = new obj.constructor()

  for key of obj
    newInstance[key] = clone obj[key]

  return newInstance


gitDescribe = (path, callback) ->
    cmd = 'git describe --tags'
    child_process.exec cmd, { cwd: path }, (err, stdout, stderr) ->
        stdout = stdout.replace '\n', ''
        return callback err, stdout

getGitVersions = (callback) ->
  info =
       npm: module.exports.version
  names = [ 'server', 'runtime',
          'dependencies',
          'gegl',
          'babl'
  ]
  paths = [ './', 'runtime',
#          'runtime/dependencies',
#          'runtime/dependencies/gegl',
#          'runtime/dependencies/babl'
  ]
  paths = (path.join projectdir, p for p in paths)

  async.map paths, gitDescribe, (err, results) ->
      for i in [0...results.length]
          name = names[i]
          info[name] = results[i]

      callback err, info

getInstalledVersions = (callback) ->
    p = path.join installdir, 'imgflo.versions.json'
    fs.readFile p, (err, content) ->
        return callback err, null if err
        try
            callback null, JSON.parse content
        catch e
            callback e, null

updateInstalledVersions = (callback) ->

    fs.mkdir installdir, (err) ->
        return callback err, null if err and err.code != 'EEXIST'
        p = path.join installdir, 'imgflo.versions.json'
        getGitVersions (err, info) ->
          return callback err, null if err
          c = JSON.stringify info
          fs.writeFile p, c, (err) ->
              return callback err, null if err
              return callback null, p


exports.mergeDefaultConfig = (overrides) ->
    defaultPort = 8080
    defaultConfig =
        verbose: false
        api_port: 8080
        api_host: "localhost:#{defaultPort}" # note: depends on port
        api_key: process.env.IMGFLO_API_KEY
        api_secret: process.env.IMGFLO_API_SECRET
        workdir: './temp'
        graphdir: './graphs'
        resourcedir: './examples'

        image_size_limit: 25 # megapixels
        worker_type: 'internal' # will start internal worker
        broker_url: 'direct://imgflo3'

        cache_type: 'local' # will start local cache server
        cache_s3_key: process.env.AMAZON_API_ID
        cache_s3_secret: process.env.AMAZON_API_TOKEN
        cache_s3_bucket: process.env.AMAZON_API_BUCKET
        cache_s3_region: process.env.AMAZON_API_REGION
        cache_s3_folder: 'test'
        cache_local_directory: './temp/cache' # note: depends on workdir?
        redis_url: process.env.IMGFLO_REDIS_URL

    config = clone defaultConfig
    for key, value of overrides
        config[key] = value if value
    return config

exports.getProductionConfig = () ->
    config =
        cache_s3_folder: 'p'
    config.api_port = process.env.PORT or null
    config.api_host = process.env.HOSTNAME or null
    config.cache_type = process.env.IMGFLO_CACHE or null
    config.worker_type = process.env.IMGFLO_WORKER or null
    config.broker_url = process.env.CLOUDAMQP_URL or null
    config.broker_url = process.env.IMGFLO_BROKER_URL or config.broker_url
    config.redis_url = process.env.REDISCLOUD_URL or null
    config.image_size_limit = process.env.IMGFLO_SIZE_LIMIT or null
    config = exports.mergeDefaultConfig config

    return config

class FsyncedWriteStream extends fs.WriteStream
    close: (cb) ->
        return super cb if not @fd
        fs.fsync @fd, (err) =>
            @emit 'error', err if err
            @emit 'fsynced' if not err
            super cb
exports.FsyncedWriteStream = FsyncedWriteStream

exports.clone = clone
exports.Processor = Processor
exports.getInstalledVersions = getInstalledVersions
exports.updateInstalledVersions = updateInstalledVersions
exports.installdir = installdir
exports.CacheServer = CacheServer
exports.errors = {
    UnsupportedImageType: UnsupportedImageTypeError
}
