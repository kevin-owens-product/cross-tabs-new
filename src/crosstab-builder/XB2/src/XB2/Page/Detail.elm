module XB2.Page.Detail exposing
    ( Config
    , Configure
    , CrosstabData
    , CrosstabSearchModel
    , EditMsg(..)
    , MeasuredAfterQueueCmd
    , Model
    , MouseDownMovemenet
    , MoveParameters
    , Msg(..)
    , ScrollingState
    , TableSelectMsg(..)
    , checkIfSharedProjectIsUpToDate
    , clearWorkspace
    , configure
    , confirmBeforeLeave
    , currentCrosstab
    , currentOrderBeforeSorting
    , exportEvent
    , getAnalyticsCmd
    , getCopyProjectFromCrosstab
    , getLastOpenedProjectId
    , getNewProjectFromCrosstab
    , init
    , leaveConfirmCheckCmd
    , markAsSaved
    , onModalOpened
    , onP2StoreChange
    , onP2StoreError
    , openNewProject
    , openSavedProject
    , projectDestroyed
    , projectUpdated
    , reopeingProject
    , saveChangesAndGoBackToProjectList
    , saveEditedProject
    , savingAudience
    , setCollapsedHeader
    , showUnsavedChangesDialog
    , subscriptions
    , update
    , updateSharedProjectWarning
    , updateTime
    , view
    )

{-| TODOs for follow up refactoring

  - [ ] change remove audiences and select audiences to `ToggleAudiences`
    which takes zipper as an argument and do all the hard traversal
    in update not in view (during every render)?
  - [ ] change selectAll view so it just generates some form of simpler msg
    so we limit work done in every render.
    (This is lower priority as this is called just one time per render)

-}

import AssocSet
import Basics.Extra exposing (fractionalModBy, uncurry)
import Browser.Dom as Dom
import Browser.Events
import Cmd.Extra as Cmd
import DateFormat
import Debouncer.Basic as Debouncer
import Dict
import Dict.Any
import DnDList as Dnd
import Glue
import Html exposing (Attribute, Html)
import Html.Attributes as Attrs
import Html.Attributes.Extra as Attrs
import Html.Events as Events
import Html.Extra as Html
import Http
import Json.Decode as Decode
import Json.Decode.Extra as Decode
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import List.NonEmpty.Zipper as ListZipper exposing (Zipper)
import Markdown
import Maybe.Extra as Maybe
import Process
import Random
import RemoteData
import Set.Any
import Simple.Fuzzy as Fuzzy
import String.Extra as String
import String.Normalize as String
import Task
import Time exposing (Posix, Zone)
import WeakCss
import XB2.Analytics as Analytics
    exposing
        ( AddedHow(..)
        , Destination(..)
        , Event(..)
        )
import XB2.CrosstabCellLoader as CrosstabCellLoader
import XB2.Data as XBData
    exposing
        ( AudienceDefinition(..)
        , MinimumSampleSize
        , Shared(..)
        , XBFolderId
        , XBProject
        , XBProjectFullyLoaded
        , XBProjectId
        , XBProjectMetadata
        , XBUserSettings
        )
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression
    exposing
        ( Expression
        , LogicOperator
        )
import XB2.Data.AudienceCrosstab as ACrosstab
    exposing
        ( AffixGroupItem
        , AudienceCrosstab
        , CrosstabTable
        , Direction(..)
        , EditGroupItem
        , MovableItems
        , MultipleAudiencesInserter
        , OriginalOrder(..)
        , VisibleCells
        )
import XB2.Data.AudienceCrosstab.Export as XBExport exposing (ExportData)
import XB2.Data.AudienceCrosstab.Sort as Sort exposing (SortConfig)
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId exposing (AudienceItemId)
import XB2.Data.Average as Average
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect
    exposing
        ( XBQueryError
        )
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Metric exposing (Metric)
import XB2.Data.MetricsTransposition exposing (MetricsTransposition(..))
import XB2.Data.Namespace as Namespace
import XB2.Data.SelectionMap as SelectionMap exposing (SelectionMap)
import XB2.Data.UndoEvent as UndoEvent exposing (UndoEvent)
import XB2.DebugDump
import XB2.Detail.Common as Common
    exposing
        ( Dropdown(..)
        , Unsaved(..)
        , datasetCodesFromNamespaceCodes
        , defaultLocations
        , filteredMetrics
        , getAudienceFolders
        , moduleClass
        )
import XB2.Detail.Heatmap as Heatmap exposing (HeatmapScale)
import XB2.Detail.NotificationText as NotificationText
import XB2.Detail.TableView as Table
import XB2.Modal.Browser as ModalBrowser exposing (SelectedItem(..), SelectedItems)
import XB2.PageScroll as PageScroll
import XB2.Router
import XB2.Share.Analytics.Place as Place exposing (Place)
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id exposing (IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        , NamespaceAndQuestionCode
        , NamespaceAndQuestionCodeTag
        , Question
        , QuestionAndDatapointCode
        , QuestionAndDatapointCodeTag
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2
import XB2.Share.DragAndDrop.Move
import XB2.Share.Export exposing (ExportError, ExportResponse)
import XB2.Share.Gwi.Browser.Dom as Dom
import XB2.Share.Gwi.Html.Attributes as Attrs
import XB2.Share.Gwi.Html.Events as Events
import XB2.Share.Gwi.Http exposing (Error)
import XB2.Share.Gwi.Json.Decode as Decode
import XB2.Share.Gwi.List as List
import XB2.Share.Gwi.String as String
import XB2.Share.Icons exposing (IconData)
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.LeavePageConfirm
import XB2.Share.Permissions exposing (Can)
import XB2.Share.Platform2.Drawers as Drawers
import XB2.Share.Platform2.Dropdown.DropdownMenu as DropdownMenu exposing (DropdownMenu)
import XB2.Share.Platform2.Grouping exposing (Grouping(..))
import XB2.Share.Platform2.NameForCopy as NameForCopy
import XB2.Share.Platform2.Notification as Notification exposing (Notification)
import XB2.Share.Platform2.Spinner as Spinner
import XB2.Share.Plural
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store
import XB2.Share.Time.Format
import XB2.Share.UndoRedo exposing (UndoRedo)
import XB2.Share.UndoRedo.Step
import XB2.Sort as Sort
    exposing
        ( Axis(..)
        , AxisSort(..)
        , Sort
        )
import XB2.Store as XBStore
import XB2.Utils.NewName as NewName
import XB2.Views.AttributeBrowser as AttributeBrowser
import XB2.Views.Header as Header
import XB2.Views.Modal as Modal exposing (AffixBaseGroupData, EditBaseGroupData, Modal)
import XB2.Views.Modal.LoaderWithProgress as LoaderWithProgressModal
import XB2.Views.Modal.LoaderWithoutProgress as LoaderWithoutProgressModal


type alias Config msg =
    { msg : Msg -> msg
    , ajaxError : Error Never -> msg
    , exportAjaxError : Error ExportError -> msg
    , queryAjaxError : Error XBQueryError -> msg
    , navigateTo : XB2.Router.Route -> msg
    , limitReachedAddingRowOrColumn : Int -> ACrosstab.ErrorAddingRowOrColumn -> msg
    , limitReachedAddingBases : Int -> ACrosstab.ErrorAddingBase -> msg
    , createXBProject : XBProject -> msg
    , updateXBProject : XBProject -> msg
    , setProjectToStore : XBProjectFullyLoaded -> msg
    , saveCopyOfProject :
        { original : XBProjectFullyLoaded
        , copy : XBProject
        , shouldRedirect : Bool
        }
        -> msg
    , openModal : Modal -> msg
    , openSharingModal : XBProject -> msg
    , closeModal : msg
    , createDetailNotification : IconData -> Html Msg -> msg
    , createDetailPersistentNotification : String -> Notification Msg -> msg
    , closeDetailNotification : String -> msg
    , disabledExportsAlert : msg
    , headerConfig : Header.Config msg
    , setDoNotShowAgain : XBData.DoNotShowAgain -> msg
    , fetchManyP2 : List XB2.Share.Store.Platform2.StoreAction -> msg
    , updateUserSettings : XBUserSettings -> msg
    , cellLoaderConfig : CrosstabCellLoader.Config Msg MeasuredAfterQueueCmd
    , toggleHeaderCollapsed : msg
    , shareAndCopyLink : XBProject -> msg
    , setNewBasesOrder :
        { triggeredFrom : Analytics.BaseOrderingChangeMethod
        , shouldFireAnalytics : Bool
        }
        -> List ACrosstab.CrosstabBaseAudience
        -> Int
        -> msg
    }


type alias Configure msg =
    { msg : Msg -> msg
    , ajaxError : Error Never -> msg
    , exportAjaxError : Error ExportError -> msg
    , queryAjaxError : Error XBQueryError -> msg
    , navigateTo : XB2.Router.Route -> msg
    , limitReachedAddingRowOrColumn : Int -> ACrosstab.ErrorAddingRowOrColumn -> msg
    , limitReachedAddingBases : Int -> ACrosstab.ErrorAddingBase -> msg
    , createXBProject : XBProject -> msg
    , updateXBProject : XBProject -> msg
    , setProjectToStore : XBProjectFullyLoaded -> msg
    , saveCopyOfProject :
        { original : XBProjectFullyLoaded
        , copy : XBProject
        , shouldRedirect : Bool
        }
        -> msg
    , openModal : Modal -> msg
    , openSharingModal : XBProject -> msg
    , closeModal : msg
    , createDetailNotification : IconData -> Html Msg -> msg
    , createDetailPersistentNotification : String -> Notification Msg -> msg
    , closeDetailNotification : String -> msg
    , disabledExportsAlert : msg
    , setSharedProjectWarningDismissal : Bool -> msg
    , setDoNotShowAgain : XBData.DoNotShowAgain -> msg
    , fetchManyP2 : List XB2.Share.Store.Platform2.StoreAction -> msg
    , updateUserSettings : XBUserSettings -> msg
    , shareAndCopyLink : XBProject -> msg
    , setNewBasesOrder :
        { triggeredFrom : Analytics.BaseOrderingChangeMethod
        , shouldFireAnalytics : Bool
        }
        -> List ACrosstab.CrosstabBaseAudience
        -> Int
        -> msg
    }


type alias AudienceItemData =
    { items : NonEmpty (Random.Seed -> ( AudienceItem, Random.Seed ))
    , itemsType : AssocSet.Set AttributeBrowser.ItemType
    }


configure : Configure msg -> Config msg
configure rec =
    let
        saveEditedMsg : XBProject -> String -> Msg
        saveEditedMsg project _ =
            SaveEdited project

        saveMsg : Maybe XBProject -> String -> Msg
        saveMsg maybeProject =
            case maybeProject of
                Just project ->
                    case project.shared of
                        MyPrivateCrosstab ->
                            saveEditedMsg project

                        SharedBy _ _ ->
                            \_ -> SaveAsCopy project

                        MySharedCrosstab _ ->
                            saveEditedMsg project

                        SharedByLink ->
                            \_ -> SaveAsCopy project

                Nothing ->
                    OpenSaveAsNew
    in
    { msg = rec.msg
    , ajaxError = rec.ajaxError
    , exportAjaxError = rec.exportAjaxError
    , queryAjaxError = rec.queryAjaxError
    , navigateTo = rec.navigateTo
    , limitReachedAddingRowOrColumn = rec.limitReachedAddingRowOrColumn
    , limitReachedAddingBases = rec.limitReachedAddingBases
    , createXBProject = rec.createXBProject
    , updateXBProject = rec.updateXBProject
    , setProjectToStore = rec.setProjectToStore
    , saveCopyOfProject = rec.saveCopyOfProject
    , openModal = rec.openModal
    , openSharingModal = rec.openSharingModal
    , closeModal = rec.closeModal
    , disabledExportsAlert = rec.disabledExportsAlert
    , createDetailNotification = rec.createDetailNotification
    , createDetailPersistentNotification = rec.createDetailPersistentNotification
    , toggleHeaderCollapsed = rec.msg ToggleHeaderCollapsed
    , closeDetailNotification = rec.closeDetailNotification
    , setDoNotShowAgain = rec.setDoNotShowAgain
    , fetchManyP2 = rec.fetchManyP2
    , updateUserSettings = rec.updateUserSettings
    , shareAndCopyLink = rec.shareAndCopyLink
    , headerConfig =
        { navigateTo = rec.msg << NavigateTo
        , startExport = \maybeProject -> rec.msg <| StartExport Nothing maybeProject
        , save = \maybeProject -> rec.msg << saveMsg maybeProject
        , saveAsNew = rec.msg << OpenSaveAsNew
        , deleteCrosstab = rec.msg << DeleteCrosstab
        , renameCrosstab = rec.msg << RenameCrosstab
        , duplicateCrosstab = rec.msg << DuplicateCrosstab
        , shareProject = rec.msg << OpenShareProjectModal
        , shareAndCopyLink = rec.shareAndCopyLink
        , closeSharedProjectWarning = rec.msg CloseSharedProjectWarning
        , setSharedProjectWarningDismissal = rec.setSharedProjectWarningDismissal
        , noOp = rec.msg NoOp
        , undo = rec.msg <| Edit Undo
        , redo = rec.msg <| Edit Redo
        , toggleHeaderCollapsed = rec.msg ToggleHeaderCollapsed
        }
    , cellLoaderConfig =
        { msg = CellLoaderMsg
        , fetchManyP2 = FetchManyP2
        , queryAjaxError = QueryAjaxError
        , analyticsPlace = Place.CrosstabBuilder
        , getAfterQueueMsg = TrackFullLoadAndProcessCmd
        }
    , setNewBasesOrder = rec.setNewBasesOrder
    }


dndSystem : XB2.Share.DragAndDrop.Move.System Msg Direction MovableItems
dndSystem =
    XB2.Share.DragAndDrop.Move.config
        |> XB2.Share.DragAndDrop.Move.withContainer Common.scrollTableId
        |> XB2.Share.DragAndDrop.Move.withOffset { top = 0, right = 30, bottom = 10, left = 0 }
        |> XB2.Share.DragAndDrop.Move.ghostStyle [ XB2.Share.DragAndDrop.Move.preserveHeight ]
        |> XB2.Share.DragAndDrop.Move.create TableCellDragAndDropMsg


crosstabCellLoader : Glue.Glue Model (CrosstabCellLoader.Model MeasuredAfterQueueCmd) msg msg
crosstabCellLoader =
    Glue.poly
        { get = currentCrosstabData >> .cellLoaderModel
        , set =
            \newModel ->
                updateCrosstabData (\d -> { d | cellLoaderModel = newModel })
        }


type MeasuredAfterQueueCmd
    = ApplyHeatmapCmd Metric
    | ExportTableCmd (Maybe SelectionMap.SelectionMap) (Maybe XBProject)
    | ApplySort SortConfig
    | ApplyResort (NonEmpty SortConfig)


type alias CrosstabData =
    { cellLoaderModel : CrosstabCellLoader.Model MeasuredAfterQueueCmd
    , projectMetadata : XBProjectMetadata
    , originalRows : OriginalOrder
    , originalColumns : OriginalOrder
    , selectionMap : SelectionMap
    }


type MouseDownMovemenet
    = None
    | MouseDown { firstPosition : ( Float, Float ), moved : Bool }


type alias Model =
    { crosstabData : UndoRedo UndoEvent CrosstabData
    , exportWaitingForQuestions :
        Maybe
            { project : Maybe XBProject
            , time : Posix
            , selectionMap : Maybe SelectionMap.SelectionMap
            }
    , -- This should probably be Maybe Http.Error with possible error of export request
      isExporting : Bool

    {- The user is supposed to have _at most one_ dropdown open at a time.
       This representation seems better than having a boolean for each dropdown --
       that would allow for impossible states like

           { baseDropdownOpen = True, metricsDropdownOpen = True }

    -}
    , activeDropdown : Maybe (Dropdown Msg)
    , currentTime : Posix
    , timezone : Zone
    , unsaved : Unsaved
    , autoScroll : Maybe Direction
    , heatmapMetric : Maybe Metric
    , groupingBoxScrollPercentage : Maybe Float
    , browserScrollPercentage : Maybe Float
    , basesPanelWidth : Int
    , scrollingState : ScrollingState
    , isScrollbarHovered : Bool
    , isHeaderCollapsed : Bool
    , tableCellDndModel : XB2.Share.DragAndDrop.Move.Model Direction MovableItems
    , wasSharedProjectWarningDismissed : Bool
    , tableCellsTopOffset : Int
    , drawer : Drawers.Model Msg
    , heatmapScale : Maybe HeatmapScale
    , basesPanelViewport : Maybe Dom.Viewport
    , basesPanelElement : Maybe Dom.Element
    , tableWarning : Maybe (Common.TableWarning Msg)
    , tableHeaderDimensions :
        { minWidth : Int
        , minHeight : Int
        , maxWidth : Int
        , maxHeight : Int
        , resizing :
            Maybe
                { direction : Direction
                , originalWidth : Int
                , originalHeight : Int
                , startPosition : Maybe XB2.Share.DragAndDrop.Move.Position
                }
        }
    , tableSelectionMouseDown : MouseDownMovemenet
    , shouldShowExactRespondentNumber : Bool
    , shouldShowExactUniverseNumber : Bool
    , basesPanelDndModel : Dnd.Model
    , crosstabSearchModel : CrosstabSearchModel

    -- Little submodel used for handling the keyboard accessibility in the bases panel
    , keyboardMovementBasesPanelModel :
        { baseFocused : Maybe Int
        , baseSelectedToMove : Maybe Int
        }
    }


isUnsavedOrEdited : Unsaved -> Bool
isUnsavedOrEdited unsaved =
    case unsaved of
        Unsaved ->
            True

        Saved _ ->
            False

        Edited _ ->
            True

        UnsavedEdited ->
            True


isEdited : Unsaved -> Bool
isEdited unsaved =
    case unsaved of
        Unsaved ->
            False

        Saved _ ->
            False

        Edited _ ->
            True

        UnsavedEdited ->
            True


setAsEdited : Unsaved -> Unsaved
setAsEdited unsaved =
    case unsaved of
        Unsaved ->
            UnsavedEdited

        Saved id ->
            Edited id

        Edited _ ->
            unsaved

        UnsavedEdited ->
            unsaved


getLastOpenedProjectId : Model -> Maybe XBProjectId
getLastOpenedProjectId { unsaved } =
    case unsaved of
        Unsaved ->
            Nothing

        Saved id ->
            Just id

        Edited id ->
            Just id

        UnsavedEdited ->
            Nothing


currentCrosstabData : Model -> CrosstabData
currentCrosstabData model =
    XB2.Share.UndoRedo.current model.crosstabData


currentMetadata : Model -> XBProjectMetadata
currentMetadata model =
    model
        |> currentCrosstabData
        |> .projectMetadata


currentCrosstabFromData : CrosstabData -> AudienceCrosstab
currentCrosstabFromData =
    .cellLoaderModel >> .audienceCrosstab


currentCrosstab : Model -> AudienceCrosstab
currentCrosstab =
    currentCrosstabData >> currentCrosstabFromData


currentOrderBeforeSorting : Model -> { rows : OriginalOrder, columns : OriginalOrder }
currentOrderBeforeSorting model =
    let
        data =
            currentCrosstabData model
    in
    { rows = data.originalRows
    , columns = data.originalColumns
    }


getCrosstabTable : Model -> CrosstabTable
getCrosstabTable =
    currentCrosstab >> ACrosstab.getCrosstab


getActiveWaves : Model -> IdSet WaveCodeTag
getActiveWaves =
    currentCrosstab >> ACrosstab.getActiveWaves


getActiveLocations : Model -> IdSet LocationCodeTag
getActiveLocations =
    currentCrosstab >> ACrosstab.getActiveLocations


getCurrentBaseAudienceIndex : Model -> Int
getCurrentBaseAudienceIndex =
    currentCrosstab >> ACrosstab.getCurrentBaseAudienceIndex


getBaseAudiences : Model -> NonEmpty BaseAudience
getBaseAudiences =
    currentCrosstab >> ACrosstab.getBaseAudiences >> ListZipper.toNonEmpty


getCrosstabBaseAudiences : Model -> NonEmpty ACrosstab.CrosstabBaseAudience
getCrosstabBaseAudiences =
    currentCrosstab >> ACrosstab.getCrosstabBaseAudiences >> ListZipper.toNonEmpty


selectedAnyBaseInCrosstab : Model -> Bool
selectedAnyBaseInCrosstab =
    ACrosstab.anyBaseSelected << currentCrosstab


maxHistoryLimit : Int
maxHistoryLimit =
    20


initialBasesPanelWidth : Int
initialBasesPanelWidth =
    800


scrollToTop : Cmd Msg
scrollToTop =
    Dom.setViewportOf Common.scrollTableId 0 0
        |> Task.attempt
            (always <|
                TableScroll
                    { shouldReloadTable = True
                    , position = ( 0, 0 )
                    }
            )


createSelectionMap : AudienceCrosstab -> SelectionMap
createSelectionMap crosstab =
    let
        rows =
            ACrosstab.getRows crosstab
                |> List.map .isSelected

        columns =
            ACrosstab.getColumns crosstab
                |> List.map .isSelected
    in
    SelectionMap.create rows columns


computeSelectionMap : Model -> Model
computeSelectionMap model =
    { model
        | crosstabData =
            model.crosstabData
                |> XB2.Share.UndoRedo.updateCurrent
                    (\crosstabData ->
                        { crosstabData | selectionMap = createSelectionMap <| currentCrosstabFromData crosstabData }
                    )
    }


init : Posix -> Flags -> ( Model, Cmd Msg )
init currentTime flags =
    let
        audienceCrosstab : AudienceCrosstab
        audienceCrosstab =
            ACrosstab.empty currentTime
                (ACrosstab.crosstabSizeLimit flags.can)
                loadingBoundaries
    in
    { crosstabData =
        XB2.Share.UndoRedo.init maxHistoryLimit
            { cellLoaderModel = CrosstabCellLoader.init audienceCrosstab
            , projectMetadata = XBData.defaultMetadata
            , originalRows = NotSet
            , originalColumns = NotSet
            , selectionMap = createSelectionMap audienceCrosstab
            }
    , isExporting = False
    , exportWaitingForQuestions = Nothing
    , activeDropdown = Nothing
    , currentTime = currentTime
    , timezone = Time.utc
    , unsaved = Unsaved
    , autoScroll = Nothing
    , heatmapMetric = Nothing
    , groupingBoxScrollPercentage = Nothing
    , browserScrollPercentage = Nothing
    , scrollingState = NotScrolling
    , isScrollbarHovered = False
    , isHeaderCollapsed = False
    , basesPanelWidth = initialBasesPanelWidth
    , tableCellDndModel = dndSystem.model
    , basesPanelDndModel = reorderBasesPanelDndSystem.model
    , wasSharedProjectWarningDismissed = False
    , tableCellsTopOffset = 0
    , drawer = Drawers.init
    , heatmapScale = Nothing
    , basesPanelViewport = Nothing
    , basesPanelElement = Nothing
    , tableWarning = Nothing
    , crosstabSearchModel =
        { inputDebouncer =
            Debouncer.toDebouncer
                (Debouncer.debounce (Debouncer.fromSeconds 0.5))
        , term = ""
        , sanitizedTerm = ""
        , searchTopLeftScrollJumps = Nothing
        , inputIsFocused = False
        }
    , tableHeaderDimensions =
        { minWidth = 262
        , minHeight = 150
        , maxWidth = 500
        , maxHeight = 250
        , resizing = Nothing
        }
    , tableSelectionMouseDown = None
    , shouldShowExactRespondentNumber = False
    , shouldShowExactUniverseNumber = False
    , keyboardMovementBasesPanelModel =
        { baseFocused = Nothing
        , baseSelectedToMove = Nothing
        }
    }
        |> Cmd.with (Dom.debouncedScrollEvent Common.scrollTableId)
        |> Cmd.add (Dom.debouncedScrollEvent Common.basesPanelScrollableId)
        |> Cmd.add scrollToTop


getBasesPanelViewport : Config msg -> Cmd msg
getBasesPanelViewport config =
    Dom.getViewportOf Common.basesPanelScrollableId
        |> Task.attempt
            (\result ->
                case result of
                    Ok info ->
                        config.msg <| GotBasesPanelViewport info

                    Err _ ->
                        config.msg NoOp
            )


getBasesPanelElement : Config msg -> Cmd msg
getBasesPanelElement config =
    Dom.getElement Common.basesPanelScrollableId
        |> Task.attempt
            (\result ->
                case result of
                    Ok info ->
                        config.msg <| GotBasesPanelElement info

                    Err _ ->
                        config.msg NoOp
            )


setOrderBeforeSorting : Axis -> OriginalOrder -> CrosstabData -> CrosstabData
setOrderBeforeSorting axis order data =
    case axis of
        Rows ->
            { data | originalRows = order }

        Columns ->
            { data | originalColumns = order }


discardOrderBeforeSorting : Axis -> CrosstabData -> CrosstabData
discardOrderBeforeSorting axis data =
    case axis of
        Rows ->
            { data | originalRows = NotSet }

        Columns ->
            { data | originalColumns = NotSet }


refreshOrderBeforeSorting : Axis -> CrosstabData -> CrosstabData
refreshOrderBeforeSorting axis data =
    case axis of
        Rows ->
            { data | originalRows = OriginalOrder (ACrosstab.getRows <| currentCrosstabFromData data) }

        Columns ->
            { data | originalColumns = OriginalOrder (ACrosstab.getColumns <| currentCrosstabFromData data) }


updateOrderBeforeSorting : Axis -> (AudienceItem -> AudienceItem) -> CrosstabData -> CrosstabData
updateOrderBeforeSorting axis fn data =
    case axis of
        Rows ->
            { data | originalRows = ACrosstab.mapOrder fn data.originalRows }

        Columns ->
            { data | originalColumns = ACrosstab.mapOrder fn data.originalColumns }


{-| If you have sorting applied and eg. move a row to another row,
the sorting is no longer active (but your new row/col order stays - doesn't get
rolled back to how it was before sorting).
-}
discardSorting : Axis -> CrosstabData -> CrosstabData
discardSorting axis data =
    data
        |> updateProjectMetadata
            (setSortForAxis axis
                NoSort
            )
        |> discardOrderBeforeSorting axis


updateTime : Config msg -> Cmd msg
updateTime { msg } =
    Task.map2 SetCurrentTime Time.here Time.now
        |> Task.perform msg


setCollapsedHeader : Config msg -> Bool -> Cmd msg
setCollapsedHeader { msg } shouldCollapseHeader =
    Cmd.perform <| msg <| SetHeaderCollapsed shouldCollapseHeader


operatorToString : Expression.LogicOperator -> String
operatorToString operator =
    case operator of
        Expression.Or ->
            "OR"

        Expression.And ->
            "AND"


itemsFromXBItems :
    Grouping
    -> NonEmpty AttributeBrowser.XBItem
    -> NonEmpty (Random.Seed -> ( AudienceItem, Random.Seed ))
itemsFromXBItems grouping xbItems =
    let
        constructWith : (NonEmpty Expression -> Expression) -> NonEmpty (Random.Seed -> ( AudienceItem, Random.Seed ))
        constructWith combineExpressions =
            let
                expressions =
                    NonemptyList.map .expression xbItems

                captions =
                    NonemptyList.map .caption xbItems
            in
            NonemptyList.singleton <|
                \seed ->
                    AudienceItem.fromCaptionExpression
                        seed
                        (Caption.fromGroupOfCaptions grouping captions)
                        (combineExpressions expressions)
    in
    case grouping of
        Split ->
            NonemptyList.map
                (\item ->
                    \seed ->
                        AudienceItem.fromCaptionExpression
                            seed
                            item.caption
                            item.expression
                )
                xbItems

        Or ->
            constructWith Expression.unionMany

        And ->
            constructWith Expression.intersectionMany


fromQuestionAsAverage : AttributeBrowser.Average -> NonEmpty (Random.Seed -> ( AudienceItem, Random.Seed ))
fromQuestionAsAverage average =
    let
        questionCode : NamespaceAndQuestionCode
        questionCode =
            AttributeBrowser.getAverageQuestionCode average

        maybeDatapointCode : Maybe QuestionAndDatapointCode
        maybeDatapointCode =
            AttributeBrowser.getAverageDatapointCode average
    in
    NonemptyList.singleton <|
        \seed ->
            AudienceItem.fromCaptionAverage
                seed
                (Caption.create
                    { name = "Average"
                    , fullName = "Average"
                    , subtitle = Just <| AttributeBrowser.getAverageQuestionLabel average
                    }
                )
                (maybeDatapointCode
                    |> Maybe.unwrap
                        (Average.AvgWithoutSuffixes questionCode)
                        (Average.AvgWithSuffixes questionCode)
                )



{--

    About how the items are constructed from the attribute browser:
    we received the items from the attribute browser, as a SelectedItems type.
    and when we save it to the crosstab, we need to convert it to AudienceItem.

    The problem with this case is that we lose data information.
    If the user renames the expression, we lose the original names. 
    (This problem is solved by calling the API questions.)

    
                    -----------------
                    |      WC      |
                    -----------------
                        |
                        | SelectedItems
                        v
                    --------------------------------
                    |             XB2              |
                    |  -------------------------   |
                    |  |       Browser         |   |
                    |  -------------------------   |
                    |               |              |
                    |  AudienceItem |              |
                    |               v              |
                    |  -------------------------   |
                    |  |       Details         |   |
                    |  -------------------------   |
                    --------------------------------

--}


itemsFromAttributeBrowser : Grouping -> SelectedItems -> Maybe AudienceItemData
itemsFromAttributeBrowser grouping addedItems =
    let
        allItems : Maybe (NonEmpty (Random.Seed -> ( AudienceItem, Random.Seed )))
        allItems =
            case grouping of
                Split ->
                    NonemptyList.fromList addedItems
                        |> Maybe.map
                            (NonemptyList.concatMap
                                (\item ->
                                    case item of
                                        ModalBrowser.SelectedAttribute attribute ->
                                            AttributeBrowser.getXBItemFromAttribute attribute
                                                |> NonemptyList.singleton
                                                |> itemsFromXBItems grouping

                                        ModalBrowser.SelectedAudience audience ->
                                            { caption =
                                                Caption.create
                                                    { name = audience.name
                                                    , fullName = audience.name
                                                    , subtitle = Nothing
                                                    }
                                            , expression = audience.expression
                                            , itemType = AttributeBrowser.AudienceItem
                                            }
                                                |> NonemptyList.singleton
                                                |> itemsFromXBItems grouping

                                        ModalBrowser.SelectedAverage avg ->
                                            fromQuestionAsAverage avg

                                        SelectedGroup group ->
                                            { caption = ModalBrowser.getCaptionFromGroup group
                                            , expression = ModalBrowser.getExpressionFromGroup group
                                            , itemType = AttributeBrowser.AttributeItem
                                            }
                                                |> NonemptyList.singleton
                                                |> itemsFromXBItems grouping
                                )
                            )

                _ ->
                    addedItems
                        |> List.filterMap
                            (\item ->
                                case item of
                                    ModalBrowser.SelectedAttribute attribute ->
                                        Just <| AttributeBrowser.getXBItemFromAttribute attribute

                                    ModalBrowser.SelectedAudience audience ->
                                        Just
                                            { caption =
                                                Caption.create
                                                    { name = audience.name
                                                    , fullName = audience.name
                                                    , subtitle = Nothing
                                                    }
                                            , expression = audience.expression
                                            , itemType = AttributeBrowser.AudienceItem
                                            }

                                    ModalBrowser.SelectedAverage _ ->
                                        Nothing

                                    SelectedGroup group ->
                                        Just
                                            { caption = ModalBrowser.getCaptionFromGroup group
                                            , expression = ModalBrowser.getExpressionFromGroup group
                                            , itemType = AttributeBrowser.AttributeItem
                                            }
                            )
                        |> NonemptyList.fromList
                        |> Maybe.map (itemsFromXBItems grouping)

        allTypes : AssocSet.Set AttributeBrowser.ItemType
        allTypes =
            List.foldr
                (\item set ->
                    case item of
                        ModalBrowser.SelectedAttribute _ ->
                            AssocSet.insert AttributeBrowser.AttributeItem set

                        ModalBrowser.SelectedAudience _ ->
                            AssocSet.insert AttributeBrowser.AudienceItem set

                        ModalBrowser.SelectedAverage _ ->
                            AssocSet.insert AttributeBrowser.AverageItem set

                        SelectedGroup _ ->
                            AssocSet.insert AttributeBrowser.AttributeItem set
                )
                AssocSet.empty
                addedItems
    in
    allItems
        |> Maybe.map
            (\items ->
                { items = items, itemsType = allTypes }
            )


basesFromAttributeBrowser : Random.Seed -> Grouping -> SelectedItems -> Maybe ( Random.Seed, NonEmpty BaseAudience )
basesFromAttributeBrowser seed grouping addedItems =
    itemsFromAttributeBrowser grouping addedItems
        |> Maybe.andThen
            (.items
                >> NonemptyList.foldr
                    (\toItem ( s, acc ) ->
                        let
                            ( item, newSeed ) =
                                toItem s
                        in
                        case BaseAudience.fromAudienceItem item of
                            Just base ->
                                ( newSeed, base :: acc )

                            Nothing ->
                                ( s, acc )
                    )
                    ( seed, [] )
                >> (\( s, l ) -> NonemptyList.fromList l |> Maybe.map (Tuple.pair s))
            )


captionsFromAttributeBrowser : Grouping -> SelectedItems -> Maybe Caption
captionsFromAttributeBrowser grouping addedItems =
    let
        captions : List Caption
        captions =
            addedItems
                |> List.map
                    (\item ->
                        case item of
                            SelectedAttribute attribute ->
                                .caption <| AttributeBrowser.getXBItemFromAttribute attribute

                            SelectedAudience audience ->
                                Caption.create
                                    { name = audience.name
                                    , fullName = audience.name
                                    , subtitle = Nothing
                                    }

                            SelectedAverage average ->
                                Caption.create
                                    { name = "Average"
                                    , fullName = "Average"
                                    , subtitle = Just <| AttributeBrowser.getAverageQuestionLabel average
                                    }

                            SelectedGroup group ->
                                ModalBrowser.getCaptionFromGroup group
                    )
    in
    NonemptyList.fromList captions
        |> Maybe.map (Caption.fromGroupOfCaptions grouping)


clearWorkspace :
    Config msg
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Maybe XBUserSettings
    -> Model
    -> ( Model, Cmd msg )
clearWorkspace config flags p2Store maybeSettings model =
    let
        commands =
            XB2.Share.UndoRedo.current model.crosstabData
                |> currentCrosstabFromData
                |> ACrosstab.cancelUnfinishedRequests
    in
    ( initWorkspace flags.can Nothing maybeSettings model
    , Cmd.none
    )
        |> updateCellLoader config
            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)


initWorkspace :
    Can
    -> Maybe XBProjectFullyLoaded
    -> Maybe XBUserSettings
    -> Model
    -> Model
initWorkspace can project maybeSettings model =
    let
        audienceCrosstab =
            ACrosstab.init
                XB2.Share.Data.Id.emptySet
                XB2.Share.Data.Id.emptySet
                model.currentTime
                (ACrosstab.crosstabSizeLimit can)
                loadingBoundaries
    in
    { model
        | crosstabData =
            XB2.Share.UndoRedo.init maxHistoryLimit
                { cellLoaderModel = CrosstabCellLoader.init audienceCrosstab
                , projectMetadata = XBData.defaultMetadata
                , originalRows = NotSet
                , originalColumns = NotSet
                , selectionMap = createSelectionMap audienceCrosstab
                }
        , heatmapMetric = Nothing
        , unsaved = Unsaved
        , activeDropdown = Nothing
        , basesPanelWidth = initialBasesPanelWidth
        , wasSharedProjectWarningDismissed =
            let
                noop =
                    model.wasSharedProjectWarningDismissed

                canShow =
                    case maybeSettings of
                        Just { canShowSharedProjectWarning } ->
                            canShowSharedProjectWarning

                        Nothing ->
                            False
            in
            if canShow then
                let
                    allowShowingTheDialog =
                        False
                in
                case model.unsaved of
                    Unsaved ->
                        noop

                    Saved id ->
                        if Maybe.map .id project == Just id then
                            noop

                        else
                            allowShowingTheDialog

                    Edited id ->
                        if Maybe.map .id project == Just id then
                            noop

                        else
                            allowShowingTheDialog

                    UnsavedEdited ->
                        noop

            else
                noop
        , tableWarning = Nothing
        , drawer = Drawers.close
    }


confirmBeforeLeave : Model -> Bool
confirmBeforeLeave model =
    let
        crosstab =
            currentCrosstab model
    in
    isEdited model.unsaved && not (ACrosstab.isEmpty crosstab && ACrosstab.basesNotEdided crosstab)


showUnsavedChangesDialog : msg -> Model -> Maybe (Cmd msg)
showUnsavedChangesDialog action model =
    if confirmBeforeLeave model then
        case model.unsaved of
            Unsaved ->
                Nothing

            Saved _ ->
                Nothing

            Edited _ ->
                Just <| Cmd.perform action

            UnsavedEdited ->
                Just <| Cmd.perform action

    else
        Nothing


saveChangesAndGoBackToProjectList : msg -> Model -> Maybe (Cmd msg)
saveChangesAndGoBackToProjectList action model =
    if confirmBeforeLeave model then
        case model.unsaved of
            Unsaved ->
                Nothing

            Saved _ ->
                Nothing

            Edited _ ->
                Just <| Cmd.perform action

            UnsavedEdited ->
                Just <| Cmd.perform action

    else
        Nothing


openNewProject :
    Config msg
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Maybe XBUserSettings
    -> Model
    -> ( Model, Cmd msg )
openNewProject config flags p2Store maybeSettings model =
    (case model.unsaved of
        UnsavedEdited ->
            ( model, Cmd.none )

        _ ->
            clearWorkspace config flags p2Store maybeSettings model
    )
        |> Glue.updateWith Glue.id (getBasesPanelWidth config.msg)
        |> Cmd.addTrigger (config.fetchManyP2 [ XB2.Share.Store.Platform2.FetchLineage Namespace.coreCode ])


checkIfSharedProjectIsUpToDate : Config msg -> XBProjectFullyLoaded -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
checkIfSharedProjectIsUpToDate config fullProject =
    if XBData.isSharedWithMe fullProject.shared then
        CheckIfSharedProjectIsUpToDate
            { autoUpdate = True
            , currentProject = XBData.fullyLoadedToProject fullProject
            }
            |> config.msg
            |> Cmd.addTrigger

    else
        identity


openSavedProject :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> XBProjectFullyLoaded
    -> Maybe AudienceCrosstab
    -> XB2.Share.Store.Platform2.Store
    -> Maybe XBUserSettings
    -> Model
    -> ( Model, Cmd msg )
openSavedProject config route flags fullProject maybeLoadedCrosstab p2Store maybeSettings model =
    let
        clearModel =
            initWorkspace
                flags.can
                (Just fullProject)
                maybeSettings
                model
                |> markAsSaved fullProject

        cancelRunningRequestsCommands =
            model.crosstabData
                |> XB2.Share.UndoRedo.current
                |> currentCrosstabFromData
                |> ACrosstab.cancelUnfinishedRequests

        initialiasedCrosstabAndCmds =
            case maybeLoadedCrosstab of
                Just crosstab ->
                    Ok ( crosstab, [] )

                Nothing ->
                    ACrosstab.initFromProject
                        model.currentTime
                        (ACrosstab.crosstabSizeLimit flags.can)
                        loadingBoundaries
                        fullProject
    in
    initialiasedCrosstabAndCmds
        |> Result.map
            (Tuple.mapFirst
                (\audienceCrosstab ->
                    { cellLoaderModel = CrosstabCellLoader.init audienceCrosstab
                    , projectMetadata = fullProject.data.metadata
                    , originalRows = NotSet
                    , originalColumns = NotSet
                    , selectionMap = createSelectionMap audienceCrosstab
                    }
                        |> XB2.Share.UndoRedo.init maxHistoryLimit
                )
            )
        |> Result.withDefault ( clearModel.crosstabData, [] )
        |> (\( newCrosstabData, crosstabCommands ) ->
                { clearModel | crosstabData = newCrosstabData }
                    |> Cmd.pure
                    |> updateCellLoader config
                        (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table (crosstabCommands ++ cancelRunningRequestsCommands))
           )
        |> Glue.updateWith Glue.id (getBasesPanelWidth config.msg)
        |> Cmd.add (Cmd.map config.msg scrollToTop)
        -- Delay those to give some time for rendering when page is refreshed on detail view
        |> Glue.updateWith Glue.id
            (\model_ ->
                let
                    lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                    lineageRequests =
                        model_.crosstabData
                            |> XB2.Share.UndoRedo.current
                            |> currentCrosstabFromData
                            |> ACrosstab.namespaceCodesWithBases
                            |> Set.Any.fromList Namespace.codeToString
                            |> Set.Any.toList
                            |> List.map XB2.Share.Store.Platform2.FetchLineage
                in
                ( model_
                , getVisibleCells False model_
                    |> delay 150
                    |> attemptTask
                    |> Cmd.map config.msg
                )
                    |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)
            )
        |> checkIfSharedProjectIsUpToDate config fullProject
        |> scrollToActiveBaseTab config
        |> Glue.updateWith Glue.id (fetchWavesAndLocations config route flags p2Store { updateCurrentHistory = False })


scrollToActiveBaseTab : Config msg -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
scrollToActiveBaseTab config ( model, cmd ) =
    let
        scrollCmd id =
            Task.attempt
                (always <| config.msg NoOp)
                (Dom.scrollToIfNotVisible { scrollParentId = Common.basesPanelScrollableId, elementId = id })

        activeBaseTabId =
            model
                |> getCurrentBaseAudienceIndex
                |> Common.basePanelTabElementId
    in
    ( model, cmd )
        |> Cmd.add (scrollCmd activeBaseTabId)


markAsSaved : { a | id : XBProjectId } -> Model -> Model
markAsSaved project model =
    { model | unsaved = Saved project.id }


projectUpdated : XBProject -> XB2.Router.Route -> Model -> ( Model, Cmd msg )
projectUpdated project route model =
    case route of
        XB2.Router.ProjectList ->
            Cmd.pure model

        XB2.Router.ExternalUrl _ ->
            Cmd.pure model

        XB2.Router.Project maybeProjectId ->
            if maybeProjectId == Just project.id then
                markAsSaved project model
                    |> Cmd.pure
                    |> Glue.trigger Glue.id leaveConfirmCheckCmd

            else
                Cmd.pure model


projectDestroyed :
    Config msg
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> XBStore.Store
    -> XBProjectId
    -> Model
    -> ( Model, Cmd msg )
projectDestroyed config flags p2Store xbStore destroyedId model =
    let
        clear =
            clearWorkspace config flags p2Store (RemoteData.toMaybe xbStore.userSettings)
    in
    case model.unsaved of
        Unsaved ->
            Cmd.pure model

        Saved projectId ->
            if projectId == destroyedId then
                clear model

            else
                Cmd.pure model

        Edited projectId ->
            if projectId == destroyedId then
                clear model

            else
                Cmd.pure model

        UnsavedEdited ->
            Cmd.pure model


type alias MoveParameters =
    { to : Direction
    , at : Int
    , items : MovableItems
    }



-- Update


type EditMsg
    = RemoveBase BaseAudience
    | RemoveBaseAudiences Bool (NonEmpty BaseAudience)
    | Move MoveParameters
    | ApplyLocationsSelection (IdSet LocationCodeTag) Bool
    | ApplyWavesSelection (IdSet WaveCodeTag)
    | RemoveSelectedAudiences Bool (List ( Direction, ACrosstab.Key ))
    | RemoveAudience ( Direction, ACrosstab.Key )
    | DuplicateAudience ( Direction, ACrosstab.Key )
    | RemoveAverageRowOrCol Direction ACrosstab.Key
    | AddFromAttributeBrowser Direction Grouping (Maybe Modal.AttributesModalData) SelectedItems
    | AddBaseAudiences Grouping SelectedItems
    | ReplaceDefaultBase Grouping SelectedItems
    | SetGroupTitle
        Direction
        { oldKey : ACrosstab.Key
        , newItem : AudienceItem
        , expression : Maybe Expression -- avg: Nothing, non-avg: Just
        }
    | SetGroupTitles
        (NonEmpty
            { direction : Direction
            , oldItem : AudienceItem
            , newItem : AudienceItem
            , expression : Maybe Expression -- avg: Nothing, non-avg: Just
            }
        )
    | SaveAffixedGroup Grouping Expression.LogicOperator SelectedItems (List AffixGroupItem) Analytics.AffixedFrom
    | SaveEditedGroup Grouping SelectedItems (List EditGroupItem)
    | SwitchCrosstab
    | Undo
    | Redo
    | AudienceFromSelectionCreated Expression AudienceItem
    | UpdateOrCreateBaseAudiences (NonEmpty BaseAudience)
    | MergeRowOrColumn Grouping (List ACrosstab.Key) (List Direction) Bool (List ( Direction, ACrosstab.Key ))
    | ResetDefaultBaseAudience
    | AffixBaseAudiences (NonEmpty AffixBaseGroupData)
    | EditBaseAudiences (NonEmpty EditBaseGroupData)
    | ApplyMetricsSelection (AssocSet.Set Metric)
    | TransposeMetrics MetricsTransposition
    | ResetSortForAxis Axis -- this makes new commit to undo/redo history
    | ResetSortByName
    | SortBy SortConfig
    | SwitchAverageTimeFormat
    | TableHeaderResizing Direction Int
    | ApplyNewBaseAudiencesOrder
        { triggeredFrom : Analytics.BaseOrderingChangeMethod
        , shouldFireAnalytics : Bool
        }
        (List ACrosstab.CrosstabBaseAudience)
        Int
    | SetFrozenRowsColumns ( Int, Int )
    | SetMinimumSampleSize MinimumSampleSize


type TableSelectMsg
    = SelectRow Events.ShiftState Analytics.ItemSelected ACrosstab.Key
    | SelectColumn Events.ShiftState Analytics.ItemSelected ACrosstab.Key
    | DeselectRow ACrosstab.Key
    | DeselectColumn ACrosstab.Key
    | ClearSelection
    | SelectAllRows
    | SelectAllColumns
    | DeselectAllRows
    | DeselectAllColumns


type Msg
    = NoOp
    | FetchManyP2 (List XB2.Share.Store.Platform2.StoreAction)
    | QueryAjaxError (Error XBQueryError)
    | UselessCheckboxClicked
    | UpdateUserSettings XBUserSettings
    | CellLoaderMsg CrosstabCellLoader.Msg
    | TrackFullLoadAndProcessCmd MeasuredAfterQueueCmd { startTime : Posix, time : Posix }
    | StartExport (Maybe SelectionMap.SelectionMap) (Maybe XBProject)
    | FullLoadAndExport (Maybe SelectionMap.SelectionMap) (Maybe XBProject)
    | Export (Maybe SelectionMap.SelectionMap) (Maybe XBProject) Posix
    | ExportSuccess ExportResponse
    | ExportFailure (Error ExportError)
    | AddProgressToExportDownload Float
    | CloseDetailNotification
    | DownloadFile String
    | NavigateTo XB2.Router.Route
    | OpenMetricsSelection
    | ViewAffixGroupModalFromAttributeBrowser Expression.LogicOperator Grouping Modal.AttributesModalData Analytics.AffixedFrom SelectedItems
    | ViewEditGroupModalFromAttributeBrowser Grouping Modal.AttributesModalData SelectedItems
    | ToggleViewOptionsDropdown
    | ToggleBulkFreezeDropdown
    | ToggleSortByNameDropdown
    | ToggleAllBasesDropdown
    | ToggleFixedPageDropdown (DropdownMenu Msg)
    | GetBasesPanelWidth
    | SetBasesPanelWidth Int
    | CloseDropdown
    | RenameBaseAudience BaseAudience
    | SelectRowOrColumnMouseDown ( Float, Float )
    | SelectAction TableSelectMsg
    | SetCurrentTime Zone Posix
    | OpenSaveAsNew String
    | SaveAsCopy XBProject
    | SaveProjectAsNew String
    | SaveEdited XBProject
    | DeleteCrosstab XBProject
    | DuplicateCrosstab XBProject
    | RenameCrosstab XBProject
    | OpenShareProjectModal XBProject
    | Edit EditMsg
    | TableScroll { shouldReloadTable : Bool, position : ( Int, Int ) }
    | DebounceForSearchTermChange (Debouncer.Msg Msg)
    | ChangeSearchTerm String
    | FilterRowsAndColsThatMatchSearchTerm
    | GoToPreviousSearchResult
    | GoToNextSearchResult
    | AutoScroll Direction
    | ViewGroupExpression ( Direction, ACrosstab.Key )
    | OpenRenameAverageModal Direction ACrosstab.Key
    | OpenSaveAsAudienceModal ( Direction, ACrosstab.Key )
    | OpenAffixTableModalForSingle ( Direction, ACrosstab.Key )
    | OpenEditTableModalForSingle ( Direction, ACrosstab.Key )
      -- If 10s pass, open the modal even if we don't have questions yet
    | OpenEditTableModalForSingleOnceQuestionsAreReadyInStore ( Direction, ACrosstab.Key ) { timeout : Int }
    | OpenSelectedSaveAsAudienceModal
    | OpenSaveBaseInMyAudiencesModal BaseAudience
    | OpenAffixBaseAudienceModalForSelected
    | OpenAffixBaseAudienceModalForSingle BaseAudience
    | OpenEditBaseAudienceModalForSingle BaseAudience
    | OpenEditBaseAudienceModalForSingleOnceQuestionsAreReadyInStore BaseAudience { timeout : Int }
    | OpenAttributeBrowser { affixedFrom : Analytics.AffixedFrom }
    | OpenAttributeBrowserForAddBase
    | OpenAttributeBrowserForReplacingDefaultBase
    | OpenRemoveFromTableConfirmModal
    | OpenRemoveBasesConfirmModal (NonEmpty BaseAudience)
    | AddSelectionAsNewBase
    | MergeSelectedRowOrColum
    | AddAsNewBase ( Direction, ACrosstab.Key )
    | CreateNewBases Grouping (List ACrosstab.Key)
    | OpenHeatmapSelection
    | OpenMinimumSampleSizeModal
    | ApplyHeatmap (Maybe Metric)
    | FullLoadAndApplyHeatmap Metric
    | DownloadDebugDump
    | GoToBaseAtIndex Int
    | ToggleBaseAudience BaseAudience
    | ToggleHeaderCollapsed
    | SetHeaderCollapsed Bool
    | SelectAllBasesInPanel
    | ClearBasesPanelSelection
    | SetVisibleCellsAndTableOffset
        { shouldReloadTable : Bool
        , topOffset : Int
        , visibleCells : VisibleCells
        }
    | CancelFullTableLoad
    | ConfirmCancelFullTableLoad
    | TurnOffViewSettingsAndContinue
    | KeepViewSettingsAndContinue
    | TableCellDragAndDropMsg (XB2.Share.DragAndDrop.Move.Msg Direction MovableItems)
    | ScrollPageUp
    | ScrollPageDown
    | ScrollPageLeft
    | ScrollPageRight
    | HoverScrollbar
    | StopHoveringScrollbar
    | WindowResized
    | CloseSharedProjectWarning
    | ShowSortingDialog SortConfig
    | LoadCellsForSorting SortConfig
    | SharedProjectChanged Bool XBProjectFullyLoaded
    | SetProjectToStore XBProjectFullyLoaded
    | CheckIfSharedProjectIsUpToDate { autoUpdate : Bool, currentProject : XBProject }
    | AnalyticsEvent Analytics.Event
    | RemoveSortingAndCloseModal
    | Resort (NonEmpty SortConfig)
    | DiscardSortForAxis Axis -- this DOES NOT make commit to undo/redo history
    | CancelSortingLoading
    | OpenWavesDrawer
    | OpenLocationsDrawer
    | ScrollBasesPanelRight
    | ScrollBasesPanelLeft
    | ScrollBasesPanelRightAnAmount Float
    | ScrollBasesPanelLeftAnAmount Float
    | GotBasesPanelViewport Dom.Viewport
    | GotBasesPanelElement Dom.Element
    | TabsPanelResized
    | DrawersMsg Drawers.Msg
    | OpenTableWarning
        { warning : Common.TableWarning Msg
        , column : AudienceDefinition
        , row : AudienceDefinition
        }
    | CloseTableWarning
    | TableHeaderResizeStart Direction XB2.Share.DragAndDrop.Move.Position
    | TableHeaderResizeStop
    | ShareProjectByLink XBProject
    | ToggleExactRespondentNumber
    | ToggleExactUniverseNumber
    | OpenReorderBasesModal
    | ReorderBasesPanelDndMsg Dnd.Msg
    | SetBaseIndexFocused (Maybe Int)
    | SetBaseIndexSelectedToMoveWithKeyboard (Maybe Int)
    | SwapBasesOrder Int Int
    | FocusElementById String
    | BlurElementById String
    | ScrollBasedOnRowIndex Int
    | ScrollBasedOnColumnIndex Int
    | SetCrosstabSearchInputFocus Bool


getAfterQueueFinishedMsg : MeasuredAfterQueueCmd -> Msg
getAfterQueueFinishedMsg afterQueueFinishedCmd =
    case afterQueueFinishedCmd of
        ExportTableCmd maybeSelectionMap data ->
            StartExport maybeSelectionMap data

        ApplyHeatmapCmd data ->
            ApplyHeatmap (Just data)

        ApplySort sortConfig ->
            Edit <| SortBy sortConfig

        ApplyResort sortConfigs ->
            Resort sortConfigs


addAudiences : Direction -> MultipleAudiencesInserter
addAudiences direction =
    case direction of
        Row ->
            ACrosstab.addRows

        Column ->
            ACrosstab.addColumns


addAudiencesAtIndex : Direction -> Int -> MultipleAudiencesInserter
addAudiencesAtIndex direction index =
    case direction of
        Row ->
            ACrosstab.addRowsAtIndex index

        Column ->
            ACrosstab.addColumnsAtIndex index


maybeTrack : Flags -> XB2.Router.Route -> Maybe Event -> Cmd msg
maybeTrack flags route maybeEvent =
    maybeEvent
        |> Maybe.map (track flags route)
        |> Maybe.withDefault Cmd.none


track : Flags -> XB2.Router.Route -> Event -> Cmd msg
track flags route event =
    Analytics.trackEvent flags route Place.CrosstabBuilder event


trackMany : Flags -> XB2.Router.Route -> List Event -> Cmd msg
trackMany flags route events =
    Analytics.trackEvents flags route Place.CrosstabBuilder events


closeDrawers : Model -> Model
closeDrawers model =
    { model | drawer = Drawers.close }


closeTableWarning : Model -> Model
closeTableWarning model =
    { model | tableWarning = Nothing }


reopeingProject : Model -> Model
reopeingProject =
    closeDrawers
        >> closeTableWarning
        >> closeDropdown
        >> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll)
        >> updateCrosstabData (updateAudienceCrosstab ACrosstab.clearBasesSelection)


onModalOpened : Model -> Model
onModalOpened =
    closeDrawers


limitReachedAddingRowOrColumn : Config msg -> XB2.Router.Route -> Flags -> ACrosstab.ErrorAddingRowOrColumn -> XB2.Share.Store.Platform2.Store -> Direction -> Model -> Cmd msg
limitReachedAddingRowOrColumn config route flags exceededCounts p2Store direction model =
    Cmd.batch
        [ getAnalyticsCmd flags route LimitReachedAddingRowOrColumn { direction = direction } p2Store model
        , Cmd.perform <|
            config.limitReachedAddingRowOrColumn
                (ACrosstab.getSizeWithTotals <| currentCrosstab model)
                exceededCounts
        ]


limitReachedAddingBase : Config msg -> XB2.Router.Route -> Flags -> ACrosstab.ErrorAddingBase -> XB2.Share.Store.Platform2.Store -> Model -> Cmd msg
limitReachedAddingBase config route flags exceededCounts p2Store model =
    let
        limitReachedMsg =
            config.limitReachedAddingBases
    in
    Cmd.batch
        [ getAnalyticsCmd flags route LimitReachedAddingBase {} p2Store model
        , Cmd.perform <|
            limitReachedMsg
                (ACrosstab.getSizeWithTotals <| currentCrosstab model)
                exceededCounts
        ]


leaveConfirmCheckCmd : Model -> Cmd msg
leaveConfirmCheckCmd model =
    XB2.Share.LeavePageConfirm.setConfirm (confirmBeforeLeave model)


toggleDropdown : Dropdown Msg -> Model -> Model
toggleDropdown newDropDown model =
    { model
        | activeDropdown =
            case ( newDropDown, model.activeDropdown ) of
                ( FixedPageDropdown ddmNew, Just (FixedPageDropdown ddm) ) ->
                    Just <| FixedPageDropdown <| DropdownMenu.toggle ddmNew ddm

                _ ->
                    if model.activeDropdown /= Just newDropDown then
                        Just newDropDown

                    else
                        Nothing
    }


toggleViewOptionsDropdown : Model -> Model
toggleViewOptionsDropdown =
    toggleDropdown ViewOptionsDropdown


toggleBulkFreezeDropdown : Model -> Model
toggleBulkFreezeDropdown =
    toggleDropdown BulkFreezeDropdown


toggleSortByNameDropdown : Model -> Model
toggleSortByNameDropdown =
    toggleDropdown SortByNameDropdown


closeDropdown : Model -> Model
closeDropdown model =
    { model | activeDropdown = Nothing }


toggleHeaderCollapsed : Model -> Model
toggleHeaderCollapsed model =
    { model | isHeaderCollapsed = not model.isHeaderCollapsed }


setCollapsedHeaderAs : Model -> Bool -> Model
setCollapsedHeaderAs model shouldCollapseHeader =
    { model | isHeaderCollapsed = shouldCollapseHeader }


savingAudience : AudienceItem -> Model -> Model
savingAudience item model =
    if ACrosstab.anySelected (currentCrosstab model) then
        model

    else
        let
            key =
                { item = item, isSelected = False }
        in
        model
            |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.selectRow key))
            |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.selectColumn key))


updateAudienceCrosstab : (AudienceCrosstab -> AudienceCrosstab) -> CrosstabData -> CrosstabData
updateAudienceCrosstab fn data =
    { data | cellLoaderModel = CrosstabCellLoader.updateAudienceCrosstab fn data.cellLoaderModel }


setAudienceCrosstab : AudienceCrosstab -> CrosstabData -> CrosstabData
setAudienceCrosstab crosstab =
    updateAudienceCrosstab (always crosstab)


updateProjectMetadata : (XBProjectMetadata -> XBProjectMetadata) -> CrosstabData -> CrosstabData
updateProjectMetadata fn data =
    { data | projectMetadata = fn data.projectMetadata }


updateCellLoader : Config msg -> (CrosstabCellLoader.Model MeasuredAfterQueueCmd -> ( CrosstabCellLoader.Model MeasuredAfterQueueCmd, Cmd Msg )) -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
updateCellLoader config fn =
    Glue.updateWith crosstabCellLoader (fn >> Glue.map config.msg)


onP2StoreChange : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> XB2.Share.Store.Platform2.Msg -> Model -> ( Model, Cmd msg )
onP2StoreChange config route flags newP2Store p2StoreMsg model =
    case p2StoreMsg of
        XB2.Share.Store.Platform2.QuestionFetched _ _ ->
            Cmd.pure model
                |> updateCellLoader config
                    (CrosstabCellLoader.dequeueAndInterpretCommand config.cellLoaderConfig
                        flags
                        newP2Store
                    )
                |> (\( m, cmds ) ->
                        case m.exportWaitingForQuestions of
                            Just { project, time, selectionMap } ->
                                updateExport config route flags selectionMap project time newP2Store m
                                    |> Cmd.add cmds

                            Nothing ->
                                ( m, cmds )
                   )

        XB2.Share.Store.Platform2.QuestionFetchError _ _ _ _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.LocationsFetched _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.LocationsByNamespaceFetched _ _ ->
            Cmd.pure model
                |> Glue.updateWith Glue.id (setDefaultLocationsIfNeeded config route flags newP2Store { updateCurrentHistory = True })

        XB2.Share.Store.Platform2.WavesFetched _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.WavesByNamespaceFetched _ _ ->
            Cmd.pure model
                |> Glue.updateWith Glue.id (setFourMostRecentWavesIfNeeded config route flags newP2Store { updateCurrentHistory = True })

        XB2.Share.Store.Platform2.AudienceRelatedMsg (XB2.Share.Store.Platform2.AudienceWithExpressionCreated _ audience) ->
            let
                newItem : AudienceItem
                newItem =
                    Common.fromAudience (getAudienceFolders newP2Store) audience
                        |> ignoreIndex
            in
            ( model
            , Cmd.batch
                [ Cmd.perform <|
                    config.createDetailNotification P2Icons.audiences
                        (Html.span []
                            [ Html.text ("\"" ++ audience.name ++ "\" saved in My Audiences") ]
                        )
                , Cmd.perform <|
                    config.msg <|
                        Edit <|
                            AudienceFromSelectionCreated audience.expression newItem
                ]
            )

        XB2.Share.Store.Platform2.AudienceRelatedMsg _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.DatasetFoldersFetched _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.DatasetsFetched _ ->
            Cmd.pure model

        XB2.Share.Store.Platform2.LineageFetched _ _ ->
            Cmd.pure model


onP2StoreError : Config msg -> Flags -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
onP2StoreError config flags newP2Store =
    Cmd.pure
        >> updateCellLoader config
            (CrosstabCellLoader.dequeueAndInterpretCommand config.cellLoaderConfig
                flags
                newP2Store
            )


getDatasetCodesFromAudienceExpression : XB2.Share.Store.Platform2.Store -> Expression -> List XB2.Share.Data.Platform2.DatasetCode
getDatasetCodesFromAudienceExpression store expression =
    store.datasetsToNamespaces
        |> RemoteData.unwrap []
            (\xs ->
                XB2.Share.Data.Platform2.datasetsFromExpression xs store.lineages expression
                    |> RemoteData.withDefault []
            )


trackGroupAddedByAppendToBase :
    Flags
    -> XB2.Router.Route
    -> Analytics.Counts
    -> Grouping
    -> Expression
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
trackGroupAddedByAppendToBase flags route counts grouping newExpression p2Store model =
    getAnalyticsCmd flags
        route
        GroupAddedByAffixToBase
        { groupingOperator = grouping
        , newExpression = newExpression
        , counts = counts
        , datasetNames =
            getDatasetCodesFromAudienceExpression p2Store newExpression
                |> getDatasetNamesFromCodes p2Store
        }
        p2Store
        model


trackBaseEdited :
    Flags
    -> XB2.Router.Route
    -> Analytics.Counts
    -> Expression
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
trackBaseEdited flags route counts newExpression p2Store model =
    getAnalyticsCmd flags
        route
        BasesEdited
        { newExpression = newExpression
        , counts = counts
        , datasetNames =
            getDatasetCodesFromAudienceExpression p2Store newExpression
                |> getDatasetNamesFromCodes p2Store
        }
        p2Store
        model


getDatasetNamesFromCodes : XB2.Share.Store.Platform2.Store -> List XB2.Share.Data.Platform2.DatasetCode -> List String
getDatasetNamesFromCodes store =
    Store.getByIds store.datasets >> List.map .name


countAddedItems : SelectedItems -> Analytics.Counts
countAddedItems addedItems =
    addedItems
        |> List.foldl
            (\item counts_ ->
                case item of
                    SelectedAttribute _ ->
                        { counts_
                            | questionsCount = counts_.questionsCount + 1
                            , datapointsCount = counts_.datapointsCount + 1
                        }

                    SelectedAudience _ ->
                        { counts_ | audiencesCount = counts_.audiencesCount + 1 }

                    SelectedAverage _ ->
                        { counts_ | averagesCount = counts_.averagesCount + 1 }

                    SelectedGroup group ->
                        ModalBrowser.groupFoldr
                            (\maybeAttr maybeAudience c ->
                                { c
                                    | questionsCount =
                                        c.questionsCount
                                            |> Maybe.unwrap identity (always <| (+) 1) maybeAttr
                                    , datapointsCount =
                                        c.datapointsCount
                                            |> Maybe.unwrap identity (always <| (+) 1) maybeAttr
                                    , audiencesCount =
                                        c.audiencesCount
                                            |> Maybe.unwrap identity (always <| (+) 1) maybeAudience
                                }
                            )
                            counts_
                            group
            )
            { audiencesCount = 0
            , questionsCount = 0
            , datapointsCount = 0
            , averagesCount = 0
            }


trackGroupsAffixed :
    Flags
    -> XB2.Router.Route
    -> SelectedItems
    -> List AffixGroupItem
    -> Grouping
    -> Expression.LogicOperator
    -> Analytics.AffixedFrom
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
trackGroupsAffixed flags route addedItems groupsToSave grouping operator affixedFrom p2Store model =
    let
        toDestination : List Direction -> Destination
        toDestination directions =
            case directions of
                [ Row ] ->
                    CrosstabRow

                [ Column ] ->
                    CrosstabColumn

                _ ->
                    CrosstabRowAndColumn

        destination : Destination
        destination =
            groupsToSave
                |> List.groupWhile (\g1 g2 -> g1.direction == g2.direction)
                |> List.map (Tuple.first >> .direction)
                |> toDestination

        counts =
            countAddedItems addedItems
    in
    getAnalyticsCmd flags
        route
        GroupsAddedByAffixToTable
        { destination = destination
        , appendedCount = List.length groupsToSave
        , appendingOperator = operator
        , groupingOperator = grouping
        , counts = counts
        , affixedFrom = affixedFrom
        , datasetNames =
            groupsToSave
                |> List.fastConcatMap
                    (\{ newExpression } ->
                        getDatasetCodesFromAudienceExpression p2Store newExpression
                            |> getDatasetNamesFromCodes p2Store
                    )
        }
        p2Store
        model


trackGroupsEdited :
    Flags
    -> XB2.Router.Route
    -> SelectedItems
    -> List EditGroupItem
    -> Grouping
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
trackGroupsEdited flags route addedItems groupsToSave grouping p2Store model =
    let
        toDestination : List Direction -> Destination
        toDestination directions =
            case directions of
                [ Row ] ->
                    CrosstabRow

                [ Column ] ->
                    CrosstabColumn

                _ ->
                    CrosstabRowAndColumn

        destination : Destination
        destination =
            groupsToSave
                |> List.groupWhile (\g1 g2 -> g1.direction == g2.direction)
                |> List.map (Tuple.first >> .direction)
                |> toDestination

        counts =
            countAddedItems addedItems
    in
    getAnalyticsCmd flags
        route
        GroupsAddedByEditToTable
        { destination = destination
        , editedCount = List.length groupsToSave
        , groupingOperator = grouping
        , counts = counts
        , datasetNames =
            groupsToSave
                |> List.fastConcatMap
                    (\{ newExpression } ->
                        getDatasetCodesFromAudienceExpression p2Store newExpression
                            |> getDatasetNamesFromCodes p2Store
                    )
        }
        p2Store
        model


trackGroupsAddedAsNew :
    Flags
    -> XB2.Router.Route
    -> SelectedItems
    -> Direction
    -> Grouping
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
trackGroupsAddedAsNew flags route addedItems direction grouping p2Store model =
    let
        toDestination : Direction -> Destination
        toDestination directions =
            case directions of
                Row ->
                    CrosstabRow

                Column ->
                    CrosstabColumn
    in
    getAnalyticsCmd flags
        route
        GroupAddedAsNew
        { destination = toDestination direction
        , groupingOperator = grouping
        , counts = countAddedItems addedItems
        , appendedCount = List.length addedItems
        , datasetNames =
            List.fastConcatMap
                (\selectedItem ->
                    (case selectedItem of
                        SelectedAttribute attribute ->
                            let
                                item : AttributeBrowser.XBItem
                                item =
                                    AttributeBrowser.getXBItemFromAttribute attribute
                            in
                            getDatasetCodesFromAudienceExpression p2Store item.expression

                        SelectedAudience audience ->
                            getDatasetCodesFromAudienceExpression p2Store audience.expression

                        SelectedAverage average ->
                            datasetCodesFromNamespaceCodes p2Store [ AttributeBrowser.getAverageQuestion average |> .namespaceCode ]

                        SelectedGroup group ->
                            ModalBrowser.groupFoldr
                                (\maybeAttr maybeAudience ->
                                    Maybe.unwrap identity
                                        (AttributeBrowser.getXBItemFromAttribute
                                            >> .expression
                                            >> getDatasetCodesFromAudienceExpression p2Store
                                            >> (++)
                                        )
                                        maybeAttr
                                        >> Maybe.unwrap identity
                                            (.expression
                                                >> getDatasetCodesFromAudienceExpression p2Store
                                                >> (++)
                                            )
                                            maybeAudience
                                )
                                []
                                group
                    )
                        |> getDatasetNamesFromCodes p2Store
                )
                addedItems
        }
        p2Store
        model


trackItemMoved : Flags -> XB2.Router.Route -> Direction -> Direction -> XB2.Share.Store.Platform2.Store -> Model -> Cmd msg
trackItemMoved flags route from to p2Store model =
    getAnalyticsCmd flags
        route
        ItemMoved
        { movedFrom = directionToDestination from
        , movedTo = directionToDestination to
        }
        p2Store
        model


{-| Some usages of AudienceItems don't need the index. Get rid of the need for the integer!
-}
ignoreIndex : (Random.Seed -> ( AudienceItem, Random.Seed )) -> AudienceItem
ignoreIndex toItem =
    toItem (Random.initialSeed 1)
        |> Tuple.first


addAudienceItemsUndoEvent : Grouping -> List a -> UndoEvent
addAudienceItemsUndoEvent grouping items =
    case grouping of
        Split ->
            UndoEvent.CreateAudienceItems (List.length items)

        Or ->
            UndoEvent.CreateAudienceItems 1

        And ->
            UndoEvent.CreateAudienceItems 1


type Origin
    = UndoRedo
    | NoOrigin


confirmDialogIfAppliedViewSettings_ : Bool -> Config msg -> Origin -> { closeDialogIfNeeded : Bool } -> Model -> ( Model, Cmd msg )
confirmDialogIfAppliedViewSettings_ addingNewBases config origin { closeDialogIfNeeded } model =
    let
        sort =
            getCurrentSort model

        isSorting : Bool
        isSorting =
            Sort.isSorting sort.rows
                || Sort.isSorting sort.columns

        isHeatmap : Bool
        isHeatmap =
            model.heatmapMetric /= Nothing

        currentCrosstab_ =
            currentCrosstab model

        getNotDoneCountFor getCount sorting =
            Sort.sortingAudience sorting
                |> Maybe.map (\id -> getCount id currentCrosstab_)
                |> Maybe.withDefault 0

        modalOptions =
            { isSorting = isSorting, isHeatmap = isHeatmap }

        initModal () =
            modalOptions
                |> (if addingNewBases then
                        Modal.initConfirmAddNewBaseWithViewSettings

                    else
                        Modal.initConfirmActionWithViewSettings
                   )

        closeDialogTrigger =
            if closeDialogIfNeeded then
                Cmd.addTrigger config.closeModal

            else
                identity
    in
    if origin == UndoRedo || (model.heatmapMetric == Nothing && isSorting == False) then
        Cmd.pure model
            |> closeDialogTrigger

    else if ACrosstab.isAnyNotAskedOrLoading (currentCrosstab model) then
        let
            sortingNotLoadedCount : Int
            sortingNotLoadedCount =
                getNotDoneCountFor ACrosstab.notDoneForColumnCount sort.rows
                    + getNotDoneCountFor ACrosstab.notDoneForRowCount sort.columns
        in
        if isSorting && (sortingNotLoadedCount == 0) && not isHeatmap then
            Cmd.withTrigger (config.msg KeepViewSettingsAndContinue) model
                |> closeDialogTrigger

        else
            Cmd.withTrigger (config.openModal <| initModal ()) model

    else
        Cmd.withTrigger (config.msg KeepViewSettingsAndContinue) model
            |> closeDialogTrigger


confirmDialogIfAppliedViewSettings : Config msg -> Origin -> { closeDialogIfNeeded : Bool } -> Model -> ( Model, Cmd msg )
confirmDialogIfAppliedViewSettings =
    confirmDialogIfAppliedViewSettings_ False


confirmDialogIfAddingNewBases : Config msg -> Origin -> { closeDialogIfNeeded : Bool } -> Model -> ( Model, Cmd msg )
confirmDialogIfAddingNewBases =
    confirmDialogIfAppliedViewSettings_ True


trackItemsAdded : Flags -> XB2.Router.Route -> Grouping -> Destination -> AddedHow -> SelectedItems -> Model -> XB2.Share.Store.Platform2.Store -> Cmd msg
trackItemsAdded flags route grouping destination addedHow items model store =
    let
        cellsCount : Int
        cellsCount =
            model |> currentCrosstab |> ACrosstab.getSizeWithoutTotals

        itemsType =
            itemsFromAttributeBrowser grouping items
                |> Maybe.map .itemsType

        itemTypeForAnalytics =
            itemsType
                |> Maybe.map NotificationText.typesToString
                |> Maybe.withDefault ""

        getQuestionsFromCodes : List NamespaceAndQuestionCode -> List Question
        getQuestionsFromCodes questionCodes =
            questionCodes
                |> Maybe.traverse (\code -> XB2.Share.Store.Platform2.getQuestionMaybe code store)
                |> Maybe.withDefault []

        eventFromAttribute : XB2.Share.Data.Platform2.Attribute -> Event
        eventFromAttribute attribute =
            let
                item : AttributeBrowser.XBItem
                item =
                    AttributeBrowser.getXBItemFromAttribute attribute
            in
            ItemAdded
                { destination = destination
                , addedHow = addedHow
                , itemType = itemTypeForAnalytics
                , audienceId = Nothing
                , cellsCount = cellsCount
                , questions = getQuestionsFromCodes <| Expression.getQuestionCodes item.expression
                , datapointCodes = Expression.getQuestionAndDatapointCodes item.expression
                , itemLabel = Caption.getFullName item.caption
                , datasetNames =
                    getDatasetCodesFromAudienceExpression store item.expression
                        |> getDatasetNamesFromCodes store
                }

        eventFromAudience : Audience.Audience -> Event
        eventFromAudience audience =
            ItemAdded
                { destination = destination
                , addedHow = addedHow
                , itemType = itemTypeForAnalytics
                , audienceId = Just audience.id
                , cellsCount = cellsCount
                , questions = getQuestionsFromCodes <| Expression.getQuestionCodes audience.expression
                , datapointCodes = Expression.getQuestionAndDatapointCodes audience.expression
                , itemLabel = audience.name
                , datasetNames =
                    getDatasetCodesFromAudienceExpression store audience.expression
                        |> getDatasetNamesFromCodes store
                }

        trackEvents : List Event
        trackEvents =
            items
                |> List.fastConcatMap
                    (\selectedItem ->
                        case selectedItem of
                            SelectedAttribute attribute ->
                                [ eventFromAttribute attribute ]

                            SelectedAudience audience ->
                                [ eventFromAudience audience ]

                            SelectedAverage average ->
                                [ AverageAdded
                                    { destination = destination
                                    , addedHow = AddedAsNew
                                    , cellsCount = cellsCount
                                    , average = average
                                    , datasetNames =
                                        datasetCodesFromNamespaceCodes store [ AttributeBrowser.getAverageQuestion average |> .namespaceCode ]
                                            |> getDatasetNamesFromCodes store
                                    }
                                ]

                            SelectedGroup group ->
                                ModalBrowser.groupFoldr
                                    (\maybeAttr maybeAudience ->
                                        Maybe.unwrap identity (eventFromAttribute >> (::)) maybeAttr
                                            >> Maybe.unwrap identity (eventFromAudience >> (::)) maybeAudience
                                    )
                                    []
                                    group
                    )
    in
    trackMany flags route trackEvents


trackHeaderCollapsed :
    Bool
    -> XB2.Router.Route
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> ( Model, Cmd msg )
trackHeaderCollapsed isCollapsed route flags p2Store model =
    let
        analyticsCmd : Cmd msg
        analyticsCmd =
            getAnalyticsCmd flags
                route
                HeaderCollapsed
                { isHeaderCollapsed = isCollapsed
                }
                p2Store
                model
    in
    model |> Cmd.with analyticsCmd


addAudienceItems :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> Grouping
    -> Direction
    -> Int
    -> XB2.Share.Store.Platform2.Store
    -> MultipleAudiencesInserter
    -> Model
    -> Maybe Modal.AttributesModalData
    -> AudienceItemData
    -> ( Model, Cmd msg )
addAudienceItems config route flags grouping direction size p2Store addAudienceToCrosstab model attributeBrowserModal { items, itemsType } =
    let
        audiences :
            List
                { key : { isSelected : Bool, item : Random.Seed -> ( AudienceItem, Random.Seed ) }
                , value : String
                }
        audiences =
            NonemptyList.toList items
                |> List.map
                    (\item ->
                        { key = { item = item, isSelected = False }
                        , value = ""
                        }
                    )

        items_ : List (Random.Seed -> ( ACrosstab.Key, Random.Seed ))
        items_ =
            audiences
                |> List.map
                    (\{ key } seed ->
                        key.item seed
                            |> Tuple.mapFirst
                                (\item ->
                                    { isSelected = key.isSelected
                                    , item = item
                                    }
                                )
                    )

        differentDataset : Bool
        differentDataset =
            case attributeBrowserModal of
                Just { browserModel } ->
                    ModalBrowser.getModalWarning browserModel == Just ModalBrowser.PossibleIncompatibilities

                Nothing ->
                    False
    in
    case
        ACrosstab.addAudiences
            addAudienceToCrosstab
            items_
            (currentCrosstab model)
    of
        Ok ( newCrosstab, reloadCellsCommands ) ->
            let
                undoEvent : UndoEvent
                undoEvent =
                    addAudienceItemsUndoEvent grouping audiences

                newModel =
                    { model
                        | crosstabData =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.commit undoEvent (setAudienceCrosstab newCrosstab)
                    }
            in
            newModel
                |> Cmd.with
                    (notification config P2Icons.tick <|
                        NotificationText.created
                            direction
                            { differentDataset = differentDataset }
                            size
                            grouping
                            itemsType
                    )
                |> updateCellLoader config
                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
                |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config NoOrigin { closeDialogIfNeeded = True })

        Err exceededCounts ->
            ( model, limitReachedAddingRowOrColumn config route flags exceededCounts p2Store direction model )


addAudienceItemsForMerge :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> Grouping
    -> Direction
    -> Int
    -> XB2.Share.Store.Platform2.Store
    -> MultipleAudiencesInserter
    -> Model
    -> Maybe Modal.AttributesModalData
    -> Bool
    -> List ( Direction, ACrosstab.Key )
    -> AudienceItemData
    -> ( Model, Cmd msg )
addAudienceItemsForMerge config route flags grouping direction size p2Store addAudienceToCrosstab model attributeBrowserModal asNew allSelected { items, itemsType } =
    let
        audiences :
            List
                { key : { isSelected : Bool, item : Random.Seed -> ( AudienceItem, Random.Seed ) }
                , value : String
                }
        audiences =
            NonemptyList.toList items
                |> List.map
                    (\item ->
                        { key = { item = item, isSelected = False }
                        , value = ""
                        }
                    )

        items_ : List (Random.Seed -> ( ACrosstab.Key, Random.Seed ))
        items_ =
            audiences
                |> List.map
                    (\{ key } seed ->
                        key.item seed
                            |> Tuple.mapFirst
                                (\item ->
                                    { isSelected = True
                                    , item = item
                                    }
                                )
                    )

        differentDataset : Bool
        differentDataset =
            case attributeBrowserModal of
                Just { browserModel } ->
                    ModalBrowser.getModalWarning browserModel == Just ModalBrowser.PossibleIncompatibilities

                Nothing ->
                    False
    in
    case
        ACrosstab.addAudiences
            addAudienceToCrosstab
            items_
            (currentCrosstab model)
    of
        Ok ( newCrosstab, reloadCellsCommands ) ->
            let
                --In this part we remove the selected audiences, we need to do it here because of the Undo
                undoEvent : UndoEvent
                undoEvent =
                    UndoEvent.MergeAudienceItems

                modelRemove : ( AudienceCrosstab, List ACrosstab.Command )
                modelRemove =
                    if asNew then
                        ( newCrosstab, reloadCellsCommands )

                    else
                        ACrosstab.removeAudiences allSelected newCrosstab

                ( removedAudienceCrosstab, removedCommands ) =
                    modelRemove

                combinedCommands : List ACrosstab.Command
                combinedCommands =
                    if asNew then
                        reloadCellsCommands

                    else
                        reloadCellsCommands ++ removedCommands

                newModel : Model
                newModel =
                    { model
                        | crosstabData =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.commit undoEvent (setAudienceCrosstab removedAudienceCrosstab)
                    }
            in
            newModel
                |> Cmd.with
                    (notification config P2Icons.tick <|
                        NotificationText.created
                            direction
                            { differentDataset = differentDataset }
                            size
                            grouping
                            itemsType
                    )
                |> updateCellLoader config
                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table combinedCommands)
                |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config NoOrigin { closeDialogIfNeeded = True })

        Err exceededCounts ->
            ( model, limitReachedAddingRowOrColumn config route flags exceededCounts p2Store direction model )


directionToDestination : Direction -> Destination
directionToDestination direction =
    case direction of
        Row ->
            CrosstabRow

        Column ->
            CrosstabColumn


getAllSelected : Model -> List ( Direction, ACrosstab.Key )
getAllSelected model =
    let
        crosstab =
            currentCrosstab model
    in
    List.map (Tuple.pair Row) (ACrosstab.getSelectedRows crosstab)
        ++ List.map (Tuple.pair Column) (ACrosstab.getSelectedColumns crosstab)


getAnalyticsEvent :
    (Analytics.EventParams extraParams -> Event)
    -> extraParams
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Event
getAnalyticsEvent paramsToEvent extraParams p2Store model =
    let
        ( waves, locations ) =
            wavesAndLocations p2Store model
    in
    paramsToEvent
        { bases =
            getBaseAudiences model
                |> NonemptyList.map Analytics.prepareBaseForTracking
                |> NonemptyList.toList
        , crosstab = getCrosstabTable model
        , locations = locations
        , waves = waves
        , extraParams = extraParams
        }


getAnalyticsCmd :
    Flags
    -> XB2.Router.Route
    -> (Analytics.EventParams extraParams -> Event)
    -> extraParams
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> Cmd msg
getAnalyticsCmd flags route paramsToEvent extraParams p2Store model =
    track flags route <| getAnalyticsEvent paramsToEvent extraParams p2Store model


notification : Config msg -> IconData -> String -> Cmd msg
notification { createDetailNotification } iconData notificationText =
    Cmd.perform <|
        createDetailNotification iconData
            (Html.span [] [ Html.text notificationText ])


resolveAppliedBaseAudience :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> Place
    -> BaseAudience
    -> Model
    -> Maybe (Result ACrosstab.ErrorAddingBase ( AudienceCrosstab, List ACrosstab.Command ))
    -> ( Model, Cmd msg )
resolveAppliedBaseAudience config route flags p2Store place newBase model maybeResult =
    maybeResult
        |> Maybe.map
            (\result ->
                case result of
                    Ok ( newCrosstab, reloadCellsCommands ) ->
                        let
                            newModel =
                                { model
                                    | crosstabData =
                                        model.crosstabData
                                            |> XB2.Share.UndoRedo.commit
                                                UndoEvent.ApplyBaseAudience
                                                (setAudienceCrosstab newCrosstab)
                                }

                            notificationString =
                                "Created Base audience"

                            lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                            lineageRequests =
                                newBase
                                    |> BaseAudience.getExpression
                                    |> Expression.getNamespaceCodes
                                    |> Set.Any.fromList Namespace.codeToString
                                    |> Set.Any.toList
                                    |> List.map XB2.Share.Store.Platform2.FetchLineage
                        in
                        newModel
                            |> Cmd.with (getAnalyticsCmd flags route BaseAudienceApplied { place = place } p2Store newModel)
                            |> updateCellLoader config (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
                            |> Cmd.add (notification config P2Icons.tick notificationString)
                            |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)

                    Err exceededCounts ->
                        {- Shouldn't be possible because we're already
                           checking when clicking the "Add new base +"
                           button, but I don't want to silently
                           Maybe.withDefault if we ever get here...

                           Better safe than sorry?
                        -}
                        ( model, limitReachedAddingBase config route flags exceededCounts p2Store model )
            )
        |> Maybe.withDefault ( model, Cmd.none )
        |> Tuple.mapFirst (updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll))
        |> Glue.updateWith Glue.id (closeDropdown >> Cmd.pure)
        |> Glue.updateWith Glue.id (confirmDialogIfAddingNewBases config NoOrigin { closeDialogIfNeeded = False })


applyBaseAudiences : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> Place -> Random.Seed -> NonEmpty BaseAudience -> Model -> ( Model, Cmd msg )
applyBaseAudiences config route flags p2Store place seed bases model =
    case
        ACrosstab.addBases
            seed
            bases
            (currentCrosstab model)
    of
        Ok ( newCrosstab, reloadCellsCommands ) ->
            let
                newModel =
                    { model
                        | crosstabData =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.commit
                                    UndoEvent.ApplyBaseAudience
                                    (setAudienceCrosstab newCrosstab)
                        , activeDropdown = Nothing
                    }

                lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                lineageRequests =
                    bases
                        |> NonemptyList.toList
                        |> List.fastConcatMap (BaseAudience.getExpression >> Expression.getNamespaceCodes)
                        |> Set.Any.fromList Namespace.codeToString
                        |> Set.Any.toList
                        |> List.map XB2.Share.Store.Platform2.FetchLineage
            in
            newModel
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll)
                |> Cmd.with (getAnalyticsCmd flags route BaseAudienceApplied { place = place } p2Store newModel)
                |> updateCellLoader config
                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
                |> Glue.updateWith Glue.id (confirmDialogIfAddingNewBases config NoOrigin { closeDialogIfNeeded = True })
                |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)

        Err exceededCounts ->
            ( model, limitReachedAddingBase config route flags exceededCounts p2Store model )


replaceDefaultBaseAudience :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> XB2.Share.Store.Platform2.Store
    -> BaseAudience
    -> Place
    -> Model
    -> ( Model, Cmd msg )
replaceDefaultBaseAudience config route flags p2Store newBase place model =
    ACrosstab.replaceDefaultBaseAudience newBase (currentCrosstab model)
        |> Maybe.map Ok
        |> resolveAppliedBaseAudience config route flags p2Store place newBase model


removeAudiences : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> List ( Direction, ACrosstab.Key ) -> Model -> ( Model, Cmd msg )
removeAudiences config route flags p2Store items model =
    let
        ( deletedRowsCount, deletedColumnsCount ) =
            List.partition (Tuple.first >> (==) Row) items
                |> Tuple.mapBoth List.length List.length

        analyticsCmd : Cmd msg
        analyticsCmd =
            getAnalyticsCmd flags
                route
                ItemsDeleted
                { deletedColumns = deletedColumnsCount
                , deletedRows = deletedRowsCount
                }
                p2Store
                model

        itemsDeleted =
            List.length items

        notificationCmd =
            notification config P2Icons.trash <|
                String.join " "
                    [ String.fromInt itemsDeleted
                    , XB2.Share.Plural.fromInt itemsDeleted "item"
                    , "deleted"
                    ]

        undoEvent =
            UndoEvent.DeleteAudienceItems itemsDeleted
    in
    (\data ->
        ACrosstab.removeAudiences items (currentCrosstabFromData data)
            |> Tuple.mapFirst
                (\crosstab ->
                    let
                        maybeEmptiedCrosstab : Maybe AudienceCrosstab
                        maybeEmptiedCrosstab =
                            if ACrosstab.isEmpty crosstab then
                                crosstab
                                    |> ACrosstab.setActiveLocations XB2.Share.Data.Id.emptySet
                                    |> Maybe.andThen (Tuple.first >> ACrosstab.setActiveWaves XB2.Share.Data.Id.emptySet)
                                    |> Maybe.map Tuple.first

                            else
                                Nothing
                    in
                    data
                        |> setAudienceCrosstab (Maybe.withDefault crosstab maybeEmptiedCrosstab)
                        |> refreshOrderBeforeSorting Rows
                        |> refreshOrderBeforeSorting Columns
                )
    )
        |> XB2.Share.UndoRedo.Step.andThen
            (\commands data ->
                ( data
                , Cmd.pure model
                    |> updateCellLoader config
                        (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)
                )
            )
        |> XB2.Share.UndoRedo.Step.map
            (Cmd.add analyticsCmd
                >> Cmd.add notificationCmd
            )
        |> XB2.Share.UndoRedo.Step.runAndCommit undoEvent model.crosstabData
        |> (\( data, ( model_, cmds ) ) ->
                ( { model_ | crosstabData = data }, cmds )
           )


discardSortingIf : Bool -> Axis -> Model -> Model
discardSortingIf condition axis =
    if condition then
        updateCrosstabData (discardSorting axis)

    else
        identity


applyWavesSelection :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> IdSet WaveCodeTag
    -> XB2.Share.Store.Platform2.Store
    -> { updateCurrentHistory : Bool }
    -> Model
    -> ( Model, Cmd msg )
applyWavesSelection config route flags selectedWaveCodes p2Store { updateCurrentHistory } model =
    let
        closeEverything modelMsg =
            Tuple.mapFirst (\m -> { m | drawer = Drawers.close }) modelMsg
                |> Cmd.addTrigger config.closeModal
    in
    currentCrosstab model
        |> ACrosstab.setActiveWaves selectedWaveCodes
        |> Maybe.map
            (\( newCrosstab, reloadCellsCommands ) ->
                let
                    newModel =
                        { model
                            | crosstabData =
                                if updateCurrentHistory then
                                    model.crosstabData
                                        |> XB2.Share.UndoRedo.updateCurrent
                                            (setAudienceCrosstab newCrosstab)

                                else
                                    model.crosstabData
                                        |> XB2.Share.UndoRedo.commit
                                            UndoEvent.ApplyWavesSelection
                                            (setAudienceCrosstab newCrosstab)
                        }
                in
                newModel
                    -- TODO: schedule resort after finishing all new requests, OR alternatively reset the sort?
                    |> Cmd.with (getAnalyticsCmd flags route WavesChanged {} p2Store newModel)
                    -- TODO: Investigate this deeply. SetVisibleCellsAndTableOffset cmd allows us to reload the cells already, so do we actually need to call updateCellLoader to fire the commands here?
                    -- TODO: There's a double API trigger here.
                    |> updateCellLoader config (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
            )
        |> Maybe.withDefault ( model, Cmd.none )
        |> closeEverything
        |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config NoOrigin { closeDialogIfNeeded = False })
        |> updateCellLoader config CrosstabCellLoader.resetRetries


applyLocationsSelection :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> IdSet LocationCodeTag
    -> XB2.Share.Store.Platform2.Store
    -> { updateCurrentHistory : Bool }
    -> Model
    -> ( Model, Cmd msg )
applyLocationsSelection config route flags selectedLocationCodes p2Store { updateCurrentHistory } model =
    let
        closeEverything modelMsg =
            Tuple.mapFirst (\m -> { m | drawer = Drawers.close }) modelMsg
                |> Cmd.addTrigger config.closeModal
    in
    currentCrosstab model
        |> ACrosstab.setActiveLocations selectedLocationCodes
        |> Maybe.map
            (\( newCrosstab, reloadCellsCommands ) ->
                let
                    newModel =
                        { model
                            | crosstabData =
                                if updateCurrentHistory then
                                    model.crosstabData
                                        |> XB2.Share.UndoRedo.updateCurrent
                                            (setAudienceCrosstab newCrosstab)

                                else
                                    model.crosstabData
                                        |> XB2.Share.UndoRedo.commit
                                            UndoEvent.ApplyLocationsSelection
                                            (setAudienceCrosstab newCrosstab)
                        }
                in
                newModel
                    -- TODO: schedule resort after finishing all new requests, OR alternatively reset the sort?
                    |> Cmd.with (getAnalyticsCmd flags route LocationsChanged {} p2Store newModel)
                    -- TODO: Investigate this deeply. SetVisibleCellsAndTableOffset cmd allows us to reload the cells already, so do we actually need to call updateCellLoader to fire the commands here?
                    -- TODO: There's a double API trigger here.
                    |> updateCellLoader config (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
            )
        |> Maybe.withDefault ( model, Cmd.none )
        |> closeEverything
        |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config NoOrigin { closeDialogIfNeeded = False })
        |> updateCellLoader config CrosstabCellLoader.resetRetries


setFourMostRecentWavesIfNeeded : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> { updateCurrentHistory : Bool } -> Model -> ( Model, Cmd msg )
setFourMostRecentWavesIfNeeded config route flags p2Store updateCurrentHistory model =
    let
        crosstab =
            currentCrosstab model
    in
    if Set.Any.isEmpty (ACrosstab.getActiveWaves crosstab) then
        let
            namespaceCodes =
                currentCrosstab model
                    |> ACrosstab.namespaceCodes

            wavesForNamespaces =
                XB2.Share.Store.Platform2.getAllWavesIfLoaded namespaceCodes p2Store
        in
        case wavesForNamespaces of
            RemoteData.Success waves ->
                applyWavesSelection config
                    route
                    flags
                    (XB2.Share.Data.Labels.getFourMostRecentWaveCodes waves)
                    p2Store
                    updateCurrentHistory
                    model

            _ ->
                Cmd.pure model

    else
        Cmd.pure model


setDefaultLocationsIfNeeded : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> { updateCurrentHistory : Bool } -> Model -> ( Model, Cmd msg )
setDefaultLocationsIfNeeded config route flags p2Store updateCurrentHistory model =
    let
        crosstab =
            currentCrosstab model
    in
    if Set.Any.isEmpty (ACrosstab.getActiveLocations crosstab) then
        let
            namespaceCodes =
                currentCrosstab model
                    |> ACrosstab.namespaceCodes

            locationsForNamespaces =
                XB2.Share.Store.Platform2.getAllLocationsIfLoaded namespaceCodes p2Store
        in
        case locationsForNamespaces of
            RemoteData.Success locations ->
                applyLocationsSelection config
                    route
                    flags
                    (defaultLocations locations)
                    p2Store
                    updateCurrentHistory
                    model

            _ ->
                Cmd.pure model

    else
        Cmd.pure model


fetchWavesAndLocations : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> { updateCurrentHistory : Bool } -> Model -> ( Model, Cmd msg )
fetchWavesAndLocations config route flags p2Store updateCurrentHistory model =
    let
        namespaceCodes =
            currentCrosstab model
                |> ACrosstab.namespaceCodes
    in
    Cmd.pure model
        |> Glue.updateWith Glue.id (setFourMostRecentWavesIfNeeded config route flags p2Store updateCurrentHistory)
        |> Glue.updateWith Glue.id (setDefaultLocationsIfNeeded config route flags p2Store updateCurrentHistory)
        |> Cmd.addTrigger
            (config.fetchManyP2
                (List.map XB2.Share.Store.Platform2.FetchWavesByNamespace namespaceCodes)
            )
        |> Cmd.addTrigger
            (config.fetchManyP2
                (List.map XB2.Share.Store.Platform2.FetchLocationsByNamespace namespaceCodes)
            )


updateEdit :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> EditMsg
    -> Model
    -> ( Model, Cmd msg )
updateEdit config route flags xbStore p2Store editMsg model =
    case editMsg of
        Move { to, at, items } ->
            let
                sort : Sort
                sort =
                    getCurrentSort model

                isMovingToSameAxis =
                    NonemptyList.all (\( from, _ ) -> from == to) items

                isMovingSorted =
                    NonemptyList.any
                        (\( from, _ ) ->
                            Sort.isSorting (Sort.forAxis (directionToAxis from) sort)
                        )
                        items

                moveFunction =
                    case to of
                        Row ->
                            ACrosstab.moveItemsToRowIndex

                        Column ->
                            ACrosstab.moveItemsToColumnIndex
            in
            case moveFunction at items (currentCrosstab model) of
                Ok ( newCrosstab, reloadCellsCommands ) ->
                    let
                        undoEvent =
                            UndoEvent.MoveAudienceItem

                        toAxis =
                            directionToAxis to

                        isMovingToSorted =
                            Sort.isSorting (Sort.forAxis toAxis sort)

                        isMovingSortedToSameAxis =
                            isMovingToSameAxis && isMovingSorted

                        notificationCopy : String
                        notificationCopy =
                            (NonemptyList.length items
                                |> String.fromInt
                            )
                                ++ XB2.Share.Plural.fromInt (NonemptyList.length items) " item"
                                ++ " moved"

                        newModel =
                            { model
                                | crosstabData =
                                    XB2.Share.UndoRedo.commit undoEvent
                                        (setAudienceCrosstab newCrosstab)
                                        model.crosstabData
                            }
                    in
                    ( newModel
                        |> discardSortingIf (isMovingSortedToSameAxis || isMovingToSorted) toAxis
                    , trackItemMoved flags route Row to p2Store newModel
                    )
                        |> Cmd.add (notification config P2Icons.tick notificationCopy)
                        |> updateCellLoader config
                            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)

                Err exceededCounts ->
                    ( model, limitReachedAddingRowOrColumn config route flags exceededCounts p2Store to model )

        ApplyNewBaseAudiencesOrder { triggeredFrom, shouldFireAnalytics } baseAudiences indexToBeActive ->
            case NonemptyList.fromList baseAudiences of
                Just baseAudiences_ ->
                    { model
                        | crosstabData =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.commit
                                    UndoEvent.ReorderBaseAudiences
                                    (updateAudienceCrosstab
                                        (ACrosstab.setBasesOrder baseAudiences_
                                            indexToBeActive
                                        )
                                    )
                    }
                        |> Cmd.pure
                        |> Cmd.addTrigger config.closeModal
                        |> Cmd.addIf shouldFireAnalytics
                            (track flags route <|
                                getAnalyticsEvent
                                    BaseOrderChanged
                                    { changedHow =
                                        triggeredFrom
                                    }
                                    p2Store
                                    model
                            )

                Nothing ->
                    Cmd.pure model

        UpdateOrCreateBaseAudiences bases ->
            applyBaseAudiences
                config
                route
                flags
                p2Store
                Place.CrosstabBuilder
                (ACrosstab.getSeed <| currentCrosstab model)
                bases
                model
                |> Cmd.addTrigger config.closeModal

        MergeRowOrColumn grouping items directions asNew allSelected ->
            let
                --we use this hasRow to know if a row is implicated in the merge, because Row has priority to be created
                hasRow : List Direction -> Bool
                hasRow listDirections =
                    List.member Row listDirections

                directionToTake : Direction
                directionToTake =
                    if hasRow directions then
                        Row

                    else
                        Column

                traductorItem : AudienceItem -> AudienceItemData
                traductorItem audience =
                    { items = NonemptyList.singleton <| AudienceItem.generateNewId audience
                    , itemsType = AssocSet.singleton AttributeBrowser.AudienceItem
                    }

                --logic of AsNew, if True we deselect the selected
                processAllSelected : Model -> ( Model, Cmd msg )
                processAllSelected modelProcess =
                    if asNew then
                        let
                            handleSelection : Direction -> ACrosstab.Key -> Model -> ( Model, Cmd msg )
                            handleSelection direction key m =
                                case direction of
                                    Row ->
                                        updateCrosstabData (updateAudienceCrosstab (ACrosstab.deselectRow key)) m
                                            |> Cmd.pure

                                    Column ->
                                        updateCrosstabData (updateAudienceCrosstab (ACrosstab.deselectColumn key)) m
                                            |> Cmd.pure
                        in
                        List.foldl
                            (\( direction, key ) ( currentModel, currentCmd ) ->
                                handleSelection direction key currentModel
                                    |> (\( newModelProcess, cmd ) ->
                                            ( newModelProcess, Cmd.batch [ currentCmd, cmd ] )
                                       )
                            )
                            ( modelProcess, Cmd.none )
                            allSelected

                    else
                        ( modelProcess, Cmd.none )

                --Here we create the merge with all selected
                constructTheMergeWith :
                    (NonEmpty Expression -> Expression)
                    -> ( Model, Cmd msg )
                constructTheMergeWith combineExpressions =
                    items
                        |> List.filterMap
                            (\key ->
                                case AudienceItem.getDefinition key.item of
                                    Average _ ->
                                        Nothing

                                    Expression expr ->
                                        Just ( AudienceItem.getCaption key.item, expr )
                            )
                        |> NonemptyList.fromList
                        |> Maybe.map
                            (\nonemptyList ->
                                let
                                    seed =
                                        ACrosstab.getSeed <| currentCrosstab model

                                    captions =
                                        NonemptyList.map Tuple.first nonemptyList

                                    expressions =
                                        NonemptyList.map Tuple.second nonemptyList
                                in
                                if NonemptyList.length nonemptyList == 1 then
                                    AudienceItem.fromCaptionExpression
                                        seed
                                        (Caption.fromGroupOfCaptions grouping captions)
                                        (NonemptyList.head expressions)

                                else
                                    AudienceItem.fromCaptionExpression
                                        seed
                                        (Caption.fromGroupOfCaptions grouping captions)
                                        (combineExpressions expressions)
                            )
                        |> Maybe.map
                            (\( combinedItem, _ ) ->
                                addAudienceItemsForMerge config
                                    route
                                    flags
                                    grouping
                                    directionToTake
                                    1
                                    p2Store
                                    (addAudiencesAtIndex directionToTake 0)
                                    model
                                    Nothing
                                    asNew
                                    allSelected
                                    (traductorItem combinedItem)
                            )
                        |> Maybe.withDefault
                            (Cmd.pure model)

                mergeCmds : Cmd msg -> Cmd msg -> Cmd msg
                mergeCmds cmd1 cmd2 =
                    Cmd.batch [ cmd1, cmd2 ]

                splitModelAndCmds : ( Model, Cmd msg ) -> Model
                splitModelAndCmds ( modelsplit, _ ) =
                    modelsplit

                newModelWithRemovedOrDeselectAudiences : ( Model, Cmd msg )
                newModelWithRemovedOrDeselectAudiences =
                    let
                        newModelWithMerge : ( Model, Cmd msg )
                        newModelWithMerge =
                            case grouping of
                                Split ->
                                    --We don't take in count the Split in the Merge
                                    ( model, Cmd.none )

                                Or ->
                                    constructTheMergeWith Expression.unionMany

                                And ->
                                    constructTheMergeWith Expression.intersectionMany

                        ( modelForProcessing, cmdsFromProcessAllSelected ) =
                            processAllSelected (splitModelAndCmds newModelWithMerge)

                        ( _, originalCmds ) =
                            newModelWithMerge

                        mergedCmds =
                            mergeCmds originalCmds cmdsFromProcessAllSelected
                    in
                    ( modelForProcessing, mergedCmds )
            in
            newModelWithRemovedOrDeselectAudiences
                |> Cmd.add
                    (track flags route <|
                        getAnalyticsEvent
                            RowsOrColumnsMerged
                            { mergedHow =
                                if asNew then
                                    Analytics.AsNew

                                else
                                    Analytics.Merged
                            }
                            p2Store
                            model
                    )

        ResetDefaultBaseAudience ->
            case ACrosstab.resetDefaultBaseAudience (currentCrosstab model) of
                Just ( newCrosstab, reloadCellsCommands ) ->
                    { model
                        | crosstabData =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.commit
                                    UndoEvent.ResetDefaultBaseAudience
                                    (setAudienceCrosstab newCrosstab)
                    }
                        |> Cmd.pure
                        |> updateCellLoader config
                            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)

                Nothing ->
                    Cmd.pure model

        AffixBaseAudiences affixBaseGroupDataList ->
            NonemptyList.foldr
                (\{ baseAudience, newCaption, newExpression, grouping, addedItems } ( model_, cmds ) ->
                    let
                        newBase =
                            baseAudience
                                |> BaseAudience.setCaption newCaption
                                |> BaseAudience.setExpression newExpression
                    in
                    case
                        ACrosstab.replaceBaseAudience
                            newBase
                            (currentCrosstab model_)
                    of
                        Just ( newCrosstab, reloadCellsCommands ) ->
                            let
                                counts =
                                    countAddedItems addedItems

                                newModel =
                                    { model_
                                        | crosstabData =
                                            XB2.Share.UndoRedo.commit
                                                UndoEvent.ApplyBaseAudience
                                                (setAudienceCrosstab newCrosstab)
                                                model_.crosstabData
                                    }
                            in
                            ( newModel, cmds )
                                |> Cmd.add (trackGroupAddedByAppendToBase flags route counts grouping newExpression p2Store model)
                                |> updateCellLoader config
                                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)

                        Nothing ->
                            ( model_, cmds )
                )
                (Cmd.pure model)
                affixBaseGroupDataList
                |> Tuple.mapFirst (updateCrosstabData (updateAudienceCrosstab ACrosstab.clearBasesSelection))
                |> Cmd.addTrigger config.closeModal

        EditBaseAudiences editBaseGroupDataList ->
            NonemptyList.foldr
                (\{ baseAudience, newCaption, newExpression, addedItems } ( model_, cmds ) ->
                    let
                        newBase =
                            baseAudience
                                |> BaseAudience.setCaption newCaption
                                |> BaseAudience.setExpression newExpression
                    in
                    case
                        ACrosstab.replaceBaseAudience
                            newBase
                            (currentCrosstab model_)
                    of
                        Just ( newCrosstab, reloadCellsCommands ) ->
                            let
                                counts =
                                    countAddedItems addedItems

                                newModel =
                                    { model_
                                        | crosstabData =
                                            XB2.Share.UndoRedo.commit
                                                UndoEvent.ApplyBaseAudience
                                                (setAudienceCrosstab newCrosstab)
                                                model_.crosstabData
                                    }
                            in
                            ( newModel, cmds )
                                |> Cmd.add (trackBaseEdited flags route counts newExpression p2Store model)
                                |> updateCellLoader config
                                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)
                                |> Cmd.add (notification config P2Icons.tick <| NotificationText.edited "base audience")

                        Nothing ->
                            ( model_, cmds )
                )
                (Cmd.pure model)
                editBaseGroupDataList
                |> Tuple.mapFirst (updateCrosstabData (updateAudienceCrosstab ACrosstab.clearBasesSelection))
                |> Cmd.addTrigger config.closeModal

        RemoveBase base ->
            { model
                | crosstabData =
                    model.crosstabData
                        |> XB2.Share.UndoRedo.commit
                            UndoEvent.RemoveBaseAudience
                            (updateAudienceCrosstab (ACrosstab.removeBase base))
            }
                |> closeDropdown
                |> Cmd.pure

        RemoveBaseAudiences doNotShowAgain bases ->
            let
                triggerDoNotShowAgainUpdate =
                    xbStore.userSettings
                        |> RemoteData.map
                            (\settings ->
                                if doNotShowAgain && XBData.canShow XBData.DeleteBasesModal settings then
                                    Cmd.addTrigger (config.setDoNotShowAgain XBData.DeleteBasesModal)

                                else
                                    identity
                            )
                        |> RemoteData.withDefault identity

                analyticsCmd : Cmd msg
                analyticsCmd =
                    getAnalyticsCmd flags
                        route
                        BasesDeleted
                        { basesCount = NonemptyList.length bases }
                        p2Store
                        model
            in
            { model
                | crosstabData =
                    model.crosstabData
                        |> XB2.Share.UndoRedo.commit
                            UndoEvent.RemoveSelectedBaseAudiences
                            (updateAudienceCrosstab (ACrosstab.removeBases bases))
            }
                |> Cmd.with analyticsCmd
                |> triggerDoNotShowAgainUpdate
                |> Cmd.addTrigger config.closeModal

        ApplyLocationsSelection selectedLocationCodes _ ->
            applyLocationsSelection config route flags selectedLocationCodes p2Store { updateCurrentHistory = False } model

        ApplyWavesSelection selectedWaveCodes ->
            applyWavesSelection config route flags selectedWaveCodes p2Store { updateCurrentHistory = False } model

        RemoveSelectedAudiences doNotShowAgain allSelected ->
            let
                ( selectedRows, selectedColumns ) =
                    allSelected
                        |> List.partition (Tuple.first >> (==) Row)

                selectedRowIds : List AudienceItemId
                selectedRowIds =
                    selectedRows
                        |> List.map (\( _, key ) -> AudienceItem.getId key.item)

                selectedColumnIds : List AudienceItemId
                selectedColumnIds =
                    selectedColumns
                        |> List.map (\( _, key ) -> AudienceItem.getId key.item)

                sort : Sort
                sort =
                    getCurrentSort model

                axisToDiscardSorting : Maybe Axis
                axisToDiscardSorting =
                    case ( Sort.sortingAudience sort.rows, Sort.sortingAudience sort.columns ) of
                        ( Just _, Just _ ) ->
                            {- Shouldn't be possible, we are supposed to disable
                               an OtherAxis sort in one axis if adding it to
                               another axis. Let's not do anything here ¯\_(ツ)_/¯
                            -}
                            Nothing

                        ( Just id, Nothing ) ->
                            if List.member id selectedColumnIds then
                                Just Columns

                            else
                                Nothing

                        ( Nothing, Just id ) ->
                            if List.member id selectedRowIds then
                                Just Rows

                            else
                                Nothing

                        ( Nothing, Nothing ) ->
                            Nothing

                possiblyResetSort : Model -> Model
                possiblyResetSort model_ =
                    case axisToDiscardSorting of
                        Nothing ->
                            model_

                        Just axis ->
                            model_
                                |> updateCrosstabData (discardSorting axis)

                triggerDoNotShowAgainUpdate =
                    xbStore.userSettings
                        |> RemoteData.map
                            (\settings ->
                                if doNotShowAgain && XBData.canShow XBData.DeleteRowsColumnsModal settings then
                                    Cmd.addTrigger (config.setDoNotShowAgain XBData.DeleteRowsColumnsModal)

                                else
                                    identity
                            )
                        |> RemoteData.withDefault identity
            in
            model
                |> removeAudiences config route flags p2Store allSelected
                |> Glue.updateWith Glue.id
                    (updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll) >> Cmd.pure)
                |> Tuple.mapFirst possiblyResetSort
                |> Cmd.addTrigger config.closeModal
                |> triggerDoNotShowAgainUpdate

        DuplicateAudience ( direction, key ) ->
            let
                duplicatedItem : AudienceItemData
                duplicatedItem =
                    { items = NonemptyList.singleton <| AudienceItem.generateNewId key.item
                    , itemsType = AssocSet.singleton AttributeBrowser.AudienceItem
                    }

                getListFn : AudienceCrosstab -> List ACrosstab.Key
                getListFn =
                    case direction of
                        Row ->
                            ACrosstab.getRows

                        Column ->
                            ACrosstab.getColumns

                index : Int
                index =
                    XB2.Share.UndoRedo.current model.crosstabData
                        |> currentCrosstabFromData
                        |> getListFn
                        |> List.elemIndex key
                        |> Maybe.withDefault 0
            in
            addAudienceItems config route flags Split direction 1 p2Store (addAudiencesAtIndex direction <| index + 1) model Nothing duplicatedItem
                |> Cmd.add
                    (getAnalyticsCmd flags
                        route
                        Analytics.GroupDuplicated
                        { caption = key.item |> AudienceItem.getCaption
                        , expression = key.item |> AudienceItem.getDefinition
                        }
                        p2Store
                        model
                    )

        RemoveAudience toRemove ->
            let
                sort : Sort
                sort =
                    getCurrentSort model

                direction : Direction
                direction =
                    Tuple.first toRemove

                idToRemove : AudienceItemId
                idToRemove =
                    toRemove
                        |> Tuple.second
                        |> .item
                        |> AudienceItem.getId

                axisToDiscardSorting : Maybe Axis
                axisToDiscardSorting =
                    case ( direction, Sort.sortingAudience sort.rows, Sort.sortingAudience sort.columns ) of
                        ( _, Just _, Just _ ) ->
                            -- Shouldn't be possible
                            Nothing

                        ( Column, Just id, _ ) ->
                            if id == idToRemove then
                                Just Rows

                            else
                                Nothing

                        ( Row, _, Just id ) ->
                            if id == idToRemove then
                                Just Columns

                            else
                                Nothing

                        _ ->
                            Nothing

                possiblyResetSort : Model -> Model
                possiblyResetSort model_ =
                    case axisToDiscardSorting of
                        Nothing ->
                            model_

                        Just axis ->
                            model_
                                |> updateCrosstabData (discardSorting axis)
            in
            model
                |> removeAudiences config route flags p2Store [ toRemove ]
                |> Tuple.mapFirst possiblyResetSort
                |> Tuple.mapFirst closeDropdown

        RemoveAverageRowOrCol direction key ->
            let
                sort : Sort
                sort =
                    getCurrentSort model

                otherAxis : Axis
                otherAxis =
                    Sort.otherAxis <| directionToAxis direction

                isRemovingSortingItem : Bool
                isRemovingSortingItem =
                    Sort.sortingAudience (Sort.forAxis otherAxis sort) == Just (AudienceItem.getId key.item)

                maybeDiscardSort : Model -> Model
                maybeDiscardSort =
                    if isRemovingSortingItem then
                        discardSortForAxis otherAxis

                    else
                        identity
            in
            (\data ->
                currentCrosstabFromData data
                    |> ACrosstab.removeAudiences [ ( direction, key ) ]
                    |> Tuple.mapFirst (\ac -> data |> setAudienceCrosstab ac)
            )
                |> XB2.Share.UndoRedo.Step.andThen
                    (\commands data ->
                        ( data
                        , Cmd.pure model
                            |> updateCellLoader config
                                (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)
                        )
                    )
                |> XB2.Share.UndoRedo.Step.map (Cmd.add (notification config P2Icons.trash "1 item deleted"))
                |> XB2.Share.UndoRedo.Step.runAndCommit UndoEvent.DeleteAverageItem model.crosstabData
                |> (\( data, ( newModel, cmds ) ) ->
                        ( { newModel | crosstabData = data }
                            |> maybeDiscardSort
                            |> closeDropdown
                        , cmds
                        )
                   )

        AddFromAttributeBrowser direction grouping attributeBrowser addedItems ->
            let
                axis : Axis
                axis =
                    directionToAxis direction

                size : Int
                size =
                    List.length addedItems

                analyticsAddedAsNew : Cmd msg
                analyticsAddedAsNew =
                    trackGroupsAddedAsNew flags route addedItems direction grouping p2Store model

                lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                lineageRequests =
                    addedItems
                        |> List.fastConcatMap ModalBrowser.selectedItemNamespaceCodes
                        |> Set.Any.fromList Namespace.codeToString
                        |> Set.Any.toList
                        |> List.map XB2.Share.Store.Platform2.FetchLineage
            in
            itemsFromAttributeBrowser grouping addedItems
                |> Maybe.unwrap (Cmd.pure model)
                    (addAudienceItems config route flags grouping direction size p2Store (addAudiences direction) model attributeBrowser
                        >> Tuple.mapFirst (updateCrosstabData (refreshOrderBeforeSorting axis))
                    )
                |> Cmd.add analyticsAddedAsNew
                |> Cmd.add (trackItemsAdded flags route grouping (directionToDestination direction) AddedAsNew addedItems model p2Store)
                |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)
                |> Glue.updateWith Glue.id (fetchWavesAndLocations config route flags p2Store { updateCurrentHistory = True })

        AddBaseAudiences grouping attributes ->
            case basesFromAttributeBrowser (ACrosstab.getSeed <| currentCrosstab model) grouping attributes of
                Just ( seed, bases ) ->
                    applyBaseAudiences
                        config
                        route
                        flags
                        p2Store
                        Place.CrosstabBuilder
                        seed
                        bases
                        model

                Nothing ->
                    Cmd.pure model

        ReplaceDefaultBase grouping attributes ->
            case basesFromAttributeBrowser (ACrosstab.getSeed <| currentCrosstab model) grouping attributes of
                Just ( _, ( base, _ ) ) ->
                    replaceDefaultBaseAudience
                        config
                        route
                        flags
                        p2Store
                        base
                        Place.CrosstabBuilderBase
                        model
                        |> Cmd.addTrigger config.closeModal

                _ ->
                    Cmd.withTrigger config.closeModal model

        AudienceFromSelectionCreated expression newItem ->
            let
                maybeDataFn : Maybe (CrosstabData -> ( CrosstabData, ( Model, Cmd msg ) ))
                maybeDataFn =
                    if selectedAnyBaseInCrosstab model then
                        let
                            crosstab =
                                currentCrosstab model
                        in
                        ACrosstab.getSelectedBases crosstab
                            |> Maybe.map NonemptyList.head
                            |> Maybe.map
                                (\base ->
                                    let
                                        newBase =
                                            base
                                                |> BaseAudience.setCaption (AudienceItem.getCaption newItem)
                                                |> BaseAudience.setExpression expression
                                    in
                                    \data ->
                                        currentCrosstabFromData data
                                            |> ACrosstab.clearBasesSelection
                                            |> ACrosstab.replaceBaseAudience newBase
                                            |> Maybe.map
                                                (Tuple.mapBoth
                                                    (\ac -> setAudienceCrosstab ac data)
                                                    (\cmds ->
                                                        Cmd.pure model
                                                            |> updateCellLoader config
                                                                (CrosstabCellLoader.interpretCommands
                                                                    config.cellLoaderConfig
                                                                    flags
                                                                    p2Store
                                                                    AudienceIntersect.Table
                                                                    cmds
                                                                )
                                                    )
                                                )
                                            |> Maybe.withDefault
                                                ( setAudienceCrosstab (ACrosstab.clearBasesSelection crosstab) data
                                                , Cmd.pure model
                                                )
                                )

                    else
                        getAllSelected model
                            |> List.head
                            |> Maybe.map
                                (\( direction, { item } as oldKey ) cData ->
                                    ( updateAudienceCrosstab
                                        (ACrosstab.replaceKey direction
                                            oldKey
                                            { oldKey
                                                | item =
                                                    item
                                                        |> AudienceItem.setCaption (AudienceItem.getCaption newItem)
                                                        |> AudienceItem.setExpression expression
                                            }
                                            >> ACrosstab.deselectAll
                                        )
                                        cData
                                    , Cmd.pure model
                                    )
                                )
            in
            case maybeDataFn of
                Just dataFn ->
                    let
                        lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                        lineageRequests =
                            expression
                                |> Expression.getNamespaceCodes
                                |> Set.Any.fromList Namespace.codeToString
                                |> Set.Any.toList
                                |> List.map XB2.Share.Store.Platform2.FetchLineage
                    in
                    dataFn
                        |> XB2.Share.UndoRedo.Step.runAndCommit UndoEvent.SaveAsAudience model.crosstabData
                        |> (\( data, ( newModel, cmds ) ) ->
                                ( { newModel | crosstabData = data }, cmds )
                           )
                        |> Cmd.addTrigger config.closeModal
                        |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)

                Nothing ->
                    model
                        |> Cmd.withTrigger config.closeModal

        SetGroupTitle direction { oldKey, newItem, expression } ->
            let
                datapointsCount =
                    expression
                        |> Maybe.map (Expression.foldr ((+) << NonemptyList.length << .questionAndDatapointCodes) 0)

                commands =
                    Cmd.batch
                        [ getAnalyticsCmd flags
                            route
                            GroupRenamed
                            { oldName = Caption.toString <| AudienceItem.getCaption oldKey.item
                            , newName = Caption.getName <| AudienceItem.getCaption newItem
                            , datapointsCount = datapointsCount
                            }
                            p2Store
                            model
                        , Cmd.perform config.closeModal
                        ]

                axis =
                    directionToAxis direction

                sort =
                    getCurrentSort model
                        |> Sort.forAxis axis

                maybeResort : ( Model, Cmd msg ) -> ( Model, Cmd msg )
                maybeResort =
                    if Sort.isSortingByName sort then
                        -- needs to happen atomically, not inside a Cmd, because of the unit test...
                        Tuple.mapFirst <| updateResort { axis = axis, mode = sort }

                    else
                        identity

                newKey : ACrosstab.Key
                newKey =
                    { oldKey | item = newItem }
            in
            (\data ->
                ( data
                    |> updateAudienceCrosstab (ACrosstab.replaceKey direction oldKey newKey)
                    |> updateOrderBeforeSorting axis
                        (\item ->
                            if item == oldKey.item then
                                newItem

                            else
                                item
                        )
                , commands
                )
            )
                |> XB2.Share.UndoRedo.Step.runAndCommit UndoEvent.SetGroupTitle model.crosstabData
                |> Tuple.mapFirst (\data -> { model | crosstabData = data })
                |> maybeResort

        SetGroupTitles newTitles ->
            let
                hasRenamedRows =
                    NonemptyList.any (\{ direction } -> direction == Row) newTitles

                hasRenamedColumns =
                    NonemptyList.any (\{ direction } -> direction == Column) newTitles

                sort =
                    getCurrentSort model

                maybeResort : ( Model, Cmd msg ) -> ( Model, Cmd msg )
                maybeResort modelAndCmd =
                    -- these subsequent updates need to happen atomically, not inside a Cmd, because of the unit test...
                    modelAndCmd
                        |> (if hasRenamedRows && Sort.isSortingByName sort.rows then
                                Tuple.mapFirst (updateResort { axis = Rows, mode = sort.rows })

                            else
                                identity
                           )
                        |> (if hasRenamedColumns && Sort.isSortingByName sort.columns then
                                Tuple.mapFirst <| updateResort { axis = Columns, mode = sort.columns }

                            else
                                identity
                           )
            in
            NonemptyList.foldr
                (\{ direction, oldItem, newItem, expression } ( data, cmds ) ->
                    ( data
                        |> updateAudienceCrosstab (ACrosstab.replaceItem direction oldItem newItem)
                        |> updateOrderBeforeSorting (directionToAxis direction)
                            (\item ->
                                if item == oldItem then
                                    newItem

                                else
                                    item
                            )
                    , Cmd.batch
                        [ getAnalyticsCmd flags
                            route
                            GroupRenamed
                            { oldName = Caption.toString <| AudienceItem.getCaption oldItem
                            , newName = Caption.getName <| AudienceItem.getCaption newItem
                            , datapointsCount =
                                expression
                                    |> Maybe.map (Expression.foldr ((+) << NonemptyList.length << .questionAndDatapointCodes) 0)
                            }
                            p2Store
                            model
                        , cmds
                        ]
                    )
                )
                ( XB2.Share.UndoRedo.current model.crosstabData
                , Cmd.perform config.closeModal
                )
                newTitles
                |> always
                |> XB2.Share.UndoRedo.Step.runAndCommit UndoEvent.SetGroupTitle model.crosstabData
                |> Tuple.mapFirst (\data -> { model | crosstabData = data })
                |> maybeResort

        SaveAffixedGroup grouping operator addedItems groupsToSave affixedFrom ->
            let
                names : List String
                names =
                    addedItems
                        |> List.filterMap
                            (\item ->
                                case item of
                                    SelectedAttribute attribute ->
                                        XB2.Share.Store.Platform2.getDatapointMaybe
                                            p2Store
                                            (XB2.Share.Data.Labels.addNamespaceToQuestionCode attribute.namespaceCode attribute.codes.questionCode)
                                            (XB2.Share.Data.Labels.addQuestionToShortDatapointCode attribute.codes.questionCode attribute.codes.datapointCode)
                                            |> Maybe.map .name

                                    SelectedAudience audience ->
                                        Just audience.name

                                    SelectedAverage average ->
                                        Just <| AttributeBrowser.getAverageQuestionLabel average

                                    SelectedGroup group ->
                                        ModalBrowser.getCaptionFromGroup group
                                            |> Caption.getFullName
                                            |> Just
                            )
                        |> List.map (String.ellipsis 30)

                notificationText counts =
                    names
                        |> NotificationText.affixed counts.affixedRows counts.affixedColumns

                toDestination : List Direction -> Destination
                toDestination directions =
                    case directions of
                        [ Row ] ->
                            CrosstabRow

                        [ Column ] ->
                            CrosstabColumn

                        _ ->
                            CrosstabRowAndColumn

                destination : Destination
                destination =
                    groupsToSave
                        |> List.groupWhile (\g1 g2 -> g1.direction == g2.direction)
                        |> List.map (Tuple.first >> .direction)
                        |> toDestination

                handleCommands { commands, counts } crosstab =
                    ( crosstab
                    , Cmd.pure model
                        |> updateCellLoader config
                            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)
                        |> Cmd.add (trackGroupsAffixed flags route addedItems groupsToSave grouping operator affixedFrom p2Store model)
                        |> Cmd.add (trackItemsAdded flags route grouping destination AddedByAppend addedItems model p2Store)
                        |> Cmd.addTrigger config.closeModal
                        |> Cmd.add (notification config P2Icons.tick <| notificationText counts)
                    )

                undoEvent =
                    UndoEvent.AppendToAudienceItems (List.length groupsToSave)

                lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                lineageRequests =
                    addedItems
                        |> List.fastConcatMap ModalBrowser.selectedItemNamespaceCodes
                        |> Set.Any.fromList Namespace.codeToString
                        |> Set.Any.toList
                        |> List.map XB2.Share.Store.Platform2.FetchLineage
            in
            (\data ->
                currentCrosstabFromData data
                    |> ACrosstab.affixGroups groupsToSave
                    |> Tuple.mapFirst (\ac -> setAudienceCrosstab ac data)
            )
                |> XB2.Share.UndoRedo.Step.andThen handleCommands
                |> XB2.Share.UndoRedo.Step.runAndCommit undoEvent model.crosstabData
                |> (\( data, ( model_, cmds ) ) ->
                        ( { model_ | crosstabData = data }, cmds )
                   )
                |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config NoOrigin { closeDialogIfNeeded = False })
                |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)
                |> Glue.updateWith Glue.id (fetchWavesAndLocations config route flags p2Store { updateCurrentHistory = True })

        SaveEditedGroup grouping addedItems groupsToSave ->
            let
                notificationText =
                    NotificationText.edited "audience"

                handleCommands { commands } crosstab =
                    ( crosstab
                    , Cmd.pure model
                        |> updateCellLoader config
                            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)
                        |> Cmd.add (trackGroupsEdited flags route addedItems groupsToSave grouping p2Store model)
                        |> Cmd.addTrigger config.closeModal
                        |> Cmd.add (notification config P2Icons.tick notificationText)
                    )

                undoEvent =
                    UndoEvent.AppendToAudienceItems (List.length groupsToSave)

                lineageRequests : List XB2.Share.Store.Platform2.StoreAction
                lineageRequests =
                    addedItems
                        |> List.fastConcatMap ModalBrowser.selectedItemNamespaceCodes
                        |> Set.Any.fromList Namespace.codeToString
                        |> Set.Any.toList
                        |> List.map XB2.Share.Store.Platform2.FetchLineage
            in
            (\data ->
                currentCrosstabFromData data
                    |> ACrosstab.editGroups groupsToSave
                    |> Tuple.mapFirst (\ac -> setAudienceCrosstab ac data)
            )
                |> XB2.Share.UndoRedo.Step.andThen handleCommands
                |> XB2.Share.UndoRedo.Step.runAndCommit undoEvent model.crosstabData
                |> (\( data, ( model_, cmds ) ) ->
                        ( { model_ | crosstabData = data }, cmds )
                   )
                |> Cmd.addTrigger (config.fetchManyP2 lineageRequests)
                |> Glue.updateWith Glue.id (fetchWavesAndLocations config route flags p2Store { updateCurrentHistory = True })

        SwitchCrosstab ->
            let
                currentSort : Sort
                currentSort =
                    getCurrentSort model

                handleCommands =
                    Cmd.add (getAnalyticsCmd flags route Flipped {} p2Store model)
                        >> Cmd.add (notification config P2Icons.random "Axes swapped")
            in
            (\data ->
                currentCrosstabFromData data
                    |> ACrosstab.switchRowsAndColumns
                    |> Tuple.mapFirst
                        (\ac ->
                            data
                                |> setAudienceCrosstab ac
                                |> updateProjectMetadata (setSortForAxis Rows currentSort.columns)
                                |> updateProjectMetadata (setSortForAxis Columns currentSort.rows)
                                |> setOrderBeforeSorting Rows data.originalColumns
                                |> setOrderBeforeSorting Columns data.originalRows
                        )
            )
                |> XB2.Share.UndoRedo.Step.andThen
                    (\commands data ->
                        ( data
                        , Cmd.pure model
                            |> updateCellLoader config
                                (CrosstabCellLoader.interpretCommands
                                    config.cellLoaderConfig
                                    flags
                                    p2Store
                                    AudienceIntersect.Table
                                    commands
                                )
                        )
                    )
                |> XB2.Share.UndoRedo.Step.map handleCommands
                |> XB2.Share.UndoRedo.Step.runAndCommit UndoEvent.SwapAxes model.crosstabData
                |> (\( data, ( model_, cmds ) ) ->
                        ( closeDropdown { model_ | crosstabData = data }, cmds )
                   )

        Undo ->
            let
                analyticsCmd : Cmd msg
                analyticsCmd =
                    -- UndoEvent for UNDO has to be retrieved from state BEFORE undo is applied
                    -- (UndoRedo slot contains XB state + UndoEvent that led to that state)
                    XB2.Share.UndoRedo.currentTag model.crosstabData
                        |> Maybe.map (\event -> getAnalyticsCmd flags route Analytics.UndoApplied { undoEvent = event } p2Store model)
                        |> Maybe.withDefault Cmd.none
            in
            { model | crosstabData = XB2.Share.UndoRedo.undo model.crosstabData }
                |> cancelAllLoadingRequests config flags p2Store
                |> Glue.updateWith Glue.id (reloadNotLoadedCells config flags p2Store)
                |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config UndoRedo { closeDialogIfNeeded = False })
                |> Cmd.add analyticsCmd

        Redo ->
            let
                newData =
                    XB2.Share.UndoRedo.redo model.crosstabData

                analyticsCmd =
                    -- UndoEvent for REDO has to be retrieved from state AFTER redo is applied
                    -- (UndoRedo slot contains XB state + UndoEvent that led to that state)
                    XB2.Share.UndoRedo.currentTag newData
                        |> Maybe.map (\event -> getAnalyticsCmd flags route Analytics.RedoApplied { undoEvent = event } p2Store model)
                        |> Maybe.withDefault Cmd.none
            in
            { model | crosstabData = newData }
                |> cancelAllLoadingRequests config flags p2Store
                |> Glue.updateWith Glue.id (reloadNotLoadedCells config flags p2Store)
                |> Glue.updateWith Glue.id (confirmDialogIfAppliedViewSettings config UndoRedo { closeDialogIfNeeded = False })
                |> Cmd.add analyticsCmd

        ApplyMetricsSelection metrics ->
            model
                |> updateCrosstabData (updateProjectMetadata (\metadata -> { metadata | activeMetrics = filteredMetrics metrics }))
                |> Cmd.withTrigger config.closeModal
                |> Cmd.add (getAnalyticsCmd flags route MetricsChosen { metrics = metrics } p2Store model)

        SetFrozenRowsColumns frozenRowsColumns ->
            let
                ( _, previousNFrozenCols ) =
                    currentMetadata model
                        |> .frozenRowsAndColumns

                newModel : Model
                newModel =
                    updateCrosstabData
                        (updateProjectMetadata
                            (\metadata ->
                                { metadata
                                    | frozenRowsAndColumns = frozenRowsColumns
                                }
                            )
                        )
                        model

                analyticsItem : Analytics.FrozenItem
                analyticsItem =
                    if
                        previousNFrozenCols
                            /= Tuple.second frozenRowsColumns
                    then
                        Analytics.FrozenColumn

                    else
                        Analytics.FrozenRow

                analyticsHowMany : Int
                analyticsHowMany =
                    case analyticsItem of
                        Analytics.FrozenRow ->
                            Tuple.first frozenRowsColumns

                        Analytics.FrozenColumn ->
                            Tuple.second frozenRowsColumns
            in
            newModel
                |> Cmd.with
                    (getAnalyticsCmd flags
                        route
                        Analytics.CellsFrozen
                        { howMany = analyticsHowMany
                        , item = analyticsItem
                        }
                        p2Store
                        newModel
                    )
                -- Reload not asked cells when freezing Rows/Columns
                |> Glue.updateWith Glue.id
                    (\model_ ->
                        ( model_
                        , getVisibleCells True model_
                            |> attemptTask
                            |> Cmd.map config.msg
                        )
                    )

        SetMinimumSampleSize minimumSampleSize ->
            let
                newModel : Model
                newModel =
                    updateCrosstabData
                        (updateProjectMetadata
                            (\metadata ->
                                { metadata
                                    | minimumSampleSize = minimumSampleSize
                                }
                            )
                        )
                        model
            in
            Cmd.withTrigger config.closeModal newModel
                |> Cmd.add
                    (getAnalyticsCmd flags
                        route
                        Analytics.MinimumSampleSizeChanged
                        { minimumSampleSize = minimumSampleSize }
                        p2Store
                        newModel
                    )

        TransposeMetrics selectedMetrics ->
            let
                { rowCount, colCount } =
                    ACrosstab.getDimensionsWithTotals (currentCrosstab model)

                analyticsCmd : Cmd msg
                analyticsCmd =
                    track flags route <|
                        MetricsViewToggled
                            { newState = selectedMetrics
                            , rowCount = rowCount
                            , colCount = colCount
                            , cellCount =
                                ACrosstab.getSizeWithTotals <|
                                    currentCrosstab model
                            }

                { tableHeaderDimensions } =
                    model

                {- We have to set the header height to its minimum to move the resizing
                   bar to its correct place
                -}
                newHeight : Int
                newHeight =
                    case selectedMetrics of
                        MetricsInColumns ->
                            112

                        MetricsInRows ->
                            150
            in
            { model
                | tableHeaderDimensions =
                    { tableHeaderDimensions
                        | minHeight = newHeight
                    }
            }
                |> updateCrosstabData
                    (updateProjectMetadata
                        (\metadata ->
                            { metadata
                                | metricsTransposition = selectedMetrics
                                , headerSize =
                                    { rowWidth = metadata.headerSize.rowWidth
                                    , columnHeight = newHeight
                                    }
                            }
                        )
                    )
                |> Cmd.with analyticsCmd
                |> Glue.updateWith Glue.id
                    (\model_ ->
                        ( model_
                        , getVisibleCells True model_
                            |> attemptTask
                            |> Cmd.map config.msg
                        )
                    )

        ResetSortByName ->
            let
                sort : Sort
                sort =
                    getCurrentSort model
            in
            ( model
                |> (if Sort.isSortingByName sort.rows then
                        resetSortForAxis Rows

                    else
                        identity
                   )
                |> (if Sort.isSortingByName sort.columns then
                        resetSortForAxis Columns

                    else
                        identity
                   )
            , Cmd.none
            )

        ResetSortForAxis axis ->
            model
                |> resetSortForAxis axis
                |> Cmd.pure

        SortBy sortConfig ->
            let
                analyticsCmd =
                    getAnalyticsCmd flags
                        route
                        TableSorted
                        { sortConfig = sortConfig }
                        p2Store
                        model
            in
            { model
                | crosstabData =
                    model.crosstabData
                        |> XB2.Share.UndoRedo.commit UndoEvent.Sort (sortCrosstabDataForAxis sortConfig)
            }
                |> Cmd.with analyticsCmd
                |> Cmd.addTrigger config.closeModal

        SwitchAverageTimeFormat ->
            model
                |> updateCrosstabData
                    (updateProjectMetadata
                        (\metadata ->
                            { metadata
                                | averageTimeFormat =
                                    Average.switchTimeFormat metadata.averageTimeFormat
                            }
                        )
                    )
                |> Cmd.with
                    (getAnalyticsCmd flags
                        route
                        AverageUnitChanged
                        {}
                        p2Store
                        model
                    )

        TableHeaderResizing direction currentPagePosition ->
            let
                tableHeaderDimensions =
                    model.tableHeaderDimensions

                delta : Int
                delta =
                    tableHeaderDimensions.resizing
                        |> Maybe.andThen .startPosition
                        |> Maybe.map
                            (\startPosition ->
                                let
                                    getInitialPosition =
                                        case direction of
                                            Column ->
                                                .y

                                            Row ->
                                                .x
                                in
                                currentPagePosition
                                    - round (getInitialPosition startPosition)
                            )
                        |> Maybe.withDefault 0
            in
            model
                |> updateCrosstabData
                    (updateProjectMetadata
                        (\({ headerSize } as metadata) ->
                            case direction of
                                Column ->
                                    let
                                        newHeight =
                                            tableHeaderDimensions.resizing
                                                |> Maybe.unwrap headerSize.columnHeight
                                                    .originalHeight
                                                |> (+) delta
                                    in
                                    if
                                        tableHeaderDimensions.minHeight
                                            <= newHeight
                                            && newHeight
                                            <= tableHeaderDimensions.maxHeight
                                    then
                                        { metadata
                                            | headerSize =
                                                { headerSize | columnHeight = newHeight }
                                        }

                                    else
                                        metadata

                                Row ->
                                    let
                                        newWidth =
                                            tableHeaderDimensions.resizing
                                                |> Maybe.unwrap headerSize.rowWidth
                                                    .originalWidth
                                                |> (+) delta
                                    in
                                    if
                                        tableHeaderDimensions.minWidth
                                            <= newWidth
                                            && newWidth
                                            <= tableHeaderDimensions.maxWidth
                                    then
                                        { metadata
                                            | headerSize =
                                                { headerSize
                                                    | rowWidth = newWidth
                                                }
                                        }

                                    else
                                        metadata
                        )
                    )
                |> Cmd.pure


updateSelectAction : Config msg -> XB2.Router.Route -> Flags -> TableSelectMsg -> Model -> ( Model, Cmd msg )
updateSelectAction config route flags selectActionType model =
    let
        clearMouseDownState : Model -> Model
        clearMouseDownState m =
            { m | tableSelectionMouseDown = None }

        executeIfMouseDownMovedWhileDown : Model -> (() -> ( Model, Cmd msg )) -> ( Model, Cmd msg )
        executeIfMouseDownMovedWhileDown m fn =
            case m.tableSelectionMouseDown of
                None ->
                    fn ()

                MouseDown d ->
                    if d.moved then
                        Cmd.pure <| clearMouseDownState m

                    else
                        fn ()
                            |> Glue.updateWith Glue.id (clearMouseDownState >> Cmd.pure)

        elementToFocus : String
        elementToFocus =
            "modal-selection-select-all-button"
    in
    case selectActionType of
        SelectRow { shiftPressed } itemSelected key ->
            executeIfMouseDownMovedWhileDown model
                (\() ->
                    model
                        |> updateCrosstabData
                            (updateAudienceCrosstab
                                (if shiftPressed then
                                    ACrosstab.selectRowWithShift key

                                 else
                                    ACrosstab.selectRow key
                                )
                            )
                        |> Cmd.with (maybeTrack flags route <| keyToItemSelectedEvent Row itemSelected key)
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )
                        |> Cmd.addIf shiftPressed (maybeTrack flags route <| keyToItemSelectedWithShiftEvent Row key)
                )

        SelectColumn { shiftPressed } itemSelected key ->
            executeIfMouseDownMovedWhileDown model
                (\() ->
                    model
                        |> updateCrosstabData
                            (updateAudienceCrosstab
                                (if shiftPressed then
                                    ACrosstab.selectColumnWithShift key

                                 else
                                    ACrosstab.selectColumn key
                                )
                            )
                        |> Cmd.with (maybeTrack flags route <| keyToItemSelectedEvent Column itemSelected key)
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )
                        |> Cmd.addIf shiftPressed (maybeTrack flags route <| keyToItemSelectedWithShiftEvent Column key)
                )

        DeselectRow key ->
            executeIfMouseDownMovedWhileDown model
                (\() ->
                    model
                        |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.deselectRow key))
                        |> Cmd.pure
                )

        DeselectColumn key ->
            executeIfMouseDownMovedWhileDown model
                (\() ->
                    model
                        |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.deselectColumn key))
                        |> Cmd.pure
                )

        ClearSelection ->
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll)
                |> Cmd.pure

        SelectAllRows ->
            let
                nonselectedRows =
                    ACrosstab.getNonselectedRows (currentCrosstab model)
            in
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.selectAllRows)
                |> Cmd.with (track flags route <| keysToItemsSelectedEvent nonselectedRows)

        SelectAllColumns ->
            let
                nonselectedColumns =
                    ACrosstab.getNonselectedColumns (currentCrosstab model)
            in
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.selectAllColumns)
                |> Cmd.with (track flags route <| keysToItemsSelectedEvent nonselectedColumns)

        DeselectAllRows ->
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAllRows)
                |> Cmd.pure

        DeselectAllColumns ->
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAllColumns)
                |> Cmd.pure


sortCrosstabDataForAxis : SortConfig -> CrosstabData -> CrosstabData
sortCrosstabDataForAxis ({ axis, mode } as sortConfig) crosstabData =
    let
        base : BaseAudience
        base =
            currentCrosstabFromData crosstabData
                |> ACrosstab.getCurrentBaseAudience

        currentSort : Sort
        currentSort =
            crosstabData.projectMetadata.sort

        otherAxis : Axis
        otherAxis =
            Sort.otherAxis axis

        resetOtherAxis : CrosstabData -> CrosstabData
        resetOtherAxis =
            {- The SortByOtherAxis* sorts are exclusive, even though
               they don't need to be; it's PM request ¯\_(ツ)_/¯
               (ATC-1269).
            -}
            updateProjectMetadata <|
                case ( mode, Sort.forAxis otherAxis currentSort ) of
                    ( ByOtherAxisMetric _ _ _, ByOtherAxisMetric _ _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByOtherAxisMetric _ _ _, ByOtherAxisAverage _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByOtherAxisMetric _ _ _, ByTotalsMetric _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByOtherAxisAverage _ _, ByOtherAxisMetric _ _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByOtherAxisAverage _ _, ByOtherAxisAverage _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByOtherAxisAverage _ _, ByTotalsMetric _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByTotalsMetric _ _, ByOtherAxisMetric _ _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByTotalsMetric _ _, ByOtherAxisAverage _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    ( ByTotalsMetric _ _, ByTotalsMetric _ _ ) ->
                        setSortForAxis otherAxis NoSort

                    _ ->
                        identity

        keyMapping =
            ACrosstab.getKeyMapping <| currentCrosstabFromData crosstabData

        updateOrder : CrosstabData -> CrosstabData
        updateOrder =
            if Sort.isSorting (Sort.forAxis axis currentSort) then
                -- Remember the original order, not the latest one. See comments in ATC-1448.
                identity

            else
                refreshOrderBeforeSorting axis

        crosstabTotals =
            currentCrosstabFromData crosstabData
                |> ACrosstab.getTotals
    in
    crosstabData
        |> -- important that this happens before reorder
           updateOrder
        |> updateProjectMetadata
            (setSortForAxis axis mode)
        |> resetOtherAxis
        |> updateAudienceCrosstab
            (ACrosstab.updateCrosstab (Sort.sortAxisBy sortConfig base crosstabTotals keyMapping))


resetSortForAxis : Axis -> Model -> Model
resetSortForAxis axis model =
    { model
        | crosstabData =
            model.crosstabData
                |> XB2.Share.UndoRedo.commit UndoEvent.ResetSort (removeSortForAxis axis)
    }


discardSortForAxis : Axis -> Model -> Model
discardSortForAxis axis model =
    { model
        | crosstabData =
            model.crosstabData
                |> XB2.Share.UndoRedo.updateCurrent (removeSortForAxis axis)
    }


removeSortForAxis : Axis -> CrosstabData -> CrosstabData
removeSortForAxis axis crosstabData =
    crosstabData
        |> updateProjectMetadata
            (setSortForAxis axis NoSort)
        |> updateAudienceCrosstab
            (ACrosstab.updateCrosstab
                (case axis of
                    Rows ->
                        case crosstabData.originalRows of
                            NotSet ->
                                identity

                            OriginalOrder originalRows ->
                                Crosstab.reorderRows originalRows

                    Columns ->
                        case crosstabData.originalColumns of
                            NotSet ->
                                identity

                            OriginalOrder originalColumns ->
                                Crosstab.reorderColumns originalColumns
                )
            )


autoScrollCmd : Config msg -> Direction -> Cmd msg
autoScrollCmd config direction =
    let
        scrollByStep step { viewport } =
            let
                ( newTop, newLeft ) =
                    case direction of
                        Row ->
                            ( viewport.y - step, viewport.x )

                        Column ->
                            ( viewport.y, viewport.x - step )
            in
            Dom.setViewportOf Common.scrollTableId newLeft newTop
    in
    Dom.getViewportOf Common.scrollTableId
        |> Task.andThen (scrollByStep 15)
        |> Task.attempt (always <| config.msg NoOp)


modalForViewGroupExpression : ( Direction, ACrosstab.Key ) -> Maybe Modal
modalForViewGroupExpression ( direction, key ) =
    case AudienceItem.getDefinition key.item of
        Average _ ->
            Nothing

        Expression expr ->
            Just <| Modal.initViewGroup ( direction, key, expr )


saveAsAudienceModalMsg : Config msg -> Maybe Modal.SaveAsItem -> msg
saveAsAudienceModalMsg config =
    Maybe.map Modal.initSaveAsAudience
        >> Maybe.unwrap (config.msg NoOp) config.openModal


openSaveAsAudienceModalForTableItems : Config msg -> List ( Direction, ACrosstab.Key ) -> msg
openSaveAsAudienceModalForTableItems config items =
    let
        extractFromItem ( _, { item } ) =
            case AudienceItem.getDefinition item of
                Average _ ->
                    Nothing

                Expression expr ->
                    Just <| Modal.SaveAsAudienceItem item expr
    in
    items
        |> List.head
        |> Maybe.andThen extractFromItem
        |> saveAsAudienceModalMsg config


openSaveAsAudienceModal : Config msg -> Model -> msg
openSaveAsAudienceModal config model =
    if selectedAnyBaseInCrosstab model then
        ACrosstab.getSelectedBases (currentCrosstab model)
            |> Maybe.map (NonemptyList.head >> Modal.SaveAsBaseAudience)
            |> saveAsAudienceModalMsg config

    else
        openSaveAsAudienceModalForTableItems config (getAllSelected model)


createBaseFromItems : Config msg -> XB2.Router.Route -> Flags -> Grouping -> XB2.Share.Store.Platform2.Store -> List ACrosstab.Key -> Model -> ( Model, Cmd msg )
createBaseFromItems config route flags grouping p2Store items model =
    let
        constructWith : (NonEmpty Expression -> Expression) -> ( Model, Cmd msg )
        constructWith combineExpressions =
            items
                |> List.filterMap
                    (\key ->
                        case AudienceItem.getDefinition key.item of
                            Average _ ->
                                Nothing

                            Expression expr ->
                                Just ( AudienceItem.getCaption key.item, expr )
                    )
                |> NonemptyList.fromList
                |> Maybe.map
                    (\nonemptyList ->
                        let
                            seed =
                                ACrosstab.getSeed <| currentCrosstab model

                            captions =
                                NonemptyList.map Tuple.first nonemptyList

                            expressions =
                                NonemptyList.map Tuple.second nonemptyList
                        in
                        if NonemptyList.length nonemptyList == 1 then
                            AudienceItem.fromCaptionExpression
                                seed
                                (Caption.fromGroupOfCaptions grouping captions)
                                (NonemptyList.head expressions)

                        else
                            AudienceItem.fromCaptionExpression
                                seed
                                (Caption.fromGroupOfCaptions grouping captions)
                                (combineExpressions expressions)
                    )
                |> Maybe.map (\( combinedItem, _ ) -> addNewBases config route flags p2Store [ ACrosstab.Key combinedItem False ] model)
                |> Maybe.withDefault (Cmd.pure model)
    in
    case grouping of
        Split ->
            addNewBases config route flags p2Store items model

        Or ->
            constructWith Expression.unionMany

        And ->
            constructWith Expression.intersectionMany


addNewBases : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> List ACrosstab.Key -> Model -> ( Model, Cmd msg )
addNewBases config route flags p2Store allSelected model =
    let
        withAnalytics =
            Cmd.add (getAnalyticsCmd flags route ItemAddedAsABase { rowsColsSelected = List.length allSelected } p2Store model)

        addBaseAudienceCmd baseAudiences =
            baseAudiences
                |> UpdateOrCreateBaseAudiences
                |> Edit
                |> Cmd.perform
                |> Cmd.map config.msg

        newModel =
            model
                |> updateCrosstabData (updateAudienceCrosstab ACrosstab.deselectAll)
    in
    List.foldr
        (\{ item } ->
            case BaseAudience.fromAudienceItem item of
                Just base ->
                    (::) base

                Nothing ->
                    identity
        )
        []
        allSelected
        |> NonemptyList.fromList
        |> Maybe.map (\bases -> ( newModel, addBaseAudienceCmd bases ))
        |> Maybe.withDefault (Cmd.pure newModel)
        |> withAnalytics


openModalForAddAsNewBase : Config msg -> List ACrosstab.Key -> Model -> ( Model, Cmd msg )
openModalForAddAsNewBase config allSelected model =
    model
        |> Cmd.withTrigger (config.openModal <| Modal.initAddAsNewBases allSelected)


addNewBase : Config msg -> XB2.Router.Route -> Flags -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
addNewBase config route flags p2Store model =
    let
        allSelected =
            List.map Tuple.second <| getAllSelected model
    in
    if List.length allSelected == 1 then
        addNewBases config route flags p2Store allSelected model

    else
        openModalForAddAsNewBase config allSelected model


openModalForMergeRowColum : Config msg -> List ACrosstab.Key -> List Direction -> List ( Direction, ACrosstab.Key ) -> Model -> ( Model, Cmd msg )
openModalForMergeRowColum config allKeys allDirections allSelected model =
    model
        |> Cmd.withTrigger (config.openModal <| Modal.initMergeRowOrColum allKeys allDirections allSelected)


mergeRowColum : Config msg -> Model -> ( Model, Cmd msg )
mergeRowColum config model =
    let
        allSelectedkey =
            List.map Tuple.second <| getAllSelected model

        allDirections =
            List.map Tuple.first <| getAllSelected model

        allSelected =
            getAllSelected model
    in
    openModalForMergeRowColum config allSelectedkey allDirections allSelected model


toAffixData :
    LogicOperator
    -> Caption
    -> Expression
    -> ( Direction, ACrosstab.Key )
    -> Maybe AffixGroupItem
toAffixData operator groupCaption affixingExpression ( direction, { item } ) =
    let
        definition =
            AudienceItem.getDefinition item
    in
    case definition of
        Expression oldExpression ->
            let
                caption =
                    AudienceItem.getCaption item
            in
            Just
                { direction = direction
                , oldExpression = oldExpression
                , oldItem = item
                , newCaption =
                    Caption.merge
                        (operatorToString operator)
                        caption
                        groupCaption
                , expressionBeingAffixed = affixingExpression
                , newExpression =
                    Expression.append
                        operator
                        oldExpression
                        affixingExpression
                }

        Average _ ->
            Nothing


toEditData :
    Caption
    -> Expression
    -> ( Direction, ACrosstab.Key )
    -> Maybe EditGroupItem
toEditData groupCaption editingExpression ( direction, { item } ) =
    let
        definition =
            AudienceItem.getDefinition item
    in
    case definition of
        Expression oldExpression ->
            Just
                { direction = direction
                , oldExpression = oldExpression
                , oldItem = item
                , newCaption = groupCaption
                , expressionBeingEdited = editingExpression
                , newExpression = editingExpression
                }

        Average _ ->
            Nothing


getProjectFromCrosstab :
    Flags
    -> Model
    ->
        { a
            | id : XBProjectId
            , folderId : Maybe XBFolderId
            , name : String
            , shared : XBData.Shared
            , sharingNote : String
            , copiedFrom : Maybe XBProjectId
        }
    -> XBProject
getProjectFromCrosstab flags model project =
    { id = project.id
    , folderId = project.folderId
    , name = project.name
    , shared = project.shared
    , sharingNote = project.sharingNote
    , copiedFrom = project.copiedFrom

    -- is always set by server
    , updatedAt = Time.millisToPosix 0
    , createdAt = Time.millisToPosix 0
    , data =
        let
            currentData =
                XB2.Share.UndoRedo.current model.crosstabData
        in
        RemoteData.Success
            { ownerId = flags.user.id
            , rows =
                ACrosstab.getRows (currentCrosstabFromData currentData)
                    |> List.map (AudienceItem.toAudienceData << .item)
            , columns =
                ACrosstab.getColumns (currentCrosstabFromData currentData)
                    |> List.map (AudienceItem.toAudienceData << .item)
            , locationCodes = Set.Any.toList <| getActiveLocations model
            , waveCodes = Set.Any.toList <| getActiveWaves model
            , bases =
                getBaseAudiences model
                    |> NonemptyList.map BaseAudience.toBaseAudienceData
            , metadata = currentData.projectMetadata
            }
    }


getNewProjectFromCrosstab : Flags -> String -> Model -> XBProject
getNewProjectFromCrosstab flags name model =
    getProjectFromCrosstab
        flags
        model
        { id = XB2.Share.Data.Id.fromString "" -- this is ignored in case of creating new audience
        , folderId = Nothing
        , name = name
        , shared = XBData.MyPrivateCrosstab
        , sharingNote = ""
        , copiedFrom = Nothing
        }


getCopyProjectFromCrosstab : Flags -> XBStore.Store -> XBProject -> Model -> XBProject
getCopyProjectFromCrosstab flags store originalProject model =
    getProjectFromCrosstab
        flags
        model
        { id = XB2.Share.Data.Id.fromString "" -- this is ignored in case of creating new audience
        , folderId = Nothing
        , name = NameForCopy.getWithLimit (XBStore.getAllProjectNames store) NewName.maxLength originalProject.name
        , shared = XBData.MyPrivateCrosstab
        , sharingNote = ""
        , copiedFrom = Just originalProject.id
        }


saveProjectSharedWithMeAsCopy : { shouldRedirect : Bool } -> XBProject -> XBStore.Store -> Flags -> Config msg -> Model -> ( Model, Cmd msg )
saveProjectSharedWithMeAsCopy { shouldRedirect } project xbStore flags config model =
    ( model
    , XBStore.fetchTaskXBProjectFullyLoaded project flags
        |> Task.map
            (\originalFull ->
                config.saveCopyOfProject
                    { original = originalFull
                    , copy =
                        getCopyProjectFromCrosstab
                            flags
                            xbStore
                            project
                            model
                    , shouldRedirect = shouldRedirect
                    }
            )
        |> Task.attempt (Result.withDefault (NoOp |> config.msg))
    )


saveEditedProject : Config msg -> Flags -> XBProject -> Model -> ( Model, Cmd msg )
saveEditedProject config flags xbProject model =
    model
        |> Cmd.withTrigger
            (config.updateXBProject <|
                getProjectFromCrosstab flags model xbProject
            )


reloadNotLoadedCells : Config msg -> Flags -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
reloadNotLoadedCells config flags p2Store model =
    let
        ( newCrosstab, reloadCellsCommands ) =
            ACrosstab.reloadNotLoadedCells
                (currentCrosstab model)

        newModel =
            model
                |> updateCrosstabData (setAudienceCrosstab newCrosstab)
    in
    Cmd.pure newModel
        |> updateCellLoader config
            (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table reloadCellsCommands)


cancelAllLoadingRequests : Config msg -> Flags -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
cancelAllLoadingRequests config flags p2Store model =
    model
        |> Cmd.withTrigger config.closeModal
        |> updateCellLoader config (CrosstabCellLoader.cancelAllLoadingRequests config.cellLoaderConfig flags p2Store)


affixModalOpenMsg :
    Config msg
    -> Grouping
    -> AudienceItemData
    -> Caption
    -> Expression.LogicOperator
    -> Analytics.AffixedFrom
    -> Modal.AttributesModalData
    -> msg
affixModalOpenMsg config grouping { items } caption operator affixedFrom attributeBrowserModal =
    let
        addedItems =
            XB2.Share.UndoRedo.current attributeBrowserModal.browserModel |> .selectedItems
    in
    if List.isEmpty addedItems then
        config.msg NoOp

    else
        let
            toLastItem =
                NonemptyList.head items

            lastItem =
                ignoreIndex toLastItem
        in
        case AudienceItem.getDefinition lastItem of
            Average _ ->
                config.msg NoOp

            Expression expression ->
                let
                    trimNewCaption item =
                        { item | newCaption = Caption.trimNameByUserDefinedLimit item.newCaption }

                    openModalForTableAffix : Zipper AffixGroupItem -> msg
                    openModalForTableAffix zipper =
                        config.openModal
                            (Modal.AffixGroup
                                { zipper = ListZipper.map trimNewCaption zipper
                                , grouping = grouping
                                , operator = operator
                                , expandedItem = Nothing
                                , itemBeingRenamed = Nothing
                                , attributeBrowserModal = attributeBrowserModal
                                , affixedFrom = affixedFrom
                                }
                            )

                    toBaseAffixData : BaseAudience -> AffixBaseGroupData
                    toBaseAffixData base =
                        let
                            baseExpr =
                                BaseAudience.getExpression base

                            baseCaption =
                                BaseAudience.getCaption base
                        in
                        { baseAudience = base
                        , newExpression = Expression.append operator baseExpr expression
                        , expressionBeingAffixed = expression
                        , newCaption = Caption.merge (operatorToString operator) baseCaption caption
                        , grouping = grouping
                        , addedItems = addedItems
                        }

                    openModalForBaseAffix : Zipper Modal.AffixBaseGroupData -> msg
                    openModalForBaseAffix zipper =
                        config.openModal
                            (Modal.AffixBase
                                { zipper = ListZipper.map trimNewCaption zipper
                                , operator = operator
                                , grouping = grouping
                                , expandedItem = Nothing
                                , itemBeingRenamed = Nothing
                                , attributeBrowserModal = attributeBrowserModal
                                }
                            )
                in
                case attributeBrowserModal.affixingOrEditingItems of
                    ModalBrowser.NotAffixingOrEditing ->
                        config.msg NoOp

                    ModalBrowser.AffixingBases bases ->
                        bases
                            |> NonemptyList.map toBaseAffixData
                            |> ListZipper.fromNonEmpty
                            |> openModalForBaseAffix

                    ModalBrowser.AffixingRowsOrColumns selectedItems ->
                        selectedItems
                            |> NonemptyList.filterMap (toAffixData operator caption expression)
                            |> Maybe.unwrap
                                (config.msg NoOp)
                                (ListZipper.fromNonEmpty >> openModalForTableAffix)

                    ModalBrowser.EditingBases _ ->
                        config.msg NoOp

                    ModalBrowser.EditingRowsOrColumns _ ->
                        config.msg NoOp


editModalOpenMsg :
    Config msg
    -> Grouping
    -> AudienceItemData
    -> Caption
    -> Modal.AttributesModalData
    -> msg
editModalOpenMsg config grouping { items } caption attributeBrowserModal =
    let
        addedItems =
            XB2.Share.UndoRedo.current attributeBrowserModal.browserModel |> .selectedItems
    in
    if List.isEmpty addedItems then
        config.msg NoOp

    else
        let
            toLastItem =
                NonemptyList.head items

            lastItem =
                ignoreIndex toLastItem
        in
        case AudienceItem.getDefinition lastItem of
            Average _ ->
                config.msg NoOp

            Expression expression ->
                let
                    trimNewCaption item =
                        { item | newCaption = Caption.trimNameByUserDefinedLimit item.newCaption }

                    openModalForTableEdit : Zipper EditGroupItem -> msg
                    openModalForTableEdit zipper =
                        config.openModal
                            (Modal.EditGroup
                                { zipper = ListZipper.map trimNewCaption zipper
                                , grouping = grouping
                                , expandedItem = Nothing
                                , itemBeingRenamed = Nothing
                                , attributeBrowserModal = attributeBrowserModal
                                }
                            )

                    toBaseEditData : BaseAudience -> Modal.EditBaseGroupData
                    toBaseEditData base =
                        { baseAudience = base
                        , newExpression = expression
                        , expressionBeingEdited = expression
                        , newCaption = caption
                        , grouping = grouping
                        , addedItems = addedItems
                        }

                    openModalForBaseEdit : Zipper Modal.EditBaseGroupData -> msg
                    openModalForBaseEdit zipper =
                        config.openModal
                            (Modal.EditBase
                                { zipper = ListZipper.map trimNewCaption zipper
                                , grouping = grouping
                                , expandedItem = Nothing
                                , itemBeingRenamed = Nothing
                                , attributeBrowserModal = attributeBrowserModal
                                }
                            )
                in
                case attributeBrowserModal.affixingOrEditingItems of
                    ModalBrowser.NotAffixingOrEditing ->
                        config.msg NoOp

                    ModalBrowser.EditingBases bases ->
                        bases
                            |> NonemptyList.map toBaseEditData
                            |> ListZipper.fromNonEmpty
                            |> openModalForBaseEdit

                    ModalBrowser.EditingRowsOrColumns selectedItems ->
                        selectedItems
                            |> NonemptyList.filterMap (toEditData caption expression)
                            |> Maybe.unwrap
                                (config.msg NoOp)
                                (ListZipper.fromNonEmpty >> openModalForTableEdit)

                    ModalBrowser.AffixingBases _ ->
                        config.msg NoOp

                    ModalBrowser.AffixingRowsOrColumns _ ->
                        config.msg NoOp


updateCrosstabData : (CrosstabData -> CrosstabData) -> Model -> Model
updateCrosstabData f model =
    { model | crosstabData = XB2.Share.UndoRedo.updateCurrent f model.crosstabData }


getBasesPanelWidth : (Msg -> msg) -> Model -> ( Model, Cmd msg )
getBasesPanelWidth msg model =
    model
        |> Cmd.with
            (Dom.getViewportOf Common.basesPanelId
                |> Task.map (\{ viewport } -> SetBasesPanelWidth <| round viewport.width)
                |> Task.onError (\_ -> Process.sleep 200 |> Task.map (always GetBasesPanelWidth))
                |> Task.attempt (Maybe.unwrap (msg NoOp) msg << Result.toMaybe)
            )


delay : Float -> Task.Task x a -> Task.Task x a
delay delayTime task =
    Process.sleep delayTime
        |> Task.andThen (always task)


getVisibleCells : Bool -> Model -> Task.Task Dom.Error Msg
getVisibleCells shouldReloadTable model =
    Task.map2
        (\scrollArea cornerCell ->
            let
                {- The JS properties scroll{Top,Left} (decoded by Elm into
                   scrollArea.viewport.{x,y}) need to be sanitized with this
                   `max 0` because of MacOS overscroll (ATC-3270). If allowed
                   to get negative, it would show wrong items in the table as a
                   result (topLeftRow == -1 and so on).
                -}
                scrollX =
                    max 0 scrollArea.viewport.x

                scrollY =
                    max 0 scrollArea.viewport.y

                currentData =
                    XB2.Share.UndoRedo.current model.crosstabData

                { rowCount, colCount } =
                    ACrosstab.getDimensionsWithTotals (currentCrosstabFromData currentData)

                cellWidth =
                    getTotalColWidth
                        (List.length currentData.projectMetadata.activeMetrics)
                        currentData.projectMetadata.metricsTransposition
                        |> toFloat

                cellHeight =
                    getTotalRowHeight
                        (List.length currentData.projectMetadata.activeMetrics)
                        currentData.projectMetadata.metricsTransposition
                        |> toFloat

                visibleAreaWidth =
                    scrollArea.viewport.width - cornerCell.viewport.width

                visibleAreaHeight =
                    scrollArea.viewport.height - cornerCell.viewport.height

                {- Deals with situations like:
                          0      1      2      3      4
                       ┌───┲━━┯━━━━━━┯━━━━━━┯━━━━━━┯━━┱───┐
                       │   ┃  │      │      │      │  ┃   │
                       │   ┃  │      │      │      │  ┃   │
                   where sum of the visible parts of leftmost and rightmost columns
                   is less than cell width. Our basic `width/width` calculations
                   would report one less column (4 columns visible).

                   The right answer is that 5 columns are visible, and to get to it
                   we need to check how much we've scrolled into the column.
                   The crux of the condition below is:

                       (partiallyVisibleLeft + partiallyVisibleRight) < cellWidth

                   Where:

                       partiallyVisibleLeft = cellWidth - (scrolledX % cellWidth)
                       partiallyVisibleRight = (scrollAreaWidth - partiallyVisibleLeft) % cellWidth

                   Throw this all into Mathematica or other symbolic computation
                   engine and you'll get slightly optimized (but no longer
                   trackable to the original meaning):

                       ((scrollAreaWidth + scrolledX) % cellWidth) < (scrollAreaWidth % cellWidth)

                -}
                wouldUnderestimateCols =
                    fractionalModBy cellWidth (scrollArea.viewport.width + scrollX)
                        < fractionalModBy cellWidth scrollArea.viewport.width

                -- similarly for rows.
                wouldUnderestimateRows =
                    fractionalModBy cellHeight (scrollArea.viewport.height + scrollY)
                        < fractionalModBy cellHeight scrollArea.viewport.height

                visibleNumberOfRows =
                    {- This `min` is here because of the padding below the table.
                       It was sometimes making the reported number of rows higher
                       because we're computing this number too simplistically
                       with division of scroll area / cell area.
                       This `min` makes sure we don't go out of bounds.
                    -}
                    min (rowCount - topLeftRow) <|
                        (ceiling <| visibleAreaHeight / cellHeight)
                            + (if wouldUnderestimateRows then
                                1

                               else
                                0
                              )

                visibleNumberOfCols =
                    min (colCount - topLeftCol) <|
                        (ceiling <| visibleAreaWidth / cellWidth)
                            + (if wouldUnderestimateCols then
                                1

                               else
                                0
                              )

                topLeftRow =
                    floor <| scrollY / cellHeight

                topLeftCol =
                    floor <| scrollX / cellWidth

                ( nFrozenRows, nFrozenCols ) =
                    currentMetadata model
                        |> .frozenRowsAndColumns
            in
            SetVisibleCellsAndTableOffset
                { shouldReloadTable = shouldReloadTable
                , topOffset = floor cornerCell.scene.height
                , visibleCells =
                    { topLeftRow = topLeftRow
                    , topLeftCol = topLeftCol
                    , bottomRightRow = topLeftRow + visibleNumberOfRows
                    , bottomRightCol = topLeftCol + visibleNumberOfCols
                    , frozenRows = nFrozenRows
                    , frozenCols = nFrozenCols
                    }
                }
        )
        (Dom.getViewportOf Common.scrollTableId)
        (Dom.getViewportOf Common.cornerCellId)


attemptTask : Task.Task x Msg -> Cmd Msg
attemptTask task =
    Task.attempt (Result.withDefault NoOp) task


type alias ScrollPosition =
    ( Int, Int )


type ScrollDirection
    = ScrollX
    | ScrollY
    | ScrollBoth


type ScrollingState
    = NotScrolling
    | StartScrolling ScrollPosition
    | JustScrolling ScrollPosition ScrollDirection


type alias CrosstabSearchModel =
    { term : String
    , sanitizedTerm : String
    , inputDebouncer : Debouncer.Debouncer Msg Msg
    , searchTopLeftScrollJumps : Maybe (Zipper { index : Int, direction : Direction })
    , inputIsFocused : Bool
    }


getCrosstabColumnsThatMatchSearchTermWithIndex : String -> AudienceCrosstab -> List ( Int, Direction )
getCrosstabColumnsThatMatchSearchTermWithIndex searchTerm crosstab =
    ACrosstab.getColumns crosstab
        |> List.indexedFoldl
            (\index col acc ->
                let
                    stringifiedSplitCaption =
                        Caption.getName (AudienceItem.getCaption col.item)
                            ++ " "
                            ++ Maybe.withDefault "" (Caption.getSubtitle (AudienceItem.getCaption col.item))

                    -- We sanitize the search term to lowercase to make the search case-insensitive
                    sanitizedTitleSubtitle =
                        sanitizeSearchTerm stringifiedSplitCaption
                in
                if Fuzzy.match searchTerm sanitizedTitleSubtitle then
                    acc ++ [ ( index + 1, Column ) ]

                else
                    acc
            )
            []


getCrosstabRowsThatMatchSearchTermWithIndex : String -> AudienceCrosstab -> List ( Int, Direction )
getCrosstabRowsThatMatchSearchTermWithIndex searchTerm crosstab =
    ACrosstab.getRows crosstab
        |> List.indexedFoldl
            (\index row acc ->
                let
                    stringifiedSplitCaption =
                        Caption.getName (AudienceItem.getCaption row.item)
                            ++ " "
                            ++ Maybe.withDefault "" (Caption.getSubtitle (AudienceItem.getCaption row.item))

                    -- We sanitize the search term to lowercase to make the search case-insensitive
                    sanitizedTitleSubtitle =
                        sanitizeSearchTerm stringifiedSplitCaption
                in
                if Fuzzy.match searchTerm sanitizedTitleSubtitle then
                    acc ++ [ ( index + 1, Row ) ]

                else
                    acc
            )
            []


sanitizeSearchTerm : String -> String
sanitizeSearchTerm term =
    String.removeDiacritics (String.toLower term)


isScrolling : ScrollingState -> Bool
isScrolling scrollingState =
    case scrollingState of
        NotScrolling ->
            False

        StartScrolling _ ->
            True

        JustScrolling _ _ ->
            True


isScrollingX : ScrollingState -> Bool
isScrollingX scrollingState =
    case scrollingState of
        NotScrolling ->
            False

        StartScrolling _ ->
            False

        JustScrolling _ ScrollBoth ->
            True

        JustScrolling _ ScrollX ->
            True

        JustScrolling _ ScrollY ->
            False


isScrollingY : ScrollingState -> Bool
isScrollingY scrollingState =
    case scrollingState of
        NotScrolling ->
            False

        StartScrolling _ ->
            False

        JustScrolling _ ScrollBoth ->
            True

        JustScrolling _ ScrollX ->
            False

        JustScrolling _ ScrollY ->
            True


resolveIsScrollingState : Bool -> ScrollPosition -> Model -> Model
resolveIsScrollingState scrollEnd position model =
    let
        getScrollDirection ( oldLeft, oldTop ) ( currentLeft, currentTop ) =
            if oldTop /= currentTop && oldLeft /= currentLeft then
                ScrollBoth

            else if oldTop /= currentTop then
                ScrollY

            else
                ScrollX
    in
    { model
        | scrollingState =
            if scrollEnd then
                NotScrolling

            else
                case model.scrollingState of
                    NotScrolling ->
                        StartScrolling position

                    JustScrolling oldPosition _ ->
                        JustScrolling position (getScrollDirection oldPosition position)

                    StartScrolling oldPosition ->
                        JustScrolling position (getScrollDirection oldPosition position)
    }


allNotDoneCellsForSorting : NonEmpty SortConfig -> AudienceCrosstab -> Int
allNotDoneCellsForSorting sortConfigs crosstab =
    NonemptyList.foldr
        (\{ axis, mode } acc ->
            let
                notLoadedRowsOrCols id =
                    case axis of
                        Rows ->
                            ACrosstab.notDoneForColumnCount id crosstab

                        Columns ->
                            ACrosstab.notDoneForRowCount id crosstab
            in
            acc
                + (case mode of
                    ByOtherAxisMetric id _ _ ->
                        notLoadedRowsOrCols id

                    ByOtherAxisAverage id _ ->
                        notLoadedRowsOrCols id

                    ByTotalsMetric _ _ ->
                        case axis of
                            Rows ->
                                ACrosstab.totalsNotDoneForRowCount crosstab

                            Columns ->
                                ACrosstab.totalsNotDoneForColumnCount crosstab

                    ByName _ ->
                        0

                    NoSort ->
                        0
                  )
        )
        0
        sortConfigs


getAverageTimeFormat : Model -> Average.AverageTimeFormat
getAverageTimeFormat =
    .crosstabData >> XB2.Share.UndoRedo.current >> .projectMetadata >> .averageTimeFormat


updateResort : SortConfig -> Model -> Model
updateResort sortConfig model =
    { model
        | crosstabData =
            model.crosstabData
                |> XB2.Share.UndoRedo.updateCurrent (sortCrosstabDataForAxis sortConfig)
    }


fetchQuestionsForCrosstab : Config msg -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
fetchQuestionsForCrosstab config ( model, cmds ) =
    let
        addFetchQuestions =
            currentCrosstab model
                |> ACrosstab.questionCodes
                |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                |> config.fetchManyP2
                |> Cmd.addTrigger
    in
    ( model, cmds )
        |> addFetchQuestions


updateExport : Config msg -> XB2.Router.Route -> Flags -> Maybe SelectionMap.SelectionMap -> Maybe XBProject -> Posix -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
updateExport config route flags maybeSelectionMap maybeProject date p2Store model =
    case
        currentCrosstab model
            |> ACrosstab.questionCodes
            |> Store.getByIdsIfAllDone p2Store.questions
    of
        Just questions ->
            let
                baseAudiences =
                    getBaseAudiences model

                ( waves, locations ) =
                    wavesAndLocations p2Store model

                metadata =
                    currentMetadata model

                settings =
                    { orientation = metadata.metricsTransposition
                    , activeMetrics = metadata.activeMetrics
                    , email = flags.can XB2.Share.Permissions.ReceiveEmailExports
                    }

                currentCrosstab_ =
                    case maybeSelectionMap of
                        Just _ ->
                            let
                                fullCrosstab =
                                    currentCrosstab model

                                nonSelectedRows =
                                    List.filterMap
                                        (\row ->
                                            if row.isSelected then
                                                Nothing

                                            else
                                                Just ( Row, row )
                                        )
                                        (ACrosstab.getRows fullCrosstab)

                                nonSelectedColumns =
                                    List.filterMap
                                        (\col ->
                                            if col.isSelected then
                                                Nothing

                                            else
                                                Just ( Column, col )
                                        )
                                        (ACrosstab.getColumns fullCrosstab)

                                ( crosstabWithCellsRemoved, _ ) =
                                    ACrosstab.removeAudiences
                                        (nonSelectedRows ++ nonSelectedColumns)
                                        fullCrosstab
                            in
                            crosstabWithCellsRemoved

                        Nothing ->
                            currentCrosstab model

                sortConfig =
                    Sort.convertSortToSortConfig metadata.sort

                exportData : Maybe ExportData
                exportData =
                    baseAudiences
                        |> NonemptyList.toList
                        |> List.map
                            (\baseAudience ->
                                XBExport.exportResult
                                    sortConfig
                                    currentCrosstab_
                                    baseAudience
                                    model.heatmapMetric
                                    questions
                                    |> Maybe.map
                                        (\results ->
                                            { metadata =
                                                { locations = locations
                                                , waves = waves
                                                , base = baseAudience
                                                , name = Maybe.map .name maybeProject
                                                , date = date
                                                , heatmap = model.heatmapMetric
                                                , averageTimeFormat = getAverageTimeFormat model
                                                }
                                            , settings = settings
                                            , results = results
                                            }
                                        )
                            )
                        |> Maybe.combine
            in
            case exportData of
                Nothing ->
                    model
                        |> Cmd.withTrigger
                            (config.createDetailNotification P2Icons.info <|
                                Html.span [] [ Html.text "Couldn't export the crosstab project." ]
                            )

                Just data ->
                    let
                        project =
                            maybeProject
                                |> Maybe.andThen XBData.getFullyLoadedProject

                        projectIdForExportTracking =
                            project
                                |> Maybe.map (.id >> XB2.Share.Data.Id.unwrap)

                        analyticsCmd =
                            track flags route <| exportEvent locations waves p2Store model project
                    in
                    ( model
                    , Cmd.batch
                        [ XBExport.exportMultipleBases flags projectIdForExportTracking data ExportSuccess ExportFailure
                            |> Cmd.map config.msg
                        , analyticsCmd
                        ]
                    )

        Nothing ->
            Cmd.pure
                { model
                    | exportWaitingForQuestions =
                        Just
                            { project = maybeProject
                            , time = date
                            , selectionMap = maybeSelectionMap
                            }
                }


exportNotificationId : String
exportNotificationId =
    "export-project-notification"


update :
    Config msg
    -> XB2.Router.Route
    -> Flags
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> Msg
    -> Model
    -> ( Model, Cmd msg )
update config route flags xbStore p2Store msg model =
    let
        update_ : ( Model, Cmd msg )
        update_ =
            case msg of
                NoOp ->
                    ( model, Cmd.none )

                FetchManyP2 toFetch ->
                    model
                        |> Cmd.withTrigger (config.fetchManyP2 toFetch)

                QueryAjaxError err ->
                    model
                        |> Cmd.withTrigger (config.queryAjaxError err)

                UselessCheckboxClicked ->
                    model
                        |> Cmd.with (getAnalyticsCmd flags route Analytics.UselessCheckboxClicked {} p2Store model)

                UpdateUserSettings userSettings ->
                    model |> Cmd.withTrigger (config.updateUserSettings userSettings)

                TableCellDragAndDropMsg dndMsg ->
                    let
                        ( dndReturn, newDndModel, dndCmd ) =
                            dndSystem.update dndMsg model.tableCellDndModel

                        handleMove to dropIndex dragItem =
                            let
                                updateDragAndDropMsg =
                                    Move
                                        { to = to
                                        , at = dropIndex
                                        , items = dragItem
                                        }
                            in
                            Glue.updateWith Glue.id
                                (update
                                    config
                                    route
                                    flags
                                    xbStore
                                    p2Store
                                    (Edit updateDragAndDropMsg)
                                )
                                (Cmd.pure { model | tableCellDndModel = newDndModel })
                                |> Cmd.add (Cmd.map config.msg dndCmd)
                    in
                    case dndReturn of
                        Just { dropListId, dropIndex, dragItem } ->
                            handleMove dropListId dropIndex dragItem

                        Nothing ->
                            { model | tableCellDndModel = newDndModel }
                                |> closeDropdown
                                |> Cmd.with (Cmd.map config.msg dndCmd)

                Edit editMsg ->
                    updateEdit config route flags xbStore p2Store editMsg model
                        |> Tuple.mapFirst (\m -> { m | unsaved = setAsEdited m.unsaved })
                        |> Glue.trigger Glue.id leaveConfirmCheckCmd
                        |> Glue.updateWith Glue.id
                            (\model_ ->
                                ( model_
                                , getVisibleCells True model_
                                    |> attemptTask
                                    |> Cmd.map config.msg
                                )
                            )
                        |> Glue.updateWith Glue.id
                            (\model_ ->
                                ( { model_ | activeDropdown = Nothing }
                                , Cmd.none
                                )
                            )
                        |> Cmd.add (getBasesPanelViewport config)
                        |> Cmd.add (getBasesPanelElement config)
                        |> Glue.updateWith Glue.id (computeSelectionMap >> Cmd.pure)

                CellLoaderMsg cellLoaderMsg ->
                    let
                        currentData =
                            XB2.Share.UndoRedo.current model.crosstabData

                        ( newCellLoaderModel, cmds ) =
                            CrosstabCellLoader.update config.cellLoaderConfig route flags p2Store cellLoaderMsg currentData.cellLoaderModel

                        newCrosstabData =
                            { currentData | cellLoaderModel = newCellLoaderModel }
                    in
                    model
                        |> updateCrosstabData (always newCrosstabData)
                        |> Cmd.with (Cmd.map config.msg cmds)

                TrackFullLoadAndProcessCmd afterQueueCmd { startTime, time } ->
                    let
                        getEvent afterLoadActionName =
                            getAnalyticsEvent TableFullyLoaded
                                { loadTime =
                                    (Time.posixToMillis time - Time.posixToMillis startTime)
                                        // 1000
                                , afterLoadAction = afterLoadActionName
                                }
                                p2Store
                                model
                                |> AnalyticsEvent
                                |> config.msg

                        fullLoadedAnalyticsCmd =
                            case afterQueueCmd of
                                ApplyHeatmapCmd _ ->
                                    getEvent "heatmap"

                                ExportTableCmd _ _ ->
                                    getEvent "export"

                                ApplySort _ ->
                                    getEvent "sorting"

                                ApplyResort _ ->
                                    getEvent "resorting"
                    in
                    model
                        |> Cmd.withTrigger fullLoadedAnalyticsCmd
                        |> Cmd.addTrigger (getAfterQueueFinishedMsg afterQueueCmd |> config.msg)

                StartExport maybeSelectionMap maybeProject ->
                    -- Here is when you already confirmed you wanted to export
                    if flags.can XB2.Share.Permissions.Export then
                        (if CrosstabCellLoader.isFullyLoaded <| .cellLoaderModel <| currentCrosstabData model then
                            ( { model | isExporting = True }
                            , Task.perform (config.msg << Export maybeSelectionMap maybeProject) Time.now
                            )

                         else
                            let
                                elementToFocus =
                                    "modal-confirmexport-close-button"
                            in
                            model
                                |> Cmd.withTrigger
                                    (config.openModal <|
                                        Modal.initConfirmFullLoadForExport
                                            maybeSelectionMap
                                            (CrosstabCellLoader.notLoadedCellCount <| .cellLoaderModel <| currentCrosstabData model)
                                            maybeProject
                                    )
                                |> Cmd.add
                                    (Task.attempt
                                        (always <| config.msg NoOp)
                                        (Dom.focus elementToFocus)
                                    )
                        )
                            |> fetchQuestionsForCrosstab config

                    else
                        model
                            |> Cmd.withTrigger config.disabledExportsAlert

                ShowSortingDialog sortConfig ->
                    let
                        notLoadedCells =
                            allNotDoneCellsForSorting (NonemptyList.singleton sortConfig) (currentCrosstab model)
                    in
                    if notLoadedCells == 0 then
                        model
                            |> Cmd.withTrigger (config.msg <| Edit <| SortBy sortConfig)

                    else
                        model
                            |> Cmd.withTrigger
                                (config.openModal <|
                                    Modal.initConfirmCellsLoadForSorting notLoadedCells sortConfig
                                )

                LoadCellsForSorting sortConfig ->
                    Cmd.pure model
                        |> updateCellLoader config
                            (CrosstabCellLoader.reloadOnlyNeededCellsForSortingWithOriginAndMsg
                                config.cellLoaderConfig
                                (ApplySort sortConfig)
                                AudienceIntersect.Table
                                (NonemptyList.singleton sortConfig)
                            )
                        |> Cmd.addTrigger config.closeModal

                FullLoadAndExport maybeSelectionMap maybeProject ->
                    Cmd.pure model
                        |> updateCellLoader config
                            (CrosstabCellLoader.reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg
                                config.cellLoaderConfig
                                (ExportTableCmd maybeSelectionMap maybeProject)
                                AudienceIntersect.Export
                            )
                        |> Cmd.addTrigger config.closeModal

                AddProgressToExportDownload amount ->
                    Cmd.pure model
                        |> updateCellLoader config
                            (\cellLoaderModal ->
                                { cellLoaderModal
                                    | openedCellLoaderModal =
                                        case cellLoaderModal.openedCellLoaderModal of
                                            CrosstabCellLoader.NoCellLoaderModal ->
                                                CrosstabCellLoader.NoCellLoaderModal

                                            CrosstabCellLoader.LoadWithoutProgress ->
                                                CrosstabCellLoader.LoadWithoutProgress

                                            CrosstabCellLoader.LoadWithProgress { currentProgress, totalProgress } ->
                                                CrosstabCellLoader.LoadWithProgress
                                                    { currentProgress = currentProgress + amount
                                                    , totalProgress = totalProgress
                                                    }
                                }
                                    |> Cmd.pure
                            )

                FocusElementById id ->
                    ( model, Task.attempt (\_ -> config.msg NoOp) (Dom.focus id) )

                BlurElementById id ->
                    ( model, Task.attempt (\_ -> config.msg NoOp) (Dom.blur id) )

                Export maybeSelectionMap maybeProject date ->
                    Cmd.pure model
                        |> updateCellLoader config
                            (\cellLoaderModal ->
                                CrosstabCellLoader.setOpenedCellLoaderModal
                                    (CrosstabCellLoader.LoadWithProgress
                                        { currentProgress = 0, totalProgress = 100 }
                                    )
                                    cellLoaderModal
                                    |> Cmd.pure
                            )
                        -- Yeah, I know...
                        |> Cmd.add (Process.sleep 200 |> Task.perform (\_ -> config.msg <| AddProgressToExportDownload 10))
                        |> Cmd.add (Process.sleep 600 |> Task.perform (\_ -> config.msg <| AddProgressToExportDownload 30))
                        |> Cmd.add (Process.sleep 1200 |> Task.perform (\_ -> config.msg <| AddProgressToExportDownload 40))
                        |> Cmd.add (Process.sleep 2000 |> Task.perform (\_ -> config.msg <| AddProgressToExportDownload 8))
                        |> Cmd.add (Process.sleep 3000 |> Task.perform (\_ -> config.msg <| AddProgressToExportDownload 11))
                        |> Glue.updateWith Glue.id (updateExport config route flags maybeSelectionMap maybeProject date p2Store)

                SwapBasesOrder originIndex destinationIndex ->
                    let
                        basesOrder : List ACrosstab.CrosstabBaseAudience
                        basesOrder =
                            NonemptyList.toList (getCrosstabBaseAudiences model)

                        activeBaseIndex : Int
                        activeBaseIndex =
                            getCurrentBaseAudienceIndex model

                        swapOrderByBasesIndices :
                            Int
                            -> Int
                            -> List ACrosstab.CrosstabBaseAudience
                            -> List ACrosstab.CrosstabBaseAudience
                        swapOrderByBasesIndices origin destination baseAudiences =
                            if destination < 0 then
                                baseAudiences

                            else if destination > List.length baseAudiences then
                                baseAudiences

                            else
                                List.swapAt origin destination baseAudiences

                        {- This function is to avoid surpassing 0 to length of
                           baseAudiences range
                        -}
                        newFocusedIndex : Int -> Maybe Int
                        newFocusedIndex newIndex_ =
                            if newIndex_ < 0 then
                                Just 0

                            else if newIndex_ >= List.length basesOrder then
                                Just <| List.length basesOrder - 1

                            else
                                Just newIndex_

                        { keyboardMovementBasesPanelModel } =
                            model

                        newBasesOrder =
                            swapOrderByBasesIndices originIndex
                                destinationIndex
                                basesOrder

                        newActiveBaseIndex : Int
                        newActiveBaseIndex =
                            if activeBaseIndex == originIndex then
                                destinationIndex

                            else if activeBaseIndex == destinationIndex then
                                originIndex

                            else
                                activeBaseIndex
                    in
                    ( { model
                        | keyboardMovementBasesPanelModel =
                            { keyboardMovementBasesPanelModel
                                | baseSelectedToMove =
                                    newFocusedIndex destinationIndex
                            }
                      }
                    , Cmd.none
                    )
                        |> Cmd.addTrigger
                            (config.msg <|
                                Edit <|
                                    ApplyNewBaseAudiencesOrder
                                        { triggeredFrom = Analytics.Keyboard
                                        , shouldFireAnalytics = True
                                        }
                                        newBasesOrder
                                        newActiveBaseIndex
                            )
                        |> Cmd.addTrigger
                            (config.msg <|
                                SetBaseIndexFocused <|
                                    newFocusedIndex destinationIndex
                            )

                SetBaseIndexFocused maybeIndex ->
                    let
                        { keyboardMovementBasesPanelModel } =
                            model
                    in
                    ( { model
                        | keyboardMovementBasesPanelModel =
                            { keyboardMovementBasesPanelModel
                                | baseFocused = maybeIndex
                            }
                      }
                    , case maybeIndex of
                        Just index ->
                            Dom.focus
                                (Common.basePanelTabElementId index)
                                |> Task.attempt (\_ -> config.msg NoOp)

                        Nothing ->
                            Cmd.none
                    )

                SetBaseIndexSelectedToMoveWithKeyboard maybeIndex ->
                    let
                        { keyboardMovementBasesPanelModel } =
                            model
                    in
                    ( { model
                        | keyboardMovementBasesPanelModel =
                            { keyboardMovementBasesPanelModel
                                | baseSelectedToMove = maybeIndex
                            }
                      }
                    , Cmd.none
                    )

                ExportSuccess response ->
                    let
                        ( newModelWithCellLoaderModalClosed, _ ) =
                            Cmd.pure model
                                |> updateCellLoader config
                                    (\cellLoaderModal ->
                                        CrosstabCellLoader.setOpenedCellLoaderModal
                                            CrosstabCellLoader.NoCellLoaderModal
                                            cellLoaderModal
                                            |> Cmd.pure
                                    )
                    in
                    -- Export is completed here
                    ( { newModelWithCellLoaderModalClosed
                        | isExporting = False
                      }
                    , case response of
                        XB2.Share.Export.Mail { message } ->
                            Cmd.perform <|
                                config.createDetailNotification P2Icons.export <|
                                    Html.text message

                        XB2.Share.Export.DirectDownload { downloadUrl } ->
                            Cmd.perform
                                (config.createDetailPersistentNotification exportNotificationId <|
                                    Notification.exportView
                                        { downloadMsg = DownloadFile downloadUrl
                                        , closeMsg = CloseDetailNotification
                                        }
                                )
                    )

                CloseDetailNotification ->
                    model
                        |> Cmd.withTrigger (config.closeDetailNotification exportNotificationId)

                DownloadFile downloadUrl ->
                    ( model, XB2.Share.Export.urlDownload downloadUrl )
                        |> Cmd.addTrigger (config.closeDetailNotification exportNotificationId)

                ExportFailure httpError ->
                    let
                        ( newModelWithCellLoaderModalClosed, _ ) =
                            Cmd.pure model
                                |> updateCellLoader config
                                    (\cellLoaderModal ->
                                        CrosstabCellLoader.setOpenedCellLoaderModal
                                            CrosstabCellLoader.NoCellLoaderModal
                                            cellLoaderModal
                                            |> Cmd.pure
                                    )
                    in
                    -- Export fails here
                    ( { newModelWithCellLoaderModalClosed
                        | isExporting = False
                      }
                    , Cmd.perform <| config.exportAjaxError httpError
                    )

                NavigateTo route_ ->
                    let
                        { crosstabSearchModel } =
                            model
                    in
                    -- Clear search bar
                    ( { model
                        | crosstabSearchModel =
                            { term = ""
                            , sanitizedTerm = ""
                            , inputDebouncer = Debouncer.cancel crosstabSearchModel.inputDebouncer
                            , searchTopLeftScrollJumps = Nothing
                            , inputIsFocused = False
                            }
                      }
                    , Cmd.batch
                        [ Cmd.perform <| config.navigateTo route_
                        , Cmd.perform (config.closeDetailNotification exportNotificationId)
                        ]
                    )

                OpenMetricsSelection ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-metrics-reset-all"
                    in
                    model
                        |> closeDropdown
                        |> Cmd.withTrigger
                            (config.openModal <|
                                Modal.initChooseMetrics
                                    (AssocSet.fromList
                                        (currentMetadata model |> .activeMetrics)
                                    )
                            )
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                ApplyHeatmap metric ->
                    case ( CrosstabCellLoader.isFullyLoaded <| .cellLoaderModel <| currentCrosstabData model, metric ) of
                        ( False, Just metricValue ) ->
                            model
                                |> Cmd.withTrigger
                                    (config.openModal <|
                                        Modal.initConfirmFullLoadForHeatmap
                                            (CrosstabCellLoader.notLoadedCellCount <| .cellLoaderModel <| currentCrosstabData model)
                                            metricValue
                                    )

                        _ ->
                            let
                                analyticsCmd =
                                    metric
                                        |> Maybe.map (\metric_ -> getAnalyticsCmd flags route HeatmapApplied { metric = metric_ } p2Store model)
                                        |> Maybe.withDefault Cmd.none
                            in
                            { model | heatmapMetric = metric }
                                |> Cmd.withTrigger config.closeModal
                                |> Cmd.add analyticsCmd

                FullLoadAndApplyHeatmap metric ->
                    Cmd.pure model
                        |> updateCellLoader config
                            (CrosstabCellLoader.reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg
                                config.cellLoaderConfig
                                (ApplyHeatmapCmd metric)
                                AudienceIntersect.Heatmap
                            )
                        |> Cmd.addTrigger config.closeModal

                CancelFullTableLoad ->
                    case currentCrosstabData model |> .cellLoaderModel |> CrosstabCellLoader.getAfterAction of
                        Just (ApplyHeatmapCmd _) ->
                            model
                                |> Cmd.withTrigger (config.openModal Modal.ConfirmCancelApplyingHeatmap)

                        Just (ExportTableCmd _ _) ->
                            model
                                |> Cmd.withTrigger (config.openModal Modal.ConfirmCancelExport)

                        Just (ApplySort _) ->
                            model
                                |> Cmd.withTrigger (config.openModal Modal.ConfirmCancelCellsSorting)

                        Just (ApplyResort _) ->
                            model
                                |> Cmd.withTrigger (config.openModal Modal.ConfirmCancelFullScreenTableLoad)

                        Nothing ->
                            cancelAllLoadingRequests config flags p2Store model

                ConfirmCancelFullTableLoad ->
                    cancelAllLoadingRequests config flags p2Store { model | heatmapMetric = Nothing }

                ToggleViewOptionsDropdown ->
                    ( toggleViewOptionsDropdown model
                    , Cmd.none
                    )

                ToggleBulkFreezeDropdown ->
                    ( toggleBulkFreezeDropdown model
                    , Cmd.none
                    )

                ToggleHeaderCollapsed ->
                    let
                        newModel =
                            toggleHeaderCollapsed model
                    in
                    trackHeaderCollapsed newModel.isHeaderCollapsed route flags p2Store newModel

                SetHeaderCollapsed shouldCollapseHeader ->
                    ( setCollapsedHeaderAs model shouldCollapseHeader
                    , Cmd.none
                    )

                ToggleSortByNameDropdown ->
                    ( toggleSortByNameDropdown model
                    , Cmd.none
                    )

                ToggleAllBasesDropdown ->
                    ( toggleDropdown AllBasesDropdown model
                    , Cmd.none
                    )

                ToggleFixedPageDropdown dropDownMenu ->
                    let
                        focusElement : String
                        focusElement =
                            "button-item-dropmenu"
                    in
                    toggleDropdown (FixedPageDropdown dropDownMenu) model
                        |> Cmd.with
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus focusElement)
                            )

                GetBasesPanelWidth ->
                    getBasesPanelWidth config.msg model

                SetBasesPanelWidth basesPanelWidth ->
                    Cmd.pure { model | basesPanelWidth = basesPanelWidth }

                CloseDropdown ->
                    let
                        dropDownMenuId : Maybe String
                        dropDownMenuId =
                            DropdownMenu.getDropdownId (getDropdownMenu model)

                        elementToFocus : String
                        elementToFocus =
                            case dropDownMenuId of
                                Just idvalidate ->
                                    "icon-ellipsis-id-" ++ idvalidate

                                Nothing ->
                                    ""
                    in
                    closeDropdown model
                        |> Cmd.with
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                RenameBaseAudience baseAudience ->
                    let
                        openModalMsg =
                            config.openModal <| Modal.initRenameBaseAudience baseAudience
                    in
                    model
                        |> Cmd.withTrigger openModalMsg

                SelectRowOrColumnMouseDown position ->
                    Cmd.pure { model | tableSelectionMouseDown = MouseDown { firstPosition = position, moved = False } }

                SelectAction selectActionType ->
                    updateSelectAction config route flags selectActionType model
                        |> Glue.updateWith Glue.id (computeSelectionMap >> Cmd.pure)

                SetCurrentTime timezone posix ->
                    ( { model
                        | currentTime = posix
                        , timezone = timezone
                      }
                    , Cmd.none
                    )

                OpenSaveAsNew name ->
                    model
                        |> Cmd.withTrigger (config.openModal <| Modal.initSaveProjectAsNew name)

                SaveAsCopy originalProject ->
                    saveProjectSharedWithMeAsCopy
                        { shouldRedirect = True }
                        originalProject
                        xbStore
                        flags
                        config
                        model

                SaveProjectAsNew name ->
                    model
                        |> Cmd.withTrigger
                            (config.createXBProject
                                (getNewProjectFromCrosstab flags name model)
                            )

                SaveEdited xbProject ->
                    saveEditedProject config flags xbProject model

                RenameCrosstab xbProject ->
                    model
                        |> Cmd.withTrigger (config.openModal <| Modal.initRenameProject xbProject)

                DebounceForSearchTermChange debouncerSubMsg ->
                    let
                        { crosstabSearchModel } =
                            model

                        ( newDebouncer, subCmd, emittedMsg ) =
                            Debouncer.update debouncerSubMsg crosstabSearchModel.inputDebouncer

                        mappedCmd =
                            Cmd.map (\debouncerMsg -> config.msg (DebounceForSearchTermChange debouncerMsg)) subCmd

                        updatedModel =
                            { model
                                | crosstabSearchModel =
                                    { crosstabSearchModel
                                        | inputDebouncer = newDebouncer
                                    }
                            }
                    in
                    case emittedMsg of
                        Just emitted ->
                            ( updatedModel, Cmd.perform (config.msg emitted) )
                                |> Cmd.add mappedCmd

                        Nothing ->
                            ( updatedModel, mappedCmd )

                ChangeSearchTerm str ->
                    let
                        { crosstabSearchModel } =
                            model

                        debounceMsg =
                            if String.length str < 3 then
                                Cmd.none

                            else
                                Cmd.perform
                                    (config.msg <|
                                        DebounceForSearchTermChange
                                            (Debouncer.provideInput FilterRowsAndColsThatMatchSearchTerm)
                                    )

                        debouncerCancelledIfNoRequiredLength =
                            if String.length str < 3 then
                                Debouncer.cancel crosstabSearchModel.inputDebouncer

                            else
                                crosstabSearchModel.inputDebouncer

                        searchResultsBasedOnRequiredLength =
                            if String.length str < 3 then
                                Nothing

                            else
                                crosstabSearchModel.searchTopLeftScrollJumps
                    in
                    ( { model
                        | crosstabSearchModel =
                            { crosstabSearchModel
                                | term = str
                                , sanitizedTerm = sanitizeSearchTerm str
                                , inputDebouncer = debouncerCancelledIfNoRequiredLength
                                , searchTopLeftScrollJumps = searchResultsBasedOnRequiredLength
                            }
                      }
                    , debounceMsg
                    )

                FilterRowsAndColsThatMatchSearchTerm ->
                    let
                        { crosstabSearchModel } =
                            model

                        rowsMatch =
                            getCrosstabRowsThatMatchSearchTermWithIndex crosstabSearchModel.sanitizedTerm (currentCrosstab model)

                        colsMatch =
                            getCrosstabColumnsThatMatchSearchTermWithIndex crosstabSearchModel.sanitizedTerm (currentCrosstab model)

                        finalSearchResults =
                            ListZipper.fromList (List.map (\( index, direction ) -> { index = index, direction = direction }) (colsMatch ++ rowsMatch))

                        scrollMsgBasedOnNewSearchResults =
                            case Maybe.map ListZipper.current finalSearchResults of
                                Just { index, direction } ->
                                    case direction of
                                        Row ->
                                            ScrollBasedOnRowIndex index

                                        Column ->
                                            ScrollBasedOnColumnIndex index

                                Nothing ->
                                    NoOp
                    in
                    ( { model
                        | crosstabSearchModel =
                            { crosstabSearchModel
                                | searchTopLeftScrollJumps = finalSearchResults
                            }
                      }
                    , scrollMsgBasedOnNewSearchResults
                        |> config.msg
                        |> Cmd.perform
                    )

                SetCrosstabSearchInputFocus bool ->
                    let
                        { crosstabSearchModel } =
                            model
                    in
                    ( { model
                        | crosstabSearchModel =
                            { crosstabSearchModel
                                | inputIsFocused = bool
                            }
                      }
                    , Cmd.none
                    )

                GoToPreviousSearchResult ->
                    let
                        { crosstabSearchModel } =
                            model

                        searchResults =
                            crosstabSearchModel.searchTopLeftScrollJumps

                        newSearchResults =
                            Maybe.map ListZipper.attemptPrev searchResults

                        scrollMsgBasedOnNewSearchResults =
                            case Maybe.map ListZipper.current newSearchResults of
                                Just { index, direction } ->
                                    case direction of
                                        Row ->
                                            ScrollBasedOnRowIndex index

                                        Column ->
                                            ScrollBasedOnColumnIndex index

                                Nothing ->
                                    NoOp
                    in
                    ( { model
                        | crosstabSearchModel =
                            { crosstabSearchModel
                                | searchTopLeftScrollJumps = newSearchResults
                            }
                      }
                    , scrollMsgBasedOnNewSearchResults
                        |> config.msg
                        |> Cmd.perform
                    )
                        |> Cmd.add (Cmd.perform <| config.msg <| FocusElementById Common.crosstabSearchId)

                GoToNextSearchResult ->
                    let
                        { crosstabSearchModel } =
                            model

                        searchResults =
                            crosstabSearchModel.searchTopLeftScrollJumps

                        newSearchResults =
                            Maybe.map ListZipper.attemptNext searchResults

                        scrollMsgBasedOnNewSearchResults =
                            case Maybe.map ListZipper.current newSearchResults of
                                Just { index, direction } ->
                                    case direction of
                                        Row ->
                                            ScrollBasedOnRowIndex index

                                        Column ->
                                            ScrollBasedOnColumnIndex index

                                Nothing ->
                                    NoOp
                    in
                    ( { model
                        | crosstabSearchModel =
                            { crosstabSearchModel
                                | searchTopLeftScrollJumps = newSearchResults
                            }
                      }
                    , scrollMsgBasedOnNewSearchResults
                        |> config.msg
                        |> Cmd.perform
                    )
                        |> Cmd.add (Cmd.perform <| config.msg <| FocusElementById Common.crosstabSearchId)

                TableScroll { shouldReloadTable, position } ->
                    let
                        ( top, left ) =
                            position
                    in
                    (if top == 0 && left == 0 then
                        { model
                            | autoScroll = Nothing
                        }

                     else if top == 0 && left > 0 then
                        { model
                            | autoScroll = Maybe.filter ((/=) Row) model.autoScroll
                        }

                     else if top > 0 && left == 0 then
                        { model
                            | autoScroll = Maybe.filter ((/=) Column) model.autoScroll
                        }

                     else
                        model
                    )
                        |> Cmd.pure
                        |> Tuple.mapFirst (resolveIsScrollingState shouldReloadTable position)
                        |> Glue.updateWith Glue.id
                            (\model_ ->
                                ( closeDropdown model_
                                , getVisibleCells shouldReloadTable model_
                                    |> attemptTask
                                    |> Cmd.map config.msg
                                )
                            )

                SetVisibleCellsAndTableOffset { shouldReloadTable, topOffset, visibleCells } ->
                    { model | tableCellsTopOffset = topOffset }
                        |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.setCellsVisibility shouldReloadTable visibleCells))
                        |> (if shouldReloadTable then
                                reloadNotLoadedCells config flags p2Store

                            else
                                Cmd.pure
                           )

                AutoScroll direction ->
                    ( model, autoScrollCmd config direction )

                DeleteCrosstab xbProject ->
                    model
                        |> Cmd.withTrigger (config.openModal <| Modal.initConfirmDeleteProject xbProject)

                DuplicateCrosstab xbProject ->
                    model
                        |> Cmd.withTrigger
                            (config.openModal <|
                                Modal.initDuplicateProject
                                    (NewName.duplicateName
                                        (XBStore.projectNameExists xbStore)
                                        xbProject.name
                                    )
                                    xbProject
                            )

                OpenShareProjectModal xbProject ->
                    let
                        elementToFocus =
                            "share-modal-focus-text"
                    in
                    model
                        |> closeDropdown
                        |> Cmd.withTrigger (config.openSharingModal xbProject)
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                ViewGroupExpression item ->
                    let
                        openModal =
                            modalForViewGroupExpression item
                                |> Cmd.fromMaybe config.openModal
                    in
                    model
                        |> closeDropdown
                        |> Cmd.with openModal

                OpenRenameAverageModal direction item ->
                    ( closeDropdown model
                    , Cmd.perform <| config.openModal <| Modal.initRenameAverage direction item
                    )

                OpenSaveAsAudienceModal item ->
                    model
                        |> Cmd.withTrigger (openSaveAsAudienceModalForTableItems config [ item ])

                OpenSelectedSaveAsAudienceModal ->
                    model
                        |> Cmd.withTrigger (openSaveAsAudienceModal config model)

                OpenSaveBaseInMyAudiencesModal baseAudience ->
                    model
                        |> Cmd.withTrigger
                            (Modal.SaveAsBaseAudience baseAudience
                                |> Just
                                |> saveAsAudienceModalMsg config
                            )

                OpenAffixBaseAudienceModalForSelected ->
                    case ACrosstab.getSelectedBases (currentCrosstab model) of
                        Just selectedBases ->
                            model
                                |> Cmd.withTrigger
                                    (Modal.initAttributesAffixBaseModal
                                        selectedBases
                                        (getActiveWaves model)
                                        (getActiveLocations model)
                                        (currentCrosstab model
                                            |> ACrosstab.getSelectedBases
                                            |> Maybe.unwrap 0 NonemptyList.length
                                        )
                                        |> config.openModal
                                    )

                        Nothing ->
                            Cmd.pure model

                OpenAffixBaseAudienceModalForSingle baseAudience ->
                    model
                        |> Cmd.withTrigger
                            (Modal.initAttributesAffixBaseModal
                                (NonemptyList.singleton baseAudience)
                                (getActiveWaves model)
                                (getActiveLocations model)
                                (currentCrosstab model
                                    |> ACrosstab.getSelectedBases
                                    |> Maybe.unwrap 0 NonemptyList.length
                                )
                                |> config.openModal
                            )

                OpenEditBaseAudienceModalForSingle baseAudience ->
                    let
                        baseAudienceQuestionCodes =
                            BaseAudience.getExpression baseAudience
                                |> Expression.getQuestionCodes

                        fetchQuestionsCmd =
                            baseAudienceQuestionCodes
                                |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                                |> config.fetchManyP2
                    in
                    model
                        |> Cmd.withTrigger fetchQuestionsCmd
                        |> Cmd.addTrigger (config.openModal Modal.FetchQuestionsForEditModal)
                        |> Cmd.addTrigger
                            (OpenEditBaseAudienceModalForSingleOnceQuestionsAreReadyInStore baseAudience { timeout = 0 }
                                |> config.msg
                            )

                OpenEditBaseAudienceModalForSingleOnceQuestionsAreReadyInStore baseAudience { timeout } ->
                    let
                        baseAudienceQuestionCodes =
                            BaseAudience.getExpression baseAudience
                                |> Expression.getQuestionCodes

                        areAllQuestionCodesPresentInStore =
                            baseAudienceQuestionCodes
                                |> List.all
                                    (\questionCode ->
                                        Dict.Any.get questionCode p2Store.questions
                                            |> Maybe.map (\questionWeWant -> RemoteData.isSuccess questionWeWant)
                                            |> Maybe.withDefault False
                                    )
                    in
                    if areAllQuestionCodesPresentInStore || timeout >= 10000 then
                        let
                            maybeFirstGroupTitle =
                                Caption.getFullName (BaseAudience.getCaption baseAudience)

                            baseAudienceAsSelectedItem =
                                ModalBrowser.expressionToSelectedItem
                                    { maybeFirstGroupTitle = Just maybeFirstGroupTitle, questions = p2Store.questions }
                                    (BaseAudience.getExpression baseAudience)
                        in
                        model
                            |> Cmd.withTrigger
                                (Modal.initAttributesEditBaseModal
                                    (NonemptyList.singleton baseAudience)
                                    [ baseAudienceAsSelectedItem ]
                                    (getActiveWaves model)
                                    (getActiveLocations model)
                                    (currentCrosstab model
                                        |> ACrosstab.getSelectedBases
                                        |> Maybe.unwrap 0 NonemptyList.length
                                    )
                                    |> config.openModal
                                )

                    else
                        model
                            |> Cmd.with
                                (Task.perform
                                    (\_ -> config.msg (OpenEditBaseAudienceModalForSingleOnceQuestionsAreReadyInStore baseAudience { timeout = timeout + 200 }))
                                    (Process.sleep 200)
                                )

                OpenAttributeBrowser { affixedFrom } ->
                    let
                        nonemptyAllSelected =
                            getAllSelected model
                                |> NonemptyList.fromList

                        openModalFn =
                            case nonemptyAllSelected of
                                Nothing ->
                                    Modal.initAttributesAddModal

                                Just allSelected ->
                                    Modal.initAttributesAffixModal affixedFrom allSelected

                        trackAnalytics =
                            if affixedFrom /= Analytics.AddAttributeButton then
                                Cmd.add (track flags route <| Analytics.AffixAttributesOrAudiences affixedFrom)

                            else
                                Cmd.add (track flags route <| Analytics.OpenAttributeBrowser Analytics.OpenForTable)

                        waves =
                            let
                                set =
                                    getActiveWaves model
                            in
                            if Set.Any.isEmpty set then
                                RemoteData.toMaybe p2Store.waves
                                    |> Maybe.map (Dict.Any.keys >> XB2.Share.Data.Id.setFromList)
                                    |> Maybe.withDefault set

                            else
                                set

                        locations =
                            let
                                set =
                                    getActiveLocations model
                            in
                            if Set.Any.isEmpty set then
                                RemoteData.toMaybe p2Store.locations
                                    |> Maybe.map (Dict.Any.keys >> XB2.Share.Data.Id.setFromList)
                                    |> Maybe.withDefault set

                            else
                                set

                        elementToFocus : String
                        elementToFocus =
                            "modal-close-header-modal"
                    in
                    ( model
                    , Cmd.perform <|
                        config.openModal <|
                            openModalFn
                                waves
                                locations
                                (currentCrosstab model
                                    |> ACrosstab.getSelectedBases
                                    |> Maybe.unwrap 0 NonemptyList.length
                                )
                    )
                        |> trackAnalytics
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                OpenAffixTableModalForSingle item ->
                    ( model
                    , Cmd.batch
                        [ Cmd.perform <|
                            config.openModal <|
                                Modal.initAttributesAffixModal
                                    Analytics.FromDropDownMenu
                                    (NonemptyList.singleton item)
                                    (getActiveWaves model)
                                    (getActiveLocations model)
                                    (currentCrosstab model
                                        |> ACrosstab.getSelectedBases
                                        |> Maybe.unwrap 0 NonemptyList.length
                                    )
                        , track flags route <| Analytics.AffixAttributesOrAudiences Analytics.FromDropDownMenu
                        ]
                    )

                OpenEditTableModalForSingle ( direction, key ) ->
                    let
                        audienceItemQuestionCodes =
                            case AudienceItem.getDefinition key.item of
                                XBData.Expression expression ->
                                    Expression.getQuestionCodes expression

                                XBData.Average _ ->
                                    []

                        fetchQuestionsCmd =
                            audienceItemQuestionCodes
                                |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                                |> config.fetchManyP2
                    in
                    model
                        |> Cmd.withTrigger fetchQuestionsCmd
                        |> Cmd.addTrigger (config.openModal Modal.FetchQuestionsForEditModal)
                        |> Cmd.addTrigger
                            (OpenEditTableModalForSingleOnceQuestionsAreReadyInStore ( direction, key ) { timeout = 0 }
                                |> config.msg
                            )

                OpenEditTableModalForSingleOnceQuestionsAreReadyInStore ( direction, key ) { timeout } ->
                    let
                        audienceItemQuestionCodes =
                            case AudienceItem.getDefinition key.item of
                                XBData.Expression expression ->
                                    Expression.getQuestionCodes expression

                                XBData.Average _ ->
                                    []

                        areAllQuestionCodesPresentInStore =
                            audienceItemQuestionCodes
                                |> List.all
                                    (\questionCode ->
                                        Dict.Any.get questionCode p2Store.questions
                                            |> Maybe.map (\questionWeWant -> RemoteData.isSuccess questionWeWant)
                                            |> Maybe.withDefault False
                                    )
                    in
                    if areAllQuestionCodesPresentInStore || timeout >= 10000 then
                        let
                            audienceItemAsSelectedItems =
                                case AudienceItem.getDefinition key.item of
                                    XBData.Expression expression ->
                                        let
                                            maybeFirstGroupTitle =
                                                Caption.getFullName (AudienceItem.getCaption key.item)
                                        in
                                        ModalBrowser.expressionToSelectedItem
                                            { maybeFirstGroupTitle = Just maybeFirstGroupTitle, questions = p2Store.questions }
                                            expression
                                            |> (\item -> [ item ])

                                    XBData.Average _ ->
                                        []
                        in
                        model
                            |> Cmd.withTrigger
                                (Modal.initAttributesEditModal
                                    (NonemptyList.singleton ( direction, key ))
                                    audienceItemAsSelectedItems
                                    (getActiveWaves model)
                                    (getActiveLocations model)
                                    (currentCrosstab model
                                        |> ACrosstab.getSelectedBases
                                        |> Maybe.unwrap 0 NonemptyList.length
                                    )
                                    |> config.openModal
                                )

                    else
                        model
                            |> Cmd.with
                                (Task.perform
                                    (\_ -> config.msg (OpenEditTableModalForSingleOnceQuestionsAreReadyInStore ( direction, key ) { timeout = timeout + 200 }))
                                    (Process.sleep 200)
                                )

                OpenAttributeBrowserForAddBase ->
                    ( model
                    , Cmd.perform <|
                        config.openModal <|
                            Modal.initAttributesAddBaseModal
                                (getActiveWaves model)
                                (getActiveLocations model)
                                (currentCrosstab model
                                    |> ACrosstab.getSelectedBases
                                    |> Maybe.unwrap 0 NonemptyList.length
                                )
                    )
                        |> Cmd.add (track flags route <| Analytics.OpenAttributeBrowser Analytics.OpenForBase)

                OpenAttributeBrowserForReplacingDefaultBase ->
                    ( model
                    , Cmd.perform <|
                        config.openModal <|
                            Modal.initAttributesReplaceDefaultBaseModal
                                (getActiveWaves model)
                                (getActiveLocations model)
                                (currentCrosstab model
                                    |> ACrosstab.getSelectedBases
                                    |> Maybe.unwrap 0 NonemptyList.length
                                )
                    )

                OpenRemoveFromTableConfirmModal ->
                    let
                        allSelected : List ( Direction, ACrosstab.Key )
                        allSelected =
                            getAllSelected model

                        modalCmd =
                            Modal.initConfirmRemoveRowsColumns allSelected
                                |> config.openModal
                                |> Cmd.perform

                        modalOrRemove =
                            xbStore.userSettings
                                |> RemoteData.map
                                    (\settings ->
                                        if XBData.canShow XBData.DeleteRowsColumnsModal settings then
                                            Cmd.batch
                                                [ modalCmd
                                                , getAnalyticsCmd flags route RowsColsDeletionModalOpened {} p2Store model
                                                ]

                                        else
                                            Cmd.perform <| config.msg <| Edit <| RemoveSelectedAudiences True allSelected
                                    )
                                |> RemoteData.withDefault modalCmd
                    in
                    model
                        |> Cmd.with modalOrRemove

                OpenRemoveBasesConfirmModal bases ->
                    let
                        modalCmd =
                            NonemptyList.toList bases
                                |> Modal.initConfirmRemoveBases
                                |> config.openModal
                                |> Cmd.perform

                        modalOrRemove =
                            xbStore.userSettings
                                |> RemoteData.map
                                    (\settings ->
                                        if XBData.canShow XBData.DeleteBasesModal settings then
                                            Cmd.batch
                                                [ modalCmd
                                                , getAnalyticsCmd flags route BasesDeletionModalOpened {} p2Store model
                                                ]

                                        else
                                            Cmd.perform <| config.msg <| Edit <| RemoveBaseAudiences True bases
                                    )
                                |> RemoteData.withDefault modalCmd
                    in
                    Cmd.with modalOrRemove model

                AddSelectionAsNewBase ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-close-header-modal"
                    in
                    addNewBase config route flags p2Store model
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                MergeSelectedRowOrColum ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-close-header-modal"
                    in
                    mergeRowColum config model
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                ViewAffixGroupModalFromAttributeBrowser operator grouping attributeBrowserModal affixedFrom addedItems ->
                    Maybe.map2
                        (\groupCaption items ->
                            model
                                |> Cmd.withTrigger (affixModalOpenMsg config grouping items groupCaption operator affixedFrom attributeBrowserModal)
                        )
                        (captionsFromAttributeBrowser grouping addedItems)
                        (itemsFromAttributeBrowser grouping addedItems)
                        |> Maybe.withDefault (Cmd.pure model)

                ViewEditGroupModalFromAttributeBrowser grouping attributeBrowserModal newItems ->
                    Maybe.map2
                        (\groupCaption items ->
                            model
                                |> Cmd.withTrigger (editModalOpenMsg config grouping items groupCaption attributeBrowserModal)
                        )
                        (captionsFromAttributeBrowser grouping newItems)
                        (itemsFromAttributeBrowser grouping newItems)
                        |> Maybe.withDefault (Cmd.pure model)

                AddAsNewBase itemToAdd ->
                    addNewBases config route flags p2Store [ Tuple.second itemToAdd ] model

                CreateNewBases grouping items ->
                    createBaseFromItems config route flags grouping p2Store items model

                OpenHeatmapSelection ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-heatmap-reset-all-button"
                    in
                    model
                        |> Cmd.withTrigger
                            (config.openModal <|
                                Modal.initChooseHeatmapMetric model.heatmapMetric
                            )
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                OpenMinimumSampleSizeModal ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-minimum-sample-size-text-input"

                        currentMinimumSampleSize =
                            currentMetadata model
                                |> .minimumSampleSize
                    in
                    model
                        |> Cmd.withTrigger
                            (config.openModal <|
                                Modal.initMinimumSampleSize currentMinimumSampleSize
                            )
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                DownloadDebugDump ->
                    let
                        filename =
                            ("XB Dump " ++ DateFormat.format XB2.Share.Time.Format.format_YYYY_MM_DD_hh_mm model.timezone model.currentTime ++ ".txt")
                                |> String.replace " " "_"

                        contents =
                            XB2.DebugDump.dump flags model p2Store
                    in
                    ( model
                    , XB2.Share.Export.stringDownload
                        { contents = contents
                        , mimeType = "text/plain"
                        , filename = filename
                        }
                    )

                GoToBaseAtIndex index ->
                    let
                        sort =
                            currentMetadata model |> .sort

                        goToBaseAtIndexResult =
                            ACrosstab.goToBaseAtIndex
                                index
                                sort
                                (currentCrosstab model)
                    in
                    case goToBaseAtIndexResult of
                        Just ( audienceCrosstab, commands ) ->
                            let
                                sortCellsMsg : SortConfig -> msg
                                sortCellsMsg =
                                    config.msg << Resort << NonemptyList.singleton

                                testAndSort : AxisSort -> Axis -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
                                testAndSort mode axis =
                                    if Sort.needsDataReload mode then
                                        sortCellsMsg { mode = mode, axis = axis }
                                            |> Cmd.addTrigger

                                    else
                                        identity

                                handleSorting : ( Model, Cmd msg ) -> ( Model, Cmd msg )
                                handleSorting =
                                    sort
                                        |> (\{ rows, columns } ->
                                                testAndSort rows Rows >> testAndSort columns Columns
                                           )
                            in
                            model
                                |> updateCrosstabData (setAudienceCrosstab audienceCrosstab)
                                |> Cmd.with
                                    (Dom.scrollToIfNotVisible
                                        { scrollParentId = Common.basesPanelScrollableId
                                        , elementId = Common.basePanelTabElementId index
                                        }
                                        |> Task.attempt (always <| config.msg NoOp)
                                    )
                                |> updateCellLoader config
                                    (CrosstabCellLoader.interpretCommands config.cellLoaderConfig flags p2Store AudienceIntersect.Table commands)
                                |> handleSorting

                        Nothing ->
                            Cmd.pure model

                ToggleBaseAudience baseAudience ->
                    let
                        audienceCrosstab =
                            model.crosstabData
                                |> XB2.Share.UndoRedo.current
                                |> currentCrosstabFromData

                        selectedBases =
                            ACrosstab.toggleBaseAudience baseAudience audienceCrosstab
                                |> ACrosstab.selectedBases

                        ( datapointCodes, questionCodes ) =
                            selectedBases
                                |> List.foldl
                                    (\base ( dp, q ) ->
                                        BaseAudience.getExpression base
                                            |> (\expression ->
                                                    ( Set.Any.union dp
                                                        (Expression.getQuestionAndDatapointCodes expression
                                                            |> XB2.Share.Data.Id.setFromList
                                                        )
                                                    , Set.Any.union q
                                                        (Expression.getQuestionCodes expression
                                                            |> XB2.Share.Data.Id.setFromList
                                                        )
                                                    )
                                               )
                                    )
                                    ( XB2.Share.Data.Id.emptySet, XB2.Share.Data.Id.emptySet )

                        isBeingSelected =
                            List.length (ACrosstab.selectedBases audienceCrosstab)
                                < List.length selectedBases

                        analyticsCmd : Cmd msg
                        analyticsCmd =
                            if isBeingSelected then
                                let
                                    appliedBases =
                                        audienceCrosstab
                                            |> ACrosstab.getBaseAudiences
                                            |> ListZipper.map Analytics.prepareBaseForTracking
                                            |> ListZipper.toList
                                in
                                track flags route <|
                                    BaseSelected
                                        { appliedBases = appliedBases
                                        , selectedBases = selectedBases
                                        , questionCodes = Set.Any.toList questionCodes
                                        , datapointCodes = Set.Any.toList datapointCodes
                                        }

                            else
                                Cmd.none

                        elementToFocus : String
                        elementToFocus =
                            "modal-selection-bases-select-all-button"
                    in
                    model
                        |> updateCrosstabData (updateAudienceCrosstab (ACrosstab.toggleBaseAudience baseAudience))
                        |> Cmd.with analyticsCmd
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                SelectAllBasesInPanel ->
                    model
                        |> updateCrosstabData (updateAudienceCrosstab ACrosstab.selectAllBases)
                        |> Cmd.pure

                ClearBasesPanelSelection ->
                    model
                        |> updateCrosstabData (updateAudienceCrosstab ACrosstab.clearBasesSelection)
                        |> Cmd.pure

                Resort sortConfigs ->
                    sortConfigs
                        |> NonemptyList.foldr
                            (\sortConfig ->
                                updateResort sortConfig
                            )
                            model
                        |> Cmd.pure

                DiscardSortForAxis axis ->
                    model
                        |> discardSortForAxis axis
                        |> Cmd.pure

                TurnOffViewSettingsAndContinue ->
                    let
                        resetAxisIfSorted : Axis -> AxisSort -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
                        resetAxisIfSorted axis mode =
                            if mode == NoSort then
                                identity

                            else
                                Cmd.addTrigger (config.msg <| DiscardSortForAxis axis)

                        resetSortingActions =
                            getCurrentSort model
                                |> (\{ rows, columns } ->
                                        resetAxisIfSorted Rows rows
                                            >> resetAxisIfSorted Columns columns
                                   )
                    in
                    { model | heatmapMetric = Nothing }
                        |> Cmd.withTrigger config.closeModal
                        |> resetSortingActions

                CancelSortingLoading ->
                    let
                        resetAxisIfSorted : Axis -> AxisSort -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
                        resetAxisIfSorted axis mode =
                            if Sort.needsDataReload mode then
                                Cmd.addTrigger (config.msg <| DiscardSortForAxis axis)

                            else
                                identity

                        resetSortingActions =
                            getCurrentSort model
                                |> (\{ rows, columns } ->
                                        resetAxisIfSorted Rows rows
                                            >> resetAxisIfSorted Columns columns
                                   )
                    in
                    { model | heatmapMetric = Nothing }
                        |> cancelAllLoadingRequests config flags p2Store
                        |> Cmd.addTrigger config.closeModal
                        |> resetSortingActions

                KeepViewSettingsAndContinue ->
                    let
                        processResort sortConfigs =
                            updateCellLoader config
                                (CrosstabCellLoader.reloadOnlyNeededCellsForSortingWithOriginAndMsg
                                    config.cellLoaderConfig
                                    (ApplyResort sortConfigs)
                                    AudienceIntersect.Table
                                    sortConfigs
                                )

                        addConfigIfSorting axis mode =
                            if Sort.isSorting mode then
                                (::) { axis = axis, mode = mode }

                            else
                                identity

                        sortActions =
                            getCurrentSort model
                                |> (\{ rows, columns } ->
                                        addConfigIfSorting Columns columns []
                                            |> addConfigIfSorting Rows rows
                                            |> NonemptyList.fromList
                                            |> Maybe.unwrap identity processResort
                                   )

                        heatmapAction =
                            Maybe.unwrap identity
                                (\heatmapMetric ->
                                    updateCellLoader config
                                        (CrosstabCellLoader.reloadNotAskedCellsIfFullLoadRequestedWithOriginAndMsg
                                            config.cellLoaderConfig
                                            (ApplyHeatmapCmd heatmapMetric)
                                            AudienceIntersect.Heatmap
                                        )
                                )
                                model.heatmapMetric

                        cellsLoadingAction =
                            heatmapAction
                                >> sortActions
                    in
                    model
                        |> Cmd.withTrigger config.closeModal
                        |> cellsLoadingAction

                ScrollBasedOnRowIndex index ->
                    let
                        getTopLeft { cellHeight, visibleCells } =
                            ( Nothing
                            , Just <| (index - visibleCells.frozenRows) * cellHeight
                            )
                    in
                    scrollTable config getTopLeft model

                ScrollBasedOnColumnIndex index ->
                    let
                        getTopLeft { cellWidth, visibleCells } =
                            ( Just <| (index - visibleCells.frozenCols) * cellWidth
                            , Nothing
                            )
                    in
                    scrollTable config getTopLeft model

                ScrollPageUp ->
                    let
                        getTopLeft { cellHeight, visibleCells } =
                            let
                                movedVisibleCells =
                                    PageScroll.up visibleCells
                            in
                            ( Nothing
                            , Just <| movedVisibleCells.topLeftRow * cellHeight
                            )
                    in
                    scrollTable config getTopLeft model

                ScrollPageDown ->
                    let
                        getTopLeft { cellHeight, visibleCells, rowCount } =
                            let
                                movedVisibleCells =
                                    PageScroll.down visibleCells rowCount
                            in
                            ( Nothing
                            , Just <| movedVisibleCells.topLeftRow * cellHeight
                            )
                    in
                    scrollTable config getTopLeft model

                ScrollPageLeft ->
                    let
                        getTopLeft { cellWidth, visibleCells } =
                            let
                                movedVisibleCells =
                                    PageScroll.left visibleCells
                            in
                            ( Just <| movedVisibleCells.topLeftCol * cellWidth
                            , Nothing
                            )
                    in
                    scrollTable config getTopLeft model

                ScrollPageRight ->
                    let
                        getTopLeft { cellWidth, visibleCells, colCount } =
                            let
                                movedVisibleCells =
                                    PageScroll.right visibleCells colCount
                            in
                            ( Just <| movedVisibleCells.topLeftCol * cellWidth
                            , Nothing
                            )
                    in
                    scrollTable config getTopLeft model

                HoverScrollbar ->
                    { model | isScrollbarHovered = True }
                        |> Cmd.pure

                StopHoveringScrollbar ->
                    { model | isScrollbarHovered = False }
                        |> Cmd.pure

                WindowResized ->
                    ( model
                    , getVisibleCells True model
                        |> delay 150
                        |> attemptTask
                        |> Cmd.map config.msg
                    )

                CloseSharedProjectWarning ->
                    { model | wasSharedProjectWarningDismissed = True }
                        |> Cmd.pure

                SharedProjectChanged autoUpdate freshProject ->
                    (if autoUpdate then
                        clearWorkspace config flags p2Store (RemoteData.toMaybe xbStore.userSettings) model
                            |> Cmd.addTrigger (config.setProjectToStore freshProject)

                     else
                        Cmd.pure model
                    )
                        |> Cmd.addTrigger
                            (config.createDetailPersistentNotification sharedProjectUpdatedNotificationId
                                (Notification.create
                                    (if autoUpdate then
                                        Nothing

                                     else
                                        Just { label = "Update now", onClick = SetProjectToStore freshProject }
                                    )
                                    (Html.text "This project has been modified.")
                                    P2Icons.refresh
                                )
                            )

                SetProjectToStore freshProject ->
                    clearWorkspace config flags p2Store (RemoteData.toMaybe xbStore.userSettings) model
                        |> Cmd.addTrigger (config.closeDetailNotification sharedProjectUpdatedNotificationId)
                        |> Cmd.addTrigger (config.setProjectToStore freshProject)

                CheckIfSharedProjectIsUpToDate { autoUpdate, currentProject } ->
                    ( model
                    , XBData.fetchTaskXBProjectFullyLoaded currentProject flags
                        |> Task.map
                            (\freshProject ->
                                if
                                    Time.posixToMillis freshProject.updatedAt
                                        > Time.posixToMillis currentProject.updatedAt
                                then
                                    SharedProjectChanged autoUpdate freshProject

                                else
                                    NoOp
                            )
                        |> Task.attempt (Result.withDefault NoOp >> config.msg)
                    )

                AnalyticsEvent event ->
                    Cmd.with (track flags route event) model

                RemoveSortingAndCloseModal ->
                    model
                        |> Cmd.withTrigger config.closeModal
                        |> Glue.update Glue.id
                            (update config route flags xbStore p2Store)
                            (Edit <| SortBy { axis = Rows, mode = NoSort })
                        |> Glue.update Glue.id
                            (update config route flags xbStore p2Store)
                            (Edit <| SortBy { axis = Columns, mode = NoSort })

                OpenLocationsDrawer ->
                    { model
                        | drawer =
                            Drawers.openLocations
                                { msg = DrawersMsg
                                , applyLocationsSelection =
                                    \loc segmenting ->
                                        ApplyLocationsSelection loc segmenting |> Edit
                                }
                                { selectedLocations = getActiveLocations model
                                , segmenting = Nothing
                                , getLocations = .locations
                                , footerWarning = Nothing
                                }
                    }
                        |> Cmd.with
                            (Process.sleep 200
                                |> Task.andThen
                                    (\_ ->
                                        let
                                            elementToFocus : String
                                            elementToFocus =
                                                "modal-locations-close-modal"
                                        in
                                        Dom.focus elementToFocus
                                    )
                                |> Task.attempt (always <| config.msg NoOp)
                            )

                OpenWavesDrawer ->
                    { model
                        | drawer =
                            Drawers.openWaves
                                { msg = DrawersMsg
                                , applyWavesSelection = ApplyWavesSelection >> Edit
                                }
                                { selectedWaves = getActiveWaves model
                                , getWaves = .waves
                                , footerWarning = Nothing
                                }
                    }
                        |> Cmd.with
                            (Process.sleep 300
                                |> Task.andThen
                                    (\_ ->
                                        let
                                            elementToFocus : String
                                            elementToFocus =
                                                "modal-waves-close-button"
                                        in
                                        Dom.focus elementToFocus
                                    )
                                |> Task.attempt (always <| config.msg NoOp)
                            )

                TabsPanelResized ->
                    ( model
                    , Cmd.batch
                        [ getBasesPanelElement config
                        , getBasesPanelViewport config
                        ]
                    )

                GotBasesPanelViewport viewport ->
                    ( { model | basesPanelViewport = Just viewport }, Cmd.none )

                GotBasesPanelElement element ->
                    ( { model | basesPanelElement = Just element }, Cmd.none )

                ScrollBasesPanelLeft ->
                    let
                        jumpLeft : String -> Cmd msg
                        jumpLeft id =
                            Dom.getViewportOf id
                                |> Task.andThen (\info -> Dom.setViewportOf id (info.viewport.x - 40) 0)
                                |> Task.attempt (\_ -> config.msg NoOp)
                    in
                    ( model
                    , Cmd.batch
                        [ jumpLeft Common.basesPanelScrollableId
                        , getBasesPanelViewport config
                        , getBasesPanelElement config
                        ]
                    )

                ScrollBasesPanelRight ->
                    let
                        jumpRight : String -> Cmd msg
                        jumpRight id =
                            Dom.getViewportOf id
                                |> Task.andThen (\info -> Dom.setViewportOf id (info.viewport.x + 40) 0)
                                |> Task.attempt (\_ -> config.msg NoOp)
                    in
                    ( model
                    , Cmd.batch
                        [ jumpRight Common.basesPanelScrollableId
                        , getBasesPanelViewport config
                        , getBasesPanelElement config
                        ]
                    )

                ScrollBasesPanelLeftAnAmount amount ->
                    let
                        jumpLeft : String -> Cmd msg
                        jumpLeft id =
                            Dom.getViewportOf id
                                |> Task.andThen (\info -> Dom.setViewportOf id (info.viewport.x - amount) 0)
                                |> Task.attempt (\_ -> config.msg NoOp)
                    in
                    ( model
                    , Cmd.batch
                        [ jumpLeft Common.basesPanelScrollableId
                        , getBasesPanelViewport config
                        , getBasesPanelElement config
                        ]
                    )

                ScrollBasesPanelRightAnAmount amount ->
                    let
                        jumpRight : String -> Cmd msg
                        jumpRight id =
                            Dom.getViewportOf id
                                |> Task.andThen (\info -> Dom.setViewportOf id (info.viewport.x + amount) 0)
                                |> Task.attempt (\_ -> config.msg NoOp)
                    in
                    ( model
                    , Cmd.batch
                        [ jumpRight Common.basesPanelScrollableId
                        , getBasesPanelViewport config
                        , getBasesPanelElement config
                        ]
                    )

                DrawersMsg dmsg ->
                    let
                        ( drawerModel, drawerMsg ) =
                            Drawers.update p2Store dmsg model.drawer
                                |> Glue.map config.msg
                    in
                    ( { model | drawer = drawerModel }, drawerMsg )

                OpenTableWarning { warning, row, column } ->
                    let
                        maybeXbQueryError =
                            case warning of
                                Common.GenericTableWarning _ ->
                                    Nothing

                                Common.CellXBQueryError err ->
                                    XB2.Share.Gwi.Http.getCustomError err

                        maybeNumWarnings : Maybe Int
                        maybeNumWarnings =
                            case warning of
                                Common.GenericTableWarning d ->
                                    Just d.count

                                Common.CellXBQueryError _ ->
                                    Nothing

                        namespaceCodesFromError xbQueryError =
                            case xbQueryError of
                                AudienceIntersect.InvalidQuery _ ->
                                    []

                                AudienceIntersect.EmptyAudienceExpression ->
                                    []

                                AudienceIntersect.UniverseZero ->
                                    []

                                AudienceIntersect.InvalidProjectsCombination codes ->
                                    codes

                        namespaceCodes : List Namespace.Code
                        namespaceCodes =
                            Maybe.unwrap [] namespaceCodesFromError maybeXbQueryError

                        withFetchCmds : model -> ( model, Cmd msg )
                        withFetchCmds =
                            if List.isEmpty namespaceCodes then
                                Cmd.pure

                            else
                                config.fetchManyP2
                                    (List.map XB2.Share.Store.Platform2.FetchLineage namespaceCodes)
                                    |> Cmd.withTrigger
                    in
                    { model | tableWarning = Just warning }
                        |> withFetchCmds
                        |> Cmd.add
                            (track flags route <|
                                getAnalyticsEvent
                                    WarningClicked
                                    { row = row
                                    , column = column
                                    , numOfWarnings = Maybe.withDefault 0 maybeNumWarnings
                                    }
                                    p2Store
                                    model
                            )

                ReorderBasesPanelDndMsg dndMsg ->
                    let
                        activeBaseIndex : Int
                        activeBaseIndex =
                            getCurrentBaseAudienceIndex model

                        preReorder : Maybe Dnd.Info
                        preReorder =
                            reorderBasesPanelDndSystem.info model.basesPanelDndModel

                        oldBasesOrder : List ACrosstab.CrosstabBaseAudience
                        oldBasesOrder =
                            NonemptyList.toList
                                (getCrosstabBaseAudiences model)

                        ( newDndModel, newBasesOrder ) =
                            reorderBasesPanelDndSystem.update dndMsg
                                model.basesPanelDndModel
                                oldBasesOrder

                        postReorder : Maybe Dnd.Info
                        postReorder =
                            reorderBasesPanelDndSystem.info newDndModel

                        addGoToBaseCmdIfDroppingBase :
                            ( model, Cmd msg )
                            -> ( model, Cmd msg )
                        addGoToBaseCmdIfDroppingBase =
                            case ( preReorder, postReorder ) of
                                ( Just infoAfterDrop, Nothing ) ->
                                    Cmd.addTrigger
                                        (GoToBaseAtIndex infoAfterDrop.dropIndex
                                            |> config.msg
                                        )

                                _ ->
                                    Cmd.add Cmd.none

                        addCloseDropdownCmd : ( model, Cmd msg ) -> ( model, Cmd msg )
                        addCloseDropdownCmd =
                            case ( preReorder, postReorder ) of
                                ( Nothing, Just _ ) ->
                                    Cmd.addTrigger
                                        (config.msg CloseDropdown)

                                _ ->
                                    Cmd.add Cmd.none

                        newActiveBaseIndex : Int
                        newActiveBaseIndex =
                            case ( preReorder, postReorder ) of
                                ( Just infoBeforeDrag, Just infoAfterDrag ) ->
                                    if activeBaseIndex == infoBeforeDrag.dragIndex then
                                        infoAfterDrag.dropIndex

                                    else if activeBaseIndex == infoBeforeDrag.dropIndex then
                                        infoBeforeDrag.dragIndex

                                    else
                                        activeBaseIndex

                                _ ->
                                    activeBaseIndex

                        {- If we're dropping the base and the order changed we fire the
                           event
                        -}
                        addAnalyticsCmdIfDroppingBase :
                            ( model, Cmd msg )
                            -> ( model, Cmd msg )
                        addAnalyticsCmdIfDroppingBase =
                            case ( preReorder, postReorder ) of
                                ( Just infoBeforeDrop, Nothing ) ->
                                    Cmd.addIf
                                        (infoBeforeDrop.dragElementId
                                            /= infoBeforeDrop.dropElementId
                                        )
                                        (track flags route <|
                                            getAnalyticsEvent
                                                BaseOrderChanged
                                                { changedHow =
                                                    Analytics.DragAndDrop
                                                }
                                                p2Store
                                                model
                                        )

                                _ ->
                                    Cmd.add Cmd.none

                        addScrollResizeObserverCmdIfDraggingBase :
                            ( model, Cmd msg )
                            -> ( model, Cmd msg )
                        addScrollResizeObserverCmdIfDraggingBase =
                            let
                                elementDraggedPassesRightThreshold :
                                    Dnd.Info
                                    -> Dom.Element
                                    -> Bool
                                elementDraggedPassesRightThreshold elementDraggedInfo scrollerElement =
                                    elementDraggedInfo.currentPosition.x
                                        >= (scrollerElement.element.x
                                                + (scrollerElement.element.width - 200)
                                           )

                                elementDraggedPassesLeftThreshold :
                                    Dnd.Info
                                    -> Dom.Element
                                    -> Bool
                                elementDraggedPassesLeftThreshold elementDraggedInfo scrollerElement =
                                    elementDraggedInfo.currentPosition.x
                                        <= (scrollerElement.element.x + 200)
                            in
                            case ( preReorder, postReorder, model.basesPanelElement ) of
                                ( Just _, Just infoAfterDrag, Just element ) ->
                                    if elementDraggedPassesRightThreshold infoAfterDrag element then
                                        Cmd.add
                                            (Task.perform
                                                (\_ ->
                                                    config.msg
                                                        (ScrollBasesPanelRightAnAmount 10)
                                                )
                                                (Process.sleep 200)
                                            )

                                    else if elementDraggedPassesLeftThreshold infoAfterDrag element then
                                        Cmd.add
                                            (Task.perform
                                                (\_ ->
                                                    config.msg
                                                        (ScrollBasesPanelLeftAnAmount 10)
                                                )
                                                (Process.sleep 200)
                                            )

                                    else
                                        Cmd.add Cmd.none

                                _ ->
                                    Cmd.add Cmd.none
                    in
                    (case NonemptyList.fromList newBasesOrder of
                        Just baseAudiences_ ->
                            if oldBasesOrder == newBasesOrder then
                                Cmd.pure
                                    { model
                                        | basesPanelDndModel = newDndModel
                                    }

                            else
                                -- Move here to previous active base when dragging. Care if active base is being replaced, swapped
                                { model
                                    | basesPanelDndModel = newDndModel
                                }
                                    |> Cmd.pure
                                    |> Cmd.addTrigger
                                        (config.setNewBasesOrder
                                            { triggeredFrom = Analytics.DragAndDrop
                                            , shouldFireAnalytics = False
                                            }
                                            (NonemptyList.toList baseAudiences_)
                                            newActiveBaseIndex
                                        )

                        Nothing ->
                            Cmd.pure model
                    )
                        |> Cmd.add
                            (reorderBasesPanelDndSystem.commands newDndModel
                                |> Cmd.map config.msg
                            )
                        |> addGoToBaseCmdIfDroppingBase
                        |> addCloseDropdownCmd
                        |> addScrollResizeObserverCmdIfDraggingBase
                        |> addAnalyticsCmdIfDroppingBase

                CloseTableWarning ->
                    { model | tableWarning = Nothing }
                        |> Cmd.pure

                TableHeaderResizeStart direction position ->
                    let
                        tableHeaderDimensions =
                            model.tableHeaderDimensions

                        currentSize =
                            model
                                |> currentMetadata
                                |> .headerSize
                    in
                    Cmd.pure
                        { model
                            | tableHeaderDimensions =
                                { tableHeaderDimensions
                                    | resizing =
                                        Just
                                            { direction = direction
                                            , originalWidth = currentSize.rowWidth
                                            , originalHeight = currentSize.columnHeight
                                            , startPosition = Just position
                                            }
                                }
                            , crosstabData =
                                model.crosstabData
                                    |> XB2.Share.UndoRedo.commit
                                        UndoEvent.ResizeTableHeader
                                        (updateAudienceCrosstab identity)
                        }

                ShareProjectByLink xbProject ->
                    model
                        |> Cmd.withTrigger (config.shareAndCopyLink xbProject)

                ToggleExactRespondentNumber ->
                    let
                        newModel =
                            { model
                                | shouldShowExactRespondentNumber =
                                    not model.shouldShowExactRespondentNumber
                            }
                    in
                    newModel
                        |> Cmd.pure
                        |> Cmd.add
                            (track flags route <|
                                getAnalyticsEvent
                                    RespondentNumberChanged
                                    { respondentNumberType =
                                        if newModel.shouldShowExactRespondentNumber then
                                            Analytics.Exact

                                        else
                                            Analytics.Rounded
                                    }
                                    p2Store
                                    model
                            )

                ToggleExactUniverseNumber ->
                    let
                        newModel =
                            { model
                                | shouldShowExactUniverseNumber =
                                    not model.shouldShowExactUniverseNumber
                            }
                    in
                    newModel
                        |> Cmd.pure
                        |> Cmd.add
                            (track flags route <|
                                getAnalyticsEvent
                                    UniverseNumberChanged
                                    { respondentNumberType =
                                        if newModel.shouldShowExactUniverseNumber then
                                            Analytics.Exact

                                        else
                                            Analytics.Rounded
                                    }
                                    p2Store
                                    model
                            )

                OpenReorderBasesModal ->
                    let
                        elementToFocus : String
                        elementToFocus =
                            "modal-reorder-bases-reset-button"
                    in
                    model
                        |> Cmd.withTrigger
                            (config.openModal
                                (Modal.ReorderBases <|
                                    Modal.reorderBasesModalInitialState <|
                                        NonemptyList.toList
                                            (getCrosstabBaseAudiences model)
                                )
                            )
                        |> Cmd.add
                            (Task.attempt
                                (always <| config.msg NoOp)
                                (Dom.focus elementToFocus)
                            )

                TableHeaderResizeStop ->
                    let
                        tableHeaderDimensions =
                            model.tableHeaderDimensions
                    in
                    tableHeaderDimensions.resizing
                        |> Maybe.map
                            (\{ direction, originalWidth, originalHeight } ->
                                let
                                    currentSize =
                                        model
                                            |> currentMetadata
                                            |> .headerSize

                                    crosstab =
                                        currentCrosstab model

                                    items : List ACrosstab.Key
                                    items =
                                        case direction of
                                            Row ->
                                                ACrosstab.getRows crosstab

                                            Column ->
                                                ACrosstab.getColumns crosstab

                                    captionLengths : List Int
                                    captionLengths =
                                        items
                                            |> List.map
                                                (\{ item } ->
                                                    let
                                                        caption =
                                                            AudienceItem.getCaption item
                                                    in
                                                    String.length (Caption.getName caption)
                                                        + Maybe.unwrap 0 String.length (Caption.getSubtitle caption)
                                                )
                                in
                                ( { model
                                    | tableHeaderDimensions =
                                        { tableHeaderDimensions | resizing = Nothing }
                                  }
                                , track flags route <|
                                    getAnalyticsEvent
                                        HeaderResized
                                        { expanded =
                                            case direction of
                                                Row ->
                                                    currentSize.rowWidth > originalWidth

                                                Column ->
                                                    currentSize.columnHeight > originalHeight
                                        , wasResizingColumns = direction == Column
                                        , maxCharCount = Maybe.withDefault 0 <| List.maximum captionLengths
                                        , avgCharCount = List.sum captionLengths // List.length captionLengths
                                        }
                                        p2Store
                                        model
                                )
                            )
                        |> Maybe.withDefault ( model, Cmd.none )
    in
    update_ |> deriveHeatmapScale model


deriveHeatmapScale : Model -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
deriveHeatmapScale oldModel ( model, cmd ) =
    if fieldsNeededForHeatmapScaleChanged { old = oldModel, new = model } then
        ( { model
            | heatmapScale =
                Maybe.map
                    (Heatmap.initScale (currentCrosstabFromData (XB2.Share.UndoRedo.current model.crosstabData)))
                    model.heatmapMetric
          }
        , cmd
        )

    else
        ( model, cmd )


fieldsNeededForHeatmapScaleChanged : { old : Model, new : Model } -> Bool
fieldsNeededForHeatmapScaleChanged { old, new } =
    ACrosstab.notSame (currentCrosstab old) (currentCrosstab new) || old.heatmapMetric /= new.heatmapMetric


sharedProjectUpdatedNotificationId : String
sharedProjectUpdatedNotificationId =
    "shared-project-updated-notification-id"


setSortForAxis : Axis -> AxisSort -> XBProjectMetadata -> XBProjectMetadata
setSortForAxis axis newAxisSort metadata =
    updateSort
        (case axis of
            Rows ->
                \sort -> { sort | rows = newAxisSort }

            Columns ->
                \sort -> { sort | columns = newAxisSort }
        )
        metadata


updateSort : (Sort -> Sort) -> XBProjectMetadata -> XBProjectMetadata
updateSort fn metadata =
    { metadata | sort = fn metadata.sort }


scrollTable :
    Config msg
    ->
        ({ cellWidth : Int
         , cellHeight : Int
         , visibleCells : VisibleCells
         , colCount : Int
         , rowCount : Int
         }
         -> ( Maybe Int, Maybe Int )
        )
    -> Model
    -> ( Model, Cmd msg )
scrollTable config getTopLeft model =
    ( model
    , Task.map
        (\{ viewport } ->
            let
                { colCount, rowCount } =
                    ACrosstab.getDimensionsWithTotals (currentCrosstab model)

                visibleCells =
                    ACrosstab.getVisibleCells (currentCrosstab model)

                metadata =
                    currentMetadata model

                cellHeight =
                    getTotalRowHeight
                        (List.length metadata.activeMetrics)
                        metadata.metricsTransposition

                cellWidth =
                    getTotalColWidth
                        (List.length metadata.activeMetrics)
                        metadata.metricsTransposition
            in
            getTopLeft
                { cellWidth = cellWidth
                , cellHeight = cellHeight
                , visibleCells = visibleCells
                , colCount = colCount
                , rowCount = rowCount
                }
                |> Tuple.mapBoth
                    (Maybe.unwrap viewport.x toFloat)
                    (Maybe.unwrap viewport.y toFloat)
        )
        (Dom.getViewportOf Common.scrollTableId)
        |> Task.andThen (uncurry <| Dom.setViewportOf Common.scrollTableId)
        |> Task.attempt (always <| config.msg NoOp)
    )


keyToItemSelectedEventData : ACrosstab.Key -> Maybe ( IdSet QuestionAndDatapointCodeTag, IdSet NamespaceAndQuestionCodeTag, Caption )
keyToItemSelectedEventData key =
    case AudienceItem.getDefinition key.item of
        Expression expression ->
            Just
                ( XB2.Share.Data.Id.setFromList <| Expression.getQuestionAndDatapointCodes expression
                , XB2.Share.Data.Id.setFromList <| Expression.getQuestionCodes expression
                , AudienceItem.getCaption key.item
                )

        Average _ ->
            Nothing


keyToItemSelectedEvent : Direction -> Analytics.ItemSelected -> ACrosstab.Key -> Maybe Event
keyToItemSelectedEvent direction itemSelected key =
    keyToItemSelectedEventData key
        |> Maybe.map
            (\( datapointCodes, questionCodes, caption ) ->
                ItemSelectedInTable
                    { datapointCodes = Set.Any.toList datapointCodes
                    , questionCodes = Set.Any.toList questionCodes
                    , captions = [ caption ]
                    , direction = direction
                    , itemSelected = itemSelected
                    }
            )


keyToItemSelectedWithShiftEvent : Direction -> ACrosstab.Key -> Maybe Event
keyToItemSelectedWithShiftEvent direction key =
    keyToItemSelectedEventData key
        |> Maybe.map
            (\( datapointCodes, questionCodes, caption ) ->
                ItemSelectedInTableWithShift
                    { datapointCodes = Set.Any.toList datapointCodes
                    , questionCodes = Set.Any.toList questionCodes
                    , captions = [ caption ]
                    , direction = direction
                    }
            )


keysToItemsSelectedEvent : List ACrosstab.Key -> Event
keysToItemsSelectedEvent keys =
    AllItemsSelectedInTable { selectedItemsCount = List.length keys + 1 }


exportEvent :
    List Location
    -> List Wave
    -> XB2.Share.Store.Platform2.Store
    ->
        { model
            | crosstabData :
                UndoRedo
                    tag
                    { data
                        | cellLoaderModel : CrosstabCellLoader.Model MeasuredAfterQueueCmd
                        , projectMetadata : XBProjectMetadata
                    }
            , heatmapMetric : Maybe Metric
            , unsaved : Unsaved
        }
    -> Maybe XBData.XBProjectFullyLoaded
    -> Analytics.Event
exportEvent locations waves store model maybeProject =
    let
        crosstabData =
            XB2.Share.UndoRedo.current model.crosstabData

        audienceCrosstab =
            crosstabData.cellLoaderModel.audienceCrosstab

        { rowCount, colCount } =
            ACrosstab.getDimensionsWithTotals audienceCrosstab
    in
    Analytics.Export
        { audiences =
            ACrosstab.getRows audienceCrosstab
                ++ ACrosstab.getColumns audienceCrosstab
                |> List.map .item
        , locations = locations
        , waves = waves
        , metricsTransposition = crosstabData.projectMetadata.metricsTransposition
        , xbBases =
            audienceCrosstab
                |> ACrosstab.getBaseAudiences
                |> ListZipper.map Analytics.prepareBaseForTracking
                |> ListZipper.toList
        , rowCount = rowCount
        , colCount = colCount
        , heatmapMetric = model.heatmapMetric
        , store = store
        , maybeProject = maybeProject
        , isSaved = model.unsaved
        }


wavesAndLocations : XB2.Share.Store.Platform2.Store -> Model -> ( List Wave, List Location )
wavesAndLocations p2Store model =
    ( Store.getByIds p2Store.waves <| Set.Any.toList <| getActiveWaves model
    , Store.getByIds p2Store.locations <| Set.Any.toList <| getActiveLocations model
    )


subscribeUndoRedoKeyShortcuts : Sub Msg
subscribeUndoRedoKeyShortcuts =
    Browser.Events.onKeyDown
        (Decode.succeed
            (\char ctrl meta shift ->
                case ( ctrl, meta, shift ) of
                    ( True, False, False ) ->
                        if char == "z" then
                            Edit Undo

                        else if char == "y" then
                            Edit Redo

                        else
                            NoOp

                    ( False, True, False ) ->
                        if char == "z" then
                            Edit Undo

                        else
                            NoOp

                    ( False, True, True ) ->
                        if char == "z" then
                            Edit Redo

                        else
                            NoOp

                    _ ->
                        NoOp
            )
            |> Decode.andMap (Decode.field "key" Decode.string)
            |> Decode.andMap (Decode.field "ctrlKey" Decode.bool)
            |> Decode.andMap (Decode.field "metaKey" Decode.bool)
            |> Decode.andMap (Decode.field "shiftKey" Decode.bool)
        )


subscribeSearchShortcuts : Bool -> Sub Msg
subscribeSearchShortcuts inputSearchIsFocused =
    Browser.Events.onKeyDown
        (Decode.succeed
            (\key ctrl meta shift ->
                if inputSearchIsFocused then
                    if shift then
                        case key of
                            "Enter" ->
                                GoToPreviousSearchResult

                            _ ->
                                NoOp

                    else
                        case key of
                            "Escape" ->
                                BlurElementById Common.crosstabSearchId

                            "Enter" ->
                                GoToNextSearchResult

                            _ ->
                                NoOp

                else
                    case ( ctrl, meta, shift ) of
                        ( True, False, True ) ->
                            if key == "f" then
                                FocusElementById Common.crosstabSearchId

                            else
                                NoOp

                        ( False, True, True ) ->
                            if key == "f" then
                                FocusElementById Common.crosstabSearchId

                            else
                                NoOp

                        _ ->
                            NoOp
            )
            |> Decode.andMap (Decode.field "key" Decode.string)
            |> Decode.andMap (Decode.field "ctrlKey" Decode.bool)
            |> Decode.andMap (Decode.field "metaKey" Decode.bool)
            |> Decode.andMap (Decode.field "shiftKey" Decode.bool)
        )


subscriptions : Config msg -> { isModalOpen : Bool } -> Maybe XBProject -> XB2.Router.Route -> Model -> Sub msg
subscriptions { msg } { isModalOpen } maybeProject route model =
    let
        scrollConfig =
            { onScrollEnd = Dict.empty
            , onScrollStart = Dict.empty
            , noOp = NoOp
            }
                |> (case ( route, model.autoScroll ) of
                        ( XB2.Router.Project _, Nothing ) ->
                            \rec ->
                                { rec
                                    | onScrollEnd =
                                        Dict.insert
                                            Common.scrollTableId
                                            (\position ->
                                                TableScroll
                                                    { shouldReloadTable = True
                                                    , position = position
                                                    }
                                            )
                                            rec.onScrollEnd
                                    , onScrollStart = Dict.insert Common.basesPanelScrollableId CloseDropdown rec.onScrollStart
                                }

                        _ ->
                            identity
                   )

        perView =
            Sub.batch
                [ Maybe.unwrap Sub.none
                    (always <| Browser.Events.onClick (Decode.succeed CloseDropdown))
                    model.activeDropdown
                , Maybe.unwrap Sub.none
                    (Browser.Events.onAnimationFrame << always << AutoScroll)
                    model.autoScroll
                , if isModalOpen then
                    Sub.none

                  else
                    subscribeUndoRedoKeyShortcuts
                , if isModalOpen then
                    Sub.none

                  else
                    subscribeSearchShortcuts model.crosstabSearchModel.inputIsFocused
                , Browser.Events.onResize (\_ _ -> GetBasesPanelWidth)
                ]

        sharedProjectChangesChecking =
            case maybeProject of
                Just project ->
                    if XBData.isSharedWithMe project.shared then
                        CheckIfSharedProjectIsUpToDate { autoUpdate = False, currentProject = project }
                            |> always
                            |> Time.every 30000

                    else
                        Sub.none

                Nothing ->
                    Sub.none

        tableResizing =
            let
                getSubs decoder =
                    Sub.batch
                        [ Browser.Events.onMouseMove decoder
                        , Browser.Events.onMouseUp (Decode.succeed TableHeaderResizeStop)
                        ]
            in
            case model.tableHeaderDimensions.resizing of
                Nothing ->
                    Sub.none

                Just { direction } ->
                    case direction of
                        Row ->
                            let
                                moseMoveRowDecoder =
                                    Decode.field "pageX" Decode.float
                                        |> Decode.map (round >> TableHeaderResizing Row >> Edit)
                            in
                            getSubs moseMoveRowDecoder

                        Column ->
                            let
                                moseMoveColDecoder =
                                    Decode.field "pageY" Decode.float
                                        |> Decode.map (round >> TableHeaderResizing Column >> Edit)
                            in
                            getSubs moseMoveColDecoder

        closeDropdownOnEsc =
            case model.activeDropdown of
                Just _ ->
                    Browser.Events.onKeyUp (Decode.escDecoder CloseDropdown)

                Nothing ->
                    Sub.none

        basesPanelFocusSubscription : Sub Msg
        basesPanelFocusSubscription =
            let
                basesOrder =
                    NonemptyList.toList (getCrosstabBaseAudiences model)

                {- This function is to avoid surpassing 0 to length of
                   baseAudiences range
                -}
                newFocusedIndex : Int -> Maybe Int
                newFocusedIndex newIndex_ =
                    if newIndex_ < 0 then
                        Just 0

                    else if newIndex_ >= List.length basesOrder then
                        Just <| List.length basesOrder - 1

                    else
                        Just newIndex_
            in
            case
                ( model.keyboardMovementBasesPanelModel.baseFocused
                , model.keyboardMovementBasesPanelModel.baseSelectedToMove
                )
            of
                ( Just index, Nothing ) ->
                    Browser.Events.onKeyDown
                        (Decode.field "key" Decode.string
                            |> Decode.andThen
                                (\key ->
                                    case key of
                                        "ArrowLeft" ->
                                            Decode.succeed <|
                                                SetBaseIndexFocused <|
                                                    newFocusedIndex (index - 1)

                                        "ArrowRight" ->
                                            Decode.succeed <|
                                                SetBaseIndexFocused <|
                                                    newFocusedIndex (index + 1)

                                        -- Space looks like this
                                        " " ->
                                            Decode.succeed <|
                                                SetBaseIndexSelectedToMoveWithKeyboard <|
                                                    Just index

                                        "Enter" ->
                                            Decode.succeed <|
                                                SetBaseIndexSelectedToMoveWithKeyboard <|
                                                    Just index

                                        _ ->
                                            Decode.fail "We do not care about this key."
                                )
                        )

                _ ->
                    Sub.none

        basesPanelMoveBaseSubscription : Sub Msg
        basesPanelMoveBaseSubscription =
            case model.keyboardMovementBasesPanelModel.baseSelectedToMove of
                Just index ->
                    Browser.Events.onKeyDown
                        (Decode.field "key" Decode.string
                            |> Decode.andThen
                                (\key ->
                                    case key of
                                        "ArrowLeft" ->
                                            Decode.succeed <|
                                                SwapBasesOrder
                                                    index
                                                    (index - 1)

                                        "ArrowRight" ->
                                            Decode.succeed <|
                                                SwapBasesOrder
                                                    index
                                                    (index + 1)

                                        -- Space looks like this
                                        " " ->
                                            Decode.succeed <|
                                                SetBaseIndexSelectedToMoveWithKeyboard
                                                    Nothing

                                        "Enter" ->
                                            Decode.succeed <|
                                                SetBaseIndexSelectedToMoveWithKeyboard
                                                    Nothing

                                        _ ->
                                            Decode.fail "We do not care about this key."
                                )
                        )

                Nothing ->
                    Sub.none
    in
    Sub.map msg <|
        Sub.batch
            [ perView
            , case route of
                XB2.Router.Project Nothing ->
                    Time.every 30000 <| SetCurrentTime model.timezone

                _ ->
                    Sub.none
            , dndSystem.subscriptions model.tableCellDndModel
            , reorderBasesPanelDndSystem.subscriptions model.basesPanelDndModel
            , basesPanelFocusSubscription
            , basesPanelMoveBaseSubscription
            , Dom.batchRegister scrollConfig
            , Browser.Events.onResize (\_ _ -> WindowResized)
            , sharedProjectChangesChecking
            , tableResizing
            , closeDropdownOnEsc
            ]



-- View


locationsAndWavesLoading : XB2.Share.Store.Platform2.Store -> Bool
locationsAndWavesLoading p2Store =
    RemoteData.isLoading p2Store.locations
        || RemoteData.isLoading p2Store.waves


locationsAndWavesErrors : XB2.Share.Store.Platform2.Store -> List Http.Error
locationsAndWavesErrors p2Store =
    [ RemoteData.map (always Nothing) p2Store.locations
    , RemoteData.map (always Nothing) p2Store.waves
    ]
        |> List.filterMap
            (\item ->
                case item of
                    RemoteData.Failure e ->
                        Just e

                    _ ->
                        Nothing
            )


reorderBasesPanelDndConfig : Dnd.Config ACrosstab.CrosstabBaseAudience
reorderBasesPanelDndConfig =
    { beforeUpdate = \_ _ list -> list
    , movement = Dnd.Horizontal
    , listen = Dnd.OnDrag
    , operation = Dnd.Rotate
    }


reorderBasesPanelDndSystem : Dnd.System ACrosstab.CrosstabBaseAudience Msg
reorderBasesPanelDndSystem =
    Dnd.create reorderBasesPanelDndConfig ReorderBasesPanelDndMsg


tableConfig : Model -> Maybe XBProject -> XBStore.Store -> Table.Config Model Msg
tableConfig xbModel maybeProject xbStore =
    let
        saveEditedMsg : XBProject -> String -> Msg
        saveEditedMsg project _ =
            SaveEdited project

        saveMsg : String -> Msg
        saveMsg =
            case maybeProject of
                Just project ->
                    case project.shared of
                        MyPrivateCrosstab ->
                            saveEditedMsg project

                        SharedBy _ _ ->
                            \_ -> SaveAsCopy project

                        MySharedCrosstab _ ->
                            saveEditedMsg project

                        SharedByLink ->
                            \_ -> SaveAsCopy project

                Nothing ->
                    OpenSaveAsNew

        name model =
            model.currentTime
                |> NewName.timeBasedCrosstabName
                    (XBStore.projectNameExists xbStore)
                    model.timezone
                |> Just
                |> Maybe.or (Maybe.map .name maybeProject)
                |> Maybe.withDefault "New Crosstab"

        isProjectLoadedCorrectly =
            case maybeProject of
                Nothing ->
                    True

                Just project ->
                    Maybe.isJust <| XBData.getFullyLoadedProject project
    in
    { openLocationsSelection = OpenLocationsDrawer
    , openMetricsSelection = OpenMetricsSelection
    , openWavesSelection = OpenWavesDrawer
    , openHeatmapSelection = OpenHeatmapSelection
    , openMinimumSampleSizeModal = OpenMinimumSampleSizeModal
    , removeSelectedAudiencesConfirm = OpenRemoveFromTableConfirmModal
    , removeAudience = Edit << RemoveAudience
    , duplicateAudience = Edit << DuplicateAudience
    , viewGroupExpression = ViewGroupExpression
    , openAffixTableForSingle = OpenAffixTableModalForSingle
    , openEditTableForSingle = OpenEditTableModalForSingle
    , openSaveAsAudienceModal = OpenSaveAsAudienceModal
    , openSelectedSaveAsAudienceModal = OpenSelectedSaveAsAudienceModal
    , openAttributeBrowser = OpenAttributeBrowser { affixedFrom = Analytics.BulkBar }
    , openAttributeBrowserViaAddAttributeButton = OpenAttributeBrowser { affixedFrom = Analytics.AddAttributeButton }
    , addSelectionAsNewBase = AddSelectionAsNewBase
    , mergeSelectedRowOrColum = MergeSelectedRowOrColum
    , addAsNewBase = AddAsNewBase
    , anySelected = ACrosstab.anySelected << currentCrosstab
    , replaceDefaultBase = OpenAttributeBrowserForReplacingDefaultBase
    , openNewBaseView = OpenAttributeBrowserForAddBase
    , switchCrosstab = Edit SwitchCrosstab
    , toggleViewOptionsDropdown = ToggleViewOptionsDropdown
    , toggleBulkFreezeDropdown = ToggleBulkFreezeDropdown
    , getActiveDropdown = .activeDropdown
    , toggleSortByNameDropdown = ToggleSortByNameDropdown
    , toggleAllBasesDropdown = ToggleAllBasesDropdown
    , toggleHeaderCollapsed = ToggleHeaderCollapsed
    , transposeMetrics = Edit << TransposeMetrics
    , selectedExpression = getAllSelected
    , selectedCount = \model -> List.length <| ACrosstab.getSelectedColumns (currentCrosstab model) ++ ACrosstab.getSelectedRows (currentCrosstab model)
    , isEveryColumnSelected = \model -> ACrosstab.allColumnsSelected (currentCrosstab model)
    , isEveryRowSelected = \model -> ACrosstab.allRowsSelected (currentCrosstab model)
    , getAllSelected = getAllSelected
    , selectableColCountWithoutTotals = ACrosstab.selectableColCountWithoutTotals << currentCrosstab
    , selectableRowCountWithoutTotals = ACrosstab.selectableRowCountWithoutTotals << currentCrosstab
    , getMetricsTransposition = .crosstabData >> XB2.Share.UndoRedo.current >> .projectMetadata >> .metricsTransposition
    , getCurrentBaseAudienceIndex = getCurrentBaseAudienceIndex
    , getBaseAudiences = getCrosstabBaseAudiences
    , goToBaseAtIndex = GoToBaseAtIndex
    , removeBase = Edit << RemoveBase
    , toggleBase = ToggleBaseAudience
    , crosstabBases =
        { anySelected = ACrosstab.anyBaseSelected << currentCrosstab
        , selectedCount = ACrosstab.selectedBasesCount << currentCrosstab
        , allSelected = ACrosstab.allBasesSelected << currentCrosstab
        , selectAll = SelectAllBasesInPanel
        , clearSelection = ClearBasesPanelSelection
        , rename = RenameBaseAudience
        , deleteBases =
            \bases ->
                if NonemptyList.length bases > 1 then
                    OpenRemoveBasesConfirmModal bases

                else
                    Edit <| RemoveBaseAudiences False bases
        , getSelected = ACrosstab.getSelectedBases << currentCrosstab
        , resetBase = Edit ResetDefaultBaseAudience
        , disabledBaseSelection = ACrosstab.anySelected << currentCrosstab
        , saveInMyAudiences = OpenSaveBaseInMyAudiencesModal
        , openAffixModalForSelected = OpenAffixBaseAudienceModalForSelected
        , openAffixModalForSingle = OpenAffixBaseAudienceModalForSingle
        , openEditModalForSingle = OpenEditBaseAudienceModalForSingle
        , openReorderBasesModal = OpenReorderBasesModal
        , reorderBasesPanelDndSystem = reorderBasesPanelDndSystem
        , reorderBasesPanelDndModel = xbModel.basesPanelDndModel
        , activeBaseIndex = getCurrentBaseAudienceIndex xbModel
        , setBaseIndexFocused = SetBaseIndexFocused
        , baseSelectedToMoveWithKeyboard =
            xbModel.keyboardMovementBasesPanelModel.baseSelectedToMove
        }
    , getActiveLocations = \store -> Store.getByIds store.locations << Set.Any.toList << getActiveLocations
    , getAllLocationsSet =
        \store _ ->
            RemoteData.unwrap
                XB2.Share.Data.Id.emptySet
                (\dict -> dict |> Dict.Any.values |> List.map .code |> XB2.Share.Data.Id.setFromList)
                store.locations
    , getActiveWaves = \store -> Store.getByIds store.waves << Set.Any.toList << getActiveWaves
    , downloadDebugDump = DownloadDebugDump
    , withDropdownMenu = DropdownMenu.withPrecisePosition ToggleFixedPageDropdown
    , getCrosstab = currentCrosstab
    , scrollBasesPanelRight = ScrollBasesPanelRight
    , scrollBasesPanelLeft = ScrollBasesPanelLeft
    , tabsPanelResized = TabsPanelResized
    , basesPanelViewport = .basesPanelViewport
    , getSelectionMap = .crosstabData >> XB2.Share.UndoRedo.current >> .selectionMap
    , isHeaderCollapsed = .isHeaderCollapsed

    -- control panel
    , timeTravel =
        { undoMsg = Edit Undo
        , redoMsg = Edit Redo
        , undoDisabled = not << XB2.Share.UndoRedo.hasPast << .crosstabData
        , redoDisabled = not << XB2.Share.UndoRedo.hasFuture << .crosstabData
        }
    , export =
        { canProcess = not << ACrosstab.isEmpty << currentCrosstab
        , isExporting = .isExporting
        , start = StartExport Nothing maybeProject
        , startForSelectedCells =
            \selectionMap ->
                StartExport (Just selectionMap) maybeProject
        }
    , sharing =
        { shareMsg =
            case maybeProject of
                Nothing ->
                    NoOp

                Just project ->
                    OpenShareProjectModal project
        , isMine = Maybe.unwrap False (.shared >> XBData.isMine) maybeProject
        , isSharedByLink =
            Maybe.unwrap False
                (.shared
                    >> (==) XBData.SharedByLink
                )
                maybeProject
        , shareAndCopyLinkMsg =
            case maybeProject of
                Nothing ->
                    NoOp

                Just project ->
                    ShareProjectByLink project
        }
    , saving =
        { save = saveMsg << name
        , isSharedWithMe =
            Maybe.unwrap False (XBData.isSharedWithMe << .shared) maybeProject
        , isSaveBtnEnabled =
            .unsaved
                >> isUnsavedOrEdited
                >> (||)
                    (Maybe.unwrap False
                        (XBData.isSharedWithMe
                            << .shared
                        )
                        maybeProject
                    )
                >> (&&) isProjectLoadedCorrectly
        , saveAsNew = OpenSaveAsNew << name
        }

    -- grid table model stuff
    , metrics = .crosstabData >> XB2.Share.UndoRedo.current >> .projectMetadata >> .activeMetrics
    , heatmapMetric = .heatmapMetric
    , getDropdownMenu = getDropdownMenu
    , isFixedPageDropdownOpen = DropdownMenu.isVisible
    , isScrolling = isScrolling << .scrollingState
    , isScrollingX = isScrollingX << .scrollingState
    , isScrollingY = isScrollingY << .scrollingState
    , isScrollbarHovered = .isScrollbarHovered
    , dnd = dndSystem
    , dndModel = .tableCellDndModel
    , getTableCellsTopOffset = .tableCellsTopOffset
    , heatmapScale = .heatmapScale
    , getAverageTimeFormat = getAverageTimeFormat
    , firstColumnWidth = currentMetadata >> .headerSize >> .rowWidth
    , hasResizedRowHeader = currentMetadata >> .headerSize >> .rowWidth >> (/=) XBData.defaultProjectHeaderSize.rowWidth
    , headerColumnHeight = currentMetadata >> .headerSize >> .columnHeight
    , hasResizedColHeader = currentMetadata >> .headerSize >> .columnHeight >> (/=) XBData.defaultProjectHeaderSize.columnHeight
    , isHeaderResizing = \direction m -> Maybe.unwrap False (.direction >> (==) direction) m.tableHeaderDimensions.resizing
    , shouldShowExactRespondentNumber = .shouldShowExactRespondentNumber
    , shouldShowExactUniverseNumber = .shouldShowExactUniverseNumber
    , toggleExactRespondentNumberMsg = ToggleExactRespondentNumber
    , toggleExactUniverseNumberMsg = ToggleExactUniverseNumber

    -- sorting
    , getCurrentSort = getCurrentSort
    , resetSortForAxis = Edit << ResetSortForAxis
    , resetSortByName = Edit ResetSortByName
    , sortByOtherAxisMetric = ShowSortingDialog
    , sortByTotalsMetric = ShowSortingDialog
    , sortByOtherAxisAverage = ShowSortingDialog
    , sortByName =
        \axis direction ->
            Edit <| SortBy { mode = ByName direction, axis = axis }

    -- Cell freezing
    , getFrozenRowsColumns = currentMetadata >> .frozenRowsAndColumns
    , setFrozenRowsColumns = Edit << SetFrozenRowsColumns

    -- Sample size
    , getMinimumSampleSize = currentMetadata >> .minimumSampleSize
    , setMinimumSampleSize = Edit << SetMinimumSampleSize

    -- Search
    , searchTermChanged = ChangeSearchTerm
    , getCrosstabSearchProps =
        \model ->
            { term = model.crosstabSearchModel.term
            , sanitizedTerm = model.crosstabSearchModel.sanitizedTerm
            , searchTopLeftScrollJumps = model.crosstabSearchModel.searchTopLeftScrollJumps
            , inputIsFocused = model.crosstabSearchModel.inputIsFocused
            }
    , setInputFocus = SetCrosstabSearchInputFocus
    , goToPreviousSearchResult = GoToPreviousSearchResult
    , goToNextSearchResult = GoToNextSearchResult

    -- messages
    , noOp = NoOp
    , selectRowOrColumnMouseDown = SelectRowOrColumnMouseDown
    , selectColumn = \shiftState itemSelected -> SelectAction << SelectColumn shiftState itemSelected
    , selectRow = \shiftState itemSelected -> SelectAction << SelectRow shiftState itemSelected
    , deselectColumn = SelectAction << DeselectColumn
    , deselectRow = SelectAction << DeselectRow
    , clearSelection = SelectAction ClearSelection
    , deselectAllColumns = SelectAction DeselectAllColumns
    , deselectAllRows = SelectAction DeselectAllRows
    , selectAllColumns = SelectAction SelectAllColumns
    , selectAllRows = SelectAction SelectAllRows
    , openRenameAverageModal = OpenRenameAverageModal
    , removeAverageRowOrCol = \direction key -> Edit (RemoveAverageRowOrCol direction key)
    , tableScroll =
        \position ->
            TableScroll
                { shouldReloadTable = False
                , position = position
                }
    , scrollUp = ScrollPageUp
    , scrollDown = ScrollPageDown
    , scrollLeft = ScrollPageLeft
    , scrollRight = ScrollPageRight
    , hoverScrollbar = HoverScrollbar
    , stopHoveringScrollbar = StopHoveringScrollbar
    , uselessCheckboxClicked = UselessCheckboxClicked
    , switchAverageTimeFormat = Edit SwitchAverageTimeFormat
    , updateUserSettings = UpdateUserSettings
    , openTableWarning = OpenTableWarning
    , tableHeaderResizeStart = TableHeaderResizeStart
    , tableHeaderResizeStop = TableHeaderResizeStop
    }


getCurrentSort : Model -> Sort
getCurrentSort model =
    currentMetadata model
        |> .sort


headerModel : Maybe XBProject -> Model -> Header.Model
headerModel maybeProject model =
    let
        isProjectLoadedCorrectly =
            case maybeProject of
                Nothing ->
                    True

                Just project ->
                    Maybe.isJust <| XBData.getFullyLoadedProject project
    in
    { currentTime = Just model.currentTime
    , canProcessExport = not <| ACrosstab.isEmpty <| currentCrosstab model
    , isDropdownOpen = False
    , isExporting = model.isExporting
    , isUnsaved =
        isUnsavedOrEdited model.unsaved
            && isProjectLoadedCorrectly
    , zone = model.timezone
    , wasSharedProjectWarningDismissed = model.wasSharedProjectWarningDismissed
    , undoDisabled = not <| XB2.Share.UndoRedo.hasPast model.crosstabData
    , redoDisabled = not <| XB2.Share.UndoRedo.hasFuture model.crosstabData
    , crosstabData = model |> currentCrosstab
    , isHeaderCollapsed = model.isHeaderCollapsed
    }


errorView : String -> Html msg
errorView error =
    Html.div
        [ WeakCss.nest "error" moduleClass ]
        [ Html.div
            [ WeakCss.nest "error-title" moduleClass ]
            [ Html.text "Error fetching data"
            ]
        , Html.div
            [ WeakCss.nest "error-message" moduleClass ]
            [ Markdown.toHtml [] error ]
        ]


getDropdownMenu : Model -> DropdownMenu Msg
getDropdownMenu model =
    case model.activeDropdown of
        Just (FixedPageDropdown dropDownMenu) ->
            dropDownMenu

        _ ->
            DropdownMenu.init


dropDownMenuView : Config msg -> Model -> Html msg
dropDownMenuView config model =
    getDropdownMenu model
        |> DropdownMenu.view
        |> Html.map config.msg


showFullTableLoader : Model -> Bool
showFullTableLoader =
    currentCrosstabData
        >> .cellLoaderModel
        >> CrosstabCellLoader.showFullTableLoader


tableView :
    Config msg
    -> Flags
    -> Maybe XBProject
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> Maybe (Dropdown Msg)
    -> Model
    -> Html msg
tableView config flags maybeProject xbStore p2Store activeDropdown model =
    let
        fullProjectIsLoading =
            Maybe.unwrap False (RemoteData.isLoading << .data) maybeProject

        fullProjectError =
            Maybe.unwrap []
                (\mp ->
                    case mp.data of
                        RemoteData.Failure e ->
                            [ e ]

                        _ ->
                            []
                )
                maybeProject

        isCrosstabEmpty =
            model |> currentCrosstab |> ACrosstab.isEmpty

        mainAndHeaderView rest =
            Html.main_ [ WeakCss.nest "container" moduleClass ]
                (Header.view
                    config.headerConfig
                    flags
                    maybeProject
                    xbStore
                    { isCrosstabEmpty = isCrosstabEmpty }
                    (headerModel maybeProject model)
                    :: dropDownMenuView config model
                    :: rest
                )

        tableWarningView warning =
            let
                ( count, content, additionalNotice ) =
                    case warning of
                        Common.GenericTableWarning d ->
                            ( d.count, d.content, d.additionalNotice )

                        Common.CellXBQueryError err ->
                            ( 1
                            , XB2.Share.Gwi.Http.errorToString (AudienceIntersect.xbQueryErrorString p2Store) err
                                |> Markdown.toHtml []
                            , Nothing
                            )

                headerCopy =
                    String.fromInt count
                        ++ XB2.Share.Plural.fromInt count " warning"

                additionalWarningNoticeView notice =
                    Html.div [ WeakCss.nestMany [ "main-content", "cell-warning", "content", "additional-notice" ] moduleClass ]
                        [ notice
                        ]
            in
            Html.map config.msg <|
                Html.div
                    [ WeakCss.nestMany [ "main-content", "cell-warning" ] moduleClass ]
                    [ Html.div [ WeakCss.nestMany [ "main-content", "cell-warning", "heading" ] moduleClass ]
                        [ Html.h3
                            [ WeakCss.nestMany [ "main-content", "cell-warning", "heading", "title" ] moduleClass ]
                            [ Html.span [ WeakCss.nestMany [ "main-content", "cell-warning", "heading", "icon" ] moduleClass ]
                                [ XB2.Share.Icons.icon [] P2Icons.warning ]
                            , Html.text headerCopy
                            ]
                        , Html.button
                            [ WeakCss.nestMany [ "main-content", "cell-warning", "heading", "close" ] moduleClass
                            , Attrs.attribute "aria-label" "Close table warning"
                            , Events.onClick CloseTableWarning
                            ]
                            [ XB2.Share.Icons.icon [] P2Icons.crossLarge
                            ]
                        ]
                    , Html.div [ WeakCss.nestMany [ "main-content", "cell-warning", "content" ] moduleClass ]
                        [ Html.viewMaybe additionalWarningNoticeView additionalNotice
                        , content
                        ]
                    ]

        tableContent =
            case locationsAndWavesErrors p2Store ++ fullProjectError of
                first :: rest ->
                    List.map (errorView << String.fromHttpError) (first :: rest)

                [] ->
                    Html.viewMaybe tableWarningView model.tableWarning
                        :: (List.map (Html.map config.msg) <|
                                Table.view
                                    { config = tableConfig model maybeProject xbStore
                                    , can = flags.can
                                    }
                                    { showLoadingOnly = showFullTableLoader model
                                    , activeDropdown = activeDropdown
                                    , xbStore = xbStore
                                    , store = p2Store
                                    , model = model
                                    }
                           )
    in
    if locationsAndWavesLoading p2Store || fullProjectIsLoading then
        Spinner.view

    else
        mainAndHeaderView
            [ Html.div [ WeakCss.nest "main-content" moduleClass ] tableContent
            ]


{-| Gets the total row height in pixels based on the number of active metrics.
-}
getTotalRowHeight : Int -> MetricsTransposition -> Int
getTotalRowHeight activeMetrics metricsTransposition =
    case metricsTransposition of
        MetricsInRows ->
            case activeMetrics of
                5 ->
                    112

                4 ->
                    95

                3 ->
                    80

                2 ->
                    52

                1 ->
                    52

                _ ->
                    112

        MetricsInColumns ->
            52


{-| Gets the total row width in pixels based on the number of active metrics.
-}
getTotalColWidth : Int -> MetricsTransposition -> Int
getTotalColWidth activeMetrics metricsTransposition =
    case metricsTransposition of
        MetricsInColumns ->
            case activeMetrics of
                5 ->
                    368

                4 ->
                    304

                3 ->
                    240

                2 ->
                    176

                1 ->
                    120

                _ ->
                    368

        MetricsInRows ->
            120


{-| Gets the line clamp property value used for the caption subtitle by the
`--column-header-line-clamp` CSS var.
-}
getColumnHeaderLineClamp : Int -> MetricsTransposition -> Int
getColumnHeaderLineClamp headerHeight metricsTransposition =
    let
        columnHeaderLabelHeight : Int
        columnHeaderLabelHeight =
            case metricsTransposition of
                MetricsInRows ->
                    40

                MetricsInColumns ->
                    32
    in
    case metricsTransposition of
        MetricsInRows ->
            (headerHeight - columnHeaderLabelHeight) // 30

        MetricsInColumns ->
            (headerHeight - columnHeaderLabelHeight) // 45


{-| Gets the line clamp property value used for the datasets shown in the top=left corner
by the `--corner-datasets-line-clamp` CSS var.
-}
getCornerDatasetsLineClamp : Int -> MetricsTransposition -> Int
getCornerDatasetsLineClamp headerHeight metricsTransposition =
    let
        {- The sum of total margin for the corner datasets element, used to calculate the
           line-clamp property of its text. This is the explanation of the used values:
               - 10 = padding-top
               - 15 = cells-used container
               - 8 = margin-bottom separator
               - 64 = padding-bottom
        -}
        cornerDatasetsMargins : Int
        cornerDatasetsMargins =
            10 + 15 + 8 + 64
    in
    case metricsTransposition of
        MetricsInRows ->
            (headerHeight - cornerDatasetsMargins) // 15

        MetricsInColumns ->
            (headerHeight - cornerDatasetsMargins) // 15


view :
    Config msg
    -> Flags
    -> Maybe XBProject
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> Maybe Modal
    -> Model
    -> Html msg
view ({ msg } as config) flags maybeProject xbStore p2Store maybeModal model =
    let
        clearSelection : Attribute msg
        clearSelection =
            Attrs.attributeIf
                (ACrosstab.anySelected (currentCrosstab model) && maybeModal == Nothing)
                (Events.onEsc <| msg <| SelectAction ClearSelection)

        metadata =
            currentMetadata model

        totalRowHeight : Int
        totalRowHeight =
            getTotalRowHeight (List.length metadata.activeMetrics)
                metadata.metricsTransposition

        totalColWidth : Int
        totalColWidth =
            getTotalColWidth (List.length metadata.activeMetrics)
                metadata.metricsTransposition

        columnHeaderLineClamp : Int
        columnHeaderLineClamp =
            getColumnHeaderLineClamp metadata.headerSize.columnHeight
                metadata.metricsTransposition

        cornerDatasetsLineClamp : Int
        cornerDatasetsLineClamp =
            getCornerDatasetsLineClamp metadata.headerSize.columnHeight
                metadata.metricsTransposition

        ( nFrozenRows, nFrozenCols ) =
            currentMetadata model
                |> .frozenRowsAndColumns
    in
    Html.div
        [ moduleClass
            |> WeakCss.withStates
                [ ( "drag-drop-occurring"
                  , dndSystem.info
                        model.tableCellDndModel.list
                        /= Nothing
                  )
                , ( "is-resizing-table"
                  , Maybe.isJust model.tableHeaderDimensions.resizing
                  )
                ]
        , clearSelection
        , Attrs.cssVars
            [ ( "--total-row-height", String.fromInt totalRowHeight ++ "px" )
            , ( "--total-col-width", String.fromInt totalColWidth ++ "px" )
            , ( "--column-header-line-clamp"
              , String.fromInt columnHeaderLineClamp
              )
            , ( "--corner-datasets-line-clamp"
              , String.fromInt cornerDatasetsLineClamp
              )
            , ( "--frozen-rows"
              , String.fromInt nFrozenRows
              )
            , ( "--frozen-cols"
              , String.fromInt nFrozenCols
              )
            ]
        ]
        [ tableView config
            flags
            maybeProject
            xbStore
            p2Store
            model.activeDropdown
            model
        , case
            currentCrosstabData model
                |> .cellLoaderModel
                |> .openedCellLoaderModal
          of
            CrosstabCellLoader.NoCellLoaderModal ->
                Html.nothing

            CrosstabCellLoader.LoadWithoutProgress ->
                LoaderWithoutProgressModal.view
                    { cancelMsg = msg CancelFullTableLoad }
                    { className = WeakCss.add "full-table-loading" moduleClass
                    , loadingLabel = "Loading your cells. This may take some time…"
                    }

            CrosstabCellLoader.LoadWithProgress { currentProgress, totalProgress } ->
                let
                    progressValue : Float
                    progressValue =
                        min 100 (100 / totalProgress * currentProgress)
                in
                LoaderWithProgressModal.view
                    { cancelMsg = msg CancelFullTableLoad }
                    { className = WeakCss.add "full-table-loading" moduleClass
                    , loadingLabel = "Cells loaded! Downloading your export…"
                    , progressValue = progressValue
                    }
        , Html.map config.msg <|
            Drawers.view
                (WeakCss.add "drawers" moduleClass)
                p2Store
                model.drawer
        ]


{-| Defined boundaries for loading cells around visible area.
Bigger number means more loaded cells
-}
loadingBoundaries : Int
loadingBoundaries =
    1


updateSharedProjectWarning : XBUserSettings -> Model -> ( Model, Cmd msg )
updateSharedProjectWarning settings model =
    ( { model
        | wasSharedProjectWarningDismissed =
            not settings.canShowSharedProjectWarning
      }
    , Cmd.none
    )


directionToAxis : Direction -> Axis
directionToAxis direction =
    case direction of
        Row ->
            Rows

        Column ->
            Columns
