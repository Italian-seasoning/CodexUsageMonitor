const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

document.querySelectorAll('.download-glow').forEach((button) => {
  button.addEventListener('pointermove', (event) => {
    const bounds = button.getBoundingClientRect();
    button.style.setProperty('--glow-x', `${event.clientX - bounds.left}px`);
    button.style.setProperty('--glow-y', `${event.clientY - bounds.top}px`);
  });
});

if (!reduceMotion) {
  document.body.classList.add('motion-ok');

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.14 });

  document.querySelectorAll('.reveal').forEach((element) => observer.observe(element));

  const stage = document.querySelector('.hero-product');
  stage?.addEventListener('pointermove', (event) => {
    const bounds = stage.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    stage.style.setProperty('--stage-y', `${x * 1.8}deg`);
    stage.style.setProperty('--stage-x', `${1.5 - y * 1.4}deg`);
  });
  stage?.addEventListener('pointerleave', () => {
    stage.style.removeProperty('--stage-x');
    stage.style.removeProperty('--stage-y');
  });
}
