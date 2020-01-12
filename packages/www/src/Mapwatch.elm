module Mapwatch exposing
    ( Model
    , Msg(..)
    , OkModel
    , ReadyState(..)
    , init
    , initModel
    , isReady
    , lastUpdatedAt
    , ready
    , subscriptions
    , tick
    , update
    , updateOk
    )

import Duration exposing (Millis)
import Json.Decode as D
import Mapwatch.Datamine as Datamine exposing (Datamine)
import Mapwatch.Instance as Instance
import Mapwatch.LogLine as LogLine
import Mapwatch.Run as Run
import Mapwatch.Visit as Visit
import Maybe.Extra
import Ports
import Readline
import Time exposing (Posix)
import TimedReadline exposing (TimedReadline)


type alias Model =
    Result String OkModel


type alias OkModel =
    { datamine : Datamine
    , history : Maybe TimedReadline
    , parseError : Maybe LogLine.ParseError
    , instance : Maybe Instance.State
    , runState : Run.State
    , runs : List Run.Run
    , readline : Maybe TimedReadline
    }


type Msg
    = LogSlice { date : Int, position : Int, length : Int, value : String }
    | LogChanged { date : Int, size : Int, oldSize : Int }
    | LogOpened { date : Int, size : Int }



-- = RecvLogLine { date : Int, line : String }
-- | RecvProgress Ports.Progress


createModel : Datamine -> OkModel
createModel datamine =
    { datamine = datamine
    , parseError = Nothing
    , instance = Nothing
    , runState = Run.Empty
    , readline = Nothing
    , history = Nothing
    , runs = []
    }


initModel : D.Value -> Model
initModel =
    D.decodeValue Datamine.decoder
        >> Result.mapError D.errorToString
        >> Result.map createModel


init : D.Value -> ( Model, Cmd Msg )
init datamineJson =
    ( initModel datamineJson, Cmd.none )


updateLine : LogLine.Line -> ( OkModel, List (Cmd Msg) ) -> ( OkModel, List (Cmd Msg) )
updateLine line ( model, cmds0 ) =
    let
        instance =
            Instance.initOrUpdate model.datamine line model.instance

        visit =
            Visit.tryInit model.instance instance

        ( runState, lastRun ) =
            Run.update instance visit model.runState

        runs =
            case lastRun of
                Just lastRun_ ->
                    lastRun_ :: model.runs

                Nothing ->
                    model.runs

        cmds =
            case model.instance of
                Nothing ->
                    cmds0

                Just i ->
                    if instance.joinedAt == i.joinedAt then
                        cmds0

                    else
                        Ports.sendJoinInstance instance.joinedAt instance.val visit runState lastRun
                            :: cmds0
    in
    ( { model
        | instance = Just instance

        -- , visits = Maybe.Extra.unwrap model.visits (\v -> v :: model.visits) visit
        , runState = runState
        , runs = runs
      }
    , cmds
    )


tick : Posix -> OkModel -> OkModel
tick t model =
    case model.instance of
        Nothing ->
            -- no loglines processed yet, no need to tick
            model

        Just instance ->
            let
                ( runState, lastRun ) =
                    Run.tick t instance model.runState

                runs =
                    case lastRun of
                        Just lastRun_ ->
                            lastRun_ :: model.runs

                        Nothing ->
                            model.runs
            in
            { model | runState = runState, runs = runs }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg rmodel =
    case rmodel of
        Err err ->
            ( rmodel, Cmd.none )

        Ok model ->
            updateOk msg model
                |> Tuple.mapFirst Ok


updateOk : Msg -> OkModel -> ( OkModel, Cmd Msg )
updateOk msg model =
    let
        _ =
            if False then
                Ports.logSliceReq { position = 0, length = 0 }

            else
                Cmd.none
    in
    case msg of
        LogOpened { date, size } ->
            case model.readline of
                Just _ ->
                    ( model, Cmd.none )

                Nothing ->
                    let
                        readline =
                            TimedReadline.create { now = Time.millisToPosix date, start = 0, end = size }
                    in
                    ( { model | readline = Just readline }
                    , readline.val |> Readline.next |> Maybe.Extra.unwrap Cmd.none Ports.logSliceReq
                    )

        LogSlice { date, position, length, value } ->
            case model.readline of
                Nothing ->
                    ( model, Cmd.none )

                Just r ->
                    let
                        ( lines, readline ) =
                            TimedReadline.read (Time.millisToPosix date) value r

                        ( model1, cmds ) =
                            lines
                                |> List.filterMap (LogLine.parse >> Result.toMaybe)
                                |> List.foldl updateLine ( model, [] )
                    in
                    case Readline.next readline.val of
                        Nothing ->
                            ( { model1 | readline = Just readline, history = model1.history |> Maybe.Extra.orElse (Just readline) }
                            , Cmd.none
                            )

                        Just next ->
                            ( { model1 | readline = Just readline }
                            , Ports.logSliceReq next
                            )

        LogChanged { date, size, oldSize } ->
            case model.readline of
                Nothing ->
                    ( model, Cmd.none )

                Just readline0 ->
                    ( { model | readline = readline0 |> TimedReadline.resize (Time.millisToPosix date) size |> Result.toMaybe }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.logSlice LogSlice
        , Ports.logChanged LogChanged
        , Ports.logOpened LogOpened
        ]


type ReadyState
    = NotStarted
    | LoadingHistory TimedReadline.Progress
    | Ready TimedReadline.Progress


ready : OkModel -> ReadyState
ready m =
    case m.history of
        Just h ->
            TimedReadline.progress h |> Ready

        Nothing ->
            case m.readline of
                Nothing ->
                    NotStarted

                Just r ->
                    TimedReadline.progress r |> LoadingHistory


isReady : OkModel -> Bool
isReady =
    .history >> Maybe.Extra.isJust


lastUpdatedAt : OkModel -> Maybe Posix
lastUpdatedAt model =
    [ model.runState |> Run.stateLastUpdatedAt
    , model.runs |> List.head |> Maybe.map (\r -> r.last.leftAt)
    ]
        |> List.filterMap identity
        |> List.head
