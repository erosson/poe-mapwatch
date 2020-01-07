module Mapwatch.Datamine exposing (Datamine, WorldArea, decoder, imgSrc)

import Array exposing (Array)
import Dict exposing (Dict)
import Json.Decode as D
import Set exposing (Set)


type alias WorldArea =
    { id : String
    , name : String
    , isTown : Bool
    , isHideout : Bool
    , isMapArea : Bool
    , isUniqueMapArea : Bool
    , itemVisualId : Maybe String
    }


imgSrc : WorldArea -> Maybe String
imgSrc =
    .itemVisualId >> Maybe.map (String.replace ".dds" ".png" >> (\path -> "https://web.poecdn.com/image/" ++ path ++ "?w=1&h=1&scale=1&mn=6"))


type alias Datamine =
    { worldAreas : Array WorldArea }


decoder : D.Decoder Datamine
decoder =
    D.map Datamine
        (D.at [ "worldAreas", "data" ] worldAreasDecoder)


worldAreasDecoder : D.Decoder (Array WorldArea)
worldAreasDecoder =
    D.map7 WorldArea
        -- fields by index are awkward, but positional rows use so much less bandwidth than keyed rows, even when minimized
        (D.index 0 D.string)
        (D.index 1 D.string)
        (D.index 2 D.bool)
        (D.index 3 D.bool)
        (D.index 4 D.bool)
        (D.index 5 D.bool)
        (D.index 6 (D.maybe D.string))
        |> D.array



-- last parameter, id, is list index. This is why we can't have a singular worldAreaDecoder
-- |> D.map (Array.indexedMap (\i v -> v i))