const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const observer = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  }
}, { threshold: 0.14 });

document.querySelectorAll('.reveal').forEach((element) => observer.observe(element));

if (!reduceMotion) {
  const stage = document.querySelector('.product-stage');
  const windowPreview = document.querySelector('.app-window');
  stage?.addEventListener('pointermove', (event) => {
    const bounds = stage.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    windowPreview.style.transform = `rotateY(${x * 5 - 4}deg) rotateX(${y * -4 + 1}deg)`;
  });
  stage?.addEventListener('pointerleave', () => {
    windowPreview.style.transform = 'rotateY(-4deg) rotateX(1deg)';
  });
}
