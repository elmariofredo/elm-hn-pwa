# Elm Hacker News Progressive Web App

Sample of [HNPWA](http://hnpwa.com) built in [Elm](http://elm-lang.org).

## Progressive

- 100 on [lighthouse](https://hnpwa.skingrapher.com/lighthouse.html)
- 91 on [webpagetest](https://www.webpagetest.org/result/171001_FR_8824939a649205e4299597bb581bd197/) for a slow 3G connection
- service worker partially generated with [workbox](https://workboxjs.org) for static files precache
- partial offline caching of HN data
- no server-side rendering actually

## Reliable 

- interactive under 5 seconds on a Moto 4G over 3G (see webpagetest below)

## Responsive

- CSS built with Sass
- inspired from [Material Design Lite](https://getmdl.io/components/index.html)
- less than 3kb

## TODO

- testing background sync
- pagination with elm

## Resources

About progressive web apps: see on [Google](https://developers.google.com/web/progressive-web-apps/) for developers.

## Credits
 
- github icon from [Entypo](https://entypo.com)
- elm SVG logo [here](https://upload.wikimedia.org/wikipedia/commons/f/f3/Elm_logo.svg)
- SVG loader by [Sam Herbert](http://samherbert.net/svg-loaders/)
