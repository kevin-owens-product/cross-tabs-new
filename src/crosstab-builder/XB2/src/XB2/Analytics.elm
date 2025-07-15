module XB2.Analytics exposing
    ( AddedHow(..)
    , AffixedFrom(..)
    , BaseOrderingChangeMethod(..)
    , Counts
    , Destination(..)
    , Event(..)
    , EventParams
    , ExportData
    , FrozenItem(..)
    , ItemSelected(..)
    , MergingMethodType(..)
    , OpenAttributeBrowserFor(..)
    , ProjectEventParams
    , RespondentNumberType(..)
    , UnsavedProjectEventParams
    , prepareBaseForTracking
    , trackEvent
    , trackEvents
    )

import AssocSet
import Iso8601
import Json.Encode as Encode exposing (Value)
import List.Extra as List
import List.NonEmpty as NonemptyList
import Maybe.Extra as Maybe
import RemoteData
import String.Extra as String
import XB2.Data as XBData
    exposing
        ( AudienceDefinition
        , XBProject
        , XBProjectFullyLoaded
        )
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression
import XB2.Data.AudienceCrosstab exposing (CrosstabTable, Direction(..))
import XB2.Data.AudienceCrosstab.Sort as XBSort
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId exposing (AudienceItemId)
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect exposing (XBQueryError)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Metric as Metric exposing (Metric(..))
import XB2.Data.MetricsTransposition exposing (MetricsTransposition, metricAnalyticsName)
import XB2.Data.UndoEvent as UndoEvent exposing (UndoEvent)
import XB2.Data.Zod.Optional as Optional
import XB2.Detail.Common as Common exposing (Unsaved(..))
import XB2.Router exposing (Route(..))
import XB2.Share.Analytics
import XB2.Share.Analytics.Common
    exposing
        ( commaSeparated
        , list
        , regionsFromLocations
        , yearsFromWaves
        )
import XB2.Share.Analytics.Place as Place exposing (Place)
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id
import XB2.Share.Data.Labels
    exposing
        ( Location
        , NamespaceAndQuestionCode
        , QuestionAndDatapointCode
        , QuestionV2
        , Wave
        )
import XB2.Share.Gwi.Http exposing (Error)
import XB2.Share.Platform2.Grouping exposing (Grouping(..))
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils
import XB2.Sort as Sort
import XB2.Views.AttributeBrowser as AttributeBrowser


type alias EventParams extraParams =
    { crosstab : CrosstabTable
    , waves : List Wave
    , locations : List Location
    , bases : List BaseAudience
    , extraParams : extraParams
    }


type Destination
    = CrosstabRow
    | CrosstabColumn
    | CrosstabRowAndColumn
    | CrosstabBase


type AddedHow
    = AddedByAppend
    | AddedAsNew


type OpenAttributeBrowserFor
    = OpenForTable
    | OpenForBase


type AffixedFrom
    = BulkBar
    | AddAttributeButton
    | FromDropDownMenu
    | NotTracked


type ItemSelected
    = TickBox


type alias ExportData =
    { rowCount : Int
    , colCount : Int
    , audiences : List AudienceItem
    , locations : List XB2.Share.Data.Labels.Location
    , waves : List XB2.Share.Data.Labels.Wave
    , metricsTransposition : MetricsTransposition
    , xbBases : List BaseAudience
    , heatmapMetric : Maybe Metric
    , store : XB2.Share.Store.Platform2.Store
    , maybeProject : Maybe XBData.XBProjectFullyLoaded
    , isSaved : Common.Unsaved
    }


type alias ProjectEventParams extra =
    { extra
        | project : XBProjectFullyLoaded
        , store : XB2.Share.Store.Platform2.Store
    }


type alias UnsavedProjectEventParams extra =
    { extra
        | project : XBProject
        , store : XB2.Share.Store.Platform2.Store
    }


type alias Counts =
    { audiencesCount : Int
    , questionsCount : Int
    , datapointsCount : Int
    , averagesCount : Int
    }


type Event
    = LimitReachedAddingRowOrColumn (EventParams { direction : Direction })
    | LimitReachedAddingBase (EventParams {})
    | Flipped (EventParams {})
    | LocationsChanged (EventParams {})
    | WavesChanged (EventParams {})
    | MetricsViewToggled
        { newState : MetricsTransposition
        , rowCount : Int
        , colCount : Int
        , cellCount : Int
        }
    | BaseAudienceApplied (EventParams { place : Place })
    | BaseSelected
        { appliedBases : List BaseAudience
        , selectedBases : List BaseAudience
        , questionCodes : List NamespaceAndQuestionCode
        , datapointCodes : List QuestionAndDatapointCode
        }
    | ItemMoved
        (EventParams
            { movedFrom : Destination
            , movedTo : Destination
            }
        )
    | ItemsDeleted
        (EventParams
            { deletedRows : Int
            , deletedColumns : Int
            }
        )
    | ItemAdded
        { destination : Destination
        , addedHow : AddedHow
        , itemType : String
        , audienceId : Maybe Audience.Id
        , cellsCount : Int
        , questions : List QuestionV2
        , datapointCodes : List QuestionAndDatapointCode
        , itemLabel : String
        , datasetNames : List String
        }
    | AverageAdded
        { destination : Destination
        , addedHow : AddedHow
        , cellsCount : Int
        , average : AttributeBrowser.Average
        , datasetNames : List String
        }
    | BasesDeleted (EventParams { basesCount : Int })
    | RowsColsDeletionModalOpened (EventParams {})
    | BasesDeletionModalOpened (EventParams {})
    | GroupAddedAsNew
        (EventParams
            { destination : Destination
            , groupingOperator : Grouping
            , appendedCount : Int
            , counts : Counts
            , datasetNames : List String
            }
        )
    | GroupDuplicated
        (EventParams
            { caption : Caption
            , expression : AudienceDefinition
            }
        )
    | GroupAddedByAffixToBase
        (EventParams
            { groupingOperator : Grouping
            , newExpression : Expression.Expression
            , counts : Counts
            , datasetNames : List String
            }
        )
    | BasesEdited
        (EventParams
            { newExpression : Expression.Expression
            , counts : Counts
            , datasetNames : List String
            }
        )
    | GroupsAddedByAffixToTable
        (EventParams
            { destination : Destination
            , appendedCount : Int
            , appendingOperator : Expression.LogicOperator
            , groupingOperator : Grouping
            , counts : Counts
            , affixedFrom : AffixedFrom
            , datasetNames : List String
            }
        )
    | GroupsAddedByEditToTable
        (EventParams
            { destination : Destination
            , editedCount : Int
            , groupingOperator : Grouping
            , counts : Counts
            , datasetNames : List String
            }
        )
    | ProjectSaved (ProjectEventParams { newlyCreated : Bool, questions : List QuestionV2 })
    | ProjectDuplicated (ProjectEventParams { originalProject : XBProjectFullyLoaded })
    | ProjectDeleted (ProjectEventParams {})
    | HeaderCollapsed (EventParams { isHeaderCollapsed : Bool })
    | ProjectCreationStarted
    | ProjectRenamed (ProjectEventParams {})
    | ProjectOpened (ProjectEventParams {})
    | UnsavedProjectOpened (UnsavedProjectEventParams {})
    | ProjectShared (ProjectEventParams { questions : List QuestionV2 })
    | Export ExportData
    | GroupRenamed
        (EventParams
            { oldName : String
            , newName : String
            , datapointsCount : Maybe Int -- Nothing in case of Avg row/col
            }
        )
    | KnowledgeBaseOpened String String
    | HeatmapApplied (EventParams { metric : Metric })
    | MetricsChosen (EventParams { metrics : AssocSet.Set Metric })
    | UndoApplied (EventParams { undoEvent : UndoEvent })
    | RedoApplied (EventParams { undoEvent : UndoEvent })
    | ItemSelectedInTable
        { datapointCodes : List QuestionAndDatapointCode
        , questionCodes : List NamespaceAndQuestionCode
        , captions : List Caption
        , direction : Direction
        , itemSelected : ItemSelected
        }
    | ItemSelectedInTableWithShift
        { datapointCodes : List QuestionAndDatapointCode
        , questionCodes : List NamespaceAndQuestionCode
        , captions : List Caption
        , direction : Direction
        }
    | AllItemsSelectedInTable { selectedItemsCount : Int }
    | ItemAddedAsABase (EventParams { rowsColsSelected : Int })
    | AudienceSaved
        (EventParams
            { id : AudienceItemId
            , caption : Caption

            {- AverageItem has a avg-enabled Definition instead, but this event
               doesn't make sense with Avg...
            -}
            , expression : Expression.Expression
            }
        )
    | TableFullyLoaded
        (EventParams
            { loadTime : Int
            , afterLoadAction : String
            }
        )
    | TableSorted (EventParams { sortConfig : XBSort.SortConfig })
    | UselessCheckboxClicked (EventParams {})
    | AverageUnitChanged (EventParams {})
    | OpenAttributeBrowser OpenAttributeBrowserFor
      -- List folders
    | FolderCreated { folder : XBData.XBFolder, projects : List XBData.XBProject }
    | MoveProjectsTo { folderName : String, movingOut : Bool, projects : List XBData.XBProject }
    | FolderDeleted { folder : XBData.XBFolder, projects : List XBData.XBProject }
    | UngroupedFolder { folder : XBData.XBFolder, projects : List XBData.XBProject }
    | NAIntersection (EventParams { queryError : Error XBQueryError, retryCount : Int })
    | HeaderResized
        (EventParams
            { expanded : Bool
            , wasResizingColumns : Bool
            , maxCharCount : Int
            , avgCharCount : Int
            }
        )
    | WarningClicked
        (EventParams
            { row : AudienceDefinition
            , column : AudienceDefinition
            , numOfWarnings : Int
            }
        )
    | ProjectOpenedAfterExportFromListView (ProjectEventParams {})
    | ListSorted { sorting : String }
    | TabsClicked { tab : String }
    | ManagementPageDragAndDropUsed
    | ManagementPageOpened { splashScreen : Bool }
    | AffixAttributesOrAudiences AffixedFrom
    | CopyLink { projectId : XBData.XBProjectId, projectName : String }
    | RespondentNumberChanged
        (EventParams
            { respondentNumberType :
                RespondentNumberType
            }
        )
    | UniverseNumberChanged
        (EventParams
            { respondentNumberType :
                RespondentNumberType
            }
        )
    | RowsOrColumnsMerged
        (EventParams
            { mergedHow :
                MergingMethodType
            }
        )
    | BaseOrderChanged
        (EventParams
            { changedHow : BaseOrderingChangeMethod
            }
        )
    | CellsFrozen
        (EventParams
            { item : FrozenItem
            , howMany : Int
            }
        )
    | MinimumSampleSizeChanged
        (EventParams
            { minimumSampleSize : Optional.Optional Int
            }
        )
    | UndoClickedInAttrBrowser
    | RedoClickedInAttrBrowser



-- Freezing Rows & Cols analytics


type FrozenItem
    = FrozenRow
    | FrozenColumn


frozenItemToString : FrozenItem -> String
frozenItemToString frozenItem =
    case frozenItem of
        FrozenRow ->
            "row"

        FrozenColumn ->
            "column"


minimumSampleSizeToString : Optional.Optional Int -> String
minimumSampleSizeToString maybeSize =
    case maybeSize of
        Optional.Present size ->
            String.fromInt size

        Optional.Undefined ->
            "n/a"


type RespondentNumberType
    = Exact
    | Rounded


type MergingMethodType
    = AsNew
    | Merged


type BaseOrderingChangeMethod
    = DragAndDrop
    | Menu
    | Keyboard


placeAttr : Place -> ( String, Value )
placeAttr place =
    ( "place", Place.encode place )


encodeAddedHow : AddedHow -> Encode.Value
encodeAddedHow how =
    Encode.string <|
        case how of
            AddedByAppend ->
                "append"

            AddedAsNew ->
                "new"


encodeDestination : Destination -> Encode.Value
encodeDestination destination =
    Encode.string <|
        case destination of
            CrosstabRow ->
                "rows"

            CrosstabColumn ->
                "columns"

            CrosstabRowAndColumn ->
                "both"

            CrosstabBase ->
                "base"


encodeSectionFromDestination : Destination -> Encode.Value
encodeSectionFromDestination destination =
    Encode.string <|
        case destination of
            CrosstabRow ->
                "table"

            CrosstabColumn ->
                "table"

            CrosstabRowAndColumn ->
                "table"

            CrosstabBase ->
                "table"


encodeGrouping : Grouping -> Encode.Value
encodeGrouping g =
    Encode.string <|
        case g of
            Split ->
                "split"

            And ->
                "and"

            Or ->
                "or"


encodeBaseAudienceCaption : BaseAudience -> Encode.Value
encodeBaseAudienceCaption audience =
    audience
        |> BaseAudience.getCaption
        |> Caption.toString
        |> Encode.string


encodeLogicOperator : Expression.LogicOperator -> Encode.Value
encodeLogicOperator op =
    Encode.string <|
        case op of
            Expression.And ->
                "and"

            Expression.Or ->
                "or"


encodeRootLogicOperator : Expression.Expression -> Encode.Value
encodeRootLogicOperator expr =
    case expr of
        Expression.FirstLevelNode operator _ ->
            encodeLogicOperator operator

        _ ->
            Encode.string "n/a"


{-| Essentially, tracking the _default_ base audience in a special way.
-}
prepareBaseForTracking : BaseAudience -> BaseAudience
prepareBaseForTracking baseAudience =
    if BaseAudience.isDefault baseAudience then
        baseAudience
            |> BaseAudience.setCaption
                (Caption.fromAudience
                    { audience = "Default"
                    , parent = Nothing
                    }
                )

    else
        baseAudience


sharedEventParameters : EventParams a -> List ( String, Encode.Value )
sharedEventParameters { waves, locations, crosstab, bases } =
    let
        regions : List String
        regions =
            regionsFromLocations locations

        years : List String
        years =
            yearsFromWaves waves
    in
    [ ( "rows_count", Encode.int <| Crosstab.rowCount crosstab )
    , ( "cols_count", Encode.int <| Crosstab.colCount crosstab )
    , ( "cells_count", Encode.int <| Crosstab.size crosstab )
    , ( "waves_count", Encode.int <| List.length waves )
    , ( "waves", commaSeparated .name waves )
    , ( "waves_list", list .name waves )
    , ( "locations_count", Encode.int <| List.length locations )
    , ( "locations", commaSeparated .name locations )
    , ( "locations_list", list .name locations )
    , ( "years_count", Encode.int <| List.length years )
    , ( "years", commaSeparated identity years )
    , ( "years_list", list identity years )
    , ( "regions_count", Encode.int <| List.length regions )
    , ( "regions", commaSeparated identity regions )
    , ( "regions_list", list identity regions )
    , ( "bases", Encode.list encodeBaseAudienceCaption bases )
    , ( "base_n", Encode.int (List.length bases) )
    ]


sharedProjectEventParams : Flags -> Place -> XBProjectFullyLoaded -> XB2.Share.Store.Platform2.Store -> List ( String, Encode.Value )
sharedProjectEventParams flags place project store =
    let
        locations =
            XB2.Share.Store.Utils.getByIds store.locations project.data.locationCodes

        waves =
            XB2.Share.Store.Utils.getByIds store.waves project.data.waveCodes

        regions : List String
        regions =
            regionsFromLocations locations

        years : List String
        years =
            yearsFromWaves waves

        rowCount =
            List.length project.data.rows

        colCount =
            List.length project.data.columns

        baseEncode base =
            Encode.string (base.name ++ " " ++ base.subtitle)
    in
    encodeShared project.data.ownerId project.shared
        ++ [ ( "project_name", Encode.string project.name )
           , ( "crosstab_id", XB2.Share.Data.Id.encode project.id )
           , ( "project_created_date", Encode.string <| Iso8601.fromTime project.createdAt )
           , placeAttr place
           , ( "rows_count", Encode.int rowCount )
           , ( "cols_count", Encode.int colCount )
           , ( "cells_count", Encode.int <| rowCount * colCount )
           , ( "waves_count", Encode.int <| List.length waves )
           , ( "waves", commaSeparated .name waves )
           , ( "waves_list", list .name waves )
           , ( "locations_count", Encode.int <| List.length locations )
           , ( "locations", commaSeparated .name locations )
           , ( "locations_list", list .name locations )
           , ( "years_count", Encode.int <| List.length years )
           , ( "years", commaSeparated identity years )
           , ( "years_list", list identity years )
           , ( "regions_count", Encode.int <| List.length regions )
           , ( "regions", commaSeparated identity regions )
           , ( "regions_list", list identity regions )
           , ( "bases", NonemptyList.encodeList baseEncode project.data.bases )
           , ( "message", Encode.bool <| not <| String.isEmpty project.sharingNote )
           , ( "message_length", Encode.int <| String.length project.sharingNote )
           , ( "is_owner", Encode.bool <| project.data.ownerId == flags.user.id )
           ]


unsavedProjectEventParams : Flags -> Place -> XBProject -> XB2.Share.Store.Platform2.Store -> List ( String, Encode.Value )
unsavedProjectEventParams flags place project store =
    (project.data
        |> RemoteData.map
            (\data ->
                let
                    locations =
                        XB2.Share.Store.Utils.getByIds store.locations data.locationCodes

                    waves =
                        XB2.Share.Store.Utils.getByIds store.waves data.waveCodes

                    regions : List String
                    regions =
                        regionsFromLocations locations

                    years : List String
                    years =
                        yearsFromWaves waves

                    rowCount =
                        List.length data.rows

                    colCount =
                        List.length data.columns

                    baseEncode base =
                        Encode.string (base.name ++ " " ++ base.subtitle)

                    isOwner : Bool
                    isOwner =
                        RemoteData.unwrap False (.ownerId >> (==) flags.user.id) project.data
                in
                encodeShared data.ownerId project.shared
                    ++ [ ( "bases", NonemptyList.encodeList baseEncode data.bases )
                       , ( "waves_count", Encode.int <| List.length waves )
                       , ( "waves", commaSeparated .name waves )
                       , ( "waves_list", list .name waves )
                       , ( "locations_count", Encode.int <| List.length locations )
                       , ( "locations", commaSeparated .name locations )
                       , ( "locations_list", list .name locations )
                       , ( "years_count", Encode.int <| List.length years )
                       , ( "years", commaSeparated identity years )
                       , ( "years_list", list identity years )
                       , ( "rows_count", Encode.int rowCount )
                       , ( "cols_count", Encode.int colCount )
                       , ( "cells_count", Encode.int <| rowCount * colCount )
                       , ( "regions_count", Encode.int <| List.length regions )
                       , ( "regions", commaSeparated identity regions )
                       , ( "regions_list", list identity regions )
                       , ( "is_owner", Encode.bool isOwner )
                       ]
            )
        |> RemoteData.withDefault []
    )
        ++ [ ( "project_name", Encode.string "new" )
           , ( "crosstab_id", Encode.string "N/A" )
           , ( "project_created_date", Encode.string "N/A" )
           , ( "message", Encode.bool False )
           , ( "message_length", Encode.int 0 )
           , placeAttr place
           ]


getNameFromItem : AudienceItem -> String
getNameFromItem =
    Caption.getName << AudienceItem.getCaption


trackEvent : Flags -> Route -> Place -> Event -> Cmd msg
trackEvent flags route place event =
    XB2.Share.Analytics.track <| encodeEvent flags route place event


trackEvents : Flags -> Route -> Place -> List Event -> Cmd msg
trackEvents flags route place events =
    XB2.Share.Analytics.batch_ (encodeEvent flags route place) events


encodeShared : String -> XBData.Shared -> List ( String, Value )
encodeShared ownerId shared =
    let
        currentOwner =
            ( "owner", Encode.string ownerId )
    in
    case shared of
        XBData.MyPrivateCrosstab ->
            [ currentOwner
            , ( "shared_with", Encode.string "n/a" )
            , ( "shared", Encode.bool False )
            ]

        XBData.SharedBy { id } _ ->
            [ ( "owner", Encode.string id )
            , ( "shared", Encode.bool True )
            ]

        XBData.MySharedCrosstab sharees ->
            let
                ( orgs, users ) =
                    sharees
                        |> NonemptyList.partition XBData.isOrgSharee

                getShareeId : XBData.Sharee -> String
                getShareeId sharee =
                    case sharee of
                        XBData.UserSharee { id } ->
                            id

                        XBData.OrgSharee orgId ->
                            XB2.Share.Data.Id.unwrap orgId
            in
            [ currentOwner
            , ( "shared_with_userID", users |> Encode.list (Encode.string << getShareeId) )
            , ( "shared_with_orgID", orgs |> Encode.list (Encode.string << getShareeId) )
            , ( "shared", Encode.bool True )
            ]

        XBData.SharedByLink ->
            [ currentOwner
            , ( "shared_with", Encode.string "n/a" )
            , ( "shared", Encode.bool True )
            ]


encodeAttributeBrowserOpenType : OpenAttributeBrowserFor -> ( String, Value )
encodeAttributeBrowserOpenType target =
    let
        openType =
            case target of
                OpenForTable ->
                    "table"

                OpenForBase ->
                    "base"
    in
    ( "type", Encode.string openType )


encodeSortConfig : XBSort.SortConfig -> List ( String, Value )
encodeSortConfig sortConfig =
    let
        ( sortType, entity ) =
            case sortConfig.mode of
                Sort.NoSort ->
                    ( "-", "-" )

                Sort.ByName _ ->
                    ( "alphabetically"
                    , case sortConfig.axis of
                        Sort.Rows ->
                            "rows"

                        Sort.Columns ->
                            "columns"
                    )

                Sort.ByOtherAxisAverage _ _ ->
                    ( "metric", "average" )

                Sort.ByOtherAxisMetric _ metric _ ->
                    ( "metric", Metric.label metric )
    in
    [ ( "type", Encode.string sortType )
    , ( "entity", Encode.string entity )
    ]


encodeAffixedFrom : AffixedFrom -> Value
encodeAffixedFrom affixedFrom =
    Encode.string <|
        case affixedFrom of
            BulkBar ->
                "bulk_bar"

            AddAttributeButton ->
                "add_attribute"

            FromDropDownMenu ->
                "dropdown_menu"

            NotTracked ->
                "not-tracked this should not be tracked!!!"


encodeCrosstabIdAttributeFromRoute : Route -> List ( String, Value )
encodeCrosstabIdAttributeFromRoute route =
    case route of
        Project (Just projectId) ->
            [ ( "crosstab_id", XB2.Share.Data.Id.encode projectId ) ]

        _ ->
            []


encodeEvent : Flags -> Route -> Place -> Event -> ( String, Value )
encodeEvent flags route place event =
    case event of
        Flipped eventParams ->
            ( "P2 - Crosstabs - View Flipped"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        LimitReachedAddingRowOrColumn eventParams ->
            ( "P2 - Crosstabs - Cells Limit Reached"
            , Encode.object <|
                placeAttr place
                    :: ( "adding_to", Encode.string <| String.toSentenceCase <| Common.directionToString eventParams.extraParams.direction )
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        LimitReachedAddingBase eventParams ->
            ( "P2 - Crosstabs - Max n.bases reached"
            , Encode.object <|
                placeAttr place
                    :: ( "adding_to", Encode.string "Base" )
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        LocationsChanged eventParams ->
            ( "P2 - Crosstabs - Save Locations"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        WavesChanged eventParams ->
            ( "P2 - Crosstabs - Save Waves"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        MetricsViewToggled { rowCount, colCount, cellCount, newState } ->
            ( "P2 - Crosstabs - Metrics View Toggled"
            , Encode.object
                ([ ( "new_state", Encode.string <| metricAnalyticsName newState )
                 , ( "rows_count", Encode.int rowCount )
                 , ( "cols_count", Encode.int colCount )
                 , ( "cells_count", Encode.int cellCount )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        BaseAudienceApplied ({ extraParams } as eventParams) ->
            ( "P2 - Crosstabs - Base Applied"
            , Encode.object <|
                placeAttr extraParams.place
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        BaseSelected params ->
            ( "P2 - Crosstabs - Base Selected"
            , Encode.object
                ([ ( "base_n", Encode.int <| List.length params.appliedBases )
                 , ( "base_selected_n", Encode.int <| List.length params.selectedBases )
                 , ( "bases", Encode.list encodeBaseAudienceCaption params.selectedBases )
                 , ( "data_point_code", params.datapointCodes |> commaSeparated XB2.Share.Data.Id.unwrap )
                 , ( "item_selected_from", Encode.string "table" )
                 , ( "item_type", Encode.string "base" )
                 , ( "question_code", params.questionCodes |> commaSeparated XB2.Share.Data.Id.unwrap )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        ItemMoved ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Item Moved"
            , Encode.object <|
                ( "moved_from", encodeDestination extraParams.movedFrom )
                    :: ( "moved_to", encodeDestination extraParams.movedTo )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ItemsDeleted ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Item Deleted"
            , Encode.object <|
                ( "total_deleted", Encode.int (extraParams.deletedRows + extraParams.deletedColumns) )
                    :: ( "rows_deleted", Encode.int extraParams.deletedRows )
                    :: ( "columns_deleted", Encode.int extraParams.deletedColumns )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ItemAdded { destination, audienceId, itemType, addedHow, cellsCount, questions, datapointCodes, datasetNames, itemLabel } ->
            let
                questionCodes : List NamespaceAndQuestionCode
                questionCodes =
                    List.map .longCode questions

                questionNames : List String
                questionNames =
                    List.map .name questions
            in
            ( "P2 - Crosstabs - Item Added"
            , Encode.object
                ([ ( "item_added_from", Encode.string "attribute browser" )
                 , ( "item_added_to", encodeDestination destination )
                 , ( "item_added_how", encodeAddedHow addedHow )
                 , ( "audience_id", Encode.string <| Maybe.unwrap "n/a" Audience.idToString audienceId )
                 , ( "item_name", Encode.string itemLabel )
                 , ( "section", encodeSectionFromDestination destination )
                 , ( "item_type", Encode.string itemType )
                 , ( "cells_count", Encode.int cellsCount )
                 , ( "question_code", questionCodes |> List.map XB2.Share.Data.Id.unwrap |> commaSeparated identity )
                 , ( "question_names_list", Encode.list Encode.string questionNames )
                 , ( "question_code_list", questionCodes |> List.map XB2.Share.Data.Id.unwrap |> list identity )
                 , ( "data_point_code", datapointCodes |> List.map XB2.Share.Data.Id.unwrap |> commaSeparated identity )
                 , ( "data_point_code_list", datapointCodes |> List.map XB2.Share.Data.Id.unwrap |> list identity )
                 , ( "data_sets", Encode.list Encode.string datasetNames )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        AverageAdded { destination, addedHow, cellsCount, average, datasetNames } ->
            let
                ( avgQuestion, dtp ) =
                    case average of
                        AttributeBrowser.AvgWithoutSuffixes code ->
                            ( code, Encode.string "n/a" )

                        AttributeBrowser.AvgWithSuffixes code { datapointCode } ->
                            ( code, XB2.Share.Data.Id.encode datapointCode )
            in
            ( "P2 - Crosstabs - Item Added"
            , Encode.object
                ([ ( "item_added_to", encodeDestination destination )
                 , ( "item_added_how", encodeAddedHow addedHow )
                 , ( "section", encodeSectionFromDestination destination )
                 , ( "item_type", Encode.string "average" )
                 , ( "cells_count", Encode.int cellsCount )
                 , ( "question_code", XB2.Share.Data.Id.encode avgQuestion.questionCode )
                 , ( "question_name", Encode.string <| AttributeBrowser.getAverageQuestionLabel average )
                 , ( "data_point_code", dtp )
                 , ( "data_sets", Encode.list Encode.string datasetNames )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        BasesDeleted ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Base Deleted"
            , Encode.object <|
                ( "deleted", Encode.int extraParams.basesCount )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        RowsColsDeletionModalOpened sharedParams ->
            ( "P2 - Crosstabs - Items deletion confirmation"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        BasesDeletionModalOpened sharedParams ->
            ( "P2 - Crosstabs - Base deletion confirmation"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        GroupAddedAsNew ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Added"
            , Encode.object <|
                ( "added_to", encodeDestination extraParams.destination )
                    :: ( "added_how", encodeAddedHow AddedAsNew )
                    :: ( "appended_by", Encode.string "" )
                    :: ( "appended_count", Encode.int extraParams.appendedCount )
                    :: ( "audiences_count", Encode.int extraParams.counts.audiencesCount )
                    :: ( "datapoints_count", Encode.int extraParams.counts.datapointsCount )
                    :: ( "questions_count", Encode.int extraParams.counts.questionsCount )
                    :: ( "operator", encodeGrouping extraParams.groupingOperator )
                    :: ( "data_sets", Encode.list Encode.string extraParams.datasetNames )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        GroupDuplicated ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Duplicated"
            , Encode.object <|
                ( "group_name", Encode.string <| Caption.getName extraParams.caption )
                    :: (Tuple.mapFirst ((++) "group_") <| XBData.encodeAudienceDefinition extraParams.expression)
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        GroupAddedByAffixToBase ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Added"
            , Encode.object <|
                ( "added_to", encodeDestination CrosstabBase )
                    :: ( "appended_count", Encode.int 1 )
                    :: ( "added_how", encodeAddedHow AddedByAppend )
                    :: ( "appended_by", encodeRootLogicOperator extraParams.newExpression )
                    :: ( "operator", encodeGrouping extraParams.groupingOperator )
                    :: ( "questions_count", Encode.int extraParams.counts.questionsCount )
                    :: ( "datapoints_count", Encode.int extraParams.counts.datapointsCount )
                    :: ( "averages_count", Encode.int extraParams.counts.averagesCount )
                    :: ( "audiences_count", Encode.int extraParams.counts.audiencesCount )
                    :: ( "data_sets", Encode.list Encode.string extraParams.datasetNames )
                    :: placeAttr Place.CrosstabBuilderBase
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        BasesEdited ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Bases Edited"
            , Encode.object <|
                ( "edited_to", encodeDestination CrosstabBase )
                    :: ( "edited_count", Encode.int 1 )
                    :: ( "edited_by", encodeRootLogicOperator extraParams.newExpression )
                    :: ( "questions_count", Encode.int extraParams.counts.questionsCount )
                    :: ( "datapoints_count", Encode.int extraParams.counts.datapointsCount )
                    :: ( "averages_count", Encode.int extraParams.counts.averagesCount )
                    :: ( "audiences_count", Encode.int extraParams.counts.audiencesCount )
                    :: ( "data_sets", Encode.list Encode.string extraParams.datasetNames )
                    :: placeAttr Place.CrosstabBuilderBase
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        GroupsAddedByAffixToTable ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Added"
            , Encode.object <|
                ( "added_to", encodeDestination extraParams.destination )
                    :: ( "appended_count", Encode.int extraParams.appendedCount )
                    :: ( "added_how", encodeAddedHow AddedByAppend )
                    :: ( "appended_by", encodeLogicOperator extraParams.appendingOperator )
                    :: ( "operator", encodeGrouping extraParams.groupingOperator )
                    :: ( "questions_count", Encode.int extraParams.counts.questionsCount )
                    :: ( "datapoints_count", Encode.int extraParams.counts.datapointsCount )
                    :: ( "averages_count", Encode.int extraParams.counts.averagesCount )
                    :: ( "audiences_count", Encode.int extraParams.counts.audiencesCount )
                    :: ( "added_from", encodeAffixedFrom extraParams.affixedFrom )
                    :: ( "data_sets", Encode.list Encode.string extraParams.datasetNames )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        GroupsAddedByEditToTable ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Edited"
            , Encode.object <|
                ( "edited_to", encodeDestination extraParams.destination )
                    :: ( "edited_count", Encode.int extraParams.editedCount )
                    :: ( "questions_count", Encode.int extraParams.counts.questionsCount )
                    :: ( "datapoints_count", Encode.int extraParams.counts.datapointsCount )
                    :: ( "averages_count", Encode.int extraParams.counts.averagesCount )
                    :: ( "audiences_count", Encode.int extraParams.counts.audiencesCount )
                    :: ( "data_sets", Encode.list Encode.string extraParams.datasetNames )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        NAIntersection ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - N/A intersection"
            , Encode.object <|
                ( "NA_reason", Encode.string <| XB2.Share.Gwi.Http.errorToString AudienceIntersect.xbQueryErrorStringWithoutCodeTranslation extraParams.queryError )
                    :: ( "retry_count", Encode.int extraParams.retryCount )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ProjectCreationStarted ->
            ( "P2 - Crosstabs - Create Project"
            , Encode.object (placeAttr place :: encodeCrosstabIdAttributeFromRoute route)
            )

        ProjectOpened { project, store } ->
            ( "P2 - Crosstabs - Project Opened"
            , Encode.object <|
                sharedProjectEventParams flags place project store
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        UnsavedProjectOpened { project, store } ->
            ( "P2 - Crosstabs - Project Opened"
            , Encode.object <|
                unsavedProjectEventParams flags place project store
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ProjectRenamed { project, store } ->
            ( "P2 - Crosstabs - Project Renamed"
            , Encode.object <|
                sharedProjectEventParams flags place project store
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        HeaderCollapsed { extraParams } ->
            let
                isHeaderCollapsedToString : Bool -> String
                isHeaderCollapsedToString collapsed =
                    if collapsed then
                        "collapsed"

                    else
                        "expanded"
            in
            ( "P2 - Crosstabs - Header status change"
            , Encode.object
                (( "status"
                 , Encode.string (isHeaderCollapsedToString extraParams.isHeaderCollapsed)
                 )
                    :: encodeCrosstabIdAttributeFromRoute route
                )
            )

        ProjectSaved { project, newlyCreated, store, questions } ->
            let
                rowsAndCols =
                    (project.data.rows ++ project.data.columns)
                        |> List.map .definition

                basesExpressions =
                    project.data.bases
                        |> NonemptyList.toList
                        |> List.map .expression

                datasetNames =
                    XBData.getProjectDatasetNames rowsAndCols basesExpressions store

                locations =
                    XB2.Share.Store.Utils.getByIds store.locations project.data.locationCodes

                waves =
                    XB2.Share.Store.Utils.getByIds store.waves project.data.waveCodes

                audienceNames =
                    project.data.bases
                        |> NonemptyList.toList
                        |> List.map .name
            in
            ( "P2 - Crosstabs - Project Saved"
            , Encode.object
                [ ( "datasets", Encode.list Encode.string datasetNames )
                , ( "datasets_count", Encode.int <| List.length datasetNames )
                , ( "app", Encode.string "Crosstabs" )
                , ( "crosstab_id", XB2.Share.Data.Id.encode project.id )
                , ( "waves_count", Encode.int <| List.length waves )
                , ( "waves", Encode.list (.name >> Encode.string) waves )
                , ( "locations_count", Encode.int <| List.length locations )
                , ( "locations", Encode.list (.name >> Encode.string) locations )
                , ( "is_owner", Encode.bool <| project.data.ownerId == flags.user.id )
                , ( "is_shared", Encode.bool <| project.shared /= XBData.MyPrivateCrosstab )
                , ( "newly_saved", Encode.bool newlyCreated )
                , ( "audiences_names", Encode.list Encode.string audienceNames )
                , ( "audiences_count", Encode.int <| List.length audienceNames )
                , ( "question_codes", Encode.list (.code >> XB2.Share.Data.Id.encode) questions )
                , ( "question_names", Encode.list (.name >> Encode.string) questions )
                , ( "question_count", Encode.int <| List.length questions )
                , ( "attributes_count", Encode.int <| List.length <| List.map (.datapoints >> NonemptyList.length) questions )
                ]
            )

        ProjectDuplicated { project, originalProject, store } ->
            ( "P2 - Crosstabs - Project Duplicated"
            , Encode.object <|
                ( "original_project_name", Encode.string originalProject.name )
                    :: ( "original_crosstab_id", XB2.Share.Data.Id.encode originalProject.id )
                    :: ( "original_project_creator", Encode.string originalProject.data.ownerId )
                    :: ( "saved_as_a_copy", Encode.bool <| XBData.isSharedWithMe originalProject.shared )
                    :: sharedProjectEventParams flags place project store
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ProjectDeleted { project, store } ->
            ( "P2 - Crosstabs - Project Deleted"
            , Encode.object <|
                sharedProjectEventParams flags place project store
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ProjectShared { project, store, questions } ->
            let
                isSharedWithOrg =
                    case project.shared of
                        XBData.MySharedCrosstab sharees ->
                            NonemptyList.any XBData.isOrgSharee sharees

                        _ ->
                            False

                rowsAndCols =
                    (project.data.rows ++ project.data.columns)
                        |> List.map .definition

                basesExpressions =
                    project.data.bases
                        |> NonemptyList.toList
                        |> List.map .expression

                datasetNames =
                    XBData.getProjectDatasetNames rowsAndCols basesExpressions store

                locations =
                    XB2.Share.Store.Utils.getByIds store.locations project.data.locationCodes

                waves =
                    XB2.Share.Store.Utils.getByIds store.waves project.data.waveCodes

                audienceNames =
                    project.data.bases
                        |> NonemptyList.toList
                        |> List.map .name
            in
            ( "P2 - Crosstabs - Project Shared"
            , Encode.object
                [ ( "message", Encode.bool <| not <| String.isEmpty project.sharingNote )
                , ( "message_length", Encode.int (String.length project.sharingNote) )
                , ( "shared_with_org", Encode.bool isSharedWithOrg )
                , ( "datasets", Encode.list Encode.string datasetNames )
                , ( "datasets_count", Encode.int <| List.length datasetNames )
                , ( "app", Encode.string "Crosstabs" )
                , ( "crosstab_id", XB2.Share.Data.Id.encode project.id )
                , ( "waves_count", Encode.int <| List.length waves )
                , ( "waves", Encode.list (.name >> Encode.string) waves )
                , ( "locations_count", Encode.int <| List.length locations )
                , ( "locations", Encode.list (.name >> Encode.string) locations )
                , ( "is_owner", Encode.bool <| project.data.ownerId == flags.user.id )
                , ( "is_shared", Encode.bool <| project.shared /= XBData.MyPrivateCrosstab )
                , ( "newly_saved", Encode.bool False )
                , ( "audiences_names", Encode.list Encode.string audienceNames )
                , ( "audiences_count", Encode.int <| List.length audienceNames )
                , ( "question_codes", Encode.list (.code >> XB2.Share.Data.Id.encode) questions )
                , ( "question_names", Encode.list (.name >> Encode.string) questions )
                , ( "question_count", Encode.int <| List.length questions )
                , ( "attributes_count", Encode.int <| List.length <| List.map (.datapoints >> NonemptyList.length) questions )
                ]
            )

        Export data ->
            let
                rowsAndCols =
                    data.audiences
                        |> List.map AudienceItem.getDefinition

                basesExpressions =
                    data.xbBases
                        |> List.map BaseAudience.getExpression

                datasetNames =
                    XBData.getProjectDatasetNames rowsAndCols basesExpressions data.store

                maybeProject =
                    data.maybeProject

                questionCodes =
                    maybeProject
                        |> Maybe.unwrap [] XBData.getProjectQuestionCodes

                questions =
                    questionCodes
                        |> Maybe.traverse (\code -> XB2.Share.Store.Platform2.getQuestionMaybe code data.store)
                        |> Maybe.withDefault []

                isSaved =
                    case data.isSaved of
                        Saved _ ->
                            True

                        Edited _ ->
                            True

                        UnsavedEdited ->
                            False

                        Unsaved ->
                            False
            in
            ( "P2 - Crosstabs - Query Export"
            , Encode.object
                ([ ( "datasets_count", Encode.int <| List.length datasetNames )
                 , ( "datasets", Encode.list Encode.string datasetNames )
                 , ( "app", Encode.string "Crosstabs" )
                 , ( "locations", list .name data.locations )
                 , ( "locations_count", Encode.int <| List.length data.locations )
                 , ( "waves", list .name data.waves )
                 , ( "waves_count", Encode.int <| List.length data.waves )
                 , ( "audiences_names", list getNameFromItem data.audiences )
                 , ( "audiences_count", Encode.int <| List.length data.audiences )
                 , ( "project_saved", Encode.bool isSaved )
                 ]
                    ++ Maybe.unwrap []
                        (\project ->
                            [ ( "crosstab_id", XB2.Share.Data.Id.encode project.id )
                            , ( "is_shared", Encode.bool <| project.shared /= XBData.MyPrivateCrosstab )
                            , ( "is_owner", Encode.bool <| project.data.ownerId == flags.user.id )
                            , ( "question_codes", Encode.list (.code >> XB2.Share.Data.Id.encode) questions )
                            , ( "question_names", Encode.list (.name >> Encode.string) questions )
                            , ( "question_count", Encode.int <| List.length questions )
                            , ( "attributes_count", Encode.int <| List.length <| List.map (.datapoints >> NonemptyList.length) questions )
                            ]
                        )
                        maybeProject
                )
            )

        GroupRenamed ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Group Renamed"
            , Encode.object <|
                ( "new_name", Encode.string extraParams.newName )
                    :: ( "old_name", Encode.string extraParams.oldName )
                    :: ( "datapoints_count"
                       , extraParams.datapointsCount
                            |> Maybe.map Encode.int
                            |> Maybe.withDefault (Encode.string "n/a - average row/col")
                       )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        KnowledgeBaseOpened name url ->
            ( "P2 - Crosstabs - Knowledge Base Opened"
            , Encode.object
                ([ ( "link_name", Encode.string name )
                 , ( "link_url", Encode.string url )
                 , placeAttr place
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        HeatmapApplied ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Heatmap applied"
            , Encode.object <|
                ( "metric", encodeMetric extraParams.metric )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        MetricsChosen ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Choose Metrics"
            , Encode.object <|
                ( "metric", extraParams.metrics |> AssocSet.toList |> commaSeparated Metric.label )
                    :: ( "metric_list", extraParams.metrics |> AssocSet.toList |> list Metric.label )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        UndoApplied ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Undo applied"
            , Encode.object <|
                ( "event", Encode.string <| UndoEvent.label extraParams.undoEvent )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        RedoApplied ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Redo applied"
            , Encode.object <|
                ( "event", Encode.string <| UndoEvent.label extraParams.undoEvent )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        UndoClickedInAttrBrowser ->
            ( "P2 - Crosstabs - Browser undo applied"
            , Encode.object <| encodeCrosstabIdAttributeFromRoute route
            )

        RedoClickedInAttrBrowser ->
            ( "P2 - Crosstabs - Browser redo applied"
            , Encode.object <| encodeCrosstabIdAttributeFromRoute route
            )

        ItemSelectedInTable params ->
            let
                selectionType =
                    case params.direction of
                        Row ->
                            "row"

                        Column ->
                            "column"

                convertSelectedTypeToString : ItemSelected -> String
                convertSelectedTypeToString selected =
                    case selected of
                        TickBox ->
                            "tickbox"
            in
            ( "P2 - Crosstabs - Item selected"
            , Encode.object
                ([ ( "item_selected_from", Encode.string "table" )
                 , ( "data_point_code", list XB2.Share.Data.Id.unwrap params.datapointCodes )
                 , ( "question_code", list XB2.Share.Data.Id.unwrap params.questionCodes )
                 , ( "expression_id", list Caption.getFullName params.captions )
                 , ( "selection_type", Encode.string selectionType )
                 , ( "selected_items_count", Encode.int 1 )
                 , ( "selected_from", Encode.string (convertSelectedTypeToString params.itemSelected) )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        ItemSelectedInTableWithShift params ->
            let
                selectionType =
                    case params.direction of
                        Row ->
                            "row"

                        Column ->
                            "column"
            in
            ( "P2 - Crosstabs - Shift+Click selection"
            , Encode.object
                ([ ( "item_selected_from", Encode.string "table" )
                 , ( "data_point_code", list XB2.Share.Data.Id.unwrap params.datapointCodes )
                 , ( "question_code", list XB2.Share.Data.Id.unwrap params.questionCodes )
                 , ( "expression_id", list Caption.getFullName params.captions )
                 , ( "selection_type", Encode.string selectionType )
                 , ( "selected_items_count", Encode.int 1 )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        AllItemsSelectedInTable params ->
            ( "P2 - Crosstabs - Select all columns / rows"
            , Encode.object
                ([ ( "item_selected_from", Encode.string "table" )
                 , ( "selected_items_count", Encode.int params.selectedItemsCount )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        ItemAddedAsABase ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Item added as a base"
            , Encode.object <|
                ( "cols_rows_selected_n", Encode.int extraParams.rowsColsSelected )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        AudienceSaved ({ extraParams } as sharedParams) ->
            let
                datapointCodes =
                    Expression.getQuestionAndDatapointCodes extraParams.expression
                        |> List.uniqueBy XB2.Share.Data.Id.unwrap

                questionCodes =
                    Expression.getQuestionCodes extraParams.expression
                        |> List.uniqueBy XB2.Share.Data.Id.unwrap

                audience_expression =
                    analyticsFriendlyExpression extraParams.expression
                        |> Encode.list Encode.string
            in
            ( "P2 - Crosstabs - Audience saved"
            , Encode.object <|
                ( "audience_name", Encode.string <| Caption.getName extraParams.caption )
                    :: ( "audience_expression", audience_expression )
                    :: ( "question_code", commaSeparated XB2.Share.Data.Id.unwrap questionCodes )
                    :: ( "question_code_list", list XB2.Share.Data.Id.unwrap questionCodes )
                    :: ( "data_point_code", commaSeparated XB2.Share.Data.Id.unwrap datapointCodes )
                    :: ( "data_point_code_list", list XB2.Share.Data.Id.unwrap datapointCodes )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        TableFullyLoaded ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Full table loaded"
            , Encode.object <|
                ( "load_time_seconds", Encode.int extraParams.loadTime )
                    :: ( "after_load_action", Encode.string extraParams.afterLoadAction )
                    :: placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        TableSorted ({ extraParams } as sharedParams) ->
            ( "P2 - Crosstabs - Sorting applied"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeSortConfig extraParams.sortConfig
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        UselessCheckboxClicked sharedParams ->
            ( "P2 - Crosstabs - Useless checkbox in selection panel clicked"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters sharedParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        AverageUnitChanged eventParams ->
            ( "P2 - Crosstabs - Average unit changed"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters eventParams
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        OpenAttributeBrowser target ->
            ( "Add an attribute/audience"
            , Encode.object (encodeAttributeBrowserOpenType target :: encodeCrosstabIdAttributeFromRoute route)
            )

        FolderCreated params ->
            ( "P2 - Crosstabs - Folder created"
            , Encode.object
                ([ placeAttr place
                 , ( "folder_name", Encode.string params.folder.name )
                 , ( "project_names", Encode.list Encode.string <| List.map .name params.projects )
                 , ( "n_projects", Encode.int <| List.length params.projects )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        MoveProjectsTo params ->
            ( "P2 - Crosstabs - Moved to/out folder"
            , Encode.object
                ([ placeAttr place
                 , ( "move_out", Encode.bool params.movingOut )
                 , ( "folder_name", Encode.string params.folderName )
                 , ( "project_names", Encode.list Encode.string <| List.map .name params.projects )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        FolderDeleted params ->
            ( "P2 - Crosstabs - Folder deleted"
            , Encode.object
                ([ placeAttr place
                 , ( "folder_name", Encode.string params.folder.name )
                 , ( "project_names", Encode.list Encode.string <| List.map .name params.projects )
                 , ( "n_projects", Encode.int <| List.length params.projects )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        UngroupedFolder params ->
            ( "P2 - Crosstabs - Ungroup"
            , Encode.object
                ([ placeAttr place
                 , ( "folder_name", Encode.string params.folder.name )
                 , ( "project_names", Encode.list Encode.string <| List.map .name params.projects )
                 , ( "n_projects", Encode.int <| List.length params.projects )
                 ]
                    ++ encodeCrosstabIdAttributeFromRoute route
                )
            )

        HeaderResized params ->
            ( "P2 - Crosstabs - Header re-sized"
            , Encode.object <|
                placeAttr place
                    :: sharedEventParameters params
                    ++ [ ( "expanded", Encode.bool params.extraParams.expanded )
                       , ( "columns_rows"
                         , Encode.string <|
                            if params.extraParams.wasResizingColumns then
                                "columns"

                            else
                                "rows"
                         )
                       , ( "max_characters_count", Encode.int params.extraParams.maxCharCount )
                       , ( "average_characters_count", Encode.int params.extraParams.avgCharCount )
                       ]
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        WarningClicked params ->
            ( "P2 - Crosstabs - Warning clicked"
            , Encode.object <|
                sharedEventParameters params
                    ++ [ Tuple.mapFirst (\type_ -> "column_" ++ type_) <| XBData.encodeAudienceDefinition params.extraParams.column
                       , Tuple.mapFirst (\type_ -> "row_" ++ type_) <| XBData.encodeAudienceDefinition params.extraParams.row
                       , ( "num_of_warnings", Encode.int params.extraParams.numOfWarnings )
                       ]
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        ProjectOpenedAfterExportFromListView { project, store } ->
            ( "P2 - Crosstabs - Project Opened after export from list view"
            , Encode.object <|
                sharedProjectEventParams flags place project store
            )

        ListSorted { sorting } ->
            ( "P2 - Crosstabs - Sorted by"
            , Encode.object (( "sorting", Encode.string sorting ) :: encodeCrosstabIdAttributeFromRoute route)
            )

        TabsClicked { tab } ->
            ( "P2 - Crosstabs - Tab clicked"
            , Encode.object (( "tab", Encode.string tab ) :: encodeCrosstabIdAttributeFromRoute route)
            )

        ManagementPageDragAndDropUsed ->
            ( "P2 - Crosstabs - drag and drop"
            , Encode.object
                (placeAttr place :: encodeCrosstabIdAttributeFromRoute route)
            )

        ManagementPageOpened { splashScreen } ->
            ( "P2 - Crosstabs Management - Opened"
            , Encode.object
                (( "splash_screen", Encode.bool splashScreen ) :: placeAttr place :: encodeCrosstabIdAttributeFromRoute route)
            )

        AffixAttributesOrAudiences affixedFrom ->
            let
                type_ =
                    case affixedFrom of
                        BulkBar ->
                            "bar"

                        AddAttributeButton ->
                            "bar"

                        FromDropDownMenu ->
                            "cell"

                        NotTracked ->
                            "N/A"
            in
            ( "P2 - Crosstabs - Affix attributes/audiences"
            , Encode.object
                (( "type", Encode.string type_ ) :: encodeCrosstabIdAttributeFromRoute route)
            )

        CopyLink { projectId, projectName } ->
            ( "P2 - Crosstabs - Copy link"
            , Encode.object
                [ ( "crosstab_id", XB2.Share.Data.Id.encode projectId )
                , ( "project_name", Encode.string projectName )
                ]
            )

        RespondentNumberChanged ({ extraParams } as params) ->
            ( "P2 - Crosstabs - respondent number"
            , Encode.object <|
                sharedEventParameters params
                    ++ (( "number_type"
                        , case extraParams.respondentNumberType of
                            Exact ->
                                Encode.string "exact"

                            Rounded ->
                                Encode.string "rounded"
                        )
                            :: encodeCrosstabIdAttributeFromRoute route
                       )
            )

        UniverseNumberChanged ({ extraParams } as params) ->
            ( "P2 - Crosstabs - Universe number"
            , Encode.object <|
                sharedEventParameters params
                    ++ (( "number_type"
                        , case extraParams.respondentNumberType of
                            Exact ->
                                Encode.string "exact"

                            Rounded ->
                                Encode.string "rounded"
                        )
                            :: encodeCrosstabIdAttributeFromRoute route
                       )
            )

        RowsOrColumnsMerged ({ extraParams } as params) ->
            ( "P2 - Crosstabs - rows/columns merged"
            , Encode.object <|
                sharedEventParameters params
                    ++ (( "merged_how"
                        , case extraParams.mergedHow of
                            AsNew ->
                                Encode.string "as_new"

                            Merged ->
                                Encode.string "merged"
                        )
                            :: encodeCrosstabIdAttributeFromRoute route
                       )
            )

        BaseOrderChanged ({ extraParams } as params) ->
            ( "P2 - Crosstabs - base order changed"
            , Encode.object <|
                sharedEventParameters params
                    ++ (( "changed_how"
                        , case extraParams.changedHow of
                            DragAndDrop ->
                                Encode.string "drag_and_drop"

                            Menu ->
                                Encode.string "menu"

                            Keyboard ->
                                Encode.string "keyboard"
                        )
                            :: encodeCrosstabIdAttributeFromRoute route
                       )
            )

        CellsFrozen ({ extraParams } as params) ->
            ( "P2 - Crosstabs - Freezing feature"
            , Encode.object <|
                sharedEventParameters params
                    ++ [ ( "item"
                         , Encode.string (frozenItemToString extraParams.item)
                         )
                       , ( "how_many"
                         , if extraParams.howMany < 1 then
                            Encode.string "none"

                           else
                            Encode.string ("first_" ++ String.fromInt extraParams.howMany)
                         )
                       ]
                    ++ encodeCrosstabIdAttributeFromRoute route
            )

        MinimumSampleSizeChanged ({ extraParams } as params) ->
            ( "P2 - Crosstabs - Minimum sample size changed"
            , Encode.object <|
                sharedEventParameters params
                    ++ (( "min_sample_size"
                        , Encode.string (minimumSampleSizeToString extraParams.minimumSampleSize)
                        )
                            :: encodeCrosstabIdAttributeFromRoute route
                       )
            )


analyticsFriendlyExpression : Expression.Expression -> List String
analyticsFriendlyExpression =
    let
        foldlExpression : Int -> Expression.LogicOperator -> (Int -> Expression.LogicOperator -> Expression.LeafData -> b -> b) -> b -> Expression.Expression -> b
        foldlExpression depth lastLogicOperator f acc expression =
            case expression of
                Expression.AllRespondents ->
                    acc

                Expression.FirstLevelLeaf leaf ->
                    f depth lastLogicOperator leaf acc

                Expression.FirstLevelNode lo subnodes ->
                    NonemptyList.foldl (\exp listAcc -> foldlExpressionHelp (depth + 1) lo f listAcc exp) acc subnodes

        foldlExpressionHelp : Int -> Expression.LogicOperator -> (Int -> Expression.LogicOperator -> Expression.LeafData -> b -> b) -> b -> Expression.ExpressionHelp -> b
        foldlExpressionHelp depth lastLogicOperator f acc expressionHelp =
            case expressionHelp of
                Expression.Leaf leaf ->
                    f depth lastLogicOperator leaf acc

                Expression.Node lo subnodes ->
                    NonemptyList.foldl (\exp listAcc -> foldlExpressionHelp (depth + 1) lo f listAcc exp) acc subnodes

        commaSeparatedString toString =
            List.map toString
                >> String.join ","

        reducer depth logic leafData =
            (::)
                (String.repeat depth "."
                    ++ "["
                    ++ (case logic of
                            Expression.And ->
                                "AND"

                            Expression.Or ->
                                "OR"
                       )
                    ++ "]"
                    -- keeping qId because of compatibility with old events:
                    ++ "qId:"
                    ++ XB2.Share.Data.Id.unwrap leafData.namespaceAndQuestionCode
                    ++ ",dtps:"
                    ++ commaSeparatedString XB2.Share.Data.Id.unwrap (NonemptyList.toList leafData.questionAndDatapointCodes)
                    ++ (case leafData.suffixCodes of
                            Optional.Present suffixCodes ->
                                ",sfxs:"
                                    ++ commaSeparatedString XB2.Share.Data.Id.unwrap (NonemptyList.toList suffixCodes)

                            Optional.Undefined ->
                                ""
                       )
                )
    in
    foldlExpression 0 Expression.And reducer []


encodeMetric : Metric -> Value
encodeMetric metric =
    Encode.string <|
        case metric of
            Size ->
                "Universe"

            Sample ->
                "Responses"

            Index ->
                "Index"

            RowPercentage ->
                "%Row"

            ColumnPercentage ->
                "%Column"
