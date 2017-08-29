{--
************+
ELM HN PWA
*************
VERSION: 0.11
=============
TODO:
- pagination
- make progressive
--}


module Hnpwa exposing (..)

import Json.Decode as JD exposing (Decoder, int, string, list, lazy)
import Json.Decode.Pipeline exposing (optional, required, decode)
import String exposing (isEmpty, split, concat, join)
import List exposing (take, drop, singleton, indexedMap, length, append, head, unzip)
import Dict exposing (Dict, empty, insert)
import Array as A
import Html exposing (Html, Attribute, node, article, main_, nav, section, header, footer, a, br, div, figure, h1, h2, h3, h4, img, li, object, p, span, text, time, ul)
import Html.Attributes exposing (id, class, href, target, rel, datetime, src, alt, attribute, tabindex, title, type_)
import Html.Keyed as K
import Html.Lazy as Lz
import HtmlParser exposing (parse)
import HtmlParser.Util exposing (toVirtualDom)
import Http
import Task exposing (Task)
import Maybe exposing (withDefault)
import RemoteData as RD exposing (RemoteData(..), WebData)
import RemoteData.Http exposing (get, getTask)
import Navigation exposing (Location)
import UrlParser as Url exposing (Parser, oneOf, s, parseHash, (</>))
import Time exposing (Time, inSeconds, inMinutes, inHours, inMilliseconds)
import Date exposing (Date, fromTime, day, month, year)
import Time.DateTime exposing (fromTimestamp, toISO8601)


{--
SPA SAMPLE TUTORIALS
https://github.com/foxdonut/adventures-reactive-web-dev/tree/elm-010-todolist-feature/client-elm
client elm by Fred Daoud

https://github.com/rtfeldman/elm-spa-example
elm spa example by Richard Feldman

https://github.com/bkbooth/Elmstagram
elmstagram by Ben Booth
--}
-- API
-- https://github.com/HackerNews/API


uri : String
uri =
    "https://hacker-news.firebaseio.com/"


versioning : String
versioning =
    "v0/"


api : Page -> Maybe String
api page =
    let
        url =
            uri ++ versioning
    in
        case page of
            Blank ->
                Nothing

            Top ->
                Just <| url ++ "topstories.json"

            New ->
                Just <| url ++ "newstories.json"

            Show ->
                Just <| url ++ "showstories.json"

            Ask ->
                Just <| url ++ "askstories.json"

            Jobs ->
                Just <| url ++ "jobstories.json"

            SingleItem id ->
                Just <| url ++ "item/" ++ toString id ++ ".json"


url : Page -> String
url page =
    withDefault "" <| api <| page


itemurl : Int -> String
itemurl id =
    uri ++ versioning ++ "item/" ++ toString id ++ ".json"



-- make decoder unrolls lazily


laz : Decoder a -> Decoder a
laz y =
    lazy (\_ -> y)


-- never
nolist = List.map never []
nohtml = Html.map never <| text ""


-- +++++++++
-- PAGE
-- +++++++++


type Page
    = Blank
    | Top
    | New
    | Show
    | Ask
    | Jobs
    | SingleItem Int


maxItemsPerPage : Int
maxItemsPerPage =
    30


pagination : Int -> Page -> Items -> Items 
pagination page pagetype items =
    let
        previous : Int
        previous =
            maxItemsPerPage * ( page - 1 )

        maxStories =
            case pagetype of
                SingleItem id ->
                    1

                Blank ->
                    0

                Top ->
                    500

                New ->
                    500

                Show ->
                    200

                Ask ->
                    200

                Jobs ->
                    200

        pages : Int
        pages =
                if previous == 0 then
                    0
                else
                    maxStories / toFloat previous
                        |> floor

        listAppend = 
            RD.map (drop previous) items 
                |> RD.map (take maxItemsPerPage)
                |> RD.map2 append items 
                |> RD.andThen RD.succeed
    in
        -- drop from stories list all previous displayed items
        -- and take the first max wanted items from the filtered list
        if page  <= pages then 
            listAppend
        else
            items



-- Model of page
-- initially some JSON data from API
-- stories response : Json Array of Integers
-- item response : Json Object of Strings : Values


type alias Feed =
    { data :
        Items
        -- nothing at startup
    , page :
        Page
        -- top, new, show, ask, jobs, job or comment
    , now :
        Time
    , comments :
        Dict Int (List Item) 
    , responses :
        Responses
    }


initialFeed : Feed
initialFeed =
    { data = NotAsked, page = Blank, now = 0, comments = empty, responses = Responses [] }



-- root page view


page : Feed -> Html Data
page feed =
    let
        {-- ***********************************
        C O M M E N T S   C H E C K
        ***************************************
        --}
        parent : Int -> List Item -> Maybe Item
        parent byId fromList =
            List.filter (\i -> i.id == byId) fromList 
                |> head

        {-- ***********************************
        I T E M   V I E W 
        ***************************************
        -- works for story, job and comment
        -- with recursive call to comments
        --}

        msg : (Int, Item) -> List (Html Data)
        msg (index, item) =
            if item.type_ == "comment" then
                case item.parent of
                    Just pid ->
                        if Dict.member pid feed.comments == True then
                            nolist
                        else
                            story feed (index, item)

                    Nothing ->
                        story feed (index, item)

            else
                story feed (index, item)


        htmlData : List Item -> (Int, Item) -> Html Data
        htmlData items (index, item) =
            Lz.lazy (K.node "article"
                [ id <| item.type_ ++ "-" ++ toString item.id
                , class item.type_
                , tabindex 0
                , attribute "aria-setsize" <| setSize items item
                , attribute "aria-posinset" <| posInSet index 
                ])
                <| pushComment items (index, item)
                <| msg (index, item)
                
        knode : List Item -> (Int, Item) -> (String, Html Data)
        knode items (index, item) =
            ( toString index
            , htmlData items (index, item)
            )

        pushComment : List Item -> (Int, Item) -> List (Html Data) -> List (String, Html Data)
        pushComment items (index, item) parentHtml =
            let
                c : Comment
                c =
                    { parent = parent item.id items
                    , item = i
                    , id = i.id
                    , index = increment
                    , kids = getChildComments i.id
                    , comments = Comments []
                    }

                increment : Int
                increment =
                    if item.kids == Nothing then
                        index + 1
                    else
                        0 + index

                kids : List Item
                kids = c.kids |> withDefault nolist

                i : Item
                i =
                    Dict.get item.id feed.comments
                        |> withDefault nolist
                        |> drop index
                        |> head
                        |> withDefault item

                getChildComments : Int -> Maybe (List Item)
                getChildComments iid =
                        Dict.get iid feed.comments

                iView : List (String, Html Data)
                iView = parentHtml
                    |> List.indexedMap (,)
                    |> List.map (Tuple.mapFirst (\_ -> toString index))

                n : List (String, Html Data)
                n =
                    if item.kids == Nothing then
                        iView
                    else
                        (knode kids (c.index, c.item)) :: iView
            in
                n


        {-- ***********************************
        A R I A
        ***************************************
        -- aria-setsize calculation by length of the list
        -- aria-posinset calculation by indexation
        --}
        setSize : List Item -> Item -> String 
        setSize li item =
            if item.type_ == "comment" then
                -- get the size from registered comments by their parent id
                case item.parent of
                    Just pid ->
                        Dict.get pid feed.comments
                            |> withDefault []
                            |> length
                            |> toString

                    -- impossible: every comment has a parent
                    -- elsewise not a comment :P
                    -- aria-setsize at -1 if total number of items is UNKNOWN
                    Nothing ->
                        "-1"
            else
                -- useful for stories
                length li
                    |> toString

        indexed : List Item -> List ( Int, Item )
        indexed li =
            List.indexedMap (,) li

        -- index starts at zero but aria-posinset starts at one
        -- so we increment by +1 all keys of the index
        posInSet : Int -> String
        posInSet n = n + 1 |> toString
        
        {-- ***********************************
        I T E M   V I E W 
        ***************************************
        --}
        articles : List Item -> Html Data
        articles li = 
            indexed li
                |> List.map (knode li)
                |> Lz.lazy (K.node "main" [ attribute "aria-busy" "false", attribute "role" "feed" ])
    in
            case feed.data of 
                Loading ->
                    main_ [ attribute "aria-busy" "true", attribute "role" "feed" ]
                        [
                            div [ id "loading" ] [
                                object [ attribute "data" "/svg/puff.svg", type_ "image/svg+xml" ] [ text "Loading..." ]
                                ]
                        ]

                Success items ->
                    List.filter (\i -> i.type_ /= "comment") items
                        |> articles

                Failure err ->
                    p [ id "err" ]
                        [
                        text "Cannot load the page."
                        , h4 [ class "warning" ] [
                            text "Error"
                            ]
                        , p [ class "warning" ] [
                            text <| toString err
                            ]
                        ]

                NotAsked ->
                    figure []
                        [
                            img [ src "/svg/hnpwa.svg" , alt "HN PWA logo" ] []
                        ]


-- view of single item


story : Feed -> ( Int, Item ) -> List (Html Data)
story feed (posinset, item) =
    let
        {-- ***********************************
        S E T T I N G   D A T E    &   T I M E
        ***************************************
        -- Warning: Time types are considered originally by Elm as milliseconds
        -- unix time in seconds
        -- feed.time integer is converted into seconds
        --}
        sec : Float 
        sec = toFloat item.time

        n = inSeconds feed.now

        -- how old is the item from now
        -- in seconds
        old : Float
        old =
            n - sec 

        dt : String
        dt = sec * 1000 |> fromTimestamp |> toISO8601 

        -- link url for h2 tag
        h2url : String
        h2url =
            case item.url of
                Just url ->
                    url
                Nothing ->
                    ""
        -- time constants (seconds)
        min =
            60
            -- minute
        h =
            3600
            -- hour
        j =
            86400
            -- day
        w =
            604800
            -- week

        timeLessThan : Float -> String
        timeLessThan dur =
            old / dur |> ceiling |> toString


        published = sec |> fromTime

        -- date format for US
        humanReadingDateUS = [
            month published |> toString
            , day published |> toString
            , year published |> toString
            ]
            |> join "-" 

        -- date format for EU
        humanReadingDateEU = [
            day published |> toString
            , month published |> toString
            , year published |> toString
            ]
            |> join "-" 

        -- date of publication
        pubdate =
            -- if date of publication < 1 mn
            if old == 1 then
               "1 second ago"
            
            else if old < min then
               (ceiling old |> toString) ++ " seconds ago"
            
            -- if date of publication has 1 mn
            else if old == min then
                "1 minute ago"
            
            -- if date of publication < 1 hour 
            else if old < h then
                timeLessThan min ++ " minutes ago"
            
            -- if date of publication has 1 hour 
            else if old == h then
                "1 hour ago"
            
            -- if date of publication < 1 day
            else if old < j then
                timeLessThan h ++ " hours ago"

            -- if date of publication has 1 day
            else if old == j then
                "1 day ago"

            -- if date of publication < 1 week 
            else if old < w then
                timeLessThan j ++ " days ago"

            -- if date of publication is older than a week 
            else
                humanReadingDateUS

        {-- ***********************************
        S E T T I N G   D O M A I N   N A M E 
        ***************************************
        --}
        domain: String
        domain =
            case item.url of
                Just url ->
                    split "/" url |> take 3 |> drop 2 |> concat
                Nothing ->
                    ""

        {-- ***********************************
        T E X T
        ***************************************
        --}

        txt : Html msg 
        txt =
            let
                msg =
                    case item.text of
                        Just words ->
                            node "div" [] <| toVirtualDom <| parse words
                        Nothing ->
                            nohtml
            in
                case feed.page of
                    SingleItem id ->
                        msg
                    _ ->
                        nohtml


        {-- ***********************************
        H E A D I N G   H 2
        ***************************************
        --}
        title : String
        title = withDefault "" item.title

        heading : Html msg
        heading =
            case isEmpty title of
                True ->
                    nohtml
                False ->
                    if isEmpty h2url == True then
                        h2 []
                            [ text title ]
                    else
                        h2 []
                            [ a [ target "_blank", rel "noopener", href h2url ]
                                [ text title
                                ]
                            , span [ class "source" ]
                                [ text domain
                                ]
                            ]

        {-- ***********************************
        A R T I C L E   M E T A D A T A
        ***************************************
        --}
        score =
            case item.score of
                Just sc ->
                    span [ class "score" ] [
                        text <| toString sc
                        ] 
                Nothing ->
                    nohtml

        totalcomments : String
        totalcomments =
            case item.descendants of
                Just nb ->
                    if nb < 2 then
                        toString nb ++ " comment"
                    else
                        toString nb ++ " comments"
                Nothing ->
                    ""

        toComments : Html msg
        toComments = 
            if isEmpty totalcomments == True then
                span [ class "comments" ] [
                    text "id: "
                    , a [ href <| "#/item/" ++ toString item.id ] [
                        text <| toString item.id
                    ]
                ]
            else
                span [ class "comments" ] [
                    a [ href <| "#/item/" ++ toString item.id ] [
                        text totalcomments
                        ]
                    ] 

    in
            -- ARIA accessibility
            -- https://w3c.github.io/aria/aria/aria.html#feed
            -- https://w3c.github.io/aria/aria/aria.html#aria-setsize
                
                [ header []
                    [ heading 
                    ]
                , p [ class "metadata" ]
                    [ text <| "by " ++ item.by
                    , time [ datetime dt ] [ text pubdate ]
                    , toComments
                    , score
                    ]
                , txt 
                ]




-- +++++++++
-- DATA
-- +++++++++
-- stories are lists of items
-- in a form of a JSON array of integers
-- after parsing list of ids
-- and converting each id into item


type Data
    = FetchStories (WebData (List Int))
    | FetchSingleItem (Time, Items)
    | ChainItems (Time, Items)
    | ChainComments (Time, Int, Items)
    | From (Maybe Page)

type alias Items =
    WebData (List Item)


type alias Item =
    { id : Int
    , by :
        String
        -- author
    , time :
        Int
        -- date of publication in unix time
    , type_ :
        String
        -- job, comment or story
    , text : Maybe String
    , url : Maybe String
    , score : Maybe Int
    , title : Maybe String
    , descendants :
        Maybe Int
        -- total comments count
    , parent :
        Maybe Int
    , kids :
        Maybe (List Int)
        -- ids of items comments
    }



-- +++++++++
-- COMMENTS
-- +++++++++
-- howto update value in a recursive type
-- https://github.com/elm-lang/elm-compiler/blob/master/hints/recursive-alias.md
-- https://stackoverflow.com/questions/39883252/update-value-in-a-recursive-type-elm-lang


type Responses = Responses (List Feed)


type alias Comment =
    { parent: Maybe Item
    , item : Item
    , index : Int
    , id : Int
    , kids: Maybe (List Item) 
    , comments : Comments
    }

type Comments = Comments (List Comment)


discuss : Feed -> Items -> Items 
discuss feed comments =
      RD.map2 append feed.data comments
    --    |> RD.andThen RD.succeed


-- index of comments
-- keyed by their parent item id
db : Int -> Items -> Feed -> Dict Int (List Item)
db parentId comments feed =
    case comments of
        Success c ->
            insert parentId c feed.comments

        _ ->
            feed.comments



-- REQUESTS
-- GET Request for top, new, ask and job stories


getPage : Page -> Cmd Data
getPage page =
    case page of
        Blank ->
            Cmd.none

        Top ->
            loadpage Top

        New ->
            loadpage New

        Show ->
            loadpage Show

        Ask ->
            loadpage Ask

        Jobs ->
            loadpage Jobs

        SingleItem id ->
            getSingleItem id


loadpage page =
    let
        data =
            FetchStories

        endpoint =
            url page

        decoder =
            list int

        stories =
            getTask endpoint decoder
    in
        Task.perform data stories



-- get a single item by its id
--getSingleItem : Int -> Cmd Data


getSingleItem : Int -> Cmd Data
getSingleItem id =
    let
        i : Task Never (WebData Item)
        i =
            getTask (itemurl id) item

        t = timeNow

        chained : Task Never (Time, Items)
        chained =
            Task.map (RD.map singleton) i
                |> Task.map2 (,) t
    in
        chained
            |> Task.perform FetchSingleItem 


getItems : RemoteData Http.Error (List Int) -> Cmd Data
getItems ids =
    case ids of
        Success items ->
            let
                getitem id =
                    getTask (itemurl id) (laz item)
            in
                List.take maxItemsPerPage items
                    |> List.map getitem
                    |> Task.succeed
                    |> Task.andThen Task.sequence
                    |> enlist

        _ ->
            Cmd.none


enlist : Task Never (List (WebData Item)) -> Cmd Data
enlist tasks =
    let
        maybeSuccess listWDI =
            RD.toMaybe listWDI

        t = timeNow

        chained : Task Never (Time, Items)
        chained =
            Task.map (List.filterMap maybeSuccess) tasks
                |> Task.map RD.succeed
                |> Task.map2 (,) t
    in
        chained
            |> Task.perform ChainItems


timeNow : Task Never Time
timeNow = Time.now
    |> Task.andThen Task.succeed


-- items can be singleton aka a list of a single item
getKidsOfSeveral : Items -> Cmd Data
getKidsOfSeveral items =
    case items of
        Success i ->
            Cmd.batch <| List.map getKidsOfSingle i
        _ ->
            Cmd.none

getKidsOfSingle : Item -> Cmd Data
getKidsOfSingle i =
    let
        id = i.id
            |> Task.succeed

        kids : List Int
        kids =
            case i.kids of
                Just k ->
                    k
                Nothing ->
                    []

        getItem id = getTask (itemurl id) (laz item)

        maybeSuccess listComments =
            RD.toMaybe listComments
        
        -- get current time
        t = timeNow
                        
        -- sequenced GET requests to fetch each comment
        seq : List Int -> Task Never (RemoteData Http.Error (List Item))
        seq uence = 
            uence
            -- take only a max of comments
            -- next line can be commented to overcome the restraint
            -- |> List.take maxItemsPerPage 
            |> List.map getItem 
            |> Task.succeed
            |> Task.andThen Task.sequence
            |> Task.map (List.filterMap maybeSuccess)
            |> Task.map RD.succeed

        -- map 3 tasks : time, id of current item (parent) and list of comments
        -- in a single task
        performDiscuss : Task Never Items -> Cmd Data
        performDiscuss task =
            Task.map3 (,,) t id task
            |> Task.perform ChainComments

    in
            if List.isEmpty kids then
                Cmd.none
            else
                kids
                |> seq
                |> performDiscuss



-- DECODERS
-- +++++++++
-- returns Result Ok values of item


item : Decoder Item
item =
    decode Item
        |> required "id" int
        |> required "by" string
        |> required "time" int
        |> required "type" string
        |> optional "text" (JD.map Just string) Nothing
        |> optional "url" (JD.map Just string) Nothing
        |> optional "score" (JD.map Just int) Nothing
        |> optional "title" (JD.map Just string) Nothing
        |> optional "descendants" (JD.map Just int) Nothing
        |> optional "parent" (JD.map Just int) Nothing
        |> optional "kids" (JD.map Just (list int)) Nothing



-- +++++++++
-- UPDATE
-- +++++++++


update : Data -> Feed -> ( Feed, Cmd Data )
update data feed =
    case data of
        FetchStories ids ->
            ( { feed | data = Loading }, getItems ids )

        FetchSingleItem (t, item) ->
            ( { feed | data = item, now = t }, getKidsOfSeveral item )

        ChainItems (t, items) ->
            ( { feed | data = items, now = t }, Cmd.none )

        ChainComments (t, parentId, comments) ->
            ( { feed | data = discuss feed comments, comments = db parentId comments feed, now = t }, getKidsOfSeveral comments )

        From (Just page) ->
            ( { feed | page = page, comments = empty }, getPage page )

        From Nothing ->
            feed ! [ Cmd.none ]


-- +++++++++++
-- NAVIGATION
-- +++++++++++
-- url in the browser


route : Parser (Page -> a) a
route =
    oneOf
        [ Url.map Top <| s "top"
        , Url.map New <| s "new"
        , Url.map Show <| s "show"
        , Url.map Ask <| s "ask"
        , Url.map Jobs <| s "jobs"
        , Url.map SingleItem <| s "item" </> Url.int
        ]



-- any browser will interpret everything after the hash # as being on the current page


routeTo : Page -> String
routeTo page =
    let
        p =
            case page of
                Top ->
                    [ "top" ]

                New ->
                    [ "new" ]

                Show ->
                    [ "show" ]

                Ask ->
                    [ "ask" ]

                Jobs ->
                    [ "jobs" ]

                SingleItem id ->
                    [ "item", toString id ]

                Blank ->
                    []
    in
        "/#/" ++ join "/" p



-- Location is a bunch of info about the address bar
-- see http://package.elm-lang.org/packages/elm-lang/navigation/2.1.0/Navigation
-- corresponds to Document.location in JS
-- more info on MDN: https://developer.mozilla.org/en-US/docs/Web/API/Location


pathto : Location -> Maybe Page
pathto loc =
    if String.isEmpty loc.hash then
        Just Top
    else
        parseHash route loc


pathparser : Location -> Data
pathparser loc =
    From <| parseHash route loc



-- +++++++++
-- INIT
-- +++++++++


init : Location -> ( Feed, Cmd Data )
init loc =
    case pathto loc of
        Just Blank ->
            ( initialFeed, getPage Top )

        Just Top ->
            ( initialFeed, getPage Top )

        Just New ->
            ( initialFeed, getPage New )

        Just Show ->
            ( initialFeed, getPage Show )

        Just Ask ->
            ( initialFeed, getPage Ask )

        Just Jobs ->
            ( initialFeed, getPage Jobs )

        Just (SingleItem id) ->
            ( initialFeed, getPage <| SingleItem id )

        Nothing ->
            ( initialFeed, Cmd.none )



-- +++++++++++++
-- MAIN PROGRAM
-- +++++++++++++


main : Program Never Feed Data
main =
    Navigation.program pathparser
        { init = init
        , update = update
        , view = page
        , subscriptions = \_ -> Sub.none
        }
