port module VaultDialog.Ports exposing (..)

import Path exposing (Path)
import VaultDialog.Model exposing (FolderItem)


type alias VaultId =
    String


port openFolderDialog : VaultId -> Cmd msg


port selectedFolder : (( VaultId, Path ) -> msg) -> Sub msg


port getFileList : ( VaultId, Path ) -> Cmd msg


port fileList : (( VaultId, Path, FolderItem ) -> msg) -> Sub msg


port openIconFileDialog : String -> Cmd msg


port selectedIconFile : (( String, String ) -> msg) -> Sub msg


port openExportFileDialog : ( String, String ) -> Cmd msg


port selectedExportFile : (( String, String ) -> msg) -> Sub msg
