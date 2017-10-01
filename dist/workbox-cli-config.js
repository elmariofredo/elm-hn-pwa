module.exports = {
  "globDirectory": "./",
  "globPatterns": [
    "**/*.{png,html,json}"
//    , "**/workbox*prod*.js"
  ],
  "swSrc": "src/sw.js",
  "swDest": "sw.js",
  "globIgnores": [
    "workbox-cli-config.js"
  ]
};
