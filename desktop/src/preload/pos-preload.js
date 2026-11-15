'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('AlMenuProDesktop', {
  syncTodaySales: () => ipcRenderer.invoke('pos:sync-today'),
  onSyncProgress: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('pos:sync-progress', listener);
    return () => ipcRenderer.removeListener('pos:sync-progress', listener);
  },
  onSyncAlert: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('pos:sync-alert', listener);
    return () => ipcRenderer.removeListener('pos:sync-alert', listener);
  },
  onPlatformSync: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('pos:sync-platform', listener);
    return () => ipcRenderer.removeListener('pos:sync-platform', listener);
  },
  onIncomingOrder: (callback) => {
    if (typeof callback !== 'function') return () => {};
    const listener = (_event, order) => callback(order);
    ipcRenderer.on('incoming-order', listener);
    return () => ipcRenderer.removeListener('incoming-order', listener);
  },
});
