module XB2.Data.Average exposing
    ( Average(..)
    , AverageTimeFormat(..)
    , averageTimeFormatDecoder
    , averageTimeToString
    , decoder
    , encode
    , encodeAverageTimeFormat
    , getDatasets
    , getQuestionCode
    , switchTimeFormat
    )

import BiDict.Assoc exposing (BiDict)
import Dict.Any
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode exposing (Value)
import RemoteData exposing (WebData)
import XB2.Data.Dataset as Dataset
import XB2.Data.Namespace as Namespace
import XB2.Share.Data.Id
import XB2.Share.Data.Labels
    exposing
        ( NamespaceAndQuestionCode
        , NamespaceLineage
        , QuestionAndDatapointCode
        )
import XB2.Share.Data.Platform2


type Average
    = AvgWithoutSuffixes NamespaceAndQuestionCode
    | AvgWithSuffixes NamespaceAndQuestionCode QuestionAndDatapointCode


type AverageTimeFormat
    = FloatNumber
    | HHmm


encode : Average -> Value
encode average =
    Encode.object <|
        case average of
            AvgWithoutSuffixes questionId ->
                [ ( "question", XB2.Share.Data.Id.encode questionId ) ]

            AvgWithSuffixes questionId datapointCode ->
                [ ( "question", XB2.Share.Data.Id.encode questionId )
                , ( "datapoint", XB2.Share.Data.Id.encode datapointCode )
                ]


decoder : Decoder Average
decoder =
    Decode.maybe (Decode.field "datapoint" XB2.Share.Data.Id.decode)
        |> Decode.andThen
            (\maybeDatapointCode ->
                case maybeDatapointCode of
                    Nothing ->
                        Decode.succeed AvgWithoutSuffixes
                            |> Decode.andMap (Decode.field "question" XB2.Share.Data.Id.decode)

                    Just datapointCode ->
                        Decode.succeed AvgWithSuffixes
                            |> Decode.andMap (Decode.field "question" XB2.Share.Data.Id.decode)
                            |> Decode.andMap (Decode.succeed datapointCode)
            )


getQuestionCode : Average -> NamespaceAndQuestionCode
getQuestionCode average =
    case average of
        AvgWithoutSuffixes questionCode_ ->
            questionCode_

        AvgWithSuffixes questionCode_ _ ->
            questionCode_


switchTimeFormat : AverageTimeFormat -> AverageTimeFormat
switchTimeFormat averageTimeFormat =
    case averageTimeFormat of
        FloatNumber ->
            HHmm

        HHmm ->
            FloatNumber


averageTimeToString : AverageTimeFormat -> Float -> String
averageTimeToString averageTimeFormat value =
    case averageTimeFormat of
        FloatNumber ->
            String.fromFloat value

        HHmm ->
            let
                {- ATC-3750: just showing hours and minutes isn't correct:
                   the best resolution we can get from value 1.01 in the
                   HH:MM:SS format is 01:00:36, but we want to show it
                   in the HH:MM format, and round the minutes correctly.

                   So for the value 1.01 (01:00:36) we really want to show
                   01:01 to the user.
                -}
                hours : Int
                hours =
                    floor value

                minutes : Int
                minutes =
                    round ((value - toFloat hours) * 60)
            in
            [ hours, minutes ]
                |> List.map (String.fromInt >> String.padLeft 2 '0')
                |> String.join ":"


averageTimeFormatDecoder : Decoder AverageTimeFormat
averageTimeFormatDecoder =
    let
        decode format =
            case format of
                "hhmm" ->
                    Decode.succeed HHmm

                "float" ->
                    Decode.succeed FloatNumber

                _ ->
                    Decode.succeed HHmm
    in
    Decode.andThen decode Decode.string


encodeAverageTimeFormat : AverageTimeFormat -> Value
encodeAverageTimeFormat format =
    Encode.string <|
        case format of
            HHmm ->
                "hhmm"

            FloatNumber ->
                "float"


getDatasets :
    BiDict Dataset.Code Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> Average
    -> WebData (List Dataset.Code)
getDatasets datasetsToNamespaces lineages average =
    getQuestionCode average
        |> XB2.Share.Data.Labels.parseNamespaceCode
        |> List.singleton
        |> XB2.Share.Data.Platform2.datasetCodesForNamespaceCodes datasetsToNamespaces lineages
