'use strict';

const TALABAT_LANDING_PATHS = new Set(['/', '/dashboard']);

function normalizedPath(rawUrl) {
  try {
    const path = new URL(rawUrl).pathname.replace(/\/+$/, '');
    return path || '/';
  } catch {
    return '';
  }
}

function orderScreenRedirect(provider, currentUrl, candidates) {
  if (provider !== 'talabat' || !TALABAT_LANDING_PATHS.has(normalizedPath(currentUrl))) {
    return '';
  }
  return (
    (Array.isArray(candidates) ? candidates : []).find(
      (candidate) =>
        normalizedPath(candidate) &&
        normalizedPath(candidate) !== normalizedPath(currentUrl),
    ) || ''
  );
}

module.exports = { normalizedPath, orderScreenRedirect };
