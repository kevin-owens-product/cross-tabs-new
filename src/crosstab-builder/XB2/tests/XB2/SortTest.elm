module XB2.SortTest exposing (suite)

import Dict.Any as AnyDict
import Expect
import Fuzz exposing (Fuzzer)
import List.Extra as List
import List.NonEmpty as NonEmpty
import Random
import Test exposing (..)
import XB2.Data.Audience.Expression as Expression
import XB2.Data.AudienceCrosstab as ACrosstab
    exposing
        ( CellData(..)
        , CrosstabTable
        , Key
        )
import XB2.Data.AudienceCrosstab.Sort as Sort
import XB2.Data.AudienceItem as AudienceItem
import XB2.Data.Average exposing (Average(..))
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect
    exposing
        ( AudienceIntersection
        , Intersect
        , IntersectResult
        )
import XB2.Data.Calc.Average exposing (AverageResult)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Metric exposing (Metric(..))
import XB2.Data.Zod.Optional as Optional
import XB2.RemoteData.Tracked as Tracked exposing (RemoteData(..))
import XB2.Share.Data.Id
import XB2.Share.Data.Labels exposing (QuestionAveragesUnit(..))
import XB2.Share.Gwi.List as List
import XB2.Sort
    exposing
        ( Axis(..)
        , AxisSort(..)
        , SortDirection(..)
        )


suite : Test
suite =
    describe "XB2.Sort"
        [ describe "sortAxisBy"
            [ fuzz3
                crosstabFuzzer
                baseFuzzer
                axisFuzzer
                "NoSort leaves list unchanged"
              <|
                \crosstab base axis ->
                    let
                        keyMapping =
                            ACrosstab.computeKeyMapping crosstab
                    in
                    crosstab
                        |> Sort.sortAxisBy
                            { axis = axis
                            , mode = NoSort
                            }
                            base
                            (AnyDict.empty ACrosstab.totalKeyToComparable)
                            keyMapping
                        |> getHeadersFor axis
                        |> Expect.equal (getHeadersFor axis crosstab)
            , fuzz3
                crosstabFuzzer
                baseFuzzer
                (Fuzz.pair
                    axisFuzzer
                    directionFuzzer
                )
                "ByName sorts alphabetically by Caption.name"
              <|
                \crosstab base ( axis, direction ) ->
                    let
                        keyMapping =
                            ACrosstab.computeKeyMapping crosstab
                    in
                    crosstab
                        |> Sort.sortAxisBy
                            { axis = axis
                            , mode = ByName direction
                            }
                            base
                            (AnyDict.empty ACrosstab.totalKeyToComparable)
                            keyMapping
                        |> getHeadersFor axis
                        |> List.map (keyName >> String.toLower)
                        |> Expect.equal
                            (case direction of
                                Ascending ->
                                    getHeadersFor axis crosstab
                                        |> List.map (keyName >> String.toLower)
                                        |> List.sort

                                Descending ->
                                    getHeadersFor axis crosstab
                                        |> List.map (keyName >> String.toLower)
                                        |> List.reverseSortBy identity
                            )
            , test "ByOtherAxisAverage sorts by the average value - ASC ROWS" <|
                \() ->
                    let
                        direction =
                            Ascending

                        axis =
                            Rows

                        id =
                            keyFromName 7 "avg-h"
                                |> .item
                                |> AudienceItem.getId

                        cells =
                            [ ( ( 0, "a" ), ( 7, "avg-h" ), avgData 5 )
                            , ( ( 1, "b" ), ( 7, "avg-h" ), avgData 2 )

                            --, ( (2,"avg-c"), (7,"avg-h"), avgData 3 )
                            , ( ( 3, "d" ), ( 7, "avg-h" ), avgData 8 )
                            , ( ( 4, "e" ), ( 7, "avg-h" ), avgData 1 )
                            ]

                        expectedAvgSorting =
                            [ "e", "b", "a", "d", "avg-c" ]

                        crosstab =
                            predeterminedCrosstabWithCells cells

                        keyMapping =
                            ACrosstab.computeKeyMapping crosstab
                    in
                    crosstab
                        |> Sort.sortAxisBy
                            { axis = axis
                            , mode =
                                ByOtherAxisAverage id direction
                            }
                            BaseAudience.default
                            (AnyDict.empty ACrosstab.totalKeyToComparable)
                            keyMapping
                        |> getHeadersFor axis
                        |> List.map keyName
                        |> Expect.equal expectedAvgSorting
            , test "ByOtherAxisMetric sorts by the average value - DESC COLUMNS INDEX" <|
                \() ->
                    let
                        direction =
                            Descending

                        axis =
                            Columns

                        metric =
                            Index

                        id =
                            keyFromName 1 "b"
                                |> .item
                                |> AudienceItem.getId

                        cells =
                            [ ( ( 1, "b" ), ( 5, "f" ), avaData 0 0 3 0 0 )
                            , ( ( 1, "b" ), ( 6, "g" ), avaData 0 0 1 0 0 )
                            , ( ( 1, "b" ), ( 7, "avg-h" ), avgData 3 )
                            , ( ( 1, "b" ), ( 8, "i" ), avaData 0 0 8 0 0 )
                            , ( ( 1, "b" ), ( 9, "j" ), avaData 0 0 7 0 0 )
                            ]

                        expectedAvASorting =
                            [ "i", "j", "f", "g", "avg-h" ]

                        crosstab =
                            predeterminedCrosstabWithCells cells

                        keyMapping =
                            ACrosstab.computeKeyMapping crosstab
                    in
                    crosstab
                        |> Sort.sortAxisBy
                            { axis = axis
                            , mode =
                                ByOtherAxisMetric id metric direction
                            }
                            BaseAudience.default
                            (AnyDict.empty ACrosstab.totalKeyToComparable)
                            keyMapping
                        |> getHeadersFor axis
                        |> List.map keyName
                        |> Expect.equal expectedAvASorting
            ]
        ]


predeterminedCrosstab : List ( Axis, Int, String )
predeterminedCrosstab =
    [ ( Rows, 0, "a" )
    , ( Rows, 1, "b" )
    , ( Rows, 2, "avg-c" )
    , ( Rows, 3, "d" )
    , ( Rows, 4, "e" )
    , ( Columns, 5, "f" )
    , ( Columns, 6, "g" )
    , ( Columns, 7, "avg-h" )
    , ( Columns, 8, "i" )
    , ( Columns, 9, "j" )
    ]


predeterminedCrosstabWithCells : List ( ( Int, String ), ( Int, String ), CellData ) -> CrosstabTable
predeterminedCrosstabWithCells cells =
    List.foldl
        (\( ( rowI, row ), ( colI, col ), value ) acc ->
            addCell
                ( { row = keyFromName rowI row
                  , col = keyFromName colI col
                  , base = BaseAudience.default
                  }
                , value
                )
                acc
        )
        predeterminedCrosstabWithoutCells
        cells


predeterminedCrosstabWithoutCells =
    List.foldl
        (\( axis_, i, name ) acc ->
            case axis_ of
                Rows ->
                    addRow i name acc

                Columns ->
                    addColumn i name acc
        )
        ACrosstab.emptyCrosstabTable
        predeterminedCrosstab


getHeadersFor : Axis -> CrosstabTable -> List Key
getHeadersFor axis crosstab =
    case axis of
        Rows ->
            Crosstab.getRows crosstab

        Columns ->
            Crosstab.getColumns crosstab


bases : List BaseAudience
bases =
    [ BaseAudience.default
    , BaseAudience.fromSavedProject
        (Random.initialSeed 1)
        { id = "base1"
        , name = "base1"
        , fullName = "base1"
        , subtitle = "base1"
        , expression =
            Expression.FirstLevelLeaf
                { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_1")
                , isExcluded = Optional.Present False
                , minCount = Optional.Present 1
                , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
                , suffixCodes = Optional.Undefined
                , metadata = Optional.Undefined
                }
        }
        |> Tuple.first
    , BaseAudience.fromSavedProject
        (Random.initialSeed 2)
        { id = "base2"
        , name = "base2"
        , fullName = "base2"
        , subtitle = "base2"
        , expression =
            Expression.FirstLevelLeaf
                { questionAndDatapointCodes = NonEmpty.singleton (XB2.Share.Data.Id.fromString "q2_2")
                , isExcluded = Optional.Present False
                , minCount = Optional.Present 1
                , namespaceAndQuestionCode = XB2.Share.Data.Id.fromString "q2"
                , suffixCodes = Optional.Undefined
                , metadata = Optional.Undefined
                }
        }
        |> Tuple.first
    ]


oneOfValues : List a -> Fuzzer a
oneOfValues list =
    Fuzz.oneOf (List.map Fuzz.constant list)


baseFuzzer : Fuzzer BaseAudience
baseFuzzer =
    oneOfValues bases


axisFuzzer : Fuzzer Axis
axisFuzzer =
    oneOfValues
        [ Rows
        , Columns
        ]


directionFuzzer : Fuzzer SortDirection
directionFuzzer =
    oneOfValues
        [ Ascending
        , Descending
        ]


itemNameFuzzer : Fuzzer String
itemNameFuzzer =
    oneOfValues
        [ "Abc"
        , "abcd"
        , "DEf"
        , "deFG"
        , "123"
        , "X-Z"
        ]


itemNamesFuzzer : Fuzzer (List String)
itemNamesFuzzer =
    Fuzz.map5 (\a b c d e -> [ a, b, c, d, e ])
        itemNameFuzzer
        itemNameFuzzer
        itemNameFuzzer
        itemNameFuzzer
        itemNameFuzzer


cellsFuzzer : Fuzzer (List ( { row : Key, col : Key, base : BaseAudience }, CellData ))
cellsFuzzer =
    Fuzz.list cellFuzzer


cellFuzzer : Fuzzer ( { row : Key, col : Key, base : BaseAudience }, CellData )
cellFuzzer =
    Fuzz.pair insertKeyFuzzer cellDataFuzzer


insertKeyFuzzer : Fuzzer { row : Key, col : Key, base : BaseAudience }
insertKeyFuzzer =
    Fuzz.map3 (\row col base -> { row = row, col = col, base = base })
        keyFuzzer
        keyFuzzer
        baseFuzzer


keyFuzzer : Fuzzer Key
keyFuzzer =
    Fuzz.map2 keyFromName
        (Fuzz.intRange 0 4)
        itemNameFuzzer


cellDataFuzzer : Fuzzer CellData
cellDataFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant ACrosstab.emptyCell.data
        , Fuzz.map (\r -> AvAData { data = Success r, incompatibilities = NotAsked }) intersectResultFuzzer
        , Fuzz.map (AverageData << Success) averageResultFuzzer
        ]


intersectResultFuzzer : Fuzzer IntersectResult
intersectResultFuzzer =
    Fuzz.constant (\i a -> IntersectResult i a Nothing)
        |> Fuzz.andMap intersectFuzzer
        |> Fuzz.andMap
            (Fuzz.map2 (\row col -> { row = row, col = col })
                audienceIntersectionFuzzer
                audienceIntersectionFuzzer
            )


audienceIntersectionFuzzer : Fuzzer AudienceIntersection
audienceIntersectionFuzzer =
    Fuzz.constant AudienceIntersection
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap Fuzz.niceFloat
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap Fuzz.int


intersectFuzzer : Fuzzer Intersect
intersectFuzzer =
    Fuzz.constant Intersect
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap Fuzz.niceFloat


averageResultFuzzer : Fuzzer AverageResult
averageResultFuzzer =
    Fuzz.constant AverageResult
        |> Fuzz.andMap Fuzz.niceFloat
        |> Fuzz.andMap questionAveragesUnitFuzzer


questionAveragesUnitFuzzer : Fuzzer QuestionAveragesUnit
questionAveragesUnitFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant AgreementScore
        , Fuzz.map OtherUnit Fuzz.string
        ]


addRow : Int -> String -> CrosstabTable -> CrosstabTable
addRow i row crosstab =
    Crosstab.addRow
        ACrosstab.emptyCell
        (keyFromName i row)
        bases
        crosstab


addColumn : Int -> String -> CrosstabTable -> CrosstabTable
addColumn i column crosstab =
    Crosstab.addColumn
        ACrosstab.emptyCell
        (keyFromName i column)
        bases
        crosstab


addRows : List String -> CrosstabTable -> CrosstabTable
addRows rows crosstab =
    List.indexedFoldl addRow crosstab rows


addColumns : List String -> CrosstabTable -> CrosstabTable
addColumns columns crosstab =
    List.indexedFoldl addColumn crosstab columns


emptyCell =
    ACrosstab.emptyCell


addCell : ( { row : Key, col : Key, base : BaseAudience }, CellData ) -> CrosstabTable -> CrosstabTable
addCell ( key, cellData ) crosstab =
    Crosstab.insert
        key
        { emptyCell | data = cellData }
        crosstab


addCells : List ( { row : Key, col : Key, base : BaseAudience }, CellData ) -> CrosstabTable -> CrosstabTable
addCells cells crosstab =
    List.foldl addCell crosstab cells


crosstabFuzzer : Fuzzer CrosstabTable
crosstabFuzzer =
    Fuzz.map3
        (\rows columns cells ->
            ACrosstab.emptyCrosstabTable
                |> addRows rows
                |> addColumns columns
                |> addCells cells
        )
        itemNamesFuzzer
        itemNamesFuzzer
        cellsFuzzer


keyFromName : Int -> String -> Key
keyFromName i name =
    { item =
        if String.contains "avg" name then
            AudienceItem.fromCaptionAverage
                (Random.initialSeed i)
                (captionFromName name)
                (AvgWithoutSuffixes (XB2.Share.Data.Id.fromString "q2"))
                |> Tuple.first

        else
            AudienceItem.fromCaptionExpression
                (Random.initialSeed i)
                (captionFromName name)
                Expression.sizeExpression
                |> Tuple.first
    , isSelected = False
    }


captionFromName : String -> Caption
captionFromName name =
    Caption.create
        { name = name
        , fullName = name
        , subtitle = Nothing
        }


avaData a b c d e =
    ACrosstab.initCell
        (Tracked.Success
            { intersection =
                { size = a
                , sample = b
                , index = c
                }
            , audiences =
                { row =
                    { id = ""
                    , intersectPercentage = d
                    , sample = 0
                    , size = 0
                    }
                , col =
                    { id = ""
                    , intersectPercentage = e
                    , sample = 0
                    , size = 0
                    }
                }
            , stretching = Nothing
            }
        )
        Tracked.NotAsked
        |> .data


avgData a =
    AverageData <| Tracked.Success <| AverageResult a AgreementScore


keyName key =
    key.item
        |> AudienceItem.getCaption
        |> Caption.getName
