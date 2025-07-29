module XB2.Views.SplashScreen exposing (Params, view)

import Html
import Html.Attributes as Attrs


type alias Params =
    { appName : String
    , email : String
    }


paramsToAttributes : Params -> List (Html.Attribute msg)
paramsToAttributes params =
    [ Attrs.attribute "app-name" params.appName
    , Attrs.attribute "email" params.email
    ]


view : Params -> Html.Html msg
view params =
    Html.node "x-et-splash-screen"
        (paramsToAttributes params)
        []
