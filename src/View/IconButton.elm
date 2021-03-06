module View.IconButton exposing (IconButton(..), view)

import Html exposing (Html, div)
import Html.Attributes exposing (class, style)
import Language exposing (Language)
import Tooltip exposing (Length(Auto))
import Translation as T
import Util exposing (Position(..))


type IconButton
    = SettingsButton
    | LogoutButton
    | FeedbackButton
    | DaemonLogButton
    | ImportVaultButton


view : List (Html.Attribute msg) -> Language -> IconButton -> Html msg
view attrs language buttonType =
    Tooltip.item
        { position = Bottom
        , length = Auto
        , text = tooltip language buttonType
        , visible = False
        }
        [ div
            (class "MainScreen-IconButton" :: attrs)
            [ div
                [ class "Icon"
                , style
                    [ ( "backgroundImage"
                      , "url(assets/" ++ iconName buttonType ++ "_24px.svg)"
                      )
                    ]
                ]
                []
            ]
        ]


iconName : IconButton -> String
iconName buttonType =
    case buttonType of
        LogoutButton ->
            "exit"

        SettingsButton ->
            "settings"

        FeedbackButton ->
            "feedback"

        DaemonLogButton ->
            "event"

        ImportVaultButton ->
            -- TODO: use custom / better icon here
            "edit"


tooltip : Language -> IconButton -> String
tooltip language buttonType =
    case buttonType of
        LogoutButton ->
            T.translate language T.Logout

        SettingsButton ->
            T.translate language T.SoftwareAndAccountSettings

        FeedbackButton ->
            T.translate language T.SendUsFeedbackAndBugReports

        DaemonLogButton ->
            T.translate language T.ViewDaemonLog

        ImportVaultButton ->
            T.translate language T.ImportVault
