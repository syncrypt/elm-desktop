module VaultDialog.Update exposing (..)

import ConfirmationDialog
import Daemon
import Data.User exposing (Email)
import Data.Vault exposing (FlyingVault, HistoryItem, LogItem, Vault, VaultId, nameOrId)
import Dialog exposing (asModalIn)
import Dict
import Model exposing (Model, vaultWithId)
import Path exposing (folderName)
import Platform.Cmd exposing (map)
import Ports
import RemoteData exposing (RemoteData(..), WebData)
import Set
import Tooltip
import Translation as T
import Ui.Input
import Ui.Modal
import Ui.Tabs
import Util exposing ((~>), andLog, logFailure)
import VaultDialog.Model
    exposing
        ( CloneStatus(..)
        , FolderItem
        , Msg(..)
        , RequiresConfirmation(..)
        , State
        , addFolder
        , closeInfoBox
        , collapseFolder
        , expandFolder
        , hasChanged
        , isIgnored
        , openInfoBox
        , resetLocalFolderItems
        , toggleIgnorePath
        , toggleInfoBox
        , toggleUserKey
        )
import VaultDialog.Ports


open : Model -> ( Model, Cmd Model.Msg )
open model =
    case model.state of
        Model.CreatingNewVault ->
            openNew model

        Model.ShowingVaultDetails vault ->
            openForVault vault model

        Model.ShowingFlyingVaultDetails flyingVault ->
            openForFlyingVault flyingVault model

        _ ->
            ( model
            , Cmd.none
            )
                |> andLog "Invalid state for VaultDialog.open: " model.state


openNew : Model -> ( Model, Cmd Model.Msg )
openNew model =
    let
        state =
            VaultDialog.Model.init
    in
    ( state.modal
        |> Ui.Modal.open
        |> asModalIn state
        |> asStateIn "" model
    , Cmd.none
    )


openForFlyingVault : FlyingVault -> Model -> ( Model, Cmd Model.Msg )
openForFlyingVault flyingVault model =
    let
        path =
            []

        ( state, cmd ) =
            VaultDialog.Model.initForFlyingVault flyingVault
                |> setNameInputValue (nameOrId flyingVault)
    in
    ( state.modal
        |> Ui.Modal.open
        |> asModalIn state
        |> asStateIn flyingVault.id model
    , Cmd.map (Model.VaultDialogMsg flyingVault.id) cmd
    )


openForVault : Vault -> Model -> ( Model, Cmd Model.Msg )
openForVault vault model =
    let
        ( isNewlyCreated, ( state, cmd ) ) =
            case Dict.get vault.id model.vaultDialogs of
                Nothing ->
                    let
                        ( state, cmd ) =
                            VaultDialog.Model.initForVault vault
                                |> setNameInputValue (nameOrId vault)
                    in
                    ( True
                    , ( state, Cmd.map (Model.VaultDialogMsg vault.id) cmd )
                    )

                Just s ->
                    ( False
                    , ( s, Cmd.none )
                    )

        path =
            Maybe.withDefault [] state.localFolderPath

        commands =
            -- if isNewlyCreated then
            [ cmd
            , VaultDialog.Ports.getFileList ( vault.id, path )
            , model
                |> fetchUsers vault.id
            , model
                |> getVaultFingerprints vault.id
            , model
                |> getVaultEventLog vault.id
            ]

        -- else
        --     [ cmd ]
    in
    ( state.modal
        |> Ui.Modal.open
        |> asModalIn (state |> resetLocalFolderItems)
        |> asStateIn vault.id model
    , Cmd.batch commands
    )


cancel : VaultId -> Model -> Model
cancel vaultId model =
    { model | vaultDialogs = Dict.remove vaultId model.vaultDialogs }


close : VaultId -> Model -> Model
close vaultId model =
    let
        state =
            dialogState vaultId model
    in
    state.modal
        |> Ui.Modal.close
        |> asModalIn state
        |> asStateIn vaultId model


dialogState : VaultId -> Model -> State
dialogState vaultId model =
    case Dict.get vaultId model.vaultDialogs of
        Just state ->
            state

        Nothing ->
            VaultDialog.Model.initForVault (vaultWithId vaultId model)


saveVaultChanges : VaultId -> State -> Model -> ( Model, Cmd Model.Msg )
saveVaultChanges vaultId state model =
    let
        addUserCmds =
            state.usersToAdd
                |> Dict.toList
                |> List.map
                    (\( email, keys ) ->
                        model
                            |> Daemon.addVaultUser vaultId email keys
                    )

        updateMetadataCmd =
            Daemon.updateVaultMetadata
                vaultId
                { name = state.nameInput.value, icon = state.icon }
                model

        updateSettingsCmd =
            Daemon.updateVaultSettings vaultId
                { folder = state.localFolderPath
                , ignorePaths = state.ignoredFolderItems |> Set.toList
                }
                model
                |> Cmd.map (Model.VaultMetadataUpdated vaultId)

        commands =
            updateMetadataCmd :: updateSettingsCmd :: addUserCmds
    in
    ( cancel vaultId model
    , Cmd.batch commands
    )


update : VaultDialog.Model.Msg -> VaultId -> Model -> ( Model, Cmd Model.Msg )
update msg vaultId ({ vaultDialogs } as model) =
    let
        dialogMsg msg =
            Model.VaultDialogMsg vaultId << msg

        dialogCmd msg ( model, cmd ) =
            ( model, cmd |> map (dialogMsg msg) )

        state =
            dialogState vaultId model
    in
    case msg of
        -- ModalMsg only has Close so we know we'll want to close the
        -- dialog window because the user has clicked outside of it
        ModalMsg msg ->
            ( state.modal
                |> Ui.Modal.update msg
                |> asModalIn state
                |> asStateIn vaultId { model | state = Model.ShowingAllVaults }
                |> close vaultId
            , Cmd.none
            )

        NameChanged ->
            ( state
                |> hasChanged
                |> asStateIn vaultId model
            , Cmd.none
            )

        ConfirmationDialogMsg msg ->
            ( state
                |> ConfirmationDialog.update msg
                |> asStateIn vaultId model
            , Cmd.none
            )

        NameInputMsg msg ->
            let
                ( nameInput, cmd ) =
                    Ui.Input.update msg state.nameInput
                        |> dialogCmd NameInputMsg
            in
            ( { state | nameInput = nameInput }
                |> asStateIn vaultId model
            , cmd
            )

        UserInputMsg msg ->
            let
                ( userInput, cmd ) =
                    Ui.Input.update msg state.userInput
                        |> dialogCmd UserInputMsg
            in
            ( { state | userInput = userInput }
                |> asStateIn vaultId model
            , cmd
            )

        TabsMsg msg ->
            let
                ( tabs, cmd ) =
                    Ui.Tabs.update msg state.tabs
                        |> dialogCmd TabsMsg
            in
            ( { state | tabs = tabs }
                |> asStateIn vaultId model
            , cmd
            )

        FileCheckBoxMsg path _ ->
            ( state
                |> hasChanged
                |> toggleIgnorePath path
                |> asStateIn vaultId model
            , Cmd.none
            )

        NestedFileList rootPath f ->
            if Just rootPath /= state.localFolderPath then
                ( model
                , Cmd.none
                )
            else
                ( state
                    |> addFolder f
                    |> asStateIn vaultId model
                , Cmd.none
                )

        ToggleIgnorePath path ->
            ( state
                |> hasChanged
                |> toggleIgnorePath path
                |> asStateIn vaultId model
            , Cmd.none
            )

        OpenIconDialog ->
            ( model
            , VaultDialog.Ports.openIconFileDialog state.id
            )

        SelectedIcon iconUrl ->
            ( { state | icon = Just iconUrl }
                |> hasChanged
                |> asStateIn state.id model
            , Cmd.none
            )

        OpenExportDialog ->
            ( model
            , VaultDialog.Ports.openExportFileDialog
                ( state.id
                , T.t (T.VaultDialogTxt T.ExportToFile) model
                )
            )

        SelectedExportFile filePath ->
            ( model
            , Daemon.exportVault state.id filePath model
            )

        OpenFolderDialog ->
            ( model
            , VaultDialog.Ports.openFolderDialog state.id
            )

        OpenFolder folderPath ->
            ( model
            , Ports.openVaultFolder folderPath
            )

        SelectedFolder path ->
            let
                ( nameInput, nameInputCmd ) =
                    Ui.Input.setValue (folderName path) state.nameInput
                        |> dialogCmd NameInputMsg
            in
            ( { state
                | localFolderPath = Just path
                , localFolderItems = Dict.empty
                , nameInput = nameInput
              }
                |> hasChanged
                |> asStateIn vaultId model
            , Cmd.batch
                [ VaultDialog.Ports.getFileList ( vaultId, path )
                , nameInputCmd
                ]
            )

        CollapseFolder path ->
            ( state
                |> collapseFolder path
                |> asStateIn vaultId model
            , Cmd.none
            )

        ExpandFolder path ->
            ( state
                |> expandFolder path
                |> asStateIn vaultId model
            , Cmd.none
            )

        Confirm DeleteVault ->
            let
                title =
                    T.t (T.VaultDialogTxt T.AskDeleteVault) model

                question =
                    T.t (T.VaultDialogTxt T.AskDeleteVaultExtended) model

                confirmMsg =
                    Confirmed DeleteVault
            in
            ( state
                |> ConfirmationDialog.open title question confirmMsg
                |> asStateIn vaultId model
            , Cmd.none
            )

        Confirm RemoveVault ->
            let
                title =
                    T.translate model.language
                        (T.ConfirmationDialogTxt T.RemoveVaultFromSyncQuestion)

                question =
                    T.translate model.language
                        (T.ConfirmationDialogTxt T.RemoveVaultFromSyncExplanation)

                confirmMsg =
                    Confirmed RemoveVault
            in
            ( state
                |> ConfirmationDialog.open title question confirmMsg
                |> asStateIn vaultId model
            , Cmd.none
            )

        Confirm AddUser ->
            -- no dialog shown for this, just a button
            ( model
            , Cmd.none
            )

        Confirmed DeleteVault ->
            ( model
            , model
                |> Daemon.deleteVault vaultId
                |> Cmd.map Model.DeletedVault
            )

        Confirmed RemoveVault ->
            ( model
            , Daemon.removeVault vaultId model
            )

        ResyncVault ->
            ( model
            , Daemon.resyncVault vaultId model
            )

        Confirmed AddUser ->
            let
                ( input, cmd ) =
                    Ui.Input.setValue "" state.userInput
                        |> dialogCmd UserInputMsg
            in
            ( { state | userInput = input }
                |> hasChanged
                |> asStateIn vaultId model
            , cmd
            )

        FetchedUsers users ->
            ( { state | users = users |> logFailure "FetchedUsers" }
                |> asStateIn vaultId model
            , Cmd.none
            )

        FetchedVaultHistory items ->
            ( { state | historyItems = items |> logFailure "FetchedVaultHistory" }
                |> asStateIn vaultId model
            , Cmd.none
            )

        UserKeyCheckbox email userKey _ ->
            ( state
                |> toggleUserKey email userKey
                |> asStateIn vaultId model
            , Cmd.none
            )

        ToggleUserKey email key ->
            ( state
                |> hasChanged
                |> toggleUserKey email key
                |> asStateIn vaultId model
            , Cmd.none
            )

        AddUserWithKeys email keys ->
            let
                usersToAdd =
                    Dict.insert email keys state.usersToAdd
            in
            ( { state | usersToAdd = usersToAdd }
                |> hasChanged
                |> asStateIn vaultId model
            , Cmd.none
            )

        SearchUserKeys email ->
            let
                newState =
                    case Dict.get email state.userKeys of
                        Just (Success _) ->
                            state

                        _ ->
                            { state
                                | userKeys =
                                    state.userKeys
                                        |> Dict.insert email Loading
                            }
            in
            newState
                |> asStateIn vaultId model
                |> searchFingerprints email vaultId

        FoundUserKeys email keys ->
            let
                cmd =
                    case keys of
                        Success _ ->
                            Ports.addEmailToCompletionList email

                        _ ->
                            Cmd.none
            in
            ( { state | userKeys = Dict.insert email keys state.userKeys }
                |> asStateIn vaultId model
            , cmd
            )

        GetVaultFingerprints ->
            ( model
            , getVaultFingerprints state.id model
            )

        FoundVaultFingerprints data ->
            ({ state
                | vaultFingerprints =
                    RemoteData.map Set.fromList data
                        |> logFailure "FoundVaultFingerprints"
             }
                |> asStateIn state.id model
            )
                |> Util.retryOnFailure data (Model.VaultDialogMsg vaultId GetVaultFingerprints)

        SetUserInput email ->
            model
                |> setUserInput email state
                ~> searchFingerprints email vaultId

        VaultLogStream logItem ->
            ( model
                |> addLogStreamItem logItem vaultId state
            , Cmd.none
            )

        VaultHistoryStream histItem ->
            ( model
                |> addHistoryStreamItem histItem vaultId state
            , Cmd.none
            )

        ToggleEventSortOrder ->
            ( state
                |> VaultDialog.Model.toggleSortOrder
                |> asStateIn vaultId model
            , Cmd.none
            )

        SortEventsBy sortFn ->
            ( state
                |> VaultDialog.Model.sortBy sortFn
                |> asStateIn vaultId model
            , Cmd.none
            )

        FilterEventsBy eventFilter ->
            ( state
                |> VaultDialog.Model.filterEventsBy eventFilter
                |> asStateIn vaultId model
            , Cmd.none
            )

        ToggleViewLogLevelFilters ->
            ( { state | viewLogLevelFilters = not state.viewLogLevelFilters }
                |> asStateIn vaultId model
            , Cmd.none
            )

        ToggleInfoBox tabId ->
            ( toggleInfoBox tabId state
                |> asStateIn vaultId model
            , Cmd.none
            )

        CloseInfoBox tabId ->
            ( closeInfoBox tabId state
                |> asStateIn vaultId model
            , Cmd.none
            )


getVaultFingerprints : VaultId -> Model -> Cmd Model.Msg
getVaultFingerprints vaultId model =
    model
        |> Daemon.getVaultFingerprints vaultId
        |> Cmd.map (Model.VaultDialogMsg vaultId << FoundVaultFingerprints)


getVaultEventLog : VaultId -> Model -> Cmd Model.Msg
getVaultEventLog vaultId model =
    model
        |> Daemon.getVaultHistory vaultId
        |> Cmd.map (Model.VaultDialogMsg vaultId << FetchedVaultHistory)


addLogStreamItem : Result String LogItem -> VaultId -> State -> Model -> Model
addLogStreamItem logItem vaultId state model =
    case logItem of
        Err reason ->
            model
                |> andLog "Failed decoding Vault log stream message: " reason

        Ok item ->
            { state | logItems = item :: state.logItems }
                |> asStateIn vaultId model


addHistoryStreamItem : Result String HistoryItem -> VaultId -> State -> Model -> Model
addHistoryStreamItem histItem vaultId state model =
    case histItem of
        Err reason ->
            model
                |> andLog "Failed decoding Vault history stream message: " reason

        Ok item ->
            let
                oldItems =
                    RemoteData.withDefault [] state.historyItems
            in
            { state | historyItems = Success (item :: oldItems) }
                |> asStateIn vaultId model


setUserInput : Email -> State -> Model -> ( Model, Cmd Model.Msg )
setUserInput email state model =
    let
        ( userInput, inputCmd ) =
            Ui.Input.setValue email state.userInput

        cmd =
            Cmd.map (Model.VaultDialogMsg state.id << UserInputMsg) inputCmd
    in
    ( { state
        | userInput = userInput
        , userKeys =
            Dict.update email
                (Just << Maybe.withDefault Loading)
                state.userKeys
      }
        |> asStateIn state.id model
    , cmd
    )


searchFingerprints : Email -> VaultId -> Model -> ( Model, Cmd Model.Msg )
searchFingerprints email vaultId model =
    ( model
    , model
        |> Daemon.getUserKeys email
        |> Cmd.map (Model.VaultDialogMsg vaultId << FoundUserKeys email)
    )


fetchUsers : VaultId -> Model -> Cmd Model.Msg
fetchUsers vaultId model =
    model
        |> Daemon.getVaultUsers vaultId
        |> Cmd.map (Model.VaultDialogMsg vaultId << FetchedUsers)


asStateIn : VaultId -> Model -> State -> Model
asStateIn vaultId model state =
    { model
        | vaultDialogs =
            Dict.insert vaultId state model.vaultDialogs
    }


setNameInputValue : String -> State -> ( State, Cmd Msg )
setNameInputValue value state =
    let
        ( nameInput, cmd ) =
            state.nameInput
                |> Ui.Input.setValue value
    in
    ( { state | nameInput = nameInput }
    , Cmd.map NameInputMsg cmd
    )


isOwner : VaultId -> Model -> Bool
isOwner vaultId model =
    let
        state =
            dialogState vaultId model
    in
    case model.login of
        Model.Unknown ->
            False

        Model.LoggedOut ->
            state.cloneStatus == New

        Model.LoggedIn { email } ->
            case List.head <| RemoteData.withDefault [] state.users of
                Nothing ->
                    state.cloneStatus == New

                Just owner ->
                    email == owner.email
