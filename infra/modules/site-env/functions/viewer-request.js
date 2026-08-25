// Basic auth at the edge. Runs before the cache, so an unauthorized request
// never reaches the origin or a cached object.
//
// The 401 carries its own noindex header: a response headers policy does not
// apply to a response this function generates.
import cf from 'cloudfront';

const store = cf.kvs();

function deny(statusCode, statusDescription) {
  return {
    statusCode: statusCode,
    statusDescription: statusDescription,
    headers: {
      'www-authenticate': { value: 'Basic realm="${realm}", charset="UTF-8"' },
      'x-robots-tag': { value: 'noindex, nofollow' },
      'cache-control': { value: 'no-store' },
    },
  };
}

async function handler(event) {
  const request = event.request;
  const header = request.headers.authorization;

  let expected;
  try {
    expected = await store.get('${auth_key}');
  } catch (err) {
    // Key absent or store unreachable. Fail closed — this gate is the only
    // thing keeping the environment private.
    return deny(503, 'Service Unavailable');
  }

  if (!header || header.value !== expected) {
    return deny(401, 'Unauthorized');
  }

  // OAC carries its SigV4 signature in this header. Leaving the viewer's value
  // on the request collides with it and the function URL answers 403 without
  // ever invoking the function. Rails has no use for it either.
  delete request.headers.authorization;

  return request;
}
