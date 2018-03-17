module VaultDialog.View exposing (..)

import Animation
    exposing
        ( Animation(..)
        , animation
        , loadingSpinner
        , loadingSpinnerIf
        )
import ConfirmationDialog
import Daemon
import Data.User as User exposing (Email, User, UserKey)
import Data.Vault
    exposing
        ( Event(..)
        , HistoryItem
        , LogLevel(..)
        , Vault
        , VaultId
        )
import Date exposing (Date)
import Date.Distance
import Dialog exposing (labeledItem)
import Dict
import Html
    exposing
        ( Html
        , div
        , h4
        , img
        , span
        , table
        , td
        , text
        , th
        , tr
        )
import Html.Attributes exposing (class, classList, src)
import Html.Events exposing (onClick)
import Language exposing (HasLanguage)
import Model exposing (Model)
import Path exposing (Path)
import RemoteData exposing (RemoteData(..))
import Translation
    exposing
        ( FolderButtonType(..)
        , Text(..)
        , VaultDialogText(..)
        , t
        , timeAgo
        )
import Ui.Checkbox
import Ui.Container
import Ui.Input
import Ui.Modal
import Ui.Tabs
import Util
    exposing
        ( Position(..)
        , TooltipLength(..)
        , button
        , dateParts
        , fullDateString
        , materialIcon
        , onAnyKeyDown
        , onEnter
        , shortDateString
        , tooltipItem
        )
import VaultDialog.Model
    exposing
        ( CloneStatus(..)
        , EventFilter(..)
        , FileName
        , FolderItem
        , Msg(..)
        , RequiresConfirmation(..)
        , State
        , TabId
        , folderIsEmpty
        , hasFiles
        , isExpanded
        , isFilterEnabled
        , isIgnored
        , isInfoBoxOpen
        , isUserKeyAlreadyAdded
        , isUserKeySelected
        , keysToAdd
        , sortedFolders
        , userInputEmail
        , userKeys
        )
import VaultDialog.Ports
import VaultDialog.Update exposing (dialogState, isOwner)


subscriptions : Model -> Sub Model.Msg
subscriptions model =
    let
        msg =
            Model.VaultDialogMsg

        fileListMsg ( vaultId, rootPath, folderItem ) =
            msg vaultId <| NestedFileList rootPath folderItem

        selectedFolderMsg ( vaultId, path ) =
            msg vaultId <| SelectedFolder path

        selectedExportFileMsg ( vaultId, path ) =
            msg vaultId <| SelectedExportFile path

        logStream =
            case model.state of
                Model.ShowingVaultDetails vault ->
                    let
                        logMsg =
                            msg vault.id << VaultLogStream
                    in
                    model
                        |> Daemon.subscribeVaultLogStream vault.id logMsg

                _ ->
                    Sub.none
    in
    Sub.batch
        [ VaultDialog.Ports.fileList fileListMsg
        , VaultDialog.Ports.selectedFolder selectedFolderMsg
        , VaultDialog.Ports.selectedExportFile selectedExportFileMsg
        , logStream
        ]


viewAll : Model -> List (Html Model.Msg)
viewAll ({ vaultDialogs } as model) =
    vaultDialogs
        |> Dict.keys
        |> List.map (\vaultId -> view vaultId model)


view : VaultId -> Model -> Html Model.Msg
view vaultId model =
    let
        state =
            dialogState vaultId model

        viewConfig =
            { address = Model.VaultDialogMsg vaultId << ModalMsg
            , contents = contents vaultId model
            , footer =
                [ span [ class "Buttons" ]
                    [ saveButton vaultId state model
                    , cancelButton vaultId state model
                    ]
                ]
            , title =
                case state.cloneStatus of
                    New ->
                        t CreateNewVault model

                    Cloned ->
                        state.title

                    NotCloned ->
                        t (VaultNotSynced vaultId) model
            }
    in
    div [ class "VaultDialog" ]
        [ Ui.Modal.view viewConfig state.modal ]


contents : VaultId -> Model -> List (Html Model.Msg)
contents vaultId model =
    let
        state =
            dialogState vaultId model

        tabsViewConfig =
            { address = Model.VaultDialogMsg vaultId << TabsMsg
            , contents = tabContents vaultId state model
            }

        tabs =
            Ui.Tabs.view tabsViewConfig state.tabs

        confirmationDialog =
            ConfirmationDialog.view model.language state
                |> Html.map (Model.VaultDialogMsg state.id)
    in
    [ tabs
    , confirmationDialog
    ]


tabContents : VaultId -> State -> Model -> List ( String, Html Model.Msg )
tabContents vaultId state model =
    let
        msg =
            Model.VaultDialogMsg vaultId

        basicTabs =
            [ filesTab msg vaultId state model
            , usersTab msg vaultId state model
            ]

        clonedTabs =
            [ cryptoTab vaultId state model
            , logTab vaultId state model
            , adminTab vaultId state model
            ]

        notClonedTabs =
            [ cryptoTab vaultId state model
            , adminTab vaultId state model
            ]

        tabs =
            case state.cloneStatus of
                New ->
                    basicTabs

                Cloned ->
                    basicTabs ++ clonedTabs

                NotCloned ->
                    basicTabs ++ notClonedTabs
    in
    tabs


type alias TabBodySettings =
    { infoBox : Maybe InfoBox
    , vaultId : VaultId
    , state : State
    , body : List (Html Model.Msg)
    }


tabBody : TabBodySettings -> Html Model.Msg
tabBody settings =
    let
        infoBox =
            case settings.infoBox of
                Nothing ->
                    text ""

                Just infoBox ->
                    viewInfoBox infoBox settings.vaultId settings.state
    in
    div []
        [ infoBox
        , div [ class "TabBody" ]
            settings.body
        ]


usersTab :
    (Msg -> Model.Msg)
    -> VaultId
    -> State
    -> Model
    -> ( String, Html Model.Msg )
usersTab toRootMsg vaultId state model =
    let
        -- converter from Html Msg -> Html Model.Msg
        rootMsg =
            Html.map toRootMsg

        searchKeys =
            Model.VaultDialogMsg vaultId <|
                SearchUserKeys (userInputEmail state)

        ownsVault =
            isOwner vaultId model

        infoText =
            t (VaultDialogText (UsersTabInfoText ownsVault)) model

        adminOnly maybeInfoText nodes =
            if ownsVault then
                div []
                    nodes
            else
                div []
                    [ text <|
                        Maybe.withDefault "" maybeInfoText
                    ]

        body =
            adminOnly Nothing
                [ div
                    [ classList [ ( "Hidden", not ownsVault ) ] ]
                    [ div
                        [ class "Add-User", onEnter searchKeys ]
                        [ Dialog.inputFor "User"
                            [ userInput vaultId state model ]
                        ]
                    , div [ class "UserKey-Selection" ]
                        [ rootMsg <| userKeySelection state model
                        , rootMsg <| confirmUserKeysButton state
                        ]
                    ]
                ]
    in
    ( t (VaultDialogText UsersTab) model
    , tabBody
        { infoBox = Just (InfoBoxText "Users" infoText)
        , vaultId = vaultId
        , state = state
        , body =
            [ body
            , adminOnly
                (Just <|
                    t (VaultDialogText YouDontHaveAccessToVaultUsers) model
                )
                [ rootMsg <| userList state model
                , rootMsg <| pendingUserList state
                ]
            ]
        }
    )


cryptoTab : VaultId -> State -> Model -> ( String, Html Model.Msg )
cryptoTab vaultId state model =
    let
        vault =
            Model.vaultWithId vaultId model

        cryptoInfoItem label tooltip body =
            div [ class "CryptoInfoItem" ]
                [ labeledItem [ class "InputLabel CryptoInfoItem-Label" ]
                    { side = Left
                    , onClick = Nothing
                    , label = text label
                    , item =
                        tooltipItem
                            { position = Top
                            , length = Medium
                            , text = tooltip
                            }
                            body
                    }
                ]

        vt vaultDialogText =
            t (VaultDialogText vaultDialogText) model
    in
    ( t (VaultDialogText CryptoTab) model
    , tabBody
        { infoBox = Just (InfoBoxText "Crypto" (vt CryptoTabInfoText))
        , vaultId = vaultId
        , state = state
        , body =
            [ div [ class "VaultMetadata" ]
                [ cryptoInfoItem (vt VaultIdLabel)
                    (vt VaultIdTooltip)
                    [ text (String.toUpper vault.remoteId) ]
                , cryptoInfoItem (vt FileRevisionsLabel)
                    (vt TotalNumberOfFileRevisionsTooltip)
                    [ text (toString vault.revisionCount) ]
                , cryptoInfoItem (vt LastModifiedLabel)
                    (vt LastModifiedTooltip)
                    [ text
                        (vault.modificationDate
                            |> Maybe.map (\date -> timeAgo date model)
                            |> Maybe.withDefault (vt NoChangesSoFar)
                        )
                    ]
                , cryptoInfoItem (vt KeyAlgorithmLabel)
                    (vt KeyAlgorithmTooltip)
                    [ text (String.toUpper vault.crypto.keyAlgorithm) ]
                , cryptoInfoItem (vt KeyFingerprintLabel)
                    (vt KeyFingerprintTooltip)
                    [ text
                        (vault.crypto.fingerprint
                            |> Maybe.map String.toUpper
                            |> Maybe.withDefault "N/A"
                        )
                    ]
                , cryptoInfoItem (vt TransferAlgorithmLabel)
                    (vt TransferAlgorithmTooltip)
                    [ text (String.toUpper vault.crypto.transferAlgorithm) ]
                , cryptoInfoItem (vt HashAlgorithmLabel)
                    (vt HashAlgorithmTooltip)
                    [ text (String.toUpper vault.crypto.hashAlgorithm) ]
                , cryptoInfoItem (vt AESKeyLengthLabel)
                    (vt AESKeyLengthTooltip)
                    [ text (toString vault.crypto.aesKeyLength) ]
                , cryptoInfoItem (vt RSAKeyLengthLabel)
                    (vt RSAKeyLengthTooltip)
                    [ text (toString vault.crypto.rsaKeyLength) ]
                , separator
                ]
            ]
        }
    )


filesTab :
    (Msg -> Model.Msg)
    -> VaultId
    -> State
    -> Model
    -> ( String, Html Model.Msg )
filesTab toRootMsg vaultId state model =
    ( t (VaultDialogText NameAndFilesTab) model
    , tabBody
        { infoBox = Nothing
        , vaultId = vaultId
        , state = state
        , body =
            [ Dialog.inputFor "Name"
                [ nameInput toRootMsg state model ]
            , Dialog.inputFor "Folder"
                [ Html.map toRootMsg <| openFolderButton vaultId state model ]
            , Dialog.inputFor "FileSelection"
                [ Html.map toRootMsg <| fileSelectionContainer state model ]
            ]
        }
    )


logTab : VaultId -> State -> Model -> ( String, Html Model.Msg )
logTab vaultId state model =
    ( t (VaultDialogText LogTab) model
    , tabBody
        { infoBox = Nothing
        , vaultId = vaultId
        , state = state
        , body =
            [ div [ class "EventFilters" ] <|
                [ Dialog.labeledItem [ class "InputLabel" ]
                    { side = Left
                    , onClick = Nothing
                    , label = text "Filters"
                    , item =
                        span []
                            (eventFilterButtons vaultId state)
                    }
                ]
            , div [ class "EventTableHeader" ]
                [ table [ class "EventTable" ] <|
                    [ th
                        [ class "Default-Cursor"
                        , onClick (Model.VaultDialogMsg vaultId ToggleEventSortOrder)
                        ]
                        [ text "Time" ]

                    -- , th []
                    --     [ text "User" ]
                    , th []
                        [ text "Operation" ]
                    , th []
                        [ text "Path / Message" ]
                    ]
                ]
            , div [ class "EventTableContent" ]
                [ table [ class "EventTable" ] <|
                    case VaultDialog.Model.events state of
                        [] ->
                            [ loadingSpinner ]

                        events ->
                            List.map (viewEvent model.now) events
                ]
            ]
        }
    )


adminTab : VaultId -> State -> Model -> ( String, Html Model.Msg )
adminTab vaultId state model =
    let
        adminActions =
            if state.cloneStatus == New || not (isOwner vaultId model) then
                []
            else
                [ infoText <| t (VaultDialogText VaultDeleteButtonInfo) model
                , deleteButton vaultId state model
                ]

        syncedActions =
            if state.cloneStatus /= Cloned then
                []
            else
                [ infoText (t (VaultDialogText VaultRemoveButtonInfo) model)
                , removeButton vaultId state model
                , separator
                ]

        infoBoxText =
            InfoBoxText "Admin" (t (VaultDialogText AdminTabInfoText) model)
    in
    ( t (VaultDialogText AdminTab) model
    , tabBody
        { infoBox = Just infoBoxText
        , vaultId = vaultId
        , state = state
        , body =
            [ div [ class "Admin-Buttons" ] <|
                syncedActions
                    ++ [ infoText (t (VaultDialogText VaultExportButtonInfo) model)
                       , exportButton <| Model.vaultWithId vaultId model
                       , separator
                       ]
                    ++ adminActions
            ]
        }
    )


eventFilterButtons : VaultId -> State -> List (Html Model.Msg)
eventFilterButtons vaultId state =
    let
        rootMsg msg =
            Model.VaultDialogMsg vaultId msg

        filterButton title filter =
            button
                [ classList
                    [ ( "Filter-Active"
                      , VaultDialog.Model.isFilterEnabled filter state
                      )
                    ]
                ]
                { label = title
                , onClick = rootMsg <| FilterEventsBy filter
                }

        logLevelButtons =
            [ filterButton "Debug" (Level Debug)
            , filterButton "Info" (Level Info)
            , filterButton "Warning" (Level Warning)
            , filterButton "Error" (Level Error)
            ]

        logLevelButton =
            button [ class "LogLevelMenuButton" ]
                { label = "Log Levels"
                , onClick = rootMsg ToggleViewLogLevelFilters
                }

        buttons =
            [ filterButton "History" IsHistoryItem
            , filterButton "Log" IsLogItem
            , span [ class "LogLevelButtons" ] <|
                if isFilterEnabled IsLogItem state then
                    []
                else
                    [ div [] <|
                        logLevelButton
                            :: (if state.viewLogLevelFilters then
                                    logLevelButtons
                                else
                                    []
                               )
                    ]
            ]
    in
    buttons


tabInfoText : String -> Html msg
tabInfoText infoText =
    div []
        [ div [ class "TabInfoText" ]
            [ text infoText ]
        , separator
        ]


viewEvent : Maybe Date -> Event -> Html msg
viewEvent now event =
    case event of
        Log item ->
            viewLogItem now item

        History item ->
            viewHistoryItem now item


type alias HasCreatedAt event =
    { event | createdAt : Maybe Date.Date }


eventDateString : Maybe Date -> HasCreatedAt a -> String
eventDateString now { createdAt } =
    case ( now, createdAt ) of
        ( Nothing, Just date ) ->
            fullDateString date

        ( Just nowDate, Just date ) ->
            let
                ( y1, m1, d1, _, _, _ ) =
                    dateParts nowDate

                ( y2, m2, d2, _, _, _ ) =
                    dateParts date
            in
            if y1 == y2 && m1 == m2 && d1 == d2 then
                shortDateString date
            else
                fullDateString date

        _ ->
            ""


viewLogItem : Maybe Date -> Data.Vault.LogItem -> Html msg
viewLogItem now item =
    tr [ class "HistoryItem" ]
        [ td []
            [ text <| eventDateString now item ]

        -- , td []
        --     []
        , td []
            [ text <| toString item.level ]
        , td []
            [ text item.message ]
        ]


viewHistoryItem : Maybe Date -> HistoryItem -> Html msg
viewHistoryItem now item =
    tr [ class "HistoryItem" ]
        [ td []
            [ text <| eventDateString now item ]

        -- , td []
        --     [ text item.email ]
        , td []
            [ text item.operation ]
        , td []
            [ text <| Util.shortenString 50 item.path ]
        ]


infoText : String -> Html msg
infoText infoText =
    div [ class "InfoText" ]
        [ text infoText ]


separator : Html msg
separator =
    Html.hr [ class "Separator" ]
        []


exportButton : Vault -> Html Model.Msg
exportButton vault =
    span
        [ class "Button-Export" ]
        [ button []
            { label = "Export vault key bundle"
            , onClick = Model.VaultDialogMsg vault.id OpenExportDialog
            }
        ]


cancelButton : VaultId -> State -> Model -> Html Model.Msg
cancelButton vaultId state model =
    span
        [ classList [ ( "Hidden", not state.hasChangesPending ) ] ]
        [ button []
            { label = t (VaultDialogText CancelChanges) model
            , onClick = Model.CloseVaultDetails vaultId
            }
        ]


deleteButton : VaultId -> State -> Model -> Html Model.Msg
deleteButton vaultId state model =
    span []
        [ button []
            { label = t (VaultDialogText DeleteFromServer) model
            , onClick =
                Model.VaultDialogMsg vaultId
                    (VaultDialog.Model.Confirm DeleteVault)
            }
        ]


removeButton : VaultId -> State -> Model -> Html Model.Msg
removeButton vaultId state model =
    span
        [ classList [ ( "Hidden", state.cloneStatus /= Cloned ) ] ]
        [ button []
            { label = t (VaultDialogText StopSyncing) model
            , onClick =
                Model.VaultDialogMsg vaultId
                    (VaultDialog.Model.Confirm RemoveVault)
            }
        ]


saveButton : VaultId -> State -> Model -> Html Model.Msg
saveButton vaultId state model =
    let
        ( label, msg ) =
            case ( state.cloneStatus, state.hasChangesPending ) of
                ( New, True ) ->
                    ( t (VaultDialogText CreateVault) model
                    , Model.SaveVaultDetails vaultId
                    )

                ( Cloned, True ) ->
                    ( t (VaultDialogText SaveVault) model
                    , Model.SaveVaultDetails vaultId
                    )

                ( NotCloned, True ) ->
                    ( t (VaultDialogText SyncVaultToFolder) model
                    , Model.CloneVault vaultId
                    )

                _ ->
                    ( t (VaultDialogText Close) model
                    , Model.CloseVaultDetails vaultId
                    )
    in
    button []
        { label = label
        , onClick = msg
        }


confirmUserKeysButton : State -> Html Msg
confirmUserKeysButton state =
    let
        email =
            userInputEmail state
    in
    if List.isEmpty (keysToAdd email state) then
        span []
            []
    else
        button []
            { label = "Invite with selected keys"
            , onClick = Confirmed AddUser
            }


openFolderButton : VaultId -> State -> Model -> Html Msg
openFolderButton vaultId state model =
    let
        pathString path =
            path
                |> Path.toString model.config.pathSeparator

        ( folderPath, msg, tooltipMsg ) =
            case ( state.cloneStatus, state.localFolderPath ) of
                ( NotCloned, Nothing ) ->
                    ( t (VaultDialogText <| FolderButtonLabel CloneIntoFolder)
                        model
                    , OpenFolderDialog
                    , t (VaultDialogText <| FolderButtonTooltip CloneIntoFolder)
                        model
                    )

                ( _, Nothing ) ->
                    ( t (VaultDialogText <| FolderButtonLabel SelectFolder)
                        model
                    , OpenFolderDialog
                    , t (VaultDialogText <| FolderButtonTooltip SelectFolder)
                        model
                    )

                ( New, Just path ) ->
                    let
                        ps =
                            pathString path
                    in
                    ( t
                        (VaultDialogText <|
                            FolderButtonLabel <|
                                FolderSelectedForSync ps
                        )
                        model
                    , OpenFolderDialog
                    , t
                        (VaultDialogText <|
                            FolderButtonTooltip <|
                                FolderSelectedForSync ps
                        )
                        model
                    )

                ( _, Just path ) ->
                    let
                        ps =
                            pathString path
                    in
                    ( t
                        (VaultDialogText <|
                            FolderButtonLabel <|
                                SyncedFolder ps
                        )
                        model
                    , OpenFolder ps
                    , t
                        (VaultDialogText <|
                            FolderButtonTooltip <|
                                SyncedFolder ps
                        )
                        model
                    )
    in
    span [ class "Button-Folder" ]
        [ labeledItem [ class "InputLabel" ]
            { side = Left
            , onClick = Nothing
            , label = text "Folder"
            , item =
                tooltipItem
                    { position = Right
                    , length = Small
                    , text = tooltipMsg
                    }
                    [ button []
                        { label =
                            if String.length folderPath > 33 then
                                String.left 10 folderPath
                                    ++ "..."
                                    ++ String.right 20 folderPath
                            else
                                folderPath
                        , onClick = msg
                        }
                    ]
            }
        ]


nameInput : (Msg -> Model.Msg) -> State -> HasLanguage a -> Html Model.Msg
nameInput msg state model =
    span [ onAnyKeyDown (msg NameChanged) ]
        [ labeledItem [ class "InputLabel" ]
            { side = Left
            , onClick = Just (Model.FocusOn state.nameInput.uid)
            , label = text "Name"
            , item =
                tooltipItem
                    { position = Right
                    , length = Small
                    , text = t (VaultDialogText VaultNameTooltip) model
                    }
                    [ Ui.Input.view state.nameInput
                        |> Html.map (msg << NameInputMsg)
                    ]
            }
        ]


iconInput : State -> Model -> Html Msg
iconInput state model =
    let
        iconPath =
            case state.icon of
                Nothing ->
                    ""

                Just path ->
                    path

        iconBaseAttrs =
            [ src (Maybe.withDefault "" state.icon)
            , class "Icon"
            ]

        iconAttrs =
            if isOwner state.id model then
                onClick OpenIconDialog :: iconBaseAttrs
            else
                iconBaseAttrs

        icon =
            img iconAttrs
                []
    in
    tooltipItem
        { position = Right
        , length = Auto
        , text = "Vault icon that can be seen by any invited user"
        }
        [ icon ]


userInput : VaultId -> State -> HasLanguage a -> Html Model.Msg
userInput vaultId state model =
    labeledItem [ class "InputLabel" ]
        { side = Left
        , onClick = Just (Model.FocusOn state.userInput.uid)
        , label = text <| t (VaultDialogText UserInputLabel) model
        , item =
            tooltipItem
                { position = Right
                , length = Medium
                , text = t (VaultDialogText UserInputTooltip) model
                }
                [ Ui.Input.view
                    state.userInput
                    |> Html.map (Model.VaultDialogMsg vaultId << UserInputMsg)
                ]
        }


fileSelectionContainer : State -> HasLanguage a -> Html Msg
fileSelectionContainer state model =
    let
        settings =
            { direction = "column"
            , compact = False
            , align = "start"
            }

        body =
            if hasFiles state then
                [ labeledItem [ class "InputLabel" ]
                    { side = Left
                    , onClick = Nothing
                    , label = text <| t (VaultDialogText FilesLabel) model
                    , item =
                        Ui.Container.view settings
                            []
                            [ tooltipItem
                                { position = Top
                                , length = Large
                                , text =
                                    t (VaultDialogText FileSelectionTooltip) model
                                }
                                (viewFolders state)
                            ]
                    }
                ]
            else
                []
    in
    div [ class "FileSelection" ]
        body


viewFolders : State -> List (Html Msg)
viewFolders state =
    case sortedFolders state of
        ( _, rootFileNames ) :: folders ->
            let
                rootFiles =
                    List.map (viewFile state []) rootFileNames

                rootFolders =
                    List.map (viewFolder state) folders
            in
            rootFiles ++ rootFolders

        [] ->
            []


viewFolder : State -> FolderItem -> Html Msg
viewFolder state ( path, files ) =
    let
        folderItem =
            span []
                [ span [ class "Folder" ] []
                , fileCheckbox path state
                , folderCollapseToggle path state
                ]
    in
    if isExpanded path state then
        div [ class "FolderItem" ] <|
            inFolderPath path
                [ folderItem
                , div (hiddenIfIgnored path state [])
                    [ div [ class "FolderItem-Nested" ]
                        (List.map (viewFile state path) files)
                    ]
                ]
    else
        div [ class "File FolderItem-Collapsed" ]
            (inFolderPath path
                [ folderItem ]
            )


viewFile : State -> Path -> FileName -> Html Msg
viewFile state folderPath path =
    let
        filePath =
            folderPath ++ [ path ]
    in
    div [ class "File" ]
        [ fileCheckbox filePath state ]


hiddenIfIgnored :
    Path
    -> State
    -> List (Html.Attribute msg)
    -> List (Html.Attribute msg)
hiddenIfIgnored path state attributes =
    if isIgnored path state then
        class "FolderItem-Hidden" :: attributes
    else
        attributes


inFolderPath : Path -> List (Html Msg) -> List (Html Msg)
inFolderPath path contents =
    case path of
        [] ->
            []

        [ p ] ->
            contents

        _ :: rest ->
            [ div [ class "FolderItem-Nested" ]
                (inFolderPath rest contents)
            ]


folderCollapseToggle : Path -> State -> Html Msg
folderCollapseToggle path state =
    if folderIsEmpty path state then
        text ""
    else if isExpanded path state then
        materialIcon "expand_less" [ onClick (CollapseFolder path) ]
    else
        materialIcon "expand_more" [ onClick (ExpandFolder path) ]


fileCheckbox : Path -> State -> Html Msg
fileCheckbox path state =
    let
        fileCheckboxSettings =
            { disabled = False
            , readonly = False
            , value = not (isIgnored path state)
            , uid = Path.name path
            }

        isActive =
            not <| isIgnored path state

        checkbox =
            span
                [ classList
                    [ ( "FileCheckbox", isActive )
                    , ( "FileCheckbox-Unchecked", not isActive )
                    ]
                , onClick (ToggleIgnorePath path)
                ]
                [ text "" ]

        checkboxWithLabel =
            labeledItem []
                { side = Right
                , onClick = Just (ToggleIgnorePath path)
                , label = text (Path.folderName path)
                , item = checkbox
                }
    in
    span [ class "Checkbox" ]
        [ checkboxWithLabel ]


userKeySelection : State -> Model -> Html Msg
userKeySelection state model =
    let
        email =
            userInputEmail state

        keys =
            userKeys email state
    in
    div [ class "UserKeys" ] <|
        (loadingSpinnerIf <| keys == Loading)
            :: List.map (\key -> userKeyCheckbox email key state model)
                (RemoteData.withDefault [] keys)


userKeyCheckbox : String -> UserKey -> State -> Model -> Html Msg
userKeyCheckbox email userKey state model =
    let
        isDisabled =
            isUserKeyAlreadyAdded userKey state

        checkboxViewSettings =
            { disabled = isDisabled
            , readonly = False
            , value = isUserKeySelected email userKey state
            , uid = userKey.fingerprint
            }

        labelMsg =
            if isDisabled then
                Nothing
            else
                Just (ToggleUserKey email userKey)

        checkbox =
            Ui.Checkbox.view checkboxViewSettings
                |> Html.map (UserKeyCheckbox email userKey)

        checkboxWithLabel =
            labeledItem []
                { side = Right
                , onClick = labelMsg
                , label = text (userKey.fingerprint ++ " - " ++ userKey.description)
                , item = checkbox
                }
    in
    div [ class "SelectKey", animation 0.5 Highlight ]
        [ span [ class "Checkbox" ] [ checkboxWithLabel ]
        , keyCreatedTimestamp userKey model
        ]


userList : State -> Model -> Html Msg
userList state model =
    div [ class "UserList" ] <|
        h4 [] [ text <| t (VaultDialogText VaultUsersLabel) model ]
            :: (case state.users of
                    Success users ->
                        List.map (\u -> userItem u state model) users

                    Loading ->
                        [ loadingSpinner ]

                    _ ->
                        []
               )


pendingUserList : State -> Html Msg
pendingUserList state =
    let
        hasPendingKeys email keys =
            keys
                |> List.isEmpty
                |> not

        pendingUsers =
            state.usersToAdd
                |> Dict.filter hasPendingKeys
                |> Dict.toList

        pendingUserItems =
            pendingUsers
                |> List.map (\( email, keys ) -> pendingUserItem email keys)
    in
    div [ class "PendingUserList" ] <|
        if List.isEmpty pendingUsers then
            []
        else
            h4 [] [ text "Pending Users:" ] :: pendingUserItems


userItem : User -> State -> Model -> Html Msg
userItem user state model =
    div
        [ classList
            [ ( "User", True )
            , ( "Normal-Cursor", not (isOwner state.id model) )
            ]
        , onClick (SetUserInput user.email)
        ]
        [ span [ class "UserName" ]
            [ text <| User.fullName user ]
        , span [ class "UserEmail" ]
            [ text <| " ( " ++ user.email ++ " )" ]
        , userAddedTimestamp user model
        ]


pendingUserItem : Email -> List UserKey -> Html Msg
pendingUserItem email keys =
    div [ class "User", onClick (SetUserInput email) ]
        [ span [ class "UserEmail" ]
            [ text email ]
        , span [ class "UserKeyFingerprints" ]
            [ text
                (keys
                    |> List.map .fingerprint
                    |> String.join ", "
                )
            ]
        ]


userAddedTimestamp : User -> Model -> Html msg
userAddedTimestamp user model =
    span [ class "UserAddedTime" ]
        [ text
            (user.accessGrantedAt
                |> Maybe.map (\date -> "Invited " ++ timeAgo date model)
                |> Maybe.withDefault "Vault Owner"
            )
        ]


keyCreatedTimestamp : UserKey -> Model -> Html msg
keyCreatedTimestamp key model =
    span [ class "UserKeyCreatedTime" ] <|
        case ( key.createdAt, model.now ) of
            ( Nothing, _ ) ->
                []

            ( Just date, Nothing ) ->
                [ text <| toString date ]

            ( Just date, Just now ) ->
                [ text <|
                    "Created "
                        ++ Date.Distance.inWords date now
                        ++ " ago"
                ]


type InfoBox
    = InfoBoxText TabId String


viewInfoBox : InfoBox -> VaultId -> State -> Html Model.Msg
viewInfoBox ((InfoBoxText tabId tabInfoText) as infoBox) vaultId state =
    span [ class "TabInfo" ]
        [ helpButton vaultId tabId state
        , div
            [ classList
                [ ( "InfoBox", True )
                , ( "InfoBox-Hidden", not <| isInfoBoxOpen tabId state )
                ]
            , onClick (Model.VaultDialogMsg vaultId (CloseInfoBox tabId))
            ]
            [ span []
                [ text tabInfoText ]
            ]
        ]


helpButton : VaultId -> TabId -> State -> Html Model.Msg
helpButton vaultId tabId state =
    span
        [ classList
            [ ( "InfoBoxButton", True )
            , ( "InfoBoxButton-Clicked", isInfoBoxOpen tabId state )
            ]
        , onClick <|
            Model.VaultDialogMsg vaultId (ToggleInfoBox tabId)
        ]
        []
