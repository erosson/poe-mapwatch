module View.View exposing (view, viewBody)

import AppPlatform
import Browser
import Html as H exposing (..)
import Mapwatch as Mapwatch
import Model as Model exposing (Model, Msg)
import Route exposing (Route(..))
import View.Changelog
import View.Debug
import View.DebugDatamine
import View.DumpLines
import View.Encounters
import View.GSheets
import View.History
import View.HistoryTSV
import View.Maps
import View.NotFound
import View.Overlay
import View.Privacy
import View.Settings
import View.Timer


view : Model -> Browser.Document Msg
view model =
    { title = "PoE Mapwatch", body = [ viewBody model ] }


viewBody : Model -> Html Msg
viewBody rmodel =
    case rmodel of
        Err err ->
            pre [] [ text err ]

        Ok model ->
            case model.route of
                History ->
                    View.History.view model

                HistoryTSV ->
                    View.HistoryTSV.view model

                GSheets ->
                    View.GSheets.view model

                Maps ->
                    View.Maps.view model

                Encounters ->
                    View.Encounters.view model

                Timer ->
                    View.Timer.view model

                Overlay ->
                    View.Overlay.view model

                Debug ->
                    View.Debug.view model

                DebugDumpLines ->
                    View.DumpLines.view model

                DebugDatamine ->
                    View.DebugDatamine.view model.query model.mapwatch.datamine

                Changelog ->
                    View.Changelog.view model

                Privacy ->
                    View.Privacy.view model

                Settings ->
                    View.Settings.view model

                NotFound loc ->
                    View.NotFound.view model
