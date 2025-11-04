module XB2.Detail.Common exposing
    ( Dropdown(..)
    , TableWarning(..)
    , Unsaved(..)
    , basePanelTabElementId
    , basesPanelId
    , basesPanelScrollableId
    , cornerCellId
    , crosstabSearchId
    , datasetCodesFromNamespaceCodes
    , defaultLocations
    , directionToString
    , filteredMetrics
    , fromAudience
    , getAudienceFolders
    , getDatasetCodesFromProject
    , moduleClass
    , scrollTableId
    , tableCellsElementId
    , tableElementId
    , tableMetricsTotalRowId
    )

import AssocSet
import Basics.Extra exposing (flip)
import Dict.Any
import Html exposing (Html)
import Maybe.Extra as Maybe
import Random
import RemoteData
import WeakCss exposing (ClassName)
import XB2.Data as XBData exposing (XBProjectId)
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Folder as AudienceFolder
import XB2.Data.AudienceCrosstab exposing (Direction(..))
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.Calc.AudienceIntersect exposing (XBQueryError)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Dataset as Dataset
import XB2.Data.Metric exposing (Metric)
import XB2.Data.Namespace as Namespace
import XB2.Data.Zod.Nullable as Nullable
import XB2.Share.Data.Id exposing (IdDict, IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        )
import XB2.Share.Data.Platform2
import XB2.Share.Gwi.Http exposing (Error)
import XB2.Share.Platform2.Dropdown.DropdownMenu as DropdownMenu
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store
import XB2.Store as XBStore


type Dropdown msg
    = ViewOptionsDropdown
    | SortByNameDropdown
    | BulkFreezeDropdown
    | AllBasesDropdown
    | FixedPageDropdown (DropdownMenu.DropdownMenu msg)


cornerCellId : String
cornerCellId =
    "xb-id-table-corner-cell"


scrollTableId : String
scrollTableId =
    "xb-id-table-scroll"


tableElementId : String
tableElementId =
    "xb-id-table-element"


tableCellsElementId : String
tableCellsElementId =
    "xb-id-table-cells-container-element"


tableMetricsTotalRowId : String
tableMetricsTotalRowId =
    "xb-table-totals-row-metrics"


basesPanelId : String
basesPanelId =
    "xb2-bases-panel-container-id"


basesPanelScrollableId : String
basesPanelScrollableId =
    "xb2-bases-panel-scrollable-id"


basePanelTabElementId : Int -> String
basePanelTabElementId index =
    "xb2-bases-panel-tab-" ++ String.fromInt index


directionToString : Direction -> String
directionToString direction =
    case direction of
        Row ->
            "row"

        Column ->
            "column"


crosstabSearchId : String
crosstabSearchId =
    "xb2-crosstab-search-id"


moduleClass : ClassName
moduleClass =
    WeakCss.namespace "xb2"


getAudienceFolders : XB2.Share.Store.Platform2.Store -> Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder
getAudienceFolders =
    .audienceFolders
        >> RemoteData.withDefault (Dict.Any.empty AudienceFolder.idToString)


{-| @TODO: This defaults to size expression. Not sure if that's correct...
-}
fromAudience : Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder -> Audience.Audience -> Random.Seed -> ( AudienceItem, Random.Seed )
fromAudience audienceFolders ({ expression } as audience) seed =
    AudienceItem.fromCaptionExpression
        seed
        (labelFromAudience audienceFolders audience)
        expression


labelFromAudience : Dict.Any.AnyDict AudienceFolder.StringifiedId AudienceFolder.Id AudienceFolder.Folder -> Audience.Audience -> Caption
labelFromAudience folders audience =
    Caption.fromAudience
        { audience = audience.name
        , parent =
            case audience.folderId of
                Nullable.Present folderId_ ->
                    folders
                        |> Dict.Any.get folderId_
                        |> Maybe.map .name

                Nullable.Null ->
                    Just (Audience.toTypeString audience)
        }


defaultLocations : IdDict LocationCodeTag Location -> IdSet LocationCodeTag
defaultLocations locations =
    XB2.Share.Data.Id.setFromList <| Dict.Any.keys locations


{-| Preserves the intended order of metrics
-}
filteredMetrics : AssocSet.Set Metric -> List Metric
filteredMetrics activeMetrics =
    List.filter
        (flip AssocSet.member activeMetrics)
        XBData.defaultMetrics


type Unsaved
    = Unsaved
    | Saved XBProjectId
    | Edited XBProjectId
    | UnsavedEdited


type TableWarning msg
    = GenericTableWarning { count : Int, content : Html msg, additionalNotice : Maybe (Html msg) }
    | CellXBQueryError (Error XBQueryError)


datasetCodesFromNamespaceCodes : XB2.Share.Store.Platform2.Store -> List Namespace.Code -> List Dataset.Code
datasetCodesFromNamespaceCodes store namespaceCodes =
    store.datasetsToNamespaces
        |> RemoteData.map
            (\datasetsToNamespaces ->
                namespaceCodes
                    |> Maybe.traverse
                        (XB2.Share.Data.Platform2.deepestNamespaceCode store.datasets
                            store.datasetsToNamespaces
                            store.lineages
                        )
                    |> Maybe.andThen
                        (XB2.Share.Data.Platform2.datasetCodesForNamespaceCodes datasetsToNamespaces store.lineages
                            >> RemoteData.toMaybe
                        )
            )
        |> RemoteData.unwrap [] (Maybe.withDefault [])


getDatasetCodesFromProject : XBStore.Store -> Maybe XBProjectId -> List Namespace.Code
getDatasetCodesFromProject xbStore maybeProjectId =
    maybeProjectId
        |> Maybe.andThen (Store.get xbStore.xbProjects)
        |> Maybe.andThen (.data >> RemoteData.toMaybe)
        |> Maybe.unwrap [] XBData.projectDataNamespaceCodes
