module XB2.Share.Permissions exposing
    ( Can
    , Permission(..)
    , fromUser
    )

-- modules

import Basics.Extra exposing (flip)
import Set.Any as AnySet
import XB2.Share.Data.User exposing (Feature(..), Plan(..), User)
import XB2.Share.Gwi.List as List


type Permission
    = CreateAudiences
    | SeeExtendedAudiences
    | AccessChartBuilder
    | AccessDashboards
    | AccessReports
    | AccessAudienceBuilder
    | CreateCuratedAudiences
    | CreateDashboards
    | ReceiveEmailExports
    | UseXB1
    | DowngradePlan
    | UseTV1
    | UseTV2
    | DownloadInfographics
    | DownloadReports
    | Export
    | SearchProducts
    | SearchQuestionsAndDatapoints
    | UseDebugButtons
    | UseXB50kTableLimit
    | UseXB2
    | UseDashboards2
    | SeeSupportChat
    | BeDashboardsGWICreator
    | BeDashboardsNonGWICreator
    | EditAudiencesAndChartsInDashboards2
    | UseP1AfterSunset
    | ShareOpenAccessDashboard
    | UseCrosstabs


type alias Can =
    Permission -> Bool


fromUser : User -> Can
fromUser { planHandle, customerFeatures } =
    let
        planBased =
            case planHandle of
                Free ->
                    [ AccessAudienceBuilder
                    , AccessChartBuilder
                    , AccessReports
                    , AccessDashboards
                    , CreateAudiences
                    , SearchProducts
                    , SearchQuestionsAndDatapoints
                    , SeeSupportChat
                    ]

                FreeReports ->
                    [ AccessAudienceBuilder
                    , AccessChartBuilder
                    , AccessReports
                    , AccessDashboards
                    , CreateAudiences
                    , SearchProducts
                    , SearchQuestionsAndDatapoints
                    , SeeSupportChat
                    ]

                Dashboards ->
                    [ AccessAudienceBuilder
                    , AccessDashboards
                    , AccessReports
                    , SeeExtendedAudiences
                    , SearchProducts
                    , SearchQuestionsAndDatapoints
                    , SeeSupportChat
                    ]

                Professional ->
                    [ AccessAudienceBuilder
                    , CreateAudiences
                    , SeeExtendedAudiences
                    , AccessChartBuilder
                    , AccessDashboards
                    , AccessReports
                    , UseXB1
                    , SearchProducts
                    , SearchQuestionsAndDatapoints
                    , SeeSupportChat
                    ]

                Api ->
                    [ CreateAudiences
                    , SearchProducts
                    , SearchQuestionsAndDatapoints
                    , SeeSupportChat
                    ]

                Student ->
                    [ AccessReports
                    , SearchProducts
                    ]

                ViewOnly ->
                    [ AccessAudienceBuilder
                    , AccessChartBuilder
                    , AccessReports
                    , AccessDashboards
                    , SeeSupportChat
                    ]

                OpenAccessViewOnly ->
                    [ AccessDashboards ]

                Plus ->
                    []

                PlusEnterprise ->
                    []

                Teams ->
                    []

                AnotherPlan _ ->
                    []

        canExport =
            not <| AnySet.member ExportBlocked customerFeatures

        canUseCrosstabs : Bool
        canUseCrosstabs =
            case
                ( AnySet.member CrosstabsUnlocked customerFeatures
                , AnySet.member NewVerticalNavigationSidebar customerFeatures
                )
            of
                ( True, True ) ->
                    -- If both are there then the user can use crosstabs
                    True

                ( True, False ) ->
                    -- If for some reason only crosstabs_unlocked is there but not new sidebar then the user can use crosstabs
                    True

                ( False, True ) ->
                    -- If we have the new sidebar but not crosstabs_unlocked the user can't use crosstabs
                    False

                ( False, False ) ->
                    -- If none is present then the user can use crosstabs
                    True
    in
    planBased
        |> List.addIf
            (AnySet.member CanShareOpenAccessDashboard customerFeatures)
            ShareOpenAccessDashboard
        |> List.addIf (AnySet.member Curator customerFeatures) CreateDashboards
        |> List.addIf (AnySet.member Curator customerFeatures) CreateCuratedAudiences
        |> List.addIf (AnySet.member EmailExports customerFeatures) ReceiveEmailExports
        |> List.addIf (AnySet.member CanUseTV customerFeatures) UseTV1
        |> List.addIf (AnySet.member TVForPlatform2 customerFeatures) UseTV2
        |> List.addIf (AnySet.member CanDowngrade customerFeatures) DowngradePlan
        |> List.addIf (planHandle /= Free && planHandle /= Api && canExport) DownloadInfographics
        |> List.addIf (planHandle /= Free && planHandle /= Api && canExport) DownloadReports
        |> List.addIf canExport Export
        |> List.addIf (AnySet.member CanUseDebugButtons customerFeatures) UseDebugButtons
        |> List.addIf (AnySet.member XB50kTableLimit customerFeatures) UseXB50kTableLimit
        |> List.addIf (planHandle == Professional && AnySet.member XBForPlatform2 customerFeatures) UseXB2
        |> List.addIf (AnySet.member DashboardsForPlatform2 customerFeatures) UseDashboards2
        |> List.addIf (AnySet.member DashboardsGWICreator customerFeatures) BeDashboardsGWICreator
        |> List.addIf (AnySet.member DashboardsNonGWICreator customerFeatures) BeDashboardsNonGWICreator
        |> List.addIf (AnySet.member CanUseP1AfterSunset customerFeatures) UseP1AfterSunset
        |> List.addIf canUseCrosstabs UseCrosstabs
        |> List.addIf (not (planHandle == Dashboards && AnySet.member DashboardsOnly_NoAudiencesCharts customerFeatures)) EditAudiencesAndChartsInDashboards2
        |> AnySet.fromList toString
        |> flip AnySet.member


toString : Permission -> String
toString permission =
    case permission of
        CreateAudiences ->
            "CreateAudiences"

        SeeExtendedAudiences ->
            "SeeExtendedAudiences"

        AccessChartBuilder ->
            "AccessChartBuilder"

        AccessDashboards ->
            "AccessDashboards"

        AccessReports ->
            "AccessReports"

        AccessAudienceBuilder ->
            "AccessAudienceBuilder"

        CreateCuratedAudiences ->
            "CreateCuratedAudiences"

        CreateDashboards ->
            "CreateDashboards"

        ReceiveEmailExports ->
            "ReceiveEmailExports"

        UseXB1 ->
            "UseQueryBuilder"

        DowngradePlan ->
            "DowngradePlan"

        UseTV1 ->
            "UseTV1"

        UseTV2 ->
            "UseTV2"

        DownloadInfographics ->
            "DownloadInfographics"

        DownloadReports ->
            "DownloadReports"

        Export ->
            "Export"

        SearchProducts ->
            "SearchProducts"

        SearchQuestionsAndDatapoints ->
            "SearchQuestionsAndDatapoints"

        UseDebugButtons ->
            "UseDebugButtons"

        UseXB50kTableLimit ->
            "UseXB50kTableLimit"

        UseXB2 ->
            "UseXB2"

        UseDashboards2 ->
            "UseDashboards2"

        SeeSupportChat ->
            "SeeSupportChat"

        BeDashboardsGWICreator ->
            "BeDashboardsGWICreator"

        BeDashboardsNonGWICreator ->
            "BeDashboardsNonGWICreator"

        EditAudiencesAndChartsInDashboards2 ->
            "EditAudiencesAndChartsInDashboards2"

        UseP1AfterSunset ->
            "UseP1AfterSunset"

        ShareOpenAccessDashboard ->
            "ShareOpenAccessDashboard"

        UseCrosstabs ->
            "UseCrosstabs"
