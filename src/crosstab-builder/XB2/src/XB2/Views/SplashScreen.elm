module XB2.Views.SplashScreen exposing (Params, Triggers, getUpgradePlanUrlBasedOnUserPlan, view)

import Html
import Html.Attributes as Attrs
import Html.Attributes.Extra as Attrs
import Html.Events as Events
import Json.Decode as Decode
import XB2.Data.Zod.Optional as Optional
import XB2.Share.Data.User as User


type alias Params =
    { appName : String
    , email : String
    , upgradePlanUrl : Optional.Optional String
    }


type alias Triggers msg =
    { talkToAnExpert : msg
    , upgrade : msg
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


paramsToAttributes : Triggers msg -> Params -> List (Html.Attribute msg)
paramsToAttributes triggers params =
    [ Attrs.attribute "app-name" params.appName
    , Attrs.attribute "email" params.email
    , Attrs.attributeMaybe (Attrs.attribute "upgrade-plan-url") (Optional.toMaybe params.upgradePlanUrl)
    , Events.on "CrosstabBuilder-talkToAnExpertEvent" (Decode.succeed triggers.talkToAnExpert)
    , Events.on "CrosstabBuilder-upgradeEvent" (Decode.succeed triggers.upgrade)
    ]


view : Triggers msg -> Params -> Html.Html msg
view triggers params =
    Html.node "x-et-splash-screen"
        (paramsToAttributes triggers params)
        []
