module Model exposing (..)

import Syncrypt.Vault exposing (Vault, FlyingVault)
import Config exposing (Config)
import Http


type alias Model =
    { config : Config
    , vaults : List Vault
    , flyingVaults : List FlyingVault
    , state : State
    , stats : { stats : Int, downloads : Int, uploads : Int }
    , sidebarOpen : Bool
    }


type State
    = LoadingVaults
    | UpdatingVaults (List Vault)
    | ShowingAllVaults
    | ShowingVaultDetails Vault
    | ShowingFlyingVaultDetails FlyingVault


type Msg
    = UpdateVaults
    | UpdateFlyingVaults
    | UpdatedVaultsFromApi (Result Http.Error (List Vault))
    | UpdatedFlyingVaultsFromApi (Result Http.Error (List FlyingVault))
    | OpenVaultDetails Vault
    | OpenVaultFolder Vault
    | OpenFlyingVaultDetails FlyingVault
    | CloseVaultDetails
    | OpenProgramSettings
    | OpenAccountSettings
    | RemoveVaultFromSync Vault
    | Logout
