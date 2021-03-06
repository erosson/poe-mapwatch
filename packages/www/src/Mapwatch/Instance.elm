module Mapwatch.Instance exposing
    ( Address
    , AddressId
    , Builder(..)
    , Instance(..)
    , State
    , addressId
    , duration
    , init
    , initOrUpdate
    , isDurationOffline
    , isMap
    , isOffline
    , isTown
    , offlineThreshold
    , unwrap
    , update
    , worldArea
    , zoneName
    )

import Duration exposing (Millis)
import Mapwatch.Datamine as Datamine exposing (Datamine, WorldArea)
import Mapwatch.LogLine as LogLine
import Maybe.Extra
import Time exposing (Posix)


{-| "Uniquely" identify a PoE zone instance.

(Zone, instance-server-address) isn't really a unique id - imagine running two
Volcano maps that just so happen to be assigned to the same instance server.
It's the best we've got though, and it works pretty well in practice.

worldArea is derived from zone. We could pass Datamine around everywhere instead
of duplicating information here, but that seems excessive

-}
type alias Address =
    { zone : String
    , addr : String
    , worldArea : Maybe WorldArea
    }


type alias AddressId =
    String


addressId : Address -> AddressId
addressId a =
    a.zone ++ "@" ++ a.addr


type Instance
    = MainMenu
    | Instance Address


type Builder
    = Empty
    | Connecting String


type alias State =
    { val : Instance
    , joinedAt : Posix
    , next : Builder
    }


init : Posix -> State
init t =
    -- initial-date is awkward, only Nothing on init, but we need to be able to tell the difference
    { val = MainMenu, joinedAt = t, next = Empty }


unwrap : a -> (Address -> a) -> Instance -> a
unwrap default fn instance0 =
    case instance0 of
        MainMenu ->
            default

        Instance instance ->
            fn instance


worldArea : Instance -> Maybe WorldArea
worldArea =
    unwrap Nothing .worldArea


zoneName : Instance -> Maybe String
zoneName =
    unwrap Nothing (.zone >> Just)


isTown : Instance -> Bool
isTown =
    -- No-zone is a town, since you're probably logged out and will log back in to town.
    -- Unknown-zone is *not* a town - towns are all known and accounted for, but non-map combat areas are excluded from my data.
    unwrap True (.worldArea >> Maybe.map (\w -> Datamine.isTown w || w.isHideout) >> Maybe.withDefault False)


isMap : Instance -> Bool
isMap =
    unwrap False (.worldArea >> Maybe.map Datamine.isMap >> Maybe.withDefault False)


duration : Posix -> State -> Millis
duration now state =
    Time.posixToMillis now - Time.posixToMillis state.joinedAt


offlineThreshold : Millis
offlineThreshold =
    -- TODO threshold should be configurable
    30 * Duration.minute


simulacrumOfflineThreshold : Millis
simulacrumOfflineThreshold =
    60 * Duration.minute


isSimulacrum : Instance -> Bool
isSimulacrum =
    worldArea >> Maybe.Extra.unwrap False (.id >> String.startsWith "AfflictionTown")


isDurationOffline : Millis -> Instance -> Bool
isDurationOffline dur instance =
    let
        threshold =
            if isSimulacrum instance then
                simulacrumOfflineThreshold

            else
                offlineThreshold
    in
    dur >= threshold


isOffline : Posix -> State -> Bool
isOffline now instance =
    isDurationOffline (duration now instance) instance.val


initOrUpdate : Datamine -> LogLine.Line -> Maybe State -> State
initOrUpdate datamine line instance =
    case instance of
        Just i ->
            update datamine line i

        Nothing ->
            init line.date |> update datamine line


update : Datamine -> LogLine.Line -> State -> State
update datamine line state =
    case ( state.next, line.info ) of
        -- it takes two loglines to build an instance:
        -- * "connecting to instance server (addr)"
        -- * "you have entered (zone)"
        -- we need both zone and addr, split across two lines, so it takes two steps.
        ( Empty, LogLine.ConnectingToInstanceServer addr ) ->
            -- step 1
            { state | next = Connecting addr }

        ( Connecting addr, LogLine.YouHaveEntered zone_ ) ->
            -- step 2
            { val =
                Instance
                    { zone = zone_
                    , addr = addr
                    , worldArea = Datamine.worldAreaFromName zone_ datamine
                    }
            , joinedAt = line.date
            , next = Empty
            }

        ( Connecting _, LogLine.ConnectingToInstanceServer addr ) ->
            -- two "connecting" messages - should never happen, but trust the most recent one
            { state | next = Connecting addr }

        ( _, LogLine.Opening ) ->
            -- the game crashed and was just reopened, reset the instance
            init line.date

        _ ->
            -- ignore everything else
            state
