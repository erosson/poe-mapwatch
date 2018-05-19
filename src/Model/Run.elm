module Model.Run
    exposing
        ( Run
        , State(..)
        , DurationSet
        , init
        , duration
        , durationSet
        , totalDurationSet
        , meanDurationSet
        , filterToday
        , update
        )

import Time
import Date
import Model.Instance as Instance exposing (Instance)
import Model.Visit as Visit exposing (Visit)


type alias Run =
    { visits : List Visit, first : Visit, last : Visit, portals : Int }


type State
    = Empty
    | Started
    | Running Run


init : Visit -> Maybe Run
init visit =
    if Visit.isOffline visit || not (Visit.isMap visit) then
        Nothing
    else
        Just { first = visit, last = visit, visits = [ visit ], portals = 1 }


duration : Run -> Time.Time
duration v =
    Date.toTime v.last.leftAt - Date.toTime v.first.joinedAt


filteredDuration : (Visit -> Bool) -> Run -> Time.Time
filteredDuration pred run =
    run.visits
        |> List.filter pred
        |> List.map Visit.duration
        |> List.sum


type alias DurationSet =
    { all : Time.Time, town : Time.Time, start : Time.Time, subs : Time.Time, notTown : Time.Time, portals : Float }


durationSet : Run -> DurationSet
durationSet run =
    let
        all =
            duration run

        town =
            filteredDuration Visit.isTown run

        notTown =
            filteredDuration (not << Visit.isTown) run

        start =
            filteredDuration (\v -> v.instance == run.first.instance) run
    in
        { all = all, town = town, notTown = notTown, start = start, subs = notTown - start, portals = toFloat run.portals }


totalDurationSet : List Run -> DurationSet
totalDurationSet runs =
    let
        durs =
            List.map durationSet runs

        sum get =
            durs |> List.map get |> List.sum
    in
        { all = sum .all, town = sum .town, notTown = sum .notTown, start = sum .start, subs = sum .subs, portals = sum .portals }


meanDurationSet : List Run -> DurationSet
meanDurationSet runs =
    let
        d =
            totalDurationSet runs

        n =
            List.length runs
                -- nonzero, since we're dividing. Numerator will be zero, so result is zero, that's fine.
                |> max 1
                |> toFloat
    in
        { all = d.all / n, town = d.town / n, notTown = d.notTown / n, start = d.start / n, subs = d.subs / n, portals = d.portals / n }


filterToday : Date.Date -> List Run -> List Run
filterToday date =
    let
        ymd date =
            ( Date.year date, Date.month date, Date.day date )

        pred run =
            ymd date == ymd run.first.leftAt
    in
        List.filter pred


push : Visit -> Run -> Maybe Run
push visit run =
    if Visit.isOffline visit then
        Nothing
    else
        Just { run | last = visit, visits = visit :: run.visits }


update : Maybe Instance -> Maybe Visit -> State -> ( State, Maybe Run )
update instance visit state =
    -- we just joined `instance`, and just left `visit.instance`.
    --
    -- instance may be Nothing (the game just reopened) - the visit is
    -- treated as if the player were online while the game was closed,
    -- and restarted instantly into no-instance.
    -- No-instance always transitions to town (the player starts there).
    case visit of
        Nothing ->
            -- no visit, no changes.
            ( state, Nothing )

        Just visit ->
            let
                initRun =
                    if Instance.isMap instance && Visit.isTown visit then
                        -- when not running, entering a map from town starts a run.
                        -- TODO: Non-town -> Map could be a Zana mission - skip for now, takes more special-casing
                        Started
                    else
                        -- ...and *only* entering a map. Ignore non-maps while not running.
                        Empty
            in
                case state of
                    Empty ->
                        ( initRun, Nothing )

                    Started ->
                        -- first complete visit of the run!
                        if Visit.isMap visit then
                            case init visit of
                                Nothing ->
                                    -- we entered a map, then went offline. Discard the run+visit.
                                    ( initRun, Nothing )

                                Just run ->
                                    -- normal visit, common case - really start the run.
                                    ( Running run, Nothing )
                        else
                            Debug.crash <| "A run's first visit should be a Map-zone, but it wasn't: " ++ toString visit

                    Running run ->
                        case push visit run of
                            Nothing ->
                                -- they went offline during a run. Start a new run.
                                if Visit.isTown visit then
                                    -- they went offline in town - end the run, discarding the time in town.
                                    ( initRun, Just run )
                                else
                                    -- they went offline in the map or a side area.
                                    -- we can't know how much time they actually spent running before disappearing - discard the run.
                                    -- TODO handle offline in no-zone - imagine crashing in a map, immediately restarting the game, then quitting for the day
                                    ( initRun, Nothing )

                            Just run ->
                                if Instance.isMap instance && instance /= run.first.instance && Visit.isTown visit then
                                    -- entering a *new* map, from town, finishes this run and starts a new one. This condition is complex:
                                    -- * Reentering the same map does not! Ex: death, or portal-to-town to dump some gear.
                                    -- * Map -> Map does not! Ex: a Zana mission. TODO Zanas ought to split off into their own run, though.
                                    -- * Even Non-Map -> Map does not! That's a Zana daily, or leaving an abyssal-depth/trial/other side-area. Has to be Town -> Map.
                                    ( initRun, Just run )
                                else if instance == run.first.instance && Visit.isTown visit then
                                    -- reentering the *same* map from town is a portal.
                                    ( Running { run | portals = run.portals + 1 }, Nothing )
                                else
                                    -- the common case - just add the visit to the run
                                    ( Running run, Nothing )