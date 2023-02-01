function disableThenSubmit() {
  const form = document.getElementById('check_boxes')
  if (!form) return

  const resetButton = document.getElementById('reset-button')
  const buttons = document.querySelectorAll('.form-check-input')

  form.submit()
  resetButton.setAttribute('disabled', true)
  buttons.forEach((button) => button.setAttribute('disabled', true))
}
