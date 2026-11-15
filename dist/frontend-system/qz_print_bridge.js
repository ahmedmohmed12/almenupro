(function (global) {
  var scriptPromise = null;

  function loadQzLibrary() {
    if (global.qz) return Promise.resolve();
    if (scriptPromise) return scriptPromise;

    scriptPromise = new Promise(function (resolve, reject) {
      var existing = document.querySelector('script[data-almenupro-qz="1"]');
      if (existing && global.qz) {
        resolve();
        return;
      }
      var script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/qz-tray@2.2.5/qz-tray.js';
      script.async = true;
      script.setAttribute('data-almenupro-qz', '1');
      script.onload = function () {
        if (global.qz) resolve();
        else reject(new Error('QZ Tray library did not initialize'));
      };
      script.onerror = function () {
        scriptPromise = null;
        reject(new Error('QZ Tray is not installed'));
      };
      document.head.appendChild(script);
      setTimeout(function () {
        if (!global.qz) {
          scriptPromise = null;
          reject(new Error('QZ Tray library timeout'));
        }
      }, 4000);
    });
    return scriptPromise;
  }

  function withTimeout(promise, ms, message) {
    return Promise.race([
      promise,
      new Promise(function (_, reject) {
        setTimeout(function () {
          reject(new Error(message));
        }, ms);
      }),
    ]);
  }

  function configureUnsignedSecurity() {
    try {
      global.qz.security.setCertificatePromise(function (resolve) {
        resolve();
      });
      global.qz.security.setSignaturePromise(function () {
        return function (resolve) {
          resolve();
        };
      });
    } catch (_) {}
  }

  async function printReceiptSilently(orderData) {
    var payload = orderData || {};
    var html = String(payload.html || '');
    if (!html.trim()) {
      throw new Error('Empty receipt HTML');
    }

    await loadQzLibrary();
    if (!global.qz || !global.qz.websocket) {
      throw new Error('QZ Tray is not installed');
    }

    configureUnsignedSecurity();

    if (!global.qz.websocket.isActive()) {
      await withTimeout(
        global.qz.websocket.connect({ retries: 0, delay: 0 }),
        2500,
        'QZ Tray is disconnected',
      );
    }

    var printerName = String(payload.printerName || '').trim();
    if (!printerName) {
      try {
        printerName = await withTimeout(
          global.qz.printers.getDefault(),
          2000,
          'No default printer',
        );
      } catch (_) {
        printerName = '';
      }
    }
    if (!printerName) {
      var found = await withTimeout(
        global.qz.printers.find(),
        2000,
        'No printers found',
      );
      if (Array.isArray(found) && found.length) {
        printerName = String(found[0] || '');
      }
    }
    if (!printerName) {
      throw new Error('QZ Tray has no printer');
    }

    var widthMm = Number(payload.widthMm) || 80;
    var copies = Math.max(1, Math.min(5, Number(payload.copies) || 1));
    var config = global.qz.configs.create(printerName, {
      units: 'mm',
      size: { width: widthMm },
      margins: 0,
      copies: copies,
      scaleContent: true,
      rasterize: true,
      interpolation: 'nearest-neighbor',
      colorType: 'blackwhite',
      jobName: 'AlMenuPro-' + String(payload.orderId || 'receipt'),
      altPrinting: false,
    });

    var data = [
      {
        type: 'pixel',
        format: 'html',
        flavor: 'plain',
        data: html,
        options: { pageWidth: widthMm },
      },
    ];

    await withTimeout(
      global.qz.print(config, data),
      15000,
      'QZ Tray print timed out',
    );
    return true;
  }

  global.AlMenuProQz = {
    printReceiptSilently: printReceiptSilently,
  };
})(window);
