$ ->
  thumbnails = $('ul.thumbnails')
  thumb_template = $('li.thumb_template')

  socket = io.connect "//#{location.host}"
  socket.on 'new_image', (data) ->
    image = JSON.parse data
    new_element = thumb_template.clone()
    new_element.find("a").attr("href", image.slug)
    new_element.find("img").attr("src", image.thumb)
    new_element.prependTo thumbnails
    new_element.fadeIn()

