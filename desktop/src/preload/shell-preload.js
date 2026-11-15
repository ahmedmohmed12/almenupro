'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('desktopShell', {
  selectView: (view) => ipcRenderer.send('shell:select-view', view),
  reload: () => ipcRenderer.send('shell:reload'),
  goHome: () => ipcRenderer.send('shell:home'),
  forceSync: () => ipcRenderer.invoke('shell:force-sync'),
  getState: () => ipcRenderer.invoke('shell:get-state'),
  setOverlay: (visible) => ipcRenderer.invoke('shell:set-overlay', visible),
  openTalabatDevTools: () => ipcRenderer.invoke('shell:open-talabat-devtools'),
  saveVendorCredential: (provider, vendorId, authToken) =>
    ipcRenderer.invoke('vendor-credentials:save', {
      provider,
      vendorId,
      authToken,
    }),
  storeTalabatCredentials: ({ vendorId, token }) =>
    ipcRenderer.invoke('vendor-credentials:save', {
      provider: 'talabat',
      vendorId,
      authToken: token,
    }),
  vendorCredentialStatus: (provider) =>
    ipcRenderer.invoke('vendor-credentials:status', provider),
  clearVendorCredential: (provider) =>
    ipcRenderer.invoke('vendor-credentials:clear', provider),
  pollVendorOrders: (provider) =>
    ipcRenderer.invoke('vendor-orders:poll-now', provider),
  onOrderIngested: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('shell:order-ingested', listener);
    return () => ipcRenderer.removeListener('shell:order-ingested', listener);
  },
  onIncomingOrder: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const listener = (_event, order) => callback(order);
    ipcRenderer.on('incoming-order', listener);
    return () => ipcRenderer.removeListener('incoming-order', listener);
  },
  onState: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on('shell:state', listener);
    return () => ipcRenderer.removeListener('shell:state', listener);
  },
  listStores: () => ipcRenderer.invoke('list-stores'),
  addStore: (store) => ipcRenderer.invoke('add-store', store),
  removeStore: (id) => ipcRenderer.invoke('remove-store', id),
  toggleStoreStatus: (id, enabled) =>
    ipcRenderer.invoke('toggle-store-status', { id, enabled }),
  openStore: (id) => ipcRenderer.invoke('open-store', id),
});
