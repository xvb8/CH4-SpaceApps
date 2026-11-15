// Stand-in for photos.js in the sandboxed Snowflake build, which has no network
// access: image lookups are switched off and the image slots stay hidden.

export function photosAvailable() { return false; }

export function imagesFor() { return Promise.resolve(null); }
