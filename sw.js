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


var DATA = "elm-hn-pwa";

//var DATA = "hn-items";

//var STORIES = "hn-stories";

var now = Date.now;

var api = "https://hacker-news.firebaseio.com/";

var versioning = "v0";

var endpoint = api + versioning + "/item/";

var timeout = 800;

var maxItems = 30;

var hn = ["/top", "/new", "/show", "/ask", "/job"];

var stories = [
    api + versioning + hn[0] + "stories.json"
    , api + versioning + hn[1] + "stories.json"
    , api + versioning + hn[2] + "stories.json"
    , api + versioning + hn[3] + "stories.json"
    , api + versioning + hn[4] + "stories.json"
]

var shell = [
    "/"
    , "/index.html"
    , "/hn.svg"
];


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


function R(json){
    var h = {"Content-Type": "application/json"};

    return new Response(json, { headers : h, status: 200 });
}


// get item from cache
// elsewise from network
function getItem(request){

    var iid = request.url.split("/").reverse().shift().split(".").shift();

    return self.caches.open(DATA).then(
        function (cache) {
            return cache.match(request).then(
                // get json object in cache
                // or fetch a request if not cached
                function (jsonCache) {

                    if(jsonCache != undefined && jsonCache.bodyUsed === false){
                        var item = jsonCache.clone();
                    }

                    var f = fetch(request).then(
                        function (i) {
                            cache.put(request, i.clone());
                            return i;
                        }
                    ).catch(
                        function () {
                            if (item != undefined) {
                                var j = item.clone().json();
                            }

                            else {
                                // ;) GITS
                                var haydali = {
                                    time : Math.ceil(Date.now() / 1000)
                                    , by : "skingrapher"
                                    , title : "<span class='warning'>WARNING: entry "+iid+" will be updated after going back online</span>"
                                    , id : 2501
                                    , type: "story"
                                };

                                var j = JSON.stringify(haydali);
                            }
                            return R(j);
                        }
                    )

                    return jsonCache || f;
                }
            );
        }
    );
}


function getStories(request) {

    // stale while revalidate
    // https://jakearchibald.com/2014/offline-cookbook/#stale-while-revalidate
    var cached = self.caches.open(DATA).then(
        function (cache) {
            return cache.match(request).then(
                // get json object in cache
                // or fetch a request if not cached
                function (jsonCache) {

                    if(jsonCache != undefined && jsonCache.bodyUsed === false){
                        var list = jsonCache.clone();
                    }

                    // stories cache update 
                    var fetching = Promise.all(stories.map(s => Promise.resolve(fetch(s).then(function(i){cache.put(s,i.clone());return i})))).then(
                        function () {
                            return cache.match(request)
                        }
                    );

                    fetching.catch(
                        // fallback cache if fetching failed
                        function () {
                            return cache.match(request)
                        }
                    );

                    return list || fetching;
                }
            )
        }
    );

    return cached;
}


/* SW INSTALL 
 * */


self.addEventListener("install", function (e) {

    e.waitUntil(
        // put site in cache
        caches.open(DATA).then(
            function (c) {
                return c.addAll(
                    shell
                    , stories
                );
            }
        )
        .then(
            function () {
                // new SW becomes active immediately
                return self.skipWaiting();
            }
        )
    )
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
    }

    // stories request
    else if (isStoriesUrl != null) {
        e.respondWith(
            getStories(req)
        );
    }
});
