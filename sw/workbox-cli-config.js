module.exports = {
  "globDirectory": "../dist/",
  "globPatterns": [
    //"**/*.{png,html,json}"
    "*{png,x.html,json}"
//    , "**/workbox*prod*.js"
  ],
  "swSrc": "./sw.js",
  "swDest": "../dist/sw.js",
  "globIgnores": [
    "workbox-cli-config.js"
  ]
};
