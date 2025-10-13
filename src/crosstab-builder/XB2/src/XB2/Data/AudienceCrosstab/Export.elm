module XB2.Data.AudienceCrosstab.Export exposing
    ( CellData
    , CellValue(..)
    , ExportData
    , ExportMetadata
    , ExportResult
    , ExportSettings
    , HeaderData
    , IntersectData
    , exportMultipleBases
    , exportResult
    )

import Dict.Any
import Http
import Json.Encode as Encode exposing (Value)
import Json.Encode.Extra as Encode
import Maybe.Extra as Maybe
import Result.Extra as Result
import Time exposing (Posix)
import Time.Extra
import Url.Builder
import XB2.Data
import XB2.Data.AudienceCrosstab as ACrosstab
import XB2.Data.AudienceCrosstab.Sort as Sort exposing (SortConfig)
import XB2.Data.AudienceItem as AudienceItem exposing (AudienceItem)
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.Average as Average exposing (AverageTimeFormat)
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect exposing (XBQueryError)
import XB2.Data.Calc.Average exposing (AverageResult)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Metric as Metric exposing (Metric(..))
import XB2.Data.MetricsTransposition exposing (MetricsTransposition(..))
import XB2.Detail.Heatmap as Heatmap
import XB2.RemoteData.Tracked exposing (RemoteData(..))
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Id exposing (IdDict)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , NamespaceAndQuestionCodeTag
        , Question
        , QuestionAveragesUnit(..)
        , Wave
        )
import XB2.Share.Data.Platform2.Export
import XB2.Share.Export exposing (ExportResponse)
import XB2.Share.Gwi.Http exposing (Error)
import XB2.Share.Gwi.List as List


type alias IntersectData =
    { sample : Int
    , size : Int
    , rowPercentage : Float
    , columnPercentage : Float
    , index : Float
    }


type alias CellData =
    { rowId : AudienceItemId
    , row : ACrosstab.Key
    , columnId : AudienceItemId
    , col : ACrosstab.Key
    , base : BaseAudience
    , value : CellValue
    , backgroundColor : Maybe String
    }


type CellValue
    = IntersectionValue IntersectData
    | AverageValue AverageResult
    | ErrorValue (Error XBQueryError)


type alias HeaderData =
    { id : String
    , label : Caption
    , questionNames : List String
    }


type alias ExportMetadata =
    { locations : List Location
    , waves : List Wave
    , date : Posix
    , base : BaseAudience
    , name : Maybe String
    , heatmap : Maybe Metric
    , averageTimeFormat : AverageTimeFormat
    }


type alias ExportSettings =
    { orientation : MetricsTransposition
    , activeMetrics : List Metric
    , -- TODO this is always false... what about hardcoding it in the encoder but not having it in this type?
      email : Bool
    }


type alias ExportResult =
    { rows : List HeaderData
    , columns : List HeaderData
    , cells : List CellData
    }


type alias ExportData =
    List
        { metadata : ExportMetadata
        , settings : ExportSettings
        , results : ExportResult
        }


toHeaderData : IdDict NamespaceAndQuestionCodeTag Question -> AudienceItem -> HeaderData
toHeaderData questions item =
    let
        questionNames =
            item
                |> AudienceItem.getDefinition
                |> XB2.Data.definitionNamespaceAndQuestionCodes
                |> List.map
                    (\code ->
                        Dict.Any.get code questions
                            |> Maybe.unwrap (XB2.Share.Data.Id.unwrap code) .name
                    )
    in
    HeaderData
        (AudienceItem.getIdString item)
        (AudienceItem.getCaption item)
        questionNames


toErrorData : AudienceItem -> AudienceItem -> BaseAudience -> Error XBQueryError -> CellData
toErrorData row column base error =
    { rowId = AudienceItem.getId row
    , row =
        { item = row
        , isSelected = False
        }
    , columnId = AudienceItem.getId column
    , col =
        { item = column
        , isSelected = False
        }
    , base = base
    , value = ErrorValue error
    , backgroundColor = Nothing
    }


toCellData : AudienceItem -> AudienceItem -> BaseAudience -> ACrosstab.AudienceCrosstab -> Maybe Metric -> ACrosstab.CellData -> Maybe CellData
toCellData row column base audienceCrosstab heatmapMetric cellData =
    case cellData of
        ACrosstab.AvAData data ->
            case data.data of
                NotAsked ->
                    Nothing

                Loading _ ->
                    Nothing

                Failure err ->
                    -- we want the N/As in the export too (ATC-2127)
                    Just <| toErrorData row column base err

                Success result ->
                    Just <|
                        toSuccessCellData row
                            column
                            base
                            audienceCrosstab
                            heatmapMetric
                            (IntersectionValue
                                -- a bit inefficient `toFloat >> round` ¯\_(ツ)_/¯
                                { sample = round <| AudienceIntersect.getValue Sample result
                                , size = round <| AudienceIntersect.getValue Size result
                                , rowPercentage = AudienceIntersect.getValue RowPercentage result
                                , columnPercentage = AudienceIntersect.getValue ColumnPercentage result
                                , index = AudienceIntersect.getValue Index result
                                }
                            )

        ACrosstab.AverageData data ->
            case data of
                NotAsked ->
                    Nothing

                Loading _ ->
                    Nothing

                Failure err ->
                    -- we want the N/As in the export too (ATC-2127)
                    Just <| toErrorData row column base err

                Success result ->
                    Just <| toSuccessCellData row column base audienceCrosstab heatmapMetric (AverageValue result)


toSuccessCellData : AudienceItem -> AudienceItem -> BaseAudience -> ACrosstab.AudienceCrosstab -> Maybe Metric -> CellValue -> CellData
toSuccessCellData row column base audienceCrosstab heatmapMetric cellValue =
    let
        heatmapScale =
            heatmapMetric
                |> Maybe.map (Heatmap.initScale audienceCrosstab)

        cellHeatmapColor scale =
            let
                rowKey =
                    { item = row, isSelected = False }

                colKey =
                    { item = column, isSelected = False }
            in
            case
                ACrosstab.value { row = rowKey, col = colKey, base = base }
                    audienceCrosstab
                    |> .data
            of
                ACrosstab.AvAData { data } ->
                    Heatmap.getColor scale
                        { row = row
                        , col = column
                        }
                        data

                ACrosstab.AverageData _ ->
                    Nothing

        color =
            Maybe.andThen cellHeatmapColor heatmapScale
    in
    { rowId = AudienceItem.getId row
    , row =
        { item = row
        , isSelected = False
        }
    , columnId = AudienceItem.getId column
    , col =
        { item = column
        , isSelected = False
        }
    , base = base
    , value = cellValue
    , backgroundColor = color
    }


encodeMultipleBases : ExportData -> Value
encodeMultipleBases list_ =
    let
        list =
            List.map
                (\{ results, metadata, settings } ->
                    { results = encodeExportResult metadata.averageTimeFormat results
                    , metadata = encodeExportMetadata metadata
                    , settings = encodeExportSettings settings
                    }
                )
                list_
    in
    Encode.object
        [ ( "requests"
          , list
                |> Encode.list
                    (\{ results, metadata, settings } ->
                        [ ( "query_results", Encode.object results )
                        , ( "metadata", Encode.object metadata )
                        , ( "settings", Encode.object settings )
                        ]
                            |> Encode.object
                    )
          )
        ]


exportResult : Maybe SortConfig -> ACrosstab.AudienceCrosstab -> BaseAudience -> Maybe Metric -> IdDict NamespaceAndQuestionCodeTag Question -> Maybe ExportResult
exportResult sortConfig_ audienceCrosstab_ baseAudience heatmapMetric questions =
    let
        sortIfNeeded : ACrosstab.AudienceCrosstab -> ACrosstab.AudienceCrosstab
        sortIfNeeded ac =
            case sortConfig_ of
                Just sortConfig ->
                    let
                        keyMapping =
                            ACrosstab.getKeyMapping ac

                        crosstabTotals =
                            ACrosstab.getTotals ac
                    in
                    ACrosstab.updateCrosstab (Sort.sortAxisBy sortConfig baseAudience crosstabTotals keyMapping) ac

                Nothing ->
                    ac

        audienceCrosstab : ACrosstab.AudienceCrosstab
        audienceCrosstab =
            (if ACrosstab.getCurrentBaseAudience audienceCrosstab_ /= baseAudience then
                ACrosstab.setFocusToBase baseAudience audienceCrosstab_

             else
                audienceCrosstab_
            )
                |> sortIfNeeded

        totals =
            ACrosstab.getTotals audienceCrosstab

        crosstab =
            ACrosstab.getCrosstab audienceCrosstab

        totalVsTotalCell : Maybe CellData
        totalVsTotalCell =
            Dict.Any.get ( AudienceItem.totalItem, baseAudience ) totals
                |> Maybe.andThen
                    (.data
                        >> toCellData
                            AudienceItem.totalItem
                            AudienceItem.totalItem
                            baseAudience
                            audienceCrosstab
                            heatmapMetric
                    )

        totalColumnCells : Maybe (List CellData)
        totalColumnCells =
            Crosstab.getRows crosstab
                |> List.map
                    (\row ->
                        Dict.Any.get ( row.item, baseAudience ) totals
                            |> Maybe.andThen
                                (.data
                                    >> toCellData
                                        row.item
                                        AudienceItem.totalItem
                                        baseAudience
                                        audienceCrosstab
                                        heatmapMetric
                                )
                    )
                |> Maybe.combine

        totalRowCells : Maybe (List CellData)
        totalRowCells =
            Crosstab.getColumns crosstab
                |> List.map
                    (\column ->
                        Dict.Any.get ( column.item, baseAudience ) totals
                            |> Maybe.andThen
                                (.data
                                    >> toCellData
                                        AudienceItem.totalItem
                                        column.item
                                        baseAudience
                                        audienceCrosstab
                                        heatmapMetric
                                )
                    )
                |> Maybe.combine

        crosstabCells : Maybe (List CellData)
        crosstabCells =
            Crosstab.toListForBase baseAudience crosstab
                |> List.map
                    (\( { row, col }, value ) ->
                        toCellData
                            row.item
                            col.item
                            baseAudience
                            audienceCrosstab
                            heatmapMetric
                            value.data
                    )
                |> Maybe.combine

        cells : Maybe (List CellData)
        cells =
            Maybe.map4
                (\totalVsTotalCell_ totalColumnCells_ totalRowCells_ crosstabCells_ ->
                    totalVsTotalCell_
                        :: List.fastConcat
                            [ totalColumnCells_
                            , totalRowCells_
                            , crosstabCells_
                            ]
                )
                totalVsTotalCell
                totalColumnCells
                totalRowCells
                crosstabCells
    in
    cells
        |> Maybe.map
            (\cells_ ->
                let
                    rows =
                        List.map (toHeaderData questions) <| AudienceItem.totalItem :: List.map .item (Crosstab.getRows crosstab)

                    columns =
                        List.map (toHeaderData questions) <| AudienceItem.totalItem :: List.map .item (Crosstab.getColumns crosstab)
                in
                { rows = rows
                , columns = columns
                , cells = cells_
                }
            )


encodeExportResult : AverageTimeFormat -> ExportResult -> List ( String, Value )
encodeExportResult averageTimeFormat result =
    let
        encodeAudience { id, label, questionNames } =
            Encode.object
                [ ( "id", Encode.string id )
                , ( "name", Encode.string (Caption.toString label) )
                , ( "question_name"
                  , (if List.length questionNames > 1 then
                        List.map (\q -> "(" ++ q ++ ")") questionNames

                     else
                        questionNames
                    )
                        |> String.join " "
                        |> Encode.string
                  )
                ]

        encodeIntersect inter =
            Encode.object
                [ ( "size", Encode.int inter.size )
                , ( "sample", Encode.int inter.sample )
                , ( "row_percentage", Encode.float inter.rowPercentage )
                , ( "column_percentage", Encode.float inter.columnPercentage )
                , ( "index", Encode.float inter.index )
                ]

        encodeAverage avg =
            Encode.object
                [ ( "value"
                  , case avg.unit of
                        TimeInHours ->
                            Encode.string <| Average.averageTimeToString averageTimeFormat avg.value

                        AgreementScore ->
                            Encode.float avg.value

                        OtherUnit _ ->
                            Encode.float avg.value
                  )
                , ( "unit", XB2.Share.Data.Labels.encodeAveragesUnit avg.unit )
                ]

        encodeError err =
            Encode.object
                [ ( "error_type"
                  , err
                        |> XB2.Share.Gwi.Http.errorToErrorType AudienceIntersect.xbQueryErrorToErrorType
                        |> Encode.string
                  )
                ]

        encodeCell cell =
            Encode.object
                [ ( "row_id", Encode.string <| AudienceItemId.toString cell.rowId )
                , ( "column_id", Encode.string <| AudienceItemId.toString cell.columnId )
                , ( "background_color", Maybe.unwrap Encode.null Encode.string cell.backgroundColor )
                , case cell.value of
                    IntersectionValue intersect ->
                        ( "intersection", encodeIntersect intersect )

                    AverageValue avg ->
                        ( "average", encodeAverage avg )

                    ErrorValue err ->
                        ( "error", encodeError err )
                ]
    in
    [ ( "rows", Encode.list encodeAudience result.rows )
    , ( "columns", Encode.list encodeAudience result.columns )
    , ( "cells", Encode.list encodeCell result.cells )
    ]


orientationToString : MetricsTransposition -> String
orientationToString orientation =
    case orientation of
        MetricsInRows ->
            "vertical"

        MetricsInColumns ->
            "horizontal"


encodeExportSettings : ExportSettings -> List ( String, Value )
encodeExportSettings settings =
    [ ( "orientation", Encode.string <| orientationToString settings.orientation )
    , ( "active_metrics", Encode.list (Encode.string << Metric.toString) settings.activeMetrics )
    , ( "email", Encode.bool settings.email )
    ]


encodeExportMetadata : ExportMetadata -> List ( String, Value )
encodeExportMetadata metadata =
    [ ( "name", Maybe.unwrap Encode.null Encode.string metadata.name )
    , ( "base_audience_name", Encode.string (Caption.toString <| BaseAudience.getCaption metadata.base) )
    , ( "location_names", Encode.list (Encode.string << .name) metadata.locations )
    , ( "wave_names", Encode.list (Encode.string << .name) metadata.waves )
    , ( "export_time", Encode.string (Time.Extra.toIso8601DateTimeUTC metadata.date) )
    , ( "heatmap", Encode.maybe Encode.string (Maybe.map Metric.label metadata.heatmap) )
    ]


exportMultipleBases : Flags -> Maybe String -> ExportData -> (ExportResponse -> msg) -> (Error XB2.Share.Export.ExportError -> msg) -> Cmd msg
exportMultipleBases flags maybeTrackerId data urlFetched error =
    let
        host =
            .env >> XB2.Share.Config.Main.get >> .uri >> .api

        namespace =
            "/v3/exports"

        url =
            host flags
                ++ namespace
                ++ Url.Builder.absolute [ "crosstab.xlsx" ] []

        body =
            Http.jsonBody (encodeMultipleBases data)
    in
    Cmd.map (Result.unpack error urlFetched) <|
        Http.request
            { method = "POST"
            , headers = [ Auth.header flags.token ]
            , url = url
            , body = body
            , expect =
                XB2.Share.Gwi.Http.expectErrorAwareJson
                    XB2.Share.Export.exportErrorDecoder
                    (XB2.Share.Data.Platform2.Export.decodeExportsResponse flags)
            , timeout = Nothing
            , tracker = maybeTrackerId
            }
