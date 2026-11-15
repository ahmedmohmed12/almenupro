'use strict';

class ViewManager {
  constructor({ window, toolbarHeight = 64, onActiveChanged = () => {} }) {
    this.window = window;
    this.toolbarHeight = toolbarHeight;
    this.onActiveChanged = onActiveChanged;
    this.views = new Map();
    this.activeName = null;
    this.shellOverlayVisible = false;
  }

  add(name, view) {
    this.views.set(name, view);
    if (!this.window.isDestroyed()) {
      this.window.contentView.addChildView(view);
      view.setBounds(this.backgroundBounds());
    }
    return view;
  }

  has(name) {
    return this.views.has(name);
  }

  get(name) {
    return this.views.get(name);
  }

  bounds() {
    const [width, height] = this.window.getContentSize();
    return {
      x: 0,
      y: this.toolbarHeight,
      width,
      height: Math.max(0, height - this.toolbarHeight),
    };
  }

  backgroundBounds() {
    return { x: -10000, y: 0, width: 1280, height: 800 };
  }

  show(name) {
    const next = this.views.get(name);
    if (!next || this.window.isDestroyed()) return false;
    const current = this.views.get(this.activeName);
    if (current === next) {
      if (!this.shellOverlayVisible) next.setBounds(this.bounds());
      return true;
    }
    if (current) current.setBounds(this.backgroundBounds());
    this.activeName = name;
    // Re-adding moves the selected view to the top without detaching the
    // provider views that must keep rendering and synchronizing off-screen.
    this.window.contentView.removeChildView(next);
    this.window.contentView.addChildView(next);
    if (this.shellOverlayVisible) {
      next.setBounds(this.backgroundBounds());
    } else {
      next.setBounds(this.bounds());
      next.webContents.focus();
    }
    this.onActiveChanged(name);
    return true;
  }

  /**
   * Hide all WebContentsViews so the shell HTML overlay (modals) can receive
   * clicks. Native views always paint above the BrowserWindow page layer.
   */
  setShellOverlayVisible(visible) {
    this.shellOverlayVisible = Boolean(visible);
    if (this.window.isDestroyed()) return false;
    if (this.shellOverlayVisible) {
      for (const view of this.views.values()) {
        view.setBounds(this.backgroundBounds());
      }
      return true;
    }
    this.layout();
    this.views.get(this.activeName)?.webContents.focus();
    return true;
  }

  layout() {
    if (this.shellOverlayVisible) {
      for (const view of this.views.values()) {
        view.setBounds(this.backgroundBounds());
      }
      return;
    }
    this.views.get(this.activeName)?.setBounds(this.bounds());
  }

  destroy() {
    const unique = new Set(this.views.values());
    for (const view of unique) {
      if (!view.webContents.isDestroyed()) view.webContents.close();
    }
    this.views.clear();
    this.activeName = null;
  }

  release(view) {
    for (const [name, candidate] of [...this.views.entries()]) {
      if (candidate === view) this.views.delete(name);
    }
    if (this.activeName && !this.views.has(this.activeName)) this.activeName = null;
    if (!this.window.isDestroyed()) {
      try {
        this.window.contentView.removeChildView(view);
      } catch {
        // The view may already have been detached.
      }
    }
    if (!view.webContents.isDestroyed()) view.webContents.close();
  }
}

module.exports = { ViewManager };
