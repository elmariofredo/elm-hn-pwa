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



/* VARIABLES 
 * */


var SHELL = "hn-shell";

var DATA = "hn-items";

var STORIES = "hn-stories";

var now = Date.now;

var inCache = [
    "/"
    , "/index.html"
    , "/hn.svg"
    , "/off"
];

var api = "https://hacker-news.firebaseio.com/";

var versioning = "v0";

var endpoint = api + versioning + "/item/";

var timeout = 800;

var maxItems = 30;



/* FUNCTIONS
 * */


// get first max items from json array
// which is returned in response of request
function jsonify(response) {
    return Promise.resolve(response).then(
        function (r) {
            return r.json().then(
                function (json) {
                    return json.slice(0, maxItems);
                }
            );
        }
    );
}


// get item from cache
// elsewise from network
function getItem(request){

    return self.caches.open(DATA).then(
        function (cache) {
            return cache.match(request).then(
                // get json object in cache
                // or fetch a request if not cached
                function (jsonCache) {
                    return jsonCache || putInCache(request);
                }
            );
        }
    );
}


function getStories(request) {

    var p = new Promise(
        function (listOf, nothing) {
            // fetch async request
            return fetch(request).then(
                // if response
                function (ids) {
                    return self.caches.open(STORIES).then(
                        // put in cache for next use
                        function (cache) {
                            return cache.put(request, ids.clone()).then(
                                listOf(ids)
                            );
                        }
                    );
                }
                // elsewise nothing
                , nothing
            );
        }
    );

    var cached = self.caches.open(STORIES).then(
        function (cache) {
            return cache.match(request).then(
                // get json object in cache
                // or fetch a request if not cached
                function (jsonCache) {
                    return jsonCache || p;
                }
            ).catch(
                function () {
                    return self.caches.open(SHELL).then(
                        function (c) {
                            return c.match("/off").then(
                                function (page) {
                                    console.log("getting offline...");
                                    var j = [ 2501 ];
                                    var r = new Response(JSON.stringify(j), {headers: {"Content-Type": "application/json"}, status: 200});
                                    return Promise.resolve(r);

                                }
                            )
                        }
                    )
                }
            )
        }
    );

    return cached;
}


// put result for item page
// in cache
// keyed by its url
// value is a json array
function putInCache(request) {

    function is2501(req) {
        if (req.url === endpoint + "2501.json") {
            return true;
        }
        else {
            return false;
        }
    } 
    
    if (is2501(request) === false) {
        return new Promise(
            function (item, nothing) {
                return fetch(request).then(
                    function (response) {

                        return self.caches.open(DATA).then(
                            function (cache) {
                                return cache.add(request).then(
                                    item(response)
                                );
                            }
                        );
                    }

                    , nothing
                );
            }
        );
    }

    else {
        var off = {
            time : Math.ceil(Date.now() / 1000)
            , by : "skingrapher"
            , title : "WARNING: you are offline"
            , id : 2501
            , type: "story"
        };

        return Promise.resolve(
            new Response(JSON.stringify(off), {headers: {"Content-Type": "application/json"}, status: 200})
        );

    }
}


/* SW INSTALL 
 * */


self.addEventListener("install", function (e) {

    e.waitUntil(
        // put site in cache
        caches.open(SHELL).then(
            function (c) {
                return c.addAll(
                    inCache
                );
            }
        )
        .then(
            function () {
                // new SW becomes active immediately
                return self.skipWaiting();
            }
        )
    );
});



/* SW ACTIVATE 
 * */


self.addEventListener("activate", function (e) {

    e.waitUntil(
        // set SW itself as controller for all clients within its scope
        self.clients.claim()
    );
});



/* SW FETCH
 * */


self.addEventListener("fetch", function (e) {

    var req = e.request;
    var url = new URL(req.url);
    //var url = req.url;
    var item ="\/item\/";
    var isItemUrl = url.pathname.match(item);
    var stories = "stories";
    var isStoriesUrl = url.pathname.match(stories);

    // item request
    if (isItemUrl != null) {
        e.respondWith(
            getItem(req)
        );
        /*
        if (req.url === endpoint + "2501.json") {
            e.respondWith(
                function() {
                }
            );
        }
        */
    }

    // stories request
    else if (isStoriesUrl != null) {
        e.respondWith(
            getStories(req)
        );
    }

});
