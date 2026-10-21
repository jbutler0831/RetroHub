// Small inline SVG icons (stroke style), so the app needs no icon font or network.
const svg = (body, { fill = false, size = 16 } = {}) =>
  `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="${fill ? 'currentColor' : 'none'}" stroke="${fill ? 'none' : 'currentColor'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

window.ICONS = {
  star: (o) => svg('<path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3l-5.9 3.3 1.3-6.6-4.9-4.6 6.6-.8z"/>', { fill: true, ...o }),
  clock: (o) => svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', o),
  wrench: (o) => svg('<path d="M4 6h9M17 6h3M4 12h3M11 12h9M4 18h11M19 18h1"/><circle cx="15" cy="6" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="18" r="2"/>', o),
  play: (o) => svg('<path d="M7 4.5v15l13-7.5z"/>', { fill: true, ...o }),
  tv: (o) => svg('<rect x="2.5" y="4" width="19" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>', o),
  refresh: (o) => svg('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>', o),
  search: (o) => svg('<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>', o),
  folder: (o) => svg('<path d="M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h8.5A1.5 1.5 0 0 1 21 8.5v9A1.5 1.5 0 0 1 19.5 19h-15A1.5 1.5 0 0 1 3 17.5z"/>', o),
  gamepad: (o) => svg('<path d="M6.5 8h11a4 4 0 0 1 3.9 4.9l-1 4.3a2.3 2.3 0 0 1-3.9 1l-2.1-2.2h-4.8l-2.1 2.2a2.3 2.3 0 0 1-3.9-1l-1-4.3A4 4 0 0 1 6.5 8z"/><path d="M8 11v3M6.5 12.5h3"/><circle cx="15.5" cy="12" r=".6" fill="currentColor"/><circle cx="17" cy="13.6" r=".6" fill="currentColor"/>', o),
  check: (o) => svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', o),
  alert: (o) => svg('<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>', o),
  close: (o) => svg('<path d="M6 6l12 12M18 6L6 18"/>', o),
};
