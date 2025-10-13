module XB2.AudienceCrosstabTest exposing (allTests)

import Dict.Any
import Expect
import List.Extra as List
import List.NonEmpty as NonEmpty
import Maybe.Extra as Maybe
import Random
import Set.Any
import Test exposing (..)
import Time
import XB2.Data
    exposing
        ( AudienceData
        , AudienceDefinition(..)
        , BaseAudienceData
        , XBProjectFullyLoaded
        )
import XB2.Data.Audience.Expression as Expression
import XB2.Data.AudienceCrosstab as AC
    exposing
        ( AffixGroupItem
        , AudienceCrosstab
        , Command(..)
        , Direction(..)
        , Key
        , RequestParams(..)
        )
import XB2.Data.AudienceItem as AudienceItem
import XB2.Data.AudienceItemId as AudienceItemId
import XB2.Data.Average as Average
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Caption as Caption
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Zod.Optional as Optional
import XB2.RemoteData.Tracked as Tracked
import XB2.Share.Data.Id
import XB2.Share.Factory.Question
import XB2.Share.Factory.Wave


key : Int -> Key
key n =
    AudienceItem.fromSavedProject
        { id = AudienceItemId.totalString
        , name = "Totals"
        , fullName = "Totals"
        , subtitle = ""
        , definition = Expression Expression.sizeExpression
        }
        (Random.initialSeed n)
        |> Tuple.first
        |> (\item ->
                { item = item
                , isSelected = False
                }
           )


loadingBoundaries : Int
loadingBoundaries =
    0


allCellsVisible : AC.VisibleCells
allCellsVisible =
    { topLeftRow = 0
    , topLeftCol = 0
    , bottomRightRow = 1000
    , bottomRightCol = 1000
    , frozenCols = 0
    , frozenRows = 0
    }


initCellDataWithLoading : Maybe Tracked.TrackerId -> Maybe Tracked.TrackerId -> AC.CellData
initCellDataWithLoading tIdForData tIdForIncompatibilities =
    AC.initCell (Tracked.Loading tIdForData) (Tracked.Loading tIdForIncompatibilities) |> .data


initCellDataWithLoadingForTotalVsTotal : Maybe Tracked.TrackerId -> AC.CellData
initCellDataWithLoadingForTotalVsTotal tId =
    AC.initCell (Tracked.Loading tId) Tracked.NotAsked |> .data


commandToComoparable : Command -> String
commandToComoparable cmd =
    case cmd of
        CancelHttpRequest id ->
            "CancelHttpRequest--" ++ id

        MakeHttpRequest id _ _ _ _ ->
            "MakeHttpRequest--" ++ id


allTests : Test
allTests =
    describe "AudienceCrosstab"
        [ describe "empty"
            [ test "should have size without totals == 0" <| \() -> AC.getSizeWithoutTotals (emptyAc 10 loadingBoundaries) |> Expect.equal 0
            , test "should have size with totals == 1" <| \() -> AC.getSizeWithTotals (emptyAc 10 loadingBoundaries) |> Expect.equal 1
            , test "should be empty" <| \() -> AC.isEmpty (emptyAc 10 loadingBoundaries) |> Expect.equal True |> Expect.onFail "should be empty"
            , test "should have empty list of rows" <| \() -> AC.getRows (emptyAc 10 loadingBoundaries) |> Expect.equal []
            , test "should have empty list of columns" <| \() -> AC.getColumns (emptyAc 10 loadingBoundaries) |> Expect.equal []
            , test "should have 0 rows" <| \() -> AC.rowCountWithoutTotals (emptyAc 10 loadingBoundaries) |> Expect.equal 0
            , test "should have 0 columns" <| \() -> AC.colCountWithoutTotals (emptyAc 10 loadingBoundaries) |> Expect.equal 0
            , test "should not be fully loaded" <| \() -> AC.isFullyLoaded (emptyAc 10 loadingBoundaries) |> Expect.equal False |> Expect.onFail "should not be fully loaded"
            ]
        , describe "crosstab with one row"
            [ test "should have size without totals == 0" <| \() -> AC.getSizeWithoutTotals crosstabWithOneRow |> Expect.equal 0
            , test "should have size with totals == 2" <| \() -> AC.getSizeWithTotals crosstabWithOneRow |> Expect.equal 2
            , test "should not be  empty" <| \() -> AC.isEmpty crosstabWithOneRow |> Expect.equal False |> Expect.onFail "should not be empty"
            , test "should have one element list of rows" <| \() -> AC.getRows crosstabWithOneRow |> Expect.equal [ row1Key ]
            , test "should have empty list of columns" <| \() -> AC.getColumns crosstabWithOneRow |> Expect.equal []
            , test "should have 1 row" <| \() -> AC.rowCountWithoutTotals crosstabWithOneRow |> Expect.equal 1
            , test "should have 0 columns" <| \() -> AC.colCountWithoutTotals crosstabWithOneRow |> Expect.equal 0
            , test "should not be fully loaded" <| \() -> AC.isFullyLoaded crosstabWithOneRow |> Expect.equal False |> Expect.onFail "should not be fully loaded"
            ]
        , describe "crosstab with one column"
            [ test "should have size without totals == 0" <| \() -> AC.getSizeWithoutTotals crosstabWithOneColumn |> Expect.equal 0
            , test "should have size with totals == 2" <| \() -> AC.getSizeWithTotals crosstabWithOneColumn |> Expect.equal 2
            , test "should not be  empty" <| \() -> AC.isEmpty crosstabWithOneColumn |> Expect.equal False |> Expect.onFail "should not be empty"
            , test "should have empty list of rows" <| \() -> AC.getRows crosstabWithOneColumn |> Expect.equal []
            , test "should have one element list of columns" <| \() -> AC.getColumns crosstabWithOneColumn |> Expect.equal [ Tuple.first <| col1 seed1 ]
            , test "should have 0 row" <| \() -> AC.rowCountWithoutTotals crosstabWithOneColumn |> Expect.equal 0
            , test "should have 1 columns" <| \() -> AC.colCountWithoutTotals crosstabWithOneColumn |> Expect.equal 1
            , test "should not be fully loaded" <| \() -> AC.isFullyLoaded crosstabWithOneColumn |> Expect.equal False |> Expect.onFail "should not be fully loaded"
            ]
        , describe "crosstab with one row and column"
            [ test "should have size without totals == 1" <| \() -> AC.getSizeWithoutTotals crosstabWithOneRowAndOneColumn |> Expect.equal 1
            , test "should have size with totals == 4" <| \() -> AC.getSizeWithTotals crosstabWithOneRowAndOneColumn |> Expect.equal 4
            , test "should not be  empty" <| \() -> AC.isEmpty crosstabWithOneRowAndOneColumn |> Expect.equal False |> Expect.onFail "should not be empty"
            , test "should have one element list of rows" <| \() -> AC.getRows crosstabWithOneRowAndOneColumn |> Expect.equal [ row1Key ]
            , test "should have one element list of columns" <| \() -> AC.getColumns crosstabWithOneRowAndOneColumn |> Expect.equal [ col1Key ]
            , test "should have 1 row" <| \() -> AC.rowCountWithoutTotals crosstabWithOneRowAndOneColumn |> Expect.equal 1
            , test "should have 1 columns" <| \() -> AC.colCountWithoutTotals crosstabWithOneRowAndOneColumn |> Expect.equal 1
            , test "should not be fully loaded" <| \() -> AC.isFullyLoaded crosstabWithOneRowAndOneColumn |> Expect.equal False |> Expect.onFail "should not be fully loaded"
            , test "should have one loading crosstab cell" <|
                \() ->
                    AC.getCrosstab crosstabWithOneRowAndOneColumn
                        |> Crosstab.value
                            { row = row1Key
                            , col = col1Key
                            , base = BaseAudience.default
                            }
                        |> Maybe.map .data
                        |> Expect.equal
                            (Just
                                (initCellDataWithLoading
                                    (Just
                                        (AC.generateBulkTrackerId
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                            BaseAudience.default
                                            (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                        )
                                    )
                                    (Just
                                        (AC.generateBulkTrackerId
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                            BaseAudience.default
                                            (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                            ++ "--incompatibilities"
                                        )
                                    )
                                )
                            )
            , test "should have three loading totals cells" <|
                \() ->
                    AC.getTotals crosstabWithOneRowAndOneColumn
                        |> Dict.Any.values
                        |> List.map .data
                        |> Expect.equal
                            [ initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoadingForTotalVsTotal
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                    )
                                )
                            ]
            , test "should have NotAsked cells without waves and locations except totalVsTotal incompatibilities" <|
                \() ->
                    let
                        notAskedCell =
                            AC.initCell Tracked.NotAsked Tracked.NotAsked |> .data
                    in
                    emptyAc_ 10 loadingBoundaries
                        |> AC.setCellsVisibility True allCellsVisible
                        |> addToMockCrosstab AC.addRows row1
                        |> addToMockCrosstab AC.addColumns col1
                        |> AC.getTotals
                        |> Dict.Any.values
                        |> List.map .data
                        |> Expect.equal
                            [ notAskedCell
                            , notAskedCell
                            , notAskedCell
                            ]
            ]
        , describe "crosstab loaded from project (1 row, 1 col)"
            [ test "should have size without totals == 1" <| \() -> AC.getSizeWithoutTotals crosstabLoadedFromProject |> Expect.equal 1
            , test "should have size with totals == 4" <| \() -> AC.getSizeWithTotals crosstabLoadedFromProject |> Expect.equal 4
            , test "should not be  empty" <| \() -> AC.isEmpty crosstabLoadedFromProject |> Expect.equal False |> Expect.onFail "should not be empty"
            , test "should have one element list of rows" <|
                \() ->
                    AC.getRows crosstabLoadedFromProject
                        |> List.map (AudienceItem.getIdString << .item)
                        |> Expect.equal [ row1IdString ]
            , test "should have one element list of columns" <|
                \() ->
                    AC.getColumns crosstabLoadedFromProject
                        |> List.map (AudienceItem.getIdString << .item)
                        |> Expect.equal [ col1IdString ]
            , test "should have 1 row" <| \() -> AC.rowCountWithoutTotals crosstabLoadedFromProject |> Expect.equal 1
            , test "should have 1 columns" <| \() -> AC.colCountWithoutTotals crosstabLoadedFromProject |> Expect.equal 1
            , test "should not be fully loaded" <| \() -> AC.isFullyLoaded crosstabLoadedFromProject |> Expect.equal False |> Expect.onFail "should not be fully loaded"
            , test "should have one loading crosstab cell" <|
                \() ->
                    AC.getCrosstab crosstabLoadedFromProject
                        |> Crosstab.value
                            { row = row1Key
                            , col = col1Key
                            , base = projectBaseAudience
                            }
                        |> Maybe.map .data
                        |> Expect.equal
                            (Just
                                (initCellDataWithLoading
                                    (Just
                                        (AC.generateBulkTrackerId
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                            projectBaseAudience
                                            (AC.getVisibleCells crosstabLoadedFromProject)
                                        )
                                    )
                                    (Just
                                        (AC.generateBulkTrackerId
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                            (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                            projectBaseAudience
                                            (AC.getVisibleCells crosstabLoadedFromProject)
                                            ++ "--incompatibilities"
                                        )
                                    )
                                )
                            )
            , test "should have three loading totals cells" <|
                \() ->
                    AC.getTotals crosstabLoadedFromProject
                        |> Dict.Any.values
                        |> List.map .data
                        |> Expect.equal
                            [ initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabLoadedFromProject)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabLoadedFromProject)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabLoadedFromProject)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabLoadedFromProject)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoadingForTotalVsTotal
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "w1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "loc1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabLoadedFromProject)
                                    )
                                )
                            ]
            ]
        , describe "commands generated when initializing crosstab project (1 row, 1 col)"
            [ test "there should be four request commands" <|
                \() ->
                    commandsWhenLoadingCrosstabFromProject
                        |> Expect.equal
                            [ MakeHttpRequest
                                (AC.generateBulkTrackerId
                                    (XB2.Share.Data.Id.setFromList [ waveMock.code ])
                                    (XB2.Share.Data.Id.setFromList [ XB2.Share.Data.Id.fromString "loc1" ])
                                    projectBaseAudience
                                    (AC.getVisibleCells crosstabLoadedFromProject)
                                )
                                (XB2.Share.Data.Id.setFromList [ waveMock.code ])
                                (XB2.Share.Data.Id.setFromList [ XB2.Share.Data.Id.fromString "loc1" ])
                                projectBaseAudience
                                (CrosstabBulkAvARequest
                                    { rows = [ projectRow1FromSavedProject ]
                                    , rowExprs = [ Expression.AllRespondents ]
                                    , cols = [ projectColumn1FromSavedProject ]
                                    , colExprs = [ Expression.AllRespondents ]
                                    }
                                )
                            , MakeHttpRequest
                                (AC.generateBulkTrackerId
                                    (XB2.Share.Data.Id.setFromList [ waveMock.code ])
                                    (XB2.Share.Data.Id.setFromList [ XB2.Share.Data.Id.fromString "loc1" ])
                                    projectBaseAudience
                                    (AC.getVisibleCells crosstabLoadedFromProject)
                                    ++ "--incompatibilities"
                                )
                                (XB2.Share.Data.Id.setFromList [ waveMock.code ])
                                (XB2.Share.Data.Id.setFromList [ XB2.Share.Data.Id.fromString "loc1" ])
                                projectBaseAudience
                                (IncompatibilityBulkRequest
                                    { rows = [ projectRow1FromSavedProject ]
                                    , rowExprs = [ Expression.AllRespondents ]
                                    , cols = [ projectColumn1FromSavedProject ]
                                    , colExprs = [ Expression.AllRespondents ]
                                    }
                                )
                            ]
            ]
        , describe "removeAudiences"
            [ describe "1 row removed"
                [ test "should cancel requests in row" <|
                    \() ->
                        Tuple.second crosstabWithRowRemoved
                            |> List.sortBy commandToComoparable
                            |> Expect.equal
                                ([ CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowRemoved)
                                        ++ "--incompatibilities"
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowRemoved)
                                        ++ "--incompatibilities"
                                    )

                                 {- TODO: This repeats twice due to the totals and table
                                    cells being on separate fields and adding the same
                                    optional command into the commands list for the
                                    requests...
                                 -}
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowRemoved)
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowRemoved)
                                    )
                                 ]
                                    |> List.sortBy commandToComoparable
                                )
                ]
            , describe "1 column removed"
                [ test "should cancel requests in column when removing column" <|
                    \() ->
                        Tuple.second crosstabWithColumnRemoved
                            |> List.sortBy commandToComoparable
                            |> Expect.equal
                                ([ CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithColumnRemoved)
                                        ++ "--incompatibilities"
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithColumnRemoved)
                                        ++ "--incompatibilities"
                                    )

                                 {- TODO: This repeats twice due to the totals and table
                                    cells being on separate fields and adding the same
                                    optional command into the commands list for the
                                    requests...
                                 -}
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithColumnRemoved)
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithColumnRemoved)
                                    )
                                 ]
                                    |> List.sortBy commandToComoparable
                                )
                ]
            , describe "1 column and 1 row removed"
                [ test "should cancel requests in row AND column when removing row AND column" <|
                    \() ->
                        Tuple.second crosstabWithRowAndColumnRemoved
                            |> List.sortBy commandToComoparable
                            |> Expect.equal
                                ([ CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                        ++ "--incompatibilities"
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                        ++ "--incompatibilities"
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                        ++ "--incompatibilities"
                                    )

                                 {- TODO: This repeats twice due to the totals and table
                                    cells being on separate fields and adding the same
                                    optional command into the commands list for the
                                    requests...
                                 -}
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                    )
                                 , CancelHttpRequest
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells <| Tuple.first crosstabWithRowAndColumnRemoved)
                                    )
                                 ]
                                    |> List.sortBy commandToComoparable
                                )
                , test "should have size without totals == 0" <| \() -> AC.getSizeWithoutTotals (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal 0
                , test "should have size with totals == 1" <| \() -> AC.getSizeWithTotals (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal 1
                , test "should be empty" <| \() -> AC.isEmpty (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal True |> Expect.onFail "should be empty"
                , test "should have empty list of rows" <| \() -> AC.getRows (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal []
                , test "should have empty list of columns" <| \() -> AC.getColumns (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal []
                , test "should have 0 rows" <| \() -> AC.rowCountWithoutTotals (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal 0
                , test "should have 0 columns" <| \() -> AC.colCountWithoutTotals (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal 0
                , test "should not be fully loaded" <| \() -> AC.isFullyLoaded (Tuple.first crosstabWithRowAndColumnRemoved) |> Expect.equal False |> Expect.onFail "should not be fully loaded"
                ]
            ]
        , describe "add items without index but waiting for it"
            [ test "should have size without totals == 1" <|
                \() ->
                    AC.getSizeWithoutTotals crosstabWithOneRowAndOneColumn
                        |> Expect.equal 1
            , test "should have size with totals == 4" <|
                \() ->
                    AC.getSizeWithTotals crosstabWithOneRowAndOneColumn
                        |> Expect.equal 4
            , test "should not be  empty" <|
                \() ->
                    AC.isEmpty crosstabWithOneRowAndOneColumn
                        |> Expect.equal False
                        |> Expect.onFail "should not be empty"
            , test "should have one element list of rows" <|
                \() ->
                    AC.getRows crosstabWithOneRowAndOneColumn
                        |> List.map (AudienceItem.getIdString << .item)
                        |> Expect.equal [ row1IdString ]
            , test "should have one element list of columns" <|
                \() ->
                    AC.getColumns crosstabWithOneRowAndOneColumn
                        |> List.map (AudienceItem.getIdString << .item)
                        |> Expect.equal [ col1IdString ]
            , test "should have 1 row" <|
                \() ->
                    AC.rowCountWithoutTotals crosstabWithOneRowAndOneColumn
                        |> Expect.equal 1
            , test "should have 1 columns" <|
                \() ->
                    AC.colCountWithoutTotals crosstabWithOneRowAndOneColumn
                        |> Expect.equal 1
            , test "should not be fully loaded" <|
                \() ->
                    AC.isFullyLoaded crosstabWithOneRowAndOneColumn
                        |> Expect.equal False
                        |> Expect.onFail "should not be fully loaded"
            ]
        , describe "test affixing group to row"
            [ test "affix row correctly" <|
                \() ->
                    AC.getRows affixedCrosstab
                        |> Expect.equal [ affixedItem ]
            , test "totals after affixing are correct" <|
                \() ->
                    AC.getTotals affixedCrosstab
                        |> Dict.Any.values
                        |> List.map .data
                        |> Expect.equal
                            [ initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells affixedCrosstab)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells affixedCrosstab)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoadingForTotalVsTotal
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells affixedCrosstab)
                                    )
                                )
                            ]
            , test "commands after affixing are correct" <|
                \() ->
                    affixedCommands
                        |> List.sortBy commandToComoparable
                        |> Expect.equal
                            (List.sortBy commandToComoparable
                                [ MakeHttpRequest
                                    (AC.generateBulkTrackerId
                                        wavesSet
                                        locationsSet
                                        projectBaseAudience
                                        (AC.getVisibleCells affixedCrosstab)
                                        ++ "--incompatibilities"
                                    )
                                    wavesSet
                                    locationsSet
                                    projectBaseAudience
                                    (IncompatibilityBulkRequest
                                        { rows = [ affixedItem ]
                                        , rowExprs = [ affixedExpression ]
                                        , cols = []
                                        , colExprs = []
                                        }
                                    )
                                , MakeHttpRequest
                                    (AC.generateBulkTrackerId
                                        wavesSet
                                        locationsSet
                                        projectBaseAudience
                                        (AC.getVisibleCells affixedCrosstab)
                                    )
                                    wavesSet
                                    locationsSet
                                    projectBaseAudience
                                    (CrosstabBulkAvARequest
                                        { rows = [ affixedItem ]
                                        , rowExprs = [ affixedExpression ]
                                        , cols = []
                                        , colExprs = []
                                        }
                                    )
                                ]
                            )
            ]
        , describe "test affixing group to column"
            [ test "affix column correctly" <|
                \() ->
                    AC.affixGroups listForAffixingCol crosstabForAffixCol
                        |> (\( crosstab, _ ) -> crosstab)
                        |> AC.getColumns
                        |> Expect.equal [ affixedItem ]
            , test "totals after affixing are correct" <|
                \() ->
                    AC.affixGroups listForAffixingCol crosstabForAffixCol
                        |> (\( crosstab, _ ) -> crosstab)
                        |> AC.getTotals
                        |> Dict.Any.values
                        |> List.map .data
                        |> Expect.equal
                            [ initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabForAffixCol)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabForAffixCol)
                                        ++ "--incompatibilities"
                                    )
                                )
                            , initCellDataWithLoadingForTotalVsTotal
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabForAffixCol)
                                    )
                                )
                            ]
            , test "commands after affixing are correct" <|
                \() ->
                    AC.affixGroups listForAffixingCol crosstabForAffixCol
                        |> (\( _, { commands } ) -> commands)
                        |> List.sortBy commandToComoparable
                        |> Expect.equal
                            (List.sortBy commandToComoparable
                                [ MakeHttpRequest
                                    (AC.generateBulkTrackerId wavesSet
                                        locationsSet
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabForAffixCol)
                                        ++ "--incompatibilities"
                                    )
                                    wavesSet
                                    locationsSet
                                    projectBaseAudience
                                    (IncompatibilityBulkRequest
                                        { rows = []
                                        , rowExprs = []
                                        , cols = [ affixedItem ]
                                        , colExprs = [ affixedExpression ]
                                        }
                                    )
                                , MakeHttpRequest
                                    (AC.generateBulkTrackerId wavesSet
                                        locationsSet
                                        projectBaseAudience
                                        (AC.getVisibleCells crosstabForAffixCol)
                                    )
                                    wavesSet
                                    locationsSet
                                    projectBaseAudience
                                    (CrosstabBulkAvARequest
                                        { rows = []
                                        , rowExprs = []
                                        , cols = [ affixedItem ]
                                        , colExprs = [ affixedExpression ]
                                        }
                                    )
                                ]
                            )
            ]
        , describe "limits"
            [ test "If you want to add rows above limit it will return error" <|
                \() ->
                    emptyAc 5 loadingBoundaries
                        |> AC.addColumn AC.emptyCell.data (key 1)
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 2))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 3))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 4))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 5))
                        |> Expect.equal (Err { exceedingSize = 8, sizeLimit = 5, currentBasesCount = 1 })
            , test "If you want to add cols above limit it will return error" <|
                \() ->
                    emptyAc 5 loadingBoundaries
                        |> AC.addRow AC.emptyCell.data (key 1)
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 2))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 3))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 4))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 5))
                        |> Expect.equal (Err { exceedingSize = 8, sizeLimit = 5, currentBasesCount = 1 })
            , test "If you want to add a base that would bring cells above limit it will return error" <|
                \() ->
                    emptyAc 20 loadingBoundaries
                        |> AC.addRow AC.emptyCell.data (key 1)
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 2))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 3))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 4))
                        {- I don't want to deal with unwrapping the Result ErrorAddingRowOrColumn ...
                           So we just remap it to Result ErrorAddingBase ... right away
                        -}
                        |> Result.mapError (always { currentBasesCount = 0, totalLimit = 0, maxBasesCount = 0, exceededBasesBy = 0 })
                        |> Result.andThen (AC.createNewBaseAudience projectBaseAudience)
                        |> Result.map Tuple.first
                        |> Result.andThen (AC.createNewBaseAudience projectBaseAudience)
                        |> Expect.equal (Err { currentBasesCount = 2, totalLimit = 20, maxBasesCount = 2, exceededBasesBy = 1 })
            , test "If move would exceed limit it should return error" <|
                \() ->
                    emptyAc 15 loadingBoundaries
                        |> AC.addColumn AC.emptyCell.data (key 1)
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 2))
                        |> Result.andThen (AC.addColumn AC.emptyCell.data (key 3))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 4))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 5))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 6))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 7))
                        |> Result.andThen (AC.addRow AC.emptyCell.data (key 8))
                        |> Result.andThen (AC.moveItemsToColumnIndex 2 ( ( Row, key 5 ), [] ))
                        |> Expect.err
            , test "should get totals vs row cell data" <|
                \() ->
                    crosstabWithOneRowAndOneColumn
                        |> AC.value
                            { row = row1Key
                            , col = { item = AudienceItem.totalItem, isSelected = False }
                            , base = BaseAudience.default
                            }
                        |> .data
                        |> Expect.equal
                            (initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                        ++ "--incompatibilities"
                                    )
                                )
                            )
            , test "should get totals vs col cell data" <|
                \() ->
                    crosstabWithOneRowAndOneColumn
                        |> AC.value
                            { row = { item = AudienceItem.totalItem, isSelected = False }
                            , col = col1Key
                            , base = BaseAudience.default
                            }
                        |> .data
                        |> Expect.equal
                            (initCellDataWithLoading
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                    )
                                )
                                (Just
                                    (AC.generateBulkTrackerId
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "wave_1"))
                                        (XB2.Share.Data.Id.singletonSet (XB2.Share.Data.Id.fromString "location_1"))
                                        BaseAudience.default
                                        (AC.getVisibleCells crosstabWithOneRowAndOneColumn)
                                        ++ "--incompatibilities"
                                    )
                                )
                            )
            ]
        , describe "Correct info about selection"
            [ test "allColumnsSelected should be correct with averages" <|
                \() ->
                    Expect.equal True (AC.allColumnsSelected <| AC.selectAllColumns crosstabWithAverages)
            , test "allRowsSelected should be correct with averages" <|
                \() ->
                    Expect.equal True (AC.allRowsSelected <| AC.selectAllRows crosstabWithAverages)
            , test "count of selectable cols should be correct with averages" <|
                \() ->
                    Expect.equal 1 (AC.selectableColCountWithoutTotals crosstabWithAverages)
            , test "count of cols should be correct with averages" <|
                \() ->
                    Expect.equal 2 (AC.colCountWithoutTotals crosstabWithAverages)
            , test "count of selectable rows should be correct with averages" <|
                \() ->
                    Expect.equal 1 (AC.selectableRowCountWithoutTotals crosstabWithAverages)
            , test "count of rows should be correct with averages" <|
                \() ->
                    Expect.equal 2 (AC.rowCountWithoutTotals crosstabWithAverages)
            , test "count of rows should be correct with only averages" <|
                \() ->
                    emptyAc 10 loadingBoundaries
                        |> AC.setCellsVisibility True allCellsVisible
                        |> addToMockCrosstab AC.addRows (mockAverageItem "Average row")
                        |> addToMockCrosstab AC.addColumns col1
                        |> addToMockCrosstab AC.addColumns (mockAverageItem "Average column")
                        |> addToMockCrosstab AC.addColumns (mockItem "Col 2")
                        |> AC.selectableRowCountWithoutTotals
                        |> Expect.equal 0
            , test "count of selectable cols should be correct" <|
                \() ->
                    emptyAc 20 loadingBoundaries
                        |> AC.setCellsVisibility True allCellsVisible
                        |> addToMockCrosstab AC.addRows (mockAverageItem "Average row")
                        |> addToMockCrosstab AC.addRows (mockItem "row 1")
                        |> addToMockCrosstab AC.addColumns col1
                        |> addToMockCrosstab AC.addColumns (mockAverageItem "Average column")
                        |> addToMockCrosstab AC.addColumns (mockItem "Col 2")
                        |> addToMockCrosstab AC.addColumns (mockItem "Col 3")
                        |> addToMockCrosstab AC.addColumns (mockItem "Col 4")
                        |> AC.selectableColCountWithoutTotals
                        |> Expect.equal 4
            ]
        , describe "Correct multiple selection with shift pressed"
            [ test "(Rows) Fist selected 4th to select all between should be selected" <|
                \() ->
                    let
                        allRows =
                            AC.getRows crosstab10x10
                    in
                    case ( List.getAt 0 allRows, List.getAt 3 allRows ) of
                        ( Just r1, Just r4 ) ->
                            let
                                expected =
                                    allRows
                                        |> List.splitAt 4
                                        |> Tuple.first
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectRow r1
                                |> AC.selectRowWithShift r4
                                |> AC.getSelectedRows
                                |> Expect.equal expected

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            , test "(Rows) Fist selected, 3rd selected 6th to select all between 3 and 6 should be selected" <|
                \() ->
                    let
                        allRows =
                            AC.getRows crosstab10x10
                    in
                    case ( List.getAt 0 allRows, List.getAt 2 allRows, List.getAt 5 allRows ) of
                        ( Just r1, Just r3, Just r6 ) ->
                            let
                                expected =
                                    (Tuple.first <| List.splitAt 1 allRows)
                                        ++ (allRows
                                                |> List.splitAt 2
                                                |> Tuple.second
                                                |> List.splitAt 4
                                                |> Tuple.first
                                           )
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectRow r1
                                |> AC.selectRow r3
                                |> AC.selectRowWithShift r6
                                |> AC.getSelectedRows
                                |> Expect.equal expected

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            , test "(Rows) [S, N, S, N, N, C, N, S, N, N] S - selected, N - not selected, C - click to select" <|
                \() ->
                    let
                        allRows =
                            AC.getRows crosstab10x10
                    in
                    case ( ( List.getAt 0 allRows, List.getAt 2 allRows ), ( List.getAt 5 allRows, List.getAt 7 allRows ) ) of
                        ( ( Just r1, Just r3 ), ( Just r6, Just r8 ) ) ->
                            let
                                expected =
                                    (Tuple.first <| List.splitAt 1 allRows)
                                        ++ (allRows
                                                |> List.splitAt 2
                                                |> Tuple.second
                                                |> List.splitAt 4
                                                |> Tuple.first
                                           )
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectRow r1
                                |> AC.selectRow r3
                                |> AC.selectRow r8
                                |> AC.selectRowWithShift r6
                                |> AC.getSelectedRows
                                |> Expect.equal (expected ++ [ setSelected r8 ])

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            , test "(Rows) [N, N, C, N, N, N, N, S, N, N] S - selected, N - not selected, C - click to select" <|
                \() ->
                    let
                        allRows =
                            AC.getRows crosstab10x10
                    in
                    case ( List.getAt 2 allRows, List.getAt 7 allRows ) of
                        ( Just r3, Just r8 ) ->
                            let
                                expected =
                                    (allRows
                                        |> List.splitAt 2
                                        |> Tuple.second
                                        |> List.splitAt 6
                                        |> Tuple.first
                                    )
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectRow r8
                                |> AC.selectRowWithShift r3
                                |> AC.getSelectedRows
                                |> Expect.equal expected

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            , test "(Columns) Fist selected 4th to select all between should be selected" <|
                \() ->
                    let
                        allColumns =
                            AC.getColumns crosstab10x10
                    in
                    case ( List.getAt 0 allColumns, List.getAt 3 allColumns ) of
                        ( Just r1, Just r4 ) ->
                            let
                                expected =
                                    allColumns
                                        |> List.splitAt 4
                                        |> Tuple.first
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectColumn r1
                                |> AC.selectColumnWithShift r4
                                |> AC.getSelectedColumns
                                |> Expect.equal expected

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            , test "(Columns) [N, N, C, N, N, N, N, S, N, N] S - selected, N - not selected, C - click to select" <|
                \() ->
                    let
                        allColumns =
                            AC.getColumns crosstab10x10
                    in
                    case ( List.getAt 2 allColumns, List.getAt 7 allColumns ) of
                        ( Just r3, Just r8 ) ->
                            let
                                expected =
                                    (allColumns
                                        |> List.splitAt 2
                                        |> Tuple.second
                                        |> List.splitAt 6
                                        |> Tuple.first
                                    )
                                        |> List.map setSelected
                            in
                            crosstab10x10
                                |> AC.selectColumn r8
                                |> AC.selectColumnWithShift r3
                                |> AC.getSelectedColumns
                                |> Expect.equal expected

                        _ ->
                            Expect.fail "Invalid input crosstab, missing some rows"
            ]
        ]


setSelected : AC.Key -> AC.Key
setSelected item =
    { item | isSelected = True }


notAffixedExpression : Expression.Expression
notAffixedExpression =
    Expression.FirstLevelLeaf
        { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_1")
        , isExcluded = Optional.Present False
        , minCount = Optional.Present 1
        , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
        , suffixCodes = Optional.Undefined
        }


notAffixedKey : Random.Seed -> ( Key, Random.Seed )
notAffixedKey seed =
    AudienceItem.fromCaptionExpression
        seed
        (Caption.fromAudience
            { audience = "Male"
            , parent = Nothing
            }
        )
        notAffixedExpression
        |> Tuple.mapFirst
            (\item ->
                { item = item
                , isSelected = False
                }
            )


diffInExpressions : Expression.Expression
diffInExpressions =
    Expression.FirstLevelNode Expression.Or
        ( Expression.Leaf
            { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_1")
            , isExcluded = Optional.Present False
            , minCount = Optional.Present 1
            , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
            , suffixCodes = Optional.Undefined
            }
        , []
        )


affixedExpression : Expression.Expression
affixedExpression =
    Expression.FirstLevelNode Expression.Or
        ( Expression.Leaf
            { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_1")
            , isExcluded = Optional.Present False
            , minCount = Optional.Present 1
            , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
            , suffixCodes = Optional.Undefined
            }
        , [ Expression.Node Expression.Or
                (NonEmpty.singleton <|
                    Expression.Leaf
                        { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_2")
                        , isExcluded = Optional.Present False
                        , minCount = Optional.Present 1
                        , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
                        , suffixCodes = Optional.Undefined
                        }
                )
          ]
        )


listForAffixingRow : List AffixGroupItem
listForAffixingRow =
    [ { direction = Row
      , oldItem = .item (Tuple.first <| notAffixedKey <| Random.initialSeed 1)
      , oldExpression = notAffixedExpression
      , newExpression = affixedExpression
      , expressionBeingAffixed = diffInExpressions
      , newCaption =
            Caption.fromAudience
                { audience = "Male or Female"
                , parent = Nothing
                }
      }
    ]


listForAffixingCol : List AffixGroupItem
listForAffixingCol =
    [ { direction = Column
      , oldItem = .item (Tuple.first <| notAffixedKey <| Random.initialSeed 1)
      , oldExpression = notAffixedExpression
      , newExpression = affixedExpression
      , expressionBeingAffixed = diffInExpressions
      , newCaption =
            Caption.fromAudience
                { audience = "Male or Female"
                , parent = Nothing
                }
      }
    ]


affixedItem : Key
affixedItem =
    let
        row =
            Tuple.first <| notAffixedKey <| Random.initialSeed 1
    in
    { row
        | item =
            row.item
                |> AudienceItem.setCaption
                    (Caption.fromAudience
                        { audience = "Male or Female"
                        , parent = Nothing
                        }
                    )
                |> AudienceItem.setExpression affixedExpression
    }


wavesSet : Set.Any.AnySet String (XB2.Share.Data.Id.Id a)
wavesSet =
    XB2.Share.Data.Id.emptySet
        |> Set.Any.insert (XB2.Share.Data.Id.fromString "wave_1")


locationsSet : Set.Any.AnySet String (XB2.Share.Data.Id.Id a)
locationsSet =
    XB2.Share.Data.Id.emptySet
        |> Set.Any.insert (XB2.Share.Data.Id.fromString "location_1")


emptyAc_ : Int -> Int -> AudienceCrosstab
emptyAc_ =
    AC.empty (Time.millisToPosix 1)


emptyAc : Int -> Int -> AudienceCrosstab
emptyAc number anotherNumber =
    let
        ac =
            emptyAc_ number anotherNumber
    in
    ac
        |> AC.setActiveWaves wavesSet
        |> Maybe.unwrap ac Tuple.first
        |> AC.setActiveLocations locationsSet
        |> Maybe.unwrap ac Tuple.first


crosstabForAffixRow : AudienceCrosstab
crosstabForAffixRow =
    emptyAc 10 loadingBoundaries
        |> AC.setCellsVisibility True allCellsVisible
        |> AC.setBaseAudienceAtIndexWithCommands 0 projectBaseAudience
        |> Maybe.unwrap (emptyAc 10 loadingBoundaries) Tuple.first
        |> AC.addAudiences AC.addRows [ notAffixedKey ]
        |> Result.withDefault ( emptyAc 10 loadingBoundaries, [] )
        |> Tuple.first


crosstabForAffixCol : AudienceCrosstab
crosstabForAffixCol =
    emptyAc 10 loadingBoundaries
        |> AC.setCellsVisibility True allCellsVisible
        |> AC.setBaseAudienceAtIndexWithCommands 0 projectBaseAudience
        |> Maybe.unwrap (emptyAc 10 loadingBoundaries) Tuple.first
        |> AC.addAudiences AC.addColumns [ notAffixedKey ]
        |> Result.withDefault ( emptyAc 10 loadingBoundaries, [] )
        |> Tuple.first


affixedCrosstab : AudienceCrosstab
affixedCrosstab =
    AC.affixGroups listForAffixingRow crosstabForAffixRow
        |> (\( crosstab, _ ) -> crosstab)


affixedCommands : List Command
affixedCommands =
    AC.affixGroups listForAffixingRow crosstabForAffixRow
        |> (\( _, { commands } ) -> commands)


addToMockCrosstab : AC.MultipleAudiencesInserter -> (Random.Seed -> ( Key, Random.Seed )) -> AudienceCrosstab -> AudienceCrosstab
addToMockCrosstab inserter item =
    AC.addAudiences inserter [ item ]
        >> Result.withDefault ( emptyAc 10 loadingBoundaries, [] )
        >> Tuple.first


crosstabWithOneRow : AudienceCrosstab
crosstabWithOneRow =
    emptyAc 10 loadingBoundaries
        |> addToMockCrosstab AC.addRows row1


crosstabWithOneColumn : AudienceCrosstab
crosstabWithOneColumn =
    emptyAc 10 loadingBoundaries
        |> addToMockCrosstab AC.addColumns col1


crosstabWithOneRowAndOneColumn : AudienceCrosstab
crosstabWithOneRowAndOneColumn =
    emptyAc 10 loadingBoundaries
        |> AC.setCellsVisibility True allCellsVisible
        |> addToMockCrosstab AC.addRows row1
        |> addToMockCrosstab AC.addColumns col1


crosstab10x10 : AudienceCrosstab
crosstab10x10 =
    List.range 1 10
        |> List.foldl
            (\index ->
                addToMockCrosstab AC.addColumns (mockItem ("c" ++ String.fromInt index))
                    >> addToMockCrosstab AC.addRows (mockItem ("r" ++ String.fromInt index))
            )
            (emptyAc 200 loadingBoundaries
                |> AC.setCellsVisibility True allCellsVisible
            )


crosstabWithAverages : AudienceCrosstab
crosstabWithAverages =
    emptyAc 10 loadingBoundaries
        |> AC.setCellsVisibility True allCellsVisible
        |> addToMockCrosstab AC.addRows row1
        |> addToMockCrosstab AC.addRows (mockAverageItem "Average row")
        |> addToMockCrosstab AC.addColumns col1
        |> addToMockCrosstab AC.addColumns (mockAverageItem "Average column")


crosstabWithRowRemoved : ( AudienceCrosstab, List Command )
crosstabWithRowRemoved =
    AC.removeAudiences [ ( Row, Tuple.first <| row1 (Random.initialSeed 1) ) ] crosstabWithOneRowAndOneColumn


crosstabWithColumnRemoved : ( AudienceCrosstab, List Command )
crosstabWithColumnRemoved =
    let
        ( _, columnSeed ) =
            row1 (Random.initialSeed 1)
    in
    AC.removeAudiences [ ( Column, Tuple.first <| col1 columnSeed ) ] crosstabWithOneRowAndOneColumn


crosstabWithRowAndColumnRemoved : ( AudienceCrosstab, List Command )
crosstabWithRowAndColumnRemoved =
    let
        ( rowItem, columnSeed ) =
            row1 (Random.initialSeed 1)
    in
    AC.removeAudiences [ ( Row, rowItem ), ( Column, Tuple.first <| col1 columnSeed ) ] crosstabWithOneRowAndOneColumn


crosstabLoadedFromProject : AudienceCrosstab
crosstabLoadedFromProject =
    AC.initFromProject (Time.millisToPosix 0) 10 loadingBoundaries mockCrosstabProject
        |> Result.withDefault ( emptyAc 10 loadingBoundaries, [] )
        |> Tuple.first
        |> AC.setCellsVisibility True allCellsVisible
        |> AC.reloadNotLoadedCells
        |> Tuple.first


commandsWhenLoadingCrosstabFromProject : List Command
commandsWhenLoadingCrosstabFromProject =
    AC.initFromProject (Time.millisToPosix 0) 10 loadingBoundaries mockCrosstabProject
        |> Result.withDefault ( emptyAc 10 loadingBoundaries, [] )
        |> Tuple.first
        |> AC.setCellsVisibility True allCellsVisible
        |> AC.reloadNotLoadedCells
        |> Tuple.second


waveMock =
    let
        wMock =
            XB2.Share.Factory.Wave.mock
    in
    { wMock
        | code = XB2.Share.Data.Id.fromString "w1"
        , name = "Q1_2225"
    }


mockCrosstabProject : XBProjectFullyLoaded
mockCrosstabProject =
    { data =
        { rows = [ projectRowData ]
        , columns = [ projectColumn ]
        , locationCodes = [ XB2.Share.Data.Id.fromString "loc1" ]
        , waveCodes = [ waveMock.code ]

        -- irrelevant for this test module
        , ownerId = ""
        , bases = NonEmpty.singleton projectAudienceData
        , metadata =
            XB2.Data.defaultMetadata
        }
    , id = XB2.Share.Data.Id.fromString ""
    , folderId = Nothing
    , name = ""
    , updatedAt = Time.millisToPosix 0
    , createdAt = Time.millisToPosix 0
    , shared = XB2.Data.MyPrivateCrosstab
    , sharingNote = ""
    , copiedFrom = Nothing
    }


projectBaseAudience : BaseAudience
projectBaseAudience =
    BaseAudience.fromSavedProject (Random.initialSeed 0) projectAudienceData
        |> Tuple.first


projectAudienceData : BaseAudienceData
projectAudienceData =
    { id = "d05b2f41-602e-4b40-b4b9-7b92e5c83b57"
    , name = "baseAudience name"
    , fullName = "baseAudience fullName"
    , subtitle = "baseAudience subtitle"
    , expression = Expression.sizeExpression
    }


projectRowData : AudienceData
projectRowData =
    { id = row1IdString
    , name = "row name"
    , fullName = "full row name"
    , subtitle = "row subtitle"
    , definition = Expression Expression.sizeExpression
    }


projectRow1FromSavedProject : Key
projectRow1FromSavedProject =
    AudienceItem.fromSavedProject
        { id = row1IdString
        , name = "row name"
        , fullName = "row name"
        , subtitle = "row subtitle"
        , definition = Expression Expression.AllRespondents
        }
        (Random.initialSeed 1)
        |> Tuple.first
        |> (\item ->
                { item = item
                , isSelected = False
                }
           )


projectColumn : AudienceData
projectColumn =
    { id = col1IdString
    , name = "column name"
    , fullName = "full column name"
    , subtitle = "column subtitle"
    , definition = Expression Expression.sizeExpression
    }


projectColumn1FromSavedProject : Key
projectColumn1FromSavedProject =
    AudienceItem.fromSavedProject
        { id = col1IdString
        , name = "column name"
        , fullName = "column name"
        , subtitle = "column subtitle"
        , definition = Expression Expression.AllRespondents
        }
        (Random.initialSeed 1)
        |> Tuple.first
        |> (\item ->
                { item = item
                , isSelected = False
                }
           )


mockAverageItem : String -> Random.Seed -> ( Key, Random.Seed )
mockAverageItem title seed =
    AudienceItem.fromSavedProject
        { id = title
        , name = title
        , fullName = title
        , subtitle = ""
        , definition = Average <| Average.AvgWithoutSuffixes XB2.Share.Factory.Question.mock.longCode
        }
        seed
        |> Tuple.mapFirst
            (\item ->
                { item = item
                , isSelected = False
                }
            )


mockItem : String -> Random.Seed -> ( Key, Random.Seed )
mockItem title seed =
    AudienceItem.fromSavedProject
        { id = title
        , name = title
        , fullName = title
        , subtitle = ""
        , definition = Expression Expression.sizeExpression
        }
        seed
        |> Tuple.mapFirst
            (\item ->
                { item = item
                , isSelected = False
                }
            )


row1 : Random.Seed -> ( Key, Random.Seed )
row1 =
    mockItem "row1"


col1 : Random.Seed -> ( Key, Random.Seed )
col1 =
    mockItem "column1"


seed1 : Random.Seed
seed1 =
    Random.initialSeed 1


seed2 : Random.Seed
seed2 =
    row1 (Random.initialSeed 1)
        |> Tuple.second


row1Key : Key
row1Key =
    row1 seed1
        |> Tuple.first


row1IdString : String
row1IdString =
    row1Key.item
        |> AudienceItem.getIdString


col1Key : Key
col1Key =
    col1 seed2
        |> Tuple.first


col1IdString : String
col1IdString =
    col1Key.item
        |> AudienceItem.getIdString
