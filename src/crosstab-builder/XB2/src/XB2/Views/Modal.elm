port module XB2.Views.Modal exposing
    ( AddAsNewBasesData
    , AffixBaseData
    , AffixBaseGroupData
    , AffixGroupData
    , AttributesModalData
    , AttributesModalType(..)
    , BulkDeleteModalAction
    , ChooseHeatmapMetricData
    , ChooseMetricsData
    , Config
    , ConfirmDeleteProjectData
    , ConfirmDeleteProjectsData
    , ConfirmRemoveBasesData
    , ConfirmRemoveRowsColumnsData
    , CreateFolderData
    , DeleteFolderData
    , DuplicateProjectData
    , EditBaseData
    , EditBaseGroupData
    , EditGroupData
    , ExpandedState
    , GenericAlertData
    , MergeRowOrColumnData
    , Modal(..)
    , MoveToFolderData
    , Msg(..)
    , RenameAverageData
    , RenameFolderData
    , RenameProjectData
    , ReorderBasesModalData
    , SaveAsAudienceData
    , SaveAsCopyProjectData
    , SaveAsItem(..)
    , SaveProjectAsNewData
    , ShareProjectData
    , State(..)
    , ViewBaseGroupData
    , ViewGroupData
    , ViewSettingsAction
    , focus
    , initAddAsNewBases
    , initAttributesAddBaseModal
    , initAttributesAddModal
    , initAttributesAffixBaseModal
    , initAttributesAffixModal
    , initAttributesEditBaseModal
    , initAttributesEditModal
    , initAttributesReplaceDefaultBaseModal
    , initChooseHeatmapMetric
    , initChooseMetrics
    , initConfirmActionWithViewSettings
    , initConfirmAddNewBaseWithViewSettings
    , initConfirmCellsLoadForSorting
    , initConfirmDeleteFolder
    , initConfirmDeleteProject
    , initConfirmDeleteProjects
    , initConfirmFullLoadForExport
    , initConfirmFullLoadForHeatmap
    , initConfirmRemoveBases
    , initConfirmRemoveRowsColumns
    , initConfirmUngroupFolder
    , initConfirmUnshareMe
    , initCreateFolder
    , initDuplicateProject
    , initMergeRowOrColum
    , initMoveOutOfFolder
    , initMoveToFolder
    , initRenameAverage
    , initRenameBaseAudience
    , initRenameFolder
    , initRenameProject
    , initSaveAsAudience
    , initSaveProjectAsNew
    , initSetNameToNewProject
    , initSetNameToProjectCopy
    , initShareProject
    , initViewGroup
    , isAttributeBrowserAffixing
    , reorderBasesModalInitialState
    , setState
    , subscriptions
    , update
    , updateAfterStoreAction
    , updateAttributesData
    , view
    )

{-| A module containing almost all the logic for the modals inside XB2 app.

TODO: Migrate this to a better hierarchical structure like:

    Views
        └ Modal
            ├ RenameProject
            ├ CreateFolder
            ├ ReorderBases
            ...

-}

import AssocSet
import Browser.Dom as Dom
import Browser.Events
import Cmd.Extra as Cmd
import Dict.Any
import DnDList as Dnd
import Glue
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Attributes.Extra as Attrs_
import Html.Events as Events
import Html.Events.Extra as Events
import Html.Extra as Html
import Json.Decode as Decode exposing (Decoder)
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import List.NonEmpty.Zipper as Zipper exposing (Zipper)
import Markdown
import Maybe.Extra as Maybe
import RemoteData exposing (WebData)
import Svg
import Svg.Attributes as SvgAttrs
import Task exposing (Task)
import WeakCss exposing (ClassName)
import XB2.Analytics as Analytics exposing (Event(..))
import XB2.Data as Data
    exposing
        ( CrosstabUser
        , Shared(..)
        , SharingEmail(..)
        , XBFolder
        , XBFolderId
        , XBFolderIdTag
        , XBProject
        , XBProjectFullyLoaded
        , XBProjectIdTag
        )
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.AudienceCrosstab as ACrosstab exposing (AffixGroupItem, Direction(..), EditGroupItem)
import XB2.Data.AudienceCrosstab.Sort exposing (SortConfig)
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId as AudienceItemId
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Metric as Metric exposing (Metric)
import XB2.Data.SelectionMap as SelectionMap
import XB2.Modal.Browser as ModalBrowser
    exposing
        ( AffixingOrEditingItems(..)
        , SelectedItems
        )
import XB2.Router exposing (Route)
import XB2.Share.Analytics.Place as Place
import XB2.Share.Config exposing (Flags)
import XB2.Share.CoolTip
import XB2.Share.CoolTip.Platform2 as P2Cooltip
import XB2.Share.Data.Id exposing (IdDict, IdSet)
import XB2.Share.Data.Labels
    exposing
        ( LocationCodeTag
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2 exposing (FullUserEmail)
import XB2.Share.Dialog.ErrorDisplay exposing (ErrorDisplay)
import XB2.Share.Gwi.Html.Attributes as Attrs
import XB2.Share.Gwi.Http
import XB2.Share.Gwi.String as String
import XB2.Share.Icons
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.Modal.ChooseMany as ChooseMany
import XB2.Share.Modal.ChooseOne as ChooseOne
import XB2.Share.Palette
import XB2.Share.Platform2.AudienceExpressionViewer as ExpressionViewer
import XB2.Share.Platform2.AutocompleteInput as Autocomplete
import XB2.Share.Platform2.Grouping as Grouping exposing (Grouping)
import XB2.Share.Platform2.Input.Text as TextInput
import XB2.Share.Platform2.Modal as P2Modals exposing (HeaderTab)
import XB2.Share.Platform2.Spinner as Spinner
import XB2.Share.Plural
import XB2.Share.Store.Platform2
import XB2.Share.UndoRedo as UndoRedo
import XB2.Store as XBStore
import XB2.Utils.NewName as NewName
import XB2.Views.Modal.LoaderWithoutProgress as LoaderWithoutProgressModal



-- TYPES


type State
    = Ready
    | Processing


type ViewSettingsAction
    = AddingNewBases
    | ChangeFilters


type Modal
    = RenameProject RenameProjectData
    | SetNameForNewProject RenameProjectData
    | SetNameForProjectCopy SaveAsCopyProjectData
    | DuplicateProject DuplicateProjectData
    | ConfirmDeleteProject ConfirmDeleteProjectData
    | ConfirmDeleteProjects ConfirmDeleteProjectsData
    | ConfirmUnshareMe ConfirmDeleteProjectData
    | SaveProjectAsNew SaveProjectAsNewData
    | ShareProject ShareProjectData
    | CreateFolder CreateFolderData
    | MoveToFolder MoveToFolderData
    | RenameFolder RenameFolderData
    | ConfirmDeleteFolder DeleteFolderData
    | ConfirmUngroupFolder { state : State, folder : XBFolder }
    | ChooseMetrics ChooseMetricsData
    | ViewGroup ViewGroupData
    | RenameAverage RenameAverageData
    | RenameBaseAudience ViewBaseGroupData
    | ChooseHeatmapMetric ChooseHeatmapMetricData
    | UnsavedChangesAlert { newRoute : Route }
    | SaveAsAudience SaveAsAudienceData
    | ConfirmFullLoadForHeatmap Int Metric
    | ConfirmFullLoadForExport (Maybe SelectionMap.SelectionMap) Int (Maybe XBProject)
    | ConfirmFullLoadForExportFromList Int XBProjectFullyLoaded
    | ConfirmCancelExport
    | ConfirmCancelExportFromList
    | ConfirmCancelApplyingHeatmap
    | ConfirmActionWithViewSettings { viewSettingsAction : ViewSettingsAction, isSorting : Bool, isHeatmap : Bool }
    | ConfirmCellsLoadForSorting Int SortConfig
    | ConfirmCancelCellsSorting
    | ConfirmCancelFullScreenTableLoad
    | AddAsNewBases AddAsNewBasesData
    | MergeRowOrColum MergeRowOrColumnData
    | ConfirmRemoveRowsColumns ConfirmRemoveRowsColumnsData
    | ConfirmRemoveBases ConfirmRemoveBasesData
    | GenericAlert GenericAlertData
    | MoveOutOfFolderModal { state : State, projects : List XBProject }
    | ErrorModal (ErrorDisplay Never)
    | ReorderBases ReorderBasesModalData
      -- When selecting several items to affix -> Affix with AND/OR -> Save modal appears
    | AffixGroup AffixGroupData
    | EditGroup EditGroupData
      -- When selecting bases to affix -> Affix with AND/OR -> Save modal appears
    | AffixBase AffixBaseData
    | EditBase EditBaseData
      -- Used when adding bases, affixing bases, replacing default base audience, adding attributes to table, affixing items
    | AttributesModal AttributesModalData
    | FetchQuestionsForEditModal


{-| The data inside the `ReorderBases` modal. It features a drag and drop model, a reset
button to go back to the initial state, accesibility messages and keyboard inputs.
-}
type alias ReorderBasesModalData =
    { dragAndDropSystem : Dnd.Model
    , initialBasesOrder : List ACrosstab.CrosstabBaseAudience
    , newBasesOrder : List ACrosstab.CrosstabBaseAudience
    , focusedBaseIndex : Maybe Int
    , baseIndexSelectedToMoveWithKeyboard : Maybe Int

    -- We need this to set the aria-label message inside the aria-live region
    , ariaMessageForBasesList : Maybe String

    -- Used to show the dividing line when a base is hovered
    , hoveredBaseIndexForDividingLine : Maybe Int
    }


reorderBasesModalDndConfig : Dnd.Config ACrosstab.CrosstabBaseAudience
reorderBasesModalDndConfig =
    { beforeUpdate = \_ _ list -> list
    , movement = Dnd.Vertical
    , listen = Dnd.OnDrag
    , operation = Dnd.Rotate
    }


reorderBasesModalDndSystem : Dnd.System ACrosstab.CrosstabBaseAudience Msg
reorderBasesModalDndSystem =
    Dnd.create reorderBasesModalDndConfig ReorderBasesModalDndMsg


reorderBasesModalInitialState : List ACrosstab.CrosstabBaseAudience -> ReorderBasesModalData
reorderBasesModalInitialState baseAudiences =
    { dragAndDropSystem = reorderBasesModalDndSystem.model
    , initialBasesOrder = baseAudiences
    , newBasesOrder = baseAudiences
    , focusedBaseIndex = Nothing
    , baseIndexSelectedToMoveWithKeyboard = Nothing
    , ariaMessageForBasesList = Nothing
    , hoveredBaseIndexForDividingLine = Nothing
    }


type AttributesModalType
    = AddRowColumnToTable
    | AffixRowColumn Analytics.AffixedFrom
    | EditRowColumn
    | AddBaseAudience
    | EditBaseAudience
    | AffixBaseAudience
    | ReplaceDefaultBaseAudience


type alias AttributesModalData =
    { browserModel : ModalBrowser.Model
    , modalType : AttributesModalType
    , selectedBasesCount : Int
    , affixingOrEditingItems : ModalBrowser.AffixingOrEditingItems
    }


type alias GenericAlertData =
    { title : String
    , htmlContent : Html Never
    , btnTitle : String
    }


type alias ExpandedState =
    { expanded : Bool
    , alreadySeen : Bool
    }


type alias AddAsNewBasesData =
    { selectedItems : List ( ExpandedState, ACrosstab.Key )
    , logicButtons : List { grouping : Grouping, active : Bool }
    }


type alias MergeRowOrColumnData =
    { selectedItems : List ( ExpandedState, ACrosstab.Key )
    , logicButtons : List { grouping : Grouping, active : Bool }
    , allDirections : List Direction
    , allSelected : List ( Direction, ACrosstab.Key )
    }


type alias ConfirmRemoveRowsColumnsData =
    { items : List ( ExpandedState, ( Direction, ACrosstab.Key ) )
    , doNotShowAgainChecked : Bool
    }


type alias ConfirmRemoveBasesData =
    { items : List ( ExpandedState, BaseAudience )
    , doNotShowAgainChecked : Bool
    }


type alias ChooseHeatmapMetricData =
    { chooseOneModal : ChooseOne.Model Metric }


isAttributeBrowserAffixing : Modal -> Bool
isAttributeBrowserAffixing modal =
    case modal of
        AttributesModal data ->
            case data.modalType of
                AddRowColumnToTable ->
                    False

                AffixRowColumn _ ->
                    True

                AddBaseAudience ->
                    False

                AffixBaseAudience ->
                    True

                ReplaceDefaultBaseAudience ->
                    False

                EditBaseAudience ->
                    False

                EditRowColumn ->
                    False

        _ ->
            False


chooseOneHeatmapMetricsConfig : Config msg -> ChooseOne.Config Metric msg
chooseOneHeatmapMetricsConfig config =
    { title = "Apply heatmap"
    , confirmButton = "Apply"
    , cancelButton = "Cancel"
    , resetButtonTitle = "Reset heatmaps"
    , helpLink = Just "https://knowledge.globalwebindex.net/hc/en-us/articles/360009983960-How-to-Apply-a-heatmap-to-your-crosstab"
    , msg = config.msg << ChooseOneModalMsg
    , close = config.closeModal
    , openUrl = config.msg << KnowledgeBaseLinkClicked "metrics_explanation"
    , confirm = config.applyHeatmap
    , getName = Metric.label
    , getInfo = Metric.description >> Just
    }


type alias RenameProjectData =
    { state : State
    , newName : String
    , project : XBProject
    }


type alias DuplicateProjectData =
    { state : State
    , newName : String
    , project : XBProject
    }


type alias SaveAsCopyProjectData =
    { state : State
    , newName : String
    , project : XBProject
    , original : XBProject
    }


type alias ConfirmDeleteProjectData =
    { state : State
    , project : XBProject
    }


type alias ConfirmDeleteProjectsData =
    { state : State
    , projects : List XBProject
    }


type alias SaveProjectAsNewData =
    { state : State
    , newName : String
    }


sharingNoteMaxLength : Int
sharingNoteMaxLength =
    160


type alias ShareProjectData =
    { project : XBProject
    , originalSharedWithEmails : Maybe (NonEmpty SharingEmail)
    , originalSharedWithOrgs : Maybe (NonEmpty XB2.Share.Data.Platform2.OrganisationId)
    , emailsForSharing : List SharingEmail
    , shareWithOrgChecked : Bool
    , hasChanges : Bool
    , state : State
    , autocompleteModel : Autocomplete.Model FullUserEmail
    }


type alias CreateFolderData =
    { state : State
    , newName : String
    , projects : List XBProject
    }


type alias MoveToFolderData =
    { state : State
    , projects : List XBProject
    , canMoveToFolder : Bool
    , selectedFolderId : Maybe XBFolderId
    , initialFolderId : Maybe XBFolderId
    }


type alias RenameFolderData =
    { state : State
    , newName : String
    , folder : XBFolder
    }


type alias DeleteFolderData =
    { state : State
    , folder : XBFolder
    , projectsInFolder : Int
    }


type alias ChooseMetricsData =
    { chooseManyModal : ChooseMany.Model Metric }


chooseMetricsConfig : Config msg -> ChooseMany.Config Metric msg
chooseMetricsConfig config =
    { title = "Choose metrics"
    , confirmButton = "Apply"
    , cancelButton = "Cancel"
    , selectAllTitle = "Reset metrics"
    , helpLink = Just "https://gwihelpcenter.zendesk.com/hc/en-us/articles/4428964311826-Reading-your-crosstab"
    , msg = config.msg << ChooseManyModalMsg
    , close = config.closeModal
    , openUrl = config.msg << KnowledgeBaseLinkClicked "metrics_explanation"
    , confirm = config.applyMetricsSelection
    , getName = Metric.label
    , getInfo = Metric.description >> Just
    }


type alias ViewGroupData =
    { hasChanges : Bool
    , caption : Caption
    , expression : Expression
    , oldKey : ACrosstab.Key
    , direction : Direction
    }


type alias RenameAverageData =
    { hasChanges : Bool
    , caption : Caption
    , oldKey : ACrosstab.Key
    , direction : Direction
    }


type alias ViewBaseGroupData =
    { hasChanges : Bool
    , baseAudience : BaseAudience
    }


type alias AffixBaseGroupData =
    { baseAudience : BaseAudience
    , newExpression : Expression
    , expressionBeingAffixed : Expression
    , newCaption : Caption
    , grouping : Grouping
    , addedItems : SelectedItems
    }


type alias EditBaseGroupData =
    { baseAudience : BaseAudience
    , newExpression : Expression
    , expressionBeingEdited : Expression
    , newCaption : Caption
    , grouping : Grouping
    , addedItems : SelectedItems
    }


type alias EditGroupData =
    { zipper : Zipper EditGroupItem
    , grouping : Grouping
    , expandedItem : Maybe Int
    , itemBeingRenamed : Maybe Int
    , attributeBrowserModal : AttributesModalData
    }


type alias AffixBaseData =
    { zipper : Zipper AffixBaseGroupData
    , grouping : Grouping
    , operator : Expression.LogicOperator
    , expandedItem : Maybe Int
    , itemBeingRenamed : Maybe Int
    , attributeBrowserModal : AttributesModalData
    }


type alias EditBaseData =
    { zipper : Zipper EditBaseGroupData
    , grouping : Grouping
    , expandedItem : Maybe Int
    , itemBeingRenamed : Maybe Int
    , attributeBrowserModal : AttributesModalData
    }


type alias AffixGroupData =
    { zipper : Zipper AffixGroupItem
    , grouping : Grouping
    , operator : Expression.LogicOperator
    , expandedItem : Maybe Int
    , itemBeingRenamed : Maybe Int
    , attributeBrowserModal : AttributesModalData
    , affixedFrom : Analytics.AffixedFrom
    }


type SaveAsItem
    = SaveAsAudienceItem AudienceItem Expression
    | SaveAsBaseAudience BaseAudience


type alias SaveAsAudienceData =
    { item : SaveAsItem
    , caption : Caption
    , expression : Expression
    , state : State
    }


type alias Config msg =
    -- general
    { noOp : msg
    , msg : Msg -> msg
    , closeModal : msg
    , openNewWindow : String -> msg
    , openSupportChat : Maybe String -> msg

    -- Project
    , renameProject : XBProject -> msg
    , saveNewProjectWithoutRedirect : XBProject -> msg
    , saveProjectAsCopy : { original : XBProject, copy : XBProject } -> msg
    , saveProjectAsNew : String -> msg
    , duplicateProject : String -> XBProject -> msg
    , confirmDeleteProject : XBProject -> msg
    , unshareMe : XBProject -> msg
    , shareProject : XBProject -> msg
    , shareAndCopyLink : XBProject -> msg
    , createFolder : List XBProject -> String -> msg
    , moveToFolder : Maybe XBFolder -> XBProject -> msg

    -- Projects
    , moveProjectsToFolder : Maybe XBFolder -> List XBProject -> msg
    , confirmDeleteProjects : List XBProject -> msg

    -- Folder
    , renameFolder : XBFolder -> msg
    , confirmDeleteFolder : XBFolder -> msg
    , confirmUngroupFolder : XBFolder -> msg

    -- Metrics
    , applyMetricsSelection : AssocSet.Set Metric -> msg

    -- Heatmap
    , applyHeatmap : Maybe Metric -> msg

    -- ViewGroup
    , saveGroupName :
        Direction
        ->
            { oldKey : ACrosstab.Key
            , newItem : AudienceItem
            , expression : Maybe Expression
            }
        -> msg

    -- ViewBaseAudience
    , setOrCreateBaseAudience : BaseAudience -> msg

    -- AffixGroup
    , affixGroup : Grouping -> Expression.LogicOperator -> SelectedItems -> List AffixGroupItem -> Analytics.AffixedFrom -> msg
    , editGroup : Grouping -> SelectedItems -> List EditGroupItem -> msg
    , affixBasesInTableView : NonEmpty AffixBaseGroupData -> msg
    , editBasesInTableView : NonEmpty EditBaseGroupData -> msg

    -- Unsaved alert
    , saveUnsavedProjectAndContinue : Route -> msg
    , ignoreUnsavedChangesAndContinue : Route -> msg

    -- Save as Audience
    , saveAsAudience : SaveAsItem -> Caption -> Expression -> msg
    , saveAsBase : Grouping -> List ACrosstab.Key -> msg

    -- Merge Rows and Columns
    , mergeRowOrColumn : Grouping -> List ACrosstab.Key -> List Direction -> Bool -> List ( Direction, ACrosstab.Key ) -> msg

    -- Reorder bases
    , reorderModalApplyChanges : { triggeredFrom : Analytics.BaseOrderingChangeMethod, shouldFireAnalytics : Bool } -> List ACrosstab.CrosstabBaseAudience -> Int -> msg

    -- Confirm and full load
    , fullLoadAndApplyHeatmap : Metric -> msg
    , fullLoadAndExport : Maybe SelectionMap.SelectionMap -> Maybe XBProject -> msg
    , fullLoadAndExportFromList : XBProjectFullyLoaded -> msg
    , confirmCancelFullLoad : msg
    , confirmCancelFullLoadFromList : msg
    , turnOffViewSettingsAndContinue : msg
    , keepViewSettingsAndContinue : msg
    , partialLoadAndSort : SortConfig -> msg
    , removeSortingAndCloseModal : msg
    , cancelSortingLoading : msg

    -- bulk actions
    , confirmDeleteRowsColumns : Bool -> List ( Direction, ACrosstab.Key ) -> msg
    , confirmDeleteBases : Bool -> NonEmpty BaseAudience -> msg
    , browser : AttributesModalData -> ModalBrowser.Config msg
    }


type BulkDeleteModalAction
    = ToggleInfo Int
    | RemoveItem Int
    | ToggleDoNotShowAgain


type Msg
    = NoOp
    | SetProjectOrFolderName String
    | SetGroupName String
    | SetGroupNameAt Int String
    | EditingInput Int
    | StopEditingInput
    | SelectTextInField String
    | KnowledgeBaseLinkClicked String String
    | RemoveOriginalSharee SharingEmail
    | RemoveOriginalSharedOrg XB2.Share.Data.Platform2.OrganisationId
    | SetSharingNote String
    | ToggleSharingWithOrg
    | ValidatedOriginalSharingEmail SharingEmail
    | SelectMoveToFolder XBFolder
    | AddAsBasesToggleInfo Int
    | AddAsBasesSetActiveLogic Int
    | MergeRowOrColumSetActiveLogic Int
    | MergeRowOrColumToggleInfo Int
    | UpdateRemoveRowsColumnsModal BulkDeleteModalAction
    | UpdateConfirmRemoveBasesModal BulkDeleteModalAction
    | OpenAttributeBrowser AttributesModalData
    | ModalBrowserMsg ModalBrowser.Msg
    | ChooseOneModalMsg (ChooseOne.Msg Metric)
    | ChooseManyModalMsg (ChooseMany.Msg Metric)
    | AutocompleteInputMsg (Autocomplete.Msg FullUserEmail)
    | ReorderBasesModalDndMsg Dnd.Msg
    | ResetReorderBasesModal
    | SetBaseAudienceIndexFocused (Maybe Int)
    | SetBaseAudienceIndexHovered (Maybe Int)
    | SetBaseAudienceIndexSelectedToMoveWithKeyboard (Maybe Int)
    | SwapBasesOrder Int Int



-- SIZES


type ModalSize
    = Small -- hardcoded width, height according to content
    | Medium -- hardcoded width, full height
    | MediumFlexible -- hardcoded width, flexible height according to the content
    | Large -- full width, full height
    | LargeCapped -- capped full width, full height
    | WebComponent -- not in our control


modalSize : Modal -> ModalSize
modalSize modal =
    case modal of
        RenameProject _ ->
            Small

        SetNameForNewProject _ ->
            Small

        SetNameForProjectCopy _ ->
            Small

        DuplicateProject _ ->
            Small

        ConfirmDeleteProject _ ->
            Small

        ConfirmDeleteProjects _ ->
            Small

        ConfirmUnshareMe _ ->
            Small

        SaveProjectAsNew _ ->
            Small

        ShareProject _ ->
            MediumFlexible

        CreateFolder _ ->
            Small

        MoveToFolder _ ->
            MediumFlexible

        RenameFolder _ ->
            Small

        ConfirmDeleteFolder _ ->
            Small

        ConfirmUngroupFolder _ ->
            Small

        ChooseMetrics _ ->
            WebComponent

        ViewGroup _ ->
            Medium

        RenameAverage _ ->
            Small

        RenameBaseAudience _ ->
            MediumFlexible

        AffixGroup _ ->
            Large

        EditGroup _ ->
            Large

        AffixBase _ ->
            Large

        EditBase _ ->
            Large

        ChooseHeatmapMetric _ ->
            WebComponent

        AttributesModal _ ->
            LargeCapped

        UnsavedChangesAlert _ ->
            Small

        SaveAsAudience _ ->
            MediumFlexible

        ConfirmFullLoadForHeatmap _ _ ->
            Small

        ConfirmFullLoadForExport _ _ _ ->
            Small

        ConfirmFullLoadForExportFromList _ _ ->
            Small

        ConfirmCancelExport ->
            Small

        FetchQuestionsForEditModal ->
            Small

        ConfirmCancelExportFromList ->
            Small

        ConfirmCancelApplyingHeatmap ->
            Small

        ConfirmActionWithViewSettings _ ->
            Small

        ConfirmCellsLoadForSorting _ _ ->
            Small

        ConfirmCancelCellsSorting ->
            Small

        ConfirmCancelFullScreenTableLoad ->
            Small

        AddAsNewBases _ ->
            MediumFlexible

        MergeRowOrColum _ ->
            MediumFlexible

        ConfirmRemoveRowsColumns _ ->
            Medium

        ConfirmRemoveBases _ ->
            Medium

        GenericAlert _ ->
            Small

        ErrorModal _ ->
            Small

        MoveOutOfFolderModal _ ->
            Small

        ReorderBases _ ->
            Small



-- INIT


initDuplicateProject : String -> XBProject -> Modal
initDuplicateProject name project =
    DuplicateProject
        { newName = name
        , state = Ready
        , project = project
        }


initConfirmDeleteProject : XBProject -> Modal
initConfirmDeleteProject project =
    ConfirmDeleteProject
        { state = Ready
        , project = project
        }


initConfirmDeleteProjects : List XBProject -> Modal
initConfirmDeleteProjects projects =
    ConfirmDeleteProjects
        { state = Ready
        , projects = projects
        }


initConfirmUnshareMe : XBProject -> Modal
initConfirmUnshareMe project =
    ConfirmUnshareMe
        { state = Ready
        , project = project
        }


initRenameProject : XBProject -> Modal
initRenameProject project =
    RenameProject
        { newName = project.name
        , state = Ready
        , project = project
        }


initSetNameToNewProject : XBProject -> Modal
initSetNameToNewProject project =
    SetNameForNewProject
        { newName = project.name
        , state = Ready
        , project = project
        }


initSetNameToProjectCopy : { original : XBProject, copy : XBProject } -> Modal
initSetNameToProjectCopy { original, copy } =
    SetNameForProjectCopy
        { newName = copy.name
        , state = Ready
        , original = original
        , project = copy
        }


initSaveProjectAsNew : String -> Modal
initSaveProjectAsNew name =
    SaveProjectAsNew
        { newName = name
        , state = Ready
        }


initShareProject : Config msg -> Flags -> XBProject -> ( Modal, Cmd msg )
initShareProject config flags project =
    let
        originalSharedWithEmails : Maybe (NonEmpty SharingEmail)
        originalSharedWithEmails =
            case project.shared of
                Data.MySharedCrosstab sharees ->
                    sharees
                        |> NonemptyList.filterMap
                            (\sharee ->
                                case sharee of
                                    Data.UserSharee user ->
                                        Just <| UncheckedEmail { email = user.email }

                                    Data.OrgSharee _ ->
                                        Nothing
                            )

                _ ->
                    Nothing
    in
    ( ShareProject
        { project = project
        , originalSharedWithEmails = originalSharedWithEmails
        , originalSharedWithOrgs =
            case project.shared of
                Data.MySharedCrosstab sharees ->
                    sharees
                        |> NonemptyList.filterMap
                            (\sharee ->
                                case sharee of
                                    Data.UserSharee _ ->
                                        Nothing

                                    Data.OrgSharee orgId ->
                                        Just orgId
                            )

                _ ->
                    Nothing
        , shareWithOrgChecked = Data.isSharedByMeWithOrg project.shared
        , emailsForSharing = []
        , state =
            if originalSharedWithEmails == Nothing then
                Ready

            else
                Processing
        , hasChanges = False
        , autocompleteModel =
            Autocomplete.init
                { debounceSeconds = 0.5
                , selectedItems = []
                }
        }
    , case originalSharedWithEmails of
        Just originalEmails ->
            originalEmails
                |> NonemptyList.toList
                |> List.map
                    (Data.unwrapSharingEmail
                        >> (\email ->
                                Data.validateUserEmail email flags
                                    |> Cmd.map
                                        (config.msg
                                            << ValidatedOriginalSharingEmail
                                            << resolveValidateEmailResponse { email = email }
                                        )
                           )
                    )
                |> Cmd.batch

        Nothing ->
            Cmd.none
    )


initCreateFolder : String -> List XBProject -> Modal
initCreateFolder name projects =
    CreateFolder
        { newName = name
        , projects = projects
        , state = Ready
        }


initMoveToFolder : List XBProject -> Modal
initMoveToFolder projects =
    let
        projectsFolderId =
            projects |> List.head |> Maybe.andThen .folderId
    in
    MoveToFolder
        { projects = projects
        , state = Ready
        , canMoveToFolder = False
        , selectedFolderId = projectsFolderId
        , initialFolderId = projectsFolderId
        }


initRenameFolder : XBFolder -> Modal
initRenameFolder folder =
    RenameFolder
        { newName = folder.name
        , state = Ready
        , folder = folder
        }


initConfirmDeleteFolder : Int -> XBFolder -> Modal
initConfirmDeleteFolder projectsInFolder folder =
    ConfirmDeleteFolder
        { state = Ready
        , folder = folder
        , projectsInFolder = projectsInFolder
        }


initConfirmUngroupFolder : XBFolder -> Modal
initConfirmUngroupFolder folder =
    ConfirmUngroupFolder { state = Ready, folder = folder }


initViewGroup : ( Direction, ACrosstab.Key, Expression ) -> Modal
initViewGroup ( direction, oldKey, expression ) =
    ViewGroup
        { hasChanges = False
        , caption = AudienceItem.getCaption oldKey.item
        , expression = expression
        , oldKey = oldKey
        , direction = direction
        }


initRenameAverage : Direction -> ACrosstab.Key -> Modal
initRenameAverage direction oldKey =
    RenameAverage
        { hasChanges = False
        , caption = AudienceItem.getCaption oldKey.item
        , oldKey = oldKey
        , direction = direction
        }


initRenameBaseAudience : BaseAudience -> Modal
initRenameBaseAudience baseAudience =
    RenameBaseAudience
        { hasChanges = False
        , baseAudience = baseAudience
        }


initSaveAsAudience : SaveAsItem -> Modal
initSaveAsAudience item =
    let
        ( caption, expression ) =
            case item of
                SaveAsAudienceItem aItem expr ->
                    ( AudienceItem.getCaption aItem
                    , expr
                    )

                SaveAsBaseAudience bItem ->
                    ( BaseAudience.getCaption bItem
                    , BaseAudience.getExpression bItem
                    )
    in
    SaveAsAudience
        { item = item
        , caption = Caption.trimNameByUserDefinedLimit caption
        , expression = expression
        , state = Ready
        }


initConfirmFullLoadForHeatmap : Int -> Metric -> Modal
initConfirmFullLoadForHeatmap =
    ConfirmFullLoadForHeatmap


initConfirmFullLoadForExport : Maybe SelectionMap.SelectionMap -> Int -> Maybe XBProject -> Modal
initConfirmFullLoadForExport =
    ConfirmFullLoadForExport


initConfirmActionWithViewSettings : { isSorting : Bool, isHeatmap : Bool } -> Modal
initConfirmActionWithViewSettings { isSorting, isHeatmap } =
    ConfirmActionWithViewSettings { viewSettingsAction = ChangeFilters, isSorting = isSorting, isHeatmap = isHeatmap }


initConfirmAddNewBaseWithViewSettings : { isSorting : Bool, isHeatmap : Bool } -> Modal
initConfirmAddNewBaseWithViewSettings { isSorting, isHeatmap } =
    ConfirmActionWithViewSettings { viewSettingsAction = AddingNewBases, isSorting = isSorting, isHeatmap = isHeatmap }


initConfirmCellsLoadForSorting : Int -> SortConfig -> Modal
initConfirmCellsLoadForSorting =
    ConfirmCellsLoadForSorting


initAddAsNewBases : List ACrosstab.Key -> Modal
initAddAsNewBases selectedItems =
    AddAsNewBases
        { selectedItems = List.map (Tuple.pair { expanded = False, alreadySeen = False }) selectedItems
        , logicButtons =
            [ { grouping = Grouping.Split, active = True }
            , { grouping = Grouping.And, active = False }
            , { grouping = Grouping.Or, active = False }
            ]
        }


initMergeRowOrColum : List ACrosstab.Key -> List Direction -> List ( Direction, ACrosstab.Key ) -> Modal
initMergeRowOrColum selectedItems allDirections allSelected =
    MergeRowOrColum
        { selectedItems = List.map (Tuple.pair { expanded = False, alreadySeen = False }) selectedItems
        , logicButtons =
            [ { grouping = Grouping.And, active = True }
            , { grouping = Grouping.Or, active = False }
            ]
        , allDirections = allDirections
        , allSelected = allSelected
        }


initConfirmRemoveRowsColumns : List ( Direction, ACrosstab.Key ) -> Modal
initConfirmRemoveRowsColumns items =
    ConfirmRemoveRowsColumns
        { items = List.map (Tuple.pair { expanded = False, alreadySeen = False }) items
        , doNotShowAgainChecked = False
        }


initConfirmRemoveBases : List BaseAudience -> Modal
initConfirmRemoveBases bases =
    ConfirmRemoveBasesData (List.map (Tuple.pair { expanded = False, alreadySeen = False }) bases) False
        |> ConfirmRemoveBases


initAttributesModal : AttributesModalType -> ModalBrowser.AffixingOrEditingItems -> SelectedItems -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesModal modalType affixingItems initialSelectedItems waves locations selectedBasesCount =
    AttributesModal
        { browserModel = ModalBrowser.init initialSelectedItems waves locations
        , modalType = modalType
        , selectedBasesCount = selectedBasesCount
        , affixingOrEditingItems = affixingItems
        }


initAttributesAddModal : IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesAddModal =
    initAttributesModal AddRowColumnToTable NotAffixingOrEditing []


initAttributesEditModal : NonEmpty ( Direction, ACrosstab.Key ) -> SelectedItems -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesEditModal editingItems initalSelectedItems =
    initAttributesModal EditRowColumn (EditingRowsOrColumns editingItems) initalSelectedItems


initAttributesAffixModal : Analytics.AffixedFrom -> NonEmpty ( Direction, ACrosstab.Key ) -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesAffixModal affixedFrom affixingItems =
    initAttributesModal (AffixRowColumn affixedFrom) (AffixingRowsOrColumns affixingItems) []


initAttributesAddBaseModal : IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesAddBaseModal =
    initAttributesModal AddBaseAudience NotAffixingOrEditing []


initAttributesAffixBaseModal : NonEmpty BaseAudience -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesAffixBaseModal affixingBases =
    initAttributesModal AffixBaseAudience (AffixingBases affixingBases) []


initAttributesEditBaseModal : NonEmpty BaseAudience -> SelectedItems -> IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesEditBaseModal editingBases initialSelectedItems =
    initAttributesModal EditBaseAudience (EditingBases editingBases) initialSelectedItems


initAttributesReplaceDefaultBaseModal : IdSet WaveCodeTag -> IdSet LocationCodeTag -> Int -> Modal
initAttributesReplaceDefaultBaseModal =
    initAttributesModal ReplaceDefaultBaseAudience NotAffixingOrEditing []


initChooseHeatmapMetric : Maybe Metric -> Modal
initChooseHeatmapMetric selectedMetric =
    ChooseHeatmapMetric
        { chooseOneModal = ChooseOne.init heatmapMetrics selectedMetric
        }


initChooseMetrics : AssocSet.Set Metric -> Modal
initChooseMetrics toggledMetrics =
    ChooseMetrics
        { chooseManyModal =
            ChooseMany.init
                Data.defaultMetrics
                toggledMetrics
        }


initMoveOutOfFolder : List XBProject -> Modal
initMoveOutOfFolder prjects =
    MoveOutOfFolderModal { state = Ready, projects = prjects }



-- UPDATE


setState : State -> Modal -> Modal
setState state modal =
    case modal of
        RenameProject m ->
            RenameProject { m | state = state }

        SetNameForNewProject m ->
            SetNameForNewProject { m | state = state }

        SetNameForProjectCopy m ->
            SetNameForProjectCopy { m | state = state }

        DuplicateProject m ->
            DuplicateProject { m | state = state }

        ConfirmDeleteProject m ->
            ConfirmDeleteProject { m | state = state }

        ConfirmDeleteProjects m ->
            ConfirmDeleteProjects { m | state = state }

        ConfirmUnshareMe m ->
            ConfirmUnshareMe { m | state = state }

        SaveProjectAsNew m ->
            SaveProjectAsNew { m | state = state }

        ShareProject m ->
            ShareProject { m | state = state }

        CreateFolder m ->
            CreateFolder { m | state = state }

        MoveToFolder m ->
            MoveToFolder { m | state = state }

        RenameFolder m ->
            RenameFolder { m | state = state }

        ConfirmDeleteFolder m ->
            ConfirmDeleteFolder { m | state = state }

        ConfirmUngroupFolder m ->
            ConfirmUngroupFolder { m | state = state }

        ChooseMetrics _ ->
            modal

        AttributesModal _ ->
            modal

        FetchQuestionsForEditModal ->
            modal

        ViewGroup _ ->
            modal

        RenameAverage _ ->
            modal

        RenameBaseAudience _ ->
            modal

        AffixGroup _ ->
            modal

        EditGroup _ ->
            modal

        AffixBase _ ->
            modal

        EditBase _ ->
            modal

        ChooseHeatmapMetric _ ->
            modal

        UnsavedChangesAlert _ ->
            modal

        SaveAsAudience m ->
            SaveAsAudience { m | state = state }

        ConfirmFullLoadForHeatmap _ _ ->
            modal

        ConfirmFullLoadForExport _ _ _ ->
            modal

        ConfirmFullLoadForExportFromList _ _ ->
            modal

        ConfirmCancelExport ->
            modal

        ConfirmCancelExportFromList ->
            modal

        ConfirmCancelApplyingHeatmap ->
            modal

        ConfirmActionWithViewSettings _ ->
            modal

        ConfirmCellsLoadForSorting _ _ ->
            modal

        ConfirmCancelCellsSorting ->
            modal

        ConfirmCancelFullScreenTableLoad ->
            modal

        AddAsNewBases _ ->
            modal

        MergeRowOrColum _ ->
            modal

        ConfirmRemoveRowsColumns _ ->
            modal

        ConfirmRemoveBases _ ->
            modal

        GenericAlert _ ->
            modal

        ErrorModal _ ->
            modal

        MoveOutOfFolderModal m ->
            MoveOutOfFolderModal { m | state = state }

        ReorderBases _ ->
            modal


setNewName : String -> Modal -> Modal
setNewName newName modal =
    case modal of
        DuplicateProject m ->
            DuplicateProject { m | newName = newName }

        RenameProject m ->
            RenameProject { m | newName = newName }

        SetNameForNewProject m ->
            SetNameForNewProject { m | newName = newName }

        SetNameForProjectCopy m ->
            SetNameForProjectCopy { m | newName = newName }

        SaveProjectAsNew m ->
            SaveProjectAsNew { m | newName = newName }

        CreateFolder m ->
            CreateFolder { m | newName = newName }

        RenameFolder m ->
            RenameFolder { m | newName = newName }

        _ ->
            modal


updateViewGroup : (ViewGroupData -> ViewGroupData) -> Modal -> Modal
updateViewGroup fn modal =
    case modal of
        ViewGroup m ->
            ViewGroup (fn m)

        _ ->
            modal


updateAttributesData : (AttributesModalData -> AttributesModalData) -> Modal -> Modal
updateAttributesData fn modal =
    case modal of
        AttributesModal data ->
            AttributesModal (fn data)

        _ ->
            modal


updateRenameAverage : (RenameAverageData -> RenameAverageData) -> Modal -> Modal
updateRenameAverage fn modal =
    case modal of
        RenameAverage m ->
            RenameAverage (fn m)

        _ ->
            modal


updateCurrentViewBaseAudience : (ViewBaseGroupData -> ViewBaseGroupData) -> Modal -> Modal
updateCurrentViewBaseAudience fn modal =
    case modal of
        RenameBaseAudience base ->
            RenameBaseAudience <| fn base

        _ ->
            modal


updateShareProject : (ShareProjectData -> ShareProjectData) -> Modal -> Modal
updateShareProject fn modal =
    case modal of
        ShareProject data ->
            ShareProject <| fn { data | hasChanges = True }

        _ ->
            modal


updateMoveToFolderProject : (MoveToFolderData -> MoveToFolderData) -> Modal -> Modal
updateMoveToFolderProject fn modal =
    case modal of
        MoveToFolder m ->
            MoveToFolder (fn m)

        _ ->
            modal


updateSaveAsAudience : (SaveAsAudienceData -> SaveAsAudienceData) -> Modal -> Modal
updateSaveAsAudience fn modal =
    case modal of
        SaveAsAudience m ->
            SaveAsAudience (fn m)

        _ ->
            modal


bulkDeleteModalActionsUpdate :
    Config msg
    -> BulkDeleteModalAction
    -> { a | items : List ( ExpandedState, item ), doNotShowAgainChecked : Bool }
    -> ( { a | items : List ( ExpandedState, item ), doNotShowAgainChecked : Bool }, Cmd msg )
bulkDeleteModalActionsUpdate config action data =
    case action of
        ToggleInfo index ->
            { data
                | items =
                    data.items
                        |> List.updateAt index
                            (Tuple.mapFirst
                                (\state ->
                                    { state | expanded = not state.expanded, alreadySeen = True }
                                )
                            )
            }
                |> Cmd.pure

        RemoveItem index ->
            let
                newData =
                    { data | items = List.removeAt index data.items }
            in
            if List.isEmpty newData.items then
                newData
                    |> Cmd.withTrigger config.closeModal

            else
                newData
                    |> Cmd.pure

        ToggleDoNotShowAgain ->
            { data | doNotShowAgainChecked = not data.doNotShowAgainChecked }
                |> Cmd.pure


update : Config msg -> Route -> Flags -> XBStore.Store -> Msg -> Modal -> ( Modal, Cmd msg )
update config route flags xbStore msg modal =
    case msg of
        NoOp ->
            Cmd.pure modal

        SetProjectOrFolderName name ->
            Cmd.pure <|
                if String.length name > NewName.maxLength then
                    -- such long name is not allowed, no-op
                    modal

                else
                    setNewName name modal
                        |> setState Ready

        SwapBasesOrder originIndex destinationIndex ->
            let
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
            in
            case modal of
                ReorderBases data ->
                    let
                        {- This function is to avoid surpassing 0 to length of
                           baseAudiences range
                        -}
                        newFocusedIndex : Int -> Maybe Int
                        newFocusedIndex newIndex_ =
                            if newIndex_ < 0 then
                                Just 0

                            else if newIndex_ >= List.length data.newBasesOrder then
                                Just <| List.length data.newBasesOrder - 1

                            else
                                Just newIndex_

                        originBaseName : String
                        originBaseName =
                            case List.getAt originIndex data.newBasesOrder of
                                Just (ACrosstab.DefaultBase baseAudience) ->
                                    BaseAudience.getCaption baseAudience
                                        |> Caption.getName

                                Just (ACrosstab.SelectableBase { base }) ->
                                    BaseAudience.getCaption base
                                        |> Caption.getName

                                Nothing ->
                                    "moved"
                    in
                    ( ReorderBases
                        { data
                            | newBasesOrder =
                                swapOrderByBasesIndices originIndex
                                    destinationIndex
                                    data.newBasesOrder
                            , baseIndexSelectedToMoveWithKeyboard =
                                newFocusedIndex destinationIndex
                            , ariaMessageForBasesList =
                                Just <|
                                    "Base "
                                        ++ originBaseName
                                        ++ ", position number "
                                        ++ (String.fromInt <| destinationIndex + 1)
                                        ++ " out of "
                                        ++ String.fromInt (List.length data.newBasesOrder)
                                        ++ "."
                        }
                    , Cmd.none
                    )
                        |> Cmd.addTrigger
                            (config.msg <|
                                SetBaseAudienceIndexFocused <|
                                    newFocusedIndex destinationIndex
                            )

                _ ->
                    ( modal, Cmd.none )

        SetBaseAudienceIndexSelectedToMoveWithKeyboard maybeIndex ->
            case modal of
                ReorderBases data ->
                    ( ReorderBases
                        { data
                            | baseIndexSelectedToMoveWithKeyboard =
                                maybeIndex
                        }
                    , Cmd.none
                    )

                _ ->
                    ( modal, Cmd.none )

        SetBaseAudienceIndexFocused maybeIndex ->
            case modal of
                ReorderBases data ->
                    ( ReorderBases { data | focusedBaseIndex = maybeIndex }
                    , case maybeIndex of
                        Just index ->
                            case List.getAt index data.newBasesOrder of
                                Just (ACrosstab.DefaultBase baseAudience) ->
                                    Dom.focus
                                        (BaseAudience.getId baseAudience
                                            |> AudienceItemId.toString
                                        )
                                        |> Task.attempt (\_ -> config.msg NoOp)

                                Just (ACrosstab.SelectableBase { base }) ->
                                    Dom.focus
                                        (BaseAudience.getId base
                                            |> AudienceItemId.toString
                                        )
                                        |> Task.attempt (\_ -> config.msg NoOp)

                                Nothing ->
                                    Cmd.none

                        Nothing ->
                            Cmd.none
                    )

                _ ->
                    ( modal, Cmd.none )

        SetBaseAudienceIndexHovered maybeIndex ->
            case modal of
                ReorderBases data ->
                    ( ReorderBases { data | hoveredBaseIndexForDividingLine = maybeIndex }
                    , Cmd.none
                    )

                _ ->
                    ( modal, Cmd.none )

        ResetReorderBasesModal ->
            case modal of
                ReorderBases data ->
                    ( ReorderBases
                        { data
                            | newBasesOrder = data.initialBasesOrder
                            , focusedBaseIndex = Nothing
                            , baseIndexSelectedToMoveWithKeyboard = Nothing
                            , ariaMessageForBasesList = Nothing
                        }
                    , Cmd.none
                    )

                _ ->
                    ( modal, Cmd.none )

        EditingInput index ->
            case modal of
                AffixGroup data ->
                    ( AffixGroup { data | itemBeingRenamed = Just index }
                    , Dom.focus (affixModalGroupNameId index) |> Task.attempt (\_ -> config.msg NoOp)
                    )

                AffixBase data ->
                    ( AffixBase { data | itemBeingRenamed = Just index }
                    , Dom.focus (affixModalGroupNameId index) |> Task.attempt (\_ -> config.msg NoOp)
                    )

                EditGroup data ->
                    ( EditGroup { data | itemBeingRenamed = Just index }
                    , Dom.focus (editModalGroupNameId index) |> Task.attempt (\_ -> config.msg NoOp)
                    )

                EditBase data ->
                    ( EditBase { data | itemBeingRenamed = Just index }
                    , Dom.focus (editModalGroupNameId index) |> Task.attempt (\_ -> config.msg NoOp)
                    )

                _ ->
                    ( modal, Cmd.none )

        StopEditingInput ->
            case modal of
                AffixGroup data ->
                    ( AffixGroup { data | itemBeingRenamed = Nothing }, Cmd.none )

                AffixBase data ->
                    ( AffixBase { data | itemBeingRenamed = Nothing }, Cmd.none )

                EditGroup data ->
                    ( EditGroup { data | itemBeingRenamed = Nothing }, Cmd.none )

                EditBase data ->
                    ( EditBase { data | itemBeingRenamed = Nothing }, Cmd.none )

                _ ->
                    ( modal, Cmd.none )

        SetGroupNameAt index name ->
            let
                updateCaption zipper =
                    zipper
                        |> Zipper.updateAtIndex index
                            (\item ->
                                let
                                    newName =
                                        String.left Caption.maxUserDefinedNameLength name
                                in
                                { item
                                    | newCaption =
                                        Caption.create
                                            { name = newName
                                            , fullName = newName
                                            , subtitle = Nothing
                                            }
                                }
                            )
                        |> Maybe.withDefault zipper
            in
            case modal of
                AffixGroup data ->
                    AffixGroup { data | zipper = updateCaption data.zipper } |> Cmd.pure

                AffixBase data ->
                    AffixBase { data | zipper = updateCaption data.zipper } |> Cmd.pure

                EditGroup data ->
                    EditGroup { data | zipper = updateCaption data.zipper } |> Cmd.pure

                EditBase data ->
                    EditBase { data | zipper = updateCaption data.zipper } |> Cmd.pure

                _ ->
                    ( modal, Cmd.none )

        SetGroupName name ->
            let
                newName : String
                newName =
                    String.left Caption.maxUserDefinedNameLength <| String.replace "\n" "" name
            in
            modal
                |> updateViewGroup
                    (\m ->
                        { m
                            | caption =
                                m.caption
                                    |> Caption.setSubtitle Nothing
                                    |> Caption.setName newName
                            , hasChanges = m.hasChanges || (newName /= Caption.getName m.caption)
                        }
                    )
                |> updateCurrentViewBaseAudience
                    (\m ->
                        { m
                            | baseAudience =
                                BaseAudience.updateCaption
                                    (Caption.setSubtitle Nothing
                                        >> Caption.setName newName
                                    )
                                    m.baseAudience
                            , hasChanges = m.hasChanges || (newName /= Caption.getName (BaseAudience.getCaption m.baseAudience))
                        }
                    )
                |> updateSaveAsAudience
                    (\m ->
                        { m
                            | caption =
                                m.caption
                                    |> Caption.setSubtitle Nothing
                                    |> Caption.setName newName
                        }
                    )
                |> updateRenameAverage
                    (\m ->
                        { m
                            | caption = Caption.setName newName m.caption
                            , hasChanges = m.hasChanges || (newName /= Caption.getName m.caption)
                        }
                    )
                |> Cmd.pure

        SelectTextInField id ->
            modal
                |> Cmd.with (selectTextInFieldXB2 id)

        KnowledgeBaseLinkClicked name url ->
            modal
                |> Cmd.withTrigger (config.openNewWindow url)
                |> Cmd.add (Analytics.trackEvent flags route Place.CrosstabBuilder <| KnowledgeBaseOpened name url)

        ValidatedOriginalSharingEmail sharingEmail ->
            modal
                |> updateShareProject
                    (\data ->
                        let
                            newOriginalSharedWithEmails =
                                data.originalSharedWithEmails
                                    |> Maybe.map
                                        (NonemptyList.map
                                            (\currentSharingEmail ->
                                                if Data.unwrapSharingEmail currentSharingEmail == Data.unwrapSharingEmail sharingEmail then
                                                    sharingEmail

                                                else
                                                    currentSharingEmail
                                            )
                                        )

                            newState =
                                if Maybe.unwrap False (NonemptyList.any Data.isUncheckedSharingEmail) newOriginalSharedWithEmails then
                                    Processing

                                else
                                    Ready
                        in
                        { data
                            | originalSharedWithEmails = newOriginalSharedWithEmails
                            , state = newState
                        }
                    )
                |> Cmd.with (focusId config sharedEmailInputId)

        RemoveOriginalSharee sharee ->
            updateShareProject
                (\data ->
                    { data
                        | originalSharedWithEmails =
                            data.originalSharedWithEmails
                                |> Maybe.andThen (NonemptyList.filter ((/=) sharee))
                        , hasChanges = True
                    }
                )
                modal
                |> Cmd.pure

        RemoveOriginalSharedOrg orgId ->
            updateShareProject
                (\data ->
                    { data
                        | originalSharedWithOrgs =
                            data.originalSharedWithOrgs
                                |> Maybe.andThen (NonemptyList.filter ((/=) orgId))
                        , shareWithOrgChecked =
                            if XB2.Share.Data.Id.unwrap orgId == Maybe.withDefault "" flags.user.organisationId then
                                False

                            else
                                data.shareWithOrgChecked
                        , hasChanges = True
                    }
                )
                modal
                |> Cmd.pure

        SetSharingNote note ->
            updateShareProject
                (\({ project } as data) ->
                    if String.length note > sharingNoteMaxLength then
                        data

                    else
                        { data | project = { project | sharingNote = note }, hasChanges = True }
                )
                modal
                |> Cmd.pure

        ToggleSharingWithOrg ->
            updateShareProject
                (\data ->
                    { data
                        | shareWithOrgChecked = not data.shareWithOrgChecked
                        , originalSharedWithOrgs =
                            if not data.shareWithOrgChecked then
                                Nothing

                            else
                                data.originalSharedWithOrgs
                        , hasChanges = True
                    }
                )
                modal
                |> Cmd.pure

        SelectMoveToFolder folder ->
            Cmd.pure <|
                updateMoveToFolderProject
                    (\m ->
                        let
                            selectedFolderId =
                                if Just folder.id == m.selectedFolderId then
                                    Nothing

                                else
                                    Just folder.id
                        in
                        { m
                            | selectedFolderId = selectedFolderId
                            , canMoveToFolder =
                                (selectedFolderId /= m.initialFolderId)
                                    && (selectedFolderId /= Nothing)
                        }
                    )
                    modal

        AddAsBasesSetActiveLogic index ->
            Cmd.pure <|
                case modal of
                    AddAsNewBases data ->
                        { data
                            | logicButtons =
                                data.logicButtons
                                    |> List.indexedMap
                                        (\itemIndex item ->
                                            { item | active = index == itemIndex }
                                        )
                        }
                            |> AddAsNewBases

                    _ ->
                        modal

        MergeRowOrColumSetActiveLogic index ->
            Cmd.pure <|
                case modal of
                    MergeRowOrColum data ->
                        { data
                            | logicButtons =
                                data.logicButtons
                                    |> List.indexedMap
                                        (\itemIndex item ->
                                            { item | active = index == itemIndex }
                                        )
                        }
                            |> MergeRowOrColum

                    _ ->
                        modal

        AddAsBasesToggleInfo index ->
            let
                updateItemSelected modalData type_ =
                    case modalData.expandedItem of
                        Just num ->
                            if num == index then
                                type_ { modalData | expandedItem = Nothing }

                            else
                                type_ { modalData | expandedItem = Just index }

                        Nothing ->
                            type_ { modalData | expandedItem = Just index }
            in
            Cmd.pure <|
                case modal of
                    AddAsNewBases data ->
                        { data
                            | selectedItems =
                                data.selectedItems
                                    |> List.updateAt index
                                        (Tuple.mapFirst
                                            (\state ->
                                                { state | expanded = not state.expanded, alreadySeen = True }
                                            )
                                        )
                        }
                            |> AddAsNewBases

                    AffixGroup modalData ->
                        updateItemSelected modalData AffixGroup

                    AffixBase modalData ->
                        updateItemSelected modalData AffixBase

                    EditGroup modalData ->
                        updateItemSelected modalData EditGroup

                    EditBase modalData ->
                        updateItemSelected modalData EditBase

                    _ ->
                        modal

        MergeRowOrColumToggleInfo index ->
            let
                updateItemSelected modalData type_ =
                    case modalData.expandedItem of
                        Just num ->
                            if num == index then
                                type_ { modalData | expandedItem = Nothing }

                            else
                                type_ { modalData | expandedItem = Just index }

                        Nothing ->
                            type_ { modalData | expandedItem = Just index }
            in
            Cmd.pure <|
                case modal of
                    MergeRowOrColum data ->
                        { data
                            | selectedItems =
                                data.selectedItems
                                    |> List.updateAt index
                                        (Tuple.mapFirst
                                            (\state ->
                                                { state | expanded = not state.expanded, alreadySeen = True }
                                            )
                                        )
                        }
                            |> MergeRowOrColum

                    AffixGroup modalData ->
                        updateItemSelected modalData AffixGroup

                    AffixBase modalData ->
                        updateItemSelected modalData AffixBase

                    EditGroup modalData ->
                        updateItemSelected modalData EditGroup

                    EditBase modalData ->
                        updateItemSelected modalData EditBase

                    _ ->
                        modal

        UpdateRemoveRowsColumnsModal action ->
            case modal of
                ConfirmRemoveRowsColumns data ->
                    let
                        ( newData, cmd ) =
                            bulkDeleteModalActionsUpdate config action data
                    in
                    ( ConfirmRemoveRowsColumns newData, cmd )

                _ ->
                    Cmd.pure modal

        UpdateConfirmRemoveBasesModal action ->
            case modal of
                ConfirmRemoveBases data ->
                    let
                        ( newData, cmd ) =
                            bulkDeleteModalActionsUpdate config action data
                    in
                    ( ConfirmRemoveBases newData, cmd )

                _ ->
                    Cmd.pure modal

        ModalBrowserMsg mbMsg ->
            case modal of
                AttributesModal data ->
                    ModalBrowser.update (config.browser data) route flags xbStore mbMsg data.browserModel
                        |> Tuple.mapFirst (\newModel -> AttributesModal { data | browserModel = newModel })

                _ ->
                    Cmd.pure modal

        OpenAttributeBrowser modalData ->
            Cmd.pure <| AttributesModal modalData

        ChooseOneModalMsg chooseOneMsg ->
            case modal of
                ChooseHeatmapMetric data ->
                    ChooseOne.update chooseOneMsg data.chooseOneModal
                        |> Tuple.mapFirst (\newModel -> ChooseHeatmapMetric { data | chooseOneModal = newModel })
                        |> Glue.map (config.msg << ChooseOneModalMsg)

                _ ->
                    Cmd.pure modal

        ChooseManyModalMsg chooseManyMsg ->
            case modal of
                ChooseMetrics data ->
                    ChooseMany.update chooseManyMsg data.chooseManyModal
                        |> Tuple.mapFirst (\newModel -> ChooseMetrics { data | chooseManyModal = newModel })
                        |> Glue.map (config.msg << ChooseManyModalMsg)

                _ ->
                    Cmd.pure modal

        ReorderBasesModalDndMsg dndMsg ->
            case modal of
                ReorderBases data ->
                    let
                        ( newDndModel, newBasesOrder ) =
                            reorderBasesModalDndSystem.update dndMsg
                                data.dragAndDropSystem
                                data.newBasesOrder
                    in
                    ( ReorderBases
                        { data
                            | dragAndDropSystem = newDndModel
                            , newBasesOrder = newBasesOrder
                        }
                    , reorderBasesModalDndSystem.commands newDndModel
                        |> Cmd.map config.msg
                    )

                _ ->
                    Cmd.pure modal

        AutocompleteInputMsg subMsg ->
            case modal of
                ShareProject data ->
                    Autocomplete.update
                        { fetchSuggestions =
                            \term ->
                                XB2.Share.Data.Platform2.fetchFullUserEmails term flags
                                    |> XB2.Share.Gwi.Http.cmdMap (List.filter (\{ email } -> email /= flags.user.email))
                        , toName = .email
                        , validate =
                            \email ->
                                Data.validateUserEmailWithoutErrorDecoding email flags
                                    |> Cmd.map
                                        (Result.map Data.getValidFullUserEmail)
                        }
                        subMsg
                        data.autocompleteModel
                        |> Tuple.mapFirst
                            (\newModel_ ->
                                let
                                    newModel =
                                        { newModel_
                                            | selectedItems =
                                                newModel_.selectedItems
                                                    |> List.filter
                                                        (\item ->
                                                            case data.originalSharedWithEmails of
                                                                Nothing ->
                                                                    True

                                                                Just list ->
                                                                    not <| NonemptyList.any (Data.unwrapSharingEmail >> (==) item.email) list
                                                        )
                                        }
                                in
                                ShareProject
                                    { data
                                        | autocompleteModel = newModel
                                        , hasChanges = not <| List.isEmpty newModel.selectedItems
                                        , emailsForSharing = List.map Data.fullUserEmailToValidSharingEmail newModel.selectedItems
                                    }
                            )
                        |> Glue.map (AutocompleteInputMsg >> config.msg)

                _ ->
                    Cmd.pure modal


resolveValidateEmailResponse : { email : String } -> Result (XB2.Share.Gwi.Http.Error err) SharingEmail -> SharingEmail
resolveValidateEmailResponse email result =
    case result of
        {- we could `case` on the custom error to
           distinguish between eg. UserNotFound and
           UserNotProfessional, but right now they
           both look the same, so what's the point...
        -}
        Err (XB2.Share.Gwi.Http.CustomError _ _ _) ->
            InvalidEmail email

        Err _ ->
            UncheckedEmail email

        Ok validMail ->
            validMail


{-| Before XB store starts saving/updating/... a project, modal needs to show spinner etc.
-}
updateAfterStoreAction : Modal -> Modal
updateAfterStoreAction modal =
    modal
        |> setState Processing


focus : Config msg -> Modal -> Cmd msg
focus config modal =
    case modal of
        SaveProjectAsNew _ ->
            focusName config

        RenameProject _ ->
            focusName config

        SetNameForNewProject _ ->
            focusName config

        SetNameForProjectCopy _ ->
            focusName config

        DuplicateProject _ ->
            focusName config

        CreateFolder _ ->
            focusName config

        RenameFolder _ ->
            focusName config

        ViewGroup _ ->
            focusAndSelectName config

        RenameAverage _ ->
            focusAndSelectName config

        RenameBaseAudience _ ->
            focusAndSelectName config

        SaveAsAudience _ ->
            focusAndSelectName config

        _ ->
            Cmd.none


focusName : Config msg -> Cmd msg
focusName config =
    Task.attempt
        (always <| config.msg NoOp)
        (Dom.focus nameFieldId)


focusAndSelectName : Config msg -> Cmd msg
focusAndSelectName config =
    Task.attempt
        (always <| config.msg (SelectTextInField nameFieldId))
        (Dom.focus nameFieldId)


port selectTextInFieldXB2 : String -> Cmd msg



-- SUBSCRIPTIONS


escDecoder : msg -> Decoder msg
escDecoder msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Escape" ->
                        Decode.succeed msg

                    _ ->
                        Decode.fail "Not the key we're interested in"
            )


subscriptions : Config msg -> Modal -> Sub msg
subscriptions config modal =
    let
        ( escMsg, extraSubscriptions ) =
            case modal of
                RenameProject _ ->
                    ( config.closeModal, Sub.none )

                SetNameForNewProject _ ->
                    ( config.closeModal, Sub.none )

                SetNameForProjectCopy _ ->
                    ( config.closeModal, Sub.none )

                DuplicateProject _ ->
                    ( config.closeModal, Sub.none )

                ConfirmDeleteProject _ ->
                    ( config.closeModal, Sub.none )

                ConfirmDeleteProjects _ ->
                    ( config.closeModal, Sub.none )

                ConfirmUnshareMe _ ->
                    ( config.closeModal, Sub.none )

                SaveProjectAsNew _ ->
                    ( config.closeModal, Sub.none )

                ShareProject _ ->
                    ( config.closeModal, Sub.none )

                CreateFolder _ ->
                    ( config.closeModal, Sub.none )

                MoveToFolder _ ->
                    ( config.closeModal, Sub.none )

                RenameFolder _ ->
                    ( config.closeModal, Sub.none )

                ConfirmDeleteFolder _ ->
                    ( config.closeModal, Sub.none )

                ConfirmUngroupFolder _ ->
                    ( config.closeModal, Sub.none )

                ChooseMetrics _ ->
                    ( config.closeModal, Sub.none )

                AttributesModal ({ browserModel } as data) ->
                    ( config.closeModal, ModalBrowser.subscriptions browserModel |> Sub.map (config.browser data |> .msg) )

                ViewGroup _ ->
                    ( config.closeModal, Sub.none )

                RenameAverage _ ->
                    ( config.closeModal, Sub.none )

                RenameBaseAudience _ ->
                    ( config.closeModal, Sub.none )

                AffixGroup _ ->
                    ( config.closeModal, Sub.none )

                FetchQuestionsForEditModal ->
                    ( config.closeModal, Sub.none )

                EditGroup _ ->
                    ( config.closeModal, Sub.none )

                AffixBase _ ->
                    ( config.closeModal, Sub.none )

                EditBase _ ->
                    ( config.closeModal, Sub.none )

                ChooseHeatmapMetric _ ->
                    ( config.closeModal, Sub.none )

                UnsavedChangesAlert _ ->
                    ( config.closeModal, Sub.none )

                SaveAsAudience _ ->
                    ( config.closeModal, Sub.none )

                ConfirmFullLoadForHeatmap _ _ ->
                    ( config.closeModal, Sub.none )

                ConfirmFullLoadForExport _ _ _ ->
                    ( config.closeModal, Sub.none )

                ConfirmFullLoadForExportFromList _ _ ->
                    ( config.closeModal, Sub.none )

                ConfirmCancelExport ->
                    ( config.closeModal, Sub.none )

                ConfirmCancelExportFromList ->
                    ( config.closeModal, Sub.none )

                ConfirmCancelApplyingHeatmap ->
                    ( config.closeModal, Sub.none )

                ConfirmActionWithViewSettings _ ->
                    ( config.turnOffViewSettingsAndContinue, Sub.none )

                ConfirmCellsLoadForSorting _ _ ->
                    ( config.closeModal, Sub.none )

                ConfirmCancelCellsSorting ->
                    ( config.closeModal, Sub.none )

                ConfirmCancelFullScreenTableLoad ->
                    ( config.closeModal, Sub.none )

                AddAsNewBases _ ->
                    ( config.closeModal, Sub.none )

                MergeRowOrColum _ ->
                    ( config.closeModal, Sub.none )

                ConfirmRemoveRowsColumns _ ->
                    ( config.closeModal, Sub.none )

                ConfirmRemoveBases _ ->
                    ( config.closeModal, Sub.none )

                GenericAlert _ ->
                    ( config.closeModal, Sub.none )

                ErrorModal _ ->
                    ( config.closeModal, Sub.none )

                MoveOutOfFolderModal _ ->
                    ( config.closeModal, Sub.none )

                ReorderBases data ->
                    ( config.closeModal
                    , Sub.batch
                        [ reorderBasesModalDndSystem.subscriptions data.dragAndDropSystem
                            |> Sub.map config.msg
                        , case data.baseIndexSelectedToMoveWithKeyboard of
                            Just index ->
                                Browser.Events.onKeyDown
                                    (Decode.field "key" Decode.string
                                        |> Decode.andThen
                                            (\key ->
                                                case key of
                                                    "ArrowUp" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SwapBasesOrder
                                                                    index
                                                                    (index - 1)
                                                                )

                                                    "ArrowDown" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SwapBasesOrder
                                                                    index
                                                                    (index + 1)
                                                                )

                                                    -- Space looks like this
                                                    " " ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexSelectedToMoveWithKeyboard
                                                                    Nothing
                                                                )

                                                    "Enter" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexSelectedToMoveWithKeyboard
                                                                    Nothing
                                                                )

                                                    _ ->
                                                        Decode.fail "We do not care about this key."
                                            )
                                    )

                            Nothing ->
                                Sub.none
                        , let
                            {- This function is to avoid surpassing 0 to length of
                               baseAudiences range
                            -}
                            newFocusedIndex : Int -> Maybe Int
                            newFocusedIndex newIndex_ =
                                if newIndex_ < 0 then
                                    Just 0

                                else if newIndex_ >= List.length data.newBasesOrder then
                                    Just <| List.length data.newBasesOrder - 1

                                else
                                    Just newIndex_
                          in
                          case ( data.focusedBaseIndex, data.baseIndexSelectedToMoveWithKeyboard ) of
                            ( Just index, Nothing ) ->
                                Browser.Events.onKeyDown
                                    (Decode.field "key" Decode.string
                                        |> Decode.andThen
                                            (\key ->
                                                case key of
                                                    "ArrowUp" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexFocused <|
                                                                    newFocusedIndex (index - 1)
                                                                )

                                                    "ArrowDown" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexFocused <|
                                                                    newFocusedIndex (index + 1)
                                                                )

                                                    -- Space looks like this
                                                    " " ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexSelectedToMoveWithKeyboard <|
                                                                    Just index
                                                                )

                                                    "Enter" ->
                                                        Decode.succeed <|
                                                            config.msg
                                                                (SetBaseAudienceIndexSelectedToMoveWithKeyboard <|
                                                                    Just index
                                                                )

                                                    _ ->
                                                        Decode.fail "We do not care about this key."
                                            )
                                    )

                            _ ->
                                Sub.none
                        ]
                    )
    in
    Sub.batch
        [ Browser.Events.onKeyUp (escDecoder escMsg)
        , extraSubscriptions
        ]



-- VIEW


moduleClass : ClassName
moduleClass =
    WeakCss.namespace "xb2-modal"


nameFieldId : String
nameFieldId =
    "modal-name-field"


affixModalGroupNameId : Int -> String
affixModalGroupNameId index =
    "affix-modal-group-name-" ++ String.fromInt index


editModalGroupNameId : Int -> String
editModalGroupNameId index =
    "edit-modal-group-name-" ++ String.fromInt index


{-| TODO: Pass primitives properly through a record.
-}
view :
    Flags
    -> Config msg
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> String
    -> Bool
    -> Modal
    -> Html msg
view flags config xbStore p2Store attributeBrowserInitialState shouldPassInitialStateToAttributeBrowser modal =
    case modal of
        ChooseMetrics m ->
            chooseMetricsContents config m

        ChooseHeatmapMetric d ->
            chooseHeatmapMetricContents config d

        _ ->
            let
                size : ModalSize
                size =
                    modalSize modal

                closeOnOverlayClicked =
                    case modal of
                        RenameFolder _ ->
                            False

                        RenameAverage _ ->
                            False

                        RenameBaseAudience _ ->
                            False

                        ViewGroup _ ->
                            False

                        AffixGroup _ ->
                            False

                        AffixBase _ ->
                            False

                        EditGroup _ ->
                            False

                        EditBase _ ->
                            False

                        -- Not too sure about what this does
                        SaveAsAudience _ ->
                            False

                        _ ->
                            True
            in
            Html.div
                [ moduleClass
                    |> WeakCss.withActiveStates
                        [ case size of
                            Small ->
                                "small-modal"

                            Medium ->
                                "medium-modal"

                            MediumFlexible ->
                                "medium-flexible-modal"

                            Large ->
                                "large-modal"

                            LargeCapped ->
                                "large-capped-modal"

                            WebComponent ->
                                "web-component-modal"
                        ]
                ]
                [ Html.div
                    [ WeakCss.nestMany [ "modal", "overlay" ] moduleClass
                    , Attrs_.attributeIf closeOnOverlayClicked <| Events.onMouseDown config.closeModal
                    ]
                    [ Html.div
                        [ WeakCss.nestMany [ "modal", "container" ] moduleClass
                        , Events.stopPropagationOn "mousedown" <| Decode.succeed ( config.noOp, True )
                        ]
                        (contents flags
                            config
                            xbStore
                            p2Store
                            attributeBrowserInitialState
                            shouldPassInitialStateToAttributeBrowser
                            modal
                        )
                    ]
                ]


heatmapMetrics : List Metric
heatmapMetrics =
    {- Size (Universe) and Sample (Responses) will be reinstated once we work
       on conditional formatting; at that point we can remove the
       `allMetrics` argument from `metricsSelectionTable` and use
       `Data.defaultMetadata.activeMetrics` again
    -}
    [ Metric.ColumnPercentage
    , Metric.RowPercentage
    , Metric.Index
    ]


{-| TODO: Pass primitives properly through a record.
-}
attributesModalContents :
    Flags
    -> Config msg
    -> XB2.Share.Store.Platform2.Store
    -> String
    -> Bool
    -> AttributesModalData
    -> List (Html msg)
attributesModalContents flags config p2Store attributeBrowserInitialState shouldPassInitialStateToAttributeBrowser data =
    let
        modalBrowserView =
            case data.modalType of
                AddRowColumnToTable ->
                    ModalBrowser.addToTableView

                AffixRowColumn affixedFrom ->
                    ModalBrowser.affixTableView affixedFrom

                AddBaseAudience ->
                    ModalBrowser.addBaseView

                AffixBaseAudience ->
                    ModalBrowser.affixBaseView

                ReplaceDefaultBaseAudience ->
                    ModalBrowser.replaceDefaultBaseView

                EditBaseAudience ->
                    ModalBrowser.editBaseView

                EditRowColumn ->
                    ModalBrowser.editTableView

        canUseAverage =
            data.modalType == AddRowColumnToTable
    in
    RemoteData.succeed (\d dn w l a -> ( ( d, dn ), ( w, l, a ) ))
        |> RemoteData.andMap p2Store.datasets
        |> RemoteData.andMap p2Store.datasetsToNamespaces
        |> RemoteData.andMap p2Store.waves
        |> RemoteData.andMap p2Store.locations
        |> RemoteData.andMap p2Store.audienceFolders
        |> remoteDataView
            (\( ( datasets, datasetsToNamespaces ), ( waves, locations, audienceFolders ) ) ->
                modalBrowserView
                    flags
                    (config.browser data)
                    moduleClass
                    data.selectedBasesCount
                    canUseAverage
                    datasets
                    datasetsToNamespaces
                    p2Store.lineages
                    waves
                    locations
                    attributeBrowserInitialState
                    shouldPassInitialStateToAttributeBrowser
                    audienceFolders
                    data.affixingOrEditingItems
                    data.browserModel
            )


chooseHeatmapMetricContents : Config msg -> ChooseHeatmapMetricData -> Html msg
chooseHeatmapMetricContents config { chooseOneModal } =
    ChooseOne.view (chooseOneHeatmapMetricsConfig config) chooseOneModal


unsavedChangesAlertContents : Config msg -> { newRoute : Route } -> List (Html msg)
unsavedChangesAlertContents config { newRoute } =
    [ Html.div [ WeakCss.nest "unsaved-alert" moduleClass ]
        [ Html.header [ WeakCss.nestMany [ "unsaved-alert", "header" ] moduleClass ]
            [ Html.h1
                [ WeakCss.nestMany [ "unsaved-alert", "headline" ] moduleClass
                ]
                [ Html.text "Save your Crosstab" ]
            , Html.button
                [ WeakCss.nestMany [ "unsaved-alert", "header", "close" ] moduleClass
                , Events.onClick config.closeModal
                ]
                [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 40 ] P2Icons.cross ]
            ]
        , Html.div [ WeakCss.nestMany [ "unsaved-alert", "content" ] moduleClass ]
            [ Html.text "Leaving without saving will lose all unsaved changes."
            , Html.br [] []
            , Html.text "Would you like to save your Crosstab?"
            ]
        , Html.footer [ WeakCss.nestMany [ "unsaved-alert", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "unsaved-alert", "action-link" ] moduleClass
                , Events.onClick <| config.ignoreUnsavedChangesAndContinue newRoute
                ]
                [ Html.text "Discard" ]
            , Html.button
                [ WeakCss.nestMany [ "unsaved-alert", "primary-button" ] moduleClass
                , Events.onClick <| config.saveUnsavedProjectAndContinue newRoute
                ]
                [ Html.text "Save" ]
            ]
        ]
    ]


confirmFullLoadContents : msg -> msg -> Int -> String -> String -> String -> List (Html msg)
confirmFullLoadContents confirm cancel notLoadedCount title actionName cancelLabel =
    [ Html.div [ WeakCss.nest "general-alert" moduleClass ]
        [ Html.header
            [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                [ Html.text title ]
            ]
        , Html.div
            [ WeakCss.nestMany [ "general-alert", "content" ] moduleClass ]
            [ Html.p
                [ WeakCss.nestMany [ "general-alert", "content", "text" ] moduleClass ]
                [ Html.text <| "In order to " ++ actionName ++ ", we need to load "
                , Html.strong [] [ Html.text <| String.fromInt notLoadedCount ]
                , Html.text " cells."
                ]
            , Html.p
                [ WeakCss.nestMany [ "general-alert", "content", "text" ] moduleClass ]
                [ Html.text "This may take a few minutes, would you like to continue?"
                ]
            ]
        , Html.footer
            [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                , Events.onClick cancel
                , Attrs.id "modal-confirmexport-close-button"
                ]
                [ Html.text cancelLabel ]
            , Html.button
                [ WeakCss.nestMany [ "general-alert", "primary-button" ] moduleClass
                , Events.onClick confirm
                ]
                [ Html.text "Continue" ]
            ]
        ]
    ]


confirmCancelContents : Config msg -> msg -> String -> String -> List (Html msg)
confirmCancelContents config msg header text =
    [ Html.div
        [ WeakCss.nest "general-alert" moduleClass ]
        [ Html.header
            [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                [ Html.text header ]
            ]
        , Html.div
            [ WeakCss.nestMany [ "general-alert", "content" ] moduleClass ]
            [ Html.p [] [ Html.text text ] ]
        , Html.footer
            [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                , Events.onClick config.closeModal
                ]
                [ Html.text "No" ]
            , Html.button
                [ WeakCss.nestMany [ "general-alert", "primary-button" ] moduleClass
                , Events.onClick msg
                ]
                [ Html.text "Yes" ]
            ]
        ]
    ]


fetchQuestionsForEditModalContents : Config msg -> Html msg
fetchQuestionsForEditModalContents config =
    LoaderWithoutProgressModal.view { cancelMsg = config.noOp }
        { className = WeakCss.add "fetch-questions-for-edit-modal" moduleClass
        , loadingLabel = "Fetching question data…"
        }


confirmActionWithViewSettingsContents : Config msg -> { viewSettingsAction : ViewSettingsAction, isSorting : Bool, isHeatmap : Bool } -> List (Html msg)
confirmActionWithViewSettingsContents config { viewSettingsAction, isSorting, isHeatmap } =
    let
        textIf cond t =
            if cond then
                Just t

            else
                Nothing

        copyTypes =
            [ textIf isSorting "sorting"
            , textIf isHeatmap "heatmap"
            ]
                |> List.filterMap identity
                |> String.join ", "

        copy =
            case viewSettingsAction of
                AddingNewBases ->
                    "Do you want to apply your current view options (" ++ copyTypes ++ ") to your new bases?"

                ChangeFilters ->
                    "Do you want to keep your current view options (" ++ copyTypes ++ ")?"
    in
    [ Html.div [ WeakCss.nest "general-alert" moduleClass ]
        [ Html.header
            [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                [ Html.text "Apply current view options" ]
            ]
        , Html.div
            [ WeakCss.nestMany [ "general-alert", "content" ] moduleClass ]
            [ Html.p [] [ Html.text copy ]
            , Html.p [] [ Html.text "To continue without your current settings being applied, they will be removed from all other bases." ]
            ]
        , Html.footer
            [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                , Events.onClick config.turnOffViewSettingsAndContinue
                ]
                [ Html.text "No, remove settings" ]
            , Html.button
                [ WeakCss.nestMany [ "general-alert", "primary-button" ] moduleClass
                , Events.onClick config.keepViewSettingsAndContinue
                ]
                [ Html.text "Yes, continue" ]
            ]
        ]
    ]


sharedEmailInputId : String
sharedEmailInputId =
    "xb-modal-sharing-email-input"


shareProjectContents : Config msg -> Flags -> ShareProjectData -> List (Html msg)
shareProjectContents config flags ({ project, originalSharedWithEmails, originalSharedWithOrgs, shareWithOrgChecked, state, hasChanges, emailsForSharing } as data) =
    let
        getOnlyValidEmails : NonEmpty SharingEmail -> Maybe (NonEmpty CrosstabUser)
        getOnlyValidEmails list =
            NonemptyList.filterMap Data.getValidEmailCrosstabUser list

        onlyValidOriginalEmails : Maybe (NonEmpty CrosstabUser)
        onlyValidOriginalEmails =
            Maybe.andThen getOnlyValidEmails originalSharedWithEmails

        onlyValidEmails : Maybe (NonEmpty CrosstabUser)
        onlyValidEmails =
            NonemptyList.fromList emailsForSharing
                |> Maybe.andThen getOnlyValidEmails
                |> Maybe.map (Maybe.unwrap identity NonemptyList.append onlyValidOriginalEmails)
                |> Maybe.orElse onlyValidOriginalEmails

        containsOnlyValidEmails : Bool
        containsOnlyValidEmails =
            case onlyValidEmails of
                Just validEmails ->
                    let
                        originalEmailsLength : Int
                        originalEmailsLength =
                            Maybe.unwrap 0 NonemptyList.length originalSharedWithEmails
                    in
                    NonemptyList.length validEmails == (List.length emailsForSharing + originalEmailsLength)

                Nothing ->
                    List.isEmpty emailsForSharing && (originalSharedWithEmails == Nothing)

        readOnly : Bool
        readOnly =
            project.shared == Data.SharedByLink

        canBeSaved : Bool
        canBeSaved =
            hasChanges && containsOnlyValidEmails

        addSharingWithOrgIfNeeded shared =
            if shareWithOrgChecked then
                case flags.user.organisationId of
                    Just orgId ->
                        let
                            org =
                                Data.OrgSharee <| XB2.Share.Data.Id.fromString orgId
                        in
                        case shared of
                            Data.MyPrivateCrosstab ->
                                Data.MySharedCrosstab <| NonemptyList.singleton org

                            Data.SharedBy _ _ ->
                                shared

                            Data.MySharedCrosstab sharees ->
                                Data.MySharedCrosstab <|
                                    if NonemptyList.member org sharees then
                                        sharees

                                    else
                                        NonemptyList.cons org sharees

                            Data.SharedByLink ->
                                shared

                    Nothing ->
                        shared

            else
                shared

        addOriginalSharedWithOrgs shared =
            case originalSharedWithOrgs of
                Just list ->
                    case shared of
                        Data.MyPrivateCrosstab ->
                            Data.MySharedCrosstab <| NonemptyList.map Data.OrgSharee list

                        Data.SharedBy _ _ ->
                            shared

                        Data.SharedByLink ->
                            shared

                        Data.MySharedCrosstab sharees ->
                            sharees
                                |> NonemptyList.append (NonemptyList.map Data.OrgSharee list)
                                |> Data.MySharedCrosstab

                Nothing ->
                    shared

        mergedShared : Shared
        mergedShared =
            (case onlyValidEmails of
                Just validEmails ->
                    if containsOnlyValidEmails then
                        validEmails
                            |> NonemptyList.map Data.UserSharee
                            |> Data.MySharedCrosstab

                    else
                        MyPrivateCrosstab

                Nothing ->
                    MyPrivateCrosstab
            )
                |> addSharingWithOrgIfNeeded
                |> addOriginalSharedWithOrgs

        shareBtnAttributes : List (Html.Attribute msg)
        shareBtnAttributes =
            WeakCss.nestMany [ "share-modal", "primary-button" ] moduleClass
                :: (case ( state, canBeSaved ) of
                        ( Ready, True ) ->
                            [ Events.onClick <| config.shareProject { project | shared = mergedShared } ]

                        _ ->
                            [ Attrs.disabled True ]
                   )

        alreadySharedWithSome =
            originalSharedWithEmails /= Nothing || originalSharedWithOrgs /= Nothing

        existingSharingEmailsView =
            let
                removeBtnView removeAction =
                    Html.i
                        [ WeakCss.nestMany [ "share-modal", "email", "icon" ] moduleClass
                        , Events.onClick <| config.msg removeAction
                        ]
                        [ XB2.Share.Icons.icon [ XB2.Share.Icons.height 10 ] P2Icons.crossSmall ]

                existingShareeView name removeTooltip tooltipPosition activeStates removeButton =
                    Html.div
                        [ WeakCss.addMany
                            [ "share-modal", "email" ]
                            moduleClass
                            |> WeakCss.withActiveStates activeStates
                        ]
                        [ Html.text name
                        , P2Cooltip.view
                            { offset = Nothing
                            , type_ = XB2.Share.CoolTip.Normal
                            , position = tooltipPosition
                            , wrapperAttributes = []
                            , targetAttributes = []
                            , targetHtml = [ removeButton ]
                            , tooltipAttributes = []
                            , tooltipHtml = Html.text removeTooltip
                            }
                        ]

                originalOrgs =
                    case originalSharedWithOrgs of
                        Just orgs ->
                            orgs
                                |> NonemptyList.toList
                                |> List.map
                                    (\orgId ->
                                        let
                                            orgName =
                                                Maybe.withDefault ("Organisation: " ++ XB2.Share.Data.Id.unwrap orgId) <|
                                                    if Just (XB2.Share.Data.Id.unwrap orgId) == flags.user.organisationId then
                                                        flags.user.organisationName

                                                    else
                                                        Nothing
                                        in
                                        existingShareeView
                                            orgName
                                            ("This action will remove permissions to\nview this Crosstab from everyone at " ++ orgName)
                                            XB2.Share.CoolTip.BottomRight
                                            [ "valid" ]
                                            (removeBtnView <| RemoveOriginalSharedOrg orgId)
                                    )

                        Nothing ->
                            []

                originalEmails =
                    case originalSharedWithEmails of
                        Just sharedWithList ->
                            sharedWithList
                                |> NonemptyList.toList
                                |> List.map
                                    (\sharedWith ->
                                        let
                                            ( name, states ) =
                                                case sharedWith of
                                                    Data.UncheckedEmail { email } ->
                                                        ( email, [ "not-validated" ] )

                                                    Data.ValidEmail { email } ->
                                                        ( email, [ "valid" ] )

                                                    Data.InvalidEmail { email } ->
                                                        ( email, [ "invalid" ] )
                                        in
                                        existingShareeView
                                            name
                                            "Remove"
                                            XB2.Share.CoolTip.Bottom
                                            states
                                            (removeBtnView <| RemoveOriginalSharee sharedWith)
                                    )

                        Nothing ->
                            []
            in
            (originalOrgs ++ originalEmails)
                |> Html.div [ WeakCss.nestMany [ "share-modal", "current-emails" ] moduleClass ]

        noteLength =
            String.length project.sharingNote

        notesView =
            Html.div [ WeakCss.nestMany [ "share-modal", "note" ] moduleClass ]
                [ Html.textarea
                    ([ WeakCss.addMany [ "share-modal", "note", "textarea" ] moduleClass
                        |> WeakCss.withStates [ ( "disabled", readOnly ) ]
                     , Attrs_.attributeIf (not readOnly) <| Events.onInput <| config.msg << SetSharingNote
                     , Attrs.rows 8
                     , Attrs.placeholder "Your message"
                     , Attrs.value project.sharingNote
                     , Attrs.disabled readOnly
                     ]
                        |> Attrs.withDisabledGrammarly
                    )
                    []
                , Html.div
                    [ WeakCss.addMany [ "share-modal", "note", "limit-info" ] moduleClass
                        |> WeakCss.withStates [ ( "reached", noteLength + 10 >= sharingNoteMaxLength ) ]
                    ]
                    [ Html.text (String.fromInt noteLength ++ "/" ++ String.fromInt sharingNoteMaxLength)
                    ]
                ]

        userOrgName =
            flags.user.organisationName
                |> Maybe.withDefault "Your organisation"

        shareWithOrgView checked =
            Html.div
                [ WeakCss.addMany [ "share-modal", "with-org", "checkbox" ] moduleClass
                    |> WeakCss.withStates [ ( "checked", checked ), ( "disabled", readOnly ) ]
                ]
                [ Html.label
                    [ WeakCss.nestMany [ "share-modal", "with-org", "checkbox", "label" ] moduleClass
                    , Attrs_.attributeIf (not readOnly) <| Events.onClick <| config.msg ToggleSharingWithOrg
                    ]
                    [ Html.i
                        [ WeakCss.nestMany [ "share-modal", "with-org", "checkbox", "icon" ] moduleClass ]
                        [ XB2.Share.Icons.icon [] <|
                            if readOnly then
                                P2Icons.checkboxCrossed

                            else if checked then
                                P2Icons.checkboxFilled

                            else
                                P2Icons.checkboxUnfilled
                        ]
                    , Html.text "Share with everyone at"
                    , Html.strong [ WeakCss.nestMany [ "share-modal", "with-org", "checkbox", "org-name" ] moduleClass ] [ Html.text userOrgName ]
                    ]
                ]
    in
    [ Html.div [ WeakCss.nest "share-modal" moduleClass ]
        [ Html.viewIfLazy readOnly
            (\() ->
                Html.div [ WeakCss.nestMany [ "share-modal", "read-only-info" ] moduleClass ]
                    [ XB2.Share.Icons.icon [] P2Icons.eye
                    , Html.text "You have view-only access and cannot change the sharing settings. You can copy the link."
                    ]
            )
        , Html.header
            [ WeakCss.nestMany [ "share-modal", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "share-modal", "headline" ] moduleClass
                , Attrs.id "share-modal-focus-text"
                , Attrs.tabindex 0
                ]
                [ Html.text "Share crosstab" ]
            ]
        , Html.div
            [ WeakCss.nestMany [ "share-modal", "content" ] moduleClass ]
            [ Html.div [ WeakCss.nest "share-modal" moduleClass ]
                [ Html.div [ WeakCss.nestMany [ "share-modal", "emails-container" ] moduleClass ]
                    [ Html.label
                        [ Attrs.for sharedEmailInputId
                        , WeakCss.nestMany [ "share-modal", "label" ] moduleClass
                        ]
                        [ if readOnly then
                            let
                                autocompleteClass : ClassName
                                autocompleteClass =
                                    WeakCss.addMany [ "share-modal", "autocomplete" ] moduleClass
                            in
                            Html.div [ WeakCss.nest "container" autocompleteClass ]
                                [ Html.div
                                    [ WeakCss.addMany [ "container", "input-cont" ] autocompleteClass
                                        |> WeakCss.withActiveStates [ "disabled" ]
                                    ]
                                    [ Html.span
                                        [ WeakCss.nest "search-icon" autocompleteClass ]
                                        [ XB2.Share.Icons.icon [] P2Icons.search ]
                                    , Html.input
                                        [ WeakCss.nestMany [ "container", "input" ] autocompleteClass
                                        , Attrs.attribute "autocomplete" "off"
                                        , Attrs.disabled True
                                        , Attrs.placeholder "Email address"
                                        ]
                                        []
                                    ]
                                ]

                          else
                            Autocomplete.view
                                { toLabel = .email
                                , toOption =
                                    \person index ->
                                        Html.div [ WeakCss.nestMany [ "share-modal", "autocomplete", "option", "content" ] moduleClass ]
                                            [ Html.div [ WeakCss.nestMany [ "share-modal", "autocomplete", "option", "avatar" ] moduleClass ]
                                                [ Svg.svg [ SvgAttrs.width "24px", SvgAttrs.height "24px" ]
                                                    [ Svg.g [ SvgAttrs.fill <| XB2.Share.Palette.p2AvatarColorFromIndex index ]
                                                        [ Svg.circle [ SvgAttrs.cx "12", SvgAttrs.cy "12", SvgAttrs.r "12" ] []
                                                        , Svg.text_
                                                            [ SvgAttrs.x "50%", SvgAttrs.y "70%", SvgAttrs.textAnchor "middle", SvgAttrs.stroke "#fff" ]
                                                            [ Html.text <| String.toUpper <| String.slice 0 1 person.firstName ]
                                                        ]
                                                    ]
                                                ]
                                            , Html.div []
                                                [ Html.p [ WeakCss.nestMany [ "share-modal", "autocomplete", "option", "headline" ] moduleClass ]
                                                    [ Html.text <| person.firstName ++ " " ++ person.lastName ]
                                                , Html.p [ WeakCss.nestMany [ "share-modal", "autocomplete", "option", "subheading" ] moduleClass ]
                                                    [ Html.text person.email ]
                                                ]
                                            ]
                                , moduleClass = WeakCss.addMany [ "share-modal", "autocomplete" ] moduleClass
                                , uniqueElementId = "share-modal-autocomplete"
                                , placeholder = "Email address"
                                , icon = P2Icons.search
                                , msg = AutocompleteInputMsg >> config.msg
                                , attributes = []
                                , disabled = False
                                }
                                data.autocompleteModel
                        ]
                    ]
                ]
            , Html.viewIf (not containsOnlyValidEmails) <|
                Html.div [ WeakCss.nestMany [ "share-modal", "error" ] moduleClass ]
                    [ Html.p [ WeakCss.nestMany [ "share-modal", "error", "text" ] moduleClass ]
                        [ Html.text "One or more email addresses are incorrect, or not associated with GWI Professional accounts." ]
                    , Html.p [ WeakCss.nestMany [ "share-modal", "error", "text" ] moduleClass ]
                        [ Html.text "Please input valid email addresses in order to share your crosstab." ]
                    ]
            , shareWithOrgView shareWithOrgChecked
            , Html.viewIf (alreadySharedWithSome && not readOnly) existingSharingEmailsView
            , notesView
            ]
        , Html.footer
            [ WeakCss.nestMany [ "share-modal", "footer" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "share-modal", "footer", "buttons" ] moduleClass ]
                [ Html.button
                    [ WeakCss.nestMany [ "share-modal", "action-link" ] moduleClass
                    , Attrs.type_ "button"
                    , Events.onClick config.closeModal
                    ]
                    [ Html.text "Cancel" ]
                , Html.button shareBtnAttributes
                    [ Html.text "Share" ]
                ]
            , Html.div [ WeakCss.nestMany [ "share-modal", "footer", "link-share" ] moduleClass ]
                [ Html.button
                    [ WeakCss.addMany [ "share-modal", "footer", "link-share", "button" ] moduleClass
                        |> WeakCss.withStates [ ( "primary", readOnly ) ]
                    , Events.onClick <| config.shareAndCopyLink project
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.link
                    , Html.text "Copy link"
                    ]
                , Html.div [ WeakCss.nestMany [ "share-modal", "footer", "link-share", "info" ] moduleClass ]
                    [ XB2.Share.Icons.icon [] P2Icons.info
                    , Html.text "Anyone with the link can view and duplicate your crosstab, depending on their data plan"
                    ]
                ]
            ]
        ]
    ]


addAsNewBasesContent : Flags -> Config msg -> AddAsNewBasesData -> List (Html msg)
addAsNewBasesContent flags { closeModal, msg, saveAsBase } data =
    let
        selectedGrouping =
            List.filter ((==) True << .active) data.logicButtons
                |> List.head
                |> Maybe.map .grouping
                |> Maybe.withDefault Grouping.Split

        groupingLabelElement =
            case selectedGrouping of
                Grouping.Split ->
                    Html.nothing

                Grouping.And ->
                    Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "grouping-label" ] moduleClass ]
                        [ Html.text "And"
                        ]

                Grouping.Or ->
                    Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "grouping-label" ] moduleClass ]
                        [ Html.text "Or"
                        ]
    in
    [ Html.form
        [ WeakCss.nest "add-new-bases" moduleClass
        , Events.onSubmit <| saveAsBase selectedGrouping <| List.map Tuple.second data.selectedItems
        ]
        [ headerWithTabsView closeModal [ { title = "Add as a new base", active = True, icon = P2Icons.attribute, onClick = Nothing } ]
        , Html.main_
            [ WeakCss.nestMany [ "add-new-bases", "content" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "add-new-bases", "logic" ] moduleClass ]
                [ Html.div [ WeakCss.nestMany [ "add-new-bases", "logic", "label" ] moduleClass ] [ Html.text "Split or merge your new base(s)" ]
                , Html.div [ WeakCss.nestMany [ "add-new-bases", "logic", "buttons" ] moduleClass ] <|
                    List.indexedMap
                        (\index btn ->
                            Html.button
                                [ WeakCss.addMany [ "add-new-bases", "logic", "buttons", "button" ] moduleClass
                                    |> WeakCss.withStates [ ( "active", btn.active ) ]
                                , Attrs.type_ "button"
                                , Events.onClick <| msg <| AddAsBasesSetActiveLogic index
                                ]
                                [ Html.text <| Grouping.toString btn.grouping
                                ]
                        )
                        data.logicButtons
                ]
            , Html.ul [ WeakCss.nestMany [ "add-new-bases", "items" ] moduleClass ] <|
                List.indexedMap
                    (\index ( { expanded, alreadySeen }, { item } ) ->
                        case AudienceItem.getDefinition item of
                            Data.Expression expression ->
                                let
                                    name =
                                        Caption.getName <| AudienceItem.getCaption item
                                in
                                Html.li [ WeakCss.nestMany [ "add-new-bases", "items", "row" ] moduleClass ]
                                    [ Html.viewIf (index > 0) groupingLabelElement
                                    , Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "item" ] moduleClass ]
                                        [ Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "item", "header" ] moduleClass ]
                                            [ Html.span [ WeakCss.nestMany [ "add-new-bases", "items", "item", "icon" ] moduleClass ] [ XB2.Share.Icons.icon [] P2Icons.attribute ]
                                            , Html.span
                                                [ WeakCss.nestMany [ "add-new-bases", "items", "item", "title" ] moduleClass
                                                , Attrs.title name
                                                ]
                                                [ Html.text name ]
                                            , Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "item", "buttons" ] moduleClass ]
                                                [ Html.viewIf (not expanded) <|
                                                    Html.button
                                                        [ WeakCss.nestMany [ "add-new-bases", "items", "item", "view-info", "show" ] moduleClass
                                                        , Attrs.type_ "button"
                                                        , Events.onClick <| msg <| AddAsBasesToggleInfo index
                                                        ]
                                                        [ XB2.Share.Icons.icon [] P2Icons.eye
                                                        , Html.span [ WeakCss.nestMany [ "add-new-bases", "items", "item", "view-info", "show", "label" ] moduleClass ]
                                                            [ Html.text "View details"
                                                            ]
                                                        ]
                                                , Html.viewIf expanded <|
                                                    Html.button
                                                        [ WeakCss.nestMany [ "add-new-bases", "items", "item", "view-info", "hide" ] moduleClass
                                                        , Attrs.type_ "button"
                                                        , Events.onClick <| msg <| AddAsBasesToggleInfo index
                                                        ]
                                                        [ XB2.Share.Icons.icon [] P2Icons.eyeCrossed
                                                        , Html.text "Hide details"
                                                        ]
                                                ]
                                            ]
                                        , Html.div
                                            [ WeakCss.addMany [ "expression-viewer", "wrapper" ] moduleClass
                                                |> WeakCss.withStates [ ( "is-expanded", expanded ) ]
                                            ]
                                            [ Html.viewIfLazy (expanded || alreadySeen) (\() -> ExpressionViewer.view flags moduleClass expression) ]
                                        ]
                                    ]

                            Data.Average _ ->
                                Html.nothing
                    )
                    data.selectedItems
            ]
        , Html.footer [ WeakCss.nestMany [ "add-new-bases", "footer" ] moduleClass ]
            [ Html.button
                [ Events.onClickPreventDefault closeModal
                , WeakCss.nestMany [ "add-new-bases", "action-link" ] moduleClass
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nestMany [ "add-new-bases", "primary-button" ] moduleClass
                , Attrs.type_ "submit"
                ]
                [ Html.text "Add as new base" ]
            ]
        ]
    ]


mergeRoworColumContent : Flags -> Config msg -> MergeRowOrColumnData -> List (Html msg)
mergeRoworColumContent flags { closeModal, msg, mergeRowOrColumn } data =
    let
        selectedGrouping =
            List.filter ((==) True << .active) data.logicButtons
                |> List.head
                |> Maybe.map .grouping
                |> Maybe.withDefault Grouping.And

        groupingLabelElement =
            case selectedGrouping of
                Grouping.Split ->
                    Html.nothing

                Grouping.And ->
                    Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "grouping-label" ] moduleClass ]
                        [ Html.text "And"
                        ]

                Grouping.Or ->
                    Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "grouping-label" ] moduleClass ]
                        [ Html.text "Or"
                        ]
    in
    [ Html.form
        [ WeakCss.nest "merge-row-or-columns " moduleClass
        ]
        [ headerWithTabsView closeModal [ { title = "Merge Columns/Rows", active = True, icon = P2Icons.mergeHeader, onClick = Nothing } ]
        , Html.main_
            [ WeakCss.nestMany [ "merge-row-or-columns ", "content" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "logic" ] moduleClass ]
                [ Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "logic", "label" ] moduleClass ] [ Html.text "Select how you wish to merge your columns/rows" ]
                , Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "logic", "buttons" ] moduleClass ] <|
                    List.indexedMap
                        (\index btn ->
                            Html.button
                                [ WeakCss.addMany [ "merge-row-or-columns ", "logic", "buttons", "button" ] moduleClass
                                    |> WeakCss.withStates [ ( "active", btn.active ) ]
                                , Attrs.type_ "button"
                                , Events.onClick <| msg <| MergeRowOrColumSetActiveLogic index
                                ]
                                [ Html.text <| Grouping.toString btn.grouping
                                ]
                        )
                        data.logicButtons
                ]
            , Html.ul [ WeakCss.nestMany [ "merge-row-or-columns ", "items" ] moduleClass ] <|
                List.indexedMap
                    (\index ( { expanded, alreadySeen }, { item } ) ->
                        case AudienceItem.getDefinition item of
                            Data.Expression expression ->
                                let
                                    name =
                                        Caption.getName <| AudienceItem.getCaption item
                                in
                                Html.li [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "row" ] moduleClass ]
                                    [ Html.viewIf (index > 0) groupingLabelElement
                                    , Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item" ] moduleClass ]
                                        [ Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "header" ] moduleClass ]
                                            [ Html.span [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "icon" ] moduleClass ] [ XB2.Share.Icons.icon [] P2Icons.attribute ]
                                            , Html.span
                                                [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "title" ] moduleClass
                                                , Attrs.title name
                                                ]
                                                [ Html.text name ]
                                            , Html.div [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "buttons" ] moduleClass ]
                                                [ Html.viewIf (not expanded) <|
                                                    Html.button
                                                        [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "view-info", "show" ] moduleClass
                                                        , Attrs.type_ "button"
                                                        , Events.onClick <| msg <| MergeRowOrColumToggleInfo index
                                                        ]
                                                        [ XB2.Share.Icons.icon [] P2Icons.eye
                                                        , Html.span [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "view-info", "show", "label" ] moduleClass ]
                                                            [ Html.text "View details"
                                                            ]
                                                        ]
                                                , Html.viewIf expanded <|
                                                    Html.button
                                                        [ WeakCss.nestMany [ "merge-row-or-columns ", "items", "item", "view-info", "hide" ] moduleClass
                                                        , Attrs.type_ "button"
                                                        , Events.onClick <| msg <| MergeRowOrColumToggleInfo index
                                                        ]
                                                        [ XB2.Share.Icons.icon [] P2Icons.eyeCrossed
                                                        , Html.text "Hide details"
                                                        ]
                                                ]
                                            ]
                                        , Html.div
                                            [ WeakCss.addMany [ "expression-viewer", "wrapper" ] moduleClass
                                                |> WeakCss.withStates [ ( "is-expanded", expanded ) ]
                                            ]
                                            [ Html.viewIfLazy (expanded || alreadySeen) (\() -> ExpressionViewer.view flags moduleClass expression) ]
                                        ]
                                    ]

                            Data.Average _ ->
                                Html.nothing
                    )
                    data.selectedItems
            ]
        , Html.footer
            [ WeakCss.nestMany [ "merge-row-or-columns ", "footer" ] moduleClass ]
            [ Html.button
                [ Events.onClickPreventDefaultAndStopPropagation <|
                    mergeRowOrColumn
                        selectedGrouping
                        (List.map Tuple.second data.selectedItems)
                        data.allDirections
                        True
                        data.allSelected
                , WeakCss.nestMany [ "merge-row-or-columns ", "secondary-button" ]
                    moduleClass
                ]
                [ Html.text "Create new column or row" ]
            , Html.button
                [ WeakCss.nestMany [ "merge-row-or-columns ", "primary-button" ]
                    moduleClass
                , Events.onClickPreventDefaultAndStopPropagation <|
                    mergeRowOrColumn selectedGrouping
                        (List.map Tuple.second data.selectedItems)
                        data.allDirections
                        False
                        data.allSelected
                ]
                [ Html.text "Merge columns or rows" ]
            ]
        ]
    ]


removeBulkConfirmContents :
    Flags
    -> Config msg
    ->
        { innerModuleClass : ClassName
        , title : String
        , onSubmit : msg
        , updateMsg : BulkDeleteModalAction -> Msg
        , items : List ( ExpandedState, { name : String, expression : Expression } )
        , dialogCopy : Html msg
        , doNotShowAgainChecked : Bool
        }
    -> List (Html msg)
removeBulkConfirmContents flags { msg, closeModal } { dialogCopy, updateMsg, onSubmit, title, items, innerModuleClass, doNotShowAgainChecked } =
    let
        itemWithExpressionView index ( { expanded, alreadySeen }, item ) =
            Html.li
                [ WeakCss.addMany [ "items", "item" ] innerModuleClass
                    |> WeakCss.withStates [ ( "expanded", expanded ) ]
                ]
                [ Html.div [ WeakCss.nestMany [ "add-new-bases", "items", "item", "header" ] moduleClass ]
                    [ Html.span [ WeakCss.nestMany [ "items", "item", "icon" ] innerModuleClass ] [ XB2.Share.Icons.icon [] P2Icons.attribute ]
                    , Html.span
                        [ WeakCss.nestMany [ "items", "item", "title" ] innerModuleClass
                        , Attrs.title item.name
                        ]
                        [ Html.text item.name ]
                    , Html.div [ WeakCss.nestMany [ "items", "item", "buttons" ] innerModuleClass ]
                        [ Html.viewIf (not expanded) <|
                            Html.button
                                [ WeakCss.nestMany [ "items", "item", "view-info", "show" ] innerModuleClass
                                , Attrs.type_ "button"
                                , Events.onClick <| msg <| updateMsg <| ToggleInfo index
                                ]
                                [ XB2.Share.Icons.icon [] P2Icons.eye
                                , Html.span [ WeakCss.nestMany [ "items", "item", "view-info", "show-label" ] innerModuleClass ]
                                    [ Html.text "View details"
                                    ]
                                ]
                        , Html.viewIf expanded <|
                            Html.button
                                [ WeakCss.nestMany [ "items", "item", "view-info", "hide" ] innerModuleClass
                                , Attrs.type_ "button"
                                , Events.onClick <| msg <| updateMsg <| ToggleInfo index
                                ]
                                [ XB2.Share.Icons.icon [] P2Icons.eyeCrossed
                                , Html.text "Hide details"
                                ]
                        , Html.button
                            [ WeakCss.nestMany [ "items", "item", "remove" ] innerModuleClass
                            , Attrs.type_ "button"
                            , Events.onClick <| msg <| updateMsg <| RemoveItem index
                            ]
                            [ XB2.Share.Icons.icon [] P2Icons.restore
                            ]
                        ]
                    ]
                , Html.div
                    [ WeakCss.addMany [ "expression-viewer", "wrapper" ] innerModuleClass
                        |> WeakCss.withStates [ ( "is-expanded", expanded ) ]
                    ]
                    [ Html.viewIfLazy (expanded || alreadySeen) (\() -> ExpressionViewer.view flags innerModuleClass item.expression) ]
                ]
    in
    [ Html.form
        [ WeakCss.toClass innerModuleClass
        , Events.onSubmit onSubmit
        ]
        [ headerWithTabsView closeModal [ { title = title, active = True, icon = P2Icons.trash, onClick = Nothing } ]
        , Html.main_
            [ WeakCss.nest "content" innerModuleClass ]
            [ Html.div [ WeakCss.nest "dialog-copy" innerModuleClass ]
                [ dialogCopy ]
            , Html.ul [ WeakCss.nest "items" innerModuleClass ] <|
                List.indexedMap itemWithExpressionView items
            ]
        , Html.footer [ WeakCss.nest "footer" innerModuleClass ]
            [ Html.label
                [ WeakCss.add "checkbox" innerModuleClass
                    |> WeakCss.withStates
                        [ ( "checked", doNotShowAgainChecked )
                        ]
                ]
                [ Html.input
                    [ Attrs.type_ "checkbox"
                    , Attrs.checked doNotShowAgainChecked
                    , WeakCss.nestMany [ "checkbox", "input" ] innerModuleClass
                    , Events.onClickStopPropagation <| msg <| updateMsg ToggleDoNotShowAgain
                    ]
                    []
                , Html.div [ WeakCss.nestMany [ "checkbox", "indicator" ] innerModuleClass ]
                    [ Html.i
                        [ WeakCss.nestMany [ "checkbox", "icon" ] innerModuleClass ]
                        [ XB2.Share.Icons.icon [] <|
                            if doNotShowAgainChecked then
                                P2Icons.checkboxFilled

                            else
                                P2Icons.checkboxUnfilled
                        ]
                    ]
                , Html.text "Don't show again"
                ]
            , Html.button
                [ Events.onClickPreventDefault closeModal
                , WeakCss.nest "action-link" innerModuleClass
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nest "primary-button" innerModuleClass
                , Attrs.type_ "submit"
                ]
                [ Html.text "Delete" ]
            ]
        ]
    ]


removeRowsColsContent : Flags -> Config msg -> ConfirmRemoveRowsColumnsData -> List (Html msg)
removeRowsColsContent flags config data =
    let
        ( containsRows, containsColumns ) =
            List.partition ((==) Row << Tuple.first << Tuple.second) data.items
                |> Tuple.mapBoth (List.isEmpty >> not)
                    (List.isEmpty >> not)

        itemsCount =
            List.length data.items

        addIf cond =
            if cond then
                (::)

            else
                always identity

        removingTypes =
            []
                |> addIf containsRows (XB2.Share.Plural.fromInt itemsCount "row")
                |> addIf containsColumns (XB2.Share.Plural.fromInt itemsCount "column")

        items =
            List.filterMap
                (\( selected, ( _, { item } ) ) ->
                    case AudienceItem.getDefinition item of
                        Data.Expression expression ->
                            Just
                                ( selected
                                , { name = Caption.getName <| AudienceItem.getCaption item
                                  , expression = expression
                                  }
                                )

                        Data.Average _ ->
                            Nothing
                )
                data.items
    in
    removeBulkConfirmContents flags
        config
        { innerModuleClass = WeakCss.add "remove-rows-columns" moduleClass
        , title = "Remove " ++ String.join "/" removingTypes
        , onSubmit = config.confirmDeleteRowsColumns data.doNotShowAgainChecked <| List.map Tuple.second data.items
        , updateMsg = UpdateRemoveRowsColumnsModal
        , items = items
        , dialogCopy =
            Html.span []
                [ Html.text "Are you sure you want to delete the following "
                , Html.text <| String.fromInt itemsCount
                , Html.text <| " " ++ String.join " and " removingTypes
                , Html.text "?"
                ]
        , doNotShowAgainChecked = data.doNotShowAgainChecked
        }


confirmRemoveBasesContent : Flags -> Config msg -> ConfirmRemoveBasesData -> List (Html msg)
confirmRemoveBasesContent flags config data =
    let
        itemsCount =
            List.length data.items

        items =
            List.map
                (Tuple.mapSecond
                    (\base ->
                        { name = Caption.getName <| BaseAudience.getCaption base
                        , expression = BaseAudience.getExpression base
                        }
                    )
                )
                data.items

        onSubmit =
            data.items
                |> List.map Tuple.second
                |> NonemptyList.fromList
                |> Maybe.map (config.confirmDeleteBases data.doNotShowAgainChecked)
                |> Maybe.withDefault config.closeModal
    in
    removeBulkConfirmContents flags
        config
        { innerModuleClass = WeakCss.add "remove-bases-confirm" moduleClass
        , title = XB2.Share.Plural.fromInt itemsCount "Delete base"
        , onSubmit = onSubmit
        , updateMsg = UpdateConfirmRemoveBasesModal
        , items = items
        , dialogCopy =
            Html.span []
                [ Html.text "Are you sure you want to delete the following "
                , Html.text <| String.fromInt itemsCount
                , Html.text <| XB2.Share.Plural.fromInt itemsCount " base"
                , Html.text "?"
                ]
        , doNotShowAgainChecked = data.doNotShowAgainChecked
        }


confirmMoveProjectOutOfFolderContents : Config msg -> State -> List XBProject -> List (Html msg)
confirmMoveProjectOutOfFolderContents config state projects =
    [ Html.div [ WeakCss.nest "general-alert" moduleClass ]
        [ Html.header
            [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                [ Html.text "You’re about to remove "
                , Html.text <| String.fromInt <| List.length projects
                , Html.text <| XB2.Share.Plural.fromInt (List.length projects) " crosstab"
                , Html.text " from your folder"
                ]
            ]
        , Html.div
            [ WeakCss.nestMany [ "general-alert", "content" ] moduleClass ]
            [ Html.p
                [ WeakCss.nestMany [ "general-alert", "content", "text" ] moduleClass ]
                [ Html.text "Are you sure you want to remove these from your folder?"
                ]
            ]
        , Html.footer
            [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                , Events.onClick config.closeModal
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nestMany [ "general-alert", "primary-button" ] moduleClass
                , Events.onClick <| config.moveProjectsToFolder Nothing projects
                , Attrs.disabled (state == Processing)
                ]
                [ Html.text "Yes, I’m sure" ]
            ]
        ]
    , Html.viewIf (state == Processing) <|
        Html.div [ WeakCss.nestMany [ "general-alert", "processing-overlay" ] moduleClass ]
            [ Spinner.view ]
    ]


{-| TODO: Pass primitives properly through a record.
-}
contents :
    Flags
    -> Config msg
    -> XBStore.Store
    -> XB2.Share.Store.Platform2.Store
    -> String
    -> Bool
    -> Modal
    -> List (Html msg)
contents flags config xbStore p2Store attributeBrowserInitialState shouldPassInitialStateToAttributeBrowser modal =
    case modal of
        RenameProject m ->
            renameProjectContents xbStore.xbProjects config m

        SetNameForNewProject m ->
            setNameForNewProjectContents xbStore.xbProjects config m

        SetNameForProjectCopy ({ newName, project, original } as data) ->
            modalWithNameFieldContents
                { inputMsg = config.msg << SetProjectOrFolderName
                , saveMsg = config.saveProjectAsCopy { copy = { project | name = newName }, original = original }
                , nameExists = projectNameExists xbStore.xbProjects newName
                , nameIsTheSame = projectNameIsTheSame project newName
                , maxLength = NewName.maxLength
                , title = "Name your crosstab"
                , placeholder = "Crosstab name"
                , entity = "crosstab"
                }
                (saveFooter config "Save Crosstab and leave")
                data

        DuplicateProject m ->
            duplicateProjectContents xbStore.xbProjects config m

        ConfirmDeleteProject m ->
            let
                modalContents =
                    case m.project.shared of
                        MySharedCrosstab _ ->
                            confirmDeleteSharedProjectContents

                        _ ->
                            confirmDeleteProjectContents
            in
            modalContents config m

        ConfirmDeleteProjects m ->
            confirmDeleteProjectsContents config m

        ConfirmUnshareMe { state, project } ->
            basicModalContents config
                { state = state
                , title = "Remove shared crosstab"
                , body =
                    Html.p []
                        [ Html.text "This will remove the crosstab from your list. To gain access to this crosstab again, please ask the crosstab’s owner to share it again."
                        ]
                , confirmButton =
                    { title = "Remove"
                    , onClick = config.unshareMe project
                    }
                }

        SaveProjectAsNew m ->
            saveProjectAsNewContents xbStore.xbProjects config m

        CreateFolder m ->
            createFolderContents xbStore.xbFolders config m

        MoveToFolder m ->
            moveToFolderContents xbStore.xbFolders config m

        RenameFolder m ->
            renameFolderContents xbStore.xbFolders config m

        ConfirmDeleteFolder { state, folder, projectsInFolder } ->
            basicModalContents config
                { state = state
                , title = "You're about to delete"
                , body =
                    Html.div []
                        [ Html.p []
                            [ Html.text "Are you sure you want to delete this folder?"
                            ]
                        , Html.p []
                            [ Html.text <|
                                "Please note: deleting this folder will also delete "
                                    ++ String.fromInt projectsInFolder
                                    ++ XB2.Share.Plural.fromInt projectsInFolder " project"
                                    ++ " inside the folder."
                            ]
                        ]
                , confirmButton =
                    { title = "Yes, I'm sure"
                    , onClick = config.confirmDeleteFolder folder
                    }
                }

        ConfirmUngroupFolder { state, folder } ->
            basicModalContents config
                { state = state
                , title = "You’re about to ungroup"
                , body = Html.p [] [ Html.text "Are you sure you want to ungroup this folder?" ]
                , confirmButton =
                    { title = "Yes, I'm sure"
                    , onClick = config.confirmUngroupFolder folder
                    }
                }

        ViewGroup m ->
            groupContentsView flags config m

        RenameAverage m ->
            renameAverageContents config m

        RenameBaseAudience m ->
            baseRenameContentsView flags config m

        AffixGroup m ->
            affixGroupContents flags config m

        EditGroup m ->
            editGroupContents flags config m

        AffixBase m ->
            affixBaseContents flags config m

        EditBase m ->
            editBaseContents flags config m

        UnsavedChangesAlert data ->
            unsavedChangesAlertContents config data

        SaveAsAudience data ->
            saveAsAudienceContents flags config data

        ConfirmFullLoadForHeatmap notLoadedCount metric ->
            confirmFullLoadContents
                (config.fullLoadAndApplyHeatmap metric)
                config.closeModal
                notLoadedCount
                "Apply heatmap"
                "apply a heatmap"
                "Cancel"

        ConfirmFullLoadForExport maybeSelectionMap notLoadedCount maybeProject ->
            confirmFullLoadContents
                (config.fullLoadAndExport maybeSelectionMap maybeProject)
                config.closeModal
                notLoadedCount
                "Export"
                "export your crosstab"
                "Cancel"

        ConfirmFullLoadForExportFromList notLoadedCount project ->
            confirmFullLoadContents
                (config.fullLoadAndExportFromList project)
                config.closeModal
                notLoadedCount
                "Export"
                "export your crosstab"
                "Cancel"

        ConfirmCellsLoadForSorting notLoadedCount sortConfig ->
            confirmFullLoadContents
                (config.partialLoadAndSort sortConfig)
                config.removeSortingAndCloseModal
                notLoadedCount
                "Sort Crosstab"
                "keep sorting applied to your crosstab"
                "Remove sorting"

        ConfirmCancelExport ->
            confirmCancelContents
                config
                config.confirmCancelFullLoad
                "Export"
                "Are you sure you want to cancel your export?"

        FetchQuestionsForEditModal ->
            [ fetchQuestionsForEditModalContents config ]

        ConfirmCancelExportFromList ->
            confirmCancelContents
                config
                config.confirmCancelFullLoadFromList
                "Export"
                "Are you sure you want to cancel your export?"

        ConfirmCancelApplyingHeatmap ->
            confirmCancelContents
                config
                config.confirmCancelFullLoad
                "Apply heatmap"
                "Are you sure you want to cancel applying your heatmap?"

        ConfirmActionWithViewSettings m ->
            confirmActionWithViewSettingsContents config m

        ShareProject data ->
            shareProjectContents config flags data

        ConfirmCancelCellsSorting ->
            confirmCancelContents
                config
                config.cancelSortingLoading
                "Sort"
                "Are you sure you want to cancel sorting your crosstab?"

        ConfirmCancelFullScreenTableLoad ->
            confirmCancelContents
                config
                config.cancelSortingLoading
                "Cancel loading"
                "Are you sure you want to cancel loading your remaining cells? This will remove all your current view settings (sorting, heatmap)."

        -- these contents are handled by custom components
        ChooseMetrics _ ->
            []

        ChooseHeatmapMetric _ ->
            []

        AttributesModal data ->
            attributesModalContents flags
                config
                p2Store
                attributeBrowserInitialState
                shouldPassInitialStateToAttributeBrowser
                data

        AddAsNewBases data ->
            addAsNewBasesContent flags config data

        MergeRowOrColum data ->
            mergeRoworColumContent flags config data

        ConfirmRemoveRowsColumns data ->
            removeRowsColsContent flags config data

        ConfirmRemoveBases data ->
            confirmRemoveBasesContent flags config data

        GenericAlert data ->
            let
                alertBody : Html Never
                alertBody =
                    Html.main_ [ WeakCss.nestMany [ "general-alert", "main" ] moduleClass ]
                        [ data.htmlContent
                        ]
            in
            [ Html.header [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
                [ Html.h2 [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                    [ Html.text data.title ]
                ]
            , Html.map (always <| config.msg NoOp) alertBody
            , Html.footer [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
                [ Html.button
                    [ Events.onClick config.closeModal
                    , Attrs.type_ "button"
                    , WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                    ]
                    [ Html.text data.btnTitle ]
                ]
            ]

        ErrorModal errorDisplay ->
            let
                alertBody : Html Never
                alertBody =
                    Html.main_ [ WeakCss.nestMany [ "general-alert", "main" ] moduleClass ]
                        [ errorDisplay.body
                        , Markdown.toHtml [] <| String.join "\n\n" errorDisplay.details
                        ]
            in
            [ Html.header [ WeakCss.nestMany [ "general-alert", "header" ] moduleClass ]
                [ Html.h2 [ WeakCss.nestMany [ "general-alert", "headline" ] moduleClass ]
                    [ Html.text errorDisplay.title ]
                ]
            , Html.map (always <| config.msg NoOp) alertBody
            , Html.footer [ WeakCss.nestMany [ "general-alert", "footer" ] moduleClass ]
                [ Html.button
                    [ Events.onClick <| config.openSupportChat errorDisplay.errorId
                    , Attrs.type_ "button"
                    , WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                    ]
                    [ Html.text "Contact support" ]
                , Html.button
                    [ Events.onClick config.closeModal
                    , Attrs.type_ "button"
                    , WeakCss.nestMany [ "general-alert", "action-link" ] moduleClass
                    ]
                    [ Html.text "Close" ]
                ]
            ]

        ReorderBases data ->
            reorderBasesModalContents config data

        MoveOutOfFolderModal data ->
            confirmMoveProjectOutOfFolderContents config data.state data.projects


{-| A view showing the pink bar used to represent the place where a base is going to be
moved in the `ReorderBases` modal. It should look like this:

    --- Dividing  line ---
    [     Upper  base    ]
    [ Base being dragged ]
    [     Lower base     ]
    --- Dividing  line ---

-}
reorderBasesModalDividingBar : Html msg
reorderBasesModalDividingBar =
    Html.div
        [ WeakCss.nestMany [ "reorder-modal", "list", "dividing-bar" ] moduleClass
        ]
        []


{-| A view showing a grey empty container for the `ReorderBases` modal. It replaces the
element being dragged.
-}
reorderBasesModalPlaceholder : Html msg
reorderBasesModalPlaceholder =
    Html.li
        [ WeakCss.nestMany [ "reorder-modal", "list", "item", "placeholder" ]
            moduleClass
        ]
        []


{-| A view showing the audience being dragged inside the `ReorderBases` modal. It follows
the cursor.
-}
reorderBasesModalGhostView :
    Config msg
    -> Dnd.Model
    -> List ACrosstab.CrosstabBaseAudience
    -> Html msg
reorderBasesModalGhostView config dnd items =
    let
        maybeDragItem : Maybe ACrosstab.CrosstabBaseAudience
        maybeDragItem =
            reorderBasesModalDndSystem.info dnd
                |> Maybe.andThen
                    (\{ dragIndex } ->
                        items
                            |> List.drop dragIndex
                            |> List.head
                    )
    in
    case maybeDragItem of
        Just item ->
            let
                baseAudienceName =
                    case item of
                        ACrosstab.DefaultBase base ->
                            BaseAudience.toBaseAudienceData base
                                |> .name

                        ACrosstab.SelectableBase { base } ->
                            BaseAudience.toBaseAudienceData base
                                |> .name
            in
            Html.li
                ((WeakCss.addMany [ "reorder-modal", "list", "item" ] moduleClass
                    |> WeakCss.withActiveStates [ "dragged" ]
                 )
                    :: reorderBasesModalDndSystem.ghostStyles dnd
                )
                [ Html.div
                    [ WeakCss.nestMany [ "reorder-modal", "list", "item", "icon" ]
                        moduleClass
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.move ]
                , Html.text baseAudienceName
                ]
                |> Html.map config.msg

        Nothing ->
            Html.nothing


reorderBasesModalContents :
    Config msg
    -> ReorderBasesModalData
    -> List (Html msg)
reorderBasesModalContents config state =
    [ Html.div
        [ WeakCss.nest "reorder-modal" moduleClass ]
        [ Html.header
            [ WeakCss.nestMany [ "reorder-modal", "header" ] moduleClass ]
            [ Html.h2
                [ WeakCss.nestMany [ "reorder-modal", "header", "title" ] moduleClass ]
                [ Html.text "Reorder bases" ]
            , Html.button
                [ WeakCss.nestMany [ "reorder-modal", "header", "reset-button" ]
                    moduleClass
                , Events.onClick <| config.msg ResetReorderBasesModal
                , Attrs.id "modal-reorder-bases-reset-button"
                ]
                [ Html.text "Reset" ]
            ]
        , Html.ul
            [ WeakCss.nestMany [ "reorder-modal", "list" ] moduleClass
            , Attrs.tabindex 0
            , Attrs.attribute "aria-label" <|
                Maybe.withDefault
                    ((String.fromInt <| List.length state.newBasesOrder)
                        ++ ", To reorder base, Use enter or space bar to  select and up "
                        ++ "and down arrows to move"
                    )
                    state.ariaMessageForBasesList
            , Attrs.attribute "aria-live" "polite"
            ]
            ((List.indexedMap
                (\index item ->
                    reorderBasesListItemView
                        { isSelectedForKeyboardReordering =
                            state.baseIndexSelectedToMoveWithKeyboard == Just index
                        , isHoveredToShowDividingLine =
                            state.hoveredBaseIndexForDividingLine == Just index
                        }
                        state.dragAndDropSystem
                        index
                        config
                        item
                )
                state.newBasesOrder
                |> List.concat
             )
                ++ [ reorderBasesModalGhostView config
                        state.dragAndDropSystem
                        state.newBasesOrder
                   ]
            )
        , Html.footer
            [ WeakCss.nestMany [ "reorder-modal", "footer" ] moduleClass ]
            [ Html.button
                [ WeakCss.nestMany [ "reorder-modal", "footer", "cancel-button" ]
                    moduleClass
                , Events.onClick config.closeModal
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nestMany [ "reorder-modal", "footer", "apply-button" ]
                    moduleClass
                , Attrs.disabled (state.initialBasesOrder == state.newBasesOrder)
                , Events.onClick <|
                    config.reorderModalApplyChanges
                        { triggeredFrom = Analytics.Menu
                        , shouldFireAnalytics = True
                        }
                        state.newBasesOrder
                        0
                ]
                [ Html.text "Apply" ]
            ]
        ]
    ]


{-| A view representing a draggable base for the `ReorderBases` modal.
-}
reorderBasesListItemView :
    { isSelectedForKeyboardReordering : Bool
    , isHoveredToShowDividingLine : Bool
    }
    -> Dnd.Model
    -> Int
    -> Config msg
    -> ACrosstab.CrosstabBaseAudience
    -> List (Html msg)
reorderBasesListItemView props dnd index config baseAudience =
    let
        ( baseAudienceName, baseAudienceId ) =
            case baseAudience of
                ACrosstab.DefaultBase base ->
                    BaseAudience.toBaseAudienceData base
                        |> (\baseData -> ( baseData.name, baseData.id ))

                ACrosstab.SelectableBase { base } ->
                    BaseAudience.toBaseAudienceData base
                        |> (\baseData -> ( baseData.name, baseData.id ))
    in
    case reorderBasesModalDndSystem.info dnd of
        Just dndInfo ->
            if dndInfo.dragIndex /= index then
                let
                    dropAttributes =
                        reorderBasesModalDndSystem.dropEvents index baseAudienceId
                            |> List.map (Attrs.map config.msg)
                in
                [ Html.viewIf
                    (index == dndInfo.dragIndex - 1 && props.isHoveredToShowDividingLine)
                    reorderBasesModalDividingBar
                , Html.li
                    [ WeakCss.addMany [ "reorder-modal", "list", "item" ] moduleClass
                        |> WeakCss.withActiveStates [ "swappable" ]
                    , Attrs.id baseAudienceId
                    , Events.onMouseOver <|
                        config.msg <|
                            SetBaseAudienceIndexHovered <|
                                Just index
                    , Events.onMouseOut <|
                        config.msg <|
                            SetBaseAudienceIndexHovered Nothing
                    ]
                    [ Html.span
                        (WeakCss.nestMany
                            [ "reorder-modal"
                            , "list"
                            , "item"
                            , "droppable-zone"
                            ]
                            moduleClass
                            :: dropAttributes
                        )
                        []
                    , Html.div
                        [ WeakCss.nestMany [ "reorder-modal", "list", "item", "icon" ]
                            moduleClass
                        ]
                        [ XB2.Share.Icons.icon [] P2Icons.move ]
                    , Html.text baseAudienceName
                    ]
                , Html.viewIf
                    (index == dndInfo.dragIndex + 1 && props.isHoveredToShowDividingLine)
                    reorderBasesModalDividingBar
                ]

            else
                [ reorderBasesModalPlaceholder ]

        Nothing ->
            [ Html.li
                ([ WeakCss.addMany [ "reorder-modal", "list", "item" ] moduleClass
                    |> WeakCss.withStates
                        [ ( "selected", props.isSelectedForKeyboardReordering ) ]
                 , Attrs.id baseAudienceId
                 , Attrs.tabindex 0
                 , Events.onFocus <|
                    config.msg <|
                        SetBaseAudienceIndexFocused <|
                            Just index
                 , Events.onBlur <|
                    config.msg <|
                        SetBaseAudienceIndexFocused
                            Nothing
                 ]
                    ++ (reorderBasesModalDndSystem.dragEvents index baseAudienceId
                            |> List.map (Attrs.map config.msg)
                       )
                )
                [ Html.div
                    [ WeakCss.nestMany [ "reorder-modal", "list", "item", "icon" ]
                        moduleClass
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.move ]
                , Html.text baseAudienceName
                ]
            ]


type alias NameModal r =
    { r
        | newName : String
        , state : State
    }


type alias ModalWithNameFieldsParameters msg =
    { inputMsg : String -> msg
    , saveMsg : msg
    , nameExists : Bool
    , nameIsTheSame : Bool
    , maxLength : Int
    , title : String
    , placeholder : String
    , entity : String
    }


projectNameExists : WebData (IdDict XBProjectIdTag XBProject) -> String -> Bool
projectNameExists xbProjects newName =
    xbProjects
        |> RemoteData.map (Dict.Any.values >> List.any (.name >> (==) newName))
        |> RemoteData.withDefault False


projectNameIsTheSame : XBProject -> String -> Bool
projectNameIsTheSame project newName =
    project.name == newName


folderNameExists : WebData (IdDict XBFolderIdTag XBFolder) -> String -> Bool
folderNameExists xbFolders newName =
    xbFolders
        |> RemoteData.map (Dict.Any.values >> List.any (.name >> (==) newName))
        |> RemoteData.withDefault False


folderNameIsTheSame : XBFolder -> String -> Bool
folderNameIsTheSame folder newName =
    folder.name == newName


modalWithNameFieldContents :
    ModalWithNameFieldsParameters msg
    -> (List (Html.Attribute msg) -> ClassName -> List (Html msg))
    -> NameModal r
    -> List (Html msg)
modalWithNameFieldContents params footerView { newName, state } =
    let
        showDuplicateNameError =
            not params.nameIsTheSame && params.nameExists

        canSave =
            (state == Ready)
                && (not <| String.isEmpty newName)
                && not params.nameExists

        formAttrs =
            [ WeakCss.nest "save-modal" moduleClass
            , Attrs_.attributeIf canSave <| Events.onSubmit params.saveMsg
            ]

        submitBtnAttrs =
            WeakCss.nestMany [ "save-modal", "primary-button" ] moduleClass
                :: (if canSave then
                        [ Attrs.type_ "submit" ]

                    else
                        [ Attrs.disabled True ]
                   )
    in
    [ Html.form formAttrs <|
        [ Html.header [ WeakCss.nestMany [ "save-modal", "header" ] moduleClass ]
            [ Html.h2 [ WeakCss.nestMany [ "save-modal", "headline" ] moduleClass ]
                [ Html.text params.title ]
            ]
        , Html.main_ [ WeakCss.nestMany [ "save-modal", "main" ] moduleClass ]
            [ TextInput.view
                { onInput = params.inputMsg
                , placeholder = params.placeholder
                }
                [ TextInput.class (WeakCss.add "save-modal" moduleClass)
                , TextInput.value newName
                , TextInput.id nameFieldId
                , TextInput.limit params.maxLength
                , TextInput.empty
                ]
            , Html.viewIf showDuplicateNameError <|
                Html.div
                    [ WeakCss.nestMany [ "save-modal", "error" ] moduleClass ]
                    [ Html.text <| "A saved " ++ params.entity ++ " with that name already exists. Please use another name." ]
            ]
        ]
            ++ footerView
                submitBtnAttrs
                (WeakCss.add "save-modal" moduleClass)
    , Html.viewIf (state == Processing) <|
        Html.div [ WeakCss.nestMany [ "save-modal", "processing-overlay" ] moduleClass ]
            [ Spinner.view ]
    ]


renameProjectContents : WebData (IdDict XBProjectIdTag XBProject) -> Config msg -> RenameProjectData -> List (Html msg)
renameProjectContents xbProjects config ({ project, newName } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.renameProject { project | name = newName }
        , nameExists = projectNameExists xbProjects newName
        , nameIsTheSame = projectNameIsTheSame project newName
        , maxLength = NewName.maxLength
        , title = "Rename your Crosstab"
        , placeholder = "Crosstab name"
        , entity = "crosstab"
        }
        (saveFooter config "Rename Crosstab")
        data


setNameForNewProjectContents : WebData (IdDict XBProjectIdTag XBProject) -> Config msg -> RenameProjectData -> List (Html msg)
setNameForNewProjectContents xbProjects config ({ project, newName } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.saveNewProjectWithoutRedirect { project | name = newName }
        , nameExists = projectNameExists xbProjects newName
        , nameIsTheSame = projectNameIsTheSame project newName
        , maxLength = NewName.maxLength
        , title = "Name your crosstab"
        , placeholder = "Crosstab name"
        , entity = "crosstab"
        }
        (saveFooter config "Save Crosstab and leave")
        data


saveProjectAsNewContents : WebData (IdDict XBProjectIdTag XBProject) -> Config msg -> SaveProjectAsNewData -> List (Html msg)
saveProjectAsNewContents xbProjects config ({ newName } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.saveProjectAsNew newName
        , nameExists = projectNameExists xbProjects newName
        , nameIsTheSame = False
        , maxLength = NewName.maxLength
        , title = "Name your crosstab"
        , placeholder = "Crosstab name"
        , entity = "crosstab"
        }
        (saveFooter config "Save Crosstab")
        data


saveFooter : Config msg -> String -> List (Html.Attribute msg) -> ClassName -> List (Html msg)
saveFooter config confirmText submitBtnAttrs class =
    [ Html.footer [ WeakCss.nest "footer" class ]
        [ Html.button
            [ Events.onClick config.closeModal
            , Attrs.type_ "button"
            , WeakCss.nest "action-link" class
            ]
            [ Html.text "Cancel" ]
        , Html.button
            submitBtnAttrs
            [ Html.text confirmText ]
        ]
    ]


duplicateProjectContents : WebData (IdDict XBProjectIdTag XBProject) -> Config msg -> DuplicateProjectData -> List (Html msg)
duplicateProjectContents xbProjects config ({ newName, project } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.duplicateProject newName project
        , nameExists = projectNameExists xbProjects newName
        , nameIsTheSame = False
        , maxLength = NewName.maxLength
        , title = "Name your new Crosstab"
        , placeholder = "Crosstab name"
        , entity = "crosstab"
        }
        (duplicateProjectFooter config)
        data


duplicateProjectFooter : Config msg -> List (Html.Attribute msg) -> ClassName -> List (Html msg)
duplicateProjectFooter config submitBtnAttrs class =
    [ Html.footer [ WeakCss.nest "footer" class ]
        [ Html.button
            [ Events.onClick config.closeModal
            , Attrs.type_ "button"
            , WeakCss.nest "action-link" class
            ]
            [ Html.text "Cancel" ]
        , Html.button
            submitBtnAttrs
            [ Html.text "Duplicate" ]
        ]
    ]


basicModalContents : Config msg -> { state : State, title : String, body : Html msg, confirmButton : { title : String, onClick : msg } } -> List (Html msg)
basicModalContents config { state, title, body, confirmButton } =
    [ Html.div
        [ WeakCss.nestMany [ "confirm-modal", "header" ] moduleClass ]
        [ Html.h2
            [ WeakCss.nestMany [ "confirm-modal", "headline" ] moduleClass ]
            [ Html.text title ]
        ]
    , Html.div
        [ WeakCss.nestMany [ "confirm-modal", "content" ] moduleClass ]
        [ body ]
    , Html.footer [ WeakCss.nestMany [ "confirm-modal", "footer" ] moduleClass ]
        [ Html.button
            [ Events.onClick config.closeModal
            , WeakCss.nestMany [ "confirm-modal", "action-link" ] moduleClass
            ]
            [ Html.text "Cancel" ]
        , Html.button
            [ WeakCss.nestMany [ "confirm-modal", "primary-button" ] moduleClass
            , Events.onClick confirmButton.onClick
            ]
            [ Html.text confirmButton.title ]
        ]
    , Html.viewIf (state == Processing)
        (Html.div
            [ WeakCss.nestMany [ "confirm-modal", "processing-overlay" ] moduleClass ]
            [ Spinner.view ]
        )
    ]


confirmDeleteSharedProjectContents : Config msg -> ConfirmDeleteProjectData -> List (Html msg)
confirmDeleteSharedProjectContents config { state, project } =
    basicModalContents config
        { state = state
        , title = "You are deleting a shared crosstab"
        , body =
            Html.div []
                [ Html.p []
                    [ Html.text project.name
                    , Html.text " will be deleted. There is no way to undo this."
                    ]
                , Html.p []
                    [ Html.text "Please note, deleting this crosstab will also remove it for all the users that it is currently shared with."
                    ]
                ]
        , confirmButton =
            { title = "Delete for everyone"
            , onClick = config.confirmDeleteProject project
            }
        }


confirmDeleteProjectContents : Config msg -> ConfirmDeleteProjectData -> List (Html msg)
confirmDeleteProjectContents config { state, project } =
    basicModalContents config
        { state = state
        , title = "You are deleting a crosstab"
        , body =
            Html.div []
                [ Html.p []
                    [ Html.text project.name
                    , Html.text " will be deleted. There is no way to undo this."
                    ]
                ]
        , confirmButton =
            { title = "Delete"
            , onClick = config.confirmDeleteProject project
            }
        }


confirmDeleteProjectsContents : Config msg -> ConfirmDeleteProjectsData -> List (Html msg)
confirmDeleteProjectsContents config { state, projects } =
    let
        projectsCount =
            List.length projects

        sharedWithMeCount =
            List.length <| List.filter (Data.isSharedWithMe << .shared) projects
    in
    basicModalContents config
        { state = state
        , title = "You’re about to delete"
        , body =
            Html.div []
                [ if sharedWithMeCount == projectsCount then
                    Html.p []
                        [ Html.text "Are you sure you want to remove "
                        , Html.text <| String.fromInt sharedWithMeCount
                        , Html.text <| XB2.Share.Plural.fromInt sharedWithMeCount " crosstab"
                        , Html.text " from your list? To gain access back, please ask the crosstab’s owner to share it again."
                        ]

                  else if sharedWithMeCount > 0 then
                    Html.p []
                        [ Html.text "Are you sure you want to delete "
                        , Html.text <| String.fromInt (projectsCount - sharedWithMeCount)
                        , Html.text <| XB2.Share.Plural.fromInt (projectsCount - sharedWithMeCount) " Crosstab"
                        , Html.text " and remove "
                        , Html.text <| String.fromInt sharedWithMeCount
                        , Html.text <| XB2.Share.Plural.fromInt sharedWithMeCount " Crosstab"
                        , Html.text " from your list? Any other user who has access to your Crosstabs will lose access."
                        ]

                  else
                    Html.p []
                        [ Html.text "Are you sure you want to delete "
                        , Html.text <| String.fromInt projectsCount
                        , Html.text <| XB2.Share.Plural.fromInt projectsCount " Crosstab"
                        , Html.text "? Any other user who has access to this will lose access."
                        ]
                ]
        , confirmButton =
            { title = "Yes, I'm sure"
            , onClick = config.confirmDeleteProjects projects
            }
        }


createFolderContents : WebData (IdDict XBFolderIdTag XBFolder) -> Config msg -> CreateFolderData -> List (Html msg)
createFolderContents xbFolders config ({ newName, projects } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.createFolder projects newName
        , nameExists = folderNameExists xbFolders newName
        , nameIsTheSame = False
        , maxLength = NewName.maxLength
        , title = "Create a name for your folder"
        , placeholder = "Folder name"
        , entity = "folder"
        }
        (saveFooter config "Save")
        data


moveToFolderContents : WebData (IdDict XBFolderIdTag XBFolder) -> Config msg -> MoveToFolderData -> List (Html msg)
moveToFolderContents xbFolders config { projects, selectedFolderId, initialFolderId, canMoveToFolder, state } =
    xbFolders
        |> remoteDataView
            (\dictFolders ->
                let
                    folders =
                        Dict.Any.values dictFolders
                in
                if List.isEmpty folders then
                    basicModalContents config
                        { state = state
                        , title = "You have no folders yet"
                        , body =
                            Html.div [] []
                        , confirmButton =
                            { title = "Ok"
                            , onClick = config.closeModal
                            }
                        }

                else
                    let
                        isSelected : XBFolder -> Bool
                        isSelected folder =
                            Just folder.id == selectedFolderId

                        canUpdateProjects =
                            List.all (\project -> not <| Data.isSharedWithMe project.shared) projects

                        moveOutBtnAttributes =
                            WeakCss.nestMany [ "move-to-folder-modal", "secondary-button" ] moduleClass
                                :: (case ( state, initialFolderId ) of
                                        ( Ready, Just _ ) ->
                                            case projects of
                                                [] ->
                                                    []

                                                [ singleProject ] ->
                                                    [ Events.onClickPreventDefaultAndStopPropagation (config.moveToFolder Nothing singleProject) ]

                                                multipleProjects ->
                                                    [ Events.onClickPreventDefaultAndStopPropagation (config.moveProjectsToFolder Nothing multipleProjects) ]

                                        _ ->
                                            [ Attrs.disabled True ]
                                   )

                        moveToBtnAttributes =
                            WeakCss.nestMany [ "move-to-folder-modal", "primary-button" ] moduleClass
                                :: (case ( state, canMoveToFolder ) of
                                        ( Ready, True ) ->
                                            [ Attrs.type_ "submit" -- Enter key behaviour and onClick at the same time
                                            ]

                                        _ ->
                                            [ Attrs.disabled True ]
                                   )

                        formAttributes =
                            WeakCss.nest "move-to-folder-modal" moduleClass
                                :: (case ( state, canUpdateProjects ) of
                                        ( Ready, True ) ->
                                            case projects of
                                                [] ->
                                                    []

                                                [ singleProject ] ->
                                                    [ Events.onSubmit (config.moveToFolder (List.find isSelected folders) singleProject) ]

                                                moreProjects ->
                                                    [ Events.onSubmit (config.moveProjectsToFolder (List.find isSelected folders) moreProjects) ]

                                        _ ->
                                            []
                                   )

                        folderView : XBFolder -> Html msg
                        folderView folder =
                            Html.li
                                [ WeakCss.addMany [ "move-to-folder-modal", "main", "folders", "item" ] moduleClass
                                    |> WeakCss.withStates [ ( "selected", isSelected folder ) ]
                                , Events.onClick <| config.msg <| SelectMoveToFolder folder
                                ]
                                [ Html.i
                                    [ WeakCss.nestMany [ "move-to-folder-modal", "main", "folders", "item", "icon" ] moduleClass ]
                                    [ if isSelected folder then
                                        XB2.Share.Icons.icon [] P2Icons.radioButtonFilled

                                      else
                                        XB2.Share.Icons.icon [] P2Icons.radioButtonUnfilled
                                    ]
                                , Html.div [ WeakCss.nestMany [ "move-to-folder-modal", "main", "folders", "item", "folder-name" ] moduleClass ] [ Html.text folder.name ]
                                ]

                        heading =
                            Html.div
                                [ WeakCss.nestMany [ "move-to-folder-modal", "main", "heading" ] moduleClass ]
                                [ Html.text <| "Move " ++ (String.fromInt <| List.length projects) ++ " " ++ XB2.Share.Plural.fromInt (List.length projects) "crosstab" ++ " to" ]
                    in
                    [ Html.form formAttributes
                        [ Html.header
                            [ WeakCss.nestMany [ "move-to-folder-modal", "header-with-tabs" ] moduleClass ]
                            [ Html.ul
                                [ WeakCss.nestMany [ "move-to-folder-modal", "header-with-tabs", "tabs" ] moduleClass ]
                                [ Html.li
                                    [ WeakCss.addMany [ "move-to-folder-modal", "header-with-tabs", "tabs", "tab" ] moduleClass
                                        |> WeakCss.withActiveStates [ "active" ]
                                    ]
                                    [ Html.i [ WeakCss.nestMany [ "move-to-folder-modal", "header-with-tabs", "tabs", "tab", "icon" ] moduleClass ]
                                        [ XB2.Share.Icons.icon [] P2Icons.moveToFolder
                                        ]
                                    , Html.text "Move to folder"
                                    ]
                                ]
                            , Html.button
                                [ Events.onClickPreventDefault config.closeModal
                                , Attrs.attribute "aria-label" "Close modal"
                                , WeakCss.nestMany [ "move-to-folder-modal", "header-with-tabs", "close" ] moduleClass
                                , Attrs.attribute "aria-label" "Close move to folder modal"
                                ]
                                [ XB2.Share.Icons.icon [ XB2.Share.Icons.width 32 ] P2Icons.cross ]
                            ]
                        , Html.main_
                            [ WeakCss.nestMany [ "move-to-folder-modal", "main" ] moduleClass ]
                            [ heading
                            , Html.div [ WeakCss.nestMany [ "move-to-folder-modal", "main", "folders", "items" ] moduleClass ]
                                [ Html.ul [] <| List.map folderView folders ]
                            ]
                        , Html.footer
                            [ WeakCss.nestMany [ "move-to-folder-modal", "footer" ] moduleClass ]
                            [ Html.button
                                [ Events.onClick config.closeModal
                                , Attrs.type_ "button"
                                , WeakCss.nestMany [ "move-to-folder-modal", "action-link" ] moduleClass
                                ]
                                [ Html.text "Cancel" ]
                            , Html.viewIf canUpdateProjects
                                (Html.button moveOutBtnAttributes [ Html.text "Move out of folder" ])
                            , Html.viewIf canUpdateProjects
                                (Html.button moveToBtnAttributes [ Html.text "Move Crosstabs" ])
                            ]
                        ]
                    , Html.viewIf (state == Processing)
                        (Html.div
                            [ WeakCss.nestMany [ "move-to-folder-modal", "processing-overlay" ] moduleClass ]
                            [ Spinner.view ]
                        )
                    ]
            )


renameFolderContents : WebData (IdDict XBFolderIdTag XBFolder) -> Config msg -> RenameFolderData -> List (Html msg)
renameFolderContents xbFolders config ({ folder, newName } as data) =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetProjectOrFolderName
        , saveMsg = config.renameFolder { folder | name = newName }
        , nameExists = folderNameExists xbFolders newName
        , nameIsTheSame = folderNameIsTheSame folder newName
        , maxLength = NewName.maxLength
        , title = "Rename your folder"
        , placeholder = "Folder name"
        , entity = "folder"
        }
        (saveFooter config "Rename folder")
        data


remoteDataView : (a -> List (Html msg)) -> WebData a -> List (Html msg)
remoteDataView fn webData =
    case webData of
        RemoteData.NotAsked ->
            [ Html.nothing ]

        RemoteData.Loading ->
            [ Spinner.view ]

        RemoteData.Failure err ->
            [ Html.div [ WeakCss.nest "error" moduleClass ] [ Markdown.toHtml [] <| String.fromHttpError err ] ]

        RemoteData.Success data ->
            fn data


affixGroupContentsMany_ :
    Flags
    ->
        { newExpression : Expression
        , currentExpression : Expression
        , expressionBeingAffixed : Expression
        , onSubmit : msg
        , headerText : String
        , saveButtonText : String
        , closeModal : msg
        , names : List ( Caption, Expression )
        , selectedItem : Maybe Int
        , back : msg
        , msg : Msg -> msg
        , focusedIndex : Maybe Int
        }
    -> List (Html msg)
affixGroupContentsMany_ flags data =
    let
        indexEqualsSelected : Int -> Bool
        indexEqualsSelected index =
            Maybe.map ((==) index) data.selectedItem |> Maybe.withDefault False

        viewGroup_ : Int -> ( Caption, Expression ) -> Html msg
        viewGroup_ index ( caption, expression ) =
            let
                isRenaming =
                    Maybe.map ((==) index) data.focusedIndex |> Maybe.withDefault False

                nameLengthLimitReached =
                    String.length (Caption.getName caption) >= Caption.maxUserDefinedNameLength - 10

                isExpanded =
                    indexEqualsSelected index
            in
            Html.li
                [ WeakCss.addMany [ "view-affix-modal-many", "groups", "items", "item" ] moduleClass
                    |> WeakCss.withStates [ ( "active", isRenaming ) ]
                ]
                [ Html.div
                    [ WeakCss.addMany [ "view-affix-modal-many", "groups", "items", "item", "header" ] moduleClass
                        |> WeakCss.withStates [ ( "active", isRenaming && isExpanded ) ]
                    ]
                    [ Html.span [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "icon" ] moduleClass ] [ XB2.Share.Icons.icon [] P2Icons.edit ]
                    , if isRenaming then
                        Html.map data.msg
                            (Html.input
                                [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "title-input" ] moduleClass
                                , Attrs.value <| Caption.getName caption
                                , Events.onInput <| SetGroupNameAt index
                                , Events.onBlur StopEditingInput
                                , Attrs.id (affixModalGroupNameId index)
                                ]
                                []
                            )

                      else
                        Html.span
                            [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "title" ] moduleClass
                            , Events.onClick <| data.msg <| EditingInput index
                            ]
                            [ Html.text <| Caption.getName caption
                            ]
                    , Html.span
                        [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "char-limit" ] moduleClass
                        , WeakCss.withStates [ ( "reached", nameLengthLimitReached ) ] moduleClass
                        ]
                        [ Html.text <| String.fromInt (String.length (Caption.getName caption)) ++ "/" ++ String.fromInt Caption.maxUserDefinedNameLength ]
                    , Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "buttons" ] moduleClass ]
                        [ Html.viewIf (not isExpanded) <|
                            Html.button
                                [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "view-info", "show" ] moduleClass
                                , Attrs.type_ "button"
                                , Events.onClick <| data.msg <| AddAsBasesToggleInfo index
                                ]
                                [ XB2.Share.Icons.icon [] P2Icons.eye
                                , Html.span [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "view-info", "show-label" ] moduleClass ]
                                    [ Html.text "View details"
                                    ]
                                ]
                        , Html.viewIf isExpanded <|
                            Html.button
                                [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "items", "item", "view-info", "hide" ] moduleClass
                                , Attrs.type_ "button"
                                , Events.onClick <| data.msg <| AddAsBasesToggleInfo index
                                ]
                                [ XB2.Share.Icons.icon [] P2Icons.eyeCrossed
                                , Html.text "Hide details"
                                ]
                        ]
                    ]
                , Html.div
                    [ WeakCss.addMany [ "expression-viewer", "wrapper" ] moduleClass
                        |> WeakCss.withStates [ ( "is-expanded", isExpanded ) ]
                    ]
                    [ ExpressionViewer.view flags moduleClass expression ]
                ]

        viewGroups : Html msg
        viewGroups =
            Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "groups" ] moduleClass ]
                [ Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "groups", "scroll" ] moduleClass ]
                    [ Html.ul [] <| List.indexedMap viewGroup_ data.names ]
                ]

        viewExpression : Html msg
        viewExpression =
            Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "footer", "expression" ] moduleClass ]
                [ Html.label [ WeakCss.nestMany [ "view-affix-modal-many", "footer", "expression", "label" ] moduleClass ]
                    [ Html.text <| "Attributes/audiences to be affixed to each " ++ data.headerText ++ ":" ]
                , Html.div
                    [ WeakCss.nestMany [ "view-affix-modal-many", "footer", "expression", "scroll" ] moduleClass ]
                    [ Html.div
                        [ WeakCss.nestMany [ "view-affix-modal-many", "footer", "expression", "scroll", "inner" ] moduleClass ]
                        [ ExpressionViewer.view flags moduleClass data.expressionBeingAffixed ]
                    ]
                ]
    in
    [ Html.form
        [ WeakCss.nestMany [ "view-affix-modal-many" ] moduleClass
        , Events.onSubmit data.onSubmit
        ]
        [ headerWithTabsViewWithoutX
            [ { title = "Affix to your " ++ data.headerText
              , active = True
              , icon = P2Icons.attribute
              , onClick = Nothing
              }
            ]
        , Html.main_ [ WeakCss.nestMany [ "view-affix-modal-many", "main" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "main", "back" ] moduleClass ]
                [ Html.button
                    [ WeakCss.nestMany [ "view-affix-modal-many", "main", "back-btn" ] moduleClass
                    , Events.onClickPreventDefault data.back
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.arrowLeft
                    ]
                , Html.label [ WeakCss.nestMany [ "view-affix-modal-many", "main", "back", "label" ] moduleClass ]
                    [ Html.text "Review changes" ]
                ]
            , Html.label [ WeakCss.nestMany [ "view-affix-modal-many", "top-label" ] moduleClass ]
                [ Html.text "Current group expressions:" ]
            , viewGroups
            ]
        , Html.footer [ WeakCss.nestMany [ "view-affix-modal-many", "footer" ] moduleClass ]
            [ viewExpression
            , Html.div [ WeakCss.nestMany [ "view-affix-modal-many", "footer", "buttons" ] moduleClass ]
                [ Html.button
                    [ Events.onClickPreventDefault data.closeModal
                    , WeakCss.nestMany [ "view-affix-modal-many", "action-link" ] moduleClass
                    ]
                    [ Html.text "Cancel" ]
                , Html.button
                    [ WeakCss.nestMany [ "view-affix-modal-many", "primary-button" ] moduleClass
                    , Attrs.type_ "submit"
                    ]
                    [ Html.text data.saveButtonText ]
                ]
            ]
        ]
    ]


affixGroupContentsOne_ :
    Flags
    ->
        { newExpression : Expression
        , currentExpression : Expression
        , name : String
        , onSubmit : msg
        , headerText : String
        , saveButtonText : String
        , closeModal : msg
        , msg : Msg -> msg
        , focusedIndex : Maybe Int
        , back : msg
        }
    -> List (Html msg)
affixGroupContentsOne_ flags data =
    let
        renameInput =
            Html.map data.msg
                (Html.input
                    [ WeakCss.nestMany [ "view-affix-modal-one", "groups", "items", "item", "title-input" ] moduleClass
                    , Attrs.value data.name
                    , Events.onInput <| SetGroupNameAt 0
                    , Events.onBlur StopEditingInput
                    , Attrs.id (affixModalGroupNameId 0)
                    ]
                    []
                )

        name =
            Html.span
                [ WeakCss.nestMany [ "view-affix-modal-one", "groups", "items", "item", "title" ] moduleClass
                , Events.onClick <| data.msg <| EditingInput 0
                ]
                [ Html.text data.name
                ]

        isRenaming =
            Maybe.map ((==) 0) data.focusedIndex |> Maybe.withDefault False

        nameLengthLimitReached name_ =
            String.length name_ >= Caption.maxUserDefinedNameLength - 10

        viewGroup_ : String -> Html msg
        viewGroup_ name_ =
            Html.div
                [ WeakCss.addMany [ "view-affix-modal-one", "groups", "items", "item" ] moduleClass
                    |> WeakCss.withStates [ ( "active", isRenaming ) ]
                ]
                [ XB2.Share.Icons.icon [] P2Icons.edit
                , if isRenaming then
                    renameInput

                  else
                    name
                , Html.span
                    [ WeakCss.nestMany [ "view-affix-modal-one", "groups", "items", "item", "char-limit" ] moduleClass
                    , WeakCss.withStates [ ( "reached", nameLengthLimitReached name_ ) ] moduleClass
                    ]
                    [ Html.text <| String.fromInt (String.length name_) ++ "/" ++ String.fromInt Caption.maxUserDefinedNameLength ]
                ]

        contentClass =
            WeakCss.addMany [ "view-affix-modal-one", "content" ] moduleClass

        viewExpression_ : Html msg
        viewExpression_ =
            Html.div [ WeakCss.toClass contentClass ]
                [ Html.div
                    [ WeakCss.nest "expression" contentClass
                    ]
                    [ Html.label [ WeakCss.nestMany [ "expression", "label" ] contentClass ]
                        [ Html.text "Current expression" ]
                    , Html.div
                        [ WeakCss.nestMany [ "expression", "content" ] contentClass ]
                        [ Html.div [ WeakCss.nestMany [ "expression", "content", "scroll" ] contentClass ] [ ExpressionViewer.view flags contentClass data.currentExpression ] ]
                    ]
                , Html.div
                    [ WeakCss.nest "expression" contentClass
                    ]
                    [ Html.label [ WeakCss.nestMany [ "expression", "label" ] contentClass ]
                        [ Html.text "New expression" ]
                    , Html.div
                        [ WeakCss.nestMany [ "expression", "content" ] contentClass ]
                        [ Html.div [ WeakCss.nestMany [ "expression", "content", "scroll" ] contentClass ] [ ExpressionViewer.view flags contentClass data.newExpression ] ]
                    ]
                ]
    in
    [ Html.form
        [ WeakCss.nestMany [ "view-affix-modal-one" ] moduleClass
        , Events.onSubmit data.onSubmit
        ]
        [ headerWithTabsViewWithoutX
            [ { title = "Affix to your " ++ data.headerText
              , active = True
              , icon = P2Icons.attribute
              , onClick = Nothing
              }
            ]
        , Html.main_ [ WeakCss.nestMany [ "view-affix-modal-one", "main" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "view-affix-modal-one", "main", "back" ] moduleClass ]
                [ Html.button
                    [ WeakCss.nestMany [ "view-affix-modal-one", "main", "back-btn" ] moduleClass
                    , Events.onClickPreventDefault data.back
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.arrowLeft
                    ]
                , Html.label [ WeakCss.nestMany [ "view-affix-modal-one", "main", "back", "label" ] moduleClass ]
                    [ Html.text "Review changes" ]
                ]
            , Html.label [ WeakCss.nestMany [ "view-affix-modal-one", "label" ] moduleClass ]
                [ Html.text "New group name:" ]
            , Html.div [ WeakCss.nestMany [ "view-affix-modal-one", "groups" ] moduleClass ] [ viewGroup_ data.name ]
            , viewExpression_
            ]
        , Html.footer [ WeakCss.nestMany [ "view-affix-modal-one", "footer" ] moduleClass ]
            [ Html.button
                [ Events.onClickPreventDefault data.closeModal
                , WeakCss.nestMany [ "view-affix-modal-one", "action-link" ] moduleClass
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nestMany [ "view-affix-modal-one", "primary-button" ] moduleClass
                , Attrs.type_ "submit"
                ]
                [ Html.text data.saveButtonText ]
            ]
        ]
    ]


editGroupContentsOne_ :
    Flags
    ->
        { newExpression : Expression
        , currentExpression : Expression
        , name : String
        , onSubmit : msg
        , headerText : String
        , saveButtonText : String
        , closeModal : msg
        , msg : Msg -> msg
        , focusedIndex : Maybe Int
        , back : msg
        }
    -> List (Html msg)
editGroupContentsOne_ flags data =
    let
        renameInput =
            Html.map data.msg
                (Html.input
                    [ WeakCss.nestMany [ "view-edit-modal-one", "groups", "items", "item", "title-input" ] moduleClass
                    , Attrs.value data.name
                    , Events.onInput <| SetGroupNameAt 0
                    , Events.onBlur StopEditingInput
                    , Attrs.id (editModalGroupNameId 0)
                    ]
                    []
                )

        name =
            Html.span
                [ WeakCss.nestMany [ "view-edit-modal-one", "groups", "items", "item", "title" ] moduleClass
                , Events.onClick <| data.msg <| EditingInput 0
                ]
                [ Html.text data.name
                ]

        isRenaming =
            Maybe.map ((==) 0) data.focusedIndex |> Maybe.withDefault False

        nameLengthLimitReached name_ =
            String.length name_ >= Caption.maxUserDefinedNameLength - 10

        viewGroup_ : String -> Html msg
        viewGroup_ name_ =
            Html.div
                [ WeakCss.addMany [ "view-edit-modal-one", "groups", "items", "item" ] moduleClass
                    |> WeakCss.withStates [ ( "active", isRenaming ) ]
                ]
                [ XB2.Share.Icons.icon [] P2Icons.edit
                , if isRenaming then
                    renameInput

                  else
                    name
                , Html.span
                    [ WeakCss.nestMany [ "view-edit-modal-one", "groups", "items", "item", "char-limit" ] moduleClass
                    , WeakCss.withStates [ ( "reached", nameLengthLimitReached name_ ) ] moduleClass
                    ]
                    [ Html.text <| String.fromInt (String.length name_) ++ "/" ++ String.fromInt Caption.maxUserDefinedNameLength ]
                ]

        contentClass =
            WeakCss.addMany [ "view-edit-modal-one", "content" ] moduleClass

        viewExpression_ : Html msg
        viewExpression_ =
            Html.div [ WeakCss.toClass contentClass ]
                [ Html.div
                    [ WeakCss.nest "expression" contentClass
                    ]
                    [ Html.label [ WeakCss.nestMany [ "expression", "label" ] contentClass ]
                        [ Html.text "Current expression" ]
                    , Html.div
                        [ WeakCss.nestMany [ "expression", "content" ] contentClass ]
                        [ Html.div [ WeakCss.nestMany [ "expression", "content", "scroll" ] contentClass ] [ ExpressionViewer.view flags contentClass data.currentExpression ] ]
                    ]
                , Html.div
                    [ WeakCss.nest "expression" contentClass
                    ]
                    [ Html.label [ WeakCss.nestMany [ "expression", "label" ] contentClass ]
                        [ Html.text "New expression" ]
                    , Html.div
                        [ WeakCss.nestMany [ "expression", "content" ] contentClass ]
                        [ Html.div [ WeakCss.nestMany [ "expression", "content", "scroll" ] contentClass ] [ ExpressionViewer.view flags contentClass data.newExpression ] ]
                    ]
                ]
    in
    [ Html.form
        [ WeakCss.nestMany [ "view-edit-modal-one" ] moduleClass
        , Events.onSubmit data.onSubmit
        ]
        [ headerWithTabsViewWithoutX
            [ { title = "Edit " ++ data.headerText
              , active = True
              , icon = P2Icons.attribute
              , onClick = Nothing
              }
            ]
        , Html.main_ [ WeakCss.nestMany [ "view-edit-modal-one", "main" ] moduleClass ]
            [ Html.div [ WeakCss.nestMany [ "view-edit-modal-one", "main", "back" ] moduleClass ]
                [ Html.button
                    [ WeakCss.nestMany [ "view-edit-modal-one", "main", "back-btn" ] moduleClass
                    , Events.onClickPreventDefault data.back
                    ]
                    [ XB2.Share.Icons.icon [] P2Icons.arrowLeft
                    ]
                , Html.label [ WeakCss.nestMany [ "view-edit-modal-one", "main", "back", "label" ] moduleClass ]
                    [ Html.text "Review changes" ]
                ]
            , Html.label [ WeakCss.nestMany [ "view-edit-modal-one", "label" ] moduleClass ]
                [ Html.text "New group name:" ]
            , Html.div [ WeakCss.nestMany [ "view-edit-modal-one", "groups" ] moduleClass ] [ viewGroup_ data.name ]
            , viewExpression_
            ]
        , Html.footer [ WeakCss.nestMany [ "view-edit-modal-one", "footer" ] moduleClass ]
            [ Html.button
                [ Events.onClickPreventDefault data.closeModal
                , WeakCss.nestMany [ "view-edit-modal-one", "action-link" ] moduleClass
                ]
                [ Html.text "Cancel" ]
            , Html.button
                [ WeakCss.nestMany [ "view-edit-modal-one", "primary-button" ] moduleClass
                , Attrs.type_ "submit"
                ]
                [ Html.text data.saveButtonText ]
            ]
        ]
    ]


affixGroupContents : Flags -> Config msg -> AffixGroupData -> List (Html msg)
affixGroupContents flags config { zipper, grouping, operator, expandedItem, itemBeingRenamed, attributeBrowserModal, affixedFrom } =
    let
        list : List AffixGroupItem
        list =
            Zipper.toList zipper

        groupsCount =
            List.length list

        affixGroupItem =
            Zipper.current zipper

        headerText =
            "group"

        saveButtonText =
            "Confirm"

        addedItems =
            UndoRedo.current attributeBrowserModal.browserModel |> .selectedItems

        onSubmit =
            if List.any ModalBrowser.isSelectedAverage addedItems || List.isEmpty addedItems then
                config.noOp

            else
                config.affixGroup grouping operator addedItems list affixedFrom
    in
    if groupsCount > 1 then
        affixGroupContentsMany_ flags
            { newExpression = affixGroupItem.newExpression
            , currentExpression = affixGroupItem.oldExpression
            , onSubmit = onSubmit
            , closeModal = config.closeModal
            , msg = config.msg
            , headerText = headerText
            , saveButtonText = saveButtonText
            , expressionBeingAffixed = affixGroupItem.expressionBeingAffixed
            , names =
                list
                    |> List.map
                        (\item ->
                            ( item.newCaption
                            , item.newExpression
                            )
                        )
            , selectedItem = expandedItem
            , focusedIndex = itemBeingRenamed
            , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
            }

    else
        affixGroupContentsOne_ flags
            { newExpression = affixGroupItem.newExpression
            , currentExpression = affixGroupItem.oldExpression
            , onSubmit = onSubmit
            , closeModal = config.closeModal
            , headerText = headerText
            , saveButtonText = saveButtonText
            , name = affixGroupItem |> .newCaption |> Caption.getName
            , msg = config.msg
            , focusedIndex = itemBeingRenamed
            , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
            }


editGroupContents : Flags -> Config msg -> EditGroupData -> List (Html msg)
editGroupContents flags config { zipper, grouping, itemBeingRenamed, attributeBrowserModal } =
    let
        list : List EditGroupItem
        list =
            Zipper.toList zipper

        editGroupItem =
            Zipper.current zipper

        headerText =
            "expression"

        saveButtonText =
            "Confirm"

        addedItems =
            UndoRedo.current attributeBrowserModal.browserModel |> .selectedItems

        onSubmit =
            if List.any ModalBrowser.isSelectedAverage addedItems || List.isEmpty addedItems then
                config.noOp

            else
                config.editGroup grouping addedItems list
    in
    editGroupContentsOne_ flags
        { newExpression = editGroupItem.newExpression
        , currentExpression = editGroupItem.oldExpression
        , onSubmit = onSubmit
        , closeModal = config.closeModal
        , headerText = headerText
        , saveButtonText = saveButtonText
        , name = editGroupItem |> .newCaption |> Caption.getName
        , msg = config.msg
        , focusedIndex = itemBeingRenamed
        , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
        }


affixBaseContents : Flags -> Config msg -> AffixBaseData -> List (Html msg)
affixBaseContents flags config { zipper, expandedItem, itemBeingRenamed, attributeBrowserModal } =
    let
        groupsCount =
            List.length <| Zipper.toList zipper

        headerText =
            "base"

        saveButtonText =
            "Confirm"

        onSubmitAction =
            zipper
                |> Zipper.toNonEmpty
                |> config.affixBasesInTableView

        currentItem =
            Zipper.current zipper
    in
    if groupsCount > 1 then
        affixGroupContentsMany_ flags
            { newExpression = currentItem.newExpression
            , currentExpression = BaseAudience.getExpression currentItem.baseAudience
            , onSubmit = onSubmitAction
            , headerText = headerText
            , msg = config.msg
            , saveButtonText = saveButtonText
            , closeModal = config.closeModal
            , expressionBeingAffixed = currentItem.expressionBeingAffixed
            , names =
                zipper
                    |> Zipper.toList
                    |> List.map
                        (\item ->
                            ( item.newCaption
                            , item.newExpression
                            )
                        )
            , selectedItem = expandedItem
            , focusedIndex = itemBeingRenamed
            , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
            }

    else
        affixGroupContentsOne_ flags
            { newExpression = currentItem.newExpression
            , currentExpression = BaseAudience.getExpression currentItem.baseAudience
            , onSubmit = onSubmitAction
            , headerText = headerText
            , saveButtonText = saveButtonText
            , closeModal = config.closeModal
            , name = Caption.getName currentItem.newCaption
            , msg = config.msg
            , focusedIndex = itemBeingRenamed
            , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
            }


editBaseContents : Flags -> Config msg -> EditBaseData -> List (Html msg)
editBaseContents flags config { zipper, itemBeingRenamed, attributeBrowserModal } =
    let
        headerText =
            "base expression"

        saveButtonText =
            "Confirm"

        onSubmitAction =
            zipper
                |> Zipper.toNonEmpty
                |> config.editBasesInTableView

        currentItem =
            Zipper.current zipper
    in
    editGroupContentsOne_ flags
        { newExpression = currentItem.newExpression
        , currentExpression = BaseAudience.getExpression currentItem.baseAudience
        , onSubmit = onSubmitAction
        , headerText = headerText
        , saveButtonText = saveButtonText
        , closeModal = config.closeModal
        , name = Caption.getName currentItem.newCaption
        , msg = config.msg
        , focusedIndex = itemBeingRenamed
        , back = config.msg <| OpenAttributeBrowser attributeBrowserModal
        }


headerWithTabsView : msg -> List (HeaderTab msg) -> Html msg
headerWithTabsView closeModal headerTabs =
    P2Modals.headerWithTabsView
        closeModal
        (WeakCss.add "general-modal" moduleClass)
        headerTabs


headerWithTabsViewWithoutX : List (HeaderTab msg) -> Html msg
headerWithTabsViewWithoutX headerTabs =
    P2Modals.headerWithTabsViewWithoutX
        (WeakCss.add "general-modal" moduleClass)
        headerTabs


viewGroupContents_ :
    Flags
    ->
        { onSubmit : msg
        , hasChanges : Bool
        , expression : Expression
        , closeModal : msg
        , onInput : String -> msg
        , name : String
        , headerTabs : List (HeaderTab msg)
        , btnTitle : String
        , state : State
        }
    -> List (Html msg)
viewGroupContents_ flags { hasChanges, onSubmit, onInput, closeModal, name, expression, headerTabs, btnTitle, state } =
    let
        canBeSaved =
            (state == Ready)
                && hasChanges
                && (not <| String.isEmpty name)
                && (String.length name <= Caption.maxUserDefinedNameLength)

        saveBtnAttributes =
            [ WeakCss.nestMany [ "view-group-modal", "primary-button" ] moduleClass
            , if canBeSaved then
                Attrs.type_ "submit"

              else
                Attrs.disabled True
            ]

        commonFormAttrs =
            [ WeakCss.nest "view-group-modal" moduleClass ]

        formAttributes =
            if canBeSaved then
                Events.onSubmit onSubmit :: commonFormAttrs

            else
                commonFormAttrs
    in
    [ Html.form formAttributes
        [ headerWithTabsView closeModal headerTabs
        , Html.main_
            [ WeakCss.nestMany [ "view-group-modal", "content" ] moduleClass ]
            [ Html.div
                [ WeakCss.nestMany [ "view-group-modal", "input-wrap" ] moduleClass ]
                [ TextInput.view
                    { onInput = onInput
                    , placeholder = "Audience name"
                    }
                    [ TextInput.class (WeakCss.add "view-group-modal" moduleClass)
                    , TextInput.value name
                    , TextInput.id nameFieldId
                    , TextInput.limit Caption.maxUserDefinedNameLength
                    , TextInput.icon P2Icons.edit
                    ]
                ]
            , Html.div
                [ WeakCss.nestMany [ "view-group-modal", "expression-content" ] moduleClass ]
                [ ExpressionViewer.view flags moduleClass expression ]
            ]
        , Html.footer [ WeakCss.nestMany [ "view-group-modal", "footer" ] moduleClass ]
            [ Html.button
                [ Events.onClickPreventDefault closeModal
                , Attrs.type_ "button"
                , WeakCss.nestMany [ "view-group-modal", "action-link" ] moduleClass
                ]
                [ Html.text "Cancel" ]
            , Html.button saveBtnAttributes
                [ Html.text btnTitle ]
            ]
        ]
    , Html.viewIf (state == Processing) <|
        Html.div [ WeakCss.nestMany [ "view-group-modal", "processing-overlay" ] moduleClass ]
            [ Spinner.view ]
    ]


groupContentsView : Flags -> Config msg -> ViewGroupData -> List (Html msg)
groupContentsView flags config { hasChanges, caption, oldKey, expression, direction } =
    viewGroupContents_ flags
        { onSubmit =
            config.saveGroupName direction
                { oldKey = oldKey
                , newItem = AudienceItem.setCaption caption oldKey.item
                , expression = Just expression
                }
        , hasChanges = hasChanges
        , closeModal = config.closeModal
        , onInput = config.msg << SetGroupName
        , name = Caption.getName caption
        , expression = expression
        , headerTabs = [ { title = "View/rename", active = True, icon = P2Icons.fileSearch, onClick = Nothing } ]
        , btnTitle = "Apply"
        , state = Ready
        }


renameAverageContents : Config msg -> RenameAverageData -> List (Html msg)
renameAverageContents config { hasChanges, caption, oldKey, direction } =
    modalWithNameFieldContents
        { inputMsg = config.msg << SetGroupName
        , saveMsg =
            config.saveGroupName direction
                { oldKey = oldKey
                , newItem = AudienceItem.setCaption caption oldKey.item
                , expression = Nothing
                }
        , nameExists = False
        , nameIsTheSame = not hasChanges
        , maxLength = Caption.maxUserDefinedNameLength
        , title = "Rename Average item"
        , placeholder = "Average item name"
        , entity = "average item"
        }
        (saveFooter config "Save")
        { newName = Caption.getName caption
        , state = Ready
        }


baseRenameContentsView : Flags -> Config msg -> ViewBaseGroupData -> List (Html msg)
baseRenameContentsView flags config { hasChanges, baseAudience } =
    viewGroupContents_ flags
        { onSubmit = baseAudience |> config.setOrCreateBaseAudience
        , hasChanges = hasChanges
        , closeModal = config.closeModal
        , onInput = config.msg << SetGroupName
        , name = Caption.getName <| BaseAudience.getCaption baseAudience
        , expression = BaseAudience.getExpression baseAudience
        , headerTabs = [ { title = "Rename Base", active = True, icon = P2Icons.datapoint, onClick = Nothing } ]
        , btnTitle = "Save Base"
        , state = Ready
        }


saveAsAudienceContents : Flags -> Config msg -> SaveAsAudienceData -> List (Html msg)
saveAsAudienceContents flags config { item, caption, expression, state } =
    viewGroupContents_ flags
        { onSubmit = config.saveAsAudience item caption expression
        , hasChanges = True
        , closeModal = config.closeModal
        , onInput = config.msg << SetGroupName
        , name = Caption.getName caption
        , expression = expression
        , headerTabs = [ { title = "Save as a new audience", active = True, icon = P2Icons.audiences, onClick = Nothing } ]
        , btnTitle = "Save"
        , state = state
        }


chooseMetricsContents : Config msg -> ChooseMetricsData -> Html msg
chooseMetricsContents config { chooseManyModal } =
    ChooseMany.view (chooseMetricsConfig config) chooseManyModal


attempt : Config msg -> Task x a -> Cmd msg
attempt { msg } task =
    Task.attempt (always <| msg NoOp) task


focusId : Config msg -> String -> Cmd msg
focusId config id =
    attempt config (Dom.focus id)
