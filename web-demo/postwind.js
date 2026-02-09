window.PostWind = (() => {
  const breakpoints = {};
  const shortcuts = {};
  const cache = {};
  const style = document.createElement('style');
  style.id = 'pw-styles';
  document.head.appendChild(style);

  // IntersectionObserver for visible: prefix
  const visibleObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      entry.target.classList.toggle('pw-visible', entry.isIntersecting);
    }
  }, { threshold: 0.5 });
  const observedElements = new WeakSet();

  function twRule(className) {
    const needle = '.' + CSS.escape(className);
    for (const sheet of document.styleSheets) {
      try {
        for (const layer of sheet.cssRules) {
          if (!layer.cssRules) continue;
          for (const rule of layer.cssRules) {
            if (rule.selectorText === needle) {
              const match = rule.cssText.match(/\{\s*([^}]+)\s*\}/);
              return match ? match[1].trim() : null;
            }
          }
        }
      } catch(e) {}
    }
    return null;
  }

  // get full cssText (including nested media/hover blocks)
  function twFull(className) {
    const needle = '.' + CSS.escape(className);
    for (const sheet of document.styleSheets) {
      try {
        for (const layer of sheet.cssRules) {
          if (!layer.cssRules) continue;
          for (const rule of layer.cssRules) {
            if (rule.selectorText === needle) {
              return rule.cssText;
            }
          }
        }
      } catch(e) {}
    }
    return null;
  }

  function twCSS(className) {
    const el = document.createElement('div');
    el.className = className;
    document.body.appendChild(el);
    return new Promise(resolve => {
      requestAnimationFrame(() => {
        resolve(twRule(className));
        el.remove();
      });
    });
  }

  function breakpoint(name, media) {
    breakpoints[name] = media;
  }

  // extract inner block from ".selector { ...inner... }"
  function extractInner(cssText) {
    const first = cssText.indexOf('{');
    const last = cssText.lastIndexOf('}');
    if (first === -1 || last === -1) return null;
    return cssText.substring(first + 1, last).trim();
  }

  function shortcut(name, classes) {
    shortcuts[name] = classes;
  }

  function resolveShortcut(name) {
    const classes = shortcuts[name];
    if (!classes) return Promise.resolve(null);
    const list = classes.split(/\s+/);

    // expand nested shortcuts
    const expanded = [];
    for (const cls of list) {
      if (shortcuts[cls]) {
        expanded.push(...shortcuts[cls].split(/\s+/));
      } else {
        expanded.push(cls);
      }
    }

    const el = document.createElement('div');
    el.className = expanded.join(' ');
    document.body.appendChild(el);

    return new Promise(resolve => {
      requestAnimationFrame(() => {
        const parts = [];
        for (const cls of expanded) {
          const full = twFull(cls);
          if (full) parts.push(extractInner(full));
        }
        el.remove();
        if (!parts.length) return resolve(null);
        resolve(`.${CSS.escape(name)} { ${parts.join(' ')} }`);
      });
    });
  }

  // unit-suffix pattern: p-10px -> p-[10px], mt-2rem -> mt-[2rem], w-50% -> w-[50%]
  const unitRe = /^(.+-)(\d+(?:\.\d+)?)(px|rem|em|vh|vw|vmin|vmax|%|ch|ex|cap|lh|dvh|dvw|svh|svw|cqw|cqh)$/;

  // colon-responsive pattern: p-10:20 or p-10:20:30 (but NOT m:flex, d:block, visible:x)
  // detected by: contains ":" AND the part before first ":" contains "-" with a value
  function isColonResponsive(className) {
    const first = className.indexOf(':');
    if (first === -1) return false;
    const before = className.substring(0, first);
    // must have a dash followed by a value (e.g. "p-10", "grid-cols-1", "text-xl")
    // skip known prefixes and pseudo-classes
    return before.includes('-') && !before.startsWith('visible');
  }

  function resolvePipe(className, parts) {
    const base = parts[0];
    const dashIdx = base.lastIndexOf('-');
    const prop = dashIdx !== -1 ? base.substring(0, dashIdx + 1) : '';
    const sel = CSS.escape(className);

    // resolve each part, expanding unit suffixes
    function expandClass(val) {
      const cls = prop + val;
      const m = cls.match(unitRe);
      return m ? `${m[1]}[${m[2]}${m[3]}]` : cls;
    }

    if (parts.length === 2) {
      const tabletClass = expandClass(parts[1]);
      const baseClass = (() => { const m = base.match(unitRe); return m ? `${m[1]}[${m[2]}${m[3]}]` : base; })();
      return Promise.all([twCSS(baseClass), twCSS(tabletClass)]).then(([bCss, tCss]) => {
        const rules = [];
        if (bCss) rules.push(`.${sel} { ${bCss} }`);
        if (tCss) rules.push(`${breakpoints.t} { .${sel} { ${tCss} } }`);
        return rules.length ? rules.join('\n') : null;
      });
    }

    if (parts.length === 3) {
      const tabletClass = expandClass(parts[1]);
      const desktopClass = expandClass(parts[2]);
      const baseClass = (() => { const m = base.match(unitRe); return m ? `${m[1]}[${m[2]}${m[3]}]` : base; })();
      return Promise.all([twCSS(baseClass), twCSS(tabletClass), twCSS(desktopClass)]).then(([bCss, tCss, dCss]) => {
        const rules = [];
        if (bCss) rules.push(`.${sel} { ${bCss} }`);
        if (tCss) rules.push(`${breakpoints.t} { .${sel} { ${tCss} } }`);
        if (dCss) rules.push(`${breakpoints.d} { .${sel} { ${dCss} } }`);
        return rules.length ? rules.join('\n') : null;
      });
    }

    return Promise.resolve(null);
  }

  function resolve(className) {
    // shortcut?
    if (shortcuts[className]) return resolveShortcut(className);

    // pipe notation: p-4|12, p-4|8|12
    if (className.includes('|')) {
      return resolvePipe(className, className.split('|'));
    }

    // colon-responsive: p-10:20, p-10:20:30 (colon as pipe alias)
    if (isColonResponsive(className)) {
      return resolvePipe(className, className.split(':'));
    }

    // unit-suffix: p-10px -> p-[10px], mt-2rem -> mt-[2rem]
    const unitMatch = className.match(unitRe);
    if (unitMatch) {
      const twClass = `${unitMatch[1]}[${unitMatch[2]}${unitMatch[3]}]`;
      return twCSS(twClass).then(css => {
        if (!css) return null;
        return `.${CSS.escape(className)} { ${css} }`;
      });
    }

    // visible: prefix — activated by IntersectionObserver
    if (className.startsWith('visible:')) {
      const base = className.substring(8);
      return twCSS(base).then(css => {
        if (!css) return null;
        return `.pw-visible.${CSS.escape(className)} { ${css} }`;
      });
    }

    // prefix notation: m:p-10, d:flex, t:block
    const sep = className.indexOf(':');
    if (sep === -1) return twCSS(className).then(css =>
      css ? `.${CSS.escape(className)} { ${css} }` : null
    );

    const prefix = className.substring(0, sep);
    const base = className.substring(sep + 1);
    const media = breakpoints[prefix];

    if (prefix === 'm') {
      console.warn(`PostWind: "${className}" — m: prefix is unnecessary. PostWind is mobile-first, so "${base}" is already the mobile default. Use "${base}" directly and t:/d: for larger screens.`);
    }

    if (!media) return twCSS(className).then(css =>
      css ? `.${CSS.escape(className)} { ${css} }` : null
    );

    return twCSS(base).then(css => {
      if (!css) return null;
      return `${media} { .${CSS.escape(className)} { ${css} } }`;
    });
  }

  function inject(className) {
    if (cache[className]) return cache[className];
    const p = resolve(className).then(css => {
      if (css && !cache[className]._injected) {
        style.textContent += css + '\n';
        cache[className]._injected = true;
      }
      return css;
    });
    p._injected = false;
    cache[className] = p;
    return p;
  }

  // observe an element for visible: classes
  function observeVisible(el) {
    if (observedElements.has(el)) return;
    observedElements.add(el);
    visibleObserver.observe(el);
  }

  // check if a class needs PostWind processing
  function needsProcessing(cls) {
    if (shortcuts[cls]) return true;
    if (cls.startsWith('visible:')) return true;
    if (cls.includes('|')) return true;
    if (isColonResponsive(cls)) return true;
    if (unitRe.test(cls)) return true;
    return false;
  }

  // process a single element: inject CSS for PostWind classes, observe visible: elements
  function processElement(el) {
    for (const cls of el.classList) {
      if (cls.startsWith('visible:')) {
        observeVisible(el);
        inject(cls);
      } else if (shortcuts[cls]) {
        inject(cls);
      } else if (needsProcessing(cls)) {
        inject(cls);
      }
    }
  }

  // scan DOM for all PostWind classes
  function initClasses(root) {
    const all = (root || document).querySelectorAll('*');
    for (const el of all) {
      if (!el.className || typeof el.className !== 'string') continue;
      for (const cls of el.classList) {
        if (needsProcessing(cls)) {
          processElement(el);
          break;
        }
      }
    }
  }

  // auto-scan: wait for both DOM and Tailwind before scanning
  function autoInit() {
    function scan() {
      if (!_ready) {
        requestAnimationFrame(scan);
        return;
      }
      _ready.then(() => initClasses());
    }
    scan();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoInit);
  } else {
    autoInit();
  }

  // MutationObserver to catch dynamically added elements and class attribute changes
  const domObserver = new MutationObserver((mutations) => {
    if (!_ready) return;
    _ready.then(() => {
      for (const m of mutations) {
        if (m.type === 'attributes') {
          if (m.target.nodeType === 1) processElement(m.target);
          continue;
        }
        for (const node of m.addedNodes) {
          if (node.nodeType !== 1) continue;
          if (node.className && typeof node.className === 'string') {
            processElement(node);
          }
          const children = node.querySelectorAll?.('*');
          if (children) {
            for (const child of children) {
              if (child.className && typeof child.className === 'string') {
                processElement(child);
              }
            }
          }
        }
      }
    });
  });
  domObserver.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] });

  // load Tailwind browser runtime
  // returns a Promise that resolves when Tailwind is loaded and has processed the page
  let _ready = null;

  function init(opts) {
    if (opts) {
      if (opts.breakpoints) {
        for (const [name, media] of Object.entries(opts.breakpoints)) {
          breakpoint(name, media);
        }
      }
      if (opts.shortcuts) {
        for (const [name, classes] of Object.entries(opts.shortcuts)) {
          shortcut(name, classes);
        }
      }
    }

    // already loaded or loading
    if (_ready) return _ready;

    // skip Tailwind CDN unless explicitly requested
    if (!opts || !opts.tailwind) {
      _ready = Promise.resolve();
      return _ready;
    }

    // Tailwind already on page (loaded via <script> tag)
    if (document.querySelector('script[src*="tailwindcss/browser"]')) {
      _ready = _waitForTailwind();
      return _ready;
    }

    // inject Tailwind and wait for it
    _ready = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4';
      s.onload = () => _waitForTailwind().then(resolve);
      s.onerror = () => reject(new Error('Failed to load Tailwind'));
      document.head.appendChild(s);
    });
    return _ready;
  }

  // wait for Tailwind to generate its stylesheet
  function _waitForTailwind() {
    return new Promise(resolve => {
      function check() {
        // Tailwind browser creates a <style> with data-tailwindcss
        for (const sheet of document.styleSheets) {
          try {
            if (sheet.ownerNode?.hasAttribute?.('data-tailwindcss')) {
              resolve();
              return;
            }
          } catch(e) {}
        }
        // also check if any sheet has @layer rules (tailwind output)
        for (const sheet of document.styleSheets) {
          try {
            for (const rule of sheet.cssRules) {
              if (rule.constructor.name === 'CSSLayerBlockRule') {
                resolve();
                return;
              }
            }
          } catch(e) {}
        }
        requestAnimationFrame(check);
      }
      check();
    });
  }

  inject.init = init;
  inject.ready = () => _ready || Promise.resolve();
  inject.breakpoint = breakpoint;
  inject.shortcut = shortcut;
  inject.resolve = resolve;
  inject.twCSS = twCSS;
  inject.cache = cache;
  inject.observeVisible = observeVisible;

  // default breakpoints
  breakpoint('m', '@media (max-width: 767px)');
  breakpoint('t', '@media (min-width: 768px)');
  breakpoint('d', '@media (min-width: 1024px)');

  return inject;
})();
