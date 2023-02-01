function disableThenSubmit() {
  const form = document.getElementById('check_boxes')
  if (!form) return

  const buttons = document.querySelectorAll('.form-check-input')
  form.submit()
  buttons.forEach((button) => button.setAttribute('disabled', true))
}
