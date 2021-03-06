module View.Util exposing (escapeSearch, hidePreLeagueButtons, insertSearch, pluralize, roundToPlaces, viewDateSearch, viewGoalForm, viewSearch)

import Dict exposing (Dict)
import Dict.Extra
import Html as H exposing (..)
import Html.Attributes as A exposing (..)
import Html.Events as E exposing (..)
import ISO8601
import List.Extra
import Mapwatch exposing (Model, Msg)
import Mapwatch.Datamine exposing (League)
import Model exposing (Msg)
import Regex
import Route exposing (Route)
import Route.Feature as Feature exposing (Feature)
import Route.QueryDict as QueryDict exposing (QueryDict)
import Time exposing (Posix)
import View.Icon as Icon


roundToPlaces : Float -> Float -> Float
roundToPlaces p n =
    (n * (10 ^ p) |> round |> toFloat) / (10 ^ p)


viewSearch : List (Attribute Msg) -> QueryDict -> Html Msg
viewSearch attrs query =
    let
        search =
            Dict.get Route.keys.search query

        msg s =
            Dict.insert Route.keys.search s query |> Model.Search
    in
    span [ class "search-form search-text", title "To see searchable text for a map-run, hover over its region on the history screen.\nSearch accepts regular expressions." ]
        [ input
            ([ value <| Maybe.withDefault "" search
             , type_ "text"
             , tabindex 1
             , onInput msg
             ]
                ++ attrs
            )
            []
        , Icon.fas "search"
        ]


viewGoalForm : QueryDict -> Html Msg
viewGoalForm query =
    if Feature.isActive Feature.Goals query then
        let
            goal =
                Dict.get Route.keys.goal query

            sessionName =
                case QueryDict.getPosix Route.keys.after query of
                    Just _ ->
                        "session"

                    Nothing ->
                        "today's"

            ( optExactly, exactly ) =
                goal
                    |> Maybe.andThen
                        (\dur ->
                            if Regex.contains ("best|mean|none" |> Regex.fromString |> Maybe.withDefault Regex.never) dur then
                                Nothing

                            else
                                Just ( [ selected True ], [ input [ type_ "text", onInput msg, value dur, placeholder "\"5:00\" or \"300\" or \"5m 0s\"" ] [] ] )
                        )
                    |> Maybe.withDefault ( [], [] )

            msg s =
                Model.Search <|
                    if s == "none" then
                        Dict.remove Route.keys.goal query

                    else
                        Dict.insert Route.keys.goal s query
        in
        span [ class "search-form search-goal" ]
            [ select [ onInput msg ]
                [ option [ selected <| goal == Nothing || goal == Just "none", value "none" ] [ text "No time goal" ]
                , option [ selected <| goal == Just "best-session", value "best-session" ] [ text <| "Goal: " ++ sessionName ++ " best" ]
                , option [ selected <| goal == Just "best", value "best" ] [ text <| "Goal: all-time best" ]
                , option [ selected <| goal == Just "mean-session", value "mean-session" ] [ text <| "Goal: " ++ sessionName ++ " average" ]
                , option [ selected <| goal == Just "mean", value "mean" ] [ text <| "Goal: all-time average" ]
                , option (optExactly ++ [ value "" ]) [ text "Goal: exactly..." ]
                ]
            , span [] exactly
            ]

    else
        span [] []


pluralize : String -> String -> number -> String
pluralize one other n =
    if n == 1 then
        one

    else
        other


filterLeagueButtons : List League -> List League
filterLeagueButtons =
    -- combine leagues with the same start time (hc/ssf variants)
    -- the winner is the one with the shortest name
    Dict.Extra.groupBy (.startAt >> Time.posixToMillis)
        >> Dict.values
        >> List.filterMap (List.Extra.minimumBy (.id >> String.length))
        >> List.filter (\l -> l.id /= "Standard")


hidePreLeagueButtons : List League -> QueryDict -> Route -> List (Html msg)
hidePreLeagueButtons leagues query route =
    leagues
        |> filterLeagueButtons
        |> List.map
            (\l ->
                a
                    [ class "button"
                    , Route.href (Dict.insert Route.keys.after (l.startAt |> ISO8601.fromPosix |> ISO8601.toString) query) route
                    ]
                    [ Icon.fas "calendar", text <| " Hide pre-" ++ l.id ++ " maps" ]
            )


viewDateSearch : List League -> QueryDict -> Route -> Html msg
viewDateSearch leagues query route =
    let
        buttons =
            case QueryDict.getPosix Route.keys.after query of
                Nothing ->
                    hidePreLeagueButtons leagues query route

                Just _ ->
                    [ a [ class "button", Route.href (Dict.remove Route.keys.after query) route ] [ Icon.fas "eye", text " Unhide all maps" ]
                    ]
    in
    span [ class "search-form search-date" ] buttons


insertSearch : String -> QueryDict -> QueryDict
insertSearch search =
    Dict.insert Route.keys.search (escapeSearch search)


escapeSearch : String -> String
escapeSearch =
    Regex.replace escapeSearchRegex (\m -> "\\" ++ m.match)


escapeSearchRegex =
    Regex.fromString "[.*+?^${}()|[\\]\\\\]" |> Maybe.withDefault Regex.never
