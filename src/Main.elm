module Main exposing (..)

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Config exposing (Config)
import Syncrypt.User exposing (User)
import Syncrypt.Vault exposing (Vault)
import Dict exposing (Dict)
import View.VaultList
import Model exposing (..)
import Api
import Debug


main =
    Html.program
        { init = init
        , subscriptions = subscriptions
        , view = view
        , update = update
        }


init : ( Model, Cmd Msg )
init =
    ( initialModel, Cmd.none )


initialModel : Model
initialModel =
    { config =
        { apiUrl = "http://localhost:28080/v1/"
        , apiAuthToken = "my API token here"
        }
    , vaults =
        [ Syncrypt.Vault.init "12312-asadssad-asdasdasd-123231123" ]
    , state = LoadingVaults
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


view : Model -> Html.Html Msg
view { config, state } =
    case state of
        LoadingVaults ->
            div [ class "vault-list", onClick UpdateVaults ]
                [ Html.text "Loading Vaults" ]

        UpdatingVaults vaults ->
            text ("Updating vaults: " ++ (vaults |> List.length |> toString))

        ShowingAllVaults vaults ->
            div []
                (text ("Showing vaults: " ++ (vaults |> List.length |> toString))
                    :: List.map View.VaultList.vaultItem vaults
                )

        ShowingVaultDetails { id } ->
            text ("Vault details = " ++ id)


update : Msg -> Model -> ( Model, Cmd Msg )
update action model =
    case action of
        UpdateVaults ->
            ( { model | state = UpdatingVaults model.vaults }, Api.getVaults model.config )

        UpdatedVaultsFromApi (Ok vaults) ->
            ( { model | state = ShowingAllVaults vaults, vaults = vaults }, Cmd.none )

        UpdatedVaultsFromApi (Err reason) ->
            let
                _ =
                    Debug.log ("Error UpdatedVaultsFromApi: " ++ (toString reason))
            in
                -- retry to get vaults if request failed
                ( model, Api.getVaults model.config )

        _ ->
            ( { model | state = LoadingVaults }, Cmd.none )
