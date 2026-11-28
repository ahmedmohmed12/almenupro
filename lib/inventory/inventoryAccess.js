'use strict';

const { isInventoryEnabled } = require('../diningTables');

async function findRestaurant(readRestaurants, tenantId) {
  const restaurants = await readRestaurants();
  return restaurants.find((entry) => String(entry.id) === String(tenantId));
}

async function inventoryEnabledForTenant(readRestaurants, tenantId) {
  const restaurant = await findRestaurant(readRestaurants, tenantId);
  if (!restaurant) return false;
  return isInventoryEnabled(restaurant);
}

/**
 * Gate inventory HTTP routes — returns true when the response was sent (blocked).
 */
async function rejectIfInventoryDisabled(res, sendJson, readRestaurants, tenantId) {
  const enabled = await inventoryEnabledForTenant(readRestaurants, tenantId);
  if (enabled) return false;
  sendJson(res, 403, {
    error: 'إدارة المخزون غير مفعّلة لهذا المطعم',
    code: 'INVENTORY_DISABLED',
    inventoryEnabled: false,
  });
  return true;
}

module.exports = {
  findRestaurant,
  inventoryEnabledForTenant,
  rejectIfInventoryDisabled,
  isInventoryEnabled,
};