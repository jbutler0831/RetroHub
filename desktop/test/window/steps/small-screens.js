// Small screens such as a Raspberry Pi's 800×480 or 640×480 display, and 320×240: couch mode
// (what --console opens) and the browser must fit without anything cut off or scrolling sideways.
const SIZES = [[800, 480], [640, 480], [320, 240]];

/**
 * Elements that stick out of the window. Content that scrolls by design is left out: the
 * carousel's covers, the couch tabs, and what's inside the sidebar and the game list.
 */
const overflow = (root) => `[...document.querySelectorAll(${JSON.stringify(root)} + ' *')]
  .filter((el) => !el.closest('.carousel, .couch-backdrop, .tabs, #nav, #content') && el.getClientRects().length)
  .filter((el) => { const r = el.getBoundingClientRect(); return r.width && (r.left < -1 || r.right > innerWidth + 1 || r.bottom > innerHeight + 1); })
  .map((el) => (el.className && typeof el.className === 'string' ? '.' + el.className.split(' ')[0] : el.tagName.toLowerCase()) + (el.textContent.trim() ? ' "' + el.textContent.trim().slice(0, 20) + '"' : ''))
  .slice(0, 6)`;

module.exports = {
  async run({ evaluate, check, log, shot, click, wait, send }) {
    await click('[data-key="sys:nes"]');
    for (const [width, height] of SIZES) {
      log(`- ${width}×${height}`);
      await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
      await wait(400);
      await click('#couch-button');
      await wait(1200);
      const out = await evaluate(overflow('#couch'));
      check(out.length === 0, `couch mode fits: ${out.length ? out.join(', ') : 'nothing cut off'}`);
      const cover = await evaluate(`(() => { const r = document.querySelector('.carousel .cover.current').getBoundingClientRect();
        return r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight; })()`);
      check(cover, 'the current cover is fully on screen');
      const tab = await evaluate(`(() => { const t = document.querySelector('.tab.active').getBoundingClientRect(),
        row = document.querySelector('.couch-tabs .tabs').getBoundingClientRect();
        return t.left >= row.left - 1 && t.right <= row.right + 1; })()`);
      check(tab, 'the current list\'s tab is in view');
      await shot(`couch ${width}x${height}`);
      await click('[data-exit]');
      await wait(1200);
      if (width >= 640) {
        const sideways = await evaluate(`document.documentElement.scrollWidth > innerWidth || document.getElementById('app').scrollWidth > innerWidth`);
        const browser = await evaluate(overflow('#app'));
        check(!sideways && browser.length === 0, `the browser fits: ${browser.length ? browser.join(', ') : 'nothing cut off'}`);
        await shot(`browser ${width}x${height}`);
      }
    }
    await send('Emulation.clearDeviceMetricsOverride');
  },
};
