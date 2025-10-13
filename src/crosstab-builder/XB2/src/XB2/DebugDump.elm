module XB2.DebugDump exposing (dump)

import DateFormat
import Dict
import Dict.Any exposing (AnyDict)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import List.Extra as List
import List.NonEmpty.Zipper as Zipper
import RemoteData
import Set.Any
import Time exposing (Posix, Zone)
import XB2.Data as Data
import XB2.Data.Audience.Expression as Expression
import XB2.Data.AudienceCrosstab as ACrosstab
    exposing
        ( AudienceCrosstab
        , OriginalOrder(..)
        )
import XB2.Data.AudienceItem as AudienceItem
import XB2.Data.AudienceItemId as AudienceItemId exposing (AudienceItemId)
import XB2.Data.Average as Average
import XB2.Data.BaseAudience as BaseAudience
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect exposing (IntersectResult)
import XB2.Data.Caption as Caption
import XB2.Data.Crosstab as Crosstab
import XB2.Data.Metric as Metric exposing (Metric)
import XB2.Data.UndoEvent exposing (UndoEvent)
import XB2.Detail.Common exposing (Unsaved(..))
import XB2.RemoteData.Tracked exposing (RemoteData(..))
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Core.Error as CoreError
import XB2.Share.Data.Id exposing (IdDict)
import XB2.Share.Data.Labels
    exposing
        ( Category
        , CategoryId
        , CategoryIdTag
        , NamespaceAndQuestionCode
        , Question
        , QuestionAveragesUnit(..)
        )
import XB2.Share.Data.Labels.Category
import XB2.Share.Data.User
import XB2.Share.Gwi.Http exposing (Error(..))
import XB2.Share.Gwi.List as List
import XB2.Share.Store.Platform2
import XB2.Share.Store.Utils as Store
import XB2.Share.Time.Format
import XB2.Share.UndoRedo exposing (UndoRedo)
import XB2.Sort as Sort


dump :
    Flags
    ->
        { model
            | crosstabData :
                UndoRedo
                    UndoEvent
                    { data
                        | cellLoaderModel : { loaderModel | audienceCrosstab : AudienceCrosstab }
                        , projectMetadata : Data.XBProjectMetadata
                        , originalRows : OriginalOrder
                        , originalColumns : OriginalOrder
                    }
            , currentTime : Posix
            , timezone : Zone
            , unsaved : Unsaved
        }
    -> XB2.Share.Store.Platform2.Store
    -> String
dump flags model store =
    let
        { cellLoaderModel, projectMetadata, originalRows, originalColumns } =
            XB2.Share.UndoRedo.current model.crosstabData

        audienceCrosstab =
            cellLoaderModel.audienceCrosstab

        activeWaves =
            ACrosstab.getActiveWaves audienceCrosstab

        activeLocations =
            ACrosstab.getActiveLocations audienceCrosstab

        baseAudiences =
            ACrosstab.getBaseAudiences audienceCrosstab

        currentBaseAudience =
            Zipper.current baseAudiences

        keyToString { item } =
            itemToString item

        itemToString item =
            definitionToString <| AudienceItem.getDefinition item

        questionCodesPerDefinition : AudienceItem.AudienceItem -> List NamespaceAndQuestionCode
        questionCodesPerDefinition item =
            case AudienceItem.getDefinition item of
                Data.Expression expression ->
                    Expression.getQuestionCodes expression

                Data.Average average ->
                    [ Average.getQuestionCode average ]

        questionInfo : List NamespaceAndQuestionCode -> List String
        questionInfo questionCodes =
            let
                questions : List Question
                questions =
                    questionCodes
                        |> List.filterMap (\questionCode -> XB2.Share.Store.Platform2.getQuestionMaybe questionCode store)

                uniqueCategories : List Category
                uniqueCategories =
                    let
                        uniqueCategoryIds : List CategoryId
                        uniqueCategoryIds =
                            questions
                                |> List.fastConcatMap .categoryIds
                                |> List.uniqueBy XB2.Share.Data.Id.unwrap
                    in
                    Store.getByIds store.categories uniqueCategoryIds

                uniqueCategoryPaths : IdDict CategoryIdTag String
                uniqueCategoryPaths =
                    let
                        categories =
                            RemoteData.withDefault XB2.Share.Data.Id.emptyDict store.categories

                        formatPath path =
                            path
                                |> List.map .name
                                |> String.join " > "
                    in
                    uniqueCategories
                        |> List.map
                            (\category ->
                                ( category.id
                                , " - " ++ formatPath (XB2.Share.Data.Labels.Category.categoryPath category categories)
                                )
                            )
                        |> XB2.Share.Data.Id.dictFromList

                findCategoryPaths : Question -> List String
                findCategoryPaths question =
                    question.categoryIds
                        |> List.filterMap (\categoryId -> Dict.Any.get categoryId uniqueCategoryPaths)
            in
            questions
                |> List.map
                    (\question ->
                        let
                            questionCode =
                                "question code: " ++ XB2.Share.Data.Id.unwrap question.code

                            questionName =
                                "question name: " ++ question.name

                            categoryPaths =
                                String.join "\n" <|
                                    "category paths:"
                                        :: findCategoryPaths question
                        in
                        String.join "\n"
                            [ questionCode
                            , questionName
                            , categoryPaths
                            , "\n"
                            ]
                    )

        definitionToString definition =
            definition
                |> Data.encodeAudienceDefinition
                |> Tuple.mapSecond (Encode.encode 2)
                |> (\( type_, value ) -> type_ ++ ": " ++ value)

        expressionToString expression =
            Encode.encode 2 <| Expression.encode expression

        metadataToString : Http.Metadata -> String
        metadataToString metadata =
            [ "URL: " ++ metadata.url
            , "STATUS CODE: " ++ String.fromInt metadata.statusCode
            , "STATUS TEXT: " ++ metadata.statusText
            , "HEADERS:"
            , metadata.headers
                |> Dict.toList
                |> List.map (\( key, value ) -> "  " ++ key ++ ": " ++ value)
                |> String.join "\n"
            ]
                |> String.join "\n"

        unitToString : QuestionAveragesUnit -> String
        unitToString unit =
            case unit of
                AgreementScore ->
                    "(agreement score)"

                TimeInHours ->
                    "hours"

                OtherUnit unit_ ->
                    unit_

        cellMetricToString : IntersectResult -> Metric -> String
        cellMetricToString result metric =
            "  "
                ++ Metric.label metric
                ++ ": "
                ++ AudienceIntersect.formatValue result
                    metric
                    { exactRespondentNumber = False
                    , exactUniverseNumber = False
                    , isForRowMetricView = True
                    }

        cellRequestToString data successToString =
            case data of
                NotAsked ->
                    "NotAsked"

                Loading Nothing ->
                    "Loading"

                Loading (Just trackerId) ->
                    "Loading (tracker ID: " ++ trackerId ++ ")"

                Success result ->
                    successToString result

                Failure err ->
                    "Error: "
                        ++ (case err of
                                BadUrl string ->
                                    "BadUrl " ++ string

                                Timeout ->
                                    "Timeout"

                                NetworkError ->
                                    "NetworkError"

                                BadStatus metadata body ->
                                    [ "BadStatus"
                                    , metadataToString metadata
                                    , ""
                                    , "BODY:"
                                    , body
                                    ]
                                        |> String.join "\n"

                                BadBody metadata decodeError ->
                                    [ "BadBody"
                                    , metadataToString metadata
                                    , ""
                                    , "DECODE ERROR:"
                                    , Decode.errorToString decodeError
                                    ]
                                        |> String.join "\n"

                                GenericError uuid body genericError ->
                                    [ "Generic core-next error"
                                    , "  UUID:  " ++ uuid
                                    , "  ERROR: " ++ CoreError.errorToString genericError
                                    , "  BODY: " ++ body
                                    ]
                                        |> String.join "\n"

                                CustomError uuid body customError ->
                                    [ "Custom core-next error"
                                    , "  UUID:  " ++ uuid
                                    , "  ERROR: " ++ AudienceIntersect.xbQueryErrorStringWithoutCodeTranslation customError
                                    , "  BODY: " ++ body
                                    ]
                                        |> String.join "\n"

                                OtherError error ->
                                    [ "Other error (miscellanious)"
                                    , "  ERROR: " ++ XB2.Share.Gwi.Http.otherErrorToString error
                                    ]
                                        |> String.join "\n"
                           )

        incompatibilitiesToString incompatibilities =
            let
                resolveWaves waves =
                    if List.isEmpty waves then
                        "any of your selected waves"

                    else
                        waves
                            |> List.map .name
                            |> String.join ", "
            in
            incompatibilities
                |> List.map
                    (\i ->
                        "- Not asked in " ++ i.location.name ++ " in " ++ resolveWaves i.waves
                    )
                |> String.join "\n"

        cellToString : ACrosstab.Cell -> String
        cellToString cell =
            case cell.data of
                ACrosstab.AvAData data ->
                    cellRequestToString data.data
                        (\result ->
                            "Success AvA:"
                                :: List.map (cellMetricToString result) Metric.allMetrics
                                |> String.join "\n"
                        )
                        |> (++)
                            (case data.incompatibilities of
                                NotAsked ->
                                    "NotAsked"

                                Loading Nothing ->
                                    "Loading"

                                Loading (Just trackerId) ->
                                    "Loading (tracker ID: " ++ trackerId ++ ")"

                                Success result ->
                                    "Success incompatibilities: " ++ incompatibilitiesToString result

                                Failure err ->
                                    "Err:" ++ XB2.Share.Gwi.Http.errorToString never err
                            )

                ACrosstab.AverageData data ->
                    cellRequestToString data
                        (\averageResult ->
                            [ "Success Average:"
                            , "  " ++ String.fromFloat averageResult.value ++ " " ++ unitToString averageResult.unit
                            ]
                                |> String.join "\n"
                        )

        header =
            [ "XB Debug Dump"
            , "============="
            ]
                |> String.join "\n"

        timeInfo =
            [ "CURRENT TIME"
            , "------------"
            , DateFormat.format XB2.Share.Time.Format.format_D_MMM_YYYY_hh_mm model.timezone model.currentTime
            ]
                |> String.join "\n"

        userInfo =
            [ "USER"
            , "----"
            , "ID: " ++ flags.user.id
            , "ORGANISATION ID: "
                ++ (flags.user.organisationId
                        |> Maybe.withDefault "-"
                   )
            , "PLAN: " ++ XB2.Share.Data.User.planToString flags.user.planHandle
            , "CUSTOMER FLAGS: "
                ++ (flags.user.customerFeatures
                        |> Set.Any.toList
                        |> List.map XB2.Share.Data.User.featureToString
                        |> String.join ", "
                   )
            ]
                |> String.join "\n"

        flagsInfo =
            [ "FLAGS"
            , "-----"
            , "ENV: " ++ XB2.Share.Config.Main.stageToString flags.env
            , "FEATURE BRANCH: "
                ++ (flags.feature
                        |> Maybe.withDefault "-"
                   )
            ]
                |> String.join "\n"

        crosstabInfo =
            [ "CROSSTAB INFO"
            , "-------------"
            , "ACTIVE METRICS: "
                ++ (projectMetadata.activeMetrics
                        |> List.map Metric.toString
                        |> String.join ", "
                   )
            , "PROJECT ID: "
                ++ (case model.unsaved of
                        Unsaved ->
                            "-"

                        Saved projectId ->
                            XB2.Share.Data.Id.unwrap projectId

                        Edited projectId ->
                            XB2.Share.Data.Id.unwrap projectId ++ " (edited, unsaved)"

                        UnsavedEdited ->
                            "-"
                   )
            , "CURRENT BASE AUDIENCE:"
            , currentBaseAudience
                |> BaseAudience.getExpression
                |> expressionToString
            , "OTHER BASE AUDIENCES:"
            , baseAudiences
                |> Zipper.toList
                |> List.filter ((/=) currentBaseAudience)
                |> List.map (\base -> "- " ++ expressionToString (BaseAudience.getExpression base))
                |> String.join "\n"
            , "ACTIVE WAVES: "
                ++ (activeWaves
                        |> Set.Any.toList
                        |> List.map XB2.Share.Data.Id.unwrap
                        |> String.join ", "
                   )
            , "ACTIVE LOCATIONS: "
                ++ (activeLocations
                        |> Set.Any.toList
                        |> List.map XB2.Share.Data.Id.unwrap
                        |> String.join ", "
                   )
            , "SORTING:"
            , [ "    Rows: " ++ Sort.axisSortToDebugString projectMetadata.sort.rows
              , "    Cols: " ++ Sort.axisSortToDebugString projectMetadata.sort.columns
              ]
                |> String.join "\n"
            , "ROWS ORDER - BEFORE SORTING:"
            , case originalRows of
                NotSet ->
                    "none"

                OriginalOrder rows ->
                    rows
                        |> List.map (\key -> "  " ++ AudienceItem.getIdString key.item)
                        |> String.join "\n"
            , "ROWS ORDER - CURRENT:"
            , ACrosstab.getRows audienceCrosstab
                |> List.map (\key -> "  " ++ AudienceItem.getIdString key.item)
                |> String.join "\n"
            , "COLUMNS ORDER - BEFORE SORTING:"
            , case originalColumns of
                NotSet ->
                    "none"

                OriginalOrder columns ->
                    columns
                        |> List.map (\key -> "  " ++ AudienceItem.getIdString key.item)
                        |> String.join "\n"
            , "COLUMNS ORDER - CURRENT:"
            , ACrosstab.getColumns audienceCrosstab
                |> List.map (\key -> "  " ++ AudienceItem.getIdString key.item)
                |> String.join "\n"
            ]
                |> String.join "\n"

        crosstabRowsInfo =
            ("ROW DEFINITIONS"
                :: "---------------"
                :: "[0] Total row"
                :: expressionToString Expression.sizeExpression
                :: ""
                :: (audienceCrosstab
                        |> ACrosstab.getRows
                        |> List.indexedMap
                            (\i { item } ->
                                -- +1 because of totals off-by-one
                                [ "[" ++ String.fromInt (i + 1) ++ "] " ++ Caption.toString (AudienceItem.getCaption item)
                                , itemToString item
                                , ""
                                ]
                                    |> String.join "\n"
                            )
                   )
            )
                |> String.join "\n"

        crosstabColumnsInfo =
            ("COLUMN DEFINITIONS"
                :: "------------------"
                :: "[0] Total column"
                :: expressionToString Expression.sizeExpression
                :: ""
                :: (audienceCrosstab
                        |> ACrosstab.getColumns
                        |> List.indexedMap
                            (\i { item } ->
                                -- +1 because of totals off-by-one
                                [ "[" ++ String.fromInt (i + 1) ++ "] " ++ Caption.toString (AudienceItem.getCaption item)
                                , itemToString item
                                , ""
                                ]
                                    |> String.join "\n"
                            )
                   )
            )
                |> String.join "\n"

        rowToIndex : AnyDict AudienceItemId.ComparableId AudienceItemId Int
        rowToIndex =
            audienceCrosstab
                |> ACrosstab.getRows
                -- +1 because of totals off-by-one
                |> List.indexedMap (\i { item } -> ( AudienceItem.getId item, i + 1 ))
                |> Dict.Any.fromList AudienceItemId.toComparable

        columnToIndex : AnyDict AudienceItemId.ComparableId AudienceItemId Int
        columnToIndex =
            audienceCrosstab
                |> ACrosstab.getColumns
                -- +1 because of totals off-by-one
                |> List.indexedMap (\i { item } -> ( AudienceItem.getId item, i + 1 ))
                |> Dict.Any.fromList AudienceItemId.toComparable

        totalsCellsInfo =
            ("TOTALS CELLS"
                :: (audienceCrosstab
                        |> ACrosstab.getTotals
                        |> Dict.Any.toList
                        |> List.sortBy
                            (\( ( item, base ), _ ) ->
                                ( AudienceItemId.toComparable (AudienceItem.getId item)
                                , AudienceItemId.toComparable (BaseAudience.getId base)
                                )
                            )
                        |> List.map
                            (\( ( item, base ), cell ) ->
                                [ "------------"
                                , case
                                    ( Dict.Any.get (AudienceItem.getId item) rowToIndex
                                    , Dict.Any.get (AudienceItem.getId item) columnToIndex
                                    )
                                  of
                                    ( Just rowIndex, Just colIndex ) ->
                                        "[r"
                                            ++ String.fromInt rowIndex
                                            ++ ", c0] or [r0, c"
                                            ++ String.fromInt colIndex
                                            ++ "], base: "
                                            ++ Caption.toString (BaseAudience.getCaption base)

                                    ( Just rowIndex, Nothing ) ->
                                        "[r"
                                            ++ String.fromInt rowIndex
                                            ++ ", c0], base: "
                                            ++ Caption.toString (BaseAudience.getCaption base)

                                    ( Nothing, Just colIndex ) ->
                                        "[r0, c"
                                            ++ String.fromInt colIndex
                                            ++ "], base: "
                                            ++ Caption.toString (BaseAudience.getCaption base)

                                    ( Nothing, Nothing ) ->
                                        "[r0, c0], base: "
                                            ++ Caption.toString (BaseAudience.getCaption base)
                                , "BASE:"
                                , base
                                    |> BaseAudience.getExpression
                                    |> expressionToString
                                , "ITEM:"
                                , itemToString item
                                , "RESULT:"
                                , cellToString cell
                                ]
                                    |> String.join "\n"
                            )
                   )
            )
                |> String.join "\n"

        crosstabCellsInfo =
            ("CROSSTAB CELLS"
                :: (audienceCrosstab
                        |> ACrosstab.getCrosstab
                        |> Crosstab.getValues
                        |> Dict.Any.toList
                        |> List.sortBy
                            (\( { row, col, base }, _ ) ->
                                ( ACrosstab.keyToComparable row
                                , ACrosstab.keyToComparable col
                                , AudienceItemId.toComparable (BaseAudience.getId base)
                                )
                            )
                        |> List.map
                            (\( { row, col, base }, cell ) ->
                                [ "--------------"
                                , Maybe.map2
                                    (\rowIndex colIndex ->
                                        "[r"
                                            ++ String.fromInt rowIndex
                                            ++ ", c"
                                            ++ String.fromInt colIndex
                                            ++ "], base: "
                                            ++ Caption.toString (BaseAudience.getCaption base)
                                    )
                                    (Dict.Any.get (AudienceItem.getId row.item) rowToIndex)
                                    (Dict.Any.get (AudienceItem.getId col.item) columnToIndex)
                                    |> Maybe.withDefault "[DEBUG DUMP BUG: can't find row/col indexes for this cell]"
                                , "ROW:"
                                , keyToString row
                                , "COL:"
                                , keyToString col
                                , "BASE:"
                                , base
                                    |> BaseAudience.getExpression
                                    |> expressionToString
                                , "RESULT:"
                                , cellToString cell
                                ]
                                    |> String.join "\n"
                            )
                   )
            )
                |> String.join "\n"

        questionsInfo =
            ("QUESTIONS USED IN CROSSTAB"
                :: "------------------"
                :: ((ACrosstab.getColumns audienceCrosstab ++ ACrosstab.getRows audienceCrosstab)
                        |> List.fastConcatMap (\{ item } -> questionCodesPerDefinition item)
                        |> List.uniqueBy XB2.Share.Data.Id.unwrap
                        |> List.sortBy XB2.Share.Data.Id.unwrap
                        |> questionInfo
                   )
            )
                |> String.join "\n"
    in
    [ header
    , timeInfo
    , userInfo
    , flagsInfo
    , crosstabInfo
    , crosstabRowsInfo
    , crosstabColumnsInfo
    , totalsCellsInfo
    , crosstabCellsInfo
    , questionsInfo
    ]
        |> String.join "\n\n\n"
