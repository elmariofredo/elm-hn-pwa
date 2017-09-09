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
import List exposing (take, drop, singleton, indexedMap, length, append, head, unzip, partition)
import Dict exposing (Dict, empty, insert)
import Array as A
import Process exposing (sleep)
import Svg as G exposing (rect, path, desc, svg, g, animate, circle)
import Svg.Attributes exposing (d, fill, x, y, width, height, viewBox, cx, cy, r, attributeName, begin, dur, values, calcMode, keyTimes, keySplines, repeatCount, stroke, strokeWidth)
import Html exposing (Html, Attribute, node, article, main_, nav, section, header, footer, a, br, div, figure, h1, h2, h3, h4, li, object, p, span, text, time, ul)
import Html.Attributes exposing (id, class, href, target, rel, datetime, src, alt, attribute, tabindex, title, type_)
import Html.Keyed as K
import Html.Lazy as Lz
import HtmlParser exposing (parse)
import HtmlParser.Util exposing (toVirtualDom)
import Http exposing (Header) 
import Task exposing (Task, sequence)
import Maybe exposing (withDefault)
import Result as R
import RemoteData as RD exposing (RemoteData(..), WebData)
import RemoteData.Http exposing (get, Config, getTaskWithConfig)
import Navigation exposing (Location)
import UrlParser as Url exposing (Parser, oneOf, s, parseHash, (</>))
import Time exposing (Time, inSeconds, inMinutes, inHours, inMilliseconds, second)
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


{-- ***********************************
 M O D E L   O F   P A G E
***************************************
--}


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
    , comments : Items 
    , index :
        Dict Int (List Item) 
    }


initialFeed : Feed
initialFeed =
    { data = NotAsked, page = Blank, now = 0, comments = NotAsked, index = empty }



-- root page view


{-- ***********************************
 V I E W S
***************************************
--}
page : Feed -> Html Data
page feed =
    let
        {-- ***********************************
        P A R E N T  I T E M   C H E C K
        ***************************************
        -- has item kids or parent?
        --}

        -- get parent item if there
        parent : Int -> List Item -> Maybe Item
        parent withParentId isInList =
            List.filter (\i -> i.id == withParentId) isInList 
                |> head

        {-- ***********************************
        K E Y E D   N O D E 
        ***************************************
        --}

        -- html content of the keyed node
        htmlContent : List Item -> (Int, Item) -> Html Data
        htmlContent items (index, item) =
            let
                -- story, job or ask content on single item page
                -- before displaying comments
                mainContent : List (String, Html Data)
                mainContent =
                    if item.type_ /= "comment" then
                        story feed (index, item)
                            |> indexedMap (,)
                            |> List.map (Tuple.mapFirst toString)
                    else
                        nolist
            in
                Lz.lazy (K.node "article"
                    [ id <| item.type_ ++ "-" ++ toString item.id
                    , class item.type_
                    , tabindex 0
                    , attribute "aria-setsize" <| setSize items item
                    , attribute "aria-posinset" <| posInSet index 
                    ])
                    <| append mainContent 
                    <| pushComment items (index, item)
                
        -- keyed node itself
        knode : List Item -> (Int, Item) -> (String, Html Data)
        knode items (index, item) =
            ( toString index
            , htmlContent items (index, item)
            )

        snode : List Item -> (Int, Item) -> (String, Html Data)
        snode items (index, item) =
            ( toString index
            , story feed (index, item)
                |> List.indexedMap (,)
                |> List.map (Tuple.mapFirst toString)
                |> Lz.lazy (K.node "article"
                    [ id <| item.type_ ++ "-" ++ toString item.id
                    , class item.type_
                    , tabindex 0
                    , attribute "aria-setsize" <| setSize items item
                    , attribute "aria-posinset" <| posInSet index 
                    ]
                )
            )

        {-- ***********************************
        C O M M E N T S
        ***************************************
        -- push first comment child after the current item which can be a comment itself
        --}
        pushComment : List Item -> (Int, Item) -> List (String, Html Data)
        pushComment items (index, item)=
            let
                c : Comment
                c =
                    { parent = parent item.id items
                    , item = i
                    , index = 0 
                    , responses = NoComment 
                    , id = i.id
                    , kids = i.kids 
                    }

                i : Item
                i = Dict.get item.id feed.index
                    |> withDefault nolist
                    |> head
                    |> withDefault item

                {-- ***********************************
                D I S P L A Y   H T M L
                ***************************************
                -- html content of comment
                -- ready to be added to the keyed node
                --}
                content : Comment -> List (String, Html Data)
                content comment =
                    case feed.page of
                        -- if page is an item page
                        -- display html 
                        -- and make it ready to be added to the keyed node
                        SingleItem id ->
                            story feed (comment.index, comment.item)
                                |> List.indexedMap (,)
                                |> List.map (Tuple.mapFirst (\_ -> toString comment.index))
                        -- if not, no comments
                        _ -> 
                            nolist

                {-- ***********************************
                S I B L I N G   C O M M E N T
                ***************************************
                --}
                siblingOf : Comment -> Comment
                siblingOf comment =
                    let
                        inList : List Item
                        inList =
                            case comment.parent of
                                Just item ->
                                    Dict.get item.id feed.index
                                        |> withDefault nolist
                                -- not a comment
                                -- impossible state, really
                                Nothing ->
                                    nolist

                        siblingOf_ : Comment -> List Item -> Maybe Item
                        siblingOf_ comment inList  =
                            case inList of
                                [] ->
                                    Nothing
                                i::is ->
                                    if i.id == comment.item.id then
                                        head is
                                    else
                                        drop 1 inList
                                        |> siblingOf_ comment 

                        sibling = siblingOf_ comment inList
                            |> withDefault comment.item
                    in
                        if sibling == comment.item then
                            comment
                        else
                            { 
                            parent = parent item.id items 
                            , item = sibling
                            , index = comment.index + 1 
                            , kids = sibling.kids 
                            , id = sibling.id
                            , responses = Responses []
                            }

                {-- ************************************
                C O M M E N T S   C O M B I N A T I O N 
                ****************************************
                --}
                cascade : Comment -> List (String, Html Data)
                cascade comment =
                    let
                        s = siblingOf comment

                        pid : Int
                        pid =
                            case comment.parent of
                                Nothing ->
                                    0
                                Just item ->
                                    item.id

                        cc = content comment

                        -- list of sibling comments
                        -- the list contains the current comment too
                        childComments : List Item
                        childComments =
                                Dict.get pid feed.index
                                    |> withDefault nolist
                    in
                        case comment.kids of
                            Nothing ->
                                if s.id == comment.id then
                                    -- nok kid neither sibling comment
                                    cc
                                else
                                    -- no kids but sibling comment
                                    append cc
                                        <| cascade s
                            Just kids ->
                                -- push child comments
                                if childComments == nolist then
                                    cc
                                else 
                                    if s.id == comment.id then
                                        cc
                                            |> A.fromList
                                            |> A.push (knode childComments (comment.index, comment.item)) 
                                            |> A.toList
                                    else
                                        append 
                                            ( cc
                                            |> A.fromList
                                            |> A.push (knode childComments (comment.index, comment.item)) 
                                            |> A.toList
                                            )
                                            <| cascade s

            in
                cascade c

        {-- ***********************************
        A R I A
        ***************************************
        -- aria-setsize calculation by length of the list
        -- aria-posinset calculation by indexation
        --}
        setSize : List Item -> Item -> String 
        setSize li item =
            if item.type_ == "comment" then
                -- get the size from registered index by their parent id
                case item.parent of
                    Just pid ->
                        Dict.get pid feed.index
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
        indexed items =
            List.indexedMap (,) items

        -- index starts at zero but aria-posinset starts at one
        -- so we increment by +1 all keys of the index
        posInSet : Int -> String
        posInSet n = n + 1 |> toString

        {-- ***********************************
        C O M M E N T   V I E W 
        ***************************************
        --}
        comments : List Item -> List (String, Html Data)
        comments listed = 
            case feed.comments of
                Success c ->
                    indexed listed
                        |> List.map (knode listed)
                Loading ->
                    [ ("0", text "loading comments") ]
                _ ->
                    nolist

        stories : List Item -> List (String, Html Data) 
        stories inList = 
            indexed inList
                |> List.map (snode inList)
    in
            case feed.data of 
                Loading ->
                    main_ [ class "loading" ]
                        [
                            div [ attribute "aria-busy" "true", attribute "role" "feed"  ] [
                                svg
                                    [ viewBox "0 0 44 44"
                                    , width "100px"
                                    , height "100px"
                                    ]
                                    [ G.title
                                        []
                                        [ G.text "loading"]
                                    , desc
                                        []
                                        [ G.text "Loading the page, please wait..." ]
                                    , g [
                                        ]
                                        [
                                        circle
                                            [ cx "22"
                                            , cy "22"
                                            , r "1"
                                            , fill "transparent"
                                            , strokeWidth "2"
                                            , stroke "#18583f"
                                            ]
                                            [ animate
                                                [ attributeName "r"
                                                , begin "0s"
                                                , dur "1.8s"
                                                , values "1; 20"
                                                , calcMode "spline"
                                                , keyTimes "0; 1"
                                                , keySplines "0.165, 0.84, 0.44, 1"
                                                , repeatCount "indefinite"
                                                ]
                                                []
                                            , animate
                                                [ attributeName "stroke-opacity"
                                                , begin "0s"
                                                , dur "1.8s"
                                                , values "1; 0"
                                                , calcMode "spline"
                                                , keyTimes "0; 1"
                                                , keySplines "0.3, 0.61, 0.355, 1"
                                                , repeatCount "indefinite"
                                                ]
                                                []
                                            ]
                                        ]
                                        , circle
                                            [ cx "22"
                                            , cy "22"
                                            , r "1"
                                            , fill "transparent"
                                            , strokeWidth "2"
                                            , stroke "#18583f"
                                            ]
                                            [ animate
                                                [ attributeName "r"
                                                , begin "-0.9s"
                                                , dur "1.8s"
                                                , values "1; 20"
                                                , calcMode "spline"
                                                , keyTimes "0; 1"
                                                , keySplines "0.165, 0.84, 0.44, 1"
                                                , repeatCount "indefinite"
                                                ]
                                                []
                                            , animate
                                                [ attributeName "stroke-opacity"
                                                , begin "-0.9s"
                                                , dur "1.8s"
                                                , values "1; 0"
                                                , calcMode "spline"
                                                , keyTimes "0; 1"
                                                , keySplines "0.3, 0.61, 0.355, 1"
                                                , repeatCount "indefinite"
                                                ]
                                                []
                                            ]
                                        ]
                                    ]
                        ]

                Success items ->
                    case feed.page of
                        SingleItem id ->
                            let
                                unique : Maybe Item
                                unique = items |> head

                                typeOfItem : String
                                typeOfItem =
                                    case unique of
                                        Just i ->
                                            i.type_
                                        Nothing ->
                                            ""
                            in
                                if typeOfItem == "job" then
                                    main_ []
                                        [ items
                                            |> stories 
                                            |> Lz.lazy (K.node "div" [ class "feed", attribute "aria-busy" "false", attribute "role" "feed" ])
                                        ]
                                else
                                    main_ []
                                        [ items
                                            |> comments
                                            |> Lz.lazy (K.node "div" [ class "feed", attribute "aria-busy" "false", attribute "role" "feed" ])
                                        ]
                        _ ->
                            main_ []
                                [ List.filter (\i -> i.type_ /= "comment") items
                                    |> stories 
                                    |> Lz.lazy (K.node "div" [ class "feed", attribute "aria-busy" "false", attribute "role" "feed" ])
                                ]

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
                            svg [ width "160", height "160", viewBox "0 0 36 36" ]
                            [ G.title [] [ G.text "HN PWA" ]
                            , desc [] [ G.text "Logo of Hacker News Progressive Web Application. More info on hnpwa.com" ]
                            , rect [ fill "#f27521", width "36", height "36", y "0", x "0" ] []
                            , path [ fill "white", d "M9.02 28.577V19.2h4.663v9.377h2.675V7.424h-2.675V16H9.02V7.424H6.348v21.153zM22.202 7.424h-2.85v21.153h2.392V13.285l5.387 15.292h2.52V7.424h-2.366v14.434z" ] []
                            ]
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
                        header []
                            [
                            h2 []
                                [ text title ]
                            ]
                    else
                        header []
                            [
                            h2 []
                                [ a [ target "_blank", rel "noopener", href h2url ]
                                    [ text title
                                    ]
                                , span [ class "source" ]
                                    [ text domain
                                    ]
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
                [ heading
                , p [ class "metadata" ]
                    [ text <| "by " ++ item.by
                    , time [ datetime dt ] [ text pubdate ]
                    , toComments
                    , score
                    ]
                , txt 
                ]




{-- ***********************************
 D A T A
***************************************
--}
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



{-- ***********************************
 C O M M E N T S
***************************************
-- howto update value in a recursive type
-- https://github.com/elm-lang/elm-compiler/blob/master/hints/recursive-alias.md
-- https://stackoverflow.com/questions/39883252/update-value-in-a-recursive-type-elm-lang
--}


type alias Comment =
    { parent: Maybe Item
    , item : Item
    , index : Int
    , responses : Responses 
    , id : Int
    , kids: Maybe (List Int) 
    }

type Responses = 
    NoComment
    | Responses (List Comment)


{-- ***********************************
 R E Q UE S T S
***************************************
-- GET Request for top, new, ask and job stories
--}


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
            getTaskWithConfig requestConf endpoint decoder
    in
        Task.perform data stories


delayPage : Time -> Page -> Cmd Data 
delayPage t page =
    sleep t
        |> (\_ -> getPage page)



-- get a single item by its id
--getSingleItem : Int -> Cmd Data

requestConf : Config
requestConf =
    { headers =
        [ Http.header "Origin" uri 
        , Http.header "Accept" "application/json"
        ]
    , withCredentials = False
    , timeout = Just <| 3 * second  
    }

getSingleItem : Int -> Cmd Data
getSingleItem id =
    let
        i : Task Never (WebData Item)
        i =
            getTaskWithConfig requestConf (itemurl id) item

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
        Success itemIds ->
            let
                getitem id =
                    getTaskWithConfig requestConf (itemurl id) (laz item)
            in
                List.take maxItemsPerPage itemIds
                    |> List.map getitem
                    |> sequence
                    |> enlist

        _ ->
            Cmd.none


enlist : Task Never (List (WebData Item)) -> Cmd Data
enlist tasks =
    let
        maybeSuccess listWDI =
            RD.toMaybe listWDI

        chained : Task Never (Time, Items)
        chained =
            Task.map (List.filterMap maybeSuccess) tasks
                |> Task.map RD.succeed
                |> Task.map2 (,) timeNow
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

        getItem id = getTaskWithConfig requestConf (itemurl id) (laz item)

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



{-- ***********************************
 D E C O D E R S
***************************************
-- returns Result Ok values of item
--}


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



{-- ***********************************
 U P D A T E
***************************************
--}


update : Data -> Feed -> ( Feed, Cmd Data )
update data feed =
    let
        discuss : Items -> ( Items, Cmd Data )
        discuss w =
            let
                appended = RD.map2 append feed.data w 

                listOf comments = (comments, getKidsOfSeveral w)
                    
                updated = RD.update listOf appended
            in
                updated

        -- RD.andThen RD.succeed

        -- index of comments
        -- keyed by their parent item id
        db : Int -> Items -> Dict Int (List Item)
        db parentId comments =
            case comments of
                Success c ->
                    insert parentId c feed.index 
                _ ->
                    feed.index


    in
        case data of
            FetchStories ids ->
                ( { feed | data = Loading }, getItems ids )

            FetchSingleItem (t, item) ->
                ( { feed | data = item, now = t }, getKidsOfSeveral item )

            ChainItems (t, items) ->
                ( { feed | data = items, now = t }, Cmd.none )

            ChainComments (t, parentId, words) ->
                let
                    (i, c) = discuss words 
                in
                    ( { feed | comments = i, index = db parentId words, now = t }, c )

            From (Just page) ->
                ( { feed | page = page, comments = NotAsked, index = empty }, getPage page )

            From Nothing ->
                feed ! [ Cmd.none ]


{-- ***********************************
 N A VI G A T I O N
***************************************
-- url in the browser
--}


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



{-- ***********************************
 I N I T 
***************************************
--}


init : Location -> ( Feed, Cmd Data )
init loc =
    case pathto loc of
        Just Blank ->
            ( initialFeed, delayPage 100 Top )

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



{-- ***********************************
 M A I N   P R O G R A M
***************************************
--}


main : Program Never Feed Data
main =
    Navigation.program pathparser
        { init = init
        , update = update
        , view = page
        , subscriptions = \_ -> Sub.none
        }
