module XB2.Data.Calc.AudienceIntersect exposing
    ( AudienceIntersection
    , AudienceParam(..)
    , AudienceParams
    , BaseAudienceParam(..)
    , BulkAudienceParams
    , BulkIntersectFailure
    , BulkIntersectResult
    , BulkIntersectionResponse(..)
    , Intersect
    , IntersectResult
    , RequestOrigin(..)
    , Stretching
    , XBQueryError(..)
    , formatValue
    , getCoefficientStretchingInfo
    , getValue
    , mapXBAudiences
    , postCrosstab
    , request
    , swapXBAudiences
    , xbQueryErrorDecoder
    , xbQueryErrorDisplay
    , xbQueryErrorString
    , xbQueryErrorStringWithoutCodeTranslation
    , xbQueryErrorToErrorType
    )

{-| TODO: Move this to XB2.Api.Query module
-}

import Dict exposing (Dict)
import Dict.Any
import FormatNumber
import FormatNumber.Locales exposing (usLocale)
import Html
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode exposing (Value)
import Lazy.Tree as Tree
import Lazy.Tree.Zipper as Zipper exposing (Zipper)
import List.Extra as List
import Maybe.Extra as Maybe
import RemoteData
import Set.Any
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Dataset as Dataset
import XB2.Data.Metric exposing (Metric(..))
import XB2.Data.Namespace as Namespace
import XB2.RemoteData.Tracked as Tracked exposing (TrackerId)
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Core.Error as CoreError
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels
    exposing
        ( LocationCode
        , WaveCode
        )
import XB2.Share.Data.Platform2
import XB2.Share.Dialog.ErrorDisplay exposing (ErrorDisplay)
import XB2.Share.Gwi.FormatNumber as FormatNumber
import XB2.Share.Gwi.Http exposing (HttpCmd)
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store



-- Config


host : Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api


namespace : String
namespace =
    "/v2/query"


type XBQueryError
    = InvalidQuery String
    | EmptyAudienceExpression
    | UniverseZero
    | InvalidProjectsCombination (List Namespace.Code)



-- API


type AudienceParam
    = Total


encodeAudienceParam : AudienceParam -> Maybe Value
encodeAudienceParam param =
    case param of
        Total ->
            Nothing


{-| ATC-1322: total row/column won't show up in the `audiences` object:

     Total vs Total               --> audiences: {}
     Total Row vs Audience Column --> audiences: { column: {...} }
     Audience Row vs Total Column --> audiences: { row: {...} }
     Audience vs Audience         --> audiences: { row: {...}, column: {...} }

-}
encodeAudienceParams : AudienceParams -> Value
encodeAudienceParams params =
    let
        encode : ( String, AudienceParam ) -> Maybe ( String, Value )
        encode ( fieldName, param ) =
            encodeAudienceParam param
                |> Maybe.map (Tuple.pair fieldName)
    in
    [ ( "row", params.row )
    , ( "column", params.column )
    ]
        |> List.filterMap encode
        |> Encode.object


baseAudienceParam : Maybe BaseAudience -> List ( String, Value )
baseAudienceParam maybeBase =
    maybeBase
        |> Maybe.map (\base -> [ ( "base_audience", encodeBase base ) ])
        |> Maybe.withDefault []


encodeBase : BaseAudience -> Value
encodeBase base =
    Encode.object
        [ ( "id"
          , BaseAudience.getId base
                |> AudienceItemId.toString
                |> Encode.string
          )
        , ( "expression", Expression.encode <| BaseAudience.getExpression base )
        ]


removeAudiencePrefix : String -> String
removeAudiencePrefix id =
    Maybe.withDefault id <| List.last <| String.split "_|_" id


type alias Intersect =
    { size : Int
    , sample : Int
    , index : Float
    }


type alias AudienceIntersection =
    { id : String
    , intersectPercentage : Float
    , sample : Int
    , size : Int
    }


intersectDecoder : Decoder Intersect
intersectDecoder =
    Decode.succeed Intersect
        |> Decode.andMap (Decode.field "size" Decode.int)
        |> Decode.andMap (Decode.field "sample" Decode.int)
        |> Decode.andMap (Decode.field "index" Decode.float)


audienceIntersectionDecoder : Decoder AudienceIntersection
audienceIntersectionDecoder =
    Decode.succeed AudienceIntersection
        |> Decode.andMap (Decode.field "audience" (Decode.map removeAudiencePrefix Decode.string))
        |> Decode.andMap (Decode.field "intersect_percentage" Decode.float)
        |> Decode.andMap (Decode.field "sample" Decode.int)
        |> Decode.andMap (Decode.field "size" Decode.int)


type alias Stretching =
    { total : Float
    , coefficient : Float
    }


type alias IntersectResult =
    { intersection : Intersect
    , audiences :
        { row : AudienceIntersection
        , col : AudienceIntersection
        }
    , stretching : Maybe (Dict String Stretching)
    }


stretchingDecoder : Decoder Stretching
stretchingDecoder =
    Decode.succeed Stretching
        |> Decode.andMap (Decode.field "total_size" Decode.float)
        |> Decode.andMap (Decode.field "coefficient" Decode.float)


intersectResultDecoder : Decoder IntersectResult
intersectResultDecoder =
    Decode.succeed IntersectResult
        |> Decode.andMap (Decode.at [ "data", "intersect" ] intersectDecoder)
        |> Decode.andMap
            (Decode.at [ "data", "audiences" ]
                (Decode.succeed (\row col -> { row = row, col = col })
                    |> Decode.andMap (Decode.field "row" audienceIntersectionDecoder)
                    |> Decode.andMap (Decode.field "column" audienceIntersectionDecoder)
                )
            )
        |> Decode.andMap (Decode.field "meta" (Decode.optionalField "stretching" <| Decode.dict stretchingDecoder))


type alias AudienceParams =
    { row : AudienceParam
    , column : AudienceParam
    }


{-| Where the query request comes from.

  - `Table`: scrolling by the table as usual
  - `Export`: clicking "Export" button. This loads the whole crosstab.
  - `Heatmap`: toggling the heatmap view option. This loads the whole crosstab.

-}
type RequestOrigin
    = Table
    | Export
    | Heatmap


request :
    Flags
    -> RequestOrigin
    -> Maybe BaseAudience
    -> List LocationCode
    -> List WaveCode
    -> TrackerId
    -> AudienceParams
    -> HttpCmd XBQueryError IntersectResult
request ({ token } as flags) requestOrigin baseAudience locations waveCodes trackerId params =
    let
        url =
            case requestOrigin of
                Table ->
                    host flags ++ namespace ++ "/intersection"

                Export ->
                    host flags ++ namespace ++ "/intersection/export"

                Heatmap ->
                    host flags ++ namespace ++ "/intersection/heatmap"
    in
    Http.request
        { method = "POST"
        , headers = [ Auth.header token ]
        , url = url
        , body =
            Http.jsonBody <|
                Encode.object <|
                    List.append
                        [ ( "audiences", encodeAudienceParams params )
                        , ( "locations", Encode.list Id.encode locations )
                        , ( "waves", Encode.list Id.encode waveCodes )
                        ]
                    <|
                        baseAudienceParam baseAudience
        , expect =
            XB2.Share.Gwi.Http.expectErrorAwareJson
                xbQueryErrorDecoder
                intersectResultDecoder
        , timeout = Nothing
        , tracker = Just trackerId
        }


xbQueryErrorDisplay : XBQueryError -> ErrorDisplay msg
xbQueryErrorDisplay err =
    case err of
        InvalidQuery errorDetail ->
            { title = "Invalid query"
            , body = Html.text "The query was invalid."
            , details = [ errorDetail ]
            , errorId = Nothing
            }

        EmptyAudienceExpression ->
            { title = "Empty audience expression"
            , body = Html.text "One of the audiences was empty."
            , details = []
            , errorId = Nothing
            }

        UniverseZero ->
            { title = "Universe zero"
            , body = Html.text "Universe calculation had 0 as a result"
            , details = []
            , errorId = Nothing
            }

        InvalidProjectsCombination incompatibleProjects ->
            { title = "Invalid projects combination"
            , body =
                Html.div []
                    [ Html.text "These projects cannot be combined: "
                    , incompatibleProjects
                        |> List.map (\project -> Html.li [] [ Html.text <| Namespace.codeToString project ])
                        |> Html.ul []
                    ]
            , details = []
            , errorId = Nothing
            }


type DatasetsZipperItem
    = DItem Dataset.Dataset
    | DFolder (Maybe XB2.Share.Data.Platform2.DatasetFolder) (List DatasetsZipperItem)


xbQueryErrorString : XB2.Share.Store.Platform2.Store -> XBQueryError -> String
xbQueryErrorString store err =
    case err of
        InvalidQuery error ->
            "**Invalid query:** " ++ error

        EmptyAudienceExpression ->
            """One of the audiences in this intersection contains an **invalid empty 
            expression**. This may be due to an error in **creating the audience** or 
            because the **crosstab project is too old**. Please, **try re-adding the 
            audience** and contact support if the issue persists."""

        UniverseZero ->
            """The calculation for the **universe** of this intersection had **0** as a 
            result."""

        InvalidProjectsCombination ids ->
            let
                datasets =
                    store.datasets
                        |> RemoteData.withDefault (Dict.Any.empty Dataset.codeToString)

                setTypesAndDatasetChildrens : XB2.Share.Data.Platform2.DatasetFolder -> DatasetsZipperItem
                setTypesAndDatasetChildrens (XB2.Share.Data.Platform2.DatasetFolder folder) =
                    let
                        datasetsInFolder =
                            folder.datasetCodes
                                |> List.filterMap (\id -> Dict.Any.get id datasets |> Maybe.map DItem)
                    in
                    DFolder (Just <| XB2.Share.Data.Platform2.DatasetFolder folder) (datasetsInFolder ++ List.map setTypesAndDatasetChildrens folder.subfolders)

                rootFolder : DatasetsZipperItem
                rootFolder =
                    store.datasetFoldersTree
                        |> RemoteData.withDefault []
                        |> List.map setTypesAndDatasetChildrens
                        |> DFolder Nothing

                getChildren item =
                    case item of
                        DItem _ ->
                            []

                        DFolder _ subitems ->
                            subitems

                datasetsZipper : Zipper DatasetsZipperItem
                datasetsZipper =
                    rootFolder
                        |> Tree.build getChildren
                        |> Zipper.fromTree

                getDatasetNamesForNamespace : Namespace.Code -> String
                getDatasetNamesForNamespace namespaceCode =
                    let
                        maybeDataset =
                            store.datasetsToNamespaces
                                |> RemoteData.toMaybe
                                |> Maybe.andThen
                                    (\datasetsToNamespaces ->
                                        XB2.Share.Data.Platform2.datasetsForNamespace datasetsToNamespaces store.lineages namespaceCode
                                            |> RemoteData.toMaybe
                                    )
                                |> Maybe.map (Set.Any.toList >> List.filterMap (Store.getFromAnyDict store.datasets))
                                |> Maybe.andThen List.head

                        maybePath =
                            maybeDataset
                                |> Maybe.andThen
                                    (\currentDataset ->
                                        datasetsZipper
                                            |> Zipper.openPath
                                                (\dataset item ->
                                                    case item of
                                                        DItem dItem ->
                                                            dataset.code == dItem.code

                                                        DFolder (Just (XB2.Share.Data.Platform2.DatasetFolder folder)) _ ->
                                                            List.member dataset.code folder.datasetCodes

                                                        DFolder Nothing _ ->
                                                            False
                                                )
                                                [ currentDataset ]
                                            |> Result.toMaybe
                                            |> Maybe.map (Tuple.pair currentDataset)
                                    )
                                |> Maybe.map
                                    (\( currentDataset, zipper ) ->
                                        let
                                            path =
                                                Zipper.getPath
                                                    (\item ->
                                                        case item of
                                                            DItem dItem ->
                                                                Just dItem.name

                                                            DFolder (Just (XB2.Share.Data.Platform2.DatasetFolder folder)) _ ->
                                                                Just folder.name

                                                            DFolder Nothing _ ->
                                                                Nothing
                                                    )
                                                    zipper
                                                    |> List.filterMap identity
                                        in
                                        path
                                            ++ [ currentDataset.name ]
                                            |> String.join " > "
                                    )
                                |> Maybe.map (\s -> s ++ " (" ++ Namespace.codeToString namespaceCode ++ ") ")
                    in
                    case maybePath of
                        Just path ->
                            path

                        Nothing ->
                            maybeDataset
                                |> Maybe.unwrap (Namespace.codeToString namespaceCode) .name

                makeBoldInMarkdown text =
                    "**" ++ text ++ "**"
            in
            "This combination of attributes contains incompatible data sets:\n - "
                ++ (ids |> List.map (getDatasetNamesForNamespace >> makeBoldInMarkdown) |> String.join "\n - ")


xbQueryErrorStringWithoutCodeTranslation : XBQueryError -> String
xbQueryErrorStringWithoutCodeTranslation err =
    case err of
        InvalidQuery error ->
            "Invalid query: " ++ error

        EmptyAudienceExpression ->
            "Empty audience expression"

        UniverseZero ->
            "Universe zero"

        InvalidProjectsCombination ids ->
            "This attribute is not compatible with the following studies:\n - "
                ++ (ids |> List.map Namespace.codeToString |> String.join "\n - ")


xbQueryErrorDecoder : Decoder XBQueryError
xbQueryErrorDecoder =
    CoreError.typeDecoder
        |> Decode.andThen
            (\errorType ->
                case errorType of
                    "invalid_query" ->
                        Decode.map InvalidQuery <|
                            Decode.field "error" Decode.string

                    "empty_audience_expression" ->
                        Decode.succeed EmptyAudienceExpression

                    "universe_zero" ->
                        Decode.succeed UniverseZero

                    "invalid_projects_combination" ->
                        Decode.map InvalidProjectsCombination <|
                            Decode.at [ "meta", "incompatible_projects" ]
                                (Decode.list Namespace.codeDecoder)

                    {- Let's be less strict about the error type here to avoid forward
                       compatibility issues... We lose guarantees, but it's better than
                       crashing in prod and quickly having to add new decoders...
                    -}
                    _ ->
                        Decode.succeed
                            (InvalidQuery
                                ("The query for this intersection was not successful: "
                                    ++ errorType
                                )
                            )
            )


mapXBAudiences :
    ({ row : AudienceIntersection, col : AudienceIntersection }
     -> { row : AudienceIntersection, col : AudienceIntersection }
    )
    -> IntersectResult
    -> IntersectResult
mapXBAudiences fn result =
    { result | audiences = fn result.audiences }


swapXBAudiences :
    { row : AudienceIntersection, col : AudienceIntersection }
    -> { row : AudienceIntersection, col : AudienceIntersection }
swapXBAudiences { row, col } =
    { row = col
    , col = row
    }


xbQueryErrorToErrorType : XBQueryError -> String
xbQueryErrorToErrorType err =
    case err of
        InvalidQuery _ ->
            "invalid_query"

        EmptyAudienceExpression ->
            "empty_audience_expression"

        UniverseZero ->
            "universe_zero"

        InvalidProjectsCombination _ ->
            "invalid_projects_combination"


getValue : Metric -> IntersectResult -> Float
getValue metric result =
    case metric of
        RowPercentage ->
            result.audiences.col.intersectPercentage

        ColumnPercentage ->
            result.audiences.row.intersectPercentage

        Index ->
            result.intersection.index

        Sample ->
            toFloat result.intersection.sample

        Size ->
            toFloat result.intersection.size


formatValue :
    IntersectResult
    -> Metric
    ->
        { exactRespondentNumber : Bool
        , exactUniverseNumber : Bool
        , isForRowMetricView : Bool
        }
    -> String
formatValue result metric { exactRespondentNumber, exactUniverseNumber, isForRowMetricView } =
    let
        value : Float
        value =
            getValue metric result
    in
    case metric of
        RowPercentage ->
            String.fromFloat value ++ "%"

        ColumnPercentage ->
            String.fromFloat value ++ "%"

        Index ->
            String.fromFloat value

        Sample ->
            if exactRespondentNumber then
                FormatNumber.format
                    { usLocale
                        | decimals = FormatNumber.Locales.Exact 0
                    }
                    value

            else
                FormatNumber.formatNumber value

        Size ->
            if exactUniverseNumber then
                if isForRowMetricView then
                    FormatNumber.format
                        { usLocale
                            | decimals = FormatNumber.Locales.Exact 0
                        }
                        value

                else
                    FormatNumber.formatNumberForExactCount value

            else
                FormatNumber.formatNumber value


getCoefficientStretchingInfo : XB2.Share.Store.Platform2.Store -> IntersectResult -> Maybe String
getCoefficientStretchingInfo store result =
    let
        translateCodes codes =
            case String.split "___" codes of
                [ wave, locationCode ] ->
                    wave
                        ++ " / "
                        ++ (Store.get store.locations (Id.fromString locationCode)
                                |> Maybe.map .name
                                |> Maybe.withDefault locationCode
                           )

                _ ->
                    codes
    in
    result.stretching
        |> Maybe.map
            (\stretching ->
                "__Stretching coefficients__\n\n"
                    ++ (stretching
                            |> Dict.toList
                            |> List.map
                                (\( codes, values ) ->
                                    "- "
                                        ++ translateCodes codes
                                        ++ ":"
                                        ++ " coef **"
                                        ++ String.fromFloat values.coefficient
                                        ++ "**"
                                        ++ ", total **"
                                        ++ String.fromFloat values.total
                                        ++ "**"
                                )
                            |> String.join "\n"
                       )
            )



-- ↓ BaseAudienceParam ↓


{-| Which BaseAudience we're sending into the request.

  - `DefaultBase`: Will send no `base_audience` field.
  - `Base baseAudience`: Will send the `base_audience` field with the given
    `BaseAudience`.

-}
type BaseAudienceParam
    = DefaultBase
    | Base BaseAudience.BaseAudience


{-| Usual encoding for BaseAudience. Having all the data.
-}
encodeBaseAudience : BaseAudience.BaseAudience -> Encode.Value
encodeBaseAudience base =
    Encode.object
        [ ( "id"
          , BaseAudience.getId base
                |> AudienceItemId.toString
                |> Encode.string
          )
        , ( "expression", Expression.encode <| BaseAudience.getExpression base )
        ]


{-| Helper function in the body encoding. We may not have the field present, so we work
with values wrapped inside a list to append them later.
-}
converBaseAudienceParamToKeyValuePair : BaseAudienceParam -> List ( String, Encode.Value )
converBaseAudienceParamToKeyValuePair param =
    case param of
        DefaultBase ->
            []

        Base baseAudience ->
            [ ( "base_audience", encodeBaseAudience baseAudience ) ]



-- ↑ BaseAudienceParam ↑


encodeAudienceParamForBulk :
    { id : AudienceItemId.AudienceItemId
    , expression : Expression.Expression
    }
    -> Encode.Value
encodeAudienceParamForBulk param =
    Encode.object
        [ ( "id", AudienceItemId.toString param.id |> Encode.string )
        , ( "expression", Expression.encode param.expression )
        ]



-- ↑ AudienceParam ↑
-- ↓ BulkIntersectionResponse ↓


type alias BulkIntersectResult =
    { rowIndex : Int
    , colIndex : Int
    , intersection : Intersect
    , audiences :
        { row : AudienceIntersection
        , col : AudienceIntersection
        }
    }


type alias BulkIntersectFailure =
    { rowId : String
    , colId : String
    , error : XBQueryError
    }


type BulkIntersectionResponse
    = BulkIntersectionSuccess BulkIntersectResult
    | BulkQueryError BulkIntersectFailure


bulkIntersectionResponseDecoder : Decode.Decoder BulkIntersectionResponse
bulkIntersectionResponseDecoder =
    Decode.oneOf
        [ Decode.map BulkIntersectionSuccess bulkIntersectResultDecoder
        , Decode.map BulkQueryError bulkIntersectFailureDecoder

        -- vv Backward compatibility with the old API vv
        , Decode.map BulkQueryError
            (Decode.map3 BulkIntersectFailure
                (Decode.maybe (Decode.at [ "row", "id" ] Decode.string)
                    |> Decode.map (Maybe.withDefault "0")
                )
                (Decode.maybe (Decode.at [ "column", "id" ] Decode.string)
                    |> Decode.map (Maybe.withDefault "0")
                )
                (Decode.field "error" Decode.string
                    |> Decode.map InvalidQuery
                )
            )

        -- vv Fallback to not show the failure modal vv
        -- TODO: Sometimes `intersect` field is not present in the response. We should create a new NoAvailableData error type to handle it properly.
        , Decode.map BulkQueryError
            (Decode.map3 BulkIntersectFailure
                (Decode.maybe (Decode.at [ "row", "id" ] Decode.string)
                    |> Decode.map (Maybe.withDefault "0")
                )
                (Decode.maybe (Decode.at [ "column", "id" ] Decode.string)
                    |> Decode.map (Maybe.withDefault "0")
                )
                (Decode.succeed (InvalidQuery "Unknown error"))
            )
        ]


bulkIntersectResultDecoder : Decode.Decoder BulkIntersectResult
bulkIntersectResultDecoder =
    Decode.succeed BulkIntersectResult
        |> Decode.andMap (Decode.field "row_index" Decode.int)
        |> Decode.andMap (Decode.field "column_index" Decode.int)
        |> Decode.andMap (Decode.field "intersect" intersectDecoder)
        |> Decode.andMap
            (Decode.field "audiences"
                (Decode.succeed (\row col -> { row = row, col = col })
                    |> Decode.andMap (Decode.field "row" audienceIntersectionDecoder)
                    |> Decode.andMap (Decode.field "column" audienceIntersectionDecoder)
                )
            )


{-| Sets default rowId & columnId as `"0"` as in the API.
-}
bulkIntersectFailureDecoder : Decode.Decoder BulkIntersectFailure
bulkIntersectFailureDecoder =
    Decode.map3 BulkIntersectFailure
        (Decode.maybe (Decode.at [ "row", "id" ] Decode.string)
            |> Decode.map (Maybe.withDefault "0")
        )
        (Decode.maybe (Decode.at [ "column", "id" ] Decode.string)
            |> Decode.map (Maybe.withDefault "0")
        )
        (Decode.field "error" xbQueryErrorDecoder)



-- ↑ BulkIntersectionResponse ↑


type alias BulkAudienceParams =
    { rows : List { id : AudienceItemId, expression : Expression }
    , columns : List { id : AudienceItemId, expression : Expression }
    , baseAudience : BaseAudienceParam
    , locations : List Labels.LocationCode
    , waves : List Labels.WaveCode
    }


{-| Like the /intersection API but meant to handle a bunch of rows/columns at once.
-}
postCrosstab :
    { flags : XB2.Share.Config.Flags
    , requestOrigin : RequestOrigin
    , trackerId : Tracked.TrackerId
    , bulkParams : BulkAudienceParams
    }
    -> XB2.Share.Gwi.Http.HttpCmd Decode.Error (List BulkIntersectionResponse)
postCrosstab params =
    let
        url : String
        url =
            case params.requestOrigin of
                Table ->
                    host params.flags ++ namespace ++ "/crosstab"

                Export ->
                    host params.flags ++ namespace ++ "/crosstab/export"

                Heatmap ->
                    host params.flags ++ namespace ++ "/crosstab/heatmap"
    in
    Http.request
        { method = "POST"
        , headers = [ Auth.header params.flags.token ]
        , url = url
        , body =
            Http.jsonBody <|
                Encode.object <|
                    [ ( "columns"
                      , Encode.list encodeAudienceParamForBulk params.bulkParams.columns
                      )
                    , ( "rows"
                      , Encode.list encodeAudienceParamForBulk params.bulkParams.rows
                      )
                    , ( "locations", Encode.list Id.encode params.bulkParams.locations )
                    , ( "waves", Encode.list Id.encode params.bulkParams.waves )
                    ]
                        ++ converBaseAudienceParamToKeyValuePair
                            params.bulkParams.baseAudience
        , expect = XB2.Share.Gwi.Http.expectJsonSeq bulkIntersectionResponseDecoder
        , timeout = Nothing
        , tracker = Just params.trackerId
        }
