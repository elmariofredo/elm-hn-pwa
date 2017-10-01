importScripts("https://unpkg.com/workbox-sw@2.0.3/build/importScripts/workbox-sw.prod.v2.0.3.js");
importScripts("https://unpkg.com/workbox-background-sync@2.0.3/build/importScripts/workbox-background-sync.prod.v2.0.3.js");

let api = "https://hacker-news.firebaseio.com/";

let versioning = "v0";

let DATA = "hn-data";

let stories = ["top", "new", "show", "ask", "job" ].map(str => {
    let endpoint = api + versioning + "/" + str;
    return endpoint + "stories.json"
});

const w = new self.WorkboxSW({
    cacheId : "hn"
    , skipWaiting: true
    , clientsClaim: true
});

let q = new workbox.backgroundSync.Queue({
    queueName: "hn-sync"
});

w.precache([
  {
    "url": "hn.png",
    "revision": "ba8282d69d144ff6779be9961d466c71"
  },
  {
    "url": "index.html",
    "revision": "c2c9bbd7084c7a35f5efd6e07b3e2817"
  },
  {
    "url": "manifest.json",
    "revision": "53b7fd9999dd87a84f476ebcf624ea5b"
  }
]);

/* FUNCTIONS
 * */

function R(json){
    let h = new Headers().append("Content-Type", "application/json");
    let opt = {headers: h, status: 200};

    return new Response(json, opt);
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
                            if(i.ok === true){
                                cache.put(request, i.clone());
                                return i;
                            }
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

    let reqClone = request.clone();

    // stale while revalidate
    // https://jakearchibald.com/2014/offline-cookbook/#stale-while-revalidate
    var cached = self.caches.open(DATA).then(
        cache => {
            return cache.match(request).then(
                // get json object in cache
                // or fetch a request if not cached
                jsonCache => {

                    if(jsonCache != undefined && jsonCache.bodyUsed === false){
                        var list = jsonCache.clone();
                    }

                    // stories cache update 
                    var fetching = Promise.all(
                            stories.map(
                                s => {
                                    return fetch(s).then(
                                        function(i){
                                            if(i.ok === true){
                                                cache.put(s,i.clone());
                                                return i
                                            }
                                        }
                    )})).then(function () {return cache.match(request)})
                    ;

                    fetching.catch(
                        // fallback cache if fetching failed
                        function () {
                            // push into queue for sync
                            // https://workboxjs.org/reference-docs/latest/module-workbox-background-sync.Queue.html
                            q.pushIntoQueue({request: reqClone});

                            return cache.match(request)
                        }
                    );

                    return list || fetching;
                }
            )
        }
    );

    return cached
}


/* PRE-CACHE STORIES AT SW INSTALL 
 * */


self.addEventListener("install", function (e) {

    e.waitUntil(
        // put site in cache
        caches.open(DATA).then(
            c => {
                return Promise.all(stories.map(
                    s => fetch(s).then(
                        j => c.put(s, j)
                        )
                    )
                )
            }
        )
    )
});

/* SW FETCH DATA
 * */


self.addEventListener("fetch", function (e) {

    var req = e.request;
    var url = new URL(req.url);
    //var url = req.url;
    var item ="\/item\/";
    var isItemUrl = url.pathname.match(item);
    var str = "stories";
    var isStoriesUrl = url.pathname.match(str);

    if (e.request.mode === "navigate") {
        e.respondWith(
            fetch(e.request).catch(fetch("/#/off"))
        )
    }

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
        )
    }
});
