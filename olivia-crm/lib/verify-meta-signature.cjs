const { createHmac, timingSafeEqual } = require('node:crypto');

// Verify the exact bytes received, before parsing or trusting the payload.
function verifyMetaSignature(rawBody, signature, appSecret) {
 if (!Buffer.isBuffer(rawBody) || typeof appSecret !== 'string' || !appSecret ||
     typeof signature !== 'string' || !/^sha256=[0-9a-f]{64}$/i.test(signature)) return false;
 const received = Buffer.from(signature.slice(7), 'hex');
 const expected = createHmac('sha256', appSecret).update(rawBody).digest();
 return received.length === expected.length && timingSafeEqual(received, expected);
}
module.exports = { verifyMetaSignature };
