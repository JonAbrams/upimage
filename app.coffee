express = require("express")
app = module.exports = express.createServer()
io = require("socket.io").listen app
routes = require("./routes")
require('jade/lib/inline-tags').push('textarea'); # Fix whitespace issue in textareas

# Force long-polling to enable heroku compatibility
# Remove this if using a WebSockets compatible server
io.configure ->
  io.set "transports", ["xhr-polling"]
  io.set "polling duration", 10

app.configure ->
  app.set "views", __dirname + "/views"
  app.set "view engine", "jade"
  app.set 'view options', pretty: true, layout: false
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express["static"](__dirname + "/public")
  app.use require("connect-assets")()
  app.use app.router

app.configure "development", ->
  app.use express.errorHandler(
    dumpExceptions: true
    showStack: true
  )

app.configure "production", ->
  app.use express.errorHandler()

app.get "/upload", routes.images.new
app.post "/upload", routes.images.create
app.get "/:image_slug", routes.images.show
app.get "/", routes.images.index

io.set "log level", 1
redis = require "redis"
redis_client = redis.createClient process.env.REDIS_PORT or null, process.env.REDIS_HOST or null
redis_client.auth process.env.REDIS_AUTH or ""
redis_client.on "error", (err) -> console.log "Redis Error: #{err}"
redis_client.subscribe "latest_images"

io.on "connection", (socket) ->
  handle_message = (channel, image) ->
    socket.emit "new_image", image if channel is "latest_images"
  event = redis_client.on "message", handle_message
  socket.on "disconnect", ->
    redis_client.removeListener "message", handle_message

port = process.env.PORT or 3000
app.listen port, ->
  console.log "Listening on " + port
