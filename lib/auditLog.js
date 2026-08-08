function normalizeAuditEvent(raw = {}) {
  const id =
    String(raw.id || '').trim() ||
    `audit_${Date.now()}_${Math.random().toString(36).slice(2, 6)}`;
  return {
    id,
    restaurantId: String(raw.restaurantId || raw.restaurant_id || '').trim(),
    action: String(raw.action || '').trim(),
    entityType: String(raw.entityType || raw.entity_type || '').trim(),
    entityId: String(raw.entityId || raw.entity_id || '').trim(),
    performedById: String(raw.performedById || raw.performed_by_id || '').trim(),
    performedByName: String(raw.performedByName || raw.performed_by_name || '').trim(),
    authorizedById:
      String(raw.authorizedById || raw.authorized_by_id || '').trim() || null,
    authorizedByName:
      String(raw.authorizedByName || raw.authorized_by_name || '').trim() || null,
    metadata:
      raw.metadata && typeof raw.metadata === 'object' ? raw.metadata : {},
    createdAt: raw.createdAt || new Date().toISOString(),
  };
}

function buildAuditEvent({
  restaurantId,
  action,
  entityType,
  entityId,
  performedById,
  performedByName,
  authorizedById = null,
  authorizedByName = null,
  metadata = {},
}) {
  return normalizeAuditEvent({
    restaurantId,
    action,
    entityType,
    entityId,
    performedById,
    performedByName,
    authorizedById,
    authorizedByName,
    metadata,
  });
}

module.exports = {
  normalizeAuditEvent,
  buildAuditEvent,
};
