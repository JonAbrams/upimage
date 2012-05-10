# Constants
THUMB_SIZE = 260 # Max height/width for thumbnails
MEDIUM_SIZE = 500 # MAx height/width for medium sized versions
N_IMAGES = 10

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

# Getter methods
exports.getRedisClient = -> redis_client

# Handlers
exports.images = {}

# Shows the latest images
exports.images.index = (req, res) ->
  # Get the latest N images to show
  redis_client.lrange "latest_images", 0, N_IMAGES, (err, result) ->
    multi = redis_client.multi()
    multi.hgetall item for item in result
    multi.exec (err, replies) ->
      res.render "index", images: replies

# Renders the image upload page
exports.images.new = (req, res) ->
  res.render "upload", uploading: "active"

# Renders the page for a specific image
exports.images.show = (req, res) ->
  id = shorty.url_decode req.params.image_slug
  unless id
    res.redirect "/"
  redis_client.hgetall "image:#{id}", (err, image) ->
    redis_client.hincrby "image:#{id}", "view_count", 1
    res.render "image", image

# Given an image file, store it with Amazon S3 and make a record with redis
exports.images.create = (req, res) ->
  # Increment the image_id (to get a unique ID)
  redis_client.incr "image_id", (err, id) ->
    # Express automatically writes the image file to disk, read it
    fs.readFile req.files.image.path, (err, buf) ->
      # Remove characters from the file name that S3 doesn't like
      file_name = req.files.image.name.replace(/[^\w]/g, "_")
      # Store the original with S3
      s3_req = s3_client.put "#{id}/original/#{file_name}",
        'Content-Length': buf.length
        'Content-Type': req.files.image.type
      s3_req.on "response", (s3_res) ->
        if s3_res.statusCode is 200
          # Make sure the file uploaded is of the right image type
          format = req.files.image.type.substring(6)
          format = "jpg" if format is "jpeg"
          unless format in ["png", "jpg", "gif"]
            res.end "Error: Invalid image type. Only jpeg, png, and gif supported"
            return
          # Use ImageMagick to create the thumbnail version
          im.resize {
            srcData: buf
            width: THUMB_SIZE
            format
          }, (err, stdout, stderr) ->
            if err then throw err
            # Store the thumbnail with s3
            stdout_buf = new Buffer(stdout, 'binary')
            s3_client.put(
              "#{id}/thumb/#{file_name}",
                'Content-Length': stdout.length
                'Content-Type': req.files.image.type
            ).end(stdout_buf)
            # Turn the unique numeric id into a shortened URL slug
            slug = shorty.url_encode id
            # Create a record of the image
            # Note: the thumb attribute contains the actual thumbnail image encoded as a Data URL
            # This will make the loading of any gallery extremely fast!
            redis_client.hmset "image:#{id}", {
              id
              slug
              view_count: 0
              file_name
              name: req.body.name
              description: req.body.description
            }, (err, result) ->
              redis_client.lpush "latest_images", "image:#{id}"
              redis_client.publish "latest_images", JSON.stringify {
                thumb: "data:#{req.files.image.type};base64,#{stdout_buf.toString('base64')}"
                name: req.body.name
                slug
              }
              # send new thumb to connected users: 
              res.redirect "/#{slug}"
        else
          console.log "Error status: #{s3_res.statusCode}. Image type: #{req.files.image.type}"
          res.end "Error uploading picture"
      s3_req.end buf
