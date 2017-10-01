# Elm Hacker News Progressive Web App

Sample of [HNPWA](http://hnpwa.com) built with [Elm](http://elm-lang.org).

## Progressive

- **100** on [lighthouse](https://hnpwa.skingrapher.com/lighthouse.html)
- **91** on [webpagetest](https://www.webpagetest.org/result/171001_FR_8824939a649205e4299597bb581bd197/) for a slow 3G connection
- service worker partially generated with [workbox](https://workboxjs.org) for static files precache
- offline caching of HN data
- no server-side rendering actually

## Reliable 

- interactive under 5 seconds on a Moto 4G over 3G (see webpagetest below)

## Responsive

CSS:
- built with Sass
- inspired from [Material Design Lite](https://getmdl.io/components/index.html)
- less than 3kb

## TODO

- testing background sync
- pagination with elm

## Resources

- about PWA: see on [Google](https://developers.google.com/web/progressive-web-apps/) for developers
- elm tutorials for SPA: [client elm](https://github.com/foxdonut/adventures-reactive-web-dev/tree/elm-010-todolist-feature/client-elm) by Fred Daoud, [elm spa example](https://github.com/rtfeldman/elm-spa-example) by Richard Feldman, [elmstagram](https://github.com/bkbooth/Elmstagram) by Ben Booth
- about service workers API: see on [MDN](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)

## Credits
 
- github icon from [Entypo](https://entypo.com)
- elm SVG logo [here](https://upload.wikimedia.org/wikipedia/commons/f/f3/Elm_logo.svg)
- SVG loader by [Sam Herbert](http://samherbert.net/svg-loaders/)
