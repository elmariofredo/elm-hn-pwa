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

"use strict";


/* VARIABLES 
 * */

!function(){"use strict";function e(){return t||(t=new Promise(function(e,n){var t=indexedDB.open("keyval-store",1);t.onerror=function(){n(t.error)},t.onupgradeneeded=function(){t.result.createObjectStore("keyval")},t.onsuccess=function(){e(t.result)}})),t}function n(n,t){return e().then(function(e){return new Promise(function(r,o){var u=e.transaction("keyval",n);u.oncomplete=function(){r()},u.onerror=function(){o(u.error)},t(u.objectStore("keyval"))})})}var t,r={get:function(e){var t;return n("readonly",function(n){t=n.get(e)}).then(function(){return t.result})},set:function(e,t){return n("readwrite",function(n){n.put(t,e)})},"delete":function(e){return n("readwrite",function(n){n["delete"](e)})},clear:function(){return n("readwrite",function(e){e.clear()})},keys:function(){var e=[];return n("readonly",function(n){(n.openKeyCursor||n.openCursor).call(n).onsuccess=function(){this.result&&(e.push(this.result.key),this.result["continue"]())}}).then(function(){return e})}};"undefined"!=typeof module&&module.exports?module.exports=r:"function"==typeof define&&define.amd?define("idbKeyval",[],function(){return r}):self.idbKeyval=r}();

var SHELL = "elm-hn-pwa";

var ITEMS = "hn-items"

var now = Date.now;

var api = "https://hacker-news.firebaseio.com/";

var versioning = "v0";

var endpoint = api + versioning + "/item/";

var timeout = 800;

var maxItems = 30;

var hn = ["top", "new", "show", "ask", "jobs" ];

var hashPages = hn.map(str => {return "/#/"+str});

var pages = hn.map(p => {return "/" + p});

var stories = hn.map(str => {
    var endpoint = api + versioning + "/" + str;
    if (str === "jobs") {
        return endpoint + "tories.json"
    }
    else {
        return endpoint + "stories.json"
    }
});

var assets = [ "/hn.svg" ];
var sm = stories.map(
    url => fetch(url).then(
        resp => caches.open(SHELL).then(
            c => c.put(url, resp)
        ) 
    )
);

/*
var pm = hashPages.map(
    p => {
        fetch(p).then(
            r => {
                Promise.resolve(r.text()).then(
                    html => {
                        // value must be a string
                        idbKeyval.set(p, html)
                    }
                )
            }
        )
    }
);
*/
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
    let h = new Headers().append("Content-Type", "application/json");
    let opt = {headers: h, status: 200};

    return new Response(json, opt);
}


// get item from cache
// elsewise from network
function getItem(request){

    var iid = request.url.split("/").reverse().shift().split(".").shift();

    return self.caches.open(ITEMS).then(
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

    // stale while revalidate
    // https://jakearchibald.com/2014/offline-cookbook/#stale-while-revalidate
    var cached = self.caches.open(SHELL).then(
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
                            return cache.match(request)
                        }
                    );

                    return list || fetching;
                }
            )
        }
    );

    return cached.catch(
            function () {
                if (request.mode === "navigate" || (request.method === "GET" && request.headers.get("accept").includes("text/html"))) {
                    cache.match("/")
                }
            }
            )
}


/* SW INSTALL 
 * */


self.addEventListener("install", function (e) {

    e.waitUntil(
        // put site in cache
        caches.open(SHELL).then(
            c => {
                return fetch("/").then(
                    r => {
                        return c.put(
                                "/"
                                , new Response(r.text(), {status: 200, headers: new Headers().append("Content-Type", "text/html")})
                        )
                    }
                )
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
    var str = "stories";
    var isStoriesUrl = url.pathname.match(str);

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
