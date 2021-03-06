module Daemon
    exposing
        ( ApiPath(..)
        , ApiStreamPath(..)
        , addVaultUser
        , attemptDelayed
        , createNewVaultInFolder
        , deleteVault
        , exportUserKey
        , exportVault
        , getConfig
        , getFlyingVault
        , getFlyingVaults
        , getLoginState
        , getStats
        , getUser
        , getUserKeys
        , getVault
        , getVaultFingerprints
        , getVaultHistory
        , getVaultUser
        , getVaultUsers
        , getVaults
        , getVersion
        , importVault
        , invalidateFirstLaunch
        , login
        , loginCheck
        , logout
        , removeVault
        , removeVaultUser
        , resyncVault
        , sendFeedback
        , subscribeDaemonLogStream
        , subscribeVaultHistoryStream
        , subscribeVaultLogStream
        , updateGUIConfig
        , updateVaultMetadata
        , updateVaultSettings
        , updateVaults
        )

import Config exposing (Config)
import Data.Daemon exposing (GUIConfig, daemonConfigDecoder)
import Data.User exposing (Email, Fingerprint, Password, User, UserKey)
import Data.Vault exposing (..)
import Http
import Json.Decode as Json exposing (succeed)
import Json.Decode.Pipeline
    exposing
        ( decode
        , required
        )
import Json.Encode
import Model exposing (..)
import Path
import RemoteData exposing (RemoteData(..), WebData)
import Task exposing (Task)
import Time exposing (Time)
import Util
import WebSocket


type ApiPath
    = Stats
    | Vaults
    | FlyingVaults
    | Vault VaultId
    | DeleteVault VaultId
    | ExportVault VaultId
    | FlyingVault VaultId
    | VaultUsers VaultId
    | VaultUser VaultId Email
    | UserKeys Email
    | VaultFingerprints VaultId
    | VaultHistory VaultId
    | ResyncVault VaultId
    | Stream ApiStreamPath
    | User
    | DaemonConfig
    | Feedback
    | Version
    | Login
    | LoginCheck
    | Logout
    | ExportUserKey


type ApiStreamPath
    = VaultLogStream VaultId
    | VaultHistoryStream VaultId
    | DaemonLogStream


getStats : Model -> Cmd Msg
getStats { config } =
    config
        |> apiRequest
            Get
            Stats
            EmptyBody
            statsDecoder
        |> Cmd.map UpdatedStatsFromApi


getVaults : Model -> Cmd Msg
getVaults { config } =
    config
        |> apiRequest
            Get
            Vaults
            EmptyBody
            (Json.list Data.Vault.decoder)
        |> Cmd.map UpdatedVaultsFromApi


getFlyingVaults : Model -> Cmd Msg
getFlyingVaults { config } =
    config
        |> apiRequest
            Get
            FlyingVaults
            EmptyBody
            (Json.list Data.Vault.flyingVaultDecoder)
        |> Cmd.map UpdatedFlyingVaultsFromApi


getVault : VaultId -> Model -> Cmd (WebData Vault)
getVault vaultId { config } =
    config
        |> apiRequest
            Get
            (Vault vaultId)
            EmptyBody
            Data.Vault.decoder


getFlyingVault : VaultId -> Model -> Cmd (WebData FlyingVault)
getFlyingVault vaultId { config } =
    config
        |> apiRequest
            Get
            (FlyingVault vaultId)
            EmptyBody
            Data.Vault.flyingVaultDecoder


updateVaultMetadata : VaultId -> Metadata -> Model -> Cmd Msg
updateVaultMetadata vaultId metadata { config } =
    config
        |> apiRequest
            Put
            (Vault vaultId)
            (Json <| Data.Vault.metadataEncoder metadata)
            Data.Vault.decoder
        |> Cmd.map (Model.VaultMetadataUpdated vaultId)


getVaultUsers : VaultId -> Model -> Cmd (WebData (List User))
getVaultUsers vaultId { config } =
    config
        |> apiRequest
            Get
            (VaultUsers vaultId)
            EmptyBody
            (Json.list Data.User.decoder)


getVaultHistory : VaultId -> Model -> Cmd (WebData (List HistoryItem))
getVaultHistory vaultId { config } =
    config
        |> apiRequest
            Get
            (VaultHistory vaultId)
            EmptyBody
            Data.Vault.historyItemsDecoder


subscribeVaultLogStream :
    VaultId
    -> (Result String Data.Vault.LogItem -> msg)
    -> Model
    -> Sub msg
subscribeVaultLogStream vaultId toMsg { config } =
    let
        parseMsg : String -> msg
        parseMsg json =
            toMsg <| Json.decodeString logItemDecoder json

        url =
            Stream (VaultLogStream vaultId)
                |> apiPath
                |> apiWSUrl config
    in
    WebSocket.listen url parseMsg


subscribeVaultHistoryStream :
    VaultId
    -> (Result String Data.Vault.HistoryItem -> msg)
    -> Model
    -> Sub msg
subscribeVaultHistoryStream vaultId toMsg { config } =
    let
        parseMsg : String -> msg
        parseMsg json =
            toMsg <| Json.decodeString historyItemDecoder json

        url =
            Stream (VaultHistoryStream vaultId)
                |> apiPath
                |> apiWSUrl config
    in
    WebSocket.listen url parseMsg


subscribeDaemonLogStream :
    (Result String Data.Daemon.LogItem -> msg)
    -> Model
    -> Sub msg
subscribeDaemonLogStream toMsg { config } =
    let
        parseMsg : String -> msg
        parseMsg json =
            toMsg <| Json.decodeString Data.Daemon.logItemDecoder json

        url =
            Stream DaemonLogStream
                |> apiPath
                |> apiWSUrl config
    in
    WebSocket.listen url parseMsg


getVaultUser : VaultId -> Email -> Model -> Cmd (WebData User)
getVaultUser vaultId email { config } =
    config
        |> apiRequest
            Get
            (VaultUser vaultId email)
            EmptyBody
            Data.User.decoder


addVaultUser : VaultId -> Email -> List UserKey -> Model -> Cmd Msg
addVaultUser vaultId email keys { config } =
    config
        |> apiRequest
            Post
            (VaultUsers vaultId)
            (Json <| Data.Vault.addVaultUserEncoder email keys)
            (decode identity |> required "email" Json.string)
        |> Cmd.map (Model.VaultUserAdded vaultId email)


removeVaultUser : VaultId -> Email -> Model -> Cmd (WebData Email)
removeVaultUser vaultId email { config } =
    -- TODO: check response data type
    config
        |> apiRequest
            Delete
            (VaultUser vaultId email)
            EmptyBody
            Json.string


getUserKeys : Email -> Model -> Cmd (WebData (List UserKey))
getUserKeys email { config } =
    config
        |> apiRequest
            Get
            (UserKeys email)
            EmptyBody
            (Json.list Data.User.keyDecoder)


getUser : Email -> Model -> Cmd (WebData User)
getUser email { config } =
    config
        |> apiRequest
            Get
            User
            EmptyBody
            Data.User.decoder


getConfig : Model -> Cmd Msg
getConfig { config } =
    config
        |> apiRequest
            Get
            DaemonConfig
            EmptyBody
            daemonConfigDecoder
        |> Cmd.map UpdatedDaemonConfig


invalidateFirstLaunch : Model -> Cmd Msg
invalidateFirstLaunch { config } =
    let
        json =
            Json.Encode.object
                [ ( "gui"
                  , Json.Encode.object
                        [ ( "is_first_launch", Json.Encode.bool False )
                        ]
                  )
                ]
    in
    config
        |> apiRequest
            Patch
            DaemonConfig
            (Json json)
            daemonConfigDecoder
        |> Cmd.map UpdatedDaemonConfig


updateGUIConfig :
    Model
    -> GUIConfig
    -> Cmd Msg
updateGUIConfig { config } { isFirstLaunch, language } =
    let
        json =
            Json.Encode.object
                [ ( "gui"
                  , Json.Encode.object
                        [ ( "is_first_launch"
                          , Json.Encode.bool isFirstLaunch
                          )
                        , ( "language"
                          , Json.Encode.string <| toString language
                          )
                        ]
                  )
                ]
    in
    config
        |> apiRequest
            Patch
            DaemonConfig
            (Json json)
            daemonConfigDecoder
        |> Cmd.map UpdatedDaemonConfig


getVaultFingerprints : VaultId -> Model -> Cmd (WebData (List Fingerprint))
getVaultFingerprints vaultId { config } =
    config
        |> apiRequest
            Get
            (VaultFingerprints vaultId)
            EmptyBody
            (Json.list Json.string)


updateVaultSettings : VaultId -> VaultSettings -> Model -> Cmd (WebData Vault)
updateVaultSettings vaultId settings { config } =
    config
        |> apiRequest
            Put
            (Vault vaultId)
            (Json <| vaultSettingsJson config settings)
            Data.Vault.decoder


updateVaults : VaultOptions -> Model -> Cmd (WebData Vault)
updateVaults options { config } =
    config
        |> apiRequest
            Post
            Vaults
            (Json <| jsonOptions config options)
            Data.Vault.decoder


createNewVaultInFolder : Path.Path -> List Path.Path -> Model -> Cmd (WebData Vault)
createNewVaultInFolder folderPath ignorePaths model =
    updateVaults
        (Data.Vault.Create
            { folder = folderPath
            , ignorePaths = ignorePaths
            }
        )
        model


removeVault : VaultId -> Model -> Cmd Msg
removeVault vaultId { config } =
    let
        json =
            Data.Vault.Remove vaultId
                |> jsonOptions config
    in
    config
        |> apiRequest
            Delete
            (Vault vaultId)
            (Json json)
            (succeed vaultId)
        |> Cmd.map RemovedVaultFromSync


resyncVault : VaultId -> Model -> Cmd Msg
resyncVault vaultId { config } =
    config
        |> apiRequest
            Get
            (ResyncVault vaultId)
            EmptyBody
            (succeed vaultId)
        |> Cmd.map ResyncingVault


deleteVault : VaultId -> Model -> Cmd (WebData VaultId)
deleteVault vaultId { config } =
    config
        |> apiRequest
            Delete
            (DeleteVault vaultId)
            EmptyBody
            (succeed vaultId)


importVault : Path.Path -> Path.Path -> Model -> Cmd (WebData Vault)
importVault folderPath vaultPackagePath model =
    updateVaults
        (Data.Vault.Import
            { folder = folderPath
            , vaultPackagePath = vaultPackagePath
            }
        )
        model


sendFeedback : String -> Model -> Cmd Msg
sendFeedback text { config } =
    config
        |> apiRequest
            Post
            Feedback
            (Json <|
                Json.Encode.object
                    [ ( "feedback_text", Json.Encode.string text ) ]
            )
            (succeed "Ok")
        |> Cmd.map SentFeedback


getVersion : Model -> Cmd (WebData String)
getVersion { config } =
    config
        |> apiRequest
            Get
            Version
            EmptyBody
            Json.string


getLoginState : Model -> Cmd Msg
getLoginState { config } =
    config
        |> apiRequest
            Get
            User
            EmptyBody
            loginStateDecoder
        |> Cmd.map UpdatedLoginState


login : Email -> Password -> Model -> Cmd Msg
login email password { config } =
    config
        |> apiRequest
            Post
            Login
            (Json <| Data.User.loginEncoder email password)
            statusResponseDecoder
        |> Cmd.map (LoginResult email)


loginCheck : Model -> Cmd (WebData String)
loginCheck { config } =
    config
        |> apiRequest
            Get
            LoginCheck
            EmptyBody
            Json.string


logout : Model -> Cmd Msg
logout { config } =
    config
        |> apiRequest
            Get
            Logout
            EmptyBody
            statusResponseDecoder
        |> Cmd.map LogoutResult


exportVault : VaultId -> String -> Model -> Cmd Msg
exportVault vaultId path { config } =
    let
        json =
            Json.Encode.object [ ( "path", Json.Encode.string path ) ]
    in
    config
        |> apiRequest
            Post
            (ExportVault vaultId)
            (Json json)
            exportStatusResponseDecoder
        |> Cmd.map (ExportedVault vaultId)


exportUserKey : Path.Path -> Model -> Cmd Msg
exportUserKey path { config } =
    let
        pathString =
            Path.toString config.pathSeparator path

        json =
            Json.Encode.object [ ( "path", Json.Encode.string pathString ) ]
    in
    config
        |> apiRequest
            Post
            ExportUserKey
            (Json json)
            exportStatusResponseDecoder
        |> Cmd.map ExportedUserKey


type alias Url =
    String


type RequestMethod
    = Get
    | Put
    | Post
    | Patch
    | Delete


{-| Converts `ApiPath` into `Path` (`String`).

    apiPath Vaults  -- -> "vaults"
    apiPath (Vault "foobaruuid") -- -> "vaults/foobaruuid"

-}
apiPath : ApiPath -> String
apiPath apiPath =
    case apiPath of
        Stats ->
            "stats"

        Vaults ->
            "vault"

        FlyingVaults ->
            "flying-vault"

        Vault vaultId ->
            "vault/" ++ vaultId

        DeleteVault vaultId ->
            "vault/" ++ vaultId ++ "?wipe=1"

        ExportVault vaultId ->
            "vault/" ++ vaultId ++ "/export"

        FlyingVault vaultId ->
            "flying-vault/" ++ vaultId

        VaultUsers vaultId ->
            "vault/" ++ vaultId ++ "/users"

        VaultUser vaultId email ->
            "vault/" ++ vaultId ++ "/users/" ++ email

        VaultFingerprints vaultId ->
            "vault/" ++ vaultId ++ "/fingerprints"

        VaultHistory vaultId ->
            "vault/" ++ vaultId ++ "/history/"

        ResyncVault vaultId ->
            "vault/" ++ vaultId ++ "/resync/"

        Stream DaemonLogStream ->
            "/logstream"

        Stream (VaultLogStream vaultId) ->
            "vault/" ++ vaultId ++ "/logstream"

        Stream (VaultHistoryStream vaultId) ->
            "vault/" ++ vaultId ++ "/historystream"

        UserKeys email ->
            "user/" ++ email ++ "/keys"

        User ->
            "auth/user"

        DaemonConfig ->
            "config"

        Feedback ->
            "feedback"

        Version ->
            "version"

        Login ->
            "auth/login"

        LoginCheck ->
            "auth/check"

        Logout ->
            "auth/logout"

        ExportUserKey ->
            "identity/export"


{-| Converts `RequestMethod` into `String`.

    requestMethod Get  -- -> "GET"
    requestMethod Post -- -> "POST"

-}
requestMethod : RequestMethod -> String
requestMethod rm =
    case rm of
        Get ->
            "GET"

        Put ->
            "PUT"

        Post ->
            "POST"

        Patch ->
            "PATCH"

        Delete ->
            "DELETE"


type ApiRequestBody
    = Json Json.Encode.Value
    | Body Http.Body
    | EmptyBody


{-| Creates an syncrypt daemon API compatible `Http.Request`.

    let
        config = {apiUrl = "http://localhost:28080/", apiAuthToken="123"}
    in
        apiRequest config Get "vault" (Json.list Data.Vault.decoder)

-}
apiRequest :
    RequestMethod
    -> ApiPath
    -> ApiRequestBody
    -> Json.Decoder a
    -> Config
    -> Cmd (WebData a)
apiRequest method path body decoder config =
    Http.request
        { method = requestMethod method
        , headers = apiHeaders config
        , url = apiUrl config (apiPath path)
        , body = apiRequestBody body
        , expect = Http.expectJson decoder
        , timeout = Nothing
        , withCredentials = False
        }
        |> RemoteData.sendRequest


apiRequestBody : ApiRequestBody -> Http.Body
apiRequestBody requestBody =
    case requestBody of
        Json json ->
            Http.jsonBody json

        Body body ->
            body

        EmptyBody ->
            Http.emptyBody


{-| Create a `Task.Task` from an api request (`Http.Request`)
-}
task : Http.Request a -> Task Http.Error a
task =
    Http.toTask


attemptDelayed : Time -> (Result Http.Error a -> Msg) -> Http.Request a -> Cmd Msg
attemptDelayed time msg request =
    request
        |> task
        |> Util.attemptDelayed time msg


rootUrl : Config -> String -> String
rootUrl config path =
    case ( String.endsWith "/" config.apiUrl, String.startsWith "/" path ) of
        ( True, False ) ->
            config.apiUrl

        ( True, True ) ->
            String.dropRight 1 config.apiUrl

        ( False, True ) ->
            config.apiUrl

        ( False, False ) ->
            config.apiUrl ++ "/"


{-| Returns the api url for a given `Config` and `Path`.

    let
        config = {apiUrl = "http://localhost:28080/", apiAuthToken="123"}
    in
        apiUrl config "foo"  -- -> "http://localhost:28080/foo/"
        apiUrl config "/bar" -- -> "http://localhost:28080/bar/"

-}
apiUrl : Config -> String -> Url
apiUrl config path =
    let
        hasQuery =
            String.contains "?"
    in
    -- the daemon API expects requests URLs to end with "/"
    -- e.g. /v1/vault/ or /v1/vault/id/ and not /v1/vault or /v1/vault/id
    if String.endsWith "/" path || hasQuery path then
        rootUrl config path ++ path
    else
        rootUrl config path ++ path ++ "/"


apiWSUrl : Config -> String -> Url
apiWSUrl config path =
    let
        wsUrl =
            case String.split "://" (apiUrl config path) of
                [ _, url ] ->
                    url

                _ ->
                    path
    in
    "ws://" ++ wsUrl


{-| Returns the required `Http.Header`s required by the daemon JSON API.
-}
apiHeaders : Config -> List Http.Header
apiHeaders config =
    [ Http.header "X-Authtoken" config.apiAuthToken ]
