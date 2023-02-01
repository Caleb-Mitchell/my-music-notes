function removeOnClick() {
  const header = document.querySelector('header');
  header.addEventListener('click', function() {
    header.remove();
  });
}
