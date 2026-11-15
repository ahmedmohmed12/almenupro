'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { ViewManager } = require('../src/views/view-manager');

function fakeView() {
  return {
    bounds: null,
    setBounds(value) {
      this.bounds = value;
    },
    webContents: {
      focused: false,
      closed: false,
      focus() {
        this.focused = true;
      },
      isDestroyed() {
        return false;
      },
      close() {
        this.closed = true;
      },
    },
  };
}

test('view manager switches and lays out WebContentsView instances', () => {
  const children = [];
  const window = {
    isDestroyed: () => false,
    getContentSize: () => [1200, 800],
    contentView: {
      addChildView: (view) => children.push(view),
      removeChildView: (view) => children.splice(children.indexOf(view), 1),
    },
  };
  const manager = new ViewManager({ window, toolbarHeight: 64 });
  const pos = manager.add('pos', fakeView());
  const talabat = manager.add('talabat', fakeView());

  assert.equal(manager.show('pos'), true);
  assert.deepEqual(pos.bounds, { x: 0, y: 64, width: 1200, height: 736 });
  manager.show('talabat');
  assert.deepEqual(children, [pos, talabat]);
  assert.deepEqual(pos.bounds, {
    x: -10000,
    y: 0,
    width: 1280,
    height: 800,
  });
  assert.equal(talabat.webContents.focused, true);

  manager.setShellOverlayVisible(true);
  assert.deepEqual(talabat.bounds, {
    x: -10000,
    y: 0,
    width: 1280,
    height: 800,
  });
  manager.setShellOverlayVisible(false);
  assert.deepEqual(talabat.bounds, { x: 0, y: 64, width: 1200, height: 736 });

  manager.destroy();
  assert.equal(pos.webContents.closed, true);
  assert.equal(talabat.webContents.closed, true);
});
