module XB2.Detail.TableView exposing (ChevronType(..), Config, DnDSystem, view)

{-| XB2 TableView module handling the Crosstabs table itself as the name suggests.

TODO: This module is still too large. It should be split into smaller parts.

TODO: Some functions are too complex (e.g. `cellView`). Simplify them.

TODO: Split views from logic.

-}

import BiDict.Assoc as BiDict exposing (BiDict)
import Browser.Dom as Dom
import Browser.Extra as Browser
import Dict.Any exposing (AnyDict)
import DnDList as Dnd
import FormatNumber
import FormatNumber.Locales as Locales
import Html exposing (Attribute, Html)
import Html.Attributes as Attrs exposing (autocomplete)
import Html.Attributes.Extra as Attrs
import Html.Events as Events
import Html.Events.Extra as Events
import Html.Extra as Html
import Html.Keyed
import Html.Lazy
import Json.Decode as Decode
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import List.NonEmpty.Zipper as Zipper
import Markdown
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import Set.Any exposing (AnySet)
import Tuple
import WeakCss exposing (ClassName)
import XB2.Analytics as Analytics
import XB2.ColumnLabel as ColumnLabel
import XB2.Data exposing (AudienceData, AudienceDefinition, MinimumSampleSize, XBUserSettings)
import XB2.Data.Audience.Expression exposing (Expression)
import XB2.Data.AudienceCrosstab as ACrosstab
    exposing
        ( AudienceCrosstab
        , CellData(..)
        , CrosstabBaseAudience
        , Direction(..)
        , Key
        , MovableItems
        , VisibleCells
        )
import XB2.Data.AudienceCrosstab.Sort exposing (SortConfig)
import XB2.Data.AudienceItem as AudienceItem
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.Average as Average exposing (AverageTimeFormat)
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect exposing (XBQueryError)
import XB2.Data.Caption as Caption
import XB2.Data.Metric as Metric exposing (Metric(..))
import XB2.Data.MetricsTransposition exposing (MetricsTransposition(..))
import XB2.Data.Namespace as Namespace
import XB2.Data.SelectionMap as SelectionMap exposing (SelectionMap)
import XB2.Data.Zod.Optional as Optional
import XB2.Detail.Common as Common
    exposing
        ( Dropdown(..)
        )
import XB2.Detail.Heatmap as Heatmap exposing (HeatmapScale)
import XB2.PageScroll as PageScroll
import XB2.RemoteData.Tracked as Tracked
import XB2.Share.CoolTip
import XB2.Share.CoolTip.Platform2 as P2CoolTip
import XB2.Share.Data.Id
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCode
        , QuestionAveragesUnit(..)
        , Wave
        , WaveCode
        )
import XB2.Share.Data.Platform2 exposing (DatasetCode)
import XB2.Share.DragAndDrop.Move
import XB2.Share.Gwi.FormatNumber
import XB2.Share.Gwi.Html.Attributes as Attrs
import XB2.Share.Gwi.Html.Events as Events
import XB2.Share.Gwi.Http exposing (Error(..), OtherError(..))
import XB2.Share.Gwi.List as List
import XB2.Share.Gwi.String as String
import XB2.Share.Icons exposing (IconData)
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.Permissions exposing (Can)
import XB2.Share.Platform2.Bubble as Bubble
import XB2.Share.Platform2.Drawers.SelectionPanel as DrawersPanel
import XB2.Share.Platform2.Dropdown.DropdownMenu as DropdownMenu exposing (DropdownMenu)
import XB2.Share.Platform2.Dropdown.Item as DropdownItem
import XB2.Share.Platform2.Dropdown.Trigger as DropdownTrigger
import XB2.Share.Plural
import XB2.Share.ResizeObserver
import XB2.Share.Store.Platform2
import XB2.Sort as Sort
    exposing
        ( Axis(..)
        , AxisSort(..)
        , Sort
        , SortDirection(..)
        )
import XB2.Store as XBStore
import XB2.Views.Onboarding as Onboarding
import XB2.Views.Scrollbar as Scrollbar
import XB2.Views.SelectionPanel as SelectionPanel


{-| TODO: I think this should come from the parent module of this one... Something like
`XB2.view` for example, and pass that all the way through here. Seems off that the parent
class comes like this.
-}
moduleClass : ClassName
moduleClass =
    Common.moduleClass


{-| TODO: this module and especially config type needs some review.
It's likely that it can be simplified by working with
`AudienceCrosstab` type module.

TODO: This record is TOO big. It MUST be split into smaller parts based on its working
area.

TODO: Model-getter generic functions are really weird... Can't we get the data we need in
the parent module?

-}
type alias Config model msg =
    { clearSelection : msg
    , deselectAllColumns : msg
    , deselectAllRows : msg
    , openLocationsSelection : msg
    , openMetricsSelection : msg
    , openWavesSelection : msg
    , removeSelectedAudiencesConfirm : msg
    , removeAudience : ( Direction, Key ) -> msg
    , duplicateAudience : ( Direction, Key ) -> msg
    , viewGroupExpression : ( Direction, Key ) -> msg
    , openAffixTableForSingle : ( Direction, Key ) -> msg
    , openEditTableForSingle : ( Direction, Key ) -> msg
    , openSelectedSaveAsAudienceModal : msg
    , openSaveAsAudienceModal : ( Direction, Key ) -> msg
    , openAttributeBrowser : msg
    , openAttributeBrowserViaAddAttributeButton : msg
    , addSelectionAsNewBase : msg
    , mergeSelectedRowOrColum : msg
    , addAsNewBase : ( Direction, Key ) -> msg
    , selectAllColumns : msg
    , selectAllRows : msg
    , anySelected : model -> Bool
    , replaceDefaultBase : msg
    , openNewBaseView : msg
    , switchCrosstab : msg
    , toggleAllBasesDropdown : msg
    , toggleViewOptionsDropdown : msg
    , toggleBulkFreezeDropdown : msg
    , getActiveDropdown : model -> Maybe (Dropdown msg)
    , toggleSortByNameDropdown : msg
    , toggleHeaderCollapsed : msg
    , transposeMetrics : MetricsTransposition -> msg
    , getAllSelected : model -> List ( Direction, Key )
    , selectedExpression : model -> List ( Direction, ACrosstab.Key )
    , selectedCount : model -> Int
    , isEveryColumnSelected : model -> Bool
    , isEveryRowSelected : model -> Bool
    , selectableColCountWithoutTotals : model -> Int
    , selectableRowCountWithoutTotals : model -> Int
    , getCurrentBaseAudienceIndex : model -> Int
    , getBaseAudiences : model -> NonEmpty CrosstabBaseAudience
    , goToBaseAtIndex : Int -> msg
    , removeBase : BaseAudience -> msg
    , toggleBase : BaseAudience -> msg
    , crosstabBases :
        { anySelected : model -> Bool
        , selectedCount : model -> Int
        , allSelected : model -> Bool
        , selectAll : msg
        , clearSelection : msg
        , rename : BaseAudience -> msg
        , deleteBases : NonEmpty BaseAudience -> msg
        , getSelected : model -> Maybe (NonEmpty BaseAudience)
        , resetBase : msg
        , disabledBaseSelection : model -> Bool
        , saveInMyAudiences : BaseAudience -> msg
        , openAffixModalForSelected : msg
        , openAffixModalForSingle : BaseAudience -> msg
        , openEditModalForSingle : BaseAudience -> msg
        , openReorderBasesModal : msg
        , reorderBasesPanelDndModel : Dnd.Model
        , reorderBasesPanelDndSystem : Dnd.System ACrosstab.CrosstabBaseAudience msg
        , activeBaseIndex : Int
        , setBaseIndexFocused : Maybe Int -> msg
        , baseSelectedToMoveWithKeyboard : Maybe Int
        }
    , getCrosstab : model -> AudienceCrosstab
    , getMetricsTransposition : model -> MetricsTransposition
    , getActiveLocations : XB2.Share.Store.Platform2.Store -> model -> List Location
    , getAllLocationsSet : XB2.Share.Store.Platform2.Store -> model -> AnySet String LocationCode
    , getActiveWaves : XB2.Share.Store.Platform2.Store -> model -> List Wave
    , openHeatmapSelection : msg
    , openMinimumSampleSizeModal : msg
    , downloadDebugDump : msg
    , withDropdownMenu : DropdownMenu.DropdownMenuOptions msg -> Html msg
    , scrollBasesPanelRight : msg
    , scrollBasesPanelLeft : msg
    , tabsPanelResized : msg
    , basesPanelViewport : model -> Maybe Dom.Viewport
    , getSelectionMap : model -> SelectionMap
    , isHeaderCollapsed : model -> Bool

    -- control panel
    , timeTravel :
        { undoMsg : msg
        , redoMsg : msg
        , undoDisabled : model -> Bool
        , redoDisabled : model -> Bool
        }
    , export :
        { canProcess : model -> Bool
        , isExporting : model -> Bool
        , start : msg
        , startForSelectedCells : SelectionMap.SelectionMap -> msg
        }
    , sharing :
        { shareMsg : msg
        , isMine : Bool
        , isSharedByLink : Bool
        , shareAndCopyLinkMsg : msg
        }
    , saving :
        { save : model -> msg
        , isSharedWithMe : Bool
        , isSaveBtnEnabled : model -> Bool
        , saveAsNew : model -> msg
        }

    -- grid table model stuff
    , metrics : model -> List Metric
    , heatmapMetric : model -> Maybe Metric
    , getDropdownMenu : model -> DropdownMenu msg
    , isFixedPageDropdownOpen : String -> DropdownMenu msg -> Bool
    , isScrolling : model -> Bool
    , isScrollingX : model -> Bool
    , isScrollingY : model -> Bool
    , isScrollbarHovered : model -> Bool
    , dnd : DnDSystem msg
    , dndModel : model -> DnDModel
    , getTableCellsTopOffset : model -> Int
    , heatmapScale : model -> Maybe HeatmapScale
    , getAverageTimeFormat : model -> AverageTimeFormat
    , firstColumnWidth : model -> Int
    , headerColumnHeight : model -> Int
    , hasResizedRowHeader : model -> Bool
    , hasResizedColHeader : model -> Bool
    , isHeaderResizing : Direction -> model -> Bool
    , shouldShowExactRespondentNumber : model -> Bool
    , shouldShowExactUniverseNumber : model -> Bool
    , toggleExactRespondentNumberMsg : msg
    , toggleExactUniverseNumberMsg : msg

    -- sorting
    , getCurrentSort : model -> Sort
    , resetSortForAxis : Axis -> msg
    , resetSortByName : msg
    , sortByOtherAxisMetric : SortConfig -> msg
    , sortByTotalsMetric : SortConfig -> msg
    , sortByOtherAxisAverage : SortConfig -> msg
    , sortByName : Axis -> SortDirection -> msg

    -- Cell freezing
    , getFrozenRowsColumns : model -> ( Int, Int )
    , setFrozenRowsColumns : ( Int, Int ) -> msg

    -- Sample size
    , getMinimumSampleSize : model -> MinimumSampleSize
    , setMinimumSampleSize : MinimumSampleSize -> msg

    -- Search
    , searchTermChanged : String -> msg
    , getCrosstabSearchProps : model -> CrosstabSearchProps
    , setInputFocus : Bool -> msg
    , goToPreviousSearchResult : msg
    , goToNextSearchResult : msg

    -- messages
    , noOp : msg
    , selectRowOrColumnMouseDown : ( Float, Float ) -> msg
    , selectColumn : Events.ShiftState -> Analytics.ItemSelected -> Key -> msg
    , selectRow : Events.ShiftState -> Analytics.ItemSelected -> Key -> msg
    , deselectColumn : Key -> msg
    , deselectRow : Key -> msg
    , openRenameAverageModal : Direction -> Key -> msg
    , removeAverageRowOrCol : Direction -> Key -> msg
    , tableScroll : ( Int, Int ) -> msg
    , scrollUp : msg
    , scrollDown : msg
    , scrollLeft : msg
    , scrollRight : msg
    , hoverScrollbar : msg
    , stopHoveringScrollbar : msg
    , uselessCheckboxClicked : msg
    , switchAverageTimeFormat : msg
    , updateUserSettings : XBUserSettings -> msg
    , openTableWarning :
        { warning : Common.TableWarning msg
        , column : AudienceDefinition
        , row : AudienceDefinition
        }
        -> msg
    , tableHeaderResizeStart : Direction -> XB2.Share.DragAndDrop.Move.Position -> msg
    , tableHeaderResizeStop : msg
    }


type alias CrosstabSearchProps =
    { term : String
    , sanitizedTerm : String
    , searchTopLeftScrollJumps : Maybe (Zipper.Zipper { index : Int, direction : Direction })
    , inputIsFocused : Bool
    }


selectionPanelView : Config model msg -> XB2.Share.Store.Platform2.Store -> model -> Html msg
selectionPanelView config p2Store model =
    let
        selectedCount : Int
        selectedCount =
            config.selectedCount model

        numCols : Int
        numCols =
            model |> config.getCrosstab |> ACrosstab.selectableColCountWithoutTotals

        numRows : Int
        numRows =
            model |> config.getCrosstab |> ACrosstab.selectableRowCountWithoutTotals

        isBulkFreezeDropdownOpened : Bool
        isBulkFreezeDropdownOpened =
            case config.getActiveDropdown model of
                Just activeDropdown ->
                    activeDropdown == BulkFreezeDropdown

                Nothing ->
                    False

        isEveryColumnSelected : Bool
        isEveryColumnSelected =
            config.isEveryColumnSelected model

        isEveryRowSelected : Bool
        isEveryRowSelected =
            config.isEveryRowSelected model

        ( allColumnsMsg, allColumnsLabel ) =
            if isEveryColumnSelected then
                ( config.deselectAllColumns, "Deselect all columns" )

            else
                ( config.selectAllColumns, "Select all columns" )

        ( allRowsMsg, allRowsLabel ) =
            if isEveryRowSelected then
                ( config.deselectAllRows, "Deselect all rows" )

            else
                ( config.selectAllRows, "Select all rows" )

        buttonView :
            Bool
            -> ClassName
            -> String
            -> IconData
            -> msg
            -> Maybe String
            -> Html msg
        buttonView disabled btnClass title icon onClick disabledMsg =
            let
                buttonView_ : Html msg
                buttonView_ =
                    Html.button
                        [ btnClass |> WeakCss.withStates [ ( "disabled", disabled ) ]
                        , Attrs.disabled disabled
                        , Attrs.attributeIf (not disabled) <| Events.onClick onClick
                        ]
                        [ Html.i [ WeakCss.nest "icon" btnClass ] [ XB2.Share.Icons.icon [] icon ]
                        , Html.text title
                        ]
            in
            case disabledMsg of
                Nothing ->
                    buttonView_

                Just disabledMsg_ ->
                    P2CoolTip.viewIf disabled
                        { targetHtml = buttonView_
                        , type_ =
                            XB2.Share.CoolTip.RelativeAncestor
                                ("."
                                    ++ WeakCss.toString
                                        SelectionPanel.panelClass
                                )
                        , position = XB2.Share.CoolTip.Top
                        , wrapperAttributes = [ WeakCss.nest "tooltip" btnClass ]
                        , tooltipText = disabledMsg_
                        }

        bulkFreezeDropdownView : ClassName -> Html msg
        bulkFreezeDropdownView btnClass =
            let
                dropdownClass : ClassName
                dropdownClass =
                    WeakCss.add "dropdown" btnClass

                dropdownMenuClass : ClassName
                dropdownMenuClass =
                    WeakCss.add "menu" dropdownClass

                crosstab : AudienceCrosstab
                crosstab =
                    config.getCrosstab model

                ( rowsFrozen, colsFrozen ) =
                    config.getFrozenRowsColumns model

                nCrosstabRows : Int
                nCrosstabRows =
                    List.length (ACrosstab.getRows crosstab)

                nCrosstabCols : Int
                nCrosstabCols =
                    List.length (ACrosstab.getColumns crosstab)
            in
            Html.div
                [ WeakCss.toClass dropdownClass ]
                [ DropdownTrigger.buttonView
                    { onClick = config.toggleBulkFreezeDropdown
                    , open = isBulkFreezeDropdownOpened
                    , openedIcon = P2Icons.caretUp
                    , closedIcon = P2Icons.caretDown
                    , activeIconClass = Nothing
                    }
                    [ DropdownTrigger.label <| Html.text "Freeze"
                    , DropdownTrigger.leftIcon (Just P2Icons.freeze)
                    , DropdownTrigger.disabled (selectedCount < 1)
                    , DropdownTrigger.class dropdownClass
                    ]
                , Html.viewIfLazy isBulkFreezeDropdownOpened
                    (\_ ->
                        Html.div
                            [ dropdownMenuClass
                                |> WeakCss.withActiveStates
                                    [ "expand-right"
                                    , "appear-top"
                                    ]
                            ]
                            [ DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 0, colsFrozen )
                                    )
                                , DropdownItem.label "No rows"
                                , DropdownItem.selected
                                    (rowsFrozen < 1)
                                ]
                            , DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 1, colsFrozen )
                                    )
                                , DropdownItem.label "First 1 row"
                                , DropdownItem.disabled (nCrosstabRows < 1)
                                , DropdownItem.selected
                                    (rowsFrozen == 1)
                                ]
                            , DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 2, colsFrozen )
                                    )
                                , DropdownItem.label "First 2 rows"
                                , DropdownItem.disabled (nCrosstabRows < 2)
                                , DropdownItem.selected
                                    (rowsFrozen == 2)
                                , DropdownItem.withSeparator True
                                ]
                            , DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 0 )
                                    )
                                , DropdownItem.label "No columns"
                                , DropdownItem.selected
                                    (colsFrozen < 1)
                                ]
                            , DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 1 )
                                    )
                                , DropdownItem.label "First 1 column"
                                , DropdownItem.disabled (nCrosstabCols < 1)
                                , DropdownItem.selected
                                    (colsFrozen == 1)
                                ]
                            , DropdownItem.view
                                [ DropdownItem.class dropdownMenuClass
                                , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 2 )
                                    )
                                , DropdownItem.label "First 2 columns"
                                , DropdownItem.disabled (nCrosstabCols < 2)
                                , DropdownItem.selected
                                    (colsFrozen == 2)
                                ]
                            ]
                    )
                ]

        addCreateBaseBtnTitle : String
        addCreateBaseBtnTitle =
            if selectedCount > 1 then
                "Create as a new base"

            else
                "Add as new base"

        deleteMsg : msg
        deleteMsg =
            -- TODO: Express this in another way to not have infinite cardinality.
            case config.getAllSelected model of
                [] ->
                    config.removeSelectedAudiencesConfirm

                [ onlyOne ] ->
                    config.removeAudience onlyOne

                _ ->
                    config.removeSelectedAudiencesConfirm

        haveAllNeededDatasets : Bool
        haveAllNeededDatasets =
            -- TODO: Express this in another way to not have infinite cardinality.
            case config.selectedExpression model of
                [ key ] ->
                    let
                        datasetsToNamespaces : BiDict DatasetCode Namespace.Code
                        datasetsToNamespaces =
                            p2Store.datasetsToNamespaces
                                |> RemoteData.withDefault BiDict.empty
                    in
                    key
                        |> Tuple.second
                        |> .item
                        |> AudienceItem.getDefinition
                        |> XB2.Data.definitionNamespaceCodes
                        |> XB2.Share.Data.Platform2.datasetCodesForNamespaceCodes
                            datasetsToNamespaces
                            p2Store.lineages
                        |> RemoteData.isSuccess

                _ ->
                    False
    in
    SelectionPanel.view
        { selectedCount = selectedCount
        , opened =
            config.anySelected model
                && not (config.crosstabBases.anySelected model)
        , clearSelection = config.clearSelection
        , uselessCheckboxClicked = config.uselessCheckboxClicked
        , buttonsGroup1 =
            \btnClass ->
                [ Html.viewIf (numCols > 0) <|
                    Html.button
                        [ WeakCss.toClass btnClass
                        , Events.onClick allColumnsMsg
                        , Attrs.id "modal-selection-select-all-button"
                        ]
                        [ Html.text allColumnsLabel
                        ]
                , Html.viewIf (numRows > 0) <|
                    Html.button
                        [ WeakCss.toClass btnClass
                        , Events.onClick allRowsMsg
                        ]
                        [ Html.text allRowsLabel
                        ]
                ]
        , buttonsGroup2 =
            \btnClass ->
                [ buttonView
                    (selectedCount == 1)
                    (WeakCss.add "action" btnClass)
                    "Merge"
                    P2Icons.merge
                    config.mergeSelectedRowOrColum
                    (if selectedCount == 1 then
                        Just "Please select a second column/row"

                     else
                        Just ""
                    )
                , bulkFreezeDropdownView
                    btnClass
                , buttonView
                    False
                    (WeakCss.add "action" btnClass)
                    "Affix attributes/audiences"
                    P2Icons.edit
                    config.openAttributeBrowser
                    Nothing
                , buttonView
                    False
                    (WeakCss.add "action" btnClass)
                    "Export selected cells"
                    P2Icons.export
                    (config.export.startForSelectedCells (config.getSelectionMap model))
                    Nothing
                , buttonView
                    False
                    (WeakCss.add "action" btnClass)
                    addCreateBaseBtnTitle
                    P2Icons.baseAudience
                    config.addSelectionAsNewBase
                    Nothing
                , buttonView
                    (selectedCount /= 1 || not haveAllNeededDatasets)
                    (WeakCss.add "action" btnClass)
                    "Save as a new audience"
                    P2Icons.audiences
                    config.openSelectedSaveAsAudienceModal
                    (if selectedCount /= 1 then
                        Just "Cannot save multiple groups as audiences"

                     else
                        Just "Not enough datasets for such audience"
                    )
                , buttonView
                    False
                    (WeakCss.add "delete" btnClass)
                    "Delete"
                    P2Icons.trash
                    deleteMsg
                    Nothing
                ]
        }


crosstabBasesView : Config model msg -> XB2.Share.Store.Platform2.Store -> model -> Html msg
crosstabBasesView config store model =
    let
        panelConfig :
            { anySelected : model -> Bool
            , selectedCount : model -> Int
            , allSelected : model -> Bool
            , selectAll : msg
            , clearSelection : msg
            , rename : BaseAudience -> msg
            , deleteBases : NonEmpty BaseAudience -> msg
            , getSelected : model -> Maybe (NonEmpty BaseAudience)
            , resetBase : msg
            , disabledBaseSelection : model -> Bool
            , saveInMyAudiences : BaseAudience -> msg
            , openAffixModalForSelected : msg
            , openAffixModalForSingle : BaseAudience -> msg
            , openEditModalForSingle : BaseAudience -> msg
            , openReorderBasesModal : msg
            , reorderBasesPanelDndModel : Dnd.Model
            , reorderBasesPanelDndSystem : Dnd.System ACrosstab.CrosstabBaseAudience msg
            , activeBaseIndex : Int
            , setBaseIndexFocused : Maybe Int -> msg
            , baseSelectedToMoveWithKeyboard : Maybe Int
            }
        panelConfig =
            config.crosstabBases

        selectedCount : Int
        selectedCount =
            panelConfig.selectedCount model

        opened : Bool
        opened =
            not (config.anySelected model)
                && panelConfig.anySelected model

        ( allToggleMsg, allToggleLabel ) =
            if panelConfig.allSelected model then
                ( panelConfig.clearSelection, "Deselect All" )

            else
                ( panelConfig.selectAll, "Select All" )

        buttonView :
            Bool
            -> Maybe String
            -> ClassName
            -> String
            -> IconData
            -> msg
            -> Html msg
        buttonView disabled disabledMessage btnClass title icon onClick =
            Html.button
                [ btnClass |> WeakCss.withStates [ ( "disabled", disabled ) ]
                , Attrs.disabled disabled
                , Events.onClick onClick
                , disabledMessage
                    |> Maybe.filter (\message -> disabled && not (String.isEmpty message))
                    |> Attrs.attributeMaybe (Attrs.attribute "data-title")
                ]
                [ Html.i [ WeakCss.nest "icon" btnClass ]
                    [ XB2.Share.Icons.icon [] icon ]
                , Html.text title
                ]
    in
    panelConfig.getSelected model
        |> Html.viewMaybe
            (\selectedBases ->
                let
                    usedNamespaceCodes : List Namespace.Code
                    usedNamespaceCodes =
                        selectedBases
                            |> NonemptyList.toList
                            |> List.fastConcatMap BaseAudience.namespaceCodes

                    namespacesUnknownOrIncompatible : Bool
                    namespacesUnknownOrIncompatible =
                        XB2.Share.Data.Labels.areNamespacesIncompatibleOrUnknown
                            store.lineages
                            usedNamespaceCodes
                in
                SelectionPanel.view
                    { selectedCount = selectedCount
                    , opened = opened
                    , clearSelection = panelConfig.clearSelection
                    , uselessCheckboxClicked = config.uselessCheckboxClicked
                    , buttonsGroup1 =
                        \btnClass ->
                            [ Html.button
                                [ WeakCss.toClass btnClass
                                , Events.onClick allToggleMsg
                                , Attrs.id "modal-selection-bases-select-all-button"
                                ]
                                [ Html.text allToggleLabel ]
                            ]
                    , buttonsGroup2 =
                        \btnClass ->
                            [ buttonView
                                (selectedCount == 0 || namespacesUnknownOrIncompatible)
                                (Just "You have selected bases from incompatible data sets, please select only relevant bases in order to affix.")
                                (WeakCss.add "action" btnClass)
                                "Affix bases"
                                P2Icons.edit
                                panelConfig.openAffixModalForSelected
                            , buttonView
                                (selectedCount /= 1)
                                Nothing
                                (WeakCss.add "action" btnClass)
                                "View/rename"
                                P2Icons.fileSearch
                                (panelConfig.rename <| NonemptyList.head selectedBases)
                            , buttonView
                                (selectedCount /= 1)
                                Nothing
                                (WeakCss.add "action" btnClass)
                                "Save as a new audience"
                                P2Icons.audiences
                                config.openSelectedSaveAsAudienceModal
                            , buttonView
                                False
                                Nothing
                                (WeakCss.add "delete" btnClass)
                                "Delete"
                                P2Icons.trash
                                (panelConfig.deleteBases selectedBases)
                            ]
                    }
            )


{-| TODO: This is a debug view. Move it into another module.
-}
tableCountsView :
    Config model msg
    -> RemoteData.WebData XBUserSettings
    -> model
    -> ()
    -> Html msg
tableCountsView config userSettings model () =
    let
        crosstab : AudienceCrosstab
        crosstab =
            config.getCrosstab model

        shouldPinThisModal : Bool
        shouldPinThisModal =
            RemoteData.unwrap False .pinDebugOptions userSettings

        visibleCells : VisibleCells
        visibleCells =
            ACrosstab.getVisibleCells
                crosstab

        visibleCellsSummary : String
        visibleCellsSummary =
            (\{ topLeftRow, topLeftCol, bottomRightRow, bottomRightCol } ->
                String.fromInt topLeftRow
                    ++ "/"
                    ++ String.fromInt topLeftCol
                    ++ " - "
                    ++ String.fromInt bottomRightRow
                    ++ "/"
                    ++ String.fromInt bottomRightCol
            )
                visibleCells

        frozenCellsSummary : String
        frozenCellsSummary =
            String.fromInt visibleCells.frozenRows
                ++ "/"
                ++ String.fromInt visibleCells.frozenCols

        sort : Sort
        sort =
            config.getCurrentSort model

        sizeWithTotals : Int
        sizeWithTotals =
            ACrosstab.getSizeWithTotals crosstab

        basesCount : Int
        basesCount =
            ACrosstab.getBaseAudiencesCount crosstab

        loadedCount : Int
        loadedCount =
            ACrosstab.loadedCellDataCount crosstab

        liView : String -> Html msg
        liView text =
            Html.li [] [ Html.text text ]

        userSettingsView : List (Html msg)
        userSettingsView =
            case userSettings of
                Success settings ->
                    let
                        userSettingsLiView :
                            String
                            -> (XBUserSettings -> Bool)
                            -> (XBUserSettings -> XBUserSettings)
                            -> Html msg
                        userSettingsLiView title get set =
                            Html.li [ WeakCss.nestMany [ "debug-info", "user-settings" ] moduleClass ]
                                [ Html.text title
                                , Html.input
                                    [ Attrs.type_ "checkbox"
                                    , Attrs.checked <| get settings
                                    , Events.onClick <| config.updateUserSettings <| set settings
                                    ]
                                    []
                                ]
                    in
                    [ liView "*User settings*"
                    , userSettingsLiView "canShowSharedProjectWarning"
                        .canShowSharedProjectWarning
                        (\s ->
                            { s
                                | canShowSharedProjectWarning =
                                    not s.canShowSharedProjectWarning
                            }
                        )
                    , userSettingsLiView "xb2ListFTUESeen"
                        .xb2ListFTUESeen
                        (\s -> { s | xb2ListFTUESeen = not s.xb2ListFTUESeen })
                    , userSettingsLiView "renamingCellsOnboardingSeen"
                        .renamingCellsOnboardingSeen
                        (\s ->
                            { s
                                | renamingCellsOnboardingSeen =
                                    not s.renamingCellsOnboardingSeen
                            }
                        )
                    , userSettingsLiView "freezeRowsColumnsOnboardingSeen"
                        .freezeRowsColumnsOnboardingSeen
                        (\s ->
                            { s
                                | freezeRowsColumnsOnboardingSeen =
                                    not s.freezeRowsColumnsOnboardingSeen
                            }
                        )
                    , userSettingsLiView "unfreezeTheFilters"
                        .unfreezeTheFilters
                        (\s ->
                            { s
                                | unfreezeTheFilters =
                                    not s.unfreezeTheFilters
                            }
                        )
                    , userSettingsLiView "editABOnboardingSeen"
                        .editAttributeExpressionOnboardingSeen
                        (\s ->
                            { s
                                | editAttributeExpressionOnboardingSeen =
                                    not s.editAttributeExpressionOnboardingSeen
                            }
                        )
                    , liView "------------------------------------------------"
                    , liView "*Do not show again types*"
                    ]
                        ++ List.map
                            (\doNotShowAgain ->
                                case doNotShowAgain of
                                    XB2.Data.DeleteRowsColumnsModal ->
                                        userSettingsLiView
                                            "DeleteRowsColumnsModal"
                                            (always True)
                                            (\s ->
                                                { s
                                                    | doNotShowAgain =
                                                        List.filter
                                                            ((/=) XB2.Data.DeleteRowsColumnsModal)
                                                            s.doNotShowAgain
                                                }
                                            )

                                    XB2.Data.DeleteBasesModal ->
                                        userSettingsLiView
                                            "DeleteBasesModal"
                                            (always True)
                                            (\s ->
                                                { s
                                                    | doNotShowAgain =
                                                        List.filter ((/=) XB2.Data.DeleteBasesModal)
                                                            s.doNotShowAgain
                                                }
                                            )
                            )
                            settings.doNotShowAgain
                        ++ [ liView "------------------------------------------------" ]

                NotAsked ->
                    [ liView "NotAsked" ]

                Loading ->
                    [ liView "Loading" ]

                Failure f ->
                    [ liView <| String.fromHttpError f ]

        {- A toggable debug option to see row/column indices inside the crosstab cells -}
        debugModesView : List (Html msg)
        debugModesView =
            case userSettings of
                Success settings ->
                    let
                        userSettingsLiView :
                            String
                            -> (XBUserSettings -> Bool)
                            -> (XBUserSettings -> XBUserSettings)
                            -> Html msg
                        userSettingsLiView title get set =
                            Html.li
                                [ WeakCss.nestMany [ "debug-info", "user-settings" ]
                                    moduleClass
                                ]
                                [ Html.text title
                                , Html.input
                                    [ Attrs.type_ "checkbox"
                                    , Attrs.checked <| get settings
                                    , Events.onClick <|
                                        config.updateUserSettings <|
                                            set settings
                                    ]
                                    []
                                ]
                    in
                    [ liView "*Debug modes*"
                    , userSettingsLiView "Pin this modal?"
                        .pinDebugOptions
                        (\s ->
                            { s
                                | pinDebugOptions =
                                    not s.pinDebugOptions
                            }
                        )
                    , userSettingsLiView "showDetailTableInDebugMode"
                        .showDetailTableInDebugMode
                        (\s ->
                            { s
                                | showDetailTableInDebugMode =
                                    not s.showDetailTableInDebugMode
                            }
                        )
                    , liView "------------------------------------------------"
                    ]

                NotAsked ->
                    [ liView "NotAsked" ]

                Loading ->
                    [ liView "Loading" ]

                Failure f ->
                    [ liView <| String.fromHttpError f ]
    in
    Html.div
        [ WeakCss.add "debug-info" moduleClass
            |> WeakCss.withStates [ ( "pinned", shouldPinThisModal ) ]
        ]
        [ Html.text "Debug info"
        , Html.div [ WeakCss.nestMany [ "debug-info", "inner" ] moduleClass ]
            [ [ "*Cell data*"
              , "Total cell count: " ++ String.fromInt (sizeWithTotals * basesCount)
              , "Cells with data requested: " ++ String.fromInt loadedCount
              , "Bases count: " ++ String.fromInt basesCount
              , "Cells count per 1 base: " ++ String.fromInt sizeWithTotals
              , "Sort (rows): " ++ Sort.axisSortToDebugString sort.rows
              , "Sort (cols): " ++ Sort.axisSortToDebugString sort.columns
              , "Visible cells (from-to): " ++ visibleCellsSummary
              , "Frozen cells (rows/columns): " ++ frozenCellsSummary
              ]
                |> List.map liView
                |> (\liViews -> userSettingsView ++ liViews)
                |> (\settingsAndLiViews -> debugModesView ++ settingsAndLiViews)
                |> Html.ul []
            ]
        ]


toolsPanelView : Config model msg -> Can -> XBStore.Store -> XB2.Share.Store.Platform2.Store -> model -> Html msg
toolsPanelView config can xbStore store model =
    let
        crosstab : AudienceCrosstab
        crosstab =
            config.getCrosstab model

        isEmpty : Bool
        isEmpty =
            ACrosstab.isEmpty crosstab

        isSelectedWaves : Bool
        isSelectedWaves =
            List.isEmpty (config.getActiveWaves store model)

        isSelectedLocations : Bool
        isSelectedLocations =
            List.isEmpty (config.getActiveLocations store model)

        showNumbersWaves : Bool
        showNumbersWaves =
            isEmpty && isSelectedWaves

        showNumbersLocations : Bool
        showNumbersLocations =
            isEmpty && isSelectedLocations

        drawersPanelData :
            ( DrawersPanel.DrawerType msg
            , List (DrawersPanel.DrawerType msg)
            )
        drawersPanelData =
            ( DrawersPanel.WavesDrawer
                { openDrawer = config.openWavesSelection
                , activeWaves = config.getActiveWaves store model
                , canEdit = True
                , notShowingNumbers = showNumbersWaves
                , disabledTooltip = Just "Please add an attribute/audience to start filtering by waves"
                }
            , [ DrawersPanel.LocationsDrawer
                    { openDrawer = config.openLocationsSelection
                    , activeLocations = config.getActiveLocations store model
                    , allLocations = config.getAllLocationsSet store model
                    , canEdit = True
                    , notShowingNumbers = showNumbersLocations
                    , disabledTooltip = Just "Please add an attribute/audience to start filtering by locations"
                    , locationsShowingMode = DrawersPanel.ShowByComparison
                    }
              ]
            )
    in
    Html.viewIf (not <| config.isHeaderCollapsed model) <|
        Html.div [ WeakCss.nest "tools-panel" moduleClass ]
            [ DrawersPanel.view
                (WeakCss.addMany [ "tools-panel", "panels" ] moduleClass)
                DrawersPanel.NotTVEdit
                drawersPanelData
            , Html.viewIfLazy (can XB2.Share.Permissions.UseDebugButtons)
                (tableCountsView config xbStore.userSettings model)
            , Html.viewIf (ACrosstab.isEmpty crosstab)
                (unfreezeFiltersOnboardingView config.updateUserSettings xbStore.userSettings)
            ]


{-| Onboarding modal for the Freezing Rows and Columns feature. Dismisses with a click on
"Got it"
-}
freezingRowsAndColumnsOnboardingView : (XBUserSettings -> msg) -> WebData XBUserSettings -> Html msg
freezingRowsAndColumnsOnboardingView updateUserSettingsMsg remoteUserSettings =
    let
        showOnboarding : Bool
        showOnboarding =
            case remoteUserSettings of
                RemoteData.Success { freezeRowsColumnsOnboardingSeen } ->
                    not freezeRowsColumnsOnboardingSeen

                RemoteData.Failure _ ->
                    False

                RemoteData.NotAsked ->
                    False

                RemoteData.Loading ->
                    False
    in
    Html.viewIfLazy showOnboarding <|
        \() ->
            Html.viewMaybe
                (\closeMsg ->
                    Html.div
                        [ WeakCss.nestMany
                            [ "freezing"
                            , "onboarding"
                            ]
                            moduleClass
                        ]
                        [ Html.div
                            [ WeakCss.nestMany
                                [ "freezing"
                                , "onboarding"
                                , "banner"
                                ]
                                moduleClass
                            ]
                            []
                        , Html.span
                            [ WeakCss.nestMany
                                [ "freezing"
                                , "onboarding"
                                , "new-badge"
                                ]
                                moduleClass
                            ]
                            [ Html.text "New" ]
                        , Html.h3
                            [ WeakCss.nestMany
                                [ "freezing"
                                , "onboarding"
                                , "title"
                                ]
                                moduleClass
                            ]
                            [ Html.text "Freeze Cells with Ease! ❄️" ]
                        , Html.p
                            [ WeakCss.nestMany
                                [ "freezing"
                                , "onboarding"
                                , "tip"
                                ]
                                moduleClass
                            ]
                            [ Html.text
                                """Introducing the ability to freeze cells in your 
                                crosstabs effortlessly. Maintain key information at your 
                                fingertips for a more focused analysis."""
                            ]
                        , Html.button
                            [ WeakCss.nestMany
                                [ "freezing"
                                , "onboarding"
                                , "got-it"
                                ]
                                moduleClass
                            , Events.onClick closeMsg
                            ]
                            [ Html.text "Got it" ]
                        ]
                )
                (remoteUserSettings
                    |> RemoteData.toMaybe
                    |> Maybe.map
                        (\settings ->
                            updateUserSettingsMsg
                                { settings
                                    | freezeRowsColumnsOnboardingSeen = True
                                }
                        )
                )


{-| Onboarding modal for the Unfreeze filters option feature. Dismisses with a click on
"Got it"
-}
unfreezeFiltersOnboardingView : (XBUserSettings -> msg) -> WebData XBUserSettings -> Html msg
unfreezeFiltersOnboardingView updateUserSettingsMsg remoteUserSettings =
    let
        showOnboarding : Bool
        showOnboarding =
            case remoteUserSettings of
                RemoteData.Success { unfreezeTheFilters } ->
                    not unfreezeTheFilters

                RemoteData.Failure _ ->
                    False

                RemoteData.NotAsked ->
                    False

                RemoteData.Loading ->
                    False
    in
    Html.viewIfLazy showOnboarding <|
        \() ->
            Html.viewMaybe
                (\closeMsg ->
                    Html.div
                        [ WeakCss.nestMany
                            [ "unfreeze"
                            , "onboarding"
                            ]
                            moduleClass
                        ]
                        [ Html.div
                            [ WeakCss.nestMany
                                [ "unfreeze"
                                , "onboarding"
                                , "banner"
                                ]
                                moduleClass
                            ]
                            []
                        , Html.span
                            [ WeakCss.nestMany
                                [ "unfreeze"
                                , "onboarding"
                                , "new-badge"
                                ]
                                moduleClass
                            ]
                            [ Html.text "New" ]
                        , Html.h3
                            [ WeakCss.nestMany
                                [ "unfreeze"
                                , "onboarding"
                                , "title"
                                ]
                                moduleClass
                            ]
                            [ Html.text "Want to start here? Now you can!" ]
                        , Html.p
                            [ WeakCss.nestMany
                                [ "unfreeze"
                                , "onboarding"
                                , "tip"
                                ]
                                moduleClass
                            ]
                            [ Html.text
                                """You can now select locations and waves 
                                before adding questions in Crosstabs, 
                                another way to get to where you want, 
                                adding even more ease to your workflow."""
                            ]
                        , Html.button
                            [ WeakCss.nestMany
                                [ "unfreeze"
                                , "onboarding"
                                , "got-it"
                                ]
                                moduleClass
                            , Events.onClick closeMsg
                            ]
                            [ Html.text "Got it" ]
                        ]
                )
                (remoteUserSettings
                    |> RemoteData.toMaybe
                    |> Maybe.map
                        (\settings ->
                            updateUserSettingsMsg
                                { settings
                                    | unfreezeTheFilters = True
                                }
                        )
                )



-- TABLE
-- Dropdowns


baseManagerDropdownView : Config model msg -> { baseAudience : BaseAudience } -> Bool -> Html msg
baseManagerDropdownView config { baseAudience } isDefault =
    let
        dropdownClass : ClassName
        dropdownClass =
            WeakCss.add "base-manager-dropdown" moduleClass

        dropdownMenuClass : ClassName
        dropdownMenuClass =
            WeakCss.add "menu" dropdownClass
    in
    Html.div
        [ dropdownClass |> WeakCss.withActiveStates [ "dynamic" ] ]
        [ Html.div
            [ dropdownMenuClass |> WeakCss.withActiveStates [ "expand-left" ] ]
            (let
                baseAudienceExpressionIsNotEmpty : Bool
                baseAudienceExpressionIsNotEmpty =
                    not <| BaseAudience.isDefault baseAudience
             in
             if isDefault then
                [ DropdownItem.viewIf baseAudienceExpressionIsNotEmpty
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick (config.crosstabBases.rename baseAudience)
                    , DropdownItem.label "View/rename"
                    , DropdownItem.leftIcon P2Icons.fileSearch
                    ]
                , DropdownItem.viewIf baseAudienceExpressionIsNotEmpty
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick (config.crosstabBases.openEditModalForSingle baseAudience)
                    , DropdownItem.label "Edit expression"
                    , DropdownItem.leftIcon P2Icons.edit
                    ]
                , DropdownItem.view
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick config.crosstabBases.openReorderBasesModal
                    , DropdownItem.label "Reorder base"
                    , DropdownItem.leftIcon P2Icons.generalChange
                    ]
                , DropdownItem.view
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick config.replaceDefaultBase
                    , DropdownItem.label "Replace"
                    , DropdownItem.leftIcon P2Icons.replace
                    ]
                , DropdownItem.view
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick config.crosstabBases.resetBase
                    , DropdownItem.label "Reset base"
                    , DropdownItem.leftIcon P2Icons.sync
                    , DropdownItem.disabled (BaseAudience.isDefault baseAudience)
                    ]
                ]

             else
                [ DropdownItem.view
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick config.crosstabBases.openReorderBasesModal
                    , DropdownItem.label "Reorder base"
                    , DropdownItem.leftIcon P2Icons.generalChange
                    ]
                , DropdownItem.viewIf baseAudienceExpressionIsNotEmpty
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick (config.crosstabBases.rename baseAudience)
                    , DropdownItem.label "View/rename"
                    , DropdownItem.leftIcon P2Icons.fileSearch
                    ]
                , DropdownItem.viewIf baseAudienceExpressionIsNotEmpty
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.label "Save as a new audience"
                    , DropdownItem.onClick (config.crosstabBases.saveInMyAudiences baseAudience)
                    , DropdownItem.leftIcon P2Icons.userFriends
                    ]
                , DropdownItem.viewIf baseAudienceExpressionIsNotEmpty
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick (config.crosstabBases.openEditModalForSingle baseAudience)
                    , DropdownItem.label "Edit expression"
                    , DropdownItem.leftIcon P2Icons.edit
                    ]
                , DropdownItem.view
                    [ DropdownItem.class dropdownMenuClass
                    , DropdownItem.onClick (config.removeBase baseAudience)
                    , DropdownItem.label "Delete base"
                    , DropdownItem.leftIcon P2Icons.trash
                    ]
                ]
            )
        ]


getBaseDropdownId : Int -> String
getBaseDropdownId index =
    "base-panel-audience-menu-" ++ String.fromInt index


baseTabPlaceHolder : Float -> Html msg
baseTabPlaceHolder width =
    Html.div
        [ WeakCss.nestMany [ "bases-panel", "tabs", "tab", "placeholder" ] moduleClass
        , Attrs.style "width" (String.fromFloat width ++ "px")
        ]
        []


basesPanelGhostView :
    Config model msg
    ->
        { currentActiveBaseIndex : Int
        }
    -> model
    -> List ACrosstab.CrosstabBaseAudience
    -> Html msg
basesPanelGhostView config props model items =
    let
        maybeDragIndex : Maybe Int
        maybeDragIndex =
            config.crosstabBases.reorderBasesPanelDndSystem.info
                config.crosstabBases.reorderBasesPanelDndModel
                |> Maybe.map .dragIndex

        maybeDragItem : Maybe ACrosstab.CrosstabBaseAudience
        maybeDragItem =
            maybeDragIndex
                |> Maybe.andThen
                    (\dragIndex ->
                        items
                            |> List.drop dragIndex
                            |> List.head
                    )
    in
    case maybeDragItem of
        Just crosstabBase ->
            let
                tabClass : ClassName
                tabClass =
                    WeakCss.addMany [ "bases-panel", "tabs", "tab" ] moduleClass

                tabEllipsisIconView : Html msg
                tabEllipsisIconView =
                    Html.div
                        [ tabClass
                            |> WeakCss.nestMany [ "ellipsis", "icon" ]
                        ]
                        [ XB2.Share.Icons.icon [] P2Icons.ellipsisVertical
                        ]

                isActive : Bool
                isActive =
                    Just props.currentActiveBaseIndex == maybeDragIndex

                dropdownMenuView : Html msg
                dropdownMenuView =
                    config.withDropdownMenu
                        { id = ""
                        , orientation = DropdownMenu.BottomLeft
                        , screenBottomEdgeMinOffset = 0
                        , screenSideEdgeMinOffset = 0
                        , content =
                            baseManagerDropdownView
                                config
                                { baseAudience = baseAudienceToShow
                                }
                                isDefaultBase
                        , controlElementAttrs = [ WeakCss.nest "ellipsis" tabClass ]
                        , controlElementContent = [ tabEllipsisIconView ]
                        }

                baseName : String
                baseName =
                    Caption.getName caption

                caption : Caption.Caption
                caption =
                    BaseAudience.getCaption baseAudienceToShow

                baseAudienceToShow : BaseAudience
                baseAudienceToShow =
                    ACrosstab.unwrapCrosstabBase crosstabBase

                {- This is checking if a base is default for the current crosstab, but the
                   default base is always set at the last in the list
                -}
                isDefaultBase : Bool
                isDefaultBase =
                    ACrosstab.isDefaultBase crosstabBase

                isSelected : Bool
                isSelected =
                    ACrosstab.isBaseSelected crosstabBase

                hasEmptyExpression : Bool
                hasEmptyExpression =
                    BaseAudience.isDefault baseAudienceToShow
            in
            Html.div
                ((tabClass
                    |> WeakCss.withStates
                        [ ( "is-default", isDefaultBase )
                        , ( "selected", isSelected )
                        , ( "active", isActive )
                        , ( "ghosted", True )
                        ]
                 )
                    :: config.crosstabBases.reorderBasesPanelDndSystem.ghostStyles
                        config.crosstabBases.reorderBasesPanelDndModel
                    ++ [ Attrs.style "top" "-8px" ]
                )
                [ Html.viewIf (not isDefaultBase && not hasEmptyExpression) <|
                    Html.button
                        [ WeakCss.add "checkbox" tabClass
                            |> WeakCss.withStates
                                [ ( "checked", isSelected )
                                , ( "disabled"
                                  , config.crosstabBases.disabledBaseSelection model
                                  )
                                ]
                        , Attrs.attributeIf
                            (not <|
                                config.crosstabBases.disabledBaseSelection model
                            )
                          <|
                            Events.onClickStopPropagation <|
                                config.toggleBase baseAudienceToShow
                        ]
                        [ Html.i
                            [ WeakCss.nestMany [ "checkbox", "icon" ] tabClass ]
                            [ XB2.Share.Icons.icon [] <|
                                if isSelected then
                                    P2Icons.checkboxFilled

                                else
                                    P2Icons.checkboxUnfilled
                            ]
                        ]
                , Html.span [ WeakCss.nest "label" tabClass ] [ Html.text baseName ]
                , dropdownMenuView
                ]

        Nothing ->
            Html.nothing


baseTabView :
    Config model msg
    ->
        { currentBaseIndex : Int
        , index : Int
        , anyBaseSelected : Bool
        , updateUserSettingsToMsg : XBUserSettings -> msg
        , userSettings : WebData XBUserSettings
        , selectedToMoveWithKeyboard : Bool
        , isInDebugMode : Bool
        }
    -> model
    -> CrosstabBaseAudience
    -> Html msg
baseTabView config props model crosstabBase =
    let
        baseAudienceToShow : BaseAudience
        baseAudienceToShow =
            ACrosstab.unwrapCrosstabBase crosstabBase

        {- This is checking if a base is default for the current crosstab, but the
           default base is always set at the last in the list
        -}
        isDefaultBase : Bool
        isDefaultBase =
            ACrosstab.isDefaultBase crosstabBase

        isSelected : Bool
        isSelected =
            ACrosstab.isBaseSelected crosstabBase

        isActive : Bool
        isActive =
            props.currentBaseIndex == props.index

        tabClass : ClassName
        tabClass =
            WeakCss.addMany [ "bases-panel", "tabs", "tab" ] moduleClass

        dropDownId : String
        dropDownId =
            getBaseDropdownId props.index

        isFixedPageDropdownOpen : Bool
        isFixedPageDropdownOpen =
            config.isFixedPageDropdownOpen dropDownId (config.getDropdownMenu model)

        caption : Caption.Caption
        caption =
            BaseAudience.getCaption baseAudienceToShow

        tabEllipsisIconView : Html msg
        tabEllipsisIconView =
            Html.div
                [ tabClass
                    |> WeakCss.addMany [ "ellipsis", "icon" ]
                    |> WeakCss.withStates [ ( "open", isFixedPageDropdownOpen ) ]
                ]
                [ XB2.Share.Icons.icon []
                    (if isFixedPageDropdownOpen then
                        P2Icons.ellipsisVerticalCircle

                     else
                        P2Icons.ellipsisVertical
                    )
                ]

        dropdownMenuView : Html msg
        dropdownMenuView =
            config.withDropdownMenu
                { id = dropDownId
                , orientation = DropdownMenu.BottomLeft
                , screenBottomEdgeMinOffset = 0
                , screenSideEdgeMinOffset = 0
                , content =
                    baseManagerDropdownView
                        config
                        { baseAudience = baseAudienceToShow
                        }
                        isDefaultBase
                , controlElementAttrs =
                    [ WeakCss.nest "ellipsis" tabClass
                    , Attrs.attribute "aria-label" "Base tab options dropdown"
                    , Attrs.id ("icon-ellipsis-id-" ++ dropDownId)
                    ]
                , controlElementContent = [ tabEllipsisIconView ]
                }

        baseName : String
        baseName =
            Caption.getName caption

        withTooltip : Html msg -> Html msg
        withTooltip content =
            let
                ellipsisElementSelector : String
                ellipsisElementSelector =
                    "." ++ (WeakCss.toString <| WeakCss.add "label" tabClass)

                tooltipTypeBasedOnDebugMode : XB2.Share.CoolTip.Type
                tooltipTypeBasedOnDebugMode =
                    if props.isInDebugMode then
                        XB2.Share.CoolTip.Normal

                    else
                        XB2.Share.CoolTip.NormalShownWhenEllipsis ellipsisElementSelector

                tooltipHtmlBasedOnDebugMode : Html msg
                tooltipHtmlBasedOnDebugMode =
                    if props.isInDebugMode then
                        Html.text <|
                            Caption.getName caption
                                ++ " {"
                                ++ AudienceItemId.toString
                                    (BaseAudience.getId baseAudienceToShow)
                                ++ "}"

                    else
                        Html.text <| Caption.getFullName caption
            in
            P2CoolTip.view
                { offset = Just -5
                , type_ = tooltipTypeBasedOnDebugMode
                , position = XB2.Share.CoolTip.Top
                , wrapperAttributes = [ WeakCss.nest "tooltip" tabClass ]
                , targetAttributes = []
                , targetHtml = [ content ]
                , tooltipAttributes = [ WeakCss.nest "tooltip-content" tabClass ]
                , tooltipHtml = tooltipHtmlBasedOnDebugMode
                }

        baseTabId : String
        baseTabId =
            Common.basePanelTabElementId props.index

        hasEmptyExpression : Bool
        hasEmptyExpression =
            BaseAudience.isDefault baseAudienceToShow
    in
    case
        config.crosstabBases.reorderBasesPanelDndSystem.info
            config.crosstabBases.reorderBasesPanelDndModel
    of
        Just dndInfo ->
            if dndInfo.dragIndex /= props.index then
                Html.div
                    [ tabClass
                        |> WeakCss.withStates
                            [ ( "active", isActive )
                            , ( "dropdown-open", isFixedPageDropdownOpen )
                            , ( "is-default", isDefaultBase )
                            , ( "shown-checkbox", props.anyBaseSelected )
                            , ( "selected", isSelected )
                            , ( "left-from-drag", dndInfo.dragIndex > props.index )
                            , ( "right-from-drag", dndInfo.dragIndex < props.index )
                            , ( "left-from-active"
                              , props.index
                                    == props.currentBaseIndex
                                    - 1
                              )
                            ]
                    , Attrs.id baseTabId
                    , Events.onMouseDown <| config.goToBaseAtIndex props.index
                    ]
                    [ Html.viewIf (not isDefaultBase && not hasEmptyExpression) <|
                        Html.button
                            [ WeakCss.add "checkbox" tabClass
                                |> WeakCss.withStates
                                    [ ( "show", props.anyBaseSelected )
                                    , ( "checked", isSelected )
                                    , ( "disabled"
                                      , config.crosstabBases.disabledBaseSelection model
                                      )
                                    ]
                            , Attrs.attributeIf
                                (not <|
                                    config.crosstabBases.disabledBaseSelection model
                                )
                              <|
                                Events.onClickStopPropagation <|
                                    config.toggleBase baseAudienceToShow
                            , Attrs.attribute "aria-label" "Select base tab"
                            ]
                            [ Html.i
                                [ WeakCss.nestMany [ "checkbox", "icon" ] tabClass ]
                                [ XB2.Share.Icons.icon [] <|
                                    if isSelected then
                                        P2Icons.checkboxFilled

                                    else
                                        P2Icons.checkboxUnfilled
                                ]
                            ]
                    , Html.span [ WeakCss.nest "label" tabClass ] [ Html.text baseName ]
                    , Html.span
                        (WeakCss.nest "droppable-zone" tabClass
                            :: config.crosstabBases.reorderBasesPanelDndSystem.dropEvents
                                props.index
                                baseTabId
                        )
                        []
                    , dropdownMenuView
                    ]
                    |> withTooltip

            else
                baseTabPlaceHolder dndInfo.dragElement.element.width

        Nothing ->
            Html.div
                [ tabClass
                    |> WeakCss.withStates
                        [ ( "active", isActive )
                        , ( "dropdown-open", isFixedPageDropdownOpen )
                        , ( "is-default", isDefaultBase )
                        , ( "shown-checkbox", props.anyBaseSelected )
                        , ( "selected", isSelected )
                        , ( "selected-to-move", props.selectedToMoveWithKeyboard )
                        , ( "left-from-active"
                          , props.index
                                == props.currentBaseIndex
                                - 1
                          )
                        ]
                , Attrs.id baseTabId
                , Events.onClick <| config.goToBaseAtIndex props.index
                , Attrs.tabindex 0
                , Events.onFocus <|
                    config.crosstabBases.setBaseIndexFocused
                        (Just props.index)
                , Events.onBlur <| config.crosstabBases.setBaseIndexFocused Nothing
                ]
                [ Html.viewIf (not isDefaultBase && not hasEmptyExpression) <|
                    Html.button
                        [ WeakCss.add "checkbox" tabClass
                            |> WeakCss.withStates
                                [ ( "show", props.anyBaseSelected )
                                , ( "checked", isSelected )
                                , ( "disabled"
                                  , config.crosstabBases.disabledBaseSelection model
                                  )
                                ]
                        , Attrs.attributeIf
                            (not <|
                                config.crosstabBases.disabledBaseSelection model
                            )
                          <|
                            Events.onClickStopPropagation <|
                                config.toggleBase baseAudienceToShow
                        , Attrs.attribute "aria-label" "Select base tab"
                        ]
                        [ Html.i
                            [ WeakCss.nestMany [ "checkbox", "icon" ] tabClass ]
                            [ XB2.Share.Icons.icon [] <|
                                if isSelected then
                                    P2Icons.checkboxFilled

                                else
                                    P2Icons.checkboxUnfilled
                            ]
                        ]
                , Html.span
                    (WeakCss.nest "label" tabClass
                        :: config.crosstabBases.reorderBasesPanelDndSystem.dragEvents
                            props.index
                            baseTabId
                    )
                    [ Html.text baseName ]
                , dropdownMenuView
                ]
                |> withTooltip


areBasesOverflown : Maybe Dom.Viewport -> Bool
areBasesOverflown maybeViewport =
    case maybeViewport of
        Just info ->
            -- Constant is used to prevent infinite loop of showing/hiding "add new base" text and bases dropdown
            info.scene.width > info.viewport.width + 5

        Nothing ->
            False


addBaseButton : Config model msg -> model -> Html msg
addBaseButton config model =
    Html.div
        [ WeakCss.addMany [ "bases-panel", "add-button" ] moduleClass
            |> WeakCss.withStates [ ( "simple-view", areBasesOverflown (config.basesPanelViewport model) ) ]
        ]
        [ Html.button
            [ WeakCss.addMany [ "bases-panel", "add-button", "button" ] moduleClass
                |> WeakCss.withStates [ ( "simple-view", areBasesOverflown (config.basesPanelViewport model) ) ]
            , Events.onClick config.openNewBaseView
            , Attrs.attribute "aria-label" "Add base"
            ]
            [ Html.viewIf (not <| areBasesOverflown (config.basesPanelViewport model)) <|
                Html.text "Add new base"
            , Html.div [ WeakCss.nestMany [ "bases-panel", "add-button", "icon" ] moduleClass ] [ XB2.Share.Icons.icon [] P2Icons.plusSign ]
            ]
        ]


allBasesDropdown : Config model msg -> model -> Maybe (Dropdown msg) -> Html msg
allBasesDropdown config model maybeDropdown =
    let
        bases : NonEmpty CrosstabBaseAudience
        bases =
            config.getBaseAudiences model

        currentBaseIndex : Int
        currentBaseIndex =
            config.getCurrentBaseAudienceIndex model

        isDropdownOpen : Bool
        isDropdownOpen =
            maybeDropdown == Just AllBasesDropdown

        allBasesDropdownClass : ClassName
        allBasesDropdownClass =
            WeakCss.addMany [ "bases-panel", "all-bases-drop-down" ] moduleClass
    in
    Html.viewIfLazy (areBasesOverflown (model |> config.basesPanelViewport))
        (\_ ->
            Html.div [ WeakCss.nestMany [ "bases-panel", "all-bases-drop-down-wrapper" ] moduleClass ]
                [ DropdownTrigger.buttonView
                    { onClick = config.toggleAllBasesDropdown
                    , open = isDropdownOpen
                    , openedIcon = P2Icons.caretUp
                    , closedIcon = P2Icons.caretDown
                    , activeIconClass = Nothing
                    }
                    [ DropdownTrigger.class allBasesDropdownClass
                    , DropdownTrigger.label <| Html.text "Bases"
                    ]
                , Html.viewIfLazy isDropdownOpen
                    (\_ ->
                        Html.div
                            [ WeakCss.toClass allBasesDropdownClass
                            , Attrs.cssVars
                                [ ( "--items-count"
                                  , String.fromInt <|
                                        {- We have one more due to the "Reorder bases"
                                           button
                                        -}
                                        NonemptyList.length bases
                                            + 1
                                  )
                                ]
                            ]
                            [ Html.div
                                [ WeakCss.nest "items" allBasesDropdownClass
                                ]
                                [ Html.ul []
                                    (Html.li
                                        [ WeakCss.add "item" allBasesDropdownClass
                                            |> WeakCss.withActiveStates [ "reorder-btn" ]
                                        , Attrs.title "Reorder bases"
                                        ]
                                        [ Html.button
                                            [ WeakCss.nestMany
                                                [ "item"
                                                , "btn"
                                                , "reorder-bases"
                                                ]
                                                allBasesDropdownClass
                                            , Events.onClick
                                                config.crosstabBases.openReorderBasesModal
                                            ]
                                            [ XB2.Share.Icons.icon
                                                [ XB2.Share.Icons.width 36
                                                , XB2.Share.Icons.height 36
                                                ]
                                                P2Icons.generalChange
                                            , Html.text "Reorder bases"
                                            ]
                                        ]
                                        :: List.indexedMap
                                            (\index ->
                                                ACrosstab.unwrapCrosstabBase
                                                    >> (\base ->
                                                            Html.li
                                                                [ WeakCss.add "item" allBasesDropdownClass
                                                                    |> WeakCss.withStates [ ( "active", currentBaseIndex == index ) ]
                                                                , Attrs.title <| Caption.getFullName <| BaseAudience.getCaption base
                                                                ]
                                                                [ Html.button
                                                                    [ WeakCss.nestMany [ "item", "btn" ] allBasesDropdownClass
                                                                    , Events.onClick <| config.goToBaseAtIndex index
                                                                    ]
                                                                    [ Html.text <| Caption.getName <| BaseAudience.getCaption base ]
                                                                ]
                                                       )
                                            )
                                            (NonemptyList.toList bases)
                                    )
                                ]
                            ]
                    )
                ]
        )


viewOptionsDropdownView :
    Config model msg
    -> Can
    -> model
    ->
        { isDropdownOpen : Bool
        , isHeaderCollapsed : Bool
        , userSettings : WebData XBUserSettings
        }
    -> Html msg
viewOptionsDropdownView config can model { isDropdownOpen, isHeaderCollapsed, userSettings } =
    let
        dropdownClass : ClassName
        dropdownClass =
            WeakCss.add "view-options-dropdown" moduleClass

        dropdownMenuClass : ClassName
        dropdownMenuClass =
            WeakCss.add "menu" dropdownClass

        crosstab : AudienceCrosstab
        crosstab =
            config.getCrosstab model

        metricsTransposition : MetricsTransposition
        metricsTransposition =
            config.getMetricsTransposition model

        usedCellsCount : Int
        usedCellsCount =
            if ACrosstab.isEmpty crosstab then
                0

            else
                ACrosstab.getSizeWithTotals crosstab
                    * ACrosstab.getBaseAudiencesCount
                        crosstab

        formatCount : Int -> String
        formatCount =
            let
                usLocale : Locales.Locale
                usLocale =
                    Locales.usLocale
            in
            toFloat
                >> FormatNumber.format
                    { usLocale
                        | decimals = Locales.Exact 0
                    }

        ( rowsFrozen, colsFrozen ) =
            config.getFrozenRowsColumns model

        nCrosstabRows : Int
        nCrosstabRows =
            List.length (ACrosstab.getRows crosstab)

        nCrosstabCols : Int
        nCrosstabCols =
            List.length (ACrosstab.getColumns crosstab)
    in
    Html.div
        [ WeakCss.toClass dropdownClass ]
        [ P2CoolTip.viewIf isHeaderCollapsed
            { targetHtml =
                DropdownTrigger.buttonView
                    { onClick = config.toggleViewOptionsDropdown
                    , open = isDropdownOpen
                    , openedIcon = P2Icons.caretUp
                    , closedIcon = P2Icons.caretDown
                    , activeIconClass = Nothing
                    }
                    [ DropdownTrigger.class dropdownClass
                    , if isHeaderCollapsed then
                        DropdownTrigger.label <| XB2.Share.Icons.icon [] P2Icons.eye

                      else
                        DropdownTrigger.label <| Html.text "View options"
                    , DropdownTrigger.disabled (ACrosstab.isEmpty crosstab)
                    ]
            , type_ = XB2.Share.CoolTip.Normal
            , position = XB2.Share.CoolTip.Bottom
            , wrapperAttributes = []
            , tooltipText = "View options"
            }
        , freezingRowsAndColumnsOnboardingView config.updateUserSettings
            userSettings
        , Html.viewIfLazy isDropdownOpen
            (\_ ->
                Html.div
                    [ dropdownMenuClass |> WeakCss.withActiveStates [ "expand-left" ] ]
                    [ Html.viewIf (can XB2.Share.Permissions.UseDebugButtons) <|
                        DropdownItem.view
                            [ DropdownItem.class dropdownMenuClass
                            , DropdownItem.onClick config.downloadDebugDump
                            , DropdownItem.label "Download Debug Dump"
                            , DropdownItem.leftIcon P2Icons.exclamationTriangle
                            ]
                    , Html.viewIf (can XB2.Share.Permissions.UseDebugButtons) <|
                        Html.div [ WeakCss.nest "separator" dropdownClass ] []
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick (config.transposeMetrics MetricsInRows)
                        , DropdownItem.label "Row metrics"
                        , DropdownItem.leftIcon P2Icons.verticalBarChart
                        , DropdownItem.selected (MetricsInRows == metricsTransposition)
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick (config.transposeMetrics MetricsInColumns)
                        , DropdownItem.label "Column metrics"
                        , DropdownItem.leftIcon P2Icons.verticalBarChart
                        , DropdownItem.selected (MetricsInColumns == metricsTransposition)
                        ]
                    , Html.div [ WeakCss.nest "separator" dropdownClass ] []
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick config.openHeatmapSelection
                        , DropdownItem.label "Apply heatmap"
                        , DropdownItem.leftIcon P2Icons.heatmap
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick config.openMinimumSampleSizeModal
                        , DropdownItem.label "Minimum sample size"
                        , DropdownItem.leftIcon P2Icons.eyeCrossed
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick config.switchCrosstab
                        , DropdownItem.label "Swap rows & columns"
                        , DropdownItem.leftIcon P2Icons.random
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Freeze"
                        , DropdownItem.leftIcon P2Icons.freeze
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.children
                            [ [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 0, colsFrozen )
                                    )
                              , DropdownItem.label "No rows"
                              , DropdownItem.selected
                                    (rowsFrozen < 1)
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 1, colsFrozen )
                                    )
                              , DropdownItem.label "First 1 row"
                              , DropdownItem.disabled (nCrosstabRows < 1)
                              , DropdownItem.selected
                                    (rowsFrozen == 1)
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( 2, colsFrozen )
                                    )
                              , DropdownItem.label "First 2 rows"
                              , DropdownItem.disabled (nCrosstabRows < 2)
                              , DropdownItem.selected
                                    (rowsFrozen == 2)
                              , DropdownItem.withSeparator True
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 0 )
                                    )
                              , DropdownItem.label "No columns"
                              , DropdownItem.selected
                                    (colsFrozen < 1)
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 1 )
                                    )
                              , DropdownItem.label "First 1 column"
                              , DropdownItem.disabled (nCrosstabCols < 1)
                              , DropdownItem.selected
                                    (colsFrozen == 1)
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.setFrozenRowsColumns
                                        ( rowsFrozen, 2 )
                                    )
                              , DropdownItem.label "First 2 columns"
                              , DropdownItem.disabled (nCrosstabCols < 2)
                              , DropdownItem.selected
                                    (colsFrozen == 2)
                              ]
                            ]
                        ]
                    , Html.div [ WeakCss.nest "separator" dropdownClass ] []
                    , Html.div
                        [ dropdownClass |> WeakCss.nest "footer" ]
                        [ Html.text "You have used "
                        , Html.span
                            [ dropdownClass
                                |> WeakCss.nestMany [ "footer", "highlight" ]
                            ]
                            [ Html.text <|
                                String.concat
                                    [ formatCount usedCellsCount
                                    , " of "
                                    , formatCount (ACrosstab.crosstabSizeLimit can)
                                    ]
                            ]
                        , Html.text " available cells within your current project"
                        ]
                    ]
            )
        ]


sortByNameDropdownView :
    Config model msg
    -> model
    ->
        { isDropdownOpen : Bool
        , isHeaderCollapsed : Bool
        }
    -> Html msg
sortByNameDropdownView config model { isDropdownOpen, isHeaderCollapsed } =
    let
        dropdownClass : ClassName
        dropdownClass =
            WeakCss.add "sort-by-name-dropdown" moduleClass

        dropdownMenuClass : ClassName
        dropdownMenuClass =
            WeakCss.add "menu" dropdownClass

        crosstab : AudienceCrosstab
        crosstab =
            config.getCrosstab model

        sort : Sort
        sort =
            config.getCurrentSort model

        isSortingByThisDirection : SortDirection -> AxisSort -> Bool
        isSortingByThisDirection sortDirection axisSort =
            axisSort == ByName sortDirection

        sortDirectionToString : SortDirection -> String
        sortDirectionToString direction =
            case direction of
                Ascending ->
                    "A-Z"

                Descending ->
                    "Z-A"

        stateIcon : SortDirection -> IconData
        stateIcon sortDirection =
            case sortDirection of
                Ascending ->
                    P2Icons.sortAscending

                Descending ->
                    P2Icons.sortDescending

        stateIconAndStateLabel : Maybe ( Maybe IconData, String )
        stateIconAndStateLabel =
            case ( sort.rows, sort.columns, config.isHeaderCollapsed model ) of
                ( ByName rowsSortDirection, ByName columnsSortDirection, False ) ->
                    if rowsSortDirection == columnsSortDirection then
                        Just
                            ( Just <| stateIcon rowsSortDirection
                            , sortDirectionToString rowsSortDirection
                                ++ " rows / "
                                ++ sortDirectionToString columnsSortDirection
                                ++ " columns"
                            )

                    else
                        Just
                            ( Just P2Icons.sort
                            , sortDirectionToString rowsSortDirection
                                ++ " rows / "
                                ++ sortDirectionToString columnsSortDirection
                                ++ " columns"
                            )

                ( ByName rowsSortDirection, ByName columnsSortDirection, True ) ->
                    if rowsSortDirection == columnsSortDirection then
                        Just
                            ( Just <| stateIcon rowsSortDirection
                            , sortDirectionToString rowsSortDirection
                                ++ " / "
                                ++ sortDirectionToString columnsSortDirection
                            )

                    else
                        Just
                            ( Just P2Icons.sort
                            , sortDirectionToString rowsSortDirection
                                ++ " / "
                                ++ sortDirectionToString columnsSortDirection
                            )

                ( ByName rowsSortDirection, _, False ) ->
                    Just
                        ( Just <| stateIcon rowsSortDirection
                        , sortDirectionToString rowsSortDirection ++ " rows"
                        )

                ( ByName rowsSortDirection, _, True ) ->
                    Just
                        ( Just <| stateIcon rowsSortDirection
                        , sortDirectionToString rowsSortDirection
                        )

                ( _, ByName columnsSortDirection, False ) ->
                    Just
                        ( Just <| stateIcon columnsSortDirection
                        , sortDirectionToString columnsSortDirection ++ " columns"
                        )

                ( _, ByName columnsSortDirection, True ) ->
                    Just
                        ( Just <| stateIcon columnsSortDirection
                        , sortDirectionToString columnsSortDirection
                        )

                ( ByOtherAxisMetric _ _ _, _, _ ) ->
                    Nothing

                ( ByTotalsMetric _ _, _, _ ) ->
                    Nothing

                ( ByOtherAxisAverage _ _, _, _ ) ->
                    Nothing

                ( NoSort, _, _ ) ->
                    Nothing
    in
    Html.div
        [ WeakCss.toClass dropdownClass ]
        [ P2CoolTip.viewIf isHeaderCollapsed
            { targetHtml =
                DropdownTrigger.buttonView
                    { onClick = config.toggleSortByNameDropdown
                    , open = isDropdownOpen
                    , openedIcon = P2Icons.caretUp
                    , closedIcon = P2Icons.caretDown
                    , activeIconClass = Nothing
                    }
                    [ DropdownTrigger.class dropdownClass
                    , if isHeaderCollapsed then
                        DropdownTrigger.label <|
                            case ( sort.rows, sort.columns ) of
                                ( NoSort, NoSort ) ->
                                    XB2.Share.Icons.icon [] P2Icons.sort

                                ( ByOtherAxisMetric _ _ _, _ ) ->
                                    Html.nothing

                                ( ByTotalsMetric _ _, _ ) ->
                                    Html.nothing

                                ( ByOtherAxisAverage _ _, _ ) ->
                                    Html.nothing

                                ( ByName _, _ ) ->
                                    Html.nothing

                                ( NoSort, _ ) ->
                                    Html.nothing

                      else
                        DropdownTrigger.label <| Html.text "Sort by"
                    , DropdownTrigger.leftIcon
                        (Maybe.andThen Tuple.first
                            stateIconAndStateLabel
                        )
                    , DropdownTrigger.sublabel
                        (Maybe.map Tuple.second
                            stateIconAndStateLabel
                        )
                    , DropdownTrigger.disabled (ACrosstab.isEmpty crosstab)
                    ]
            , type_ = XB2.Share.CoolTip.Normal
            , position = XB2.Share.CoolTip.Bottom
            , wrapperAttributes = []
            , tooltipText = "Sort by"
            }
        , Html.viewIfLazy isDropdownOpen
            (\_ ->
                Html.div
                    [ dropdownMenuClass |> WeakCss.withActiveStates [ "expand-left" ] ]
                    [ DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "A-Z – Alphabetical"
                        , DropdownItem.leftIcon P2Icons.sortAscending
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.selected
                            (isSortingByThisDirection Ascending
                                sort.rows
                                || isSortingByThisDirection Ascending sort.columns
                            )
                        , DropdownItem.children
                            [ [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick (config.sortByName Rows Ascending)
                              , DropdownItem.label (Sort.axisToString Rows)
                              , DropdownItem.leftIcon P2Icons.rows
                              , DropdownItem.selected
                                    (isSortingByThisDirection
                                        Ascending
                                        sort.rows
                                    )
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick (config.sortByName Columns Ascending)
                              , DropdownItem.label (Sort.axisToString Columns)
                              , DropdownItem.leftIcon P2Icons.columns
                              , DropdownItem.selected
                                    (isSortingByThisDirection
                                        Ascending
                                        sort.columns
                                    )
                              ]
                            ]
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Z-A – Alphabetical"
                        , DropdownItem.leftIcon P2Icons.sortDescending
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.selected
                            (isSortingByThisDirection Descending
                                sort.rows
                                || isSortingByThisDirection Descending sort.columns
                            )
                        , DropdownItem.children
                            [ [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick (config.sortByName Rows Descending)
                              , DropdownItem.label (Sort.axisToString Rows)
                              , DropdownItem.leftIcon P2Icons.rows
                              , DropdownItem.selected
                                    (isSortingByThisDirection
                                        Descending
                                        sort.rows
                                    )
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick
                                    (config.sortByName Columns
                                        Descending
                                    )
                              , DropdownItem.label (Sort.axisToString Columns)
                              , DropdownItem.leftIcon P2Icons.columns
                              , DropdownItem.selected
                                    (isSortingByThisDirection
                                        Descending
                                        sort.columns
                                    )
                              ]
                            ]
                        ]
                    , Html.div [ WeakCss.nest "separator" dropdownClass ] []
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick config.resetSortByName
                        , DropdownItem.label "Reset"
                        , DropdownItem.leftIcon P2Icons.sync
                        , DropdownItem.disabled
                            (not
                                (Sort.isSortingByName sort.rows
                                    || Sort.isSortingByName sort.columns
                                )
                            )
                        ]
                    ]
            )
        ]


viewCrosstabSearchBar : Config model msg -> model -> Html msg
viewCrosstabSearchBar config model =
    let
        searchProps =
            config.getCrosstabSearchProps model

        panelShouldBeInvisible =
            not searchProps.inputIsFocused
                && String.isEmpty searchProps.term

        previousIsEnabled =
            Maybe.unwrap False Zipper.hasPrev searchProps.searchTopLeftScrollJumps

        nextIsEnabled =
            Maybe.unwrap False Zipper.hasNext searchProps.searchTopLeftScrollJumps

        clearIsEnabled =
            not <| String.isEmpty searchProps.term
    in
    Html.div
        [ WeakCss.nestMany [ "bases-panel", "search-bar" ]
            moduleClass
        ]
        [ Html.input
            [ Attrs.type_ "text"
            , Attrs.attributeIf (not searchProps.inputIsFocused) (Attrs.placeholder "Find…")
            , Events.onInput config.searchTermChanged
            , Attrs.value searchProps.term
            , Attrs.id Common.crosstabSearchId
            , autocomplete False
            , Events.onBlur (config.setInputFocus False)
            , Events.onFocus (config.setInputFocus True)
            , WeakCss.nestMany [ "bases-panel", "search-bar", "input" ]
                moduleClass
            ]
            []
        , Html.div
            [ WeakCss.addMany [ "bases-panel", "search-bar", "panel" ]
                moduleClass
                |> WeakCss.withStates
                    [ ( "invisible", panelShouldBeInvisible )
                    ]
            ]
            [ Html.span
                [ WeakCss.nestMany [ "bases-panel", "search-bar", "results" ]
                    moduleClass
                ]
                [ let
                    focusedIndexAndLength =
                        let
                            zipperLength =
                                Maybe.unwrap 0 Zipper.length searchProps.searchTopLeftScrollJumps

                            currentFocusedIndex =
                                Maybe.map
                                    (\zipper ->
                                        List.length (Zipper.listPrev zipper) + 1
                                    )
                                    searchProps.searchTopLeftScrollJumps
                                    |> Maybe.withDefault 0
                        in
                        case searchProps.searchTopLeftScrollJumps of
                            Nothing ->
                                "0/0"

                            Just _ ->
                                String.fromInt currentFocusedIndex ++ "/" ++ String.fromInt zipperLength
                  in
                  Html.text focusedIndexAndLength
                ]
            , Html.span
                [ WeakCss.nestMany [ "bases-panel", "search-bar", "separator" ]
                    moduleClass
                ]
                []
            , Html.button
                [ Events.onClick config.goToPreviousSearchResult
                , WeakCss.nestMany [ "bases-panel", "search-bar", "previous" ]
                    moduleClass
                , Attrs.disabled (not previousIsEnabled)
                ]
                [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 16 ] P2Icons.searchCaretUp ]
            , Html.button
                [ Events.onClick config.goToNextSearchResult
                , WeakCss.nestMany [ "bases-panel", "search-bar", "next" ]
                    moduleClass
                , Attrs.disabled (not nextIsEnabled)
                ]
                [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 16 ] P2Icons.searchCaretDown ]
            , Html.button
                [ Events.onClick (config.searchTermChanged "")
                , WeakCss.nestMany [ "bases-panel", "search-bar", "clear" ]
                    moduleClass
                , Attrs.disabled (not clearIsEnabled)
                ]
                [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 16 ] P2Icons.searchCross ]
            ]
        ]


basesPanelView : Config model msg -> Can -> model -> XBStore.Store -> Maybe (Dropdown msg) -> Html msg
basesPanelView config can model { userSettings } activeDropdown =
    let
        currentBaseIndex : Int
        currentBaseIndex =
            config.getCurrentBaseAudienceIndex model

        bases : NonEmpty CrosstabBaseAudience
        bases =
            config.getBaseAudiences model

        anyBaseSelected : Bool
        anyBaseSelected =
            config.crosstabBases.anySelected model

        metricsCount : Int
        metricsCount =
            List.length <| config.metrics model

        anySortingSelected : Bool
        anySortingSelected =
            Sort.isAnyAxisSorting <| config.getCurrentSort model

        isHeaderCollapsed : Bool
        isHeaderCollapsed =
            config.isHeaderCollapsed model

        someBaseIsBeingDragged : Bool
        someBaseIsBeingDragged =
            config.crosstabBases.reorderBasesPanelDndSystem.info
                config.crosstabBases.reorderBasesPanelDndModel
                |> Maybe.isJust

        ariaMessage : String
        ariaMessage =
            String.fromInt (NonemptyList.length bases)
                ++ ", To reorder base, Use enter or space bar to select and left and"
                ++ " right arrows to move"

        basesPanelDropdownsView : List (Html msg)
        basesPanelDropdownsView =
            if isHeaderCollapsed then
                let
                    exportButton : Html msg
                    exportButton =
                        let
                            isDisabled : Bool
                            isDisabled =
                                not <|
                                    config.export.canProcess model
                                        || config.export.isExporting model
                        in
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.Bottom
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ WeakCss.addMany [ "control-panel", "export-btn" ] moduleClass
                                        |> WeakCss.withStates [ ( "disabled", isDisabled ) ]
                                    , Attrs.disabled isDisabled
                                    , Events.onClick config.export.start
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.export ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml =
                                if config.export.canProcess model then
                                    Html.text "Export"

                                else
                                    Html.text
                                        "Add Attributes or Audiences to your Crosstab to export it."
                            }

                    collapsorButton : Html msg
                    collapsorButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.BottomLeft
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ WeakCss.nestMany [ "btn", "collapsor" ] moduleClass
                                    , Events.onClick config.toggleHeaderCollapsed
                                    , Attrs.attribute "aria-label" "Toggle collapsed header"
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 16 ]
                                        P2Icons.chevronDown
                                    ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml =
                                Html.text "Expand header"
                            }

                    undoButton : Html msg
                    undoButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.Bottom
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ WeakCss.addMany [ "control-panel", "btn", "undo" ] moduleClass
                                        |> WeakCss.withStates
                                            [ ( "disabled"
                                              , config.timeTravel.undoDisabled model
                                              )
                                            ]
                                    , Events.onClick config.timeTravel.undoMsg
                                    , Attrs.disabled <| config.timeTravel.undoDisabled model
                                    , Attrs.attribute "aria-label" "Undo"
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.undo ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml = Html.text "Undo (CTRL / ⌘ Z)"
                            }

                    redoButton : Html msg
                    redoButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.BottomLeft
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ WeakCss.addMany [ "control-panel", "btn", "redo" ] moduleClass
                                        |> WeakCss.withStates
                                            [ ( "disabled"
                                              , config.timeTravel.redoDisabled model
                                              )
                                            ]
                                    , Events.onClick config.timeTravel.redoMsg
                                    , Attrs.disabled <| config.timeTravel.redoDisabled model
                                    , Attrs.attribute "aria-label" "Redo"
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.redo ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml = Html.text "Redo (CTRL Y / Shift ⌘ Z)"
                            }

                    shareButton : Html msg
                    shareButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.Bottom
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ Events.onClick config.sharing.shareMsg
                                    , WeakCss.nestMany
                                        [ "control-panel"
                                        , "share-buttons"
                                        , "share"
                                        ]
                                        moduleClass
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.share
                                    ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml = Html.text "Share"
                            }

                    shareLinkButton : Html msg
                    shareLinkButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.Bottom
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.button
                                    [ Events.onClick config.sharing.shareAndCopyLinkMsg
                                    , WeakCss.nestMany
                                        [ "control-panel"
                                        , "share-buttons"
                                        , "share-link"
                                        ]
                                        moduleClass
                                    ]
                                    [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.link
                                    ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml = Html.text "Copy link"
                            }

                    saveAsNewButton : Html msg
                    saveAsNewButton =
                        P2CoolTip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = XB2.Share.CoolTip.Bottom
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml =
                                [ Html.viewIf config.sharing.isMine <|
                                    Html.button
                                        [ Events.onClick <| config.saving.saveAsNew model
                                        , WeakCss.nestMany [ "control-panel", "btn", "save-as-new" ]
                                            moduleClass
                                        ]
                                        [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.saveAsNew ]
                                ]
                            , tooltipAttributes = []
                            , tooltipHtml =
                                Html.text "Save as new"
                            }
                in
                [ viewCrosstabSearchBar config model
                , P2CoolTip.viewIf isHeaderCollapsed
                    { targetHtml =
                        Html.button
                            [ Events.onClick config.openMetricsSelection
                            , WeakCss.nestMany [ "bases-panel", "metrics-btn" ]
                                moduleClass
                            , Attrs.disabled <|
                                ACrosstab.isEmpty <|
                                    config.getCrosstab model
                            ]
                            [ XB2.Share.Icons.icon [] P2Icons.dataMetrics
                            , Bubble.view
                                (WeakCss.addMany
                                    [ "bases-panel"
                                    , "metrics-btn"
                                    , "badge"
                                    ]
                                    moduleClass
                                )
                                (String.fromInt metricsCount)
                            ]
                    , type_ = XB2.Share.CoolTip.Normal
                    , position = XB2.Share.CoolTip.Bottom
                    , wrapperAttributes = []
                    , tooltipText = "Metrics"
                    }
                , viewOptionsDropdownView config
                    can
                    model
                    { isDropdownOpen = activeDropdown == Just ViewOptionsDropdown
                    , isHeaderCollapsed = isHeaderCollapsed
                    , userSettings = userSettings
                    }
                , sortByNameDropdownView config
                    model
                    { isDropdownOpen = activeDropdown == Just SortByNameDropdown
                    , isHeaderCollapsed = isHeaderCollapsed
                    }
                , Html.span [ WeakCss.nest "separator" moduleClass ] []
                , Html.div
                    [ WeakCss.nest "control-panel" moduleClass ]
                    [ Html.button
                        [ WeakCss.nestMany [ "control-panel", "btn-primary", "save" ] moduleClass
                        , Events.onClick <| config.saving.save model
                        , Attrs.disabled <| not <| config.saving.isSaveBtnEnabled model
                        ]
                        [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.changes
                        , Html.text
                            (if config.saving.isSharedWithMe then
                                "Save as copy"

                             else
                                "Save"
                            )
                        ]
                    , saveAsNewButton
                    , Html.viewIf
                        (config.sharing.isMine
                            || config.sharing.isSharedByLink
                        )
                      <|
                        Html.div
                            [ WeakCss.nestMany
                                [ "control-panel"
                                , "share-buttons"
                                ]
                                moduleClass
                            ]
                            [ shareButton
                            , Html.div
                                [ WeakCss.nestMany
                                    [ "control-panel"
                                    , "share-buttons"
                                    , "separator"
                                    ]
                                    moduleClass
                                ]
                                []
                            , shareLinkButton
                            ]
                    , exportButton
                    , undoButton
                    , redoButton
                    ]
                , Html.span [ WeakCss.nest "separator" moduleClass ] []
                , collapsorButton
                ]

            else
                [ viewCrosstabSearchBar config model
                , Html.button
                    [ Events.onClick config.openMetricsSelection
                    , WeakCss.nestMany [ "bases-panel", "metrics-btn" ] moduleClass
                    , Attrs.disabled <| ACrosstab.isEmpty <| config.getCrosstab model
                    ]
                    [ Html.text "Metrics"
                    , Bubble.view
                        (WeakCss.addMany [ "bases-panel", "metrics-btn", "badge" ]
                            moduleClass
                        )
                        (String.fromInt metricsCount)
                    ]
                , viewOptionsDropdownView config
                    can
                    model
                    { isDropdownOpen = activeDropdown == Just ViewOptionsDropdown
                    , isHeaderCollapsed = isHeaderCollapsed
                    , userSettings = userSettings
                    }
                , sortByNameDropdownView config
                    model
                    { isDropdownOpen = activeDropdown == Just SortByNameDropdown
                    , isHeaderCollapsed = isHeaderCollapsed
                    }
                ]
    in
    Html.div
        [ WeakCss.add "bases-panel" moduleClass
            |> WeakCss.withStates
                [ ( "active-sorting", anySortingSelected ) ]
        ]
        [ Html.div [ WeakCss.nestMany [ "bases-panel", "left-container" ] moduleClass ]
            [ addBaseButton config model
            , allBasesDropdown config model activeDropdown
            ]
        , Html.div
            [ WeakCss.addMany [ "bases-panel", "tabs" ] moduleClass
                |> WeakCss.withStates [ ( "some-base-dragged", someBaseIsBeingDragged ) ]
            , Attrs.attribute "aria-live" "polite"
            , Attrs.attribute "aria-label" ariaMessage
            ]
            [ Html.div
                [ WeakCss.nestMany [ "bases-panel", "tabs", "bases" ] moduleClass
                , Attrs.id Common.basesPanelId
                ]
                [ XB2.Share.ResizeObserver.view
                    { targetSelector = "#" ++ Common.basesPanelScrollableId
                    , toMsg = \_ -> config.tabsPanelResized
                    }
                    []
                    [ Html.div
                        [ WeakCss.nestMany [ "bases-panel", "tabs", "scrollable" ]
                            moduleClass
                        , Attrs.id Common.basesPanelScrollableId
                        , Events.on "scroll" <| Decode.succeed config.tabsPanelResized
                        ]
                      <|
                        showChevron
                            (shouldBeChevronVisible ChevronLeft
                                (model
                                    |> config.basesPanelViewport
                                )
                            )
                            ChevronLeft
                            config.scrollBasesPanelLeft
                            :: List.indexedMap
                                (\index base ->
                                    baseTabView
                                        config
                                        { currentBaseIndex = currentBaseIndex
                                        , index = index
                                        , anyBaseSelected = anyBaseSelected
                                        , updateUserSettingsToMsg =
                                            config.updateUserSettings
                                        , userSettings = userSettings
                                        , selectedToMoveWithKeyboard =
                                            config.crosstabBases.baseSelectedToMoveWithKeyboard
                                                == Just index
                                        , isInDebugMode =
                                            RemoteData.unwrap False
                                                .showDetailTableInDebugMode
                                                userSettings
                                        }
                                        model
                                        base
                                )
                                (NonemptyList.toList bases)
                            ++ [ basesPanelGhostView config
                                    { currentActiveBaseIndex = currentBaseIndex }
                                    model
                                    (NonemptyList.toList bases)
                               , showChevron
                                    (shouldBeChevronVisible ChevronRight
                                        (model
                                            |> config.basesPanelViewport
                                        )
                                    )
                                    ChevronRight
                                    config.scrollBasesPanelRight
                               ]
                    ]
                ]
            ]
        , Html.div
            [ WeakCss.addMany [ "bases-panel", "dropdowns" ] moduleClass
                |> WeakCss.withStates
                    [ ( "collapsed"
                      , isHeaderCollapsed
                      )
                    ]
            ]
            basesPanelDropdownsView
        ]


type ChevronType
    = ChevronLeft
    | ChevronRight


shouldBeChevronVisible : ChevronType -> Maybe Dom.Viewport -> Bool
shouldBeChevronVisible chevronType maybeViewport =
    let
        isAtTheEnd : Dom.Viewport -> Bool
        isAtTheEnd info =
            case chevronType of
                ChevronRight ->
                    info.viewport.x + info.viewport.width >= info.scene.width

                ChevronLeft ->
                    info.viewport.x <= 0
    in
    case maybeViewport of
        Just viewport ->
            not <| isAtTheEnd viewport

        Nothing ->
            False


showChevron : Bool -> ChevronType -> msg -> Html msg
showChevron display chevronType basesPanelScrolled =
    let
        ( chevron, chevronSpecificStyle ) =
            if chevronType == ChevronLeft then
                ( P2Icons.chevronLeft, WeakCss.nestMany [ "bases-panel", "tabs", "scrollable", "chevron", "left" ] moduleClass )

            else
                ( P2Icons.chevronRight, WeakCss.nestMany [ "bases-panel", "tabs", "scrollable", "chevron", "right" ] moduleClass )
    in
    Html.viewIf display <|
        Html.button
            [ Events.onClick basesPanelScrolled
            , chevronSpecificStyle
            , WeakCss.nestMany [ "bases-panel", "tabs", "scrollable", "chevron" ] moduleClass
            ]
            [ XB2.Share.Icons.icon [ XB2.Share.Icons.height 32 ] chevron
            ]


view :
    { config : Config model msg, can : Can }
    ->
        { showLoadingOnly : Bool
        , activeDropdown : Maybe (Dropdown msg)
        , xbStore : XBStore.Store
        , store : XB2.Share.Store.Platform2.Store
        , model : model
        }
    -> List (Html msg)
view triggers params =
    [ toolsPanelView triggers.config
        triggers.can
        params.xbStore
        params.store
        params.model
    , basesPanelView triggers.config
        triggers.can
        params.model
        params.xbStore
        params.activeDropdown
    , gridView
        { config = triggers.config, can = triggers.can }
        { showOverlay = triggers.config.crosstabBases.anySelected params.model
        , forcedLoadingState = params.showLoadingOnly
        , store = params.store
        , xbStore = params.xbStore
        , model = params.model
        }
    , selectionPanelView triggers.config params.store params.model
    , crosstabBasesView triggers.config params.store params.model
    ]


tableModuleClass : ClassName
tableModuleClass =
    WeakCss.namespace "xb2-table"



-- TYPES


type alias DnDSystem msg =
    XB2.Share.DragAndDrop.Move.System msg Direction MovableItems


type alias DnDModel =
    XB2.Share.DragAndDrop.Move.Model Direction MovableItems


type alias DnDListModel =
    XB2.Share.DragAndDrop.Move.ListModel Direction MovableItems


type alias HeaderClass =
    String



-- HELPERS


getHeaderClass : Direction -> HeaderClass
getHeaderClass direction =
    case direction of
        Row ->
            "rows"

        Column ->
            "cols"


heatmapColorAttrs : Maybe HeatmapScale -> Key -> Key -> ACrosstab.Cell -> List (Attribute msg)
heatmapColorAttrs heatmapScale column row cell =
    case ( heatmapScale, cell.data ) of
        ( Just scale, AvAData data ) ->
            case Heatmap.getColor scale { col = column.item, row = row.item } data.data of
                Just color ->
                    [ Attrs.style "background-color" color ]

                Nothing ->
                    []

        ( Nothing, _ ) ->
            []

        ( _, AverageData _ ) ->
            []


checkIfCellPassesMinSampleSize : MinimumSampleSize -> ACrosstab.Cell -> Bool
checkIfCellPassesMinSampleSize minimumSampleSize cell =
    case Optional.toMaybe minimumSampleSize.cells of
        Just minCellsSampleSize ->
            case cell.data of
                AvAData data ->
                    case data.data of
                        Tracked.Success intersectResult ->
                            let
                                thisCellSampleSize =
                                    AudienceIntersect.getValue Sample intersectResult
                            in
                            round thisCellSampleSize < minCellsSampleSize

                        Tracked.NotAsked ->
                            False

                        Tracked.Loading _ ->
                            False

                        Tracked.Failure _ ->
                            False

                AverageData _ ->
                    False

        Nothing ->
            False


msgOnClickSelectRowOrColumn : Key -> Direction -> Config model msg -> Analytics.ItemSelected -> Events.ShiftState -> msg
msgOnClickSelectRowOrColumn key direction config itemSelected shiftState =
    case ( key.isSelected, direction ) of
        ( True, Row ) ->
            config.deselectRow key

        ( True, Column ) ->
            config.deselectColumn key

        ( False, Row ) ->
            config.selectRow shiftState itemSelected key

        ( False, Column ) ->
            config.selectColumn shiftState itemSelected key



-- Header views


selectCheckboxView : Config model msg -> Direction -> Key -> Html msg
selectCheckboxView config direction key =
    let
        headerClass : String
        headerClass =
            getHeaderClass direction
    in
    Html.label
        [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "select" ] ]
        [ Html.input
            [ Attrs.type_ "checkbox"
            , Attrs.checked key.isSelected
            , tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "select", "input" ]
            , Events.onClickStopPropagationWithShiftCheck (msgOnClickSelectRowOrColumn key direction config Analytics.TickBox)
            , Attrs.attribute "aria-label" "Select header"
            ]
            []
        , Html.div
            [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "select", "indicator" ] ]
            [ Html.i
                [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "select", "indicator", "icon" ] ]
                [ XB2.Share.Icons.icon [] <|
                    if key.isSelected then
                        P2Icons.checkboxFilled

                    else
                        P2Icons.checkboxUnfilled
                ]
            ]
        ]


{-| A view containing the onboarding modal for the Renaming cells feature.
-}
renamingCellsOnboardingView :
    (XBUserSettings -> msg)
    -> WebData XBUserSettings
    -> Html msg
renamingCellsOnboardingView updateUserSettingsMsg userSettings =
    let
        showOnboarding : Bool
        showOnboarding =
            case userSettings of
                RemoteData.Success { renamingCellsOnboardingSeen } ->
                    not renamingCellsOnboardingSeen

                RemoteData.NotAsked ->
                    False

                RemoteData.Loading ->
                    False

                RemoteData.Failure _ ->
                    False
    in
    Html.viewIfLazy showOnboarding <|
        \() ->
            Html.viewMaybe
                (\closeMsg ->
                    Html.div
                        [ WeakCss.nestMany
                            [ "table"
                            , "renaming-cells"
                            , "onboarding"
                            ]
                            tableModuleClass
                        ]
                        [ Html.h3
                            [ WeakCss.nestMany
                                [ "table"
                                , "renaming-cells"
                                , "onboarding"
                                , "title"
                                ]
                                tableModuleClass
                            ]
                            [ Html.text "Easily Rename Cells in Crosstabs! 🌟" ]
                        , Html.p
                            [ WeakCss.nestMany
                                [ "table"
                                , "renaming-cells"
                                , "onboarding"
                                , "tip"
                                ]
                                tableModuleClass
                            ]
                            [ Html.text
                                """You can now personalize cell names in your crosstabs 
                                effortlessly! Simply hover over a cell, click, and give 
                                it a name that makes sense to you. It's that simple! Try 
                                it out now and level up your data game!"""
                            ]
                        , Html.button
                            [ WeakCss.nestMany
                                [ "table"
                                , "renaming-cells"
                                , "onboarding"
                                , "got-it"
                                ]
                                tableModuleClass
                            , Events.onClick closeMsg
                            ]
                            [ Html.text "Got it" ]
                        ]
                )
                (userSettings
                    |> RemoteData.toMaybe
                    |> Maybe.map
                        (\settings ->
                            updateUserSettingsMsg
                                { settings
                                    | renamingCellsOnboardingSeen = True
                                }
                        )
                )


{-| View for the item title/subtitle inside the header rows and columns.
-}
captionView :
    { config : Config model msg }
    ->
        { headerClass : HeaderClass
        , direction : Direction
        , key : Key
        , isInDebugMode : Bool
        }
    -> Html msg
captionView triggers params =
    let
        audienceData : AudienceData
        audienceData =
            AudienceItem.toAudienceData params.key.item

        audienceHasSubtitle : Bool
        audienceHasSubtitle =
            audienceData.subtitle /= ""

        tooltipDirection : XB2.Share.CoolTip.Position
        tooltipDirection =
            if params.direction == Column then
                XB2.Share.CoolTip.Bottom

            else
                XB2.Share.CoolTip.TopRight

        isTotalCell : Bool
        isTotalCell =
            AudienceItem.getId params.key.item == AudienceItemId.total

        tooltipHtml : Html msg
        tooltipHtml =
            if params.isInDebugMode then
                Html.text audienceData.id

            else
                Html.text <|
                    audienceData.fullName
                        ++ "\n"
                        ++ audienceData.subtitle
    in
    P2CoolTip.view
        { offset = Nothing
        , type_ = XB2.Share.CoolTip.Global
        , position = tooltipDirection
        , wrapperAttributes =
            [ tableModuleClass
                |> WeakCss.nestMany [ "table", params.headerClass, "item", "tooltip" ]
            ]
        , targetAttributes = []
        , targetHtml =
            [ Html.span
                [ tableModuleClass
                    |> WeakCss.nestMany [ "table", params.headerClass, "item", "caption" ]
                , if isTotalCell then
                    Events.onClickPreventDefaultAndStopPropagation triggers.config.noOp

                  else
                    Events.onClickPreventDefault
                        (triggers.config.viewGroupExpression
                            ( params.direction, params.key )
                        )
                ]
                [ Html.span []
                    [ Html.span
                        [ tableModuleClass
                            |> WeakCss.addMany
                                [ "table"
                                , params.headerClass
                                , "item"
                                , "caption"
                                , "name"
                                ]
                            |> WeakCss.withStates
                                [ ( "title-only", not audienceHasSubtitle ) ]
                        ]
                        [ Html.text audienceData.name
                        ]
                    , Html.viewIfLazy audienceHasSubtitle
                        (\_ ->
                            Html.span
                                [ tableModuleClass
                                    |> WeakCss.nestMany
                                        [ "table"
                                        , params.headerClass
                                        , "item"
                                        , "caption"
                                        , "subtitle"
                                        ]
                                ]
                                [ Html.text audienceData.subtitle ]
                        )
                    ]
                ]
            ]
        , tooltipAttributes = []
        , tooltipHtml = tooltipHtml
        }


metricsView :
    Sort
    -> Key
    -> HeaderClass
    -> List Metric
    -> MetricsTransposition
    -> List (Html msg)
metricsView sort key headerClass metrics metricsTransposition =
    let
        audienceItemId : AudienceItemId
        audienceItemId =
            AudienceItem.getId key.item

        isSortingByThisMetric : Metric -> Bool
        isSortingByThisMetric m =
            case metricsTransposition of
                MetricsInRows ->
                    (Sort.sortingMetric sort.rows == Just m)
                        || ((Sort.sortingMetric sort.columns == Just m)
                                && (Sort.sortingAudience sort.columns == Just audienceItemId)
                           )

                MetricsInColumns ->
                    (Sort.sortingMetric sort.columns == Just m)
                        || ((Sort.sortingMetric sort.rows == Just m)
                                && (Sort.sortingAudience sort.rows == Just audienceItemId)
                           )

        metricView : Metric -> Html msg
        metricView metric =
            case metricsTransposition of
                MetricsInRows ->
                    if isSortingByThisMetric metric then
                        Html.span [ WeakCss.nest "sorted-by" tableModuleClass ]
                            [ Html.text <| Metric.label metric ]

                    else
                        Html.span []
                            [ Html.text <| Metric.label metric ]

                MetricsInColumns ->
                    Html.span
                        [ tableModuleClass
                            |> WeakCss.addMany [ "table", headerClass, "item", "metrics", "label" ]
                            |> WeakCss.withStates [ ( "sorted-by", isSortingByThisMetric metric ) ]
                        ]
                        [ Html.text <| Metric.label metric ]
    in
    [ Html.div
        [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "metrics", "cont" ]
        ]
        [ metrics
            |> List.map metricView
            |> Html.div
                [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "metrics" ]
                ]
        ]
    ]


reorderMetrics : Sort -> List Metric -> List Metric
reorderMetrics sort metrics =
    let
        thisOneFirstIfVisible : Metric -> List Metric
        thisOneFirstIfVisible metric =
            if List.member metric metrics then
                metric :: List.filter ((/=) metric) metrics

            else
                metrics
    in
    case ( sort.rows, sort.columns ) of
        ( ByOtherAxisMetric _ metric _, _ ) ->
            thisOneFirstIfVisible metric

        ( _, ByOtherAxisMetric _ metric _ ) ->
            thisOneFirstIfVisible metric

        ( ByTotalsMetric metric _, _ ) ->
            thisOneFirstIfVisible metric

        ( _, ByTotalsMetric metric _ ) ->
            thisOneFirstIfVisible metric

        ( ByOtherAxisAverage _ _, _ ) ->
            metrics

        ( ByName _, _ ) ->
            metrics

        ( NoSort, _ ) ->
            metrics


dragHandleView :
    { dnd : DnDSystem msg }
    ->
        { headerClass : HeaderClass
        , direction : Direction
        , staticId : String
        , index : Int
        , movableItems : MovableItems
        , numMetrics : Int
        }
    -> Html msg
dragHandleView triggers params =
    Html.div
        ([ WeakCss.nestMany [ "table", params.headerClass, "item", "drag" ]
            tableModuleClass
         , Attrs.attribute "data-metrics-count" (String.fromInt params.numMetrics)
         ]
            ++ triggers.dnd.dragEvents params.direction
                params.movableItems
                params.index
                params.staticId
        )
        [ XB2.Share.Icons.icon [] P2Icons.move ]


sortByEllipsisIconView : (SortDirection -> Bool) -> HeaderClass -> Bool -> Html msg
sortByEllipsisIconView isSortingByThisDirection headerClass isDropdownOpen =
    let
        ( stateIcon, sorted ) =
            if isDropdownOpen then
                ( P2Icons.ellipsisVerticalCircle, False )

            else if isSortingByThisDirection Ascending then
                ( P2Icons.sortAscending, True )

            else if isSortingByThisDirection Descending then
                ( P2Icons.sortDescending, True )

            else
                ( P2Icons.ellipsisVertical, False )
    in
    Html.div
        [ tableModuleClass
            |> WeakCss.addMany [ "table", headerClass, "item", "ellipsis", "icon" ]
            |> WeakCss.withStates [ ( "open", isDropdownOpen ), ( "sorted", sorted ) ]
        ]
        [ XB2.Share.Icons.icon [] stateIcon ]


averageItemDropdown :
    { config : Config model msg }
    ->
        { sort : Sort
        , direction : Direction
        , headerClass : HeaderClass
        , key : Key
        , staticId : String
        , dropdownMenu : DropdownMenu msg
        }
    -> Html msg
averageItemDropdown triggers params =
    let
        dropdownId : String
        dropdownId =
            params.staticId ++ "-dropdown"

        dropdownClass : ClassName
        dropdownClass =
            WeakCss.add "average-item-dropdown" tableModuleClass

        dropdownMenuClass : ClassName
        dropdownMenuClass =
            WeakCss.add "menu" dropdownClass

        otherAxis : Axis
        otherAxis =
            case params.direction of
                Row ->
                    Columns

                Column ->
                    Rows

        sortForOtherAxis : AxisSort
        sortForOtherAxis =
            Sort.forAxis otherAxis params.sort

        isSortingByThisItem : Bool
        isSortingByThisItem =
            case sortForOtherAxis of
                ByOtherAxisMetric _ _ _ ->
                    False

                ByOtherAxisAverage id _ ->
                    id == AudienceItem.getId params.key.item

                ByTotalsMetric _ _ ->
                    False

                ByName _ ->
                    False

                NoSort ->
                    False

        isSortingByThisDirection : SortDirection -> Bool
        isSortingByThisDirection sortDirection =
            sortForOtherAxis == ByOtherAxisAverage (AudienceItem.getId params.key.item) sortDirection

        isDropdownOpen : Bool
        isDropdownOpen =
            triggers.config.isFixedPageDropdownOpen dropdownId params.dropdownMenu
    in
    triggers.config.withDropdownMenu
        { id = dropdownId
        , orientation =
            case params.direction of
                Row ->
                    DropdownMenu.RightCenter

                Column ->
                    DropdownMenu.BottomRight
        , screenBottomEdgeMinOffset = 160
        , screenSideEdgeMinOffset = 800
        , controlElementAttrs =
            [ tableModuleClass
                |> WeakCss.nestMany [ "table", params.headerClass, "item", "ellipsis" ]
            , Attrs.attribute "aria-label" "Header options"
            , Attrs.id ("icon-ellipsis-id-" ++ dropdownId)
            ]
        , controlElementContent =
            [ sortByEllipsisIconView isSortingByThisDirection params.headerClass isDropdownOpen ]
        , content =
            Html.div
                [ dropdownClass |> WeakCss.withActiveStates [ "dynamic" ] ]
                [ Html.div
                    [ dropdownMenuClass
                        |> WeakCss.withActiveStates
                            [ if params.headerClass == "rows" then
                                "expand-right"

                              else
                                "expand-left"
                            ]
                    ]
                    [ DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Rename"
                        , DropdownItem.onClick (triggers.config.openRenameAverageModal params.direction params.key)
                        , DropdownItem.leftIcon P2Icons.fileSearch
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Sort by"
                        , DropdownItem.leftIcon P2Icons.sort
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.selected isSortingByThisItem
                        , DropdownItem.children
                            [ [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.label "Ascending"
                              , DropdownItem.leftIcon P2Icons.sortAscending
                              , DropdownItem.selected (isSortingByThisDirection Ascending)
                              , DropdownItem.onClick
                                    {- If we're in a row, and clicking on "Sort by this row's average"
                                       that translates into
                                           sort =
                                                { rows = ... -- unchanged
                                                , columns = ByOtherAxisAverage thisKey.id  direction
                                                }
                                       Hence why we're sorting *the other axis* in this msg:
                                    -}
                                    (triggers.config.sortByOtherAxisAverage
                                        { mode = ByOtherAxisAverage (AudienceItem.getId params.key.item) Ascending
                                        , axis = otherAxis
                                        }
                                    )
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.label "Descending"
                              , DropdownItem.leftIcon P2Icons.sortDescending
                              , DropdownItem.selected (isSortingByThisDirection Descending)
                              , DropdownItem.onClick
                                    -- same as above
                                    (triggers.config.sortByOtherAxisAverage
                                        { mode = ByOtherAxisAverage (AudienceItem.getId params.key.item) Descending
                                        , axis = otherAxis
                                        }
                                    )
                              ]
                            , [ DropdownItem.class dropdownMenuClass
                              , DropdownItem.onClick (triggers.config.resetSortForAxis otherAxis)
                              , DropdownItem.label "Reset"
                              , DropdownItem.leftIcon P2Icons.sync
                              , DropdownItem.disabled (not isSortingByThisItem)
                              ]
                            ]
                        ]
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick (triggers.config.removeAverageRowOrCol params.direction params.key)
                        , DropdownItem.label "Remove attribute"
                        , DropdownItem.leftIcon P2Icons.trash
                        ]
                    ]
                ]
        }


{-| Header dropdown of Crosstabs' `AudienceItem`s.
-}
viewHeaderDropdown :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , sort : Sort
        , direction : Direction
        , frozenRowsAndColumns : ( Int, Int )
        , headerClass : HeaderClass
        , key : Key
        , staticId : String
        , dropdownMenu : DropdownMenu msg
        , remoteUserSettings : RemoteData.WebData XBUserSettings
        , headerIndex : Int
        , numberOfRowsAndCols : { rows : Int, cols : Int }
        , isTotalsHeader : Bool
        }
    -> Html msg
viewHeaderDropdown triggers params =
    let
        dropdownId : String
        dropdownId =
            params.staticId ++ "-dropdown"

        dropdownClass : ClassName
        dropdownClass =
            WeakCss.add "header-item-dropdown" tableModuleClass

        dropdownMenuClass : ClassName
        dropdownMenuClass =
            WeakCss.add "menu" dropdownClass

        orientation : DropdownMenu.Orientation
        orientation =
            case params.direction of
                Row ->
                    DropdownMenu.RightCenter

                Column ->
                    DropdownMenu.BottomRight

        otherAxis : Axis
        otherAxis =
            case params.direction of
                Row ->
                    Columns

                Column ->
                    Rows

        sortForOtherAxis : AxisSort
        sortForOtherAxis =
            Sort.forAxis otherAxis params.sort

        isSortingByThisItem : Bool
        isSortingByThisItem =
            case sortForOtherAxis of
                ByOtherAxisMetric id _ _ ->
                    id == AudienceItem.getId params.key.item

                ByTotalsMetric _ _ ->
                    AudienceItemId.total == AudienceItem.getId params.key.item

                ByOtherAxisAverage _ _ ->
                    False

                ByName _ ->
                    False

                NoSort ->
                    False

        isSortingByThisMetric : Metric -> Bool
        isSortingByThisMetric metric =
            isSortingByThisItem && (Just metric == Sort.sortingMetric sortForOtherAxis)

        isSortingByThisMetricDirection : Metric -> SortDirection -> Bool
        isSortingByThisMetricDirection metric sortDirection =
            sortForOtherAxis
                == ByOtherAxisMetric (AudienceItem.getId params.key.item) metric sortDirection
                || (sortForOtherAxis
                        == ByTotalsMetric metric sortDirection
                        && AudienceItemId.total
                        == AudienceItem.getId params.key.item
                   )

        isSortingByThisDirection : SortDirection -> Bool
        isSortingByThisDirection sortDirection =
            List.foldl
                (\metric acc ->
                    acc
                        || (sortForOtherAxis
                                == ByOtherAxisMetric (AudienceItem.getId params.key.item) metric sortDirection
                                || (sortForOtherAxis
                                        == ByTotalsMetric metric sortDirection
                                        && AudienceItemId.total
                                        == AudienceItem.getId params.key.item
                                   )
                           )
                )
                False
                Metric.allMetrics

        datasetsToNamespaces : BiDict DatasetCode Namespace.Code
        datasetsToNamespaces =
            params.p2Store.datasetsToNamespaces
                |> RemoteData.withDefault BiDict.empty

        haveAllNeededDatasets : Bool
        haveAllNeededDatasets =
            params.key.item
                |> AudienceItem.getDefinition
                |> XB2.Data.definitionNamespaceCodes
                |> XB2.Share.Data.Platform2.datasetCodesForNamespaceCodes datasetsToNamespaces params.p2Store.lineages
                |> RemoteData.isSuccess

        isDropdownOpen : Bool
        isDropdownOpen =
            triggers.config.isFixedPageDropdownOpen dropdownId params.dropdownMenu

        metricDropdownChildren : Metric -> List (DropdownItem.Attribute msg)
        metricDropdownChildren metric =
            [ DropdownItem.class dropdownMenuClass
            , DropdownItem.label (Metric.label metric)
            , DropdownItem.rightIcon P2Icons.chevronRight
            , DropdownItem.selected (isSortingByThisMetric metric)
            , DropdownItem.children
                [ [ DropdownItem.class dropdownMenuClass
                  , DropdownItem.label "Ascending"
                  , DropdownItem.leftIcon P2Icons.sortAscending
                  , DropdownItem.selected (isSortingByThisMetricDirection metric Ascending)
                  , DropdownItem.onClick
                        {- If we're in a row, and clicking on "Sort by this row's
                           metric", that translates into
                               sort =
                                    { rows = ... -- unchanged
                                    , columns = ByOtherAxisMetric thisKey.id metric direction
                                    }
                           Hence why we're sorting *the other axis* in this msg:
                        -}
                        (if params.isTotalsHeader then
                            triggers.config.sortByTotalsMetric
                                { mode = ByTotalsMetric metric Ascending
                                , axis = otherAxis
                                }

                         else
                            triggers.config.sortByOtherAxisMetric
                                { mode = ByOtherAxisMetric (AudienceItem.getId params.key.item) metric Ascending
                                , axis = otherAxis
                                }
                        )
                  ]
                , [ DropdownItem.class dropdownMenuClass
                  , DropdownItem.label "Descending"
                  , DropdownItem.leftIcon P2Icons.sortDescending
                  , DropdownItem.selected (isSortingByThisMetricDirection metric Descending)
                  , DropdownItem.onClick
                        -- same as above
                        (if params.isTotalsHeader then
                            triggers.config.sortByTotalsMetric
                                { mode = ByTotalsMetric metric Descending
                                , axis = otherAxis
                                }

                         else
                            triggers.config.sortByOtherAxisMetric
                                { mode = ByOtherAxisMetric (AudienceItem.getId params.key.item) metric Descending
                                , axis = otherAxis
                                }
                        )
                  ]
                ]
            ]

        ( rowsFrozen, colsFrozen ) =
            params.frozenRowsAndColumns

        freezeDropdownChildrenView : List (List (DropdownItem.Attribute msg))
        freezeDropdownChildrenView =
            case params.direction of
                Column ->
                    [ [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( rowsFrozen, 0 )
                            )
                      , DropdownItem.label "No columns"
                      , DropdownItem.selected
                            (colsFrozen < 1)
                      ]
                    , [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( rowsFrozen, 1 )
                            )
                      , DropdownItem.label "First 1 column"
                      , DropdownItem.selected
                            (colsFrozen == 1)
                      ]
                    , [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( rowsFrozen, 2 )
                            )
                      , DropdownItem.label "First 2 columns"
                      , DropdownItem.selected
                            (colsFrozen == 2)
                      ]
                    ]

                Row ->
                    [ [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( 0, colsFrozen )
                            )
                      , DropdownItem.label "No rows"
                      , DropdownItem.selected
                            (rowsFrozen < 1)
                      ]
                    , [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( 1, colsFrozen )
                            )
                      , DropdownItem.label "First 1 row"
                      , DropdownItem.selected
                            (rowsFrozen == 1)
                      ]
                    , [ DropdownItem.class dropdownMenuClass
                      , DropdownItem.onClick
                            (triggers.config.setFrozenRowsColumns
                                ( 2, colsFrozen )
                            )
                      , DropdownItem.label "First 2 rows"
                      , DropdownItem.selected
                            (rowsFrozen == 2)
                      ]
                    ]
    in
    triggers.config.withDropdownMenu
        { id = dropdownId
        , orientation = orientation
        , screenBottomEdgeMinOffset = 160
        , screenSideEdgeMinOffset = 800
        , controlElementAttrs =
            [ tableModuleClass
                |> WeakCss.nestMany [ "table", params.headerClass, "item", "ellipsis" ]
            , Attrs.attribute "aria-label" "Header options"
            , Attrs.id ("icon-ellipsis-id-" ++ dropdownId)
            ]
        , controlElementContent =
            [ sortByEllipsisIconView isSortingByThisDirection params.headerClass isDropdownOpen
            ]
        , content =
            Html.div
                [ dropdownClass |> WeakCss.withActiveStates [ "dynamic" ] ]
                [ Html.div
                    [ dropdownMenuClass
                        |> WeakCss.withActiveStates
                            [ if params.headerClass == "rows" || params.headerClass == "frozen-total-rows" || params.isTotalsHeader then
                                "expand-right"

                              else
                                "expand-left"
                            ]
                    ]
                    [ DropdownItem.viewIf (not params.isTotalsHeader)
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "View/rename"
                        , DropdownItem.onClick (triggers.config.viewGroupExpression ( params.direction, params.key ))
                        , DropdownItem.leftIcon P2Icons.fileSearch
                        ]
                    , DropdownItem.viewIf (not params.isTotalsHeader)
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Edit expression"
                        , DropdownItem.onClick (triggers.config.openEditTableForSingle ( params.direction, params.key ))
                        , DropdownItem.leftIcon P2Icons.edit
                        ]
                    , Html.viewIf haveAllNeededDatasets <|
                        DropdownItem.viewIf (not params.isTotalsHeader)
                            [ DropdownItem.class dropdownMenuClass
                            , DropdownItem.onClick (triggers.config.openSaveAsAudienceModal ( params.direction, params.key ))
                            , DropdownItem.label "Save as a new audience"
                            , DropdownItem.leftIcon P2Icons.userFriends
                            ]
                    , DropdownItem.separator dropdownMenuClass
                    , DropdownItem.view
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Sort by"
                        , DropdownItem.leftIcon P2Icons.sort
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.selected isSortingByThisItem
                        , DropdownItem.dynamicVerticalOrientation
                        , DropdownItem.children
                            (List.map metricDropdownChildren Metric.allMetrics
                                ++ [ [ DropdownItem.class dropdownMenuClass
                                     , DropdownItem.onClick (triggers.config.resetSortForAxis otherAxis)
                                     , DropdownItem.label "Reset"
                                     , DropdownItem.leftIcon P2Icons.sync
                                     , DropdownItem.disabled (not isSortingByThisItem)
                                     ]
                                   ]
                            )
                        ]
                    , DropdownItem.viewIf (not params.isTotalsHeader)
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.label "Freeze"
                        , DropdownItem.leftIcon P2Icons.freeze
                        , DropdownItem.rightIcon P2Icons.chevronRight
                        , DropdownItem.dynamicVerticalOrientation
                        , DropdownItem.children
                            freezeDropdownChildrenView
                        ]
                    , DropdownItem.separator dropdownMenuClass
                    , DropdownItem.viewIf (not params.isTotalsHeader)
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick (triggers.config.duplicateAudience ( params.direction, params.key ))
                        , DropdownItem.label <|
                            "Duplicate "
                                ++ (case params.direction of
                                        Row ->
                                            "row"

                                        Column ->
                                            "column"
                                   )
                        , DropdownItem.leftIcon P2Icons.duplicate
                        ]
                    , DropdownItem.viewIf (not params.isTotalsHeader)
                        [ DropdownItem.class dropdownMenuClass
                        , DropdownItem.onClick (triggers.config.removeAudience ( params.direction, params.key ))
                        , DropdownItem.label <|
                            "Remove "
                                ++ (case params.direction of
                                        Row ->
                                            "row"

                                        Column ->
                                            "column"
                                   )
                        , DropdownItem.leftIcon P2Icons.trash
                        ]
                    ]
                ]
        }


keyedHeaderView :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , className : String
        , sort : Sort
        , dndListModel : DnDListModel
        , selectedItems : Maybe MovableItems
        , selectionMap : SelectionMap
        , isLastHeader : Bool
        , direction : Direction
        , metrics : List Metric
        , metricsTransposition : MetricsTransposition
        , dropdownMenu : DropdownMenu msg
        , index : Int
        , key : Key
        , numberOfRowsAndCols : { rows : Int, cols : Int }
        , searchProps : CrosstabSearchProps
        }
    -> ( String, Html msg )
keyedHeaderView triggers params =
    let
        isInDebugMode : Bool
        isInDebugMode =
            RemoteData.unwrap False .showDetailTableInDebugMode params.remoteUserSettings

        dndInfo : Maybe (XB2.Share.DragAndDrop.Move.Info Direction MovableItems)
        dndInfo =
            triggers.config.dnd.info params.dndListModel

        isTotalsHeader : Bool
        isTotalsHeader =
            params.index == 0

        staticId : String
        staticId =
            case ( isTotalsHeader, params.direction ) of
                ( True, Row ) ->
                    Common.tableMetricsTotalRowId

                ( True, Column ) ->
                    "totals-col"

                ( False, _ ) ->
                    "header-" ++ (AudienceItem.getIdString << .item) params.key

        selectionSettings : SelectionMap.SelectionSettings
        selectionSettings =
            case params.direction of
                Row ->
                    SelectionMap.selectionSettingsForRow (params.index - 1) params.selectionMap

                Column ->
                    SelectionMap.selectionSettingsForColumn (params.index - 1) params.selectionMap

        selectionStates : List ( String, Bool )
        selectionStates =
            case params.direction of
                Row ->
                    [ ( "selected-above", selectionSettings.above )
                    , ( "selected-below", selectionSettings.below )
                    , ( "last-header", params.isLastHeader )
                    , ( "even", modBy 2 params.index > 0 )
                    ]

                Column ->
                    [ ( "selected-left", selectionSettings.left )
                    , ( "selected-right", selectionSettings.right )
                    , ( "last-header", params.isLastHeader )
                    ]

        headerClass : String
        headerClass =
            params.className

        sortDirection : Maybe SortDirection
        sortDirection =
            let
                sortingForThisKey : AxisSort
                sortingForThisKey =
                    case params.direction of
                        Column ->
                            params.sort.rows

                        Row ->
                            params.sort.columns
            in
            case sortingForThisKey of
                ByOtherAxisMetric id _ sDirection ->
                    if id == AudienceItem.getId params.key.item then
                        Just sDirection

                    else
                        Nothing

                ByTotalsMetric _ sDirection ->
                    if AudienceItemId.total == AudienceItem.getId params.key.item then
                        Just sDirection

                    else
                        Nothing

                ByOtherAxisAverage id sDirection ->
                    if id == AudienceItem.getId params.key.item then
                        Just sDirection

                    else
                        Nothing

                ByName _ ->
                    Nothing

                NoSort ->
                    Nothing

        isSortByThisKey : Bool
        isSortByThisKey =
            Nothing /= sortDirection

        dndStates : List ( String, Bool )
        dndStates =
            dndInfo
                |> Maybe.map
                    (\{ dragListId, dragIndex, dropListId, dropIndex, dragItem } ->
                        [ ( "placeholder", ACrosstab.isMovableItemsMember params.key dragItem )
                        , ( "next-to-placeholder", dragIndex == params.index + 1 && dragListId == params.direction )
                        , ( "droppable", not (dragIndex == params.index && dragListId == params.direction) && not (dragIndex == params.index + 1 && dragListId == params.direction) )
                        , ( "affordance", dragIndex == dropIndex && dragListId == dropListId )
                        , ( "mouseover", dropIndex == params.index && dropListId == params.direction && (not <| ACrosstab.isMovableItemsMember params.key dragItem) )
                        ]
                    )
                |> Maybe.withDefault []

        isAverage : Bool
        isAverage =
            AudienceItem.isAverage params.key.item

        isFocusedSearchTerm : Bool
        isFocusedSearchTerm =
            case Maybe.map Zipper.current params.searchProps.searchTopLeftScrollJumps of
                Just { index, direction } ->
                    index == params.index && direction == params.direction && params.searchProps.inputIsFocused

                Nothing ->
                    False

        isHighlightedBySearchTerm : Bool
        isHighlightedBySearchTerm =
            case Maybe.map Zipper.toList params.searchProps.searchTopLeftScrollJumps of
                Just searchItems ->
                    List.member { index = params.index, direction = params.direction } searchItems

                Nothing ->
                    False

        states : List ( String, Bool )
        states =
            selectionStates
                ++ dndStates
                ++ [ ( "selected", params.key.isSelected )
                   , ( "focused-search-term", isFocusedSearchTerm )
                   , ( "search-highlight", isHighlightedBySearchTerm )
                   , ( "sorted-by", isSortByThisKey )
                   , ( "sort-direction-asc", sortDirection == Just Ascending )
                   , ( "sort-direction-desc", sortDirection == Just Descending )
                   , ( "is-average", isAverage )
                   , ( "non-totals", params.index /= 0 )
                   ]

        dropEvents : List (Attribute msg)
        dropEvents =
            case dndInfo of
                Just { dragListId, dragIndex } ->
                    if not (dragIndex == params.index && dragListId == params.direction) && not (dragIndex == params.index + 1 && dragListId == params.direction) then
                        triggers.config.dnd.dropEvents params.direction params.index staticId

                    else
                        []

                Nothing ->
                    []

        labelNameView : Html msg
        labelNameView =
            Html.span
                [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "label" ] ]
                [ Html.text <|
                    case params.direction of
                        Column ->
                            if isInDebugMode then
                                "{ "
                                    ++ String.fromInt params.index
                                    ++ "/"
                                    ++ headerClass
                                    ++ " }"

                            else
                                Maybe.withDefault "" <|
                                    columnName params.index

                        Row ->
                            if isInDebugMode then
                                "{ "
                                    ++ String.fromInt params.index
                                    ++ "/"
                                    ++ headerClass
                                    ++ " }"

                            else
                                rowName params.index
                ]

        numMetrics : Int
        numMetrics =
            List.length params.metrics
    in
    ( staticId
    , Html.li
        ([ tableModuleClass |> WeakCss.addMany [ "table", headerClass, "item" ] |> WeakCss.withStates states
         , Attrs.id staticId
         ]
            ++ dropEvents
        )
        [ Html.div [ WeakCss.nestMany [ "table", headerClass, "item", "content" ] tableModuleClass ]
            [ labelNameView
            , Html.div
                [ WeakCss.addMany [ "table", headerClass, "item", "main" ] tableModuleClass
                    |> WeakCss.withStates [ ( "is-total", isTotalsHeader ) ]
                , Events.on "mousedown" <|
                    Decode.map2 (\x y -> triggers.config.selectRowOrColumnMouseDown ( x, y ))
                        (Decode.field "pageX" Decode.float)
                        (Decode.field "pageY" Decode.float)
                ]
              <|
                Html.viewIfLazy
                    (not isAverage && (params.key.isSelected || (not isTotalsHeader && dndInfo == Nothing)))
                    (\_ -> selectCheckboxView triggers.config params.direction params.key)
                    :: Html.viewIfLazy
                        (not isTotalsHeader && dndInfo == Nothing)
                        (\_ ->
                            let
                                movableItems : MovableItems
                                movableItems =
                                    params.selectedItems
                                        |> Maybe.andThen
                                            (\mItems ->
                                                if NonemptyList.member ( params.direction, params.key ) mItems then
                                                    Just mItems

                                                else
                                                    Nothing
                                            )
                                        |> Maybe.withDefault (NonemptyList.singleton ( params.direction, params.key ))
                            in
                            dragHandleView
                                { dnd = triggers.config.dnd }
                                { headerClass = headerClass
                                , direction = params.direction
                                , staticId = staticId
                                , index = params.index
                                , movableItems = movableItems
                                , numMetrics = numMetrics
                                }
                        )
                    :: captionView
                        { config = triggers.config }
                        { headerClass = headerClass
                        , direction = params.direction
                        , key = params.key
                        , isInDebugMode = isInDebugMode
                        }
                    :: (if isAverage then
                            [ Html.Lazy.lazy2
                                averageItemDropdown
                                { config = triggers.config }
                                { sort = params.sort
                                , direction = params.direction
                                , headerClass = headerClass
                                , key = params.key
                                , staticId = staticId
                                , dropdownMenu = params.dropdownMenu
                                }
                            ]

                        else
                            Html.Lazy.lazy2 viewHeaderDropdown
                                { config = triggers.config }
                                { p2Store = params.p2Store
                                , sort = params.sort
                                , direction = params.direction
                                , frozenRowsAndColumns = params.frozenRowsAndColumns
                                , headerClass = headerClass
                                , key = params.key
                                , staticId = staticId
                                , dropdownMenu = params.dropdownMenu
                                , remoteUserSettings = params.remoteUserSettings
                                , headerIndex = params.index
                                , numberOfRowsAndCols = params.numberOfRowsAndCols
                                , isTotalsHeader = isTotalsHeader
                                }
                                :: metricsView params.sort params.key headerClass params.metrics params.metricsTransposition
                       )
            ]
        ]
    )


ghostInnerView :
    { config : Config model msg
    , dnd : DnDSystem msg
    }
    ->
        { dndModel : DnDModel
        , direction : Direction
        , items : MovableItems
        , isInDebugMode : Bool
        }
    -> Html msg
ghostInnerView triggers params =
    let
        headerClass : HeaderClass
        headerClass =
            getHeaderClass params.direction

        key : Key
        key =
            NonemptyList.head params.items
                |> Tuple.second

        isAverage : Bool
        isAverage =
            AudienceItem.isAverage key.item
    in
    Html.div
        ((tableModuleClass
            |> WeakCss.addMany [ "table", headerClass, "item" ]
            |> WeakCss.withStates
                [ ( "ghost", True )
                , ( "is-average", isAverage )
                ]
         )
            :: triggers.dnd.ghostStyles params.dndModel
        )
        [ Html.viewIf (NonemptyList.length params.items > 1) <|
            Html.div [ WeakCss.nestMany [ "table", headerClass, "item", "drag-multiple" ] tableModuleClass ] []
        , Html.div [ WeakCss.nestMany [ "table", headerClass, "item", "content" ] tableModuleClass ]
            [ Html.span
                [ tableModuleClass |> WeakCss.nestMany [ "table", headerClass, "item", "label" ] ]
                []
            , Html.div [ WeakCss.nestMany [ "table", headerClass, "item", "main" ] tableModuleClass ]
                [ captionView
                    { config = triggers.config }
                    { headerClass = headerClass
                    , direction = params.direction
                    , key = key
                    , isInDebugMode = params.isInDebugMode
                    }
                ]
            ]
        ]


viewGhostHeaderLazy :
    { config : Config model msg, dnd : DnDSystem msg }
    -> { dndModel : DnDModel, isInDebugMode : Bool }
    -> Html msg
viewGhostHeaderLazy =
    Html.Lazy.lazy2
        (\memoTriggers memoParams ->
            case memoTriggers.dnd.info memoParams.dndModel.list of
                Just { dragListId, dragItem } ->
                    ghostInnerView
                        { config = memoTriggers.config, dnd = memoTriggers.dnd }
                        { dndModel = memoParams.dndModel
                        , direction = dragListId
                        , items = dragItem
                        , isInDebugMode = memoParams.isInDebugMode
                        }

                Nothing ->
                    Html.nothing
        )



-- Cell views


{-| Shows the horizontal grey loading bar. Useful as a placeholder for lazy views.
-}
loaderViewContent : String -> Bool -> Int -> List (Html msg)
loaderViewContent className animated metricsCount =
    List.repeat metricsCount
        (Html.span
            [ tableModuleClass
                |> WeakCss.addMany [ "table", className, "row", "item", "loader-bar" ]
                |> WeakCss.withStates [ ( "animated", animated ) ]
            ]
            []
        )


valueView : String -> { isSortingMetric : Bool, shouldBeGreyOut : Bool } -> String -> Html msg
valueView className { isSortingMetric, shouldBeGreyOut } value =
    Html.div
        [ tableModuleClass
            |> WeakCss.addMany [ "table", className, "row", "item", "value" ]
            |> WeakCss.withStates [ ( "sorted-by", isSortingMetric ) ]
        , Attrs.attributeIf shouldBeGreyOut (Attrs.style "opacity" "0.15")
        ]
        [ Html.text value ]


{-| TODO: Absolute madness of unreadable function... Cognitive complexity is TOO huge.
Split this monstrosity into several small parts.
-}
cellView :
    { switchAverageTimeFormatMsg : msg
    , openTableWarning :
        { warning : Common.TableWarning msg
        , row : AudienceDefinition
        , column : AudienceDefinition
        }
        -> msg
    , averageTimeFormat : AverageTimeFormat
    , loaderContent : List (Html msg)
    , notAnimatedLoaderContent : List (Html msg)
    , sort : Sort
    , metricsTransposition : MetricsTransposition
    , crosstab : AudienceCrosstab
    , metrics : List Metric
    , heatmapScale : Maybe HeatmapScale
    , minimumSampleSize : MinimumSampleSize
    , totalRowRespondents : Int
    , totalColRespondents : Int
    , base : BaseAudience
    , column : Key
    , row : Key
    , selectionMap : SelectionMap
    , rowIndex : Int
    , colIndex : Int
    , dndInfo : Maybe (XB2.Share.DragAndDrop.Move.Info Direction MovableItems)
    , forcedLoadingState : Bool
    , areDatasetsIncompatible : Bool
    , can : Can
    , store : XB2.Share.Store.Platform2.Store
    , shouldShowExactRespondentNumber : Bool
    , shouldShowExactUniverseNumber : Bool
    , toggleExactRespondentNumberMsg : msg
    , toggleExactUniverseNumberMsg : msg
    , updateUserSettingsMsg : XBUserSettings -> msg
    , userSettings : WebData XBUserSettings
    , className : String
    }
    -> Html msg
cellView p =
    let
        selectionSettings : SelectionMap.SelectionSettings
        selectionSettings =
            SelectionMap.selectionSettings (p.rowIndex - 1) (p.colIndex - 1) p.selectionMap

        isLastRow : Bool
        isLastRow =
            p.rowIndex == ACrosstab.rowCountWithoutTotals p.crosstab

        cellClass : ClassName
        cellClass =
            WeakCss.addMany [ "table", p.className, "row", "item" ] tableModuleClass

        withDndStates : Direction -> List ( String, Bool ) -> List ( String, Bool )
        withDndStates direction =
            let
                ( directionPrefix, index, key ) =
                    case direction of
                        Row ->
                            ( "row-", p.rowIndex, p.row )

                        Column ->
                            ( "column-", p.colIndex, p.column )
            in
            p.dndInfo
                |> Maybe.unwrap
                    identity
                    (\{ dropListId, dropIndex, dragItem } ->
                        (++) [ ( directionPrefix ++ "mouseover", dropIndex == index && dropListId == direction && (not <| ACrosstab.isMovableItemsMember key dragItem) ) ]
                    )

        cellClassAttr : Attribute msg
        cellClassAttr =
            WeakCss.withStates
                ([ ( "last-row", isLastRow )
                 , ( "selected-above", selectionSettings.above )
                 , ( "selected-below", selectionSettings.below )
                 , ( "selected-left", selectionSettings.left )
                 , ( "selected-right", selectionSettings.right )
                 , ( "selected-row", selectionSettings.selectedRow )
                 , ( "selected-column", selectionSettings.selectedColumn )
                 ]
                    |> withDndStates Row
                    |> withDndStates Column
                )
                cellClass

        cell : ACrosstab.Cell
        cell =
            ACrosstab.value { base = p.base, col = p.column, row = p.row } p.crosstab
                |> (if p.forcedLoadingState then
                        \c ->
                            { c
                                | data =
                                    case c.data of
                                        AvAData avaData ->
                                            AvAData { avaData | data = Tracked.Loading Nothing }

                                        AverageData _ ->
                                            AverageData <| Tracked.Loading Nothing
                            }

                    else
                        identity
                   )

        isTotalCell : Bool
        isTotalCell =
            (AudienceItem.getId p.row.item == AudienceItemId.total)
                || (AudienceItem.getId p.column.item == AudienceItemId.total)

        isTotalVsTotalCell : Bool
        isTotalVsTotalCell =
            (AudienceItem.getId p.row.item == AudienceItemId.total)
                && (AudienceItem.getId p.column.item == AudienceItemId.total)

        isAverageCell : Bool
        isAverageCell =
            List.any (.item >> AudienceItem.isAverage) [ p.row, p.column ]

        warningIcon : { onClick : msg } -> Html msg
        warningIcon { onClick } =
            Html.span
                [ WeakCss.nest "warning-icon" cellClass
                ]
                [ P2CoolTip.view
                    { offset = Nothing
                    , type_ = XB2.Share.CoolTip.Global
                    , position = XB2.Share.CoolTip.Bottom
                    , wrapperAttributes = []
                    , targetAttributes = [ Events.onClick onClick ]
                    , targetHtml =
                        [ Html.button
                            [ WeakCss.nestMany [ "warning-icon", "target" ] cellClass
                            , Attrs.attribute "aria-label" "Cell warning"
                            ]
                            [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 16 ] P2Icons.warning ]
                        ]
                    , tooltipAttributes = []
                    , tooltipHtml = Html.text "See warning"
                    }
                ]

        notAvailableWarningIcon : Error XBQueryError -> Html msg
        notAvailableWarningIcon err =
            warningIcon
                { onClick =
                    p.openTableWarning
                        { warning = Common.CellXBQueryError err
                        , row = AudienceItem.getDefinition p.row.item
                        , column = AudienceItem.getDefinition p.column.item
                        }
                }

        totalVsTotalDatasetWarningIcon : { isColumns : Bool } -> Html msg
        totalVsTotalDatasetWarningIcon { isColumns } =
            Html.span
                [ cellClass
                    |> WeakCss.add "warning-icon-total-vs-total"
                    |> WeakCss.withStates [ ( "is-alone", List.length p.metrics == 1 && not isColumns ) ]
                ]
                [ P2CoolTip.view
                    { offset = Nothing
                    , type_ = XB2.Share.CoolTip.Global
                    , position = XB2.Share.CoolTip.Bottom
                    , wrapperAttributes = []
                    , targetAttributes = []
                    , targetHtml = [ XB2.Share.Icons.icon [] P2Icons.info ]
                    , tooltipAttributes = [ Attrs.class "p2-white short" ]
                    , tooltipHtml = Html.text "Please note, this cell value refers to all respondents in the GWI Core dataset. To display more relevant results to your analysis change your default base with the “Audience Size” data point for your selected data set."
                    }
                ]

        generateMarkdownForIncompatibilities : List ACrosstab.Incompatibility -> String
        generateMarkdownForIncompatibilities incompatibilities =
            let
                allWavesPseudoWave : { code : WaveCode, name : String }
                allWavesPseudoWave =
                    { code = XB2.Share.Data.Id.fromString "all-waves-pseudo-code"
                    , name = "any of your selected waves"
                    }

                emptyDictForLocationsPerWave :
                    AnyDict
                        String
                        { code : WaveCode
                        , name : String
                        }
                        (AnySet String XB2.Share.Data.Labels.Location)
                emptyDictForLocationsPerWave =
                    Dict.Any.empty (.code >> XB2.Share.Data.Id.unwrap)

                bold : String -> String
                bold str =
                    "**" ++ str ++ "**"

                incompatibilitiesLocationsPerWaves :
                    AnyDict
                        String
                        { code : XB2.Share.Data.Id.Id XB2.Share.Data.Labels.WaveCodeTag
                        , name : String
                        }
                        (AnySet String Location)
                incompatibilitiesLocationsPerWaves =
                    incompatibilities
                        |> List.foldl
                            (\i locationsPerWave ->
                                let
                                    storeLocationForThisWave : Maybe (AnySet String XB2.Share.Data.Labels.Location) -> Maybe (AnySet String XB2.Share.Data.Labels.Location)
                                    storeLocationForThisWave maybeSet =
                                        Maybe.withDefault (Set.Any.empty (.code >> XB2.Share.Data.Id.unwrap)) maybeSet
                                            |> Set.Any.insert i.location
                                            |> Just
                                in
                                if List.isEmpty i.waves then
                                    Dict.Any.update allWavesPseudoWave storeLocationForThisWave locationsPerWave

                                else
                                    i.waves
                                        |> List.foldl (\wave -> Dict.Any.update { code = wave.code, name = wave.name } storeLocationForThisWave) locationsPerWave
                            )
                            emptyDictForLocationsPerWave
            in
            incompatibilitiesLocationsPerWaves
                |> Dict.Any.toList
                |> List.map
                    (\( w, locations ) ->
                        "- Not asked in "
                            ++ bold w.name
                            ++ " in: \n\n"
                            ++ (Set.Any.toList locations
                                    |> List.map (.name >> bold)
                                    |> List.sort
                                    |> String.join ", "
                               )
                    )
                |> String.join "\n\n"

        coefficientStretchingView : AudienceIntersect.IntersectResult -> Html msg
        coefficientStretchingView value =
            if p.can XB2.Share.Permissions.UseDebugButtons then
                AudienceIntersect.getCoefficientStretchingInfo p.store value
                    |> Html.viewMaybe
                        (\stretchingInfo ->
                            let
                                warningContent : Common.TableWarning msg
                                warningContent =
                                    Common.GenericTableWarning
                                        { count = 1
                                        , content =
                                            stretchingInfo
                                                |> Markdown.toHtml []
                                        , additionalNotice = Nothing
                                        }
                            in
                            Html.span
                                [ WeakCss.nest "info-icon" cellClass
                                ]
                                [ P2CoolTip.view
                                    { offset = Nothing
                                    , type_ = XB2.Share.CoolTip.Global
                                    , position = XB2.Share.CoolTip.Top
                                    , wrapperAttributes = []
                                    , targetAttributes =
                                        [ Events.onClick <|
                                            p.openTableWarning
                                                { warning = warningContent
                                                , row = AudienceItem.getDefinition p.row.item
                                                , column = AudienceItem.getDefinition p.column.item
                                                }
                                        ]
                                    , targetHtml =
                                        [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.info
                                        ]
                                    , tooltipAttributes = []
                                    , tooltipHtml = Html.text "See stretching warning"
                                    }
                                ]
                        )

            else
                Html.nothing

        singleNAErrorView : Error XBQueryError -> Html msg
        singleNAErrorView err =
            Html.li
                [ cellClassAttr ]
                [ notAvailableWarningIcon err
                , Html.div
                    [ cellClass |> WeakCss.nest "value" ]
                    [ Html.text "N/A" ]
                ]

        ( isSortingByThisCell, sortingMetric ) =
            case ( p.sort.rows, p.sort.columns ) of
                {- we're "guaranteed" ByOtherAxisMetric is only in one of the
                   axis, never in both

                   TODO: Then why do we have to check both?? TYPES make guarantees. Use
                   them to enforce invariants.
                -}
                ( ByOtherAxisMetric id metric _, _ ) ->
                    ( AudienceItem.getId p.column.item == id
                    , Just metric
                    )

                ( _, ByOtherAxisMetric id metric _ ) ->
                    ( AudienceItem.getId p.row.item == id
                    , Just metric
                    )

                ( ByTotalsMetric metric _, _ ) ->
                    ( AudienceItem.getId p.column.item == AudienceItemId.total
                    , Just metric
                    )

                ( _, ByTotalsMetric metric _ ) ->
                    ( AudienceItem.getId p.row.item == AudienceItemId.total
                    , Just metric
                    )

                {- We do not care about ⬇this⬇ other combinations of sorting. Only if
                   either rows or columns are sorted by this cell `ByOtherAxisMetric`.
                -}
                ( ByOtherAxisAverage _ _, _ ) ->
                    ( False, Nothing )

                ( ByName _, _ ) ->
                    ( False, Nothing )

                ( NoSort, _ ) ->
                    ( False, Nothing )

        averageCellValueView : List String -> List (Html msg)
        averageCellValueView values =
            [ Html.div
                [ tableModuleClass
                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "average" ]
                ]
                [ Html.button
                    [ tableModuleClass
                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "average", "button" ]
                    ]
                    (case p.metricsTransposition of
                        MetricsInRows ->
                            values
                                |> String.join " "
                                |> Html.text
                                |> List.singleton

                        MetricsInColumns ->
                            List.map
                                (valueView p.className
                                    { isSortingMetric = False
                                    , shouldBeGreyOut = False
                                    }
                                )
                                values
                    )
                ]
            ]

        metricCellValueView : List ( Metric, String ) -> List (Html msg)
        metricCellValueView metricValues =
            let
                totalRowRespondentsIsLowerThanMinSampleSizeForRows : Bool
                totalRowRespondentsIsLowerThanMinSampleSizeForRows =
                    p.totalRowRespondents
                        < (Optional.toMaybe p.minimumSampleSize.rows
                            |> Maybe.withDefault 0
                          )

                totalColRespondentsIsLowerThanMinSampleSizeForColumns : Bool
                totalColRespondentsIsLowerThanMinSampleSizeForColumns =
                    p.totalColRespondents
                        < (Optional.toMaybe p.minimumSampleSize.columns
                            |> Maybe.withDefault 0
                          )

                shouldGreyOutSize : Bool
                shouldGreyOutSize =
                    -- Universe
                    checkIfCellPassesMinSampleSize p.minimumSampleSize cell
                        || totalRowRespondentsIsLowerThanMinSampleSizeForRows
                        || totalColRespondentsIsLowerThanMinSampleSizeForColumns

                shouldGreyOutSample : Bool
                shouldGreyOutSample =
                    -- Responses
                    checkIfCellPassesMinSampleSize p.minimumSampleSize cell
                        || (totalRowRespondentsIsLowerThanMinSampleSizeForRows
                                && totalColRespondentsIsLowerThanMinSampleSizeForColumns
                           )

                shouldGreyOutColumnPercentage : Bool
                shouldGreyOutColumnPercentage =
                    checkIfCellPassesMinSampleSize p.minimumSampleSize cell
                        || totalColRespondentsIsLowerThanMinSampleSizeForColumns

                shouldGreyOutRowPercentage : Bool
                shouldGreyOutRowPercentage =
                    checkIfCellPassesMinSampleSize p.minimumSampleSize cell
                        || totalRowRespondentsIsLowerThanMinSampleSizeForRows

                shouldGreyOutIndex : Bool
                shouldGreyOutIndex =
                    checkIfCellPassesMinSampleSize p.minimumSampleSize cell
                        || totalRowRespondentsIsLowerThanMinSampleSizeForRows
                        || totalColRespondentsIsLowerThanMinSampleSizeForColumns
            in
            case p.metricsTransposition of
                MetricsInRows ->
                    if isSortingByThisCell then
                        case List.uncons metricValues of
                            Nothing ->
                                []

                            Just ( ( metric, value ), rest ) ->
                                if Just metric == sortingMetric then
                                    [ Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                                        (totalVsTotalDatasetWarningIcon { isColumns = False })
                                    , Html.span
                                        [ tableModuleClass
                                            |> WeakCss.add "sorted-by"
                                            |> WeakCss.withStates [ ( "total", isTotalCell ) ]
                                        ]
                                        [ Html.text value ]
                                    , Html.text "\n"
                                    ]
                                        ++ (rest
                                                |> List.map
                                                    (\( metric_, value_ ) ->
                                                        case metric_ of
                                                            Sample ->
                                                                Html.button
                                                                    [ Events.onClick p.toggleExactRespondentNumberMsg
                                                                    , tableModuleClass
                                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "sample" ]
                                                                    , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                                    , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                                    ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            Index ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutIndex (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            Size ->
                                                                Html.button
                                                                    [ Events.onClick p.toggleExactUniverseNumberMsg
                                                                    , tableModuleClass
                                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "size" ]
                                                                    , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                                    , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                                    ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            RowPercentage ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutRowPercentage (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            ColumnPercentage ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutColumnPercentage (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]
                                                    )
                                           )

                                else
                                    Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                                        (totalVsTotalDatasetWarningIcon { isColumns = False })
                                        :: (metricValues
                                                |> List.map
                                                    (\( metric_, value_ ) ->
                                                        case metric_ of
                                                            Sample ->
                                                                Html.button
                                                                    [ Events.onClick p.toggleExactRespondentNumberMsg
                                                                    , tableModuleClass
                                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "sample" ]
                                                                    , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                                    , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                                    ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            Index ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutIndex (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            Size ->
                                                                Html.button
                                                                    [ Events.onClick p.toggleExactUniverseNumberMsg
                                                                    , tableModuleClass
                                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "size" ]
                                                                    , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                                    , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                                    ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            RowPercentage ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutRowPercentage (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]

                                                            ColumnPercentage ->
                                                                Html.span
                                                                    [ Attrs.attributeIf shouldGreyOutColumnPercentage (Attrs.style "opacity" "0.15") ]
                                                                    [ Html.text <| value_ ++ "\n" ]
                                                    )
                                           )

                    else
                        Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                            (totalVsTotalDatasetWarningIcon { isColumns = False })
                            :: (metricValues
                                    |> List.map
                                        (\( metric, value ) ->
                                            case metric of
                                                Sample ->
                                                    Html.button
                                                        [ Events.onClick p.toggleExactRespondentNumberMsg
                                                        , tableModuleClass
                                                            |> WeakCss.nestMany [ "table", p.className, "row", "item", "sample" ]
                                                        , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                        , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                        ]
                                                        [ Html.text <| value ++ "\n" ]

                                                Index ->
                                                    Html.span
                                                        [ Attrs.attributeIf shouldGreyOutIndex (Attrs.style "opacity" "0.15") ]
                                                        [ Html.text <| value ++ "\n" ]

                                                Size ->
                                                    Html.button
                                                        [ Events.onClick p.toggleExactUniverseNumberMsg
                                                        , tableModuleClass
                                                            |> WeakCss.nestMany [ "table", p.className, "row", "item", "size" ]
                                                        , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                        , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                        ]
                                                        [ Html.text <| value ++ "\n" ]

                                                RowPercentage ->
                                                    Html.span
                                                        [ Attrs.attributeIf shouldGreyOutRowPercentage (Attrs.style "opacity" "0.15") ]
                                                        [ Html.text <| value ++ "\n" ]

                                                ColumnPercentage ->
                                                    Html.span
                                                        [ Attrs.attributeIf shouldGreyOutColumnPercentage (Attrs.style "opacity" "0.15") ]
                                                        [ Html.text <| value ++ "\n" ]
                                        )
                               )

                MetricsInColumns ->
                    if isSortingByThisCell then
                        case List.uncons metricValues of
                            Nothing ->
                                []

                            Just ( ( metric, value ), rest ) ->
                                if Just metric == sortingMetric then
                                    [ Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                                        (totalVsTotalDatasetWarningIcon { isColumns = True })
                                    , valueView p.className
                                        { isSortingMetric = True
                                        , shouldBeGreyOut = False
                                        }
                                        value
                                    ]
                                        ++ List.map
                                            (\( metric_, value_ ) ->
                                                case metric_ of
                                                    Sample ->
                                                        Html.div
                                                            [ tableModuleClass
                                                                |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                            ]
                                                            [ Html.button
                                                                [ Events.onClick p.toggleExactRespondentNumberMsg
                                                                , tableModuleClass
                                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "sample" ]
                                                                , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                                , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                                ]
                                                                [ Html.text <| value_ ++ "\n" ]
                                                            ]

                                                    Index ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutIndex
                                                            }
                                                            value_

                                                    Size ->
                                                        Html.div
                                                            [ tableModuleClass
                                                                |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                            ]
                                                            [ Html.button
                                                                [ Events.onClick p.toggleExactUniverseNumberMsg
                                                                , tableModuleClass
                                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "size" ]
                                                                , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                                , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                                ]
                                                                [ Html.text <| value_ ++ "\n" ]
                                                            ]

                                                    RowPercentage ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutRowPercentage
                                                            }
                                                            value_

                                                    ColumnPercentage ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutColumnPercentage
                                                            }
                                                            value_
                                            )
                                            rest

                                else
                                    Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                                        (totalVsTotalDatasetWarningIcon { isColumns = True })
                                        :: List.map
                                            (\( metric_, value_ ) ->
                                                case metric_ of
                                                    Sample ->
                                                        Html.div
                                                            [ tableModuleClass
                                                                |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                            ]
                                                            [ Html.button
                                                                [ Events.onClick p.toggleExactRespondentNumberMsg
                                                                , tableModuleClass
                                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "sample" ]
                                                                , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                                , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                                ]
                                                                [ Html.text <| value_ ++ "\n" ]
                                                            ]

                                                    Index ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutIndex
                                                            }
                                                            value_

                                                    Size ->
                                                        Html.div
                                                            [ tableModuleClass
                                                                |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                            ]
                                                            [ Html.button
                                                                [ Events.onClick p.toggleExactUniverseNumberMsg
                                                                , tableModuleClass
                                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "size" ]
                                                                , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                                , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                                ]
                                                                [ Html.text <| value_ ++ "\n" ]
                                                            ]

                                                    RowPercentage ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutRowPercentage
                                                            }
                                                            value_

                                                    ColumnPercentage ->
                                                        valueView p.className
                                                            { isSortingMetric = False
                                                            , shouldBeGreyOut = shouldGreyOutColumnPercentage
                                                            }
                                                            value_
                                            )
                                            metricValues

                    else
                        Html.viewIf (isTotalVsTotalCell && p.areDatasetsIncompatible)
                            (totalVsTotalDatasetWarningIcon { isColumns = True })
                            :: List.map
                                (\( metric, value_ ) ->
                                    case metric of
                                        Sample ->
                                            Html.div
                                                [ tableModuleClass
                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                ]
                                                [ Html.button
                                                    [ Events.onClick p.toggleExactRespondentNumberMsg
                                                    , tableModuleClass
                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "sample" ]
                                                    , Attrs.title "Click on your sample sizes to show the exact numbers."
                                                    , Attrs.attributeIf shouldGreyOutSample (Attrs.style "opacity" "0.15")
                                                    ]
                                                    [ Html.text <| value_ ++ "\n" ]
                                                ]

                                        Index ->
                                            valueView p.className
                                                { isSortingMetric = False
                                                , shouldBeGreyOut = shouldGreyOutIndex
                                                }
                                                value_

                                        Size ->
                                            Html.div
                                                [ tableModuleClass
                                                    |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                                ]
                                                [ Html.button
                                                    [ Events.onClick p.toggleExactUniverseNumberMsg
                                                    , tableModuleClass
                                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "value", "size" ]
                                                    , Attrs.title "Click on your universe sizes to show the exact numbers."
                                                    , Attrs.attributeIf shouldGreyOutSize (Attrs.style "opacity" "0.15")
                                                    ]
                                                    [ Html.text <| value_ ++ "\n" ]
                                                ]

                                        RowPercentage ->
                                            valueView p.className
                                                { isSortingMetric = False
                                                , shouldBeGreyOut = shouldGreyOutRowPercentage
                                                }
                                                value_

                                        ColumnPercentage ->
                                            valueView p.className
                                                { isSortingMetric = False
                                                , shouldBeGreyOut = shouldGreyOutColumnPercentage
                                                }
                                                value_
                                )
                                metricValues

        cellTrackedDataView :
            (result -> Html msg)
            -> Tracked.WebData XBQueryError result
            -> Html msg
        cellTrackedDataView resultView data =
            case data of
                Tracked.Success result ->
                    resultView result

                Tracked.Failure ((OtherError XBAvgVsAvgNotSupported) as err) ->
                    singleNAErrorView err

                Tracked.Failure err ->
                    if isAverageCell then
                        singleNAErrorView err

                    else
                        List.repeat (List.length p.metrics)
                            (Html.div [ cellClass |> WeakCss.nest "value" ] [ Html.text "N/A" ])
                            |> (::) (notAvailableWarningIcon err)
                            |> Html.li [ cellClassAttr ]

                Tracked.Loading _ ->
                    if cell.isVisible then
                        Html.li [ cellClassAttr ] p.loaderContent

                    else
                        Html.li [ cellClassAttr ] p.notAnimatedLoaderContent

                Tracked.NotAsked ->
                    Html.li [ cellClassAttr ] p.notAnimatedLoaderContent
    in
    case cell.data of
        AvAData data ->
            let
                isInDebugMode : Bool
                isInDebugMode =
                    RemoteData.unwrap False .showDetailTableInDebugMode p.userSettings

                incompatibilitiesWarningView : Html msg
                incompatibilitiesWarningView =
                    case cell.data of
                        AvAData avaData ->
                            case avaData.incompatibilities of
                                Tracked.Success incompatibilities ->
                                    if List.isEmpty incompatibilities then
                                        Html.nothing

                                    else
                                        let
                                            warningContent : Common.TableWarning msg
                                            warningContent =
                                                Common.GenericTableWarning
                                                    { count = List.length incompatibilities
                                                    , content =
                                                        generateMarkdownForIncompatibilities incompatibilities
                                                            |> Markdown.toHtml []
                                                    , additionalNotice =
                                                        Just <|
                                                            Html.div []
                                                                [ Html.text "The below warning means that your specific combination of attributes was not asked in certain waves and locations, however the data "
                                                                , Html.strong [] [ Html.text "is still valid" ]
                                                                , Html.text "."
                                                                ]
                                                    }
                                        in
                                        warningIcon
                                            { onClick =
                                                p.openTableWarning
                                                    { warning = warningContent
                                                    , row = AudienceItem.getDefinition p.row.item
                                                    , column = AudienceItem.getDefinition p.column.item
                                                    }
                                            }

                                Tracked.Failure _ ->
                                    {- TODO: handle incompatibilities error ? Do we need show
                                       something or rather ignore it?
                                    -}
                                    Html.nothing

                                Tracked.Loading _ ->
                                    {- TODO: handle incompatibilities loading ? Do we need show
                                       something or rather ignore it?
                                    -}
                                    Html.nothing

                                Tracked.NotAsked ->
                                    Html.nothing

                        AverageData _ ->
                            Html.nothing
            in
            cellTrackedDataView
                (\value ->
                    p.metrics
                        |> List.map
                            (\m ->
                                ( m
                                , if isInDebugMode then
                                    "{ "
                                        ++ String.fromInt p.rowIndex
                                        ++ "/"
                                        ++ String.fromInt p.colIndex
                                        ++ " }"

                                  else
                                    AudienceIntersect.formatValue value
                                        m
                                        { exactRespondentNumber =
                                            p.shouldShowExactRespondentNumber
                                        , exactUniverseNumber =
                                            p.shouldShowExactUniverseNumber
                                        , isForRowMetricView =
                                            p.metricsTransposition == MetricsInRows
                                        }
                                )
                            )
                        |> metricCellValueView
                        |> (::) incompatibilitiesWarningView
                        |> (::) (coefficientStretchingView value)
                        |> Html.li (cellClassAttr :: heatmapColorAttrs p.heatmapScale p.column p.row cell)
                )
                data.data

        AverageData avgData ->
            cellTrackedDataView
                (\averageResult ->
                    case averageResult.unit of
                        AgreementScore ->
                            [ XB2.Share.Gwi.FormatNumber.formatXBAverage averageResult.value
                            , "agreement score"
                            ]
                                |> averageCellValueView
                                |> Html.li
                                    [ cellClassAttr
                                    , Attrs.title agreementScoreTooltip
                                    ]

                        TimeInHours ->
                            [ Html.div
                                [ tableModuleClass
                                    |> WeakCss.addMany [ "table", p.className, "row", "item", "average" ]
                                    |> WeakCss.withActiveStates [ "time" ]
                                ]
                                [ Html.div
                                    [ tableModuleClass
                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                    ]
                                    [ Html.span
                                        [ tableModuleClass
                                            |> WeakCss.nestMany [ "table", p.className, "row", "item", "togglable-value" ]
                                        , Events.onClick p.switchAverageTimeFormatMsg
                                        , Attrs.title "Click on your average values to change their format."
                                        ]
                                        [ Html.text <| Average.averageTimeToString p.averageTimeFormat averageResult.value
                                        ]
                                    ]
                                , Html.span
                                    [ tableModuleClass
                                        |> WeakCss.nestMany [ "table", p.className, "row", "item", "value" ]
                                    ]
                                    [ Html.text <|
                                        if p.metricsTransposition == MetricsInColumns then
                                            "hours"

                                        else
                                            "\u{00A0}hours"
                                    ]
                                ]
                            ]
                                |> Html.li [ cellClassAttr ]

                        OtherUnit unit ->
                            [ XB2.Share.Gwi.FormatNumber.formatXBAverage averageResult.value
                            , unit
                            ]
                                |> averageCellValueView
                                |> Html.li [ cellClassAttr ]
                )
                avgData


agreementScoreTooltip : String
agreementScoreTooltip =
    """Strongly agree: 2
Somewhat agree: 1
Neither agree nor disagree: 0
Somewhat disagree: -1
Strongly disagree: -2
"""



-- Table views


totalsHeader : Key
totalsHeader =
    { item = AudienceItem.totalItem, isSelected = False }


listSplice : Int -> Int -> List a -> List a
listSplice from to list =
    List.drop from list
        |> List.take to


getOnlyVisible : Direction -> VisibleCells -> List a -> List a
getOnlyVisible colOrRow visibleCells list =
    case colOrRow of
        Row ->
            listSplice visibleCells.topLeftRow (visibleCells.bottomRightRow - visibleCells.topLeftRow + 1) list

        Column ->
            listSplice visibleCells.topLeftCol (visibleCells.bottomRightCol - visibleCells.topLeftCol + 1) list


headersView :
    { config : Config model msg }
    ->
        { colOrRow : Direction
        , className : String
        , p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , startingIndex : Int
        , sort : Sort
        , selectedItems : Maybe MovableItems
        , items : List Key
        , dndListModel : DnDListModel
        , metricsTransposition : MetricsTransposition
        , metrics_ : List Metric
        , dropdownMenu : DropdownMenu msg
        , selectionMap : SelectionMap
        , crosstab : AudienceCrosstab
        , searchProps : CrosstabSearchProps
        }
    -> Html msg
headersView triggers params =
    let
        metrics : List Metric
        metrics =
            case ( params.colOrRow, params.metricsTransposition ) of
                ( Column, MetricsInColumns ) ->
                    params.metrics_

                ( Row, MetricsInRows ) ->
                    params.metrics_

                ( Column, MetricsInRows ) ->
                    []

                ( Row, MetricsInColumns ) ->
                    []

        isLastHeader : Int -> Bool
        isLastHeader idx =
            case params.colOrRow of
                Row ->
                    idx == ACrosstab.rowCountWithoutTotals params.crosstab

                Column ->
                    idx == ACrosstab.colCountWithoutTotals params.crosstab
    in
    params.items
        |> List.indexedMap
            (\index key ->
                let
                    finalIndex : Int
                    finalIndex =
                        case params.colOrRow of
                            Row ->
                                index + params.startingIndex

                            Column ->
                                index + params.startingIndex
                in
                keyedHeaderView
                    { config = triggers.config }
                    { p2Store = params.p2Store
                    , frozenRowsAndColumns = params.frozenRowsAndColumns
                    , remoteUserSettings = params.remoteUserSettings
                    , className = params.className
                    , sort = params.sort
                    , dndListModel = params.dndListModel
                    , selectedItems = params.selectedItems
                    , selectionMap = params.selectionMap
                    , isLastHeader = isLastHeader finalIndex
                    , direction = params.colOrRow
                    , metrics = metrics
                    , metricsTransposition = params.metricsTransposition
                    , dropdownMenu = params.dropdownMenu
                    , index = finalIndex
                    , key = key
                    , numberOfRowsAndCols =
                        { rows = ACrosstab.rowCountWithoutTotals params.crosstab
                        , cols = ACrosstab.colCountWithoutTotals params.crosstab
                        }
                    , searchProps = params.searchProps
                    }
            )
        |> Html.Keyed.ul [ tableModuleClass |> WeakCss.nestMany [ "table", params.className, "partial" ] ]
        |> List.singleton
        |> Html.div [ WeakCss.nestMany [ "table", params.className ] tableModuleClass ]


headersRowsView :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , startingIndex : Int
        , sort : Sort
        , selectedItems : Maybe MovableItems
        , items : List Key
        , dndListModel : DnDListModel
        , metricsTransposition : MetricsTransposition
        , metrics_ : List Metric
        , dropdownMenu : DropdownMenu msg
        , selectionMap : SelectionMap
        , crosstab : AudienceCrosstab
        , searchProps : CrosstabSearchProps
        }
    -> Html msg
headersRowsView triggers params =
    headersView triggers
        { colOrRow = Row
        , className = "rows"
        , p2Store = params.p2Store
        , frozenRowsAndColumns = params.frozenRowsAndColumns
        , remoteUserSettings = params.remoteUserSettings
        , startingIndex = params.startingIndex
        , sort = params.sort
        , selectedItems = params.selectedItems
        , items = params.items
        , dndListModel = params.dndListModel
        , metricsTransposition = params.metricsTransposition
        , metrics_ = params.metrics_
        , dropdownMenu = params.dropdownMenu
        , selectionMap = params.selectionMap
        , crosstab = params.crosstab
        , searchProps = params.searchProps
        }


headersFrozenTotalRowsView :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , startingIndex : Int
        , sort : Sort
        , selectedItems : Maybe MovableItems
        , items : List Key
        , dndListModel : DnDListModel
        , metricsTransposition : MetricsTransposition
        , metrics_ : List Metric
        , dropdownMenu : DropdownMenu msg
        , selectionMap : SelectionMap
        , crosstab : AudienceCrosstab
        , searchProps : CrosstabSearchProps
        }
    -> Html msg
headersFrozenTotalRowsView triggers params =
    headersView triggers
        { colOrRow = Row
        , className = "frozen-total-rows"
        , p2Store = params.p2Store
        , frozenRowsAndColumns = params.frozenRowsAndColumns
        , remoteUserSettings = params.remoteUserSettings
        , startingIndex = params.startingIndex
        , sort = params.sort
        , selectedItems = params.selectedItems
        , items = params.items
        , dndListModel = params.dndListModel
        , metricsTransposition = params.metricsTransposition
        , metrics_ = params.metrics_
        , dropdownMenu = params.dropdownMenu
        , selectionMap = params.selectionMap
        , crosstab = params.crosstab
        , searchProps = params.searchProps
        }


headersFrozenTotalColsView :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , startingIndex : Int
        , sort : Sort
        , selectedItems : Maybe MovableItems
        , items : List Key
        , dndListModel : DnDListModel
        , metricsTransposition : MetricsTransposition
        , metrics_ : List Metric
        , dropdownMenu : DropdownMenu msg
        , selectionMap : SelectionMap
        , crosstab : AudienceCrosstab
        , searchProps : CrosstabSearchProps
        }
    -> Html msg
headersFrozenTotalColsView triggers params =
    headersView triggers
        { colOrRow = Column
        , className = "frozen-total-cols"
        , p2Store = params.p2Store
        , frozenRowsAndColumns = params.frozenRowsAndColumns
        , remoteUserSettings = params.remoteUserSettings
        , startingIndex = params.startingIndex
        , sort = params.sort
        , selectedItems = params.selectedItems
        , items = params.items
        , dndListModel = params.dndListModel
        , metricsTransposition = params.metricsTransposition
        , metrics_ = params.metrics_
        , dropdownMenu = params.dropdownMenu
        , selectionMap = params.selectionMap
        , crosstab = params.crosstab
        , searchProps = params.searchProps
        }


headersColumnsView :
    { config : Config model msg }
    ->
        { p2Store : XB2.Share.Store.Platform2.Store
        , frozenRowsAndColumns : ( Int, Int )
        , remoteUserSettings : WebData XBUserSettings
        , startingIndex : Int
        , sort : Sort
        , selectedItems : Maybe MovableItems
        , items : List Key
        , dndListModel : DnDListModel
        , metricsTransposition : MetricsTransposition
        , metrics_ : List Metric
        , dropdownMenu : DropdownMenu msg
        , selectionMap : SelectionMap
        , crosstab : AudienceCrosstab
        , searchProps : CrosstabSearchProps
        }
    -> Html msg
headersColumnsView triggers params =
    headersView triggers
        { colOrRow = Column
        , className = "cols"
        , p2Store = params.p2Store
        , frozenRowsAndColumns = params.frozenRowsAndColumns
        , remoteUserSettings = params.remoteUserSettings
        , startingIndex = params.startingIndex
        , sort = params.sort
        , selectedItems = params.selectedItems
        , items = params.items
        , dndListModel = params.dndListModel
        , metricsTransposition = params.metricsTransposition
        , metrics_ = params.metrics_
        , dropdownMenu = params.dropdownMenu
        , selectionMap = params.selectionMap
        , crosstab = params.crosstab
        , searchProps = params.searchProps
        }


frozenCellsView :
    { visibleCells : VisibleCells
    , sort : Sort
    , rowHeaders : List Key
    , columnHeaders : List Key
    , heatmapScale : Maybe HeatmapScale
    , minimumSampleSize : MinimumSampleSize
    , crosstab : AudienceCrosstab
    , metrics : List Metric
    , metricsTransposition : MetricsTransposition
    , forcedLoadingState : Bool
    , dndInfo : Maybe (XB2.Share.DragAndDrop.Move.Info Direction MovableItems)
    , switchAverageTimeFormatMsg : msg
    , openTableWarning : { warning : Common.TableWarning msg, row : AudienceDefinition, column : AudienceDefinition } -> msg
    , averageTimeFormat : AverageTimeFormat
    , areDatasetsIncompatible : Bool
    , can : Can
    , store : XB2.Share.Store.Platform2.Store
    , selectionMap : SelectionMap
    , shouldShowExactRespondentNumber : Bool
    , shouldShowExactUniverseNumber : Bool
    , toggleExactRespondentNumberMsg : msg
    , toggleExactUniverseNumberMsg : msg
    , updateUserSettingsMsg : XBUserSettings -> msg
    , userSettings : WebData XBUserSettings
    , className : String
    , startingRowIndex : Int
    , startingColIndex : Int
    }
    -> Html msg
frozenCellsView p =
    let
        base : BaseAudience
        base =
            ACrosstab.getCurrentBaseAudience p.crosstab

        metricsLength : Int
        metricsLength =
            List.length p.metrics

        loaderContent : List (Html msg)
        loaderContent =
            loaderViewContent p.className True metricsLength

        notAnimatedLoaderHtml : List (Html msg)
        notAnimatedLoaderHtml =
            loaderViewContent p.className False metricsLength
    in
    p.rowHeaders
        |> List.indexedMap
            (\rowIndex row ->
                let
                    finalRowIndex : Int
                    finalRowIndex =
                        rowIndex + p.startingRowIndex
                in
                p.columnHeaders
                    |> List.indexedMap
                        (\columnIndex column ->
                            let
                                finalColumnIndex : Int
                                finalColumnIndex =
                                    columnIndex + p.startingColIndex

                                getTotalRespondents : AudienceItem.AudienceItem -> BaseAudience -> Int
                                getTotalRespondents audienceItem baseAudience =
                                    case Dict.Any.get ( audienceItem, baseAudience ) (ACrosstab.getTotals p.crosstab) of
                                        Just cell ->
                                            case cell.data of
                                                AvAData data ->
                                                    case data.data of
                                                        Tracked.Success intersectResult ->
                                                            round (AudienceIntersect.getValue Sample intersectResult)

                                                        Tracked.NotAsked ->
                                                            0

                                                        Tracked.Loading _ ->
                                                            0

                                                        Tracked.Failure _ ->
                                                            0

                                                AverageData _ ->
                                                    0

                                        Nothing ->
                                            0
                            in
                            cellView
                                { switchAverageTimeFormatMsg = p.switchAverageTimeFormatMsg
                                , openTableWarning = p.openTableWarning
                                , averageTimeFormat = p.averageTimeFormat
                                , loaderContent = loaderContent
                                , notAnimatedLoaderContent = notAnimatedLoaderHtml
                                , sort = p.sort
                                , metricsTransposition = p.metricsTransposition
                                , crosstab = p.crosstab
                                , metrics = p.metrics
                                , heatmapScale = p.heatmapScale
                                , minimumSampleSize = p.minimumSampleSize
                                , totalRowRespondents = getTotalRespondents row.item base
                                , totalColRespondents = getTotalRespondents column.item base
                                , base = base
                                , column = column
                                , row = row
                                , selectionMap = p.selectionMap
                                , rowIndex = finalRowIndex
                                , colIndex = finalColumnIndex
                                , dndInfo = p.dndInfo
                                , forcedLoadingState = p.forcedLoadingState
                                , areDatasetsIncompatible = p.areDatasetsIncompatible
                                , can = p.can
                                , store = p.store
                                , shouldShowExactRespondentNumber = p.shouldShowExactRespondentNumber
                                , shouldShowExactUniverseNumber = p.shouldShowExactUniverseNumber
                                , toggleExactRespondentNumberMsg = p.toggleExactRespondentNumberMsg
                                , toggleExactUniverseNumberMsg = p.toggleExactUniverseNumberMsg
                                , updateUserSettingsMsg = p.updateUserSettingsMsg
                                , userSettings = p.userSettings
                                , className = p.className
                                }
                        )
                    |> Html.ul
                        [ tableModuleClass
                            |> WeakCss.addMany [ "table", p.className, "row" ]
                            |> WeakCss.withStates
                                [ ( "scrolled-x", p.visibleCells.topLeftCol > 0 )
                                , ( "scrolled-y", p.visibleCells.topLeftRow > 0 )
                                , ( "even", modBy 2 finalRowIndex > 0 )
                                ]
                        ]
            )
        |> Html.div [ tableModuleClass |> WeakCss.nestMany [ "table", p.className, "partial" ] ]
        |> List.singleton
        |> Html.div [ tableModuleClass |> WeakCss.nestMany [ "table", p.className ] ]


cellsView :
    { visibleCells : VisibleCells
    , sort : Sort
    , rowHeaders : List Key
    , columnHeaders : List Key
    , heatmapScale : Maybe HeatmapScale
    , minimumSampleSize : MinimumSampleSize
    , crosstab : AudienceCrosstab
    , metrics : List Metric
    , metricsTransposition : MetricsTransposition
    , forcedLoadingState : Bool
    , dndInfo : Maybe (XB2.Share.DragAndDrop.Move.Info Direction MovableItems)
    , switchAverageTimeFormatMsg : msg
    , openTableWarning : { warning : Common.TableWarning msg, row : AudienceDefinition, column : AudienceDefinition } -> msg
    , averageTimeFormat : AverageTimeFormat
    , areDatasetsIncompatible : Bool
    , can : Can
    , store : XB2.Share.Store.Platform2.Store
    , selectionMap : SelectionMap
    , shouldShowExactRespondentNumber : Bool
    , shouldShowExactUniverseNumber : Bool
    , toggleExactRespondentNumberMsg : msg
    , toggleExactUniverseNumberMsg : msg
    , updateUserSettingsMsg : XBUserSettings -> msg
    , userSettings : WebData XBUserSettings
    , frozenRowsAndColumns : ( Int, Int )
    , className : String
    }
    -> Html msg
cellsView p =
    let
        base : BaseAudience
        base =
            ACrosstab.getCurrentBaseAudience p.crosstab

        metricsLength : Int
        metricsLength =
            List.length p.metrics

        loaderContent : List (Html msg)
        loaderContent =
            loaderViewContent p.className True metricsLength

        notAnimatedLoaderHtml : List (Html msg)
        notAnimatedLoaderHtml =
            loaderViewContent p.className False metricsLength
    in
    p.rowHeaders
        |> List.indexedMap
            (\rowIndex row ->
                let
                    finalRowIndex : Int
                    finalRowIndex =
                        rowIndex + Tuple.first p.frozenRowsAndColumns + p.visibleCells.topLeftRow
                in
                p.columnHeaders
                    |> List.indexedMap
                        (\columnIndex column ->
                            let
                                finalColIndex : Int
                                finalColIndex =
                                    columnIndex + Tuple.second p.frozenRowsAndColumns + p.visibleCells.topLeftCol

                                getTotalRespondents : AudienceItem.AudienceItem -> BaseAudience -> Int
                                getTotalRespondents audienceItem baseAudience =
                                    case Dict.Any.get ( audienceItem, baseAudience ) (ACrosstab.getTotals p.crosstab) of
                                        Just cell ->
                                            case cell.data of
                                                AvAData data ->
                                                    case data.data of
                                                        Tracked.Success intersectResult ->
                                                            round (AudienceIntersect.getValue Sample intersectResult)

                                                        Tracked.NotAsked ->
                                                            0

                                                        Tracked.Loading _ ->
                                                            0

                                                        Tracked.Failure _ ->
                                                            0

                                                AverageData _ ->
                                                    0

                                        Nothing ->
                                            0
                            in
                            cellView
                                { switchAverageTimeFormatMsg = p.switchAverageTimeFormatMsg
                                , openTableWarning = p.openTableWarning
                                , averageTimeFormat = p.averageTimeFormat
                                , loaderContent = loaderContent
                                , notAnimatedLoaderContent = notAnimatedLoaderHtml
                                , sort = p.sort
                                , metricsTransposition = p.metricsTransposition
                                , crosstab = p.crosstab
                                , metrics = p.metrics
                                , heatmapScale = p.heatmapScale
                                , minimumSampleSize = p.minimumSampleSize
                                , totalRowRespondents = getTotalRespondents row.item base
                                , totalColRespondents = getTotalRespondents column.item base
                                , base = base
                                , column = column
                                , row = row
                                , selectionMap = p.selectionMap
                                , rowIndex = finalRowIndex
                                , colIndex = finalColIndex
                                , dndInfo = p.dndInfo
                                , forcedLoadingState = p.forcedLoadingState
                                , areDatasetsIncompatible = p.areDatasetsIncompatible
                                , can = p.can
                                , store = p.store
                                , shouldShowExactRespondentNumber = p.shouldShowExactRespondentNumber
                                , shouldShowExactUniverseNumber = p.shouldShowExactUniverseNumber
                                , toggleExactRespondentNumberMsg = p.toggleExactRespondentNumberMsg
                                , toggleExactUniverseNumberMsg = p.toggleExactUniverseNumberMsg
                                , updateUserSettingsMsg = p.updateUserSettingsMsg
                                , userSettings = p.userSettings
                                , className = p.className
                                }
                        )
                    |> Html.ul
                        [ tableModuleClass
                            |> WeakCss.addMany [ "table", p.className, "row" ]
                            |> WeakCss.withStates
                                [ ( "scrolled-x", p.visibleCells.topLeftCol > 0 )
                                , ( "scrolled-y", p.visibleCells.topLeftRow > 0 )
                                , ( "even", modBy 2 finalRowIndex > 0 )
                                ]
                        ]
            )
        |> Html.div [ tableModuleClass |> WeakCss.nestMany [ "table", p.className, "partial" ] ]
        |> List.singleton
        |> Html.div [ tableModuleClass |> WeakCss.nestMany [ "table", p.className ], Attrs.id Common.tableCellsElementId ]


rowName : Int -> String
rowName n =
    String.fromInt <| n + 1


columnName : Int -> Maybe String
columnName n =
    ColumnLabel.fromInt n


verticalTooltipContent : VisibleCells -> Int -> String
verticalTooltipContent cells rowsCount =
    "Cells "
        ++ rowName cells.topLeftRow
        ++ "-"
        ++ rowName (min cells.bottomRightRow rowsCount)


horizontalTooltipContent : VisibleCells -> Int -> String
horizontalTooltipContent cells columnsCount =
    Maybe.map2
        (\from to ->
            "Cells "
                ++ from
                ++ "-"
                ++ to
        )
        (columnName cells.topLeftCol)
        (columnName (min cells.bottomRightCol columnsCount))
        -- Nothing would be a bug!
        |> Maybe.withDefault ""


verticalTooltipContentPrev : VisibleCells -> Int -> String
verticalTooltipContentPrev visibleCells =
    verticalTooltipContent
        (PageScroll.up visibleCells)


verticalTooltipContentNext : VisibleCells -> Int -> String
verticalTooltipContentNext visibleCells rowsCount =
    verticalTooltipContent
        (PageScroll.down visibleCells rowsCount)
        rowsCount


horizontalTooltipContentPrev : VisibleCells -> Int -> String
horizontalTooltipContentPrev visibleCells =
    horizontalTooltipContent
        (PageScroll.left visibleCells)


horizontalTooltipContentNext : VisibleCells -> Int -> String
horizontalTooltipContentNext visibleCells columnsCount =
    horizontalTooltipContent
        (PageScroll.right visibleCells columnsCount)
        columnsCount



{--
    Let's describes how table cells are dynamically loaded based on the user's view
    and how updates are managed efficiently to optimize performance.

    Cell Loading Mechanism
        Cells in the table are loaded dynamically depending on the user's viewport. As the user
        navigates through the table, additional cells are fetched in bulk using the Bulk API.
        This approach is implemented to enhance performance by only loading the necessary data
        rather than the entire dataset at once.

    Data Updates
        When a user modifies any data, row, or column, only the affected fields are reloaded.
        This selective reloading ensures minimal data transfer and maintains optimal performance.

        Major Updates
        For significant changes, such as adding a new database or switching the view from
        vertical to horizontal, all visible data is reloaded. This ensures that the new structure
        is correctly displayed with up-to-date information.

    Loading Requests Handling
        Depending on the data type of request, different data loads are triggered:
        |
        | -> AVA Request: CrosstabBulkAvARequest
        | -> Average Request: AverageRowRequest, AverageColRequest, TotalRowAverageColRequest, TotalColAverageRowRequest, AverageVsAverageRequest
        | -> Total Request: TotalVsTotalRequest 
        | -> Incompatibility Request: IncompatibilityBulkRequest
--}


tableView :
    { config : Config model msg, can : Can }
    ->
        { store : XB2.Share.Store.Platform2.Store
        , xbStore : XBStore.Store
        , model : model
        , visibleCells : VisibleCells
        , forcedLoadingState : Bool
        , crosstab : AudienceCrosstab
        }
    -> Html msg
tableView triggers params =
    let
        dndModel : DnDModel
        dndModel =
            triggers.config.dndModel params.model

        searchProps : CrosstabSearchProps
        searchProps =
            triggers.config.getCrosstabSearchProps params.model

        selectionMap : SelectionMap
        selectionMap =
            triggers.config.getSelectionMap params.model

        tableStates : List ( String, Bool )
        tableStates =
            [ ( "selection-panel-opened", ACrosstab.anySelected params.crosstab )
            , ( "drag-drop-occuring", triggers.config.dnd.info dndModel.list /= Nothing )
            , ( "forced-loading-state", params.forcedLoadingState )
            , ( "is-header-resizing-row", triggers.config.isHeaderResizing Row params.model )
            , ( "is-header-resizing-column", triggers.config.isHeaderResizing Column params.model )
            ]

        selectedMovableItems : Maybe MovableItems
        selectedMovableItems =
            (ACrosstab.getSelectedRows params.crosstab
                |> List.map (Tuple.pair Row)
            )
                ++ (ACrosstab.getSelectedColumns params.crosstab
                        |> List.map (Tuple.pair Column)
                   )
                |> NonemptyList.fromList

        metricsTransposition : MetricsTransposition
        metricsTransposition =
            triggers.config.getMetricsTransposition params.model

        metrics : List Metric
        metrics =
            triggers.config.metrics params.model
                |> reorderMetrics sort

        sort : Sort
        sort =
            triggers.config.getCurrentSort params.model

        coreNamespace : Namespace.Code
        coreNamespace =
            Namespace.coreCode

        coreLineage : Maybe (List Namespace.Code)
        coreLineage =
            Dict.Any.get coreNamespace params.store.lineages
                |> Maybe.andThen RemoteData.toMaybe
                |> Maybe.map (XB2.Share.Data.Labels.mergeLineage coreNamespace)

        isSubsetOfLineage : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code -> List Namespace.Code -> Bool
        isSubsetOfLineage possibleSuperset possibleSubset =
            {- Is everything in `possibleSubset` also present in
               `possibleSuperset`? In our case, is everything in the given lineage
               a subset of the core lineage?
            -}
            Set.Any.diff
                (Set.Any.fromList Namespace.codeToString possibleSubset)
                possibleSuperset
                |> Set.Any.isEmpty

        areDatasetsIncompatible : Bool
        areDatasetsIncompatible =
            case coreLineage of
                Nothing ->
                    False

                Just coreLineage_ ->
                    let
                        coreLineageSet : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
                        coreLineageSet =
                            Set.Any.fromList Namespace.codeToString coreLineage_
                    in
                    BaseAudience.isDefault (ACrosstab.getCurrentBaseAudience params.crosstab)
                        && (params.crosstab
                                |> ACrosstab.namespaceCodesWithBases
                                |> List.filterMap
                                    (\namespaceCode ->
                                        Dict.Any.get namespaceCode params.store.lineages
                                            |> Maybe.andThen RemoteData.toMaybe
                                            |> Maybe.map (Tuple.pair namespaceCode)
                                    )
                                |> List.map (\( namespaceCode, lineage ) -> XB2.Share.Data.Labels.mergeLineage namespaceCode lineage)
                                |> Set.Any.fromList (List.map Namespace.codeToString >> String.join ",")
                                |> Set.Any.filter (not << isSubsetOfLineage coreLineageSet)
                                |> Set.Any.size
                                |> (\size -> size > 0)
                           )

        dropdownMenu : DropdownMenu msg
        dropdownMenu =
            triggers.config.getDropdownMenu params.model

        ( nFrozenRows, nFrozenCols ) =
            triggers.config.getFrozenRowsColumns params.model

        columnHeaders : List Key
        columnHeaders =
            totalsHeader
                :: ACrosstab.getColumns params.crosstab
                |> getOnlyVisible Column params.visibleCells
                |> List.drop nFrozenCols

        frozenColumnHeaders : List Key
        frozenColumnHeaders =
            totalsHeader
                :: ACrosstab.getColumns params.crosstab
                |> List.take nFrozenCols

        rowHeaders : List Key
        rowHeaders =
            totalsHeader
                :: ACrosstab.getRows params.crosstab
                |> getOnlyVisible Row params.visibleCells
                |> List.drop nFrozenRows

        frozenRowHeaders : List Key
        frozenRowHeaders =
            totalsHeader
                :: ACrosstab.getRows params.crosstab
                |> List.take nFrozenRows

        renamingOnboardingView : Html msg
        renamingOnboardingView =
            let
                hasThisBeenSeenInUserSettings : Bool
                hasThisBeenSeenInUserSettings =
                    RemoteData.unwrap False .renamingCellsOnboardingSeen params.xbStore.userSettings

                hasEditABExprBeenSeenInUserSettings : Bool
                hasEditABExprBeenSeenInUserSettings =
                    RemoteData.unwrap False .editAttributeExpressionOnboardingSeen params.xbStore.userSettings

                thereIsAtLeastOneRowHeader : Bool
                thereIsAtLeastOneRowHeader =
                    List.length rowHeaders > 1

                shouldThisBeSeen : Bool
                shouldThisBeSeen =
                    not hasThisBeenSeenInUserSettings && thereIsAtLeastOneRowHeader && hasEditABExprBeenSeenInUserSettings
            in
            Html.viewIf shouldThisBeSeen
                (Html.div [ WeakCss.nestMany [ "table", "renaming-cells" ] tableModuleClass ]
                    [ renamingCellsOnboardingView triggers.config.updateUserSettings params.xbStore.userSettings
                    ]
                )

        editAttributeExprOnboardingView : Html msg
        editAttributeExprOnboardingView =
            let
                beenSeenInUserSettings : Bool
                beenSeenInUserSettings =
                    RemoteData.unwrap False .editAttributeExpressionOnboardingSeen params.xbStore.userSettings

                shouldBeSeen : Bool
                shouldBeSeen =
                    not beenSeenInUserSettings && (List.length rowHeaders > 0 || List.length columnHeaders > 0)
            in
            Html.viewIf shouldBeSeen <|
                Html.div
                    [ WeakCss.addMany [ "table", "edit-ab-exp" ] tableModuleClass
                        |> WeakCss.withStates [ ( "for-row", List.length columnHeaders <= 1 ) ]
                    ]
                    [ Onboarding.viewEditABExpBasedOnUserSettings
                        { updateUserSettingsToMsg = triggers.config.updateUserSettings }
                        { remoteUserSettings = params.xbStore.userSettings
                        , className = WeakCss.addMany [ "table", "edit-ab-exp" ] tableModuleClass
                        }
                    ]

        isInDebugMode : Bool
        isInDebugMode =
            RemoteData.unwrap False .showDetailTableInDebugMode params.xbStore.userSettings
    in
    Html.div
        [ WeakCss.add "table" tableModuleClass
            |> WeakCss.withStates tableStates
        , Attrs.id Common.tableElementId
        , [ ( "--top-left-row", params.visibleCells.topLeftRow )
          , ( "--bottom-right-row", params.visibleCells.bottomRightRow )
          , ( "--top-left-col", params.visibleCells.topLeftCol )
          , ( "--bottom-right-col", params.visibleCells.bottomRightCol )
          , ( "--cells-top-offset", triggers.config.getTableCellsTopOffset params.model )
          ]
            |> List.map (Tuple.mapSecond String.fromInt)
            |> Attrs.cssVars
        ]
        [ viewCornerLazy
            triggers.config
            triggers.can
            params.store
            params.model
        , Html.viewIf
            (nFrozenCols > 0)
            (headersFrozenTotalColsView
                { config = triggers.config }
                { p2Store = params.store
                , frozenRowsAndColumns = ( nFrozenRows, nFrozenCols )
                , remoteUserSettings = params.xbStore.userSettings
                , startingIndex = 0
                , sort = sort
                , selectedItems = selectedMovableItems
                , items = frozenColumnHeaders
                , dndListModel = dndModel.list
                , metricsTransposition = metricsTransposition
                , metrics_ = metrics
                , dropdownMenu = dropdownMenu
                , selectionMap = selectionMap
                , crosstab = params.crosstab
                , searchProps = searchProps
                }
            )
        , headersRowsView
            { config = triggers.config }
            { p2Store = params.store
            , frozenRowsAndColumns = ( nFrozenRows, nFrozenCols )
            , remoteUserSettings = params.xbStore.userSettings
            , startingIndex = nFrozenRows + params.visibleCells.topLeftRow
            , sort = sort
            , selectedItems = selectedMovableItems
            , items = rowHeaders
            , dndListModel = dndModel.list
            , metricsTransposition = metricsTransposition
            , metrics_ = metrics
            , dropdownMenu = dropdownMenu
            , selectionMap = selectionMap
            , crosstab = params.crosstab
            , searchProps = searchProps
            }
        , Html.viewIf
            (nFrozenRows > 0)
            (headersFrozenTotalRowsView
                { config = triggers.config }
                { p2Store = params.store
                , frozenRowsAndColumns = ( nFrozenRows, nFrozenCols )
                , remoteUserSettings = params.xbStore.userSettings
                , startingIndex = 0
                , sort = sort
                , selectedItems = selectedMovableItems
                , items = frozenRowHeaders
                , dndListModel = dndModel.list
                , metricsTransposition = metricsTransposition
                , metrics_ = metrics
                , dropdownMenu = dropdownMenu
                , selectionMap = selectionMap
                , crosstab = params.crosstab
                , searchProps = searchProps
                }
            )
        , headersColumnsView
            { config = triggers.config }
            { p2Store = params.store
            , frozenRowsAndColumns = ( nFrozenRows, nFrozenCols )
            , remoteUserSettings = params.xbStore.userSettings
            , startingIndex = nFrozenCols + params.visibleCells.topLeftCol
            , sort = sort
            , selectedItems = selectedMovableItems
            , items = columnHeaders
            , dndListModel = dndModel.list
            , metricsTransposition = metricsTransposition
            , metrics_ = metrics
            , dropdownMenu = dropdownMenu
            , selectionMap = selectionMap
            , crosstab = params.crosstab
            , searchProps = searchProps
            }
        , Html.viewIf
            (nFrozenRows > 0 && nFrozenCols > 0)
            (frozenCellsView
                { visibleCells = params.visibleCells
                , sort = sort
                , rowHeaders = frozenRowHeaders
                , columnHeaders = frozenColumnHeaders
                , heatmapScale = triggers.config.heatmapScale params.model
                , minimumSampleSize = triggers.config.getMinimumSampleSize params.model
                , crosstab = params.crosstab
                , metrics = metrics
                , metricsTransposition = metricsTransposition
                , forcedLoadingState = params.forcedLoadingState
                , dndInfo = triggers.config.dnd.info dndModel.list
                , switchAverageTimeFormatMsg = triggers.config.switchAverageTimeFormat
                , openTableWarning = triggers.config.openTableWarning
                , averageTimeFormat = triggers.config.getAverageTimeFormat params.model
                , areDatasetsIncompatible = areDatasetsIncompatible
                , can = triggers.can
                , store = params.store
                , selectionMap = selectionMap
                , shouldShowExactRespondentNumber =
                    triggers.config.shouldShowExactRespondentNumber
                        params.model
                , shouldShowExactUniverseNumber =
                    triggers.config.shouldShowExactUniverseNumber
                        params.model
                , toggleExactRespondentNumberMsg = triggers.config.toggleExactRespondentNumberMsg
                , toggleExactUniverseNumberMsg = triggers.config.toggleExactUniverseNumberMsg
                , updateUserSettingsMsg = triggers.config.updateUserSettings
                , userSettings = params.xbStore.userSettings
                , className = "frozen-combined"
                , startingColIndex = 0
                , startingRowIndex = 0
                }
            )
        , Html.viewIf
            (nFrozenRows > 0)
            (frozenCellsView
                { visibleCells = params.visibleCells
                , sort = sort
                , rowHeaders = frozenRowHeaders
                , columnHeaders = columnHeaders
                , heatmapScale = triggers.config.heatmapScale params.model
                , minimumSampleSize = triggers.config.getMinimumSampleSize params.model
                , crosstab = params.crosstab
                , metrics = metrics
                , metricsTransposition = metricsTransposition
                , forcedLoadingState = params.forcedLoadingState
                , dndInfo = triggers.config.dnd.info dndModel.list
                , switchAverageTimeFormatMsg = triggers.config.switchAverageTimeFormat
                , openTableWarning = triggers.config.openTableWarning
                , averageTimeFormat = triggers.config.getAverageTimeFormat params.model
                , areDatasetsIncompatible = areDatasetsIncompatible
                , can = triggers.can
                , store = params.store
                , selectionMap = selectionMap
                , shouldShowExactRespondentNumber =
                    triggers.config.shouldShowExactRespondentNumber
                        params.model
                , shouldShowExactUniverseNumber =
                    triggers.config.shouldShowExactUniverseNumber
                        params.model
                , toggleExactRespondentNumberMsg = triggers.config.toggleExactRespondentNumberMsg
                , toggleExactUniverseNumberMsg = triggers.config.toggleExactUniverseNumberMsg
                , updateUserSettingsMsg = triggers.config.updateUserSettings
                , userSettings = params.xbStore.userSettings
                , className = "frozen-rows"
                , startingColIndex = nFrozenCols + params.visibleCells.topLeftCol
                , startingRowIndex = 0
                }
            )
        , Html.viewIf
            (nFrozenCols > 0)
            (frozenCellsView
                { visibleCells = params.visibleCells
                , sort = sort
                , rowHeaders = rowHeaders
                , columnHeaders = frozenColumnHeaders
                , heatmapScale = triggers.config.heatmapScale params.model
                , minimumSampleSize = triggers.config.getMinimumSampleSize params.model
                , crosstab = params.crosstab
                , metrics = metrics
                , metricsTransposition = metricsTransposition
                , forcedLoadingState = params.forcedLoadingState
                , dndInfo = triggers.config.dnd.info dndModel.list
                , switchAverageTimeFormatMsg = triggers.config.switchAverageTimeFormat
                , openTableWarning = triggers.config.openTableWarning
                , averageTimeFormat = triggers.config.getAverageTimeFormat params.model
                , areDatasetsIncompatible = areDatasetsIncompatible
                , can = triggers.can
                , store = params.store
                , selectionMap = selectionMap
                , shouldShowExactRespondentNumber =
                    triggers.config.shouldShowExactRespondentNumber
                        params.model
                , shouldShowExactUniverseNumber =
                    triggers.config.shouldShowExactUniverseNumber
                        params.model
                , toggleExactRespondentNumberMsg = triggers.config.toggleExactRespondentNumberMsg
                , toggleExactUniverseNumberMsg = triggers.config.toggleExactUniverseNumberMsg
                , updateUserSettingsMsg = triggers.config.updateUserSettings
                , userSettings = params.xbStore.userSettings
                , className = "frozen-cols"
                , startingColIndex = 0
                , startingRowIndex = nFrozenRows + params.visibleCells.topLeftRow
                }
            )
        , cellsView
            { visibleCells = params.visibleCells
            , sort = sort
            , rowHeaders = rowHeaders
            , columnHeaders = columnHeaders
            , heatmapScale = triggers.config.heatmapScale params.model
            , minimumSampleSize = triggers.config.getMinimumSampleSize params.model
            , crosstab = params.crosstab
            , metrics = metrics
            , metricsTransposition = metricsTransposition
            , forcedLoadingState = params.forcedLoadingState
            , dndInfo = triggers.config.dnd.info dndModel.list
            , switchAverageTimeFormatMsg = triggers.config.switchAverageTimeFormat
            , openTableWarning = triggers.config.openTableWarning
            , averageTimeFormat = triggers.config.getAverageTimeFormat params.model
            , areDatasetsIncompatible = areDatasetsIncompatible
            , can = triggers.can
            , store = params.store
            , selectionMap = selectionMap
            , shouldShowExactRespondentNumber =
                triggers.config.shouldShowExactRespondentNumber
                    params.model
            , shouldShowExactUniverseNumber =
                triggers.config.shouldShowExactUniverseNumber
                    params.model
            , toggleExactRespondentNumberMsg = triggers.config.toggleExactRespondentNumberMsg
            , toggleExactUniverseNumberMsg = triggers.config.toggleExactUniverseNumberMsg
            , updateUserSettingsMsg = triggers.config.updateUserSettings
            , userSettings = params.xbStore.userSettings
            , frozenRowsAndColumns = ( nFrozenRows, nFrozenCols )
            , className = "cells"
            }
        , viewGhostHeaderLazy
            { config = triggers.config, dnd = triggers.config.dnd }
            { dndModel = dndModel
            , isInDebugMode = isInDebugMode
            }
        , renamingOnboardingView
        , editAttributeExprOnboardingView
        ]


{-| Renders the top left corner of the Crosstab in a lazy manner. Only gets updated when
changing Dataset filters, which is not that common.

    Renders this part -> [_]A|B|C|D|E|
                         |1|_|_|_|_|_|
                         |2|_|_|_|_|_|
                         |3|_|_|_|_|_|

-}
viewCornerLazy :
    Config model msg
    -> Can
    -> XB2.Share.Store.Platform2.Store
    -> model
    -> Html msg
viewCornerLazy =
    Html.Lazy.lazy4
        (\memoConfig memoCan memoStore memoModel ->
            viewCornerLazyHelp memoConfig memoCan memoStore memoModel
        )


{-| Helper for `viewCornerLazy` function. Use that one instead to render this view.
-}
viewCornerLazyHelp : Config model msg -> Can -> XB2.Share.Store.Platform2.Store -> model -> Html msg
viewCornerLazyHelp config can store model =
    let
        usedNamespaceCodes : List Namespace.Code
        usedNamespaceCodes =
            config.getAllSelected model
                |> List.fastConcatMap (Tuple.second >> ACrosstab.keyNamespaceCodes)

        namespacesUnknownOrIncompatible : Bool
        namespacesUnknownOrIncompatible =
            not (List.isEmpty usedNamespaceCodes)
                && XB2.Share.Data.Labels.areNamespacesIncompatibleOrUnknown
                    store.lineages
                    usedNamespaceCodes

        crosstabData : AudienceCrosstab
        crosstabData =
            config.getCrosstab model

        usedCellsCount : Int
        usedCellsCount =
            if ACrosstab.isEmpty crosstabData then
                0

            else
                ACrosstab.getSizeWithTotals crosstabData
                    * ACrosstab.getBaseAudiencesCount crosstabData

        formatCount : Int -> String
        formatCount =
            let
                usLocale : Locales.Locale
                usLocale =
                    Locales.usLocale
            in
            toFloat
                >> FormatNumber.format
                    { usLocale
                        | decimals = Locales.Exact 0
                    }
    in
    Html.div
        [ WeakCss.nestMany [ "table", "corner" ] tableModuleClass
        , Attrs.id Common.cornerCellId
        ]
        [ Html.div
            [ WeakCss.nestMany [ "table", "corner", "borderlines" ] tableModuleClass ]
            [ Html.div
                [ WeakCss.nestMany
                    [ "table"
                    , "corner"
                    , "borderlines"
                    , "button"
                    , "wrapper"
                    ]
                    tableModuleClass
                ]
                [ Html.div
                    [ WeakCss.nestMany
                        [ "table"
                        , "corner"
                        , "borderlines"
                        , "metadata"
                        ]
                        tableModuleClass
                    ]
                    [ Html.span
                        [ WeakCss.nestMany
                            [ "table"
                            , "corner"
                            , "borderlines"
                            , "metadata"
                            , "datasets"
                            ]
                            tableModuleClass
                        ]
                        [ viewCornerDatasets
                            (ACrosstab.getCrosstabBaseAudiences crosstabData)
                            (ACrosstab.getRows crosstabData)
                            (ACrosstab.getColumns crosstabData)
                            store
                        ]
                    , Html.span
                        [ WeakCss.nestMany
                            [ "table"
                            , "corner"
                            , "borderlines"
                            , "metadata"
                            , "cells-used"
                            ]
                            tableModuleClass
                        ]
                        [ Html.b [] [ Html.text "Cells: " ]
                        , Html.text <|
                            String.join " "
                                [ formatCount usedCellsCount
                                , "of"
                                , formatCount (ACrosstab.crosstabSizeLimit can)
                                , "used"
                                ]
                        ]
                    ]
                , Html.button
                    [ WeakCss.nestMany
                        [ "table"
                        , "corner"
                        , "borderlines"
                        , "button"
                        ]
                        tableModuleClass
                    , Events.onClick config.openAttributeBrowserViaAddAttributeButton
                    , Attrs.disabled namespacesUnknownOrIncompatible
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.plusSign
                    , Html.text "Add an attribute / audience"
                    ]
                ]
            , Html.viewIf namespacesUnknownOrIncompatible <|
                Html.div
                    [ WeakCss.nestMany
                        [ "table"
                        , "corner"
                        , "borderlines"
                        , "tooltip"
                        ]
                        tableModuleClass
                    ]
                    [ Html.text
                        """
                        You have selected columns / rows from incompatible data sets,
                        please select only relevant columns / rows in order to affix.
                        """
                    ]
            ]
        ]


viewCornerDatasets :
    Zipper.Zipper ACrosstab.CrosstabBaseAudience
    -> List ACrosstab.Key
    -> List ACrosstab.Key
    -> XB2.Share.Store.Platform2.Store
    -> Html msg
viewCornerDatasets bases rows columns p2Store =
    let
        audiences : List AudienceDefinition
        audiences =
            rows
                |> List.map (.item >> AudienceItem.getDefinition)
                |> List.append
                    (columns
                        |> List.map
                            (.item
                                >> AudienceItem.getDefinition
                            )
                    )

        expressions : List Expression
        expressions =
            bases
                |> Zipper.map
                    (ACrosstab.unwrapCrosstabBase
                        >> BaseAudience.getExpression
                    )
                |> Zipper.toList

        datasetNames : List String
        datasetNames =
            XB2.Data.getProjectDatasetNames audiences expressions p2Store

        label : String
        label =
            XB2.Share.Plural.fromInt (List.length datasetNames) "Dataset"
                ++ ": "

        datasetsSeparatedByComma : String
        datasetsSeparatedByComma =
            if datasetNames == [] then
                "..."

            else
                List.greedyGroupsOf 4 datasetNames
                    |> List.concat
                    |> String.join ", "
    in
    P2CoolTip.view
        { offset = Nothing
        , type_ = XB2.Share.CoolTip.Normal
        , position = XB2.Share.CoolTip.BottomRight
        , wrapperAttributes = []
        , targetAttributes = []
        , targetHtml =
            [ Html.span
                []
                [ Html.strong
                    [ WeakCss.nestMany
                        [ "table"
                        , "corner"
                        , "borderlines"
                        , "metadata"
                        , "datasets"
                        , "label"
                        ]
                        tableModuleClass
                    ]
                    [ Html.text label ]
                , Html.p
                    [ WeakCss.nestMany
                        [ "table"
                        , "corner"
                        , "borderlines"
                        , "metadata"
                        , "datasets"
                        , "text"
                        ]
                        tableModuleClass
                    ]
                    [ Html.text datasetsSeparatedByComma ]
                ]
            ]
        , tooltipAttributes =
            [ WeakCss.nestMany
                [ "table"
                , "corner"
                , "borderlines"
                , "metadata"
                , "datasets"
                , "text"
                , "tooltip"
                ]
                tableModuleClass
            ]
        , tooltipHtml = Html.text datasetsSeparatedByComma
        }


emptyTableView : Config model msg -> Html msg
emptyTableView config =
    Html.div
        [ WeakCss.nest "empty" tableModuleClass ]
        [ Html.div
            [ WeakCss.nestMany [ "empty", "content" ] tableModuleClass ]
            [ Html.div
                [ WeakCss.nestMany [ "empty", "title" ] tableModuleClass ]
                [ Html.text "Populate your crosstab by adding attributes and audiences" ]
            , Html.div
                [ WeakCss.nestMany [ "empty", "button", "wrapper" ] tableModuleClass ]
                [ Html.button
                    [ WeakCss.nestMany [ "empty", "button" ] tableModuleClass
                    , Events.onClick config.openAttributeBrowserViaAddAttributeButton
                    ]
                    [ Html.span
                        [ WeakCss.nestMany [ "empty", "button", "label" ] tableModuleClass ]
                        [ Html.text "Add an attribute / audience" ]
                    , Html.i
                        [ WeakCss.nestMany [ "empty", "button", "icon" ] tableModuleClass ]
                        [ XB2.Share.Icons.icon [] P2Icons.plusSign ]
                    ]
                ]
            ]
        ]


tableContainerClass : ClassName
tableContainerClass =
    tableModuleClass
        |> WeakCss.add "table-container"


{-| Calculates the line-clamp property for the title/subtitle of the rows/cols headers.
-}
getNumberOfHeaderTitleAndSubtitleLinesBasedOnMetricsLength :
    Int
    ->
        { titleLines : Int
        , subtitleLines : Int
        }
getNumberOfHeaderTitleAndSubtitleLinesBasedOnMetricsLength metricsLength =
    if metricsLength == 5 then
        { titleLines = 3, subtitleLines = 3 }

    else if metricsLength == 4 then
        { titleLines = 2, subtitleLines = 3 }

    else if metricsLength == 3 then
        { titleLines = 2, subtitleLines = 2 }

    else
        { titleLines = 1, subtitleLines = 1 }


gridView :
    { config : Config model msg, can : Can }
    ->
        { showOverlay : Bool
        , forcedLoadingState : Bool
        , store : XB2.Share.Store.Platform2.Store
        , xbStore : XBStore.Store
        , model : model
        }
    -> Html msg
gridView triggers params =
    let
        crosstab : AudienceCrosstab
        crosstab =
            triggers.config.getCrosstab params.model

        ( nFrozenRows, nFrozenCols ) =
            triggers.config.getFrozenRowsColumns params.model

        tableResizeHandlerView : Direction -> Html msg
        tableResizeHandlerView direction =
            Html.div
                [ WeakCss.add "resize-handler" tableContainerClass
                    |> WeakCss.withStates
                        [ ( "is-resizing", triggers.config.isHeaderResizing direction params.model )
                        , ( "vertical", direction == Column )
                        ]
                , Events.on "mousedown" <|
                    Decode.map (triggers.config.tableHeaderResizeStart direction)
                        XB2.Share.DragAndDrop.Move.pagePosition
                , Events.onMouseUp triggers.config.tableHeaderResizeStop
                ]
                [ Html.div
                    [ WeakCss.nestMany
                        [ "resize-handler", "line" ]
                        tableContainerClass
                    ]
                    []
                ]

        { titleLines, subtitleLines } =
            getNumberOfHeaderTitleAndSubtitleLinesBasedOnMetricsLength
                (List.length (triggers.config.metrics params.model))
    in
    if ACrosstab.isEmpty crosstab then
        emptyTableView triggers.config

    else
        let
            metricsTransposition : MetricsTransposition
            metricsTransposition =
                triggers.config.getMetricsTransposition params.model

            visibleCellsForRender : VisibleCells
            visibleCellsForRender =
                ACrosstab.getVisibleCellsForRender crosstab

            visibleCells : VisibleCells
            visibleCells =
                ACrosstab.getVisibleCells crosstab

            containerState : String
            containerState =
                case metricsTransposition of
                    MetricsInColumns ->
                        "metrics-in-cols"

                    MetricsInRows ->
                        "metrics-in-rows"

            columnsCount : Int
            columnsCount =
                ACrosstab.colCountWithoutTotals crosstab + 1

            rowsCount : Int
            rowsCount =
                ACrosstab.rowCountWithoutTotals crosstab + 1
        in
        -- TODO: Check here scrollMessages
        Scrollbar.view
            { scrollId = Common.scrollTableId
            , parentClass = tableModuleClass
            , upMsg = triggers.config.scrollUp
            , downMsg = triggers.config.scrollDown
            , leftMsg = triggers.config.scrollLeft
            , rightMsg = triggers.config.scrollRight
            , hover = triggers.config.hoverScrollbar
            , stopHovering = triggers.config.stopHoveringScrollbar
            , active = triggers.config.isScrolling params.model
            , activeScrollLeft = triggers.config.isScrollingX params.model
            , activeScrollTop = triggers.config.isScrollingY params.model
            , hovered = triggers.config.isScrollbarHovered params.model
            , verticalTooltip = verticalTooltipContent visibleCells rowsCount
            , horizontalTooltip = horizontalTooltipContent visibleCells columnsCount
            , verticalTooltipNext = verticalTooltipContentNext visibleCells rowsCount
            , verticalTooltipPrev = verticalTooltipContentPrev visibleCells rowsCount
            , horizontalTooltipNext = horizontalTooltipContentNext visibleCells columnsCount
            , horizontalTooltipPrev = horizontalTooltipContentPrev visibleCells columnsCount
            , scrollDecoder =
                Decode.map
                    (\v ->
                        triggers.config.tableScroll
                            ( floor v.viewport.x
                            , floor v.viewport.y
                            )
                    )
                    Browser.viewportDecoder
            }
            [ Attrs.cssVars
                [ ( "--columns-count", String.fromInt columnsCount )
                , ( "--rows-count", String.fromInt rowsCount )
                , ( "--metrics-count"
                  , (String.fromInt << List.length)
                        (triggers.config.metrics params.model)
                  )
                , ( "--first-table-column-width"
                  , (String.fromInt <| triggers.config.firstColumnWidth params.model) ++ "px"
                  )
                , ( "--header-column-height"
                  , (String.fromInt <|
                        triggers.config.headerColumnHeight params.model
                    )
                        ++ "px"
                  )
                , ( "--title-lines", String.fromInt titleLines )
                , ( "--subtitle-lines", String.fromInt subtitleLines )
                ]
            ]
            [ tableResizeHandlerView Row, tableResizeHandlerView Column ]
            [ Html.div
                [ tableContainerClass
                    |> WeakCss.withActiveStates
                        [ containerState

                        -- CSS state to keep track of how many metrics are loaded
                        , "metrics-" ++ String.fromInt (List.length <| triggers.config.metrics params.model)
                        , if triggers.config.heatmapScale params.model /= Nothing then
                            "heatmap-active"

                          else
                            "heatmap-disabled"
                        , if triggers.config.hasResizedRowHeader params.model then
                            "resized-row-header"

                          else
                            "not-resized-row-header"
                        , if triggers.config.hasResizedColHeader params.model then
                            "resized-col-header"

                          else
                            "not-resized-col-header"
                        , if nFrozenRows > 0 then
                            "table-has-frozen-rows"

                          else
                            "table-hasnt-frozen-rows"
                        , if nFrozenCols > 0 then
                            "table-has-frozen-cols"

                          else
                            "table-hasnt-frozen-cols"
                        ]
                ]
                [ tableView
                    { config = triggers.config, can = triggers.can }
                    { store = params.store
                    , xbStore = params.xbStore
                    , model = params.model
                    , visibleCells = visibleCellsForRender
                    , forcedLoadingState = params.forcedLoadingState
                    , crosstab = crosstab
                    }
                , Html.viewIf params.showOverlay <|
                    Html.div [ WeakCss.nest "table-overlay" tableModuleClass ] []
                ]
            ]
