/* HapticVideoApp landing — scroll fades, copy button, drifting sparks. */

(function () {
  'use strict';

  // ─── scroll fade-up
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add('vis');
        io.unobserve(e.target);
      }
    });
  }, { threshold: 0.12 });

  document.querySelectorAll('.up').forEach((el) => io.observe(el));

  // ─── copy button
  const copyBtn = document.getElementById('copy-btn');
  if (copyBtn) {
    copyBtn.addEventListener('click', async () => {
      const value = copyBtn.dataset.copy || '';
      try {
        await navigator.clipboard.writeText(value);
        const original = copyBtn.textContent;
        copyBtn.textContent = 'Copied';
        copyBtn.style.background = 'rgba(140,92,255,.35)';
        setTimeout(() => {
          copyBtn.textContent = original;
          copyBtn.style.background = '';
        }, 1400);
      } catch (err) {
        console.warn('Copy failed', err);
      }
    });
  }

  // ─── drifting background sparks (decorative only)
  const sparkHost = document.getElementById('spark-host');
  if (sparkHost && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const count = window.innerWidth < 700 ? 14 : 32;
    const colors = ['#8C5CFF', '#00d4ff', '#ec4899', '#FF8A4C', '#ffffff'];
    for (let i = 0; i < count; i++) {
      const s = document.createElement('span');
      s.className = 'spark';
      const c = colors[Math.floor(Math.random() * colors.length)];
      s.style.background = c;
      s.style.boxShadow = `0 0 8px 2px ${c}66`;
      s.style.left = Math.random() * 100 + '%';
      s.style.top = Math.random() * 100 + '%';
      const dur = 14 + Math.random() * 22;
      const delay = -Math.random() * dur;
      s.style.animation = `sparkDrift ${dur}s ease-in-out ${delay}s infinite`;
      sparkHost.appendChild(s);
    }
  }

  // Inject the spark drift keyframes once (kept in JS so we can vary directions)
  const sheet = document.createElement('style');
  sheet.textContent = `
    @keyframes sparkDrift {
      0%   { transform: translate3d(0, 0, 0)        scale(1);   opacity: .35; }
      25%  { transform: translate3d(20px, -28px, 0) scale(1.3); opacity: .85; }
      50%  { transform: translate3d(-14px, -48px, 0) scale(.9); opacity: .55; }
      75%  { transform: translate3d(12px, -28px, 0) scale(1.1); opacity: .8; }
      100% { transform: translate3d(0, 0, 0)        scale(1);   opacity: .35; }
    }
  `;
  document.head.appendChild(sheet);

  // ─── headline letter-by-letter timing (delays as inline-style fallback)
  document.querySelectorAll('.mega-headline .ltr').forEach((el, i) => {
    el.style.animationDelay = (0.04 + i * 0.04) + 's';
  });

  // ─── animate nav background on scroll
  const nav = document.querySelector('.nav');
  if (nav) {
    let lastY = 0;
    const onScroll = () => {
      const y = window.scrollY;
      if (y > 8 && lastY <= 8) nav.style.background = 'rgba(10,10,15,.85)';
      if (y <= 8 && lastY > 8) nav.style.background = 'rgba(10,10,15,.62)';
      lastY = y;
    };
    window.addEventListener('scroll', onScroll, { passive: true });
  }
})();
