module Dialog exposing (WithModalState, asModalIn, labeledItem)

import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Ui.Modal
import Util exposing (Direction(..))


type alias WithModalState a =
    { a | modal : Ui.Modal.Model }


asModalIn : WithModalState a -> Ui.Modal.Model -> WithModalState a
asModalIn state modal =
    { state | modal = modal }


labeledItem : Direction -> List (Html.Attribute msg) -> Maybe msg -> Html msg -> Html msg -> Html msg
labeledItem side attributes onClickMsg labelContent content =
    let
        className =
            case side of
                Top ->
                    "Dialog-Label-Top"

                Bottom ->
                    "Dialog-Label-Bottom"

                Left ->
                    "Dialog-Label-Left"

                Right ->
                    "Dialog-Label-Right"

        attrs =
            case onClickMsg of
                Nothing ->
                    (class "Default-Cursor") :: attributes

                Just msg ->
                    (onClick msg) :: attributes

        label =
            span (class className :: attrs)
                [ labelContent ]
    in
        orderedLabeling side label content


orderedLabeling side label content =
    let
        labelBody =
            case side of
                Top ->
                    [ label, content ]

                Bottom ->
                    [ content, label ]

                Left ->
                    [ label, content ]

                Right ->
                    [ content, label ]
    in
        span []
            labelBody
