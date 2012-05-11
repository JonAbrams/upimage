$ ->
  submitted = false
  $("form#entry_form").submit (event) ->
    unless submitted
      submitted = true
      $(this).find('input[type="submit"]').button("loading")
    else
      return false
