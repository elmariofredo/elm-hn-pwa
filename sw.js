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
];

var timeout = 400;

/* SW INSTALL */

self.addEventListener("install", function (e) {
    console.log("Service Worker being installed");

    /* PRECACHE 
     * Open a cache and use addAll()
     * with an array of assets
     * to add all of them to the cache.
     * return a promise resolving when all the assets are added
     * */
    e.waitUntil(
        caches.open(CACHE).then (function (c) {
            c.addAll(
                inCache
            );
        }));
});

/* SW FETCH
 * On fetch, use cache but update the entry with the latest contents from the server
 * */
self.addEventListener("fetch", function(e) {
    console.log("Service Worker tries a connexion to network...");
    /* FROM NETWORK 
    /* Try network
     * Time limited network request.
     * if the network fails
     * or the response is not served before timeout,
     * the promise is rejected
     * and go for the cached copy
     * */
    e.respondWith(
        new Promise(function (getNew, useCachedContent) {

            var sto = setTimeout(useCachedContent, timeout);

            /* fullfill in case of success*/
            fetch(e.request).then(
                    function(stories) {
                        clearTimeout(sto);
                        getNew(stories);
                    }
            /* reject in case of timeout */
            , useCachedContent 
            );
        }).catch(
            /* FROM CACHE 
             * Open the cache
             * and search for the requested resource.
             * notice that in case of no matching,
             * the promise still resolves
             * but it does with undefined as value
             * */
            function (){
                caches.open(CACHE).then(
                    function (cache) {
                        cache.match(e.request).then(
                            function (matching) {
                                matching || Promise.reject("CthulhuFhtagn");
                            });
                    });
            }));
});
