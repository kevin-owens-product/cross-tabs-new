module XB2.Share.Data.User exposing
    ( Feature(..)
    , LastPlatformUsed(..)
    , Plan(..)
    , User
    , decoder
    , encodeFeature
    , featureToString
    , planToString
    , toFeatureSet
    )

import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode exposing (Value)
import Maybe.Extra as Maybe
import Set.Any as AnySet exposing (AnySet)
import Time exposing (Posix)
import XB2.Share.Gwi.Json.Decode exposing (intToString)


type Plan
    = Free
    | FreeReports
    | Dashboards
    | Professional
    | Api
    | Student
    | ViewOnly
    | OpenAccessViewOnly
    | Plus
    | PlusEnterprise
    | Teams
    | AnotherPlan String


planDecoder : Decoder Plan
planDecoder =
    let
        fromString plan =
            case plan of
                "free" ->
                    Decode.succeed Free

                "free_reports" ->
                    Decode.succeed FreeReports

                "dashboards" ->
                    Decode.succeed Dashboards

                "professional" ->
                    Decode.succeed Professional

                "api" ->
                    Decode.succeed Api

                "student" ->
                    Decode.succeed Student

                "view_only" ->
                    Decode.succeed ViewOnly

                "open_access_view_only" ->
                    Decode.succeed OpenAccessViewOnly

                "plus" ->
                    Decode.succeed Plus

                "plus_enterprise" ->
                    Decode.succeed PlusEnterprise

                "teams" ->
                    Decode.succeed Teams

                anotherPlan ->
                    Decode.succeed (AnotherPlan anotherPlan)
    in
    Decode.andThen fromString Decode.string


type Feature
    = EmailExports
    | CanDowngrade
    | CanUseTV
    | TVForPlatform2
    | Curator
    | ExportBlocked
    | CanUseDebugButtons
    | CanUseXBFolders
    | XB50kTableLimit
    | XBSorting
    | XBForPlatform2
    | DashboardsForPlatform2
    | DashboardsGWICreator
    | DashboardsNonGWICreator
    | DashboardsOnly_NoAudiencesCharts
    | CanUseP1AfterSunset
    | CanShareOpenAccessDashboard
    | ViewOnlyFF
    | CrosstabsUnlocked
    | NewVerticalNavigationSidebar


{-| Needs to be the same as the name in Customer Features CRUD in Admin UI.
-}
featureToString : Feature -> String
featureToString feature =
    case feature of
        EmailExports ->
            "email_exports"

        CanDowngrade ->
            "can_downgrade"

        CanUseTV ->
            "tv_rf_user"

        TVForPlatform2 ->
            "TVRF 2.0 visible in pro-next"

        Curator ->
            "curator"

        ExportBlocked ->
            "export_blocked"

        CanUseDebugButtons ->
            "debug_buttons"

        CanUseXBFolders ->
            "xb_folders"

        XB50kTableLimit ->
            "XB 50k Table Limit (Product Only)"

        XBSorting ->
            "xb_sorting"

        XBForPlatform2 ->
            "xb_20_visible_in_pronext"

        DashboardsForPlatform2 ->
            "Dashboards 2.0 visible in pro-next"

        DashboardsGWICreator ->
            "Dashboards GWI creator (Product Only)"

        DashboardsNonGWICreator ->
            "Dashboards non-GWI creator (Product Only)"

        DashboardsOnly_NoAudiencesCharts ->
            "Dashboard Only (excl. Aud/Charts)"

        CanUseP1AfterSunset ->
            "P1 User After Sunset"

        CanShareOpenAccessDashboard ->
            "can_share_open_access_dashboard"

        ViewOnlyFF ->
            "view_only"

        CrosstabsUnlocked ->
            "crosstabs_locked"

        NewVerticalNavigationSidebar ->
            "p2_new_vertical_navigation_sidebar"


customerFeaturesDecoder : Decoder (List Feature)
customerFeaturesDecoder =
    let
        fromString feature =
            case feature of
                "email_exports" ->
                    Just EmailExports

                "can_downgrade" ->
                    Just CanDowngrade

                "tv_rf_user" ->
                    Just CanUseTV

                "TVRF 2.0 visible in pro-next" ->
                    Just TVForPlatform2

                "curator" ->
                    Just Curator

                "export_blocked" ->
                    Just ExportBlocked

                "debug_buttons" ->
                    Just CanUseDebugButtons

                "xb_folders" ->
                    Just CanUseXBFolders

                "XB 50k Table Limit (Product Only)" ->
                    Just XB50kTableLimit

                "xb_sorting" ->
                    Just XBSorting

                "xb_20_visible_in_pronext" ->
                    Just XBForPlatform2

                "Dashboards 2.0 visible in pro-next" ->
                    Just DashboardsForPlatform2

                "Dashboards GWI creator (Product Only)" ->
                    Just DashboardsGWICreator

                "Dashboards non-GWI creator (Product Only)" ->
                    Just DashboardsNonGWICreator

                "Dashboard Only (excl. Aud/Charts)" ->
                    Just DashboardsOnly_NoAudiencesCharts

                "P1 User After Sunset" ->
                    Just CanUseP1AfterSunset

                "can_share_open_access_dashboard" ->
                    Just CanShareOpenAccessDashboard

                "view_only" ->
                    Just ViewOnlyFF

                "crosstabs_unlocked" ->
                    Just CrosstabsUnlocked

                "p2_new_vertical_navigation_sidebar" ->
                    Just NewVerticalNavigationSidebar

                _ ->
                    Nothing
    in
    Decode.list (Decode.string |> Decode.map fromString)
        |> Decode.map Maybe.values


encodeFeature : Feature -> Value
encodeFeature =
    Encode.string << featureToString


type LastPlatformUsed
    = Platform1
    | Platform2


type alias User =
    { id : String -- TODO: wrap this inside an opaque type
    , email : String
    , firstName : String
    , lastName : String
    , organisationId : Maybe String
    , organisationName : Maybe String
    , country : Maybe String
    , city : Maybe String
    , jobTitle : Maybe String
    , planHandle : Plan
    , customerFeatures : AnySet String Feature
    , industry : Maybe String
    , sawOnboarding : Bool
    , lastPlatformUsed : LastPlatformUsed
    , accessStart : Posix
    }


toFeatureSet : List Feature -> AnySet String Feature
toFeatureSet =
    AnySet.fromList featureToString


platformVersionDecoder : Decoder LastPlatformUsed
platformVersionDecoder =
    let
        decode str =
            case str of
                "platform1" ->
                    Decode.succeed Platform1

                "platform2" ->
                    Decode.succeed Platform2

                unknownType ->
                    Decode.fail <| "Invalid platform type" ++ unknownType
    in
    Decode.nullable (Decode.andThen decode Decode.string)
        |> Decode.map (Maybe.withDefault Platform1)


decoder : Decoder User
decoder =
    Decode.succeed User
        |> Decode.andMap (Decode.field "id" intToString)
        |> Decode.andMap (Decode.field "email" Decode.string)
        |> Decode.andMap (Decode.field "first_name" Decode.string)
        |> Decode.andMap (Decode.field "last_name" Decode.string)
        |> Decode.andMap (Decode.field "organisation_id" (Decode.maybe intToString))
        |> Decode.andMap (Decode.field "organisation_name" (Decode.maybe Decode.string))
        |> Decode.andMap (Decode.field "country_name" (Decode.maybe Decode.string))
        |> Decode.andMap (Decode.field "city_name" (Decode.maybe Decode.string))
        |> Decode.andMap (Decode.field "job_title" (Decode.maybe Decode.string))
        |> Decode.andMap (Decode.field "plan_handle" planDecoder)
        |> Decode.andMap (Decode.map toFeatureSet (Decode.field "customer_features" customerFeaturesDecoder))
        |> Decode.andMap (Decode.field "industry" (Decode.maybe Decode.string))
        |> Decode.andMap (Decode.field "saw_onboarding" Decode.bool)
        |> Decode.andMap (Decode.field "last_platform_used" platformVersionDecoder)
        |> Decode.andMap (Decode.field "access_start" Iso8601.decoder)


{-| Beware: these values have to align with expected `plan_handle` values in
legacy Ember.
-}
planToString : Plan -> String
planToString plan =
    case plan of
        Free ->
            "free"

        FreeReports ->
            "free_reports"

        Dashboards ->
            "dashboards"

        Professional ->
            "professional"

        Api ->
            "api"

        Student ->
            "student"

        ViewOnly ->
            "view_only"

        OpenAccessViewOnly ->
            "open_access_view_only"

        Plus ->
            "plus"

        PlusEnterprise ->
            "plus_enterprise"

        Teams ->
            "teams"

        AnotherPlan anotherPlan ->
            anotherPlan
