function disableNoSubmit() {
  const resetButton = document.getElementById('reset-button')
  const buttons = document.querySelectorAll('.form-check-input')

  resetButton.setAttribute('disabled', true)
  buttons.forEach((button) => button.setAttribute('disabled', true))
}
