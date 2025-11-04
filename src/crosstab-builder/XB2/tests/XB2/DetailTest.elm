module XB2.DetailTest exposing
    ( movingNonsortingAudienceToNonsortedAxisDoesNothing
    , movingNonsortingAudienceToSortedAxisDiscardsSort
    , movingSortAudienceToOtherAxisDiscardsSortOfOtherAxis
    , movingSortAudienceToOtherAxisKeepsSortOfOriginalAxis
    , movingSortAudienceToSameAxisDiscardsSortOfThatAxis
    , movingSortAudienceToSameAxisKeepsSortOfOtherAxis
    , movingSortedAudienceToOtherAxisDiscardsSortOfOtherAxis
    , movingSortedAudienceToOtherAxisKeepsSortOfOriginalAxis
    , movingSortedAudienceToSameAxisDiscardsSortOfThatAxis
    , movingSortedAudienceToSameAxisKeepsSortOfOtherAxis
    , onlyOneSortByOtherAxisActive
    , renamedItemReflectedInRememberedSortOrder
    , renamedItemsReflectedInRememberedSortOrder
    , sortAppliedAfterRenamingSortedItem
    , sortAppliedAfterRenamingSortedItems
    , sortAudienceInRememberedOrderAfterDeletingOther
    , sortAudienceNotInRememberedOrderAfterDeletingMultiple
    , sortAudienceNotInRememberedOrderAfterDeletingSingle
    , sortByNameDoesntResetSortByOtherAxis
    , sortNotAppliedAfterDeletingSortingItemAverage
    , sortNotAppliedAfterDeletingSortingItemMetric
    , sortRememberedOrderSwitchedAfterSwitchingRowsAndColumns
    , sortStillAppliedAfterDeletingItemOnSortedAxis
    , sortStillAppliedAfterDeletingItemsOnSortedAxis
    , sortStillAppliedAfterDeletingOtherItemOnNotSortedAxis
    , sortStillAppliedAfterDeletingOtherItemsOnNotSortedAxis
    , sortSwitchedAfterSwitchingRowsAndColumns
    , sortingTwiceAndResettingRestoresOriginalSortOrder
    , viewTest
    )

import Expect
import Fuzz exposing (Fuzzer)
import List.Extra as List
import Random
import Test exposing (..)
import Time
import XB2.Analytics as Analytics
import XB2.CrosstabCellLoader as CrosstabCellLoader
import XB2.Data exposing (AudienceDefinition(..))
import XB2.Data.Audience.Expression as Expression
import XB2.Data.AudienceCrosstab as AC
    exposing
        ( AudienceCrosstab
        , Direction(..)
        , OriginalOrder(..)
        )
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Metric exposing (Metric(..))
import XB2.Data.Namespace as Namespace
import XB2.Detail.Common as Common
import XB2.Modal.Browser exposing (SelectedItem(..), SelectedItems)
import XB2.Page.Detail exposing (EditMsg(..), Model, Msg(..), TableSelectMsg(..))
import XB2.Router exposing (Route(..))
import XB2.Share.Config exposing (Flags)
import XB2.Share.Data.Id
import XB2.Share.Data.Labels exposing (QuestionAveragesUnit(..))
import XB2.Share.Factory.Flags
import XB2.Share.Platform2.Grouping exposing (Grouping(..))
import XB2.Share.Store.Platform2
import XB2.Share.UndoRedo
import XB2.Sort as Sort exposing (Axis(..), AxisSort(..), Sort, SortDirection(..))
import XB2.Store as XBStore
import XB2.Views.AttributeBrowser as AttributeBrowser


mockTableHeaderCell : String -> Int -> ( AC.Key, Random.Seed )
mockTableHeaderCell title index =
    AudienceItem.fromSavedProject
        { id = title
        , name = title
        , fullName = title
        , subtitle = ""
        , definition = Expression Expression.sizeExpression
        }
        (Random.initialSeed index)
        |> Tuple.mapFirst
            (\item ->
                { item = item
                , isSelected = False
                }
            )


emptyAC =
    AC.empty (Time.millisToPosix 0)


viewTest : Test
viewTest =
    describe "XB2.Page.Detail.view"
        [ test "Export event contains only currently used audiences" <|
            \() ->
                let
                    crosstabForExport : AudienceCrosstab
                    crosstabForExport =
                        emptyAC 10 0
                            |> -- add two rows
                               AC.addAudiences
                                AC.addRows
                                [ always <| mockTableHeaderCell "row" 1
                                , always <| mockTableHeaderCell "extra" 2
                                ]
                            |> Result.withDefault ( emptyAC 10 0, [] )
                            |> Tuple.first
                            -- add a column
                            |> AC.addAudiences AC.addColumns [ always <| mockTableHeaderCell "column" 3 ]
                            |> Result.withDefault ( emptyAC 10 0, [] )
                            |> Tuple.first
                            -- remove extra row
                            |> AC.removeAudiences [ ( Row, Tuple.first <| mockTableHeaderCell "extra" 2 ) ]
                            |> Tuple.first

                    inputData =
                        { crosstabData =
                            XB2.Share.UndoRedo.init 5
                                { cellLoaderModel = CrosstabCellLoader.init crosstabForExport
                                , projectMetadata =
                                    XB2.Data.defaultMetadata
                                }
                        , heatmapMetric = Nothing
                        , unsaved = Common.Unsaved
                        }
                in
                case XB2.Page.Detail.exportEvent [] [] emptyP2Store inputData Nothing of
                    Analytics.Export { audiences } ->
                        audiences
                            |> Expect.equal
                                (List.map .item
                                    [ Tuple.first <| mockTableHeaderCell "row" 1
                                    , Tuple.first <| mockTableHeaderCell "column" 3
                                    ]
                                )

                    _ ->
                        Expect.fail "Expected CrosstabBuilderExport event"
        ]



-- For these tests, we only care about view, not about any Msgs and Cmds. So, dummy data


config : XB2.Page.Detail.Config ()
config =
    XB2.Page.Detail.configure
        { msg = \_ -> ()
        , ajaxError = \_ -> ()
        , exportAjaxError = \_ -> ()
        , queryAjaxError = \_ -> ()
        , navigateTo = \_ -> ()
        , limitReachedAddingRowOrColumn = \_ _ -> ()
        , limitReachedAddingBases = \_ _ -> ()
        , createXBProject = \_ -> ()
        , updateXBProject = \_ -> ()
        , setProjectToStore = \_ -> ()
        , saveCopyOfProject = \_ -> ()
        , openModal = \_ -> ()
        , openSharingModal = \_ -> ()
        , closeModal = ()
        , disabledExportsAlert = ()
        , createDetailNotification = \_ _ -> ()
        , createDetailPersistentNotification = \_ _ -> ()
        , closeDetailNotification = \_ -> ()
        , setSharedProjectWarningDismissal = \_ -> ()
        , setDoNotShowAgain = \_ -> ()
        , fetchManyP2 = \_ -> ()
        , updateUserSettings = \_ -> ()
        , shareAndCopyLink = \_ -> ()
        , setNewBasesOrder = \_ _ _ -> ()
        }


flags : Flags
flags =
    let
        f =
            XB2.Share.Factory.Flags.withFeature Nothing
    in
    { f | can = \_ -> True }


emptyXBStore : XBStore.Store
emptyXBStore =
    XBStore.init


emptyP2Store : XB2.Share.Store.Platform2.Store
emptyP2Store =
    XB2.Share.Store.Platform2.init


average : AttributeBrowser.Average
average =
    AttributeBrowser.AvgWithoutSuffixes
        { averagesUnit = AgreementScore
        , namespaceCode = Namespace.coreCode
        , questionCode = XB2.Share.Data.Id.fromString ""
        , questionLabel = "Average question"
        }


getSelectAttribute : String -> String -> SelectedItem
getSelectAttribute question datapoint =
    SelectedAttribute
        { codes =
            { datapointCode = XB2.Share.Data.Id.fromString datapoint
            , questionCode = XB2.Share.Data.Id.fromString question
            , suffixCode = Nothing
            }
        , namespaceCode = Namespace.coreCode
        , questionName = question
        , datapointName = datapoint
        , suffixName = Nothing
        , taxonomyPaths = Nothing
        , questionDescription = Nothing
        , order = 0
        , compatibilitiesMetadata = Nothing
        , isExcluded = False
        , metadata = Nothing
        }


itemsForAddition : SelectedItems
itemsForAddition =
    [ getSelectAttribute "Question" "Datapoint"
    , getSelectAttribute "Question" "Second dp"
    , getSelectAttribute "Question" "And third dp"
    ]


itemsFromAnotherQuestionForAddition : SelectedItems
itemsFromAnotherQuestionForAddition =
    [ getSelectAttribute "Another question" "None"
    , getSelectAttribute "Another question" "1"
    , getSelectAttribute "Another question" "2"
    , getSelectAttribute "Another question" "3"
    ]


topLevelModel : Model
topLevelModel =
    XB2.Page.Detail.init (Time.millisToPosix 0) flags
        |> Tuple.first


update : Msg -> Model -> Model
update msg model =
    -- If you change the store here, also change it in `topLevelModel`
    model
        |> XB2.Page.Detail.update
            config
            (Project Nothing)
            flags
            emptyXBStore
            emptyP2Store
            msg
        |> Tuple.first


fakeId : AudienceItemId
fakeId =
    AudienceItemId.generateFromString "blabla" (Random.initialSeed 0)
        |> Tuple.first


axisFuzzer : Fuzzer Axis
axisFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Rows
        , Fuzz.constant Columns
        ]


sortDirectionFuzzer : Fuzzer SortDirection
sortDirectionFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Ascending
        , Fuzz.constant Descending
        ]


sortByOtherAxisFuzzer : Fuzzer AxisSort
sortByOtherAxisFuzzer =
    Fuzz.oneOf
        [ Fuzz.map2 (\metric direction -> ByOtherAxisMetric fakeId metric direction)
            metricFuzzer
            sortDirectionFuzzer
        , Fuzz.map (\direction -> ByOtherAxisAverage fakeId direction)
            sortDirectionFuzzer
        ]


metricFuzzer : Fuzzer Metric
metricFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Size
        , Fuzz.constant Sample
        , Fuzz.constant Index
        , Fuzz.constant RowPercentage
        , Fuzz.constant ColumnPercentage
        ]


getSortingForModel : Model -> Sort
getSortingForModel m =
    m.crosstabData
        |> XB2.Share.UndoRedo.current
        |> .projectMetadata
        |> .sort


onlyOneSortByOtherAxisActive : Test
onlyOneSortByOtherAxisActive =
    fuzz3 axisFuzzer sortByOtherAxisFuzzer sortByOtherAxisFuzzer "Only one sort ByOtherAxis* can be active" <|
        \firstAxis firstSort otherSort ->
            let
                otherAxis =
                    Sort.otherAxis firstAxis

                modelAfterSorting : Model
                modelAfterSorting =
                    topLevelModel
                        |> update (Edit <| SortBy { axis = firstAxis, mode = firstSort })
                        |> update (Edit <| SortBy { axis = otherAxis, mode = otherSort })

                currentSort : Sort
                currentSort =
                    getSortingForModel modelAfterSorting
            in
            currentSort
                |> Expect.all
                    [ \sort ->
                        Sort.forAxis firstAxis sort
                            |> Expect.equal NoSort
                    , \sort ->
                        Sort.forAxis otherAxis sort
                            |> Expect.equal otherSort
                    ]


sortByNameDoesntResetSortByOtherAxis : Test
sortByNameDoesntResetSortByOtherAxis =
    test "Sort by name doesn't reset sort by other axis" <|
        \() ->
            let
                id : AudienceItemId
                id =
                    fakeId

                modelAfterSorting : Model
                modelAfterSorting =
                    topLevelModel
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisAverage id Ascending })

                currentSort : Sort
                currentSort =
                    getSortingForModel modelAfterSorting
            in
            currentSort
                |> Expect.all
                    [ \sort ->
                        sort.rows
                            |> Expect.equal (ByName Ascending)
                    , \sort ->
                        sort.columns
                            |> Expect.equal (ByOtherAxisAverage id Ascending)
                    ]


updateWithRemovingSelectedRowsCols : Model -> Model
updateWithRemovingSelectedRowsCols model =
    let
        getter what =
            case what of
                Row ->
                    AC.getSelectedRows

                Column ->
                    AC.getSelectedColumns

        getItems what =
            XB2.Page.Detail.currentCrosstab model
                |> getter what
                |> List.map (Tuple.pair what)

        clearlyNamedMsgVariableWithoutMagic =
            (getItems Row ++ getItems Column)
                |> RemoveSelectedAudiences True
                |> Edit
    in
    model
        |> update clearlyNamedMsgVariableWithoutMagic


sortAudienceInRememberedOrderAfterDeletingOther : Test
sortAudienceInRememberedOrderAfterDeletingOther =
    test "Sort audience in rememebered order after deleting other" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                orderAfterSorting : List String
                orderAfterSorting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterSorting
                        |> .rows
                        |> orderItemNames

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Row "Second dp" modelAfterSorting

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAudience ( Row, keyToDelete ))

                orderAfterDeleting : List String
                orderAfterDeleting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterDeleting
                        |> .rows
                        |> orderItemNames
            in
            { afterSorting = orderAfterSorting
            , afterDeleting = orderAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if List.member "Datapoint" afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Remembered rows after sorting should contain the item (it wasn't deleted yet)"
                    , \{ afterSorting } ->
                        if List.member "Second dp" afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Remembered rows after sorting should contain the item to be deleted (it wasn't deleted yet)"
                    , \{ afterDeleting } ->
                        if List.member "Datapoint" afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Remembered rows after sorting should still contain the item if it wasn't deleted"
                    , \{ afterDeleting } ->
                        if List.member "Second dp" afterDeleting then
                            Expect.fail "Remembered rows after sorting shouldn't contain the item if it was deleted"

                        else
                            Expect.pass
                    ]


sortAudienceNotInRememberedOrderAfterDeletingSingle : Test
sortAudienceNotInRememberedOrderAfterDeletingSingle =
    test "Sort audience not in rememebered order after deleting it" <|
        \() ->
            let
                itemToAdd =
                    itemsForAddition

                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemToAdd)

                nameToDelete : String
                nameToDelete =
                    "Datapoint"

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Row nameToDelete modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                orderAfterSorting : List String
                orderAfterSorting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterSorting
                        |> .rows
                        |> orderItemNames

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAudience ( Row, keyToDelete ))

                orderAfterDeleting : List String
                orderAfterDeleting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterDeleting
                        |> .rows
                        |> orderItemNames
            in
            { afterSorting = orderAfterSorting
            , afterDeleting = orderAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if List.member nameToDelete afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Remembered rows after sorting should contain the item to be deleted"
                    , \{ afterDeleting } ->
                        if List.member nameToDelete afterDeleting then
                            Expect.fail "Remembered rows after deleting shouldn't contain the deleted item"

                        else
                            Expect.pass
                    ]


sortAudienceNotInRememberedOrderAfterDeletingMultiple : Test
sortAudienceNotInRememberedOrderAfterDeletingMultiple =
    test "Sort audiences not in rememebered order after deleting them" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                orderAfterSorting : List String
                orderAfterSorting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterSorting
                        |> .rows
                        |> orderItemNames

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (SelectAction SelectAllRows)
                        |> updateWithRemovingSelectedRowsCols

                orderAfterDeleting : List String
                orderAfterDeleting =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterDeleting
                        |> .rows
                        |> orderItemNames
            in
            { afterSorting = orderAfterSorting
            , afterDeleting = orderAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if List.isEmpty afterSorting then
                            Expect.fail "Remembered rows after sorting should contain the item to be deleted"

                        else
                            Expect.pass
                    , \{ afterDeleting } ->
                        if List.isEmpty afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Remembered rows after deleting shouldn't contain the deleted item"
                    ]


sortStillAppliedAfterDeletingOtherItemsOnNotSortedAxis : Test
sortStillAppliedAfterDeletingOtherItemsOnNotSortedAxis =
    test "Sort still applied after deleting other items on not sorted axis" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Datapoint" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (SelectAction <| SelectRow { shiftPressed = False } Analytics.TickBox (findKey Row "Second dp" modelAfterSorting))
                        |> update (SelectAction <| SelectRow { shiftPressed = False } Analytics.TickBox (findKey Row "And third dp" modelAfterSorting))
                        |> updateWithRemovingSelectedRowsCols

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByMetric afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByMetric afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after deleting irrelevant rows."
                    ]


sortStillAppliedAfterDeletingOtherItemOnNotSortedAxis : Test
sortStillAppliedAfterDeletingOtherItemOnNotSortedAxis =
    test "Sort still applied after deleting other item on not sorted axis" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Row "Second dp" modelAfterAdding

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Datapoint" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAudience ( Row, keyToDelete ))

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByMetric afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByMetric afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after deleting irrelevant row."
                    ]


sortNotAppliedAfterDeletingSortingItemMetric : Test
sortNotAppliedAfterDeletingSortingItemMetric =
    test "Sort not applied after deleting sorting item (metric)" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Row "Datapoint" modelAfterAdding

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Datapoint" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAudience ( Row, keyToDelete ))

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByMetric afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByMetric afterDeleting then
                            Expect.fail "Should not have been sorting columns by a row after deleting the sorting row."

                        else
                            Expect.pass
                    ]


sortNotAppliedAfterDeletingSortingItemAverage : Test
sortNotAppliedAfterDeletingSortingItemAverage =
    test "Sort not applied after deleting sorting item (average)" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing [ SelectedAverage average ])

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Row "Average" modelAfterAdding

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Average" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisAverage sortingRowId Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAverageRowOrCol Row keyToDelete)

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByAverage afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByAverage afterDeleting then
                            Expect.fail "Should not have been sorting columns by a row after deleting the sorting row."

                        else
                            Expect.pass
                    ]


sortStillAppliedAfterDeletingItemsOnSortedAxis : Test
sortStillAppliedAfterDeletingItemsOnSortedAxis =
    test "Sort still applied after deleting items on sorted axis" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                        |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Datapoint" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (SelectAction <| SelectColumn { shiftPressed = False } Analytics.TickBox (findKey Column "Second dp" modelAfterSorting))
                        |> update (SelectAction <| SelectColumn { shiftPressed = False } Analytics.TickBox (findKey Column "And third dp" modelAfterSorting))
                        |> updateWithRemovingSelectedRowsCols

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByMetric afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByMetric afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Should have still been sorting columns by a row after deleting the sorted columns."
                    ]


sortStillAppliedAfterDeletingItemOnSortedAxis : Test
sortStillAppliedAfterDeletingItemOnSortedAxis =
    test "Sort still applied after deleting item on sorted axis" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                        |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

                keyToDelete : AC.Key
                keyToDelete =
                    findKey Column "Datapoint" modelAfterAdding

                sortingRowId : AudienceItemId
                sortingRowId =
                    findKeyId Row "Datapoint" modelAfterAdding

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

                sortAfterSorting : AxisSort
                sortAfterSorting =
                    modelAfterSorting
                        |> getSortingForModel
                        |> .columns

                modelAfterDeleting : Model
                modelAfterDeleting =
                    modelAfterSorting
                        |> update (Edit <| RemoveAudience ( Column, keyToDelete ))

                sortAfterDeleting : AxisSort
                sortAfterDeleting =
                    modelAfterDeleting
                        |> getSortingForModel
                        |> .columns
            in
            { afterSorting = sortAfterSorting
            , afterDeleting = sortAfterDeleting
            }
                |> Expect.all
                    [ \{ afterSorting } ->
                        if Sort.isSortingByMetric afterSorting then
                            Expect.pass

                        else
                            Expect.fail "Should have been sorting columns by a row after sorting."
                    , \{ afterDeleting } ->
                        if Sort.isSortingByMetric afterDeleting then
                            Expect.pass

                        else
                            Expect.fail "Should have still been sorting columns by a row after deleting the sorted column."
                    ]


renamedItemReflectedInRememberedSortOrder : Test
renamedItemReflectedInRememberedSortOrder =
    test "Renamed item reflected in remembered sort order" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                keyToRename : AC.Key
                keyToRename =
                    findKey Row "Datapoint" modelAfterAdding

                newCaption : Caption
                newCaption =
                    keyToRename.item
                        |> AudienceItem.getCaption
                        |> Caption.setName "ZZZ Renamed"

                newItem : AudienceItem
                newItem =
                    keyToRename.item
                        |> AudienceItem.setCaption newCaption

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                modelAfterRenaming : Model
                modelAfterRenaming =
                    modelAfterSorting
                        |> update
                            (Edit <|
                                SetGroupTitle Row
                                    { oldKey = keyToRename
                                    , newItem = newItem
                                    , expression = Nothing
                                    }
                            )

                orderAfterRenaming : List String
                orderAfterRenaming =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterRenaming
                        |> .rows
                        |> orderItemNames
            in
            orderAfterRenaming
                -- (Nothing) Datapoint, Second dp, And third dp
                --> sort by name ASC
                -- (Just)    Datapoint, Second dp, And third dp
                --> rename one
                -- (Just)    ZZZ Renamed, Second dp, And third dp
                |> Expect.equalLists [ "ZZZ Renamed", "Second dp", "And third dp" ]


orderItemNames : OriginalOrder -> List String
orderItemNames order =
    case order of
        NotSet ->
            [ "The order was NOTHING" ]

        OriginalOrder keys ->
            List.map (.item >> AudienceItem.getCaption >> Caption.getName) keys


renamedItemsReflectedInRememberedSortOrder : Test
renamedItemsReflectedInRememberedSortOrder =
    test "Renamed items reflected in remembered sort order" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                oldItem1 : AudienceItem
                oldItem1 =
                    findKeyItem Row "Datapoint" modelAfterAdding

                oldItem2 : AudienceItem
                oldItem2 =
                    findKeyItem Row "Second dp" modelAfterAdding

                newCaption1 : Caption
                newCaption1 =
                    oldItem1
                        |> AudienceItem.getCaption
                        |> Caption.setName "ZZZ Renamed 1"

                newCaption2 : Caption
                newCaption2 =
                    oldItem2
                        |> AudienceItem.getCaption
                        |> Caption.setName "Aaa Renamed 2"

                newItem1 : AudienceItem
                newItem1 =
                    oldItem1
                        |> AudienceItem.setCaption newCaption1

                newItem2 : AudienceItem
                newItem2 =
                    oldItem2
                        |> AudienceItem.setCaption newCaption2

                modelAfterSorting : Model
                modelAfterSorting =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                modelAfterRenaming : Model
                modelAfterRenaming =
                    modelAfterSorting
                        |> update
                            (Edit <|
                                SetGroupTitles
                                    ( { direction = Row
                                      , oldItem = oldItem1
                                      , newItem = newItem1
                                      , expression = Nothing
                                      }
                                    , [ { direction = Row
                                        , oldItem = oldItem2
                                        , newItem = newItem2
                                        , expression = Nothing
                                        }
                                      ]
                                    )
                            )

                orderAfterRenaming : List String
                orderAfterRenaming =
                    XB2.Page.Detail.currentOrderBeforeSorting modelAfterRenaming
                        |> .rows
                        |> orderItemNames
            in
            orderAfterRenaming
                -- (Nothing) Datapoint, Second dp, And third dp
                --> sort by name ASC
                -- (Just)    Datapoint, Second dp, And third dp
                --> rename multiple
                -- (Just)    ZZZ Renamed 1, Aaa Renamed 2, And third dp
                |> Expect.equalLists [ "ZZZ Renamed 1", "Aaa Renamed 2", "And third dp" ]


sortAppliedAfterRenamingSortedItem : Test
sortAppliedAfterRenamingSortedItem =
    test "Sort applied after renaming a sorted item" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                keyToRename : AC.Key
                keyToRename =
                    findKey Row "Datapoint" modelAfterAdding

                newCaption : Caption
                newCaption =
                    keyToRename.item
                        |> AudienceItem.getCaption
                        |> Caption.setName "Szzzz"

                newItem : AudienceItem
                newItem =
                    keyToRename.item
                        |> AudienceItem.setCaption newCaption

                modelAfterSortingAndRenaming : Model
                modelAfterSortingAndRenaming =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })
                        |> update
                            (Edit <|
                                SetGroupTitle Row
                                    { oldKey = keyToRename
                                    , newItem = newItem
                                    , expression = Nothing
                                    }
                            )

                crosstabOrderAfterSortingAndRenaming : List String
                crosstabOrderAfterSortingAndRenaming =
                    modelAfterSortingAndRenaming
                        |> XB2.Page.Detail.currentCrosstab
                        |> AC.getRows
                        |> List.map (.item >> AudienceItem.getCaption >> Caption.getName)
            in
            crosstabOrderAfterSortingAndRenaming
                |> Expect.equalLists (List.sort crosstabOrderAfterSortingAndRenaming)


sortAppliedAfterRenamingSortedItems : Test
sortAppliedAfterRenamingSortedItems =
    test "Sort applied after renaming multiple sorted items" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

                oldItem1 : AudienceItem
                oldItem1 =
                    findKeyItem Row "Datapoint" modelAfterAdding

                oldItem2 : AudienceItem
                oldItem2 =
                    findKeyItem Row "Second dp" modelAfterAdding

                newCaption1 : Caption
                newCaption1 =
                    oldItem1
                        |> AudienceItem.getCaption
                        |> Caption.setName "ZZZZ"

                newCaption2 : Caption
                newCaption2 =
                    oldItem2
                        |> AudienceItem.getCaption
                        |> Caption.setName "AAAA"

                newItem1 : AudienceItem
                newItem1 =
                    oldItem1
                        |> AudienceItem.setCaption newCaption1

                newItem2 : AudienceItem
                newItem2 =
                    oldItem2
                        |> AudienceItem.setCaption newCaption2

                modelAfterSortingAndRenaming : Model
                modelAfterSortingAndRenaming =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })
                        |> update
                            (Edit <|
                                SetGroupTitles
                                    ( { direction = Row
                                      , oldItem = oldItem1
                                      , newItem = newItem1
                                      , expression = Nothing
                                      }
                                    , [ { direction = Row
                                        , oldItem = oldItem2
                                        , newItem = newItem2
                                        , expression = Nothing
                                        }
                                      ]
                                    )
                            )

                crosstabOrderAfterSortingAndRenaming : List String
                crosstabOrderAfterSortingAndRenaming =
                    modelAfterSortingAndRenaming
                        |> XB2.Page.Detail.currentCrosstab
                        |> AC.getRows
                        |> List.map (.item >> AudienceItem.getCaption >> Caption.getName)
            in
            crosstabOrderAfterSortingAndRenaming
                |> Expect.equalLists (List.sort crosstabOrderAfterSortingAndRenaming)


sortingTwiceAndResettingRestoresOriginalSortOrder : Test
sortingTwiceAndResettingRestoresOriginalSortOrder =
    test "Sorting twice and resetting restores original sort order" <|
        \() ->
            let
                modelAfterAdding : Model
                modelAfterAdding =
                    topLevelModel
                        |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsFromAnotherQuestionForAddition)

                modelAfterSorting1 : Model
                modelAfterSorting1 =
                    modelAfterAdding
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Ascending })

                modelAfterSorting2 : Model
                modelAfterSorting2 =
                    modelAfterSorting1
                        |> update (Edit <| SortBy { axis = Rows, mode = ByName Descending })

                modelAfterResetting : Model
                modelAfterResetting =
                    modelAfterSorting2
                        |> update (Edit <| ResetSortForAxis Rows)

                crosstabOrderAfterAdding : List String
                crosstabOrderAfterAdding =
                    modelAfterAdding
                        |> XB2.Page.Detail.currentCrosstab
                        |> AC.getRows
                        |> List.map (.item >> AudienceItem.getCaption >> Caption.getName)

                crosstabOrderAfterResetting : List String
                crosstabOrderAfterResetting =
                    modelAfterResetting
                        |> XB2.Page.Detail.currentCrosstab
                        |> AC.getRows
                        |> List.map (.item >> AudienceItem.getCaption >> Caption.getName)
            in
            crosstabOrderAfterResetting
                |> Expect.equalLists crosstabOrderAfterAdding


type alias DataForSortAfterSwitchTests =
    { orderAfterSorting : { rows : OriginalOrder, columns : OriginalOrder }
    , orderAfterSwitching : { rows : OriginalOrder, columns : OriginalOrder }
    , sortAfterSorting : Sort
    , sortAfterSwitching : Sort
    }


dataForSortAfterSwitchTests : () -> DataForSortAfterSwitchTests
dataForSortAfterSwitchTests () =
    let
        itemToAdd =
            itemsForAddition

        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemToAdd)

        sortingRowId : AudienceItemId
        sortingRowId =
            findKeyId Row "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })
                |> update (Edit <| SortBy { axis = Rows, mode = ByName Descending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        orderAfterSorting : { rows : OriginalOrder, columns : OriginalOrder }
        orderAfterSorting =
            modelAfterSorting
                |> XB2.Page.Detail.currentOrderBeforeSorting

        modelAfterSwitching : Model
        modelAfterSwitching =
            modelAfterSorting
                |> update (Edit SwitchCrosstab)

        sortAfterSwitching : Sort
        sortAfterSwitching =
            modelAfterSwitching
                |> getSortingForModel

        orderAfterSwitching : { rows : OriginalOrder, columns : OriginalOrder }
        orderAfterSwitching =
            modelAfterSwitching
                |> XB2.Page.Detail.currentOrderBeforeSorting
    in
    { orderAfterSorting = orderAfterSorting
    , orderAfterSwitching = orderAfterSwitching
    , sortAfterSorting = sortAfterSorting
    , sortAfterSwitching = sortAfterSwitching
    }


sortRememberedOrderSwitchedAfterSwitchingRowsAndColumns : Test
sortRememberedOrderSwitchedAfterSwitchingRowsAndColumns =
    test "Sort remembered order switched after switching rows and columns" <|
        \() ->
            let
                { orderAfterSorting, orderAfterSwitching } =
                    dataForSortAfterSwitchTests ()
            in
            ( orderAfterSwitching.rows, orderAfterSwitching.columns )
                |> Expect.equal ( orderAfterSorting.columns, orderAfterSorting.rows )


sortSwitchedAfterSwitchingRowsAndColumns : Test
sortSwitchedAfterSwitchingRowsAndColumns =
    test "Sort switched after switching rows and columns" <|
        \() ->
            let
                { sortAfterSorting, sortAfterSwitching } =
                    dataForSortAfterSwitchTests ()
            in
            ( sortAfterSwitching.rows, sortAfterSwitching.columns )
                |> Expect.equal ( sortAfterSorting.columns, sortAfterSorting.rows )


keyName : AC.Key -> String
keyName key =
    key.item
        |> AudienceItem.getCaption
        |> Caption.getName


findKey : Direction -> String -> Model -> AC.Key
findKey direction name model =
    case
        model
            |> XB2.Page.Detail.currentCrosstab
            |> (case direction of
                    Row ->
                        AC.getRows

                    Column ->
                        AC.getColumns
               )
            |> List.find (\key -> keyName key == name)
    of
        Nothing ->
            Debug.todo "Didn't find a key"

        Just key ->
            key


findKeyItem : Direction -> String -> Model -> AudienceItem
findKeyItem direction name model =
    findKey direction name model
        |> .item


findKeyId : Direction -> String -> Model -> AudienceItemId
findKeyId direction name model =
    findKeyItem direction name model
        |> AudienceItem.getId


type alias DataForSortAndMoveTests =
    { sortAfterSorting : Sort
    , sortAfterMoving : Sort
    }


dataForMoveSortRowToRowTests : () -> DataForSortAndMoveTests
dataForMoveSortRowToRowTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

        sortingRowId : AudienceItemId
        sortingRowId =
            findKeyId Row "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Rows, mode = ByName Descending })
                |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Row
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Datapoint" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


dataForMoveSortRowToColumnTests : () -> DataForSortAndMoveTests
dataForMoveSortRowToColumnTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)

        sortingRowId : AudienceItemId
        sortingRowId =
            findKeyId Row "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Rows, mode = ByName Descending })
                |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Column
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Datapoint" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


dataForMoveSortedRowToRowTests : () -> DataForSortAndMoveTests
dataForMoveSortedRowToRowTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

        sortingColumnId : AudienceItemId
        sortingColumnId =
            findKeyId Column "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Rows, mode = ByOtherAxisMetric sortingColumnId Index Ascending })
                |> update (Edit <| SortBy { axis = Columns, mode = ByName Descending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Row
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Datapoint" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


dataForMoveSortedRowToColumnTests : () -> DataForSortAndMoveTests
dataForMoveSortedRowToColumnTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

        sortingColumnId : AudienceItemId
        sortingColumnId =
            findKeyId Column "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Rows, mode = ByOtherAxisMetric sortingColumnId Index Ascending })
                |> update (Edit <| SortBy { axis = Columns, mode = ByName Descending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Column
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Datapoint" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


dataForMoveNonsortingRowToSortedColumnTests : () -> DataForSortAndMoveTests
dataForMoveNonsortingRowToSortedColumnTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

        sortingRowId : AudienceItemId
        sortingRowId =
            findKeyId Row "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Column
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Second dp" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


dataForMoveNonsortingRowToNonsortedRowTests : () -> DataForSortAndMoveTests
dataForMoveNonsortingRowToNonsortedRowTests () =
    let
        modelAfterAdding : Model
        modelAfterAdding =
            topLevelModel
                |> update (Edit <| AddFromAttributeBrowser Row Split Nothing itemsForAddition)
                |> update (Edit <| AddFromAttributeBrowser Column Split Nothing itemsForAddition)

        sortingRowId : AudienceItemId
        sortingRowId =
            findKeyId Row "Datapoint" modelAfterAdding

        modelAfterSorting : Model
        modelAfterSorting =
            modelAfterAdding
                |> update (Edit <| SortBy { axis = Columns, mode = ByOtherAxisMetric sortingRowId Index Ascending })

        sortAfterSorting : Sort
        sortAfterSorting =
            modelAfterSorting
                |> getSortingForModel

        modelAfterMoving : Model
        modelAfterMoving =
            modelAfterSorting
                |> update
                    (Edit <|
                        Move
                            { to = Row
                            , at = 4 -- basically at the end - the Crosstab action clamps so being off by one is fine.
                            , items = ( ( Row, findKey Row "Second dp" modelAfterSorting ), [] )
                            }
                    )

        sortAfterMoving : Sort
        sortAfterMoving =
            modelAfterMoving
                |> getSortingForModel
    in
    { sortAfterSorting = sortAfterSorting
    , sortAfterMoving = sortAfterMoving
    }


movingSortAudienceToSameAxisKeepsSortOfOtherAxis : Test
movingSortAudienceToSameAxisKeepsSortOfOtherAxis =
    test "Moving sort audience to same axis keeps sort of other axis" <|
        \() ->
            let
                { sortAfterSorting, sortAfterMoving } =
                    dataForMoveSortRowToRowTests ()
            in
            sortAfterMoving.columns
                |> Expect.equal sortAfterSorting.columns


movingSortAudienceToSameAxisDiscardsSortOfThatAxis : Test
movingSortAudienceToSameAxisDiscardsSortOfThatAxis =
    test "Moving sort audience to same axis discards sort of that axis" <|
        \() ->
            let
                { sortAfterMoving } =
                    dataForMoveSortRowToRowTests ()
            in
            sortAfterMoving.rows
                |> Expect.equal NoSort


movingSortAudienceToOtherAxisDiscardsSortOfOtherAxis : Test
movingSortAudienceToOtherAxisDiscardsSortOfOtherAxis =
    test "Moving sort audience to other axis discards sort of other axis" <|
        \() ->
            let
                { sortAfterMoving } =
                    dataForMoveSortRowToColumnTests ()
            in
            sortAfterMoving.columns
                |> Expect.equal NoSort


movingSortAudienceToOtherAxisKeepsSortOfOriginalAxis : Test
movingSortAudienceToOtherAxisKeepsSortOfOriginalAxis =
    test "Moving sort audience to other axis keeps sort of original axis" <|
        \() ->
            let
                { sortAfterSorting, sortAfterMoving } =
                    dataForMoveSortRowToColumnTests ()
            in
            sortAfterMoving.rows
                |> Expect.equal sortAfterSorting.rows


movingSortedAudienceToSameAxisKeepsSortOfOtherAxis : Test
movingSortedAudienceToSameAxisKeepsSortOfOtherAxis =
    test "Moving sorted audience to same axis keeps sort of other axis" <|
        \() ->
            let
                { sortAfterSorting, sortAfterMoving } =
                    dataForMoveSortedRowToRowTests ()
            in
            sortAfterMoving.columns
                |> Expect.equal sortAfterSorting.columns


movingSortedAudienceToSameAxisDiscardsSortOfThatAxis : Test
movingSortedAudienceToSameAxisDiscardsSortOfThatAxis =
    test "Moving sorted audience to same axis discards sort of that axis" <|
        \() ->
            let
                { sortAfterMoving } =
                    dataForMoveSortedRowToRowTests ()
            in
            sortAfterMoving.rows
                |> Expect.equal NoSort


movingSortedAudienceToOtherAxisDiscardsSortOfOtherAxis : Test
movingSortedAudienceToOtherAxisDiscardsSortOfOtherAxis =
    test "Moving sorted audience to other axis discards sort of other axis" <|
        \() ->
            let
                { sortAfterMoving } =
                    dataForMoveSortedRowToColumnTests ()
            in
            sortAfterMoving.columns
                |> Expect.equal NoSort


movingSortedAudienceToOtherAxisKeepsSortOfOriginalAxis : Test
movingSortedAudienceToOtherAxisKeepsSortOfOriginalAxis =
    test "Moving sorted audience to other axis keeps sort of original axis" <|
        \() ->
            let
                { sortAfterSorting, sortAfterMoving } =
                    dataForMoveSortedRowToColumnTests ()
            in
            sortAfterMoving.rows
                |> Expect.equal sortAfterSorting.rows


movingNonsortingAudienceToSortedAxisDiscardsSort : Test
movingNonsortingAudienceToSortedAxisDiscardsSort =
    test "Moving non-sorting audience to sorted axis discards sort" <|
        \() ->
            let
                { sortAfterMoving } =
                    dataForMoveNonsortingRowToSortedColumnTests ()
            in
            sortAfterMoving.columns
                |> Expect.equal NoSort


movingNonsortingAudienceToNonsortedAxisDoesNothing : Test
movingNonsortingAudienceToNonsortedAxisDoesNothing =
    test "Moving non-sorting audience to non-sorted axis does nothing" <|
        \() ->
            let
                { sortAfterSorting, sortAfterMoving } =
                    dataForMoveNonsortingRowToNonsortedRowTests ()
            in
            sortAfterMoving.rows
                |> Expect.equal sortAfterSorting.rows
