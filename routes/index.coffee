# Setup services
redis = require "redis"
redis_client = redis.createClient process.env.REDIS_PORT or null, process.env.REDIS_HOST or null
redis_client.auth process.env.REDIS_AUTH or ""

fs = require "fs"

shorty = require "node-shorty"

im = require "imagemagick"

knox = require "knox"
s3_client = knox.createClient
  key: process.env.S3_KEY
  secret: process.env.S3_SECRET
  bucket: process.env.S3_BUCKET

# Handlers
exports.images = {}

exports.images.new = (req, res) ->
  res.render "upload", uploading: "active"

exports.images.show = (req, res) ->
  id = shorty.url_decode req.params.image_slug
  unless id
    res.redirect "/"
  redis_client.hgetall "image:#{id}", (err, image) ->
    redis_client.hincrby "image:#{id}", "view_count", 1
    res.render "image", image

exports.images.create = (req, res) ->
  redis_client.incr "image_id", (err, id) ->
      fs.readFile req.files.image.path, (err, buf) ->
        s3_req = s3_client.put "#{id}/original/#{req.files.image.name}",
          'Content-Length': buf.length
          'Content-Type': req.files.image.type
        s3_req.on "response", (s3_res) ->
          if s3_res.statusCode is 200
            im.resize {
              srcData: buf
              width:200
              format:"jpg"
            }, (err, stdout, stderr) ->
              if err then throw err
              fs.writeFileSync('kittens-resized.jpg', new Buffer(stdout, 'binary'));
              s3_client.put(
                "#{id}/thumb/#{req.files.image.name}.jpg",
                  'Content-Length': stdout.length
                  'Content-Type': "image/jpeg"
              ).end(new Buffer(stdout, 'binary'))
              redis_client.hmset "image:#{id}", {
                id
                view_count: 0
                file_name: req.files.image.name
                name: req.body.name
                description: req.body.description
                thumb: "data:image/jpeg;base64,#{(new Buffer(stdout, 'binary')).toString('base64')}"
              }, (err, result) ->
                slug = shorty.url_encode id
                res.redirect "/#{slug}"
        s3_req.end buf

exports.entry = {}

exports.entry.show = (req, res) ->
  root_url = "http://#{req.headers.host}"
  
  slug = req.params.original
  
  if slug
    id = shorty.url_decode slug
    redis_client.hgetall "entry-#{id}", (err, entry) ->
      if entry?
        old_text = entry.old_text
        new_text = entry.new_text
      else
        old_text = new_text = ""
      redis_client.hincrby "entry-#{id}", "view_count", 1
      res.render "show_entry", old_text: old_text, new_text: new_text, url: "http://diffb.in/#{slug}"
  else
    res.render "show_entry", old_text: "", new_text: "", url: "http://diffb.in"

exports.entry.create = (req, res) ->
  root_url = "http://#{req.headers.host}"
  
  old_text = req.body.old_text
  new_text = req.body.new_text
  
  unless old_text and new_text
    res.write("Missing old text")
    return res.end()
  
  redis_client.incr "id_count", (err, id) ->
    slug = shorty.url_encode id
    redis_client.hmset "entry-#{id}", {new_text: new_text, old_text: old_text, slug: slug, view_count: 0 }, (err, redis_result) ->
      res.write JSON.stringify err: "SUCCESS", url: "#{root_url}/#{slug}", slug: slug
      res.end()
