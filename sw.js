/* SERVICE WORKER
 *
 * tries to retrieve the most up to date content
 * from the network
 * but if the network is taking too much,
 * it will serve cached content instead.
 *
 * DOCS
 * https://serviceworke.rs/strategy-network-or-cache_index_doc.html
 */
var CACHE = "hn-cache"

var inCache = [
    "/index.html"
    , "/hn.svg"
];


/* SW INSTALL */
self.addEventListener("install", function (e) {
    console.log("Service Worker being installed")
    /* Ask the service worker to keep installing until the returning promise resolves */
    e.waitUntil(precache());
});

/* SW FETCH
 * On fetch, use cache but update the entry with the latest contents from the server
 * */
self.addEventListener("fetch", function(e) {
    console.log("Service Worker serving the asset")
    /* Try network and if it fails, go for the cached copy */
    e.respondWith(fromNetwork(e.request, 400).catch(function(){
        return fromCache(e.request)
    }))
})

/* PRECACHE 
 * Open a cache and use addAll()
 * with an array of assets
 * to add all of them to the cache.
 * return a promise resolving when all the assets are added
 * */
function precache() {
  return caches.open(CACHE).then(function (cache) {
    return cache.addAll(
        inCache
    );
  });
}

/* FROM NETWORK 
 * Time limited network request.
 * if the network fails
 * or the response is not served before timeout,
 * the promise is rejected
 * */
function fromNetwork(request, timeout) {
  return new Promise(function (fulfill, reject) {
    /* Reject in case of timeout */
    var timeoutId = setTimeout(reject, timeout);
    /* Fulfill in case of success*/
    fetch(request).then(function (response) {
      clearTimeout(timeoutId);
      fulfill(response);
    /* Reject also if network fetch rejects */
    }, reject);
  });
}

/* FROM CACHE 
 * Open the cache where the assets were stored
 * and search for the requested resource.
 * notice that in case of no matching,
 * the promise still resolves
 * but it does with undefined as value
 * */
function fromCache(request) {
  return caches.open(CACHE).then(function (cache) {
    return cache.match(request).then(function (matching) {
      return matching || Promise.reject("no-match");
    });
  });
}
