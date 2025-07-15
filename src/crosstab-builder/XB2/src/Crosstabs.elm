module Crosstabs exposing
    ( Config
    , Configure
    , Model
    , Msg(..)
    , ProjectSavingState
    , StoreActionFolder
    , StoreActionProject
    , StoreActionProjects
    , StoreActionUserSettings
    , checkConfirmBeforeLeave
    , configure
    , init
    , onP2StoreChange
    , onP2StoreError
    , saveProjectAndNavigateToListIfProjectIsUnsaved
    , showUnsavedChangesDialog
    , subscriptions
    , update
    , updateForRoute
    , view
    )

import Browser.Navigation
import Cmd.Extra as Cmd
import Dict.Any
import Glue exposing (Glue)
import Glue.Lazy exposing (LazyGlue)
import Html exposing (Html)
import Html.Events as Events
import Html.Extra as Html
import Json.Decode as Decode
import Json.Encode as Encode
import List.NonEmpty as NonemptyList
import Markdown
import Maybe.Extra as Maybe
import RemoteData
import Task
import Time exposing (Posix, Zone)
import Url exposing (Url)
import WeakCss exposing (ClassName)
import XB2.Analytics as Analytics exposing (Event(..))
import XB2.Data as XBData
    exposing
        ( DoNotShowAgain
        , Shared(..)
        , XBFolder
        , XBProject
        , XBProjectError
        , XBProjectFullyLoaded
        , XBProjectId
        )
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression exposing (Expression(..))
import XB2.Data.AudienceCrosstab as ACrosstab
import XB2.Data.AudienceItem as AudienceItem
import XB2.Data.BaseAudience as BaseAudience
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect exposing (XBQueryError)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Namespace as Namespace
import XB2.Detail.Common as Common
import XB2.Modal.Browser as ModalBrowser exposing (SelectedItem, SelectedItems)
import XB2.NotificationFormatting as NotificationFormatting
import XB2.Page.Detail as Detail
import XB2.Page.List as XBList
import XB2.Router as Router
import XB2.Share.Analytics.Place as Place
import XB2.Share.Clipboard
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id
import XB2.Share.Dialog.ErrorDisplay exposing (ErrorDisplay)
import XB2.Share.Error
import XB2.Share.ErrorHandling
import XB2.Share.Export exposing (ExportError)
import XB2.Share.Gwi.Http exposing (Error(..))
import XB2.Share.Gwi.List as List
import XB2.Share.Icons exposing (IconData)
import XB2.Share.Icons.Platform2 as P2Icons
import XB2.Share.Platform2.Notification as Notification exposing (Notification)
import XB2.Share.Platform2.Notification.Queue as NotificationQueue exposing (NotificationQueue)
import XB2.Share.Platform2.Spinner as Spinner
import XB2.Share.Plural
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store
import XB2.Store as XBStore
import XB2.Utils.NewName as NewName
import XB2.Views.Modal as Modal exposing (Modal)



-- Config


type alias Config msg =
    { msg : Msg -> msg
    , navigateTo : Router.Route -> msg
    , forceNavigateTo : Router.Route -> msg
    , runStoreActions : List XB2.Share.Store.Platform2.StoreAction -> msg
    , detailConfig : Detail.Config msg
    , listConfig : XBList.Config msg
    , modalConfig : Modal.Config msg
    , createAudienceWithExpression :
        { name : String
        , expression : Expression.Expression
        }
        -> msg
    }


type alias Configure msg =
    { msg : Msg -> msg
    , navigateTo : Router.Route -> msg
    , forceNavigateTo : Router.Route -> msg
    , runStoreActions : List XB2.Share.Store.Platform2.StoreAction -> msg
    , openNewWindow : String -> msg
    , createAudienceWithExpression :
        { name : String
        , expression : Expression.Expression
        }
        -> msg
    , createNewAudienceInP2 : msg
    , editAudienceInP2 : Audience.Id -> msg
    , openSupportChat : Maybe String -> msg
    }


configure : Configure msg -> Config msg
configure rec =
    { msg = rec.msg
    , navigateTo = rec.navigateTo
    , forceNavigateTo = rec.forceNavigateTo
    , runStoreActions = rec.runStoreActions
    , detailConfig = detailConfig rec
    , listConfig = listConfig rec
    , modalConfig = modalConfig rec
    , createAudienceWithExpression = rec.createAudienceWithExpression
    }


detailConfig : Configure msg -> Detail.Config msg
detailConfig c =
    Detail.configure
        { msg = c.msg << DetailMsg
        , ajaxError = c.msg << AjaxError
        , exportAjaxError = c.msg << ExportError
        , queryAjaxError = c.msg << QueryAjaxError
        , navigateTo = c.navigateTo
        , limitReachedAddingRowOrColumn = \currentSize -> c.msg << LimitReachedAddingRowOrColumn currentSize
        , limitReachedAddingBases = \currentSize -> c.msg << LimitReachedAddingBases currentSize
        , createXBProject = c.msg << XBStoreActionProject CreateProject
        , updateXBProject = c.msg << XBStoreActionProject UpdateProject
        , setProjectToStore = c.msg << UpdateXBProjectInStore
        , saveCopyOfProject =
            \{ original, copy, shouldRedirect } ->
                c.msg <|
                    XBStoreActionProject
                        (CopyOfProject
                            { original = original
                            , shouldRedirect = shouldRedirect
                            }
                        )
                        copy
        , openModal = c.msg << OpenModal
        , openSharingModal = c.msg << OpenSharingModal
        , closeModal = c.msg CloseModal
        , disabledExportsAlert = c.msg (CreateDetailNotification P2Icons.export Nothing <| Html.text "Your exports are currently disabled, please get in touch with us if you wish to enable them.")
        , createDetailNotification = \iconData msg -> c.msg (CreateDetailNotification iconData Nothing <| Html.map DetailMsg msg)
        , createDetailPersistentNotification = \id notif -> c.msg <| CreateDetailPersistentNotification id (Notification.map DetailMsg notif)
        , closeDetailNotification = c.msg << CloseDetailNotification
        , setSharedProjectWarningDismissal =
            c.msg
                << XBStoreActionUserSettings
                << SetSharedProjectWarningDismissal
        , setDoNotShowAgain =
            c.msg
                << XBStoreActionUserSettings
                << SetDoNotShowAgain
        , fetchManyP2 = c.runStoreActions
        , updateUserSettings =
            c.msg
                << XBStoreActionUserSettings
                << SetUserSettings
        , shareAndCopyLink = c.msg << XBStoreActionProject ShareProjectWithLink
        , setNewBasesOrder =
            \{ triggeredFrom, shouldFireAnalytics } baseAudiencesOrder activeBaseIndex ->
                c.msg <|
                    DetailMsg <|
                        Detail.Edit <|
                            Detail.ApplyNewBaseAudiencesOrder
                                { triggeredFrom = triggeredFrom
                                , shouldFireAnalytics = shouldFireAnalytics
                                }
                                baseAudiencesOrder
                                activeBaseIndex
        }


listConfig : Configure msg -> XBList.Config msg
listConfig c =
    XBList.configure
        { msg = c.msg << ListMsg
        , openProject = c.navigateTo << Router.Project << Just
        , openModal = c.msg << OpenModal
        , openSharingModal = c.msg << OpenSharingModal
        , closeModal = c.msg CloseModal
        , openNewWindow = c.openNewWindow
        , createXBProject = c.msg CreateXBProject
        , moveToFolder = \maybeFolder project -> c.msg <| XBStoreActionProject (SetFolder maybeFolder) project
        , openError = c.msg << ProjectsAjaxError << OtherError << XBList.customFrontendErrorToOtherError
        , setXB2ListFTUESeen = c.msg SetXB2ListFTUESeen
        , fetchManyP2 = c.runStoreActions
        , queryAjaxError = c.msg << QueryAjaxError
        , createNotification = \iconData msg -> c.msg (CreateListNotification iconData Nothing <| Html.map ListMsg msg)
        , createPersistentNotification = \id notif -> c.msg <| CreateListPersistentNotification id (Notification.map ListMsg notif)
        , exportAjaxError = c.msg << ExportError
        , closeNotification = c.msg << CloseListNotification
        }


storeConfig : XBStore.Config Msg
storeConfig =
    { msg = CrosstabBuilderStoreMsg
    , err = AjaxError
    , projectErr = ProjectsAjaxError
    }


modalConfig : Configure msg -> Modal.Config msg
modalConfig c =
    { noOp = c.msg NoOp
    , msg = c.msg << ModalMsg
    , closeModal = c.msg CloseModal
    , openNewWindow = c.openNewWindow
    , openSupportChat = c.openSupportChat
    , renameProject = c.msg << XBStoreActionProject RenameProject
    , saveNewProjectWithoutRedirect = c.msg << XBStoreActionProject CreateProjectWithoutRedirect
    , saveProjectAsCopy = c.msg << SaveSharedProjectAsCopy
    , saveProjectAsNew = c.msg << DetailMsg << Detail.SaveProjectAsNew -- TODO this could possibly go straight from XB.Modal to XB, not through XB.Detail. Some stuff would have to go to XB.Common, not sure it's worth it.
    , duplicateProject = \name project -> c.msg <| XBStoreActionProject (DuplicateProject name) project
    , confirmDeleteProject = c.msg << XBStoreActionProject DestroyProject
    , confirmDeleteProjects = c.msg << XBStoreActionProjects RemoveProjects
    , unshareMe = c.msg << XBStoreActionProject UnshareMe
    , moveToFolder = \maybeFolder project -> c.msg <| XBStoreActionProject (SetFolder maybeFolder) project
    , moveProjectsToFolder = \maybeFolder projects -> c.msg <| XBStoreActionProjects (MoveToFolder maybeFolder) projects
    , createFolder = \name projects -> c.msg <| XBStoreActionFolder (CreateFolder name projects)
    , renameFolder = c.msg << XBStoreActionFolder << RenameFolder
    , confirmDeleteFolder = c.msg << XBStoreActionFolder << DestroyFolder
    , confirmUngroupFolder = c.msg << XBStoreActionFolder << UngroupFolder
    , applyMetricsSelection = c.msg << DetailMsg << Detail.Edit << Detail.ApplyMetricsSelection
    , applyHeatmap = c.msg << DetailMsg << Detail.ApplyHeatmap
    , setMinimumSampleSize = c.msg << DetailMsg << Detail.Edit << Detail.SetMinimumSampleSize
    , saveGroupName = \direction -> c.msg << DetailMsg << Detail.Edit << Detail.SetGroupTitle direction
    , setOrCreateBaseAudience = c.msg << DetailMsg << Detail.Edit << Detail.UpdateOrCreateBaseAudiences << NonemptyList.singleton
    , affixGroup = \grouping operator addedItems groups affixedFrom -> c.msg <| DetailMsg <| Detail.Edit <| Detail.SaveAffixedGroup grouping operator addedItems groups affixedFrom
    , editGroup = \grouping addedItems groups -> c.msg <| DetailMsg <| Detail.Edit <| Detail.SaveEditedGroup grouping addedItems groups
    , affixBasesInTableView = c.msg << DetailMsg << Detail.Edit << Detail.AffixBaseAudiences
    , editBasesInTableView = c.msg << DetailMsg << Detail.Edit << Detail.EditBaseAudiences
    , saveUnsavedProjectAndContinue = c.msg << SaveProjectAndNavigateTo
    , ignoreUnsavedChangesAndContinue = c.msg << DiscardChangesAndNavigateTo
    , saveAsAudience = \item caption expression -> c.msg <| SaveAsAudience item caption expression
    , saveAsBase = \grouping items -> c.msg <| DetailMsg <| Detail.CreateNewBases grouping items
    , mergeRowOrColumn = \grouping items directions asNew allSelected -> c.msg <| DetailMsg <| Detail.Edit <| Detail.MergeRowOrColumn grouping items directions asNew allSelected
    , reorderModalApplyChanges =
        \{ triggeredFrom, shouldFireAnalytics } baseAudiencesOrder activeBaseIndex ->
            c.msg <|
                DetailMsg <|
                    Detail.Edit <|
                        Detail.ApplyNewBaseAudiencesOrder
                            { triggeredFrom = triggeredFrom
                            , shouldFireAnalytics = shouldFireAnalytics
                            }
                            baseAudiencesOrder
                            activeBaseIndex
    , fullLoadAndApplyHeatmap = c.msg << DetailMsg << Detail.FullLoadAndApplyHeatmap
    , fullLoadAndExport = \maybeSelectionMap -> c.msg << DetailMsg << Detail.FullLoadAndExport maybeSelectionMap
    , fullLoadAndExportFromList = c.msg << ListMsg << XBList.FullLoadAndExport
    , confirmCancelFullLoad = c.msg <| DetailMsg Detail.ConfirmCancelFullTableLoad
    , confirmCancelFullLoadFromList = c.msg <| ListMsg XBList.ConfirmCancelFullTableLoad
    , turnOffViewSettingsAndContinue = c.msg <| DetailMsg Detail.TurnOffViewSettingsAndContinue
    , keepViewSettingsAndContinue = c.msg <| DetailMsg Detail.KeepViewSettingsAndContinue
    , shareProject = c.msg << XBStoreActionProject ShareProject
    , shareAndCopyLink = c.msg << XBStoreActionProject ShareProjectWithLink
    , partialLoadAndSort = c.msg << DetailMsg << Detail.LoadCellsForSorting
    , removeSortingAndCloseModal = c.msg <| DetailMsg Detail.RemoveSortingAndCloseModal
    , cancelSortingLoading = c.msg <| DetailMsg Detail.CancelSortingLoading
    , confirmDeleteRowsColumns = \doNotShowAgainChecked -> c.msg << DetailMsg << Detail.Edit << Detail.RemoveSelectedAudiences doNotShowAgainChecked
    , confirmDeleteBases = \doNotShowAgainChecked -> c.msg << DetailMsg << Detail.Edit << Detail.RemoveBaseAudiences doNotShowAgainChecked
    , browser =
        \attrBrowserModal ->
            { addItemsToTable = \direction grouping -> c.msg << DetailMsg << Detail.Edit << Detail.AddFromAttributeBrowser direction grouping (Just attrBrowserModal)
            , viewAffixModalFromAttrBrowser = \operator grouping affixedFrom -> c.msg << DetailMsg << Detail.ViewAffixGroupModalFromAttributeBrowser operator grouping attrBrowserModal affixedFrom
            , viewEditModalFromAttrBrowser = \grouping -> c.msg << DetailMsg << Detail.ViewEditGroupModalFromAttributeBrowser grouping attrBrowserModal
            , addBaseAudiences = \grouping -> c.msg << DetailMsg << Detail.Edit << Detail.AddBaseAudiences grouping
            , replaceDefaultBase = \grouping -> c.msg << DetailMsg << Detail.Edit << Detail.ReplaceDefaultBase grouping

            -- TODO: find better solution without too much boilerplate
            , noOp = c.msg <| ModalMsg Modal.NoOp
            , msg = c.msg << ModalMsg << Modal.ModalBrowserMsg
            , closeModal = c.msg CloseModal
            , createAudience = c.createNewAudienceInP2
            , editAudience = c.editAudienceInP2
            , itemToggled = \item items -> c.msg <| BrowserModalItemToggled item items
            , gotAttributeBrowserStateSnapshot = c.msg << GotAttributeBrowserStateSnapshot
            , updateUserSettings = c.msg << XBStoreActionUserSettings << SetUserSettings
            }
    }


store : Glue Model XBStore.Store Msg Msg
store =
    Glue.poly
        { get = .xbStore
        , set = \sub model -> { model | xbStore = sub }
        }


detail : LazyGlue Model Detail.Model msg msg
detail =
    Glue.poly
        { get = .detailModel
        , set = \sub model -> { model | detailModel = sub }
        }


list : LazyGlue Model XBList.Model msg msg
list =
    Glue.poly
        { get = .listModel
        , set = \sub model -> { model | listModel = sub }
        }


showUnsavedChangesDialog : Config msg -> Router.Route -> Model -> Maybe (Cmd msg)
showUnsavedChangesDialog config newRoute { detailModel } =
    Maybe.andThen
        (\dModel ->
            Detail.showUnsavedChangesDialog
                (config.msg <| OpenModal <| Modal.UnsavedChangesAlert { newRoute = newRoute })
                dModel
        )
        detailModel


saveProjectAndNavigateToListIfProjectIsUnsaved :
    Config msg
    -> Model
    -> Maybe (Cmd msg)
saveProjectAndNavigateToListIfProjectIsUnsaved config { detailModel } =
    Maybe.andThen
        (\dModel ->
            Detail.saveChangesAndGoBackToProjectList
                (config.msg (SaveProjectAndNavigateTo Router.ProjectList))
                dModel
        )
        detailModel
        |> Maybe.map
            (\cmd ->
                Cmd.batch
                    [ cmd
                    , Cmd.perform <|
                        config.msg <|
                            CreateListNotification P2Icons.tick
                                Nothing
                                (Html.text "Project saved")
                    ]
            )



-- Model


type ProjectSavingState
    = NewlyCreated
    | Existing


type alias Model =
    { modal : Maybe Modal
    , trackProjectSharing : Maybe XBData.XBProjectId
    , trackProjectSaving : Maybe ( XBData.XBProjectId, ProjectSavingState )
    , detailNotificationQueue : NotificationQueue Msg
    , listNotificationQueue : NotificationQueue Msg
    , forceNavigateToWhenProjectSaved : Maybe Router.Route

    {- Keeps track of how the initial state is saved. -}
    , attributeBrowserInitialState : String

    {- Goes hand-by-hand with the above field
       TODO: Think better about the architecture of this type to make impossible states
       impossible.
    -}
    , shouldPassInitialStateToAttributeBrowser : Bool
    , xbStore : XBStore.Store
    , detailModel : Maybe Detail.Model
    , listModel : Maybe XBList.Model
    }


init : Config msg -> ( Model, Cmd msg )
init config =
    Model
        Nothing
        Nothing
        Nothing
        NotificationQueue.empty
        (NotificationQueue.emptyWithLimit 1)
        Nothing
        (Encode.encode 0 Encode.null)
        True
        |> Cmd.pure
        |> Glue.init store (Cmd.pure XBStore.init)
        |> Glue.Lazy.initLater detail
        |> Glue.map config.msg
        |> Glue.Lazy.initLater list
        |> Cmd.add (Task.perform (config.msg << InitDetail) Time.now)
        |> Cmd.addTrigger (config.msg <| XBStoreActionUserSettings FetchXBUserSettings)


getProject : XBStore.Store -> Maybe XBProjectId -> Maybe XBProject
getProject xbStore =
    Maybe.andThen (Store.get xbStore.xbProjects)



-- Update


type StoreActionProject
    = CreateProject
    | CreateProjectWithoutRedirect
    | UpdateProject
    | RenameProject
    | DestroyProject
    | DuplicateProject String
    | CopyOfProject
        { original : XBProjectFullyLoaded
        , shouldRedirect : Bool
        }
    | FetchFullProject
    | ShareProject
    | ShareProjectWithLink
    | UnshareMe
    | SetFolder (Maybe XBFolder)


type StoreActionProjects
    = MoveToFolder (Maybe XBFolder)
    | RemoveProjects


type StoreActionFolder
    = CreateFolder (List XBProject) String
    | RenameFolder XBFolder
    | DestroyFolder XBFolder
    | UngroupFolder XBFolder


type StoreActionUserSettings
    = FetchXBUserSettings
    | SetSharedProjectWarningDismissal Bool
    | SetDoNotShowAgain DoNotShowAgain
    | SetXB2FTUESeen
    | SetUserSettings XBData.XBUserSettings


type Msg
    = NoOp
    | LoadExternalUrl String
    | DetailMsg Detail.Msg
    | ListMsg XBList.Msg
    | ModalMsg Modal.Msg
    | AjaxError (Error Never)
    | ProjectsAjaxError (Error XBProjectError)
    | QueryAjaxError (Error XBQueryError)
    | ExportError (Error ExportError)
    | CrosstabBuilderStoreMsg (XBStore.Msg Msg)
    | UpdateXBProjectInStore XBProjectFullyLoaded
    | NavigateTo Router.Route
    | CreateXBProject
    | XBProjectCreated XBProjectId
    | OpenModal Modal
    | OpenSharingModal XBProject
    | CloseModal
    | FetchSingleProject XBProjectId
    | XBStoreActionProject StoreActionProject XBProject
    | XBStoreActionProjects StoreActionProjects (List XBProject)
    | XBStoreActionFolder StoreActionFolder
    | XBStoreActionUserSettings StoreActionUserSettings
    | SaveProjectAndNavigateTo Router.Route
    | SaveSharedProjectAsCopy { original : XBProject, copy : XBProject }
    | DiscardChangesAndNavigateTo Router.Route
    | SaveAsAudience Modal.SaveAsItem Caption Expression
    | AnalyticsEvent Place.Place Analytics.Event
    | InitDetail Posix
    | SetXB2ListFTUESeen
    | BrowserModalItemToggled SelectedItem SelectedItems
    | CheckIncompatibilitiesAfterToggle SelectedItems
      -- detail notifications
    | DetailNotificationQueueMsg (NotificationQueue.Msg Msg)
    | CreateDetailNotification IconData (Maybe (Notification.Button Msg)) (Html Msg)
    | CreateDetailPersistentNotification String (Notification Msg)
    | CloseDetailNotification String
      -- list notifications
    | ListNotificationQueueMsg (NotificationQueue.Msg Msg)
    | CreateListNotification IconData (Maybe (Notification.Button Msg)) (Html Msg)
    | CreateListPersistentNotification String (Notification Msg)
    | LimitReachedAddingRowOrColumn Int ACrosstab.ErrorAddingRowOrColumn
    | LimitReachedAddingBases Int ACrosstab.ErrorAddingBase
    | CloseListNotification String
    | GotAttributeBrowserStateSnapshot Decode.Value


subscriptions : Config msg -> Router.Route -> Model -> Sub msg
subscriptions config route model =
    Sub.batch
        [ case route of
            Router.ProjectList ->
                model.listModel
                    |> Maybe.unwrap Sub.none
                        (XBList.subscriptions model.xbStore)
                    |> Sub.map (config.msg << ListMsg)

            Router.ExternalUrl _ ->
                Sub.none

            Router.Project maybeId ->
                -- using non conventional (Glue less) way of subscribing
                -- which is fine right now but with additional logic
                -- it might become better to switch to Glue style even in this function.
                model.detailModel
                    |> Maybe.unwrap Sub.none
                        (Detail.subscriptions
                            config.detailConfig
                            { isModalOpen = model.modal /= Nothing }
                            (getProject model.xbStore maybeId)
                            route
                        )
        , model.modal
            |> Maybe.map (Modal.subscriptions config.modalConfig)
            |> Maybe.withDefault Sub.none
        ]


checkConfirmBeforeLeave : Model -> Bool
checkConfirmBeforeLeave model =
    model.detailModel
        |> Maybe.unwrap False
            Detail.confirmBeforeLeave


openSavedProject :
    Config msg
    -> Flags
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> ( Model, Cmd msg )
    -> ( Model, Cmd msg )
openSavedProject config flags route p2Store ( model, cmd ) =
    let
        handleProject : XBProject -> ( Model, Cmd msg )
        handleProject project =
            case
                -- Doesn't match the last open and thus needs to be initialized
                ( Just project.id /= Maybe.andThen Detail.getLastOpenedProjectId model.detailModel
                , model.xbStore.userSettings
                , XBData.getFullyLoadedProject project
                )
            of
                ( True, RemoteData.Success userSettings, Just fullProject ) ->
                    let
                        maybeLoadedCrosstab : Maybe ACrosstab.AudienceCrosstab
                        maybeLoadedCrosstab =
                            model.listModel
                                |> Maybe.andThen (XBList.getLoadedCrosstab fullProject)

                        extraOpenInfoAnalyticsEvent =
                            maybeLoadedCrosstab
                                |> Maybe.unwrap Cmd.none
                                    (\_ ->
                                        Analytics.trackEvent flags
                                            route
                                            Place.CrosstabBuilderList
                                            (ProjectOpenedAfterExportFromListView
                                                { project = fullProject
                                                , store = p2Store
                                                }
                                            )
                                    )
                    in
                    Cmd.pure model
                        |> Glue.Lazy.updateWith detail
                            (Detail.openSavedProject
                                config.detailConfig
                                route
                                flags
                                fullProject
                                maybeLoadedCrosstab
                                p2Store
                                (Just userSettings)
                            )
                        |> Cmd.add
                            (Analytics.trackEvent flags
                                route
                                Place.CrosstabBuilderList
                                (ProjectOpened
                                    { project = fullProject
                                    , store = p2Store
                                    }
                                )
                            )
                        |> Cmd.add extraOpenInfoAnalyticsEvent

                ( True, _, Nothing ) ->
                    Cmd.pure model
                        |> Glue.Lazy.updateWith detail
                            (Detail.clearWorkspace
                                config.detailConfig
                                flags
                                p2Store
                                (RemoteData.toMaybe model.xbStore.userSettings)
                            )
                        |> Cmd.addTrigger (config.msg <| XBStoreActionProject FetchFullProject project)

                ( False, _, Just fullProject ) ->
                    model
                        |> Glue.Lazy.updateModelWith detail Detail.reopeingProject
                        |> Cmd.pure
                        |> Glue.Lazy.updateWith detail (Cmd.pure >> Detail.checkIfSharedProjectIsUpToDate config.detailConfig fullProject)

                _ ->
                    -- The project was last opened OR we don't have waves and locations => do nothing
                    Cmd.pure model
    in
    Cmd.add cmd
        (case route of
            Router.Project (Just projectId) ->
                case model.xbStore.xbProjects of
                    RemoteData.Success projects ->
                        case Dict.Any.get projectId projects of
                            Nothing ->
                                Cmd.pure model
                                    |> Cmd.addTrigger (config.msg <| FetchSingleProject projectId)

                            Just project ->
                                handleProject project

                    _ ->
                        -- Project data not yet loaded
                        Cmd.pure model

            Router.Project Nothing ->
                Cmd.pure model
                    |> Glue.Lazy.updateWith detail
                        (Detail.openNewProject
                            config.detailConfig
                            flags
                            p2Store
                            (RemoteData.toMaybe model.xbStore.userSettings)
                        )
                    |> Cmd.addMaybe
                        (\detailModel ->
                            Analytics.trackEvent flags
                                route
                                Place.CrosstabBuilderList
                                (UnsavedProjectOpened
                                    { project =
                                        Detail.getNewProjectFromCrosstab
                                            flags
                                            "new"
                                            detailModel
                                    , store = p2Store
                                    }
                                )
                        )
                        model.detailModel

            Router.ProjectList ->
                closeModal model
                    |> Cmd.pure

            Router.ExternalUrl _ ->
                Cmd.pure model
        )


getLineageRequestsForProject : XBStore.Store -> Maybe XBProjectId -> List XB2.Share.Store.Platform2.StoreAction
getLineageRequestsForProject xbStore =
    Common.getDatasetCodesFromProject xbStore >> List.map XB2.Share.Store.Platform2.FetchLineage


updateForRoute :
    Config msg
    -> Flags
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> ( Model, Cmd msg )
updateForRoute config flags route p2Store model =
    let
        routeRelatedCmd =
            case route of
                Router.ExternalUrl _ ->
                    Cmd.none

                Router.ProjectList ->
                    Cmd.batch
                        [ XBList.updateTime config.listConfig
                        , Detail.setCollapsedHeader config.detailConfig False
                        , Cmd.perform <|
                            config.runStoreActions
                                -- need these data for analytics events triggered from project list
                                [ XB2.Share.Store.Platform2.FetchAllWaves
                                , XB2.Share.Store.Platform2.FetchAllLocations

                                -- Audience browser
                                , XB2.Share.Store.Platform2.FetchDatasets
                                ]
                        ]

                Router.Project maybeProjectId ->
                    Cmd.batch
                        [ Detail.updateTime config.detailConfig
                        , Cmd.perform <|
                            config.runStoreActions
                                ([ XB2.Share.Store.Platform2.FetchAudienceFolders
                                 , XB2.Share.Store.Platform2.FetchAllWaves
                                 , XB2.Share.Store.Platform2.FetchAllLocations

                                 -- Audience browser
                                 , XB2.Share.Store.Platform2.FetchDatasets
                                 , XB2.Share.Store.Platform2.FetchDatasetFolders
                                 ]
                                    ++ -- warning for incompatible namespaces
                                       getLineageRequestsForProject model.xbStore maybeProjectId
                                )
                        ]

        -- We don't keep the initial-state in the model in List page
        routeRelatedModel : Model
        routeRelatedModel =
            { model
                | attributeBrowserInitialState =
                    case route of
                        Router.ExternalUrl _ ->
                            Encode.encode 0 Encode.null

                        Router.ProjectList ->
                            Encode.encode 0 Encode.null

                        Router.Project _ ->
                            model.attributeBrowserInitialState
            }
    in
    Cmd.pure routeRelatedModel
        |> Glue.updateWith store (XBStore.fetchXBProjectList storeConfig flags)
        |> Glue.updateWith store (XBStore.fetchXBFolders storeConfig flags)
        |> Glue.map config.msg
        |> Cmd.add routeRelatedCmd
        |> openSavedProject config flags route p2Store


closeModal : Model -> Model
closeModal model =
    { model | modal = Nothing, shouldPassInitialStateToAttributeBrowser = True }


onP2StoreChange :
    Config msg
    -> Flags
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> XB2.Share.Store.Platform2.Msg
    -> Model
    -> ( Model, Cmd msg )
onP2StoreChange config flags route newP2Store p2StoreMsg model =
    let
        open =
            openSavedProject config flags route newP2Store

        openProjectWhenLoadedMissingData : ( Model, Cmd msg ) -> ( Model, Cmd msg )
        openProjectWhenLoadedMissingData =
            case p2StoreMsg of
                XB2.Share.Store.Platform2.LocationsFetched _ ->
                    open

                XB2.Share.Store.Platform2.WavesFetched _ ->
                    open

                _ ->
                    identity
    in
    (case route of
        Router.ExternalUrl _ ->
            Cmd.pure model

        Router.ProjectList ->
            Cmd.pure model
                |> Glue.Lazy.updateWith list
                    (XBList.onP2StoreChange
                        config.listConfig
                        route
                        flags
                        newP2Store
                        p2StoreMsg
                    )

        Router.Project _ ->
            Cmd.pure model
                |> Glue.Lazy.updateWith detail
                    (Detail.onP2StoreChange
                        config.detailConfig
                        route
                        flags
                        newP2Store
                        p2StoreMsg
                    )
    )
        |> openProjectWhenLoadedMissingData


onP2StoreError :
    Config msg
    -> { showModal : Bool }
    -> Flags
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> Error Never
    -> Maybe Url
    -> Model
    -> ( Model, Cmd msg )
onP2StoreError config { showModal } flags route newP2Store err maybeUrl model_ =
    let
        model =
            updateModal (Modal.setState Modal.Ready) model_
    in
    (case route of
        Router.ProjectList ->
            Cmd.pure model

        Router.ExternalUrl _ ->
            Cmd.pure model

        Router.Project _ ->
            Cmd.pure model
                |> Glue.Lazy.updateWith detail
                    (Detail.onP2StoreError
                        config.detailConfig
                        flags
                        newP2Store
                    )
    )
        |> (if showModal then
                Glue.updateWith Glue.id (handleAjaxError config flags maybeUrl never err)

            else
                identity
           )


updateModal : (Modal -> Modal) -> Model -> Model
updateModal fn model =
    { model | modal = Maybe.map fn model.modal }


notifyListAboutFinishedStoreAction : Router.Route -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
notifyListAboutFinishedStoreAction route =
    case route of
        Router.ProjectList ->
            Glue.Lazy.updateWith list XBList.storeActionFinished

        Router.Project _ ->
            identity

        Router.ExternalUrl _ ->
            identity


copySharedLink : Config msg -> Flags -> Router.Route -> XBProject -> Model -> ( Model, Cmd msg )
copySharedLink config flags route project model =
    let
        prefix : Maybe String
        prefix =
            XB2.Share.Config.combinePrefixAndFeature flags

        createNotification =
            case route of
                Router.ProjectList ->
                    CreateListNotification

                Router.Project _ ->
                    CreateDetailNotification

                Router.ExternalUrl _ ->
                    CreateDetailNotification

        url =
            Router.toUrlString prefix (Router.Project <| Just project.id) []

        notificationMsg =
            config.msg <| createNotification P2Icons.tick Nothing <| Html.text "Url copied to the clipboard."
    in
    closeModal model
        |> Cmd.with (XB2.Share.Clipboard.addHostAndCopyToClipboard url)
        |> Cmd.addTrigger notificationMsg


updateXBStore :
    Config msg
    -> Flags
    -> XBStore.Msg Msg
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> Model
    -> ( Model, Cmd msg )
updateXBStore config flags xbMsg route p2Store model =
    let
        ( eventPlace, createNotification ) =
            case route of
                Router.ProjectList ->
                    ( Place.CrosstabBuilderList
                    , CreateListNotification
                    )

                Router.Project _ ->
                    ( Place.CrosstabBuilder
                    , CreateDetailNotification
                    )

                Router.ExternalUrl _ ->
                    ( Place.UnknownPlace
                    , CreateDetailNotification
                    )

        removeFolderIfIsEmpty : Maybe XBData.XBFolderId -> ( Model, Cmd msg ) -> ( Model, Cmd msg )
        removeFolderIfIsEmpty oldFolderId =
            case oldFolderId of
                Just oldFolderId_ ->
                    let
                        isOldFolderEmpty : Bool
                        isOldFolderEmpty =
                            model.xbStore.xbProjects
                                |> RemoteData.toMaybe
                                |> Maybe.unwrap False (Dict.Any.values >> List.any (.folderId >> (==) oldFolderId) >> not)
                    in
                    if isOldFolderEmpty then
                        Store.get model.xbStore.xbFolders oldFolderId_
                            |> Maybe.unwrap identity
                                (Cmd.addTrigger << config.msg << XBStoreActionFolder << DestroyFolder)

                    else
                        identity

                Nothing ->
                    identity
    in
    (case xbMsg of
        XBStore.AjaxError _ _ ->
            model
                |> updateModal (Modal.setState Modal.Ready)
                |> Cmd.pure

        XBStore.ProjectAjaxError _ _ ->
            { model | forceNavigateToWhenProjectSaved = Nothing }
                |> updateModal (Modal.setState Modal.Ready)
                |> Cmd.pure

        XBStore.XBProjectsFetched _ ->
            Cmd.pure model
                |> openSavedProject config flags route p2Store

        XBStore.XBProjectFetched _ ->
            Cmd.pure model
                |> openSavedProject config flags route p2Store

        XBStore.XBProjectDuplicated { original, duplicate, shouldRedirect } ->
            let
                analyticsCmd =
                    XBStore.fetchTaskXBProjectFullyLoaded original flags
                        |> Task.andThen
                            (\originalFull ->
                                XBStore.fetchTaskXBProjectFullyLoaded duplicate flags
                                    |> Task.map
                                        (\duplicateFull ->
                                            AnalyticsEvent
                                                eventPlace
                                                (ProjectDuplicated
                                                    { project = duplicateFull
                                                    , originalProject = originalFull
                                                    , store = p2Store
                                                    }
                                                )
                                        )
                            )
                        |> Task.attempt (Result.withDefault NoOp >> config.msg)

                notificationBody text =
                    Html.div []
                        [ Html.text <| duplicate.name ++ text ]

                ( finalText, iconData ) =
                    if XBData.isSharedWithMe original.shared then
                        let
                            notificationForCopyOfSharedProject =
                                Html.text <| duplicate.name ++ " has been saved"
                        in
                        ( notificationForCopyOfSharedProject, P2Icons.changes )

                    else
                        case route of
                            Router.Project _ ->
                                ( notificationBody " is available in Saved Crosstabs", P2Icons.crossSmall )

                            Router.ProjectList ->
                                ( notificationBody " has been saved", P2Icons.changes )

                            Router.ExternalUrl _ ->
                                ( notificationBody "", P2Icons.changes )

                shouldShowOpenButton : Bool
                shouldShowOpenButton =
                    not shouldRedirect

                notificationMsg =
                    finalText
                        |> createNotification iconData
                            (if shouldShowOpenButton then
                                Just
                                    { onClick = NavigateTo <| Router.Project <| Just duplicate.id
                                    , label = "Open"
                                    }

                             else
                                Nothing
                            )
                        |> config.msg
            in
            (if XBData.isSharedWithMe original.shared && shouldRedirect then
                updateXbProjectCreated config duplicate.id model

             else
                Cmd.pure model
            )
                |> Tuple.mapFirst closeModal
                |> Cmd.add analyticsCmd
                |> (model.forceNavigateToWhenProjectSaved
                        |> Maybe.unwrap (Cmd.addTrigger notificationMsg)
                            (\newRoute ->
                                Glue.updateWith Glue.id (\m -> Cmd.pure { m | forceNavigateToWhenProjectSaved = Nothing })
                                    >> Glue.Lazy.updateWith detail
                                        (Detail.clearWorkspace config.detailConfig
                                            flags
                                            p2Store
                                            (RemoteData.toMaybe model.xbStore.userSettings)
                                        )
                                    >> Cmd.addTrigger (config.forceNavigateTo newRoute)
                            )
                   )

        XBStore.XBProjectCreated _ _ ->
            Cmd.pure { model | forceNavigateToWhenProjectSaved = Nothing }
                |> (model.forceNavigateToWhenProjectSaved
                        |> Maybe.unwrap identity
                            (\newRoute ->
                                Glue.Lazy.updateWith detail
                                    (Detail.clearWorkspace config.detailConfig
                                        flags
                                        p2Store
                                        (RemoteData.toMaybe model.xbStore.userSettings)
                                    )
                                    >> Cmd.addTrigger (config.forceNavigateTo newRoute)
                            )
                   )

        XBStore.XBProjectShared project ->
            let
                notify =
                    config.msg << createNotification P2Icons.tick Nothing << Html.text

                notificationMsg =
                    case project.shared of
                        MyPrivateCrosstab ->
                            notify "Crosstab unshared with everyone"

                        MySharedCrosstab sharees ->
                            let
                                isSharedWithOrg : Bool
                                isSharedWithOrg =
                                    NonemptyList.any XBData.isOrgSharee sharees

                                userEmails : List String
                                userEmails =
                                    sharees
                                        |> NonemptyList.toList
                                        |> List.filterMap XBData.userShareeEmail

                                emailsCount =
                                    List.length userEmails

                                copy =
                                    if isSharedWithOrg then
                                        if List.isEmpty userEmails then
                                            "Crosstab shared with everyone in your organisation."

                                        else
                                            "Crosstab shared with everyone in your organisation and with "
                                                ++ String.fromInt emailsCount
                                                ++ " other "
                                                ++ XB2.Share.Plural.fromInt emailsCount "person"
                                                ++ "."

                                    else
                                        "Crosstab shared with "
                                            ++ String.fromInt emailsCount
                                            ++ " "
                                            ++ XB2.Share.Plural.fromInt emailsCount "person"
                                            ++ "."
                            in
                            notify copy

                        _ ->
                            config.msg NoOp

                maybeProject =
                    XBData.getFullyLoadedProject project

                questionCodes =
                    maybeProject
                        |> Maybe.unwrap [] XBData.getProjectQuestionCodes

                fetchQuestionsForAnalyticsCmd =
                    questionCodes
                        |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                        |> config.runStoreActions
            in
            closeModal { model | trackProjectSharing = Maybe.map .id maybeProject }
                |> Cmd.withTrigger notificationMsg
                |> Cmd.addTrigger fetchQuestionsForAnalyticsCmd

        XBStore.XBProjectSharedWithLink project ->
            copySharedLink config flags route project model

        XBStore.XBProjectDestroyed xbProject ->
            let
                doRedirect =
                    route == Router.Project (Just xbProject.id)

                redirectCmd =
                    if doRedirect then
                        Cmd.perform (config.navigateTo Router.ProjectList)

                    else
                        Cmd.none

                analyticsCmd =
                    Analytics.trackEvent flags
                        route
                        eventPlace
                        (ProjectDeleted
                            { project = xbProject
                            , store = p2Store
                            }
                        )

                notificationMsg =
                    config.msg <| createNotification P2Icons.trash Nothing (Html.text <| xbProject.name ++ " has been deleted")
            in
            closeModal model
                |> Cmd.with analyticsCmd
                |> Glue.Lazy.updateWith detail
                    (Detail.projectDestroyed config.detailConfig flags p2Store model.xbStore xbProject.id)
                |> Cmd.addTrigger notificationMsg
                |> removeFolderIfIsEmpty xbProject.folderId
                |> Cmd.add redirectCmd

        XBStore.XBProjectRenamed xbProject ->
            let
                notificationMsg =
                    config.msg <| createNotification P2Icons.tick Nothing (Html.text <| xbProject.name ++ " has been renamed")

                analyticsCmd =
                    XBStore.fetchTaskXBProjectFullyLoaded xbProject flags
                        |> Task.map
                            (\project ->
                                AnalyticsEvent eventPlace
                                    (ProjectRenamed
                                        { project = project
                                        , store = p2Store
                                        }
                                    )
                            )
                        |> Task.attempt (Result.withDefault NoOp >> config.msg)
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
                |> Cmd.add analyticsCmd

        XBStore.XBProjectsMovedToFolder { projects, folderId, oldFolderId } ->
            let
                projectsLength =
                    List.length projects

                notificationMsg =
                    config.msg <|
                        createNotification P2Icons.moveToFolder
                            Nothing
                            (NotificationFormatting.formattedLine
                                notificationClass
                                [ ( NotificationFormatting.Bold, String.fromInt projectsLength )
                                , ( NotificationFormatting.Plain, XB2.Share.Plural.fromInt projectsLength " project" ++ " " ++ XB2.Share.Plural.fromInt projectsLength "have" ++ " been moved" )
                                , ( NotificationFormatting.Plain
                                  , folderId
                                        |> Maybe.andThen (Store.get model.xbStore.xbFolders)
                                        |> Maybe.unwrap "" (.name >> (++) " to ")
                                  )
                                ]
                            )

                analyticsFolderName =
                    Maybe.or folderId oldFolderId
                        |> Maybe.andThen (Store.get model.xbStore.xbFolders)
                        |> Maybe.unwrap "" .name

                analyticsCmd =
                    Analytics.trackEvent flags route Place.CrosstabBuilderList <|
                        MoveProjectsTo
                            { folderName = analyticsFolderName
                            , movingOut = Maybe.isNothing folderId
                            , projects = projects
                            }
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
                |> removeFolderIfIsEmpty oldFolderId
                |> Cmd.add analyticsCmd

        XBStore.XBProjectsDestroyedAndUnshared projects ->
            let
                unsharedCount =
                    List.length <| List.filter (XBData.isSharedWithMe << .shared) projects

                destroyedCount =
                    List.length projects - unsharedCount

                destroyedCopy =
                    if destroyedCount > 0 then
                        [ ( NotificationFormatting.Bold, String.fromInt destroyedCount )
                        , ( NotificationFormatting.Plain, XB2.Share.Plural.fromInt destroyedCount " project" ++ " " ++ XB2.Share.Plural.fromInt destroyedCount "have" ++ " been deleted.\n" )
                        ]

                    else
                        []

                unsharedCopy =
                    if unsharedCount > 0 then
                        [ ( NotificationFormatting.Bold, String.fromInt unsharedCount )
                        , ( NotificationFormatting.Plain, XB2.Share.Plural.fromInt unsharedCount " project" ++ " " ++ XB2.Share.Plural.fromInt unsharedCount "have" ++ " been removed from your list." )
                        ]

                    else
                        []

                notificationMsg =
                    config.msg <|
                        createNotification
                            P2Icons.trash
                            Nothing
                            (NotificationFormatting.formattedLine
                                notificationClass
                                (destroyedCopy ++ unsharedCopy)
                            )
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg

        XBStore.XBProjectFolderSet { project, oldFolderId } ->
            let
                fallbackCopy : List ( NotificationFormatting.TextType, String )
                fallbackCopy =
                    [ ( NotificationFormatting.Bold, project.name )
                    , ( NotificationFormatting.Plain, " has been moved" )
                    ]

                notificationCopy : List ( NotificationFormatting.TextType, String )
                notificationCopy =
                    case project.folderId of
                        Just newFolderId ->
                            Store.get model.xbStore.xbFolders newFolderId
                                |> Maybe.map
                                    (\newFolder ->
                                        [ ( NotificationFormatting.Bold, project.name )
                                        , ( NotificationFormatting.Plain, " has been moved to " )
                                        , ( NotificationFormatting.Bold, newFolder.name )
                                        ]
                                    )
                                |> Maybe.withDefault fallbackCopy

                        Nothing ->
                            case oldFolderId of
                                Nothing ->
                                    {- Moving out of Nothing (root level) to Nothing (root level).
                                       This shouldn't happen, we can't rule it off in the type system though
                                    -}
                                    fallbackCopy

                                Just oldFolderId_ ->
                                    Store.get model.xbStore.xbFolders oldFolderId_
                                        |> Maybe.map
                                            (\oldFolder ->
                                                [ ( NotificationFormatting.Bold, project.name )
                                                , ( NotificationFormatting.Plain, " has been moved out of " )
                                                , ( NotificationFormatting.Bold, oldFolder.name )
                                                ]
                                            )
                                        |> Maybe.withDefault fallbackCopy

                notificationMsg =
                    config.msg <|
                        createNotification
                            P2Icons.moveToFolder
                            Nothing
                            (NotificationFormatting.formattedLine
                                notificationClass
                                notificationCopy
                            )

                analyticsFolderName =
                    Maybe.or project.folderId oldFolderId
                        |> Maybe.andThen (Store.get model.xbStore.xbFolders)
                        |> Maybe.unwrap "" .name

                analyticsCmd =
                    Analytics.trackEvent flags route Place.CrosstabBuilderList <|
                        MoveProjectsTo
                            { folderName = analyticsFolderName
                            , movingOut = Maybe.isNothing project.folderId
                            , projects = [ project ]
                            }
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
                |> removeFolderIfIsEmpty oldFolderId
                |> Cmd.add analyticsCmd

        XBStore.XBProjectUpdated xbProject ->
            let
                notificationMsg =
                    if Maybe.isNothing model.forceNavigateToWhenProjectSaved then
                        Cmd.addTrigger <| config.msg <| createNotification P2Icons.changes Nothing (Html.text <| xbProject.name ++ " has been saved")

                    else
                        identity

                navigateToIfNeeded =
                    model.forceNavigateToWhenProjectSaved
                        |> Maybe.unwrap identity (config.forceNavigateTo >> Cmd.addTrigger)

                maybeProject =
                    XBData.getFullyLoadedProject xbProject

                questionCodes =
                    maybeProject
                        |> Maybe.unwrap [] XBData.getProjectQuestionCodes

                fetchQuestionsForAnalyticsCmd =
                    questionCodes
                        |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                        |> config.runStoreActions
            in
            { model | forceNavigateToWhenProjectSaved = Nothing }
                |> closeModal
                |> Cmd.pure
                |> Glue.Lazy.updateWith detail (Detail.projectUpdated xbProject route)
                |> notificationMsg
                |> Glue.updateWith Glue.id (\m -> Cmd.pure { m | trackProjectSaving = Just ( xbProject.id, Existing ) })
                |> navigateToIfNeeded
                |> Cmd.addTrigger fetchQuestionsForAnalyticsCmd

        XBStore.XBFoldersFetched _ ->
            ( model, Cmd.none )

        XBStore.XBFolderCreated xbProjects xbFolder ->
            let
                setFolderCmds : List (Cmd msg)
                setFolderCmds =
                    List.map
                        (\xbProject ->
                            Cmd.perform <| config.msg <| XBStoreActionProject (SetFolder (Just xbFolder)) xbProject
                        )
                        xbProjects

                analyticsCmd =
                    Analytics.trackEvent flags route Place.CrosstabBuilderList <|
                        FolderCreated
                            { folder = xbFolder
                            , projects = xbProjects
                            }
            in
            ( closeModal model, Cmd.batch setFolderCmds )
                |> Cmd.add analyticsCmd

        XBStore.XBFolderRenamed xbFolder ->
            let
                notificationMsg =
                    config.msg <| createNotification P2Icons.tick Nothing (Html.text <| xbFolder.name ++ " has been renamed")
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg

        XBStore.XBFolderWithContentDestroyed xbFolder removedProjects ->
            let
                notificationMsg =
                    config.msg <| createNotification P2Icons.trash Nothing (Html.text <| xbFolder.name ++ " has been deleted")

                analyticsCmd =
                    Analytics.trackEvent flags route Place.CrosstabBuilderList <|
                        FolderDeleted
                            { folder = xbFolder
                            , projects = removedProjects
                            }
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
                |> Glue.Lazy.updateWith list (XBList.folderDeleted xbFolder.id >> Cmd.pure)
                |> Cmd.add analyticsCmd

        XBStore.XBFolderDestroyed xbFolder projectsInFolder ->
            let
                notificationMsg =
                    config.msg <| createNotification P2Icons.tick Nothing (Html.text <| xbFolder.name ++ " has been ungrouped")

                analyticsCmd =
                    Analytics.trackEvent flags route Place.CrosstabBuilderList <|
                        UngroupedFolder
                            { folder = xbFolder
                            , projects = projectsInFolder
                            }
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
                |> Glue.Lazy.updateWith list (XBList.folderDeleted xbFolder.id >> Cmd.pure)
                |> Cmd.add analyticsCmd

        XBStore.XBUserSettingsFetched settings ->
            ( model, Cmd.none )
                |> Glue.Lazy.updateWith detail
                    (Detail.updateSharedProjectWarning settings)
                |> Glue.Lazy.ensure list
                    (always <| XBList.init config.listConfig flags route settings)

        XBStore.XBUserSettingsUpdated _ ->
            ( model, Cmd.none )

        XBStore.XBUserSettingsUpdatedDoNotSave ->
            ( model, Cmd.none )

        XBStore.XBProjectUnshared _ ->
            let
                notificationMsg =
                    config.msg <| createNotification P2Icons.trash Nothing <| Html.text "Crosstab was removed from your list."
            in
            closeModal model
                |> Cmd.withTrigger notificationMsg
    )
        |> notifyListAboutFinishedStoreAction route


projectSavedAnalytics : Config msg -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
projectSavedAnalytics config p2Store model =
    let
        maybeProject =
            model.trackProjectSaving
                |> Maybe.map Tuple.first
                |> getProject model.xbStore
                |> Maybe.andThen XBData.getFullyLoadedProject

        questionCodes =
            maybeProject
                |> Maybe.unwrap [] XBData.getProjectQuestionCodes

        questions =
            questionCodes
                |> Maybe.traverse (\code -> XB2.Share.Store.Platform2.getQuestionMaybe code p2Store)

        newlyCreated =
            case Maybe.map Tuple.second model.trackProjectSaving of
                Just savingState ->
                    savingState == NewlyCreated

                Nothing ->
                    False
    in
    case ( questions, maybeProject ) of
        ( Just qs, Just project ) ->
            let
                analyticsCmd : Cmd msg
                analyticsCmd =
                    AnalyticsEvent
                        Place.CrosstabBuilder
                        (ProjectSaved
                            { project = project
                            , newlyCreated = newlyCreated
                            , store = p2Store
                            , questions = qs
                            }
                        )
                        |> config.msg
                        |> Cmd.perform
            in
            Cmd.pure { model | trackProjectSaving = Nothing }
                |> Cmd.add analyticsCmd

        _ ->
            Cmd.pure model


updateXBStoreActionProject : Config msg -> Flags -> Router.Route -> StoreActionProject -> XBProject -> Model -> ( Model, Cmd msg )
updateXBStoreActionProject config flags route action project model =
    let
        updateStore_ storeFn xbProject =
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (storeFn storeConfig xbProject flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)

        resolveTask result =
            config.msg <|
                case result of
                    Ok msg ->
                        msg

                    Err err ->
                        ProjectsAjaxError err

        handleChainForNotFullyLoadedProject : (XBProjectFullyLoaded -> ( Model, Cmd msg )) -> (XBProject -> Msg) -> ( Model, Cmd msg )
        handleChainForNotFullyLoadedProject whenLoaded afterLoadedAction =
            case project.data of
                RemoteData.Success _ ->
                    XBData.getFullyLoadedProject project
                        |> Maybe.unwrap (Cmd.pure model) whenLoaded

                RemoteData.NotAsked ->
                    ( model
                    , XBData.fetchTaskXBProjectFullyLoaded project flags
                        |> Task.map (afterLoadedAction << XBData.fullyLoadedToProject)
                        |> Task.attempt resolveTask
                    )

                _ ->
                    Cmd.pure model
    in
    case action of
        CreateProject ->
            let
                maybeProject =
                    XBData.getFullyLoadedProject project

                questionCodes =
                    maybeProject
                        |> Maybe.unwrap [] XBData.getProjectQuestionCodes

                fetchQuestionsForAnalyticsCmd =
                    questionCodes
                        |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                        |> config.runStoreActions
            in
            handleChainForNotFullyLoadedProject
                (updateStore_
                    (XBStore.createXBProject
                        (model.listModel |> Maybe.andThen .currentFolderId)
                        [ Cmd.perform << XBProjectCreated << .id
                        , always <| Cmd.perform CloseModal
                        ]
                    )
                )
                (\xbProject -> XBStoreActionProject CreateProject xbProject)
                |> Glue.updateWith Glue.id (\m -> Cmd.pure { m | trackProjectSaving = Just ( project.id, NewlyCreated ) })
                |> Cmd.addTrigger fetchQuestionsForAnalyticsCmd

        CreateProjectWithoutRedirect ->
            let
                maybeProject =
                    XBData.getFullyLoadedProject project

                questionCodes =
                    maybeProject
                        |> Maybe.unwrap [] XBData.getProjectQuestionCodes

                fetchQuestionsForAnalyticsCmd =
                    questionCodes
                        |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                        |> config.runStoreActions
            in
            handleChainForNotFullyLoadedProject
                (updateStore_
                    (XBStore.createXBProject
                        (model.listModel |> Maybe.andThen .currentFolderId)
                        []
                    )
                )
                (XBStoreActionProject CreateProjectWithoutRedirect)
                |> Glue.updateWith Glue.id (closeModal >> Cmd.pure)
                |> Glue.updateWith Glue.id (\m -> Cmd.pure { m | trackProjectSaving = Just ( project.id, NewlyCreated ) })
                |> Cmd.addTrigger fetchQuestionsForAnalyticsCmd

        UpdateProject ->
            handleChainForNotFullyLoadedProject
                (updateStore_ XBStore.updateXBProject)
                (XBStoreActionProject UpdateProject)

        RenameProject ->
            updateStore_ XBStore.renameXBProject project

        DestroyProject ->
            handleChainForNotFullyLoadedProject
                (updateStore_ XBStore.destroyXBProject)
                (XBStoreActionProject DestroyProject)

        FetchFullProject ->
            updateStore_ XBStore.fetchXBProject project

        DuplicateProject newName ->
            handleChainForNotFullyLoadedProject
                (updateStore_
                    (\c p ->
                        XBStore.duplicateXBProject c
                            { newName = newName
                            , originalProject = p
                            }
                    )
                )
                (XBStoreActionProject <| DuplicateProject newName)

        CopyOfProject ({ original, shouldRedirect } as r) ->
            handleChainForNotFullyLoadedProject
                (updateStore_
                    (\c copyFull ->
                        XBStore.copyOfXBProject c
                            { original = original
                            , copy = copyFull
                            , shouldRedirect = shouldRedirect
                            }
                    )
                )
                (XBStoreActionProject <| CopyOfProject r)

        ShareProject ->
            updateStore_ XBStore.shareXBProject project

        ShareProjectWithLink ->
            (if project.shared == XBData.SharedByLink then
                copySharedLink config flags route project model

             else
                updateStore_ XBStore.shareXBProjectWithLink project
            )
                |> Cmd.add (Analytics.trackEvent flags route Place.CrosstabBuilder <| Analytics.CopyLink { projectId = project.id, projectName = project.name })

        UnshareMe ->
            updateStore_ XBStore.unshareMe project

        SetFolder maybeFolder ->
            updateStore_
                (XBStore.setFolderXBProject { oldFolderId = project.folderId })
                { project | folderId = Maybe.map .id maybeFolder }


updateXBStoreActionProjects : Config msg -> Flags -> StoreActionProjects -> List XBProject -> Model -> ( Model, Cmd msg )
updateXBStoreActionProjects config flags action projects model =
    let
        updateStore_ storeFn =
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store
                    (storeFn storeConfig projects flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)
    in
    case action of
        MoveToFolder maybeFolder ->
            updateStore_
                (XBStore.moveProjectsToFolder (Maybe.map .id maybeFolder))

        RemoveProjects ->
            updateStore_ XBStore.removeOrUnshareXBProjects


updateXBStoreActionFolder : Config msg -> Flags -> StoreActionFolder -> Model -> ( Model, Cmd msg )
updateXBStoreActionFolder config flags action model =
    case action of
        CreateFolder projects newName ->
            let
                folder : XBFolder
                folder =
                    -- The id is deliberately empty, because the API will return the correct values.
                    { id = XB2.Share.Data.Id.fromString ""
                    , name = newName
                    }
            in
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (XBStore.createXBFolder storeConfig projects folder flags)
                |> Glue.map config.msg

        RenameFolder folder ->
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (XBStore.renameXBFolder storeConfig folder flags)
                |> Glue.map config.msg

        DestroyFolder folder ->
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (XBStore.destroyXBFolderWithContent storeConfig folder flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)

        UngroupFolder folder ->
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (XBStore.destroyXBFolder storeConfig folder flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)


updateXBStoreActionUserSettings : Config msg -> Flags -> StoreActionUserSettings -> Model -> ( Model, Cmd msg )
updateXBStoreActionUserSettings config flags action model =
    let
        updateStore_ storeFn =
            model
                |> updateModal Modal.updateAfterStoreAction
                |> Cmd.pure
                |> Glue.updateWith store (storeFn storeConfig flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)
    in
    case action of
        FetchXBUserSettings ->
            updateStore_ XBStore.fetchXBUserSettings

        SetSharedProjectWarningDismissal shouldDismiss ->
            updateStore_ <|
                XBStore.setSharedProjectWarningDismissal shouldDismiss

        SetDoNotShowAgain doNotShowAgain ->
            updateStore_ <|
                XBStore.setDoNotShowAgain doNotShowAgain

        SetXB2FTUESeen ->
            updateStore_ XBStore.setXB2ListFTUESeen

        SetUserSettings userSettings ->
            updateStore_ <| XBStore.updateXBUserSettings userSettings


updateXbProjectCreated : Config msg -> XBProjectId -> Model -> ( Model, Cmd msg )
updateXbProjectCreated config id model =
    model
        |> Glue.Lazy.updateModelWith detail (Detail.markAsSaved { id = id })
        |> Cmd.withTrigger (config.forceNavigateTo <| Router.Project <| Just id)
        |> Glue.Lazy.trigger detail Detail.leaveConfirmCheckCmd


openModal : Config msg -> Modal -> Model -> ( Model, Cmd msg )
openModal config modal model =
    let
        shouldPassInitialState : Bool
        shouldPassInitialState =
            if Modal.isAttributeBrowserAffixing modal then
                False

            else
                model.shouldPassInitialStateToAttributeBrowser
    in
    { model
        | modal = Just modal
        , shouldPassInitialStateToAttributeBrowser = shouldPassInitialState
    }
        |> Glue.Lazy.updateModelWith detail Detail.onModalOpened
        |> Cmd.with (Modal.focus config.modalConfig modal)


handleAjaxError : Config msg -> Flags -> Maybe Url -> (err -> ErrorDisplay Never) -> Error err -> Model -> ( Model, Cmd msg )
handleAjaxError config flags maybeUrl customErrorDisplay =
    let
        handleAjaxErrorGeneric : (Error err -> Model -> ( Model, Cmd msg )) -> Error err -> Model -> ( Model, Cmd msg )
        handleAjaxErrorGeneric showErrorDialog err =
            XB2.Share.ErrorHandling.signOutOn401
                flags
                err
                (Maybe.unwrap "" Url.toString maybeUrl)
                (config.msg << LoadExternalUrl)
                (showErrorDialog err)

        openErrorModal : ErrorDisplay Never -> Model -> ( Model, Cmd msg )
        openErrorModal errorDisplay =
            let
                errorModal =
                    Modal.ErrorModal errorDisplay
            in
            openModal config errorModal
    in
    handleAjaxErrorGeneric
        (openErrorModal << XB2.Share.Error.getDisplay customErrorDisplay)


projectSharedAnalytics : Config msg -> Flags -> Router.Route -> XB2.Share.Store.Platform2.Store -> Model -> ( Model, Cmd msg )
projectSharedAnalytics config flags route p2Store model =
    let
        maybeProject =
            model.trackProjectSharing
                |> getProject model.xbStore
                |> Maybe.andThen XBData.getFullyLoadedProject

        questionCodes =
            maybeProject
                |> Maybe.unwrap [] XBData.getProjectQuestionCodes

        questions =
            questionCodes
                |> Maybe.traverse (\code -> XB2.Share.Store.Platform2.getQuestionMaybe code p2Store)
    in
    case ( questions, maybeProject ) of
        ( Just qs, Just project ) ->
            let
                analyticsCmd =
                    XBStore.fetchTaskXBProjectFullyLoaded (XBData.fullyLoadedToProject project) flags
                        |> Task.map
                            (\xbProject ->
                                let
                                    eventPlace =
                                        case route of
                                            Router.ProjectList ->
                                                Place.CrosstabBuilderList

                                            Router.Project _ ->
                                                Place.CrosstabBuilder

                                            Router.ExternalUrl _ ->
                                                Place.UnknownPlace
                                in
                                AnalyticsEvent
                                    eventPlace
                                    (ProjectShared
                                        { project = xbProject
                                        , store = p2Store
                                        , questions = qs
                                        }
                                    )
                            )
                        |> Task.attempt (Result.withDefault NoOp >> config.msg)
            in
            Cmd.pure { model | trackProjectSharing = Nothing }
                |> Cmd.add analyticsCmd

        _ ->
            Cmd.pure model


update :
    Config msg
    -> Zone
    -> Flags
    -> Maybe Url
    -> Router.Route
    -> XB2.Share.Store.Platform2.Store
    -> Msg
    -> Model
    -> ( Model, Cmd msg )
update config zone flags maybeUrl route p2Store msg model =
    (case msg of
        NoOp ->
            Cmd.pure model

        LoadExternalUrl url ->
            ( model, Browser.Navigation.load url )

        InitDetail posix ->
            Cmd.pure model
                |> Glue.Lazy.ensure detail (always <| Glue.map (config.msg << DetailMsg) <| Detail.init posix flags)

        DetailMsg dMsg ->
            Cmd.pure model
                |> Glue.Lazy.updateWith detail
                    (Detail.update config.detailConfig route flags model.xbStore p2Store dMsg)

        ListMsg lMsg ->
            Cmd.pure model
                |> Glue.Lazy.updateWith list
                    (XBList.update config.listConfig route flags zone model.xbStore p2Store lMsg)

        AnalyticsEvent place event ->
            Cmd.with (Analytics.trackEvent flags route place event) model

        ModalMsg mMsg ->
            model.modal
                |> Maybe.map
                    (Modal.update config.modalConfig route flags model.xbStore mMsg
                        >> Tuple.mapFirst (\newModal -> { model | modal = Just newModal })
                    )
                |> Maybe.withDefault (Cmd.pure model)

        AjaxError err ->
            handleAjaxError
                config
                flags
                maybeUrl
                never
                err
                model

        ProjectsAjaxError err ->
            let
                handleErr () =
                    handleAjaxError
                        config
                        flags
                        maybeUrl
                        XBData.xbProjectErrorDisplay
                        err
                        model
            in
            case err of
                XB2.Share.Gwi.Http.BadStatus { statusCode } _ ->
                    if statusCode == 404 then
                        model
                            |> Cmd.withTrigger (config.msg <| CreateListNotification P2Icons.info Nothing (Html.text "Project not found"))
                            |> Cmd.addTrigger (config.navigateTo Router.ProjectList)

                    else
                        handleErr ()

                _ ->
                    handleErr ()

        QueryAjaxError err ->
            handleAjaxError
                config
                flags
                maybeUrl
                AudienceIntersect.xbQueryErrorDisplay
                err
                model

        ExportError err ->
            handleAjaxError
                config
                flags
                maybeUrl
                XB2.Share.Export.exportErrorDisplay
                err
                model

        CrosstabBuilderStoreMsg xbMsg ->
            let
                addLineageRequests : Model -> ( Model, Cmd msg )
                addLineageRequests model_ =
                    model_
                        |> Cmd.withTrigger
                            (route
                                |> Router.getProjectId
                                |> getLineageRequestsForProject model_.xbStore
                                |> config.runStoreActions
                            )
            in
            ( model, Cmd.none )
                |> Glue.update store (XBStore.update storeConfig) xbMsg
                |> Glue.map config.msg
                |> (\( m, cmd ) -> updateXBStore config flags xbMsg route p2Store m |> Cmd.add cmd)
                |> Glue.updateWith Glue.id addLineageRequests

        UpdateXBProjectInStore project ->
            model
                |> Cmd.withTrigger
                    (XBData.fullyLoadedToProject project
                        |> XBStore.XBProjectFetched
                        |> CrosstabBuilderStoreMsg
                        |> config.msg
                    )

        SetXB2ListFTUESeen ->
            updateXBStoreActionUserSettings config flags SetXB2FTUESeen model

        OpenModal modal ->
            openModal config modal model

        OpenSharingModal project ->
            let
                ( modal, cmds ) =
                    Modal.initShareProject config.modalConfig flags project
            in
            openModal config modal model
                |> Cmd.add cmds

        CloseModal ->
            Cmd.pure (closeModal model)

        NavigateTo r ->
            Cmd.withTrigger (config.navigateTo r) model

        FetchSingleProject id ->
            Cmd.pure model
                |> Glue.updateWith store (XBStore.fetchXBProjectById storeConfig id flags)
                |> Glue.map config.msg
                |> Cmd.add (XBList.updateTime config.listConfig)

        XBStoreActionProject sMsg project ->
            updateXBStoreActionProject config flags route sMsg project model

        XBStoreActionProjects sMsg projects ->
            updateXBStoreActionProjects config flags sMsg projects model

        XBStoreActionFolder sMsg ->
            updateXBStoreActionFolder config flags sMsg model

        XBStoreActionUserSettings sMsg ->
            updateXBStoreActionUserSettings config flags sMsg model

        CreateXBProject ->
            model
                |> Cmd.withTrigger (config.navigateTo <| Router.Project Nothing)
                |> Cmd.add (Analytics.trackEvent flags route Place.CrosstabBuilderList ProjectCreationStarted)

        XBProjectCreated id ->
            updateXbProjectCreated config id model
                |> Glue.updateWith Glue.id (\m -> Cmd.pure { m | trackProjectSaving = Just ( id, NewlyCreated ) })

        DiscardChangesAndNavigateTo newRoute ->
            closeModal model
                |> Cmd.pure
                |> Glue.Lazy.updateWith detail
                    (Detail.clearWorkspace config.detailConfig
                        flags
                        p2Store
                        (RemoteData.toMaybe model.xbStore.userSettings)
                    )
                |> Cmd.addTrigger (config.navigateTo Router.ProjectList)
                |> Cmd.addTrigger (config.forceNavigateTo newRoute)

        GotAttributeBrowserStateSnapshot stateSnapshot ->
            let
                isNullSnapshot : Bool
                isNullSnapshot =
                    case
                        Decode.decodeValue (Decode.nullable Decode.value)
                            stateSnapshot
                    of
                        Ok Nothing ->
                            True

                        Ok (Just _) ->
                            False

                        Err _ ->
                            False
            in
            if isNullSnapshot then
                Cmd.pure
                    { model
                        | shouldPassInitialStateToAttributeBrowser = False
                    }

            else
                Cmd.pure
                    { model
                        | attributeBrowserInitialState = Encode.encode 0 stateSnapshot
                        , shouldPassInitialStateToAttributeBrowser = False
                    }

        SaveSharedProjectAsCopy { original, copy } ->
            closeModal model
                |> Cmd.with
                    (XBStore.fetchTaskXBProjectFullyLoaded original flags
                        |> Task.map
                            (\originalFull ->
                                config.msg <|
                                    XBStoreActionProject
                                        (CopyOfProject
                                            { original = originalFull
                                            , shouldRedirect = False
                                            }
                                        )
                                        copy
                            )
                        |> Task.attempt (Result.withDefault (NoOp |> config.msg))
                    )

        SaveProjectAndNavigateTo newRoute ->
            closeModal { model | forceNavigateToWhenProjectSaved = Just newRoute }
                |> Cmd.pure
                |> Glue.Lazy.updateWith detail
                    (\detailModel ->
                        case getProject model.xbStore <| Detail.getLastOpenedProjectId detailModel of
                            Just project ->
                                if XBData.isMine project.shared then
                                    detailModel
                                        |> Detail.saveEditedProject config.detailConfig flags project

                                else
                                    detailModel
                                        |> Cmd.withTrigger
                                            (config.msg <|
                                                OpenModal <|
                                                    Modal.initSetNameToProjectCopy
                                                        { original = project
                                                        , copy =
                                                            Detail.getCopyProjectFromCrosstab
                                                                flags
                                                                model.xbStore
                                                                project
                                                                detailModel
                                                        }
                                            )

                            Nothing ->
                                let
                                    name =
                                        NewName.timeBasedCrosstabName (XBStore.projectNameExists model.xbStore) zone detailModel.currentTime

                                    project =
                                        Detail.getNewProjectFromCrosstab flags name detailModel
                                in
                                detailModel
                                    |> Cmd.withTrigger (config.msg <| OpenModal <| Modal.initSetNameToNewProject project)
                    )

        SaveAsAudience saveAsItem caption expression ->
            let
                -- Done to avoid empty audience error msg when adding audience from XB2
                newExpression =
                    case expression of
                        FirstLevelLeaf data ->
                            FirstLevelNode Expression.Or <| NonemptyList.singleton <| Expression.Leaf data

                        expr ->
                            expr

                name =
                    Caption.getName caption

                ( id, detailModelUpdate ) =
                    case saveAsItem of
                        Modal.SaveAsAudienceItem aItem _ ->
                            ( AudienceItem.getId aItem
                            , Glue.Lazy.updateModelWith detail (Detail.savingAudience aItem)
                            )

                        Modal.SaveAsBaseAudience bItem ->
                            ( BaseAudience.getId bItem, identity )

                analyticsCmd =
                    Maybe.unwrap identity
                        (Cmd.add
                            << Detail.getAnalyticsCmd flags
                                route
                                AudienceSaved
                                { caption = caption
                                , expression = newExpression
                                , id = id
                                }
                                p2Store
                        )
                        model.detailModel
            in
            { model | modal = Maybe.map (Modal.setState Modal.Processing) model.modal }
                |> detailModelUpdate
                |> Cmd.withTrigger
                    (config.createAudienceWithExpression
                        { name = name
                        , expression = newExpression
                        }
                    )
                |> analyticsCmd

        DetailNotificationQueueMsg innerMsg ->
            let
                ( notificationQueue, cmd, maybeMsg ) =
                    NotificationQueue.update innerMsg model.detailNotificationQueue
            in
            ( { model | detailNotificationQueue = notificationQueue }
            , Cmd.map config.msg <|
                Cmd.batch
                    [ Cmd.map DetailNotificationQueueMsg cmd
                    , Cmd.maybe maybeMsg
                    ]
            )

        BrowserModalItemToggled item selectedItems ->
            let
                newSelectedItems : SelectedItems
                newSelectedItems =
                    selectedItems |> List.toggle item

                fetchLineages_ : msg
                fetchLineages_ =
                    newSelectedItems
                        |> List.fastConcatMap ModalBrowser.selectedItemNamespaceCodes
                        |> List.map XB2.Share.Store.Platform2.FetchLineage
                        |> config.runStoreActions

                fetchQuestions_ : msg
                fetchQuestions_ =
                    ModalBrowser.getSelectedItemQuestionCodes item
                        |> List.map (XB2.Share.Store.Platform2.FetchQuestion { showErrorModal = False })
                        |> config.runStoreActions
            in
            model
                |> Cmd.withTrigger fetchLineages_
                |> Cmd.addTrigger fetchQuestions_
                |> Cmd.addTriggerMaybe
                    (if List.isEmpty newSelectedItems then
                        Nothing

                     else
                        Just (config.msg <| CheckIncompatibilitiesAfterToggle newSelectedItems)
                    )

        CheckIncompatibilitiesAfterToggle selectedItems ->
            let
                selectedDatasetCodes : List Namespace.Code
                selectedDatasetCodes =
                    List.fastConcatMap ModalBrowser.selectedItemNamespaceCodes selectedItems

                arePossibleDatasetIncompatibilities : Bool
                arePossibleDatasetIncompatibilities =
                    ModalBrowser.arePossibleDatasetIncompatibilities
                        (Maybe.map Detail.currentCrosstab model.detailModel)
                        selectedDatasetCodes
            in
            case ( model.modal, arePossibleDatasetIncompatibilities ) of
                ( Just (Modal.AttributesModal attModalData), True ) ->
                    { model
                        | modal =
                            Modal.updateAttributesData
                                (\({ browserModel } as attModalData_) ->
                                    { attModalData_
                                        | browserModel =
                                            if List.isEmpty selectedDatasetCodes then
                                                browserModel

                                            else
                                                ModalBrowser.setModalBrowserWarning
                                                    ModalBrowser.PossibleIncompatibilities
                                                    browserModel
                                    }
                                )
                                (Modal.AttributesModal attModalData)
                                |> Just
                    }
                        |> Cmd.pure

                _ ->
                    Cmd.pure model

        CreateDetailNotification iconData action body ->
            let
                ( newQueue, cmd ) =
                    model.detailNotificationQueue
                        |> NotificationQueue.clearNonpersistent
                        |> NotificationQueue.enqueue (Notification.create action body iconData)
            in
            ( { model | detailNotificationQueue = newQueue }
            , Cmd.map (config.msg << DetailNotificationQueueMsg) cmd
            )

        CreateDetailPersistentNotification id notif ->
            let
                ( newQueue, cmd ) =
                    model.detailNotificationQueue
                        |> NotificationQueue.clearNonpersistent
                        |> NotificationQueue.enqueueWithId id notif
            in
            ( { model | detailNotificationQueue = newQueue }
            , Cmd.map (config.msg << DetailNotificationQueueMsg) cmd
            )

        CloseDetailNotification id ->
            ( { model | detailNotificationQueue = NotificationQueue.clearById id model.detailNotificationQueue }
            , Cmd.none
            )

        ListNotificationQueueMsg innerMsg ->
            let
                ( notificationQueue, cmd, maybeMsg ) =
                    NotificationQueue.update innerMsg model.listNotificationQueue
            in
            ( { model | listNotificationQueue = notificationQueue }
            , Cmd.map config.msg <|
                Cmd.batch
                    [ Cmd.map ListNotificationQueueMsg cmd
                    , Cmd.maybe maybeMsg
                    ]
            )

        CreateListNotification iconData maybeAction body ->
            let
                ( newQueue, cmd ) =
                    NotificationQueue.enqueue
                        (Notification.create maybeAction body iconData)
                        model.listNotificationQueue
            in
            ( { model | listNotificationQueue = newQueue }
            , Cmd.map (config.msg << ListNotificationQueueMsg) cmd
            )

        CreateListPersistentNotification id notif ->
            let
                ( newQueue, cmd ) =
                    model.listNotificationQueue
                        |> NotificationQueue.clearNonpersistent
                        |> NotificationQueue.enqueueWithId id notif
            in
            ( { model | listNotificationQueue = newQueue }
            , Cmd.map (config.msg << ListNotificationQueueMsg) cmd
            )

        CloseListNotification id ->
            ( { model | listNotificationQueue = NotificationQueue.clearById id model.listNotificationQueue }
            , Cmd.none
            )

        LimitReachedAddingBases currentSize { currentBasesCount, exceededBasesBy, totalLimit, maxBasesCount } ->
            let
                totalLimit_ =
                    String.fromInt totalLimit

                modal =
                    Modal.GenericAlert
                        { title = "Crosstab size limit exceeded"
                        , htmlContent =
                            Markdown.toHtml [] <|
                                String.join "\n\n"
                                    [ "You cannot exceed the "
                                        ++ totalLimit_
                                        ++ " cells limits between multiple bases tabs. Please lower the number of cells in your crosstab or remove "
                                        ++ String.fromInt exceededBasesBy
                                        ++ XB2.Share.Plural.fromInt exceededBasesBy " base"
                                        ++ "."
                                    , "Current size "
                                        ++ String.fromInt (currentSize * currentBasesCount)
                                        ++ "/"
                                        ++ totalLimit_
                                    , "Current bases "
                                        ++ String.fromInt currentBasesCount
                                        ++ "/"
                                        ++ String.fromInt maxBasesCount
                                    ]
                        , btnTitle = "Close"
                        }
            in
            openModal config modal model

        LimitReachedAddingRowOrColumn currentSize { exceedingSize, sizeLimit, currentBasesCount } ->
            let
                sizeLimit_ =
                    String.fromInt sizeLimit

                modal =
                    Modal.GenericAlert
                        { title = "Crosstab size limit exceeded"
                        , htmlContent =
                            Markdown.toHtml [] <|
                                String.join "\n\n"
                                    ([ "This change would lead to exceeding the maximum number of cells. Please remove row(s), column(s) or base(s) before adding more."
                                     , "Current size: " ++ String.fromInt currentSize ++ " / " ++ sizeLimit_ ++ " cells."
                                     , "New size: " ++ String.fromInt exceedingSize ++ " / " ++ sizeLimit_ ++ " cells."
                                     ]
                                        ++ (if currentBasesCount > 1 then
                                                [ "Please note: because of multiple bases selection the cells limit for the current crosstab is now reduced." ]

                                            else
                                                []
                                           )
                                    )
                        , btnTitle = "Close"
                        }
            in
            openModal config modal model
    )
        |> Glue.updateWith Glue.id (projectSharedAnalytics config flags route p2Store)
        |> Glue.updateWith Glue.id (projectSavedAnalytics config p2Store)



-- View


moduleClass : ClassName
moduleClass =
    WeakCss.namespace "xb2-app"


notificationClass : ClassName
notificationClass =
    WeakCss.add "notifications" moduleClass


view : Config msg -> Flags -> Zone -> Router.Route -> XB2.Share.Store.Platform2.Store -> Model -> Html msg
view config flags zone route p2Store model =
    let
        viewModal : () -> Html msg
        viewModal _ =
            Html.viewMaybe
                (Modal.view flags
                    config.modalConfig
                    model.xbStore
                    p2Store
                    model.attributeBrowserInitialState
                    model.shouldPassInitialStateToAttributeBrowser
                )
                model.modal

        {- We keep this because we need to show onboarding. This maybe should be in
           XB2.Modal module.
        -}
        viewAttrsBrowserModal : Modal -> Html msg
        viewAttrsBrowserModal attrBrowserModal =
            Html.div
                [ WeakCss.nest "attributes-browser-modal" moduleClass ]
                [ Modal.view
                    flags
                    config.modalConfig
                    model.xbStore
                    p2Store
                    model.attributeBrowserInitialState
                    model.shouldPassInitialStateToAttributeBrowser
                    attrBrowserModal
                ]
    in
    Html.div [ WeakCss.toClass moduleClass ] <|
        (case route of
            Router.ExternalUrl _ ->
                [ Html.text "You are about to leave soon." ]

            Router.ProjectList ->
                case model.listModel of
                    Nothing ->
                        [ Spinner.view ]

                    Just listModel ->
                        [ Html.div
                            [ WeakCss.nest "list-content-wrapper" moduleClass
                            , Events.on "scroll" (Decode.succeed <| config.msg <| ListMsg XBList.CloseDropdown)
                            ]
                            [ XBList.view
                                config.listConfig
                                flags
                                zone
                                model.xbStore
                                listModel
                            , NotificationQueue.view notificationClass model.listNotificationQueue
                                |> Html.map (config.msg << ListNotificationQueueMsg)
                            ]
                        , XBList.selectionPanelView
                            config.listConfig
                            flags
                            model.xbStore
                            listModel
                        ]

            Router.Project maybeId ->
                case model.detailModel of
                    Nothing ->
                        [ Spinner.view ]

                    Just detailModel ->
                        [ Detail.view
                            config.detailConfig
                            flags
                            (getProject model.xbStore maybeId)
                            model.xbStore
                            p2Store
                            model.modal
                            detailModel
                        , NotificationQueue.view notificationClass
                            model.detailNotificationQueue
                            |> Html.map (config.msg << DetailNotificationQueueMsg)
                        ]
        )
            ++ (case model.modal of
                    Just (Modal.AttributesModal attModalData) ->
                        [ viewAttrsBrowserModal
                            (Modal.AttributesModal attModalData)
                        ]

                    _ ->
                        [ viewModal () ]
               )
