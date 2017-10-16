module MainScreen exposing (..)

import Animation exposing (..)
import Config exposing (Config)
import Daemon
import Data.Daemon exposing (GUIConfig)
import Data.User exposing (Email)
import Data.Vault exposing (FlyingVault, Vault, VaultId, VaultOptions(..))
import Date
import Html exposing (Html, div, node, span, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import LoginDialog.Update
import LoginDialog.View
import Model exposing (..)
import Ports
import RemoteData exposing (RemoteData(..), WebData)
import Set
import SettingsDialog.Model as SettingsDialog
import SettingsDialog.Update
import SettingsDialog.View
import Time
import Translation exposing (NotificationText(..), Text(..), t, translate)
import Ui.Input
import Ui.NotificationCenter
import Util exposing (Direction(..), IconButton(..), iconButton, (~>))
import VaultDialog.Model exposing (CloneStatus(..))
import VaultDialog.Update exposing (dialogState)
import VaultDialog.View
import VaultList
import WizardDialog
    exposing
        ( Button(Cancel, CustomButton)
        , ButtonSettings(Default, Visible)
        , Step(..)
        )


-- INIT


init : Config -> ( Model, Cmd Msg )
init config =
    let
        model =
            Model.init config

        initialActions =
            [ Daemon.getLoginState model
            , Daemon.getVaults model
            , Daemon.getStats model
            , Ports.updateEmailCompletionList ()
            , Daemon.getConfig model
            ]
    in
        model ! initialActions



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.login of
        LoggedIn _ ->
            Sub.batch
                [ VaultDialog.View.subscriptions model
                , Time.every (10 * Time.minute) (\_ -> UpdateVaults)
                , Time.every Time.second (Date.fromTime >> SetTime)
                , Time.every model.config.updateInterval (\_ -> UpdateStats)
                , Ports.getEmailCompletionList EmailCompletionList
                ]

        _ ->
            Sub.none



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetTime time ->
            { model | now = Just time }
                ! []

        UpdateLoginState ->
            model
                |> updateLoginState

        UpdateVaults ->
            model
                |> updateVaults

        UpdateDaemonConfig ->
            model
                ! [ Daemon.getConfig model ]

        UpdateFlyingVaults ->
            model
                |> updateFlyingVaults

        UpdateStats ->
            model
                |> updateStats

        UpdatedLoginState data ->
            model
                |> updatedLoginState data

        UpdatedVaultsFromApi vaults ->
            model
                |> updatedVaults vaults

        UpdatedFlyingVaultsFromApi vaults ->
            model
                |> updatedFlyingVaults vaults

        OpenVaultDetails vault ->
            model
                |> openVaultDetails vault

        OpenFlyingVaultDetails flyingVault ->
            model
                |> openFlyingVaultDetails flyingVault

        CloneVault vaultId ->
            model
                |> cloneVault vaultId
                ~> VaultDialog.Update.close vaultId

        ClonedVault vaultId data ->
            model
                |> clonedVault vaultId data

        CloseVaultDetails vaultId ->
            model
                |> closeVaultDetails vaultId

        SaveVaultDetails vaultId ->
            { model | state = ShowingAllVaults }
                |> VaultDialog.Update.close vaultId
                ~> saveVault vaultId

        Model.CreateNewVault ->
            { model | state = CreatingNewVault }
                |> VaultDialog.Update.openNew

        CreatedVault dialogState (Success vault) ->
            model
                |> VaultDialog.Update.saveVaultChanges vault.id dialogState
                ~> (notifyText <| VaultCreated vault.id)
                ~> updateVaults

        CreatedVault _ (Failure reason) ->
            model
                |> notifyText (VaultCreateFailed <| toString reason)

        CreatedVault _ _ ->
            model
                ! []

        ExportedVault vaultId (Success { success, filename }) ->
            model
                |> notifyText (VaultExported vaultId)

        ExportedVault vaultId data ->
            model
                |> notifyText (VaultExportFailed (toString data))

        RemoveVaultFromSync vaultId ->
            model
                |> removeVaultFromSync vaultId

        RemovedVaultFromSync (Success vaultId) ->
            model
                |> VaultDialog.Update.cancel vaultId
                ~> (notifyText <| VaultRemoved vaultId)

        RemovedVaultFromSync data ->
            model
                |> notifyText (VaultRemoveFailed <| toString data)

        DeletedVault data ->
            model
                |> deletedVault data

        VaultDialogMsg vaultId msg ->
            model
                |> VaultDialog.Update.update msg vaultId

        OpenVaultFolder vault ->
            model
                ! [ Ports.openVaultFolder vault.folderPath ]

        OpenSettingsDialog ->
            -- TODO
            (model
                |> SettingsDialog.open
            )
                ! []

        CloseSettingsDialog ->
            (model
                |> SettingsDialog.close
            )
                ! []

        Login ->
            model
                |> login

        Logout ->
            model
                |> logout

        Model.LoginDialogMsg msg ->
            model
                |> LoginDialog.Update.update msg

        LoginResult email data ->
            model
                |> handleLoginResult email data

        LogoutResult _ ->
            { model | login = LoggedOut }
                ! []

        FocusOn id ->
            model
                ! [ Ports.focusOn id ]

        NotificationCenterMsg msg ->
            let
                ( state, cmd ) =
                    Ui.NotificationCenter.update msg model.notificationCenter
            in
                { model | notificationCenter = state }
                    ! [ Cmd.map NotificationCenterMsg cmd ]

        UpdatedStatsFromApi stats ->
            { model | stats = stats }
                ! []

        VaultUserAdded vaultId email data ->
            model
                |> vaultUserAdded vaultId email data

        VaultMetadataUpdated vaultId (Success _) ->
            model
                |> updateVaults

        VaultMetadataUpdated vaultId _ ->
            model
                |> notifyText (VaultMetadataUpdateFailed vaultId)

        WizardDialogMsg msg ->
            model
                |> WizardDialog.update msg

        SettingsDialogMsg msg ->
            model
                |> SettingsDialog.Update.update msg

        OpenSetupWizardDialog ->
            (model
                |> openSetupWizard
            )
                ! []

        SetupWizardFinished ->
            ({ model | isFirstLaunch = False }
                ! [ Daemon.invalidateFirstLaunch model ]
            )
                ~> (notify (text "Syncrypt initialized"))

        EmailCompletionList emails ->
            let
                _ =
                    Debug.log "got email completion list: " emails
            in
                { model | emailCompletionList = emails }
                    ! []

        UpdatedDaemonConfig (Success { gui }) ->
            (model
                |> updateGUIConfig gui
                |> openSetupWizardIfFirstLaunch
            )
                ! []

        UpdatedDaemonConfig msg ->
            model
                |> Model.retryOnFailure msg UpdateDaemonConfig

        OpenFeedbackWizard ->
            (model
                |> openFeedbackWizard
            )
                ! []

        SentFeedback (Success _) ->
            { model | feedback = Nothing }
                |> notify (text "Thanks for your feedback!")

        SentFeedback error ->
            model
                |> notify (text "Sending feedback failed. Please try again.")

        --  ~> (notify (text "Failed to send feedback. Retrying."))
        FeedbackEntered text ->
            case String.trim text of
                "" ->
                    { model | feedback = Nothing }
                        ! []

                trimmedText ->
                    { model | feedback = Just trimmedText }
                        ! []

        SendFeedback ->
            model
                |> WizardDialog.close
                |> sendFeedback

        SetupWizardMsg msg ->
            model ! []



-- TODO:
-- case msg of
--     EmailInputMsg msg ->
--         Ui.Input.update msg model.accountSetupWizard.emailInput
--
--
--     PasswordInputMsg msg ->
--         Ui.Input.update msg model.accountSetupWizard.passwordInput
--
--     PasswordConfirmationInputMsg msg ->
--         Ui.Input.update msg model.accountSetupWizard.passwordConfirmationInput


sendFeedback : Model -> ( Model, Cmd Msg )
sendFeedback model =
    case model.feedback of
        Nothing ->
            model
                ! []

        Just feedback ->
            model
                ! [ Daemon.sendFeedback feedback model.config ]


updateGUIConfig : GUIConfig -> Model -> Model
updateGUIConfig { isFirstLaunch, language } model =
    { model
        | isFirstLaunch = isFirstLaunch
        , language = language
    }


openSetupWizardIfFirstLaunch : Model -> Model
openSetupWizardIfFirstLaunch model =
    if model.isFirstLaunch then
        model
            |> openSetupWizard
    else
        model


wizardContent : List (Html msg) -> Html msg
wizardContent body =
    div [ class "MainScreen-SetupWizard" ]
        body


openSetupWizard : Model -> Model
openSetupWizard model =
    let
        steps =
            [ Step
                { title = "Welcome to Syncrypt"
                , contents =
                    wizardContent
                        [ text "We'll guide you through a step-by-step setup process to initiate your Syncrypt account." ]
                , buttons = Default
                }
            , setupWizardAccountSetupStep model
            ]
    in
        model
            |> WizardDialog.open steps SetupWizardFinished


setupWizardAccountSetupStep : HasAccountSetupWizard a -> Step Msg
setupWizardAccountSetupStep ({ accountSetupWizard } as model) =
    Step
        { title = "Account Setup"
        , contents =
            wizardContent
                [ text "Setup your account here"
                , text "Email"
                , Ui.Input.view accountSetupWizard.emailInput
                    |> Html.map (Model.SetupWizardMsg << EmailInputMsg)
                , text "Password"
                , Ui.Input.view accountSetupWizard.passwordInput
                    |> Html.map (Model.SetupWizardMsg << PasswordInputMsg)
                , text "Password Confirmation"
                , Ui.Input.view accountSetupWizard.passwordConfirmationInput
                    |> Html.map (Model.SetupWizardMsg << PasswordConfirmationInputMsg)
                ]
        , buttons = Default
        }


openFeedbackWizard : Model -> Model
openFeedbackWizard model =
    let
        wizardContent body =
            div [ class "FeedbackWizard" ]
                body

        steps =
            [ Step
                { title = "Send us feedback"
                , contents =
                    wizardContent
                        [ div [ class "Label" ]
                            [ text "Your feedback, suggestions or bug report:" ]
                        , div []
                            [ Html.textarea
                                [ class "FeedbackTextArea"
                                , cols 40
                                , rows 10
                                , placeholder "Type your feedback here"
                                , onInput FeedbackEntered
                                ]
                                []
                            ]
                        ]
                , buttons =
                    Visible
                        [ Cancel
                        , CustomButton [ style [ ( "float", "right" ) ] ]
                            "Send Feedback"
                            SendFeedback
                        ]
                }
            ]
    in
        model
            |> WizardDialog.open steps SendFeedback


updateLoginState : Model -> ( Model, Cmd Msg )
updateLoginState model =
    model
        ! [ Daemon.getLoginState model ]


updateVaults : Model -> ( Model, Cmd Msg )
updateVaults model =
    { model | state = UpdatingVaults }
        ! [ Daemon.getVaults model ]


updateFlyingVaults : Model -> ( Model, Cmd Msg )
updateFlyingVaults model =
    { model | flyingVaults = Loading }
        ! [ Daemon.getFlyingVaults model ]


updateStats : Model -> ( Model, Cmd Msg )
updateStats model =
    model
        ! [ Daemon.getStats model ]


updatedLoginState : WebData LoginState -> Model -> ( Model, Cmd Msg )
updatedLoginState data model =
    case data of
        Success loginState ->
            { model | login = loginState }
                ! []

        Failure _ ->
            { model | login = LoggedOut }
                |> Model.retryOnFailure data UpdateLoginState

        _ ->
            { model | login = Unknown }
                ! []


updatedVaults : WebData (List Vault) -> Model -> ( Model, Cmd Msg )
updatedVaults vaults model =
    { model | vaults = vaults }
        ! []


updatedFlyingVaults : WebData (List FlyingVault) -> Model -> ( Model, Cmd Msg )
updatedFlyingVaults flyingVaults model =
    { model | flyingVaults = flyingVaults }
        |> Model.retryOnFailure flyingVaults UpdateFlyingVaults


openVaultDetails : Vault -> Model -> ( Model, Cmd Msg )
openVaultDetails vault model =
    { model | state = ShowingVaultDetails vault }
        |> VaultDialog.Update.open


closeVaultDetails : VaultId -> Model -> ( Model, Cmd Msg )
closeVaultDetails vaultId model =
    { model | state = ShowingAllVaults }
        |> VaultDialog.Update.cancel vaultId


openFlyingVaultDetails : FlyingVault -> Model -> ( Model, Cmd Msg )
openFlyingVaultDetails flyingVault model =
    { model | state = ShowingFlyingVaultDetails flyingVault }
        |> VaultDialog.Update.open


deletedVault : WebData VaultId -> Model -> ( Model, Cmd Msg )
deletedVault data model =
    case data of
        Success vaultId ->
            let
                newModel =
                    case model.state of
                        ShowingVaultDetails v ->
                            if v.id == vaultId then
                                { model | state = ShowingAllVaults }
                            else
                                model

                        _ ->
                            model
            in
                newModel
                    |> VaultDialog.Update.close vaultId
                    ~> (notifyText <| VaultDeleted vaultId)

        _ ->
            model
                |> notifyText (VaultDeleteFailed <| toString data)


notify : Html Msg -> Model -> ( Model, Cmd Msg )
notify body model =
    let
        content =
            div [ class "MainScreen-NotificationCenter" ] [ body ]

        ( state, cmd ) =
            Ui.NotificationCenter.notify content model.notificationCenter
    in
        { model | notificationCenter = state }
            ! [ Cmd.map NotificationCenterMsg cmd ]


notifyText : Translation.NotificationText -> Model -> ( Model, Cmd Msg )
notifyText notificationText model =
    model
        |> notify
            (text <|
                t (NotificationText notificationText) model
            )


saveVault : Data.Vault.VaultId -> Model -> ( Model, Cmd Msg )
saveVault vaultId model =
    let
        state =
            dialogState vaultId model
    in
        case state.cloneStatus of
            New ->
                model
                    |> createVault state

            _ ->
                model
                    |> VaultDialog.Update.saveVaultChanges vaultId state
                    ~> (notifyText <| VaultUpdated vaultId)


createVault : VaultDialog.Model.State -> Model -> ( Model, Cmd Msg )
createVault state model =
    case state.localFolderPath of
        Just folderPath ->
            model
                ! [ model.config
                        |> Daemon.updateVault
                            (Create
                                { folder = folderPath
                                , ignorePaths = Set.toList state.ignoredFolderItems
                                }
                            )
                        |> Cmd.map (CreatedVault state)
                  ]

        Nothing ->
            model
                |> notifyText NoPathSelected


cloneVault : VaultId -> Model -> ( Model, Cmd Msg )
cloneVault vaultId origModel =
    let
        model =
            { origModel | state = CloningVault vaultId }

        state =
            dialogState vaultId model
    in
        case state.localFolderPath of
            Nothing ->
                model
                    |> notifyText (CouldNotCloneVaultWithoutFolder vaultId)

            Just folderPath ->
                model
                    ! [ model.config
                            |> Daemon.updateVault
                                (Clone
                                    { id = vaultId
                                    , folder = folderPath
                                    , ignorePaths = Set.toList state.ignoredFolderItems
                                    }
                                )
                            |> Cmd.map (ClonedVault vaultId)
                      ]


clonedVault : VaultId -> WebData Vault -> Model -> ( Model, Cmd Msg )
clonedVault vaultId data model =
    case data of
        Success vault ->
            { model | state = ShowingAllVaults }
                ! [ Daemon.getVaults model ]

        Failure reason ->
            model
                |> notifyText (VaultCloneFailed vaultId <| toString reason)

        result ->
            model
                |> notifyText (VaultCloneFailed vaultId <| toString result)


vaultUserAdded : VaultId -> Email -> WebData Email -> Model -> ( Model, Cmd Msg )
vaultUserAdded vaultId email data model =
    case data of
        Success _ ->
            model
                ! []

        _ ->
            model
                |> notifyText (VaultAddUserFailed vaultId email)


login : Model -> ( Model, Cmd Msg )
login model =
    let
        email =
            model.loginDialog.emailInput.value

        password =
            model.loginDialog.passwordInput.value
    in
        model
            ! [ Daemon.login email password model ]


logout : Model -> ( Model, Cmd Msg )
logout model =
    model
        ! [ Daemon.logout model ]


handleLoginResult :
    Email
    -> WebData StatusResponse
    -> Model
    -> ( Model, Cmd Msg )
handleLoginResult email data model =
    case data of
        Success _ ->
            { model | login = LoggedIn { firstName = "", lastName = "", email = email } }
                ! []

        Failure reason ->
            { model | login = LoggedOut }
                ! []

        _ ->
            { model | login = Unknown }
                ! []


removeVaultFromSync : VaultId -> Model -> ( Model, Cmd Msg )
removeVaultFromSync vaultId model =
    model
        ! [ Daemon.removeVault vaultId model ]



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "MainScreen" ] <|
        case model.login of
            Unknown ->
                [ text "..." ]

            LoggedOut ->
                [ LoginDialog.View.view model ]

            LoggedIn _ ->
                [ div [ class (currentClass model) ] <|
                    [ header
                    , div [ class "MainScreen-Container", animation 1.0 FadeInFast ]
                        [ VaultList.view model ]
                    , footer model
                    , viewNotificationCenter model
                    , WizardDialog.view model
                    , SettingsDialog.View.view model
                    ]
                        ++ VaultDialog.View.viewAll model
                ]


currentClass : Model -> String
currentClass model =
    if model.sidebarOpen then
        "MainScreen-Container"
    else
        "MainScreen-Container MainScreen-Expanded"


viewNotificationCenter : Model -> Html Msg
viewNotificationCenter { notificationCenter } =
    Ui.NotificationCenter.view NotificationCenterMsg notificationCenter


header : Html Msg
header =
    div [ class "MainScreen-Header" ]
        [ div [ class "MainScreen-HeaderLogo" ]
            []
        , div [ class "MainScreen-Buttons" ]
            [ iconButton FeedbackButton [ onClick OpenFeedbackWizard ]
            , iconButton SettingsButton [ onClick OpenSettingsDialog ]
            , iconButton LogoutButton [ onClick Logout ]
            ]
        ]


footer : Model -> Html Msg
footer { stats, vaults, language } =
    let
        statsText =
            Translation.StatsText <|
                case stats of
                    Success s ->
                        Translation.Stats s

                    Loading ->
                        Translation.StatsLoading

                    NotAsked ->
                        Translation.StatsNotAvailable

                    Failure reason ->
                        Translation.StatsFailedToLoad (toString reason)

        syncedVaultsText =
            case vaults of
                Success vaults ->
                    Translation.SyncedVaults (List.length vaults)

                Loading ->
                    Translation.VaultsLoading

                NotAsked ->
                    Translation.VaultsNotAvailable

                Failure reason ->
                    Translation.VaultsFailedToLoad (toString reason)
    in
        div [ class "MainScreen-Footer" ]
            [ span [ class "MainScreen-Stats" ]
                [ text <|
                    translate syncedVaultsText language
                        ++ translate statsText language
                ]
            ]
