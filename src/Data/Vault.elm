module Data.Vault
    exposing
        ( CryptoInfo
        , Event(..)
        , FlyingVault
        , HistoryItem
        , HistoryItems
        , LogItem
        , Metadata
        , NameOrId
        , Status(..)
        , Vault
        , VaultId
        , VaultOperation(..)
        , VaultOptions(..)
        , VaultSettings
        , addVaultUserEncoder
        , asVault
        , decoder
        , flyingVaultDecoder
        , historyItemDecoder
        , historyItemsDecoder
        , init
        , jsonOptions
        , logItemDecoder
        , logLevelDecoder
        , metadataEncoder
        , nameOrId
        , vaultSettingsJson
        , vaultStatusDecoder
        )

import Config exposing (Config)
import Data.User
    exposing
        ( Email
        , Fingerprint
        , UserKey
        )
import Date exposing (Date)
import Json.Decode as Json exposing (andThen, fail, succeed)
import Json.Decode.Pipeline
    exposing
        ( decode
        , optional
        , optionalAt
        , required
        )
import Json.Encode
import Path exposing (Path)
import Util exposing (LogLevel(..), dateDecoder)


type alias VaultId =
    String


{-| Record type with an id and optional name field.
-}
type alias NameOrId vault =
    { vault
        | name : Maybe String
        , id : VaultId
    }


{-| Vault status as returned from Daemon API.
-}
type Status
    = Uninitialized
    | Unsynced
    | Syncing
    | Initializing
    | Synced
    | Ready
    | Failed


type VaultOptions
    = Create
        { folder : Path
        , ignorePaths : List Path
        }
    | Import
        { folder : Path
        , vaultPackagePath : Path
        }
    | Clone
        { id : String
        , folder : Path
        , ignorePaths : List Path
        }
    | Remove VaultId
    | Delete VaultId


type alias Metadata =
    { name : String
    , icon : Maybe String
    }


type alias CryptoInfo =
    { aesKeyLength : Int
    , rsaKeyLength : Int
    , keyAlgorithm : String
    , transferAlgorithm : String
    , hashAlgorithm : String
    , fingerprint : Maybe Fingerprint
    }


type alias HistoryItems =
    { items : List HistoryItem }


type alias HistoryItem =
    { revisionId : String
    , createdAt : Maybe Date
    , operation : VaultOperation
    , path : Maybe String
    , email : String
    , fingerprint : Fingerprint
    , verified : Bool
    }


type UserId
    = Email String


type VaultOperation
    = CreateVault
    | SetMetadata
    | AddUser
    | RemoveUser
    | AddUserKey
    | RemoveUserKey
    | AddFile
    | DeleteFileRevision
    | RenameFile
    | RestoreFile
    | RemoveFile


type alias LogItem =
    { level : LogLevel
    , createdAt : Maybe Date
    , message : String
    , vaultId : VaultId
    }


type Event
    = History HistoryItem
    | Log LogItem


{-| Main vault type. Represents all vaults cloned & synced on current computer.
-}
type alias Vault =
    { id : VaultId
    , remoteId : VaultId
    , name : Maybe String
    , size : Int
    , status : Status
    , userCount : Int
    , fileCount : Int
    , revisionCount : Int
    , resourceUri : String
    , folderPath : String
    , modificationDate : Maybe Date
    , icon : Maybe String
    , crypto : CryptoInfo
    , ignore : List Path
    }


{-| Remote vaults that haven't been cloned or synced to this computer.
-}
type alias FlyingVault =
    { id : VaultId
    , remoteId : VaultId
    , name : Maybe String
    , size : Maybe Int
    , userCount : Int
    , fileCount : Int
    , revisionCount : Int
    , resourceUri : String
    , modificationDate : Maybe Date
    , icon : Maybe String
    }


init : VaultId -> Vault
init vaultId =
    { id = vaultId
    , remoteId = vaultId
    , name = Nothing
    , size = 0
    , status = Initializing
    , userCount = 0
    , fileCount = 0
    , revisionCount = 0
    , resourceUri = ""
    , folderPath = ""
    , modificationDate = Nothing
    , icon = Nothing
    , crypto =
        { aesKeyLength = 0
        , rsaKeyLength = 0
        , keyAlgorithm = ""
        , transferAlgorithm = ""
        , hashAlgorithm = ""
        , fingerprint = Nothing
        }
    , ignore = []
    }



-- This is pretty cool and will work with `Vault` & `FlyingVault` because both
-- Types have the correctly typed `name` and `id` fields.


nameOrId : NameOrId a -> String
nameOrId vault =
    vault.name
        |> Maybe.withDefault vault.id


asVault : FlyingVault -> Vault
asVault fv =
    let
        v =
            init fv.id
    in
    { v
        | id = fv.id
        , remoteId = fv.remoteId
        , name = fv.name
        , size = Maybe.withDefault 0 fv.size
        , status = Unsynced
        , userCount = fv.userCount
        , fileCount = fv.fileCount
        , revisionCount = fv.revisionCount
        , resourceUri = fv.resourceUri
        , folderPath = ""
        , modificationDate = fv.modificationDate
        , icon = fv.icon
    }


type alias VaultSettings =
    { folder : Maybe Path, ignorePaths : List Path }


vaultSettingsJson : Config -> VaultSettings -> Json.Encode.Value
vaultSettingsJson config settings =
    let
        ignorePaths =
            ( "ignore_paths"
            , Json.Encode.list <|
                List.map
                    (Json.Encode.string << pathString config)
                    settings.ignorePaths
            )

        props =
            case settings.folder of
                Nothing ->
                    [ ignorePaths ]

                Just folder ->
                    [ ( "folder", Json.Encode.string (pathString config folder) )
                    , ignorePaths
                    ]
    in
    Json.Encode.object props


pathString : Config -> Path -> String
pathString config path =
    String.join config.pathSeparator path


jsonOptions : Config -> VaultOptions -> Json.Encode.Value
jsonOptions config options =
    let
        ps path =
            pathString config path
    in
    case options of
        Create cfg ->
            vaultSettingsJson config
                { folder = Just <| cfg.folder
                , ignorePaths = cfg.ignorePaths
                }

        Import { folder, vaultPackagePath } ->
            Json.Encode.object
                [ ( "folder", Json.Encode.string (ps folder) )
                , ( "import_package", Json.Encode.string (ps vaultPackagePath) )
                ]

        Clone { id, folder } ->
            Json.Encode.object
                [ ( "id", Json.Encode.string id )
                , ( "folder", Json.Encode.string (ps folder) )
                ]

        Remove _ ->
            Json.Encode.null

        Delete _ ->
            Json.Encode.null


{-| Decodes a `Data.Vault.Vault`.
-}
decoder : Json.Decoder Vault
decoder =
    decode Vault
        |> required "id" Json.string
        |> optional "remote_id" Json.string "N/A"
        |> optionalMetadata "name" Json.string
        |> optional "size" Json.int 0
        |> required "state" vaultStatusDecoder
        |> optional "user_count" Json.int 1
        |> optional "file_count" Json.int 0
        |> optional "revision_count" Json.int 0
        |> required "resource_uri" Json.string
        |> required "folder" Json.string
        |> optional "modification_date" dateDecoder Nothing
        |> optionalMetadata "icon" Json.string
        |> required "crypt_info" cryptoInfoDecoder
        |> required "ignore_paths" (Json.list pathDecoder)


pathDecoder : Json.Decoder Path
pathDecoder =
    Json.string
        |> Json.map Path.asPath


optionalMetadata : String -> Json.Decoder a -> Json.Decoder (Maybe a -> b) -> Json.Decoder b
optionalMetadata propName propDecoder objDecoder =
    objDecoder
        |> optionalAt [ "metadata", propName ] (Json.maybe propDecoder) Nothing


cryptoInfoDecoder : Json.Decoder CryptoInfo
cryptoInfoDecoder =
    decode CryptoInfo
        |> required "aes_key_len" Json.int
        |> required "rsa_key_len" Json.int
        |> required "key_algo" Json.string
        |> required "transfer_algo" Json.string
        |> required "hash_algo" Json.string
        |> required "fingerprint" (Json.maybe Json.string)


historyItemsDecoder : Json.Decoder (List HistoryItem)
historyItemsDecoder =
    decode HistoryItems
        |> required "items" (Json.list historyItemDecoder)
        |> andThen (\{ items } -> Json.succeed items)


historyItemDecoder : Json.Decoder HistoryItem
historyItemDecoder =
    decode HistoryItem
        |> required "revision_id" Json.string
        |> required "created_at" dateDecoder
        |> required "operation" vaultOperationDecoder
        |> required "path" (Json.maybe Json.string)
        |> required "user_email" Json.string
        |> required "user_fingerprint" Json.string
        |> required "verified" Json.bool


vaultOperationDecoder : Json.Decoder VaultOperation
vaultOperationDecoder =
    let
        convert : String -> Json.Decoder VaultOperation
        convert op =
            case op of
                "OP_CREATE_VAULT" ->
                    succeed CreateVault

                "OP_SET_METADATA" ->
                    succeed SetMetadata

                "OP_ADD_USER" ->
                    succeed AddUser

                "OP_REMOVE_USER" ->
                    succeed RemoveUser

                "OP_ADD_USER_KEY" ->
                    succeed AddUserKey

                "OP_REMOVE_USER_KEY" ->
                    succeed RemoveUserKey

                "OP_UPLOAD" ->
                    succeed AddFile

                "OP_RENAME_FILE" ->
                    succeed RenameFile

                "OP_REMOVE_FILE" ->
                    succeed RemoveFile

                "OP_DELETE_FILE_REVISION" ->
                    succeed DeleteFileRevision

                "OP_RESTORE_FILE" ->
                    succeed RestoreFile

                val ->
                    fail <| "Unknown VaultOperation: " ++ val
    in
    Json.string
        |> Json.andThen convert


logLevelDecoder : Json.Decoder LogLevel
logLevelDecoder =
    let
        convert : String -> Json.Decoder LogLevel
        convert level =
            case String.toLower level of
                "debug" ->
                    succeed Debug

                "info" ->
                    succeed Info

                "warning" ->
                    succeed Warning

                "error" ->
                    succeed Error

                val ->
                    fail <| "Invalid log level: " ++ val
    in
    Json.string
        |> Json.andThen convert


logItemDecoder : Json.Decoder LogItem
logItemDecoder =
    decode LogItem
        |> required "level" logLevelDecoder
        |> required "created_at" dateDecoder
        |> required "message" Json.string
        |> required "vault_id" Json.string


{-| Decodes a `Data.Vault.FlyingVault`.
-}
flyingVaultDecoder : Json.Decoder FlyingVault
flyingVaultDecoder =
    decode FlyingVault
        |> required "id" Json.string
        |> required "remote_id" Json.string
        |> optionalAt [ "metadata", "name" ] (Json.maybe Json.string) Nothing
        |> optional "size" (Json.maybe Json.int) Nothing
        |> required "user_count" Json.int
        |> required "file_count" Json.int
        |> required "revision_count" Json.int
        |> required "resource_uri" Json.string
        |> optional "modification_date" dateDecoder Nothing
        |> optional "icon" (Json.maybe Json.string) Nothing


{-| Decodes a `Data.Vault.Status`.
-}
vaultStatusDecoder : Json.Decoder Status
vaultStatusDecoder =
    let
        convert : String -> Json.Decoder Status
        convert raw =
            case raw of
                "uninitialized" ->
                    succeed Uninitialized

                "unsynced" ->
                    succeed Unsynced

                "syncing" ->
                    succeed Syncing

                "initializing" ->
                    succeed Initializing

                "synced" ->
                    succeed Synced

                "ready" ->
                    succeed Ready

                "failure" ->
                    succeed Failed

                val ->
                    fail ("Invalid vault status: " ++ val)
    in
    Json.string |> andThen convert


metadataEncoder : Metadata -> Json.Encode.Value
metadataEncoder metadata =
    let
        metadataJson =
            case metadata.icon of
                Nothing ->
                    Json.Encode.object
                        [ ( "name", Json.Encode.string metadata.name ) ]

                Just iconUrl ->
                    Json.Encode.object
                        [ ( "name", Json.Encode.string metadata.name )
                        , ( "icon", Json.Encode.string iconUrl )
                        ]
    in
    Json.Encode.object [ ( "metadata", metadataJson ) ]


addVaultUserEncoder : Email -> List UserKey -> Json.Encode.Value
addVaultUserEncoder email keys =
    let
        fingerprints =
            List.map .fingerprint keys
    in
    Json.Encode.object
        [ ( "email", Json.Encode.string email )
        , ( "fingerprints"
          , Json.Encode.list <|
                List.map Json.Encode.string fingerprints
          )
        ]
