module Dialog
    exposing
        ( LabeledItemSettings
        , WithModalState
        , asModalIn
        , errorMsg
        , input
        , inputFor
        , labeledItem
        )

import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Ui.Modal
import Util exposing (Position(..))


type alias WithModalState a =
    { a | modal : Ui.Modal.Model }


asModalIn : WithModalState a -> Ui.Modal.Model -> WithModalState a
asModalIn state modal =
    { state | modal = modal }


type alias LabeledItemSettings msg =
    { side : Position
    , onClick : Maybe msg
    , label : Html msg
    , item : Html msg
    }


labeledItem : List (Html.Attribute msg) -> LabeledItemSettings msg -> Html msg
labeledItem attributes settings =
    let
        className =
            "Dialog-Label-" ++ toString settings.side

        attrs =
            case settings.onClick of
                Nothing ->
                    class "Default-Cursor" :: attributes

                Just msg ->
                    onClick msg :: attributes

        labelContainer =
            div (class className :: attrs)
                [ settings.label ]
    in
    orderedLabeling { settings | label = labelContainer }


orderedLabeling : LabeledItemSettings msg -> Html msg
orderedLabeling { side, label, item } =
    let
        labelBody =
            case side of
                Top ->
                    [ label, item ]

                Bottom ->
                    [ item, label ]

                Left ->
                    [ label, item ]

                Right ->
                    [ item, label ]
    in
    span []
        labelBody


errorMsg : String -> Html msg
errorMsg msg =
    span [ class "ErrorMsg" ] [ text msg ]


inputFor : String -> List (Html msg) -> Html msg
inputFor inputClassSuffix body =
    div
        [ class "Input"
        , class ("Input-" ++ inputClassSuffix)
        ]
        body


input : Html msg -> Html msg
input body =
    div [ class "Input" ]
        [ body ]
