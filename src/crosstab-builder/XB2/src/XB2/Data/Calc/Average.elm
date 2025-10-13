module XB2.Data.Calc.Average exposing
    ( AverageResult
    , request
    )

import Cmd.Extra as Cmd
import Http
import Json.Decode as Decode
import Json.Decode.Extra as Decode
import Json.Encode as Encode exposing (Value)
import Json.Encode.Extra as Encode
import List.NonEmpty as NonemptyList
import Maybe.Extra as Maybe
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.Average exposing (Average(..))
import XB2.Data.BaseAudience as BaseAudience exposing (BaseAudience)
import XB2.Data.Calc.AudienceIntersect as AudienceIntersect {- TODO what about our own error type? -} exposing (XBQueryError)
import XB2.Data.Suffix as Suffix
import XB2.Data.Zod.Nullish as Nullish
import XB2.RemoteData.Tracked exposing (TrackerId)
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Id
import XB2.Share.Data.Labels
    exposing
        ( LocationCode
        , Question
        , QuestionAndDatapointCode
        , QuestionAveragesUnit
        , WaveCode
        )
import XB2.Share.Gwi.Http exposing (HttpCmd)


type alias AverageResult =
    { value : Float
    , unit : QuestionAveragesUnit
    }


host : Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api


namespace : String
namespace =
    "/v2/query"


extractCodesWithMidpoints : List Suffix.Suffix -> List Suffix.Code
extractCodesWithMidpoints suffixes =
    List.filterMap (\{ code, midpoint } -> Maybe.map (\_ -> code) (Nullish.toMaybe midpoint)) suffixes


encode :
    Question
    -> Maybe BaseAudience
    -> Maybe Expression
    -> List LocationCode
    -> List WaveCode
    -> Average
    -> Result String Value
encode question baseAudience maybeAudience locationCodes waveCodes average =
    case average of
        AvgWithoutSuffixes questionCode ->
            let
                datapointCodes : List QuestionAndDatapointCode
                datapointCodes =
                    question.datapoints
                        |> NonemptyList.toList
                        |> List.filterMap
                            (\{ code, midpoint } ->
                                if midpoint == Nothing then
                                    Nothing

                                else
                                    Just code
                            )
            in
            if List.isEmpty datapointCodes then
                Err <| "Missing midpoint for all datapoints (" ++ XB2.Share.Data.Id.unwrap questionCode ++ ")"

            else
                [ ( "question", XB2.Share.Data.Id.encode questionCode )
                , ( "datapoints", Encode.list XB2.Share.Data.Id.encode datapointCodes )
                , ( "suffixes", Encode.list identity [] )
                , ( "audience", Maybe.unwrap Encode.null Expression.encode maybeAudience )
                , ( "locations", Encode.list XB2.Share.Data.Id.encode locationCodes )
                , ( "waves", Encode.list XB2.Share.Data.Id.encode waveCodes )
                , ( "base_audience", Encode.maybe (BaseAudience.getExpression >> Expression.encode) baseAudience )
                ]
                    |> Encode.object
                    |> Ok

        AvgWithSuffixes questionCode datapointCode ->
            let
                suffixCodes : List Suffix.Code
                suffixCodes =
                    question.suffixes
                        |> Maybe.map
                            (NonemptyList.toList
                                >> extractCodesWithMidpoints
                            )
                        |> Maybe.withDefault []
            in
            if List.isEmpty suffixCodes then
                Err <| "Missing midpoint for all suffixes (" ++ XB2.Share.Data.Id.unwrap questionCode ++ ")"

            else
                [ ( "question", XB2.Share.Data.Id.encode questionCode )
                , ( "datapoints", Encode.list XB2.Share.Data.Id.encode [ datapointCode ] )
                , ( "suffixes", Encode.list Suffix.encodeCodeAsString suffixCodes )
                , ( "audience", Maybe.unwrap Encode.null Expression.encode maybeAudience )
                , ( "locations", Encode.list XB2.Share.Data.Id.encode locationCodes )
                , ( "waves", Encode.list XB2.Share.Data.Id.encode waveCodes )
                , ( "base_audience", Encode.maybe (BaseAudience.getExpression >> Expression.encode) baseAudience )
                ]
                    |> Encode.object
                    |> Ok


request :
    Flags
    -> Question
    -> Maybe BaseAudience
    -> List LocationCode
    -> List WaveCode
    -> TrackerId
    -> Average
    -> Maybe Expression
    -> QuestionAveragesUnit
    -> HttpCmd XBQueryError AverageResult
request ({ token } as flags) question baseAudience locations waveCodes trackerId average maybeAudience unit =
    if question.averageSupport then
        -- https://github.com/GlobalWebIndex/core-next/blob/6b660545254d6844757f3449f7f86eb1d9392d0f/services/query-es/swagger/average_query.yaml
        case encode question baseAudience maybeAudience locations waveCodes average of
            Ok encodedBody ->
                Http.request
                    { method = "POST"
                    , headers = [ Auth.header token ]
                    , url = host flags ++ namespace ++ "/average"
                    , body = Http.jsonBody encodedBody
                    , expect =
                        XB2.Share.Gwi.Http.expectErrorAwareJson
                            AudienceIntersect.xbQueryErrorDecoder
                            (Decode.succeed AverageResult
                                |> Decode.andMap (Decode.field "average" Decode.float)
                                |> Decode.andMap (Decode.succeed unit)
                            )
                    , timeout = Nothing
                    , tracker = Just trackerId
                    }

            Err err ->
                Cmd.perform <| Err <| XB2.Share.Gwi.Http.OtherError <| XB2.Share.Gwi.Http.AveragesDataIssue err

    else
        Cmd.perform <| Err <| XB2.Share.Gwi.Http.OtherError XB2.Share.Gwi.Http.XBQuestionDoesntSupportAverages
