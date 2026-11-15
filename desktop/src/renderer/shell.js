'use strict';

const posButton = document.querySelector('[data-view="pos"]');
const viewNav = document.querySelector('nav[aria-label="Desktop views"]');
const queueStatus = document.querySelector('#queue-status');
const ingestionStatus = document.querySelector('#ingestion-status');
const ingestionWarning = document.querySelector('#ingestion-warning');
const apiStatus = document.querySelector('#api-status');
const errorBanner = document.querySelector('#error');
const forceSyncButton = document.querySelector('#force-sync');
const credentialsButton = document.querySelector('#api-credentials');
const credentialsModal = document.querySelector('#credentials-modal');
const credentialsForm = document.querySelector('#credentials-form');
const vendorIdInput = document.querySelector('#vendor-id');
const vendorTokenInput = document.querySelector('#vendor-token');
const credentialsStatus = document.querySelector('#credentials-status');
const clearCredentialsButton = document.querySelector('#clear-credentials');
const saveCredentialsButton = document.querySelector('#save-credentials');
const copyTokenFilterButton = document.querySelector('#copy-token-filter');
const openTalabatDevToolsButton = document.querySelector(
  '#open-talabat-devtools',
);
const tokenFilterValue = document.querySelector('#token-filter-value');
let errorTimer;
let lastCredentialStatus = null;
let lastShellState = {
  activeView: 'pos',
  queue: { pending: 0, failed: 0 },
};

function formatCredentialStatus(status) {
  if (!status?.configured) {
    return {
      short: 'API: غير مضبوط',
      detail: 'الحالة: غير مضبوط — أدخل Vendor ID وتوكن JWT الرسمي.',
      configured: false,
    };
  }
  const updated = status.updatedAt
    ? new Date(status.updatedAt).toLocaleString('ar-KW')
    : '';
  return {
    short: `API: ${status.vendorId}`,
    detail: `الحالة: محفوظ ومشفّر • Vendor ${status.vendorId}${
      updated ? ` • آخر تحديث ${updated}` : ''
    } — التوكن مخفي عمدًا.`,
    configured: true,
  };
}

function syncCredentialsFormUi(status) {
  const configured = Boolean(status?.configured);
  if (configured && !vendorIdInput.value.trim()) {
    vendorIdInput.value = status.vendorId || '';
  }
  vendorTokenInput.required = !configured;
  vendorTokenInput.placeholder = configured
    ? 'محفوظ مسبقًا — اتركه فارغًا لإعادة الفحص، أو الصق JWT جديد للتحديث'
    : 'الصق توكن Vendor API هنا';
  saveCredentialsButton.textContent = configured
    ? vendorTokenInput.value.trim()
      ? 'تحديث التوكن وتشغيل الفحص'
      : 'إعادة الفحص بالتوكن المحفوظ'
    : 'حفظ وتشغيل الفحص';
}

async function refreshCredentialStatus() {
  try {
    const status = await window.desktopShell.vendorCredentialStatus('talabat');
    const formatted = formatCredentialStatus(status);
    apiStatus.textContent = formatted.short;
    apiStatus.classList.toggle('configured', formatted.configured);
    apiStatus.classList.toggle('missing', !formatted.configured);
    credentialsStatus.textContent = formatted.detail;
    lastCredentialStatus = status;
    syncCredentialsFormUi(status);
    return status;
  } catch (error) {
    apiStatus.textContent = 'API: خطأ';
    apiStatus.classList.add('missing');
    credentialsStatus.textContent = `تعذر قراءة الحالة: ${error.message}`;
    lastCredentialStatus = null;
    syncCredentialsFormUi(null);
    return null;
  }
}

async function openCredentialsModal() {
  try {
    await window.desktopShell.setOverlay(true);
  } catch (error) {
    render({
      ...lastShellState,
      error: `تعذر فتح شاشة التوكن: ${error.message}`,
    });
    return;
  }
  credentialsModal.hidden = false;
  vendorTokenInput.value = '';
  void refreshCredentialStatus().then(() => {
    vendorIdInput.focus();
  });
}

async function closeCredentialsModal() {
  credentialsModal.hidden = true;
  vendorTokenInput.value = '';
  try {
    await window.desktopShell.setOverlay(false);
  } catch {
    // Restore best-effort; shell remains usable from the toolbar.
  }
}

function renderIngestionStatus(state) {
  if (!ingestionStatus) return;
  const mode = state.ingestion?.mode || 'login_required';
  const apiOk = state.ingestion?.apiOk === true;
  const label =
    state.ingestion?.label ||
    (mode === 'api_connected'
      ? '⚡ API شغال'
      : mode === 'dom_active'
        ? 'DOM: شغال'
        : '🔒 التوكن غير مضبوط');
  ingestionStatus.textContent = label;
  ingestionStatus.classList.toggle('api', mode === 'api_connected' && apiOk);
  ingestionStatus.classList.toggle(
    'api-down',
    mode !== 'api_connected' || !apiOk,
  );
  ingestionStatus.classList.toggle('dom', mode === 'dom_active');
  ingestionStatus.classList.toggle('login', mode === 'login_required');
  ingestionStatus.title = state.ingestion?.warning
    ? state.ingestion.warning
    : state.ingestion?.reason
      ? `${label} (${state.ingestion.reason})`
      : label;

  const warning = String(state.ingestion?.warning || '').trim();
  if (ingestionWarning) {
    if (!apiOk && warning) {
      ingestionWarning.hidden = false;
      ingestionWarning.textContent = warning;
      document.body.classList.add('has-ingestion-warning');
    } else {
      ingestionWarning.hidden = true;
      ingestionWarning.textContent = '';
      document.body.classList.remove('has-ingestion-warning');
    }
  }
}

function storeTabIsActive(store, active, stores) {
  if (active === store.id) return true;
  if (active !== store.type) return false;
  const primary = stores.find((item) => item.enabled && item.type === store.type);
  return primary?.id === store.id;
}

function renderStoreTabs(state) {
  if (!viewNav || !posButton) return;
  const stores = Array.isArray(state.stores) ? state.stores : [];
  const active = state.activeView;
  posButton.classList.toggle('active', active === 'pos');
  for (const button of viewNav.querySelectorAll('[data-store-tab]')) button.remove();
  for (const store of stores.filter((item) => item.enabled)) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.storeTab = store.id;
    button.dataset.view = store.id;
    button.textContent = store.name;
    button.classList.toggle('active', storeTabIsActive(store, active, stores));
    button.addEventListener('click', () => {
      window.desktopShell.selectView(store.id);
    });
    viewNav.append(button);
  }
}

function sanitizePortalUrl(value) {
  let text = String(value || '').trim().replace(/^['"]+|['"]+$/g, '');
  const embedded = text.match(/https?:\/\/\S+/i);
  if (embedded) return embedded[0].replace(/[),.;]+$/g, '');
  text = text.replace(/^\/+/, '');
  if (text && !/^https?:\/\//i.test(text)) text = `https://${text}`;
  return text;
}

function render(state) {
  lastShellState = state;
  renderStoreTabs(state);
  renderIngestionStatus(state);
  queueStatus.textContent = `Queue: ${state.queue.pending}`;
  if (state.queue.failed) {
    queueStatus.textContent += ` · Failed: ${state.queue.failed}`;
  }
  if (state.mockOrders?.enabled) {
    queueStatus.textContent += ` · Mock: 127.0.0.1:${state.mockOrders.port}`;
  }
  const message = state.error || state.notice || state.warnings?.[0];
  if (message) {
    clearTimeout(errorTimer);
    errorBanner.textContent = message;
    errorBanner.style.display = 'block';
    errorTimer = setTimeout(() => {
      errorBanner.style.display = 'none';
    }, 7000);
  }
}

posButton?.addEventListener('click', () => {
  window.desktopShell.selectView('pos');
});
document.querySelector('#home').addEventListener('click', () => {
  window.desktopShell.goHome();
});
document.querySelector('#reload').addEventListener('click', () => {
  window.desktopShell.reload();
});
copyTokenFilterButton?.addEventListener('click', async () => {
  const value = tokenFilterValue?.textContent?.trim() || 'vendor-portal-api';
  try {
    await navigator.clipboard.writeText(value);
    credentialsStatus.textContent = `تم نسخ الفلتر: ${value} — الصقه في Network.`;
  } catch {
    credentialsStatus.textContent =
      'تعذر النسخ تلقائيًا — حدّد الفلتر الأخضر وانسخه يدويًا.';
  }
});

openTalabatDevToolsButton?.addEventListener('click', async () => {
  openTalabatDevToolsButton.disabled = true;
  try {
    await closeCredentialsModal();
    await window.desktopShell.openTalabatDevTools();
    render({
      ...lastShellState,
      notice:
        'DevTools مفتوح على Talabat — فلتر vendor-portal-api ثم انسخ Bearer والصقه هنا.',
    });
  } catch (error) {
    render({
      ...lastShellState,
      error: `تعذر فتح Network: ${error.message}`,
    });
    await openCredentialsModal();
  } finally {
    openTalabatDevToolsButton.disabled = false;
  }
});

credentialsButton.addEventListener('click', () => {
  openCredentialsModal();
});
ingestionStatus?.addEventListener('click', () => {
  openCredentialsModal();
});
ingestionWarning?.addEventListener('click', () => {
  openCredentialsModal();
});
for (const closer of credentialsModal.querySelectorAll('[data-close-modal]')) {
  closer.addEventListener('click', () => {
    closeCredentialsModal();
  });
}
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !credentialsModal.hidden) {
    closeCredentialsModal();
  }
});

vendorTokenInput.addEventListener('input', () => {
  syncCredentialsFormUi(lastCredentialStatus);
});

credentialsForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const vendorId = vendorIdInput.value.trim();
  const token = vendorTokenInput.value.trim();
  const existing = await window.desktopShell.vendorCredentialStatus('talabat');
  const hasSaved = Boolean(existing?.configured);

  if (!vendorId) {
    render({
      ...lastShellState,
      error: 'Vendor ID مطلوب.',
    });
    return;
  }
  if (!token && !hasSaved) {
    render({
      ...lastShellState,
      error: 'الصق توكن JWT لأول مرة، أو احفظه من بوابة Vendor.',
    });
    return;
  }

  saveCredentialsButton.disabled = true;
  saveCredentialsButton.textContent = token ? 'جاري الحفظ…' : 'جاري الفحص…';
  try {
    if (token) {
      await window.desktopShell.storeTalabatCredentials({ vendorId, token });
      vendorTokenInput.value = '';
    } else {
      await window.desktopShell.pollVendorOrders('talabat');
    }
    await refreshCredentialStatus();
    const state = await window.desktopShell.getState();
    render({
      ...state,
      notice: token
        ? 'تم حفظ توكن Talabat وتفعيل فحص الطلبات.'
        : 'تم إعادة فحص الطلبات بالتوكن المحفوظ.',
    });
    closeCredentialsModal();
  } catch (error) {
    render({
      ...lastShellState,
      error: `فشل حفظ/فحص التوكن: ${error.message}`,
    });
  } finally {
    saveCredentialsButton.disabled = false;
    await refreshCredentialStatus();
  }
});

clearCredentialsButton.addEventListener('click', async () => {
  clearCredentialsButton.disabled = true;
  try {
    await window.desktopShell.clearVendorCredential('talabat');
    vendorIdInput.value = '';
    vendorTokenInput.value = '';
    await refreshCredentialStatus();
    const state = await window.desktopShell.getState();
    render({
      ...state,
      notice: 'تم مسح توكن Talabat. سيستمر السحب عبر DOM.',
    });
  } catch (error) {
    render({
      ...lastShellState,
      error: `فشل مسح التوكن: ${error.message}`,
    });
  } finally {
    clearCredentialsButton.disabled = false;
  }
});

const storesModal = document.querySelector('#stores-modal');
const storesList = document.querySelector('#stores-list');
const storesForm = document.querySelector('#stores-form');
const storesMessage = document.querySelector('#stores-message');
const manageStoresButton = document.querySelector('#manage-stores');

async function renderStores() {
  const stores = await window.desktopShell.listStores();
  storesList.replaceChildren(
    ...stores.map((store) => {
      const item = document.createElement('li');
      const label = document.createElement('span');
      label.textContent = `${store.name} · ${store.type}${store.enabled ? '' : ' · متوقف'}`;
      const actions = document.createElement('span');
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.textContent = store.enabled ? 'إيقاف' : 'تشغيل';
      toggle.addEventListener('click', async () => {
        await window.desktopShell.toggleStoreStatus(store.id, !store.enabled);
        await renderStores();
      });
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.textContent = 'حذف';
      remove.addEventListener('click', async () => {
        await window.desktopShell.removeStore(store.id);
        await renderStores();
      });
      const open = document.createElement('button');
      open.type = 'button';
      open.textContent = 'فتح';
      open.addEventListener('click', () => {
        void window.desktopShell.openStore(store.id).catch((error) => {
          storesMessage.textContent = error.message;
        });
      });
      actions.append(open, toggle, remove);
      item.append(label, actions);
      return item;
    }),
  );
}

async function openStoresModal() {
  storesMessage.textContent = '';
  await window.desktopShell.setOverlay(true);
  storesModal.hidden = false;
  await renderStores();
}

async function closeStoresModal() {
  storesModal.hidden = true;
  try {
    await window.desktopShell.setOverlay(false);
  } catch {
    // The toolbar stays usable if the overlay flag fails.
  }
}

manageStoresButton.addEventListener('click', () => {
  void openStoresModal().catch((error) => {
    storesMessage.textContent = error.message;
  });
});
storesModal.querySelectorAll('[data-close-stores]').forEach((button) => {
  button.addEventListener('click', () => {
    void closeStoresModal();
  });
});
storesForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  storesMessage.textContent = '';
  try {
    const urlInput = document.querySelector('#store-url');
    urlInput.value = sanitizePortalUrl(urlInput.value);
    await window.desktopShell.addStore({
      name: document.querySelector('#store-name').value,
      type: document.querySelector('#store-type').value,
      url: urlInput.value,
      enabled: true,
    });
    storesForm.reset();
    await renderStores();
  } catch (error) {
    storesMessage.textContent = error.message;
  }
});

forceSyncButton.addEventListener('click', async () => {
  forceSyncButton.disabled = true;
  forceSyncButton.textContent = 'Syncing…';
  try {
    await window.desktopShell.forceSync();
    const state = await window.desktopShell.getState();
    render({ ...state, notice: 'Platform order sync started.' });
  } catch (error) {
    render({
      activeView: 'pos',
      queue: { pending: 0, failed: 0 },
      error: `Sync failed to start: ${error.message}`,
    });
  } finally {
    forceSyncButton.disabled = false;
    forceSyncButton.textContent = 'Force Sync Orders';
  }
});

window.desktopShell.onState(render);
window.desktopShell
  .getState()
  .then((state) => {
    render(state);
    return refreshCredentialStatus();
  })
  .catch((error) => {
    render({
      activeView: 'pos',
      queue: { pending: 0, failed: 0 },
      error: error.message,
    });
  });
