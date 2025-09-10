module XB2.Views.SplashScreen exposing (Params, getUpgradePlanUrlBasedOnUserPlan, view)

import Html
import Html.Attributes as Attrs
import Html.Attributes.Extra as Attrs
import XB2.Data.Zod.Optional as Optional
import XB2.Share.Data.User as User


type alias Params =
    { appName : String
    , email : String
    , upgradePlanUrl : Optional.Optional String
    }


getUpgradePlanUrlBasedOnUserPlan : User.Plan -> Optional.Optional String
getUpgradePlanUrlBasedOnUserPlan userPlan =
    case userPlan of
        User.Free ->
            Optional.Undefined

        User.FreeReports ->
            Optional.Undefined

        User.Dashboards ->
            Optional.Undefined

        User.Professional ->
            Optional.Undefined

        User.Api ->
            Optional.Undefined

        User.Student ->
            Optional.Undefined

        User.ViewOnly ->
            Optional.Undefined

        User.OpenAccessViewOnly ->
            Optional.Undefined

        User.Plus ->
            Optional.Undefined

        User.PlusEnterprise ->
            Optional.Undefined

        User.Teams ->
            Optional.Present "https://www.gwi.com/book-demo/upgrade"

        User.AnotherPlan _ ->
            Optional.Undefined


paramsToAttributes : Params -> List (Html.Attribute msg)
paramsToAttributes params =
    [ Attrs.attribute "app-name" params.appName
    , Attrs.attribute "email" params.email
    , Attrs.attributeMaybe (Attrs.attribute "upgrade-plan-url") (Optional.toMaybe params.upgradePlanUrl)
    ]


view : Params -> Html.Html msg
view params =
    Html.node "x-et-splash-screen"
        (paramsToAttributes params)
        []
