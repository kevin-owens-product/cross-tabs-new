module XB2.Api.V1.Crosstabs exposing (Attribute, AttributeWithIncompatibilities, Cell, CellResponse, Filters, GetIncompatibilitiesBulkRequest, GetIncompatibilitiesBulkResponse, Incompatibility, postIncompatibilitiesBulk)

import AssocSet
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import XB2.Data.AudienceItemId as AudienceItemId
import XB2.Data.Namespace as Namespace
import XB2.Data.Suffix as Suffix
import XB2.Data.Zod.Nullish as Nullish
import XB2.RemoteData.Tracked as Tracked
import XB2.Share.Config
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Id as Id
import XB2.Share.Data.Labels as Labels
import XB2.Share.Gwi.Http as GwiHttp
import XB2.Utils.AssocSet as AssocSet


host : XB2.Share.Config.Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api



-- Request


type alias GetIncompatibilitiesBulkRequest =
    { cells : AssocSet.Set Cell
    , filters : Filters
    }


encodeGetIncompatibilitiesBulkRequest : GetIncompatibilitiesBulkRequest -> Encode.Value
encodeGetIncompatibilitiesBulkRequest request =
    Encode.object
        [ ( "cells", AssocSet.encode encodeCell request.cells )
        , ( "filters", encodeFilters request.filters )
        , ( "hard_filters_on", Encode.bool False )
        ]


type alias Filters =
    { locationCodes : AssocSet.Set Labels.LocationCode
    , waveCodes : AssocSet.Set Labels.WaveCode
    }


encodeFilters : Filters -> Encode.Value
encodeFilters filters =
    Encode.object
        [ ( "location_codes", AssocSet.encode Id.encode filters.locationCodes )
        , ( "wave_codes", AssocSet.encode Id.encode filters.waveCodes )
        ]


type alias Cell =
    { rowId : Maybe AudienceItemId.AudienceItemId
    , columnId : Maybe AudienceItemId.AudienceItemId
    , attributes : AssocSet.Set Attribute
    }


encodeCell : Cell -> Encode.Value
encodeCell cell =
    Encode.object <|
        ( "attributes", AssocSet.encode encodeAttribute cell.attributes )
            :: (case cell.rowId of
                    Just rowId ->
                        [ ( "row_id", Encode.string (AudienceItemId.toString rowId) ) ]

                    Nothing ->
                        []
               )
            ++ (case cell.columnId of
                    Just columnId ->
                        [ ( "column_id", Encode.string (AudienceItemId.toString columnId) ) ]

                    Nothing ->
                        []
               )


type alias Attribute =
    { questionCode : Labels.ShortQuestionCode
    , datapointCode : Labels.ShortDatapointCode
    , maybeSuffixCode : Maybe Suffix.Code
    , namespaceCode : Namespace.Code
    }


encodeAttribute : Attribute -> Encode.Value
encodeAttribute attribute =
    Encode.object <|
        [ ( "question_code", Id.encode attribute.questionCode )
        , ( "datapoint_code", Id.encode attribute.datapointCode )
        , ( "namespace_code", Namespace.encodeCode attribute.namespaceCode )
        ]
            ++ (case attribute.maybeSuffixCode of
                    Just suffixCode ->
                        [ ( "suffix_code", Suffix.encodeCodeAsString suffixCode ) ]

                    Nothing ->
                        []
               )



-- Response


type alias GetIncompatibilitiesBulkResponse =
    { cellsResponse : AssocSet.Set CellResponse
    }


getIncompatibilitiesBulkResponseDecoder : Decode.Decoder GetIncompatibilitiesBulkResponse
getIncompatibilitiesBulkResponseDecoder =
    Decode.map GetIncompatibilitiesBulkResponse
        (Decode.field "cells_response" (AssocSet.decode cellResponseDecoder))


type alias CellResponse =
    { rowId : AudienceItemId.AudienceItemId
    , columnId : AudienceItemId.AudienceItemId
    , attributes : AssocSet.Set AttributeWithIncompatibilities
    }


cellResponseDecoder : Decode.Decoder CellResponse
cellResponseDecoder =
    Decode.map3 CellResponse
        (Decode.field "row_id" AudienceItemId.decoderWithoutField)
        (Decode.field "column_id" AudienceItemId.decoderWithoutField)
        (Decode.field "attributes" (AssocSet.decode attributeWithIncompatibilitiesDecoder))


type alias AttributeWithIncompatibilities =
    { questionCode : Labels.ShortQuestionCode
    , datapointCode : Labels.ShortDatapointCode
    , suffixCode : Nullish.Nullish Suffix.Code
    , namespaceCode : Namespace.Code
    , incompatibilities : AssocSet.Set Incompatibility

    {- This field avoids incompatibilities to be shown in the UI when there's some
       combination of "waves"/"locations" questions that need to be skipped. (See: https://globalwebindex.atlassian.net/browse/AUR-1007)
    -}
    , questionExceptionsSkip : Nullish.Nullish Bool
    }


attributeWithIncompatibilitiesDecoder : Decode.Decoder AttributeWithIncompatibilities
attributeWithIncompatibilitiesDecoder =
    Decode.map6 AttributeWithIncompatibilities
        (Decode.field "question_code" Id.decode)
        (Decode.field "datapoint_code" Id.decode)
        (Decode.oneOf
            [ Nullish.decodeField "suffix_code" Suffix.codeDecoder

            -- Fallback in case we get `""`
            , Decode.succeed Nullish.Undefined
            ]
        )
        (Decode.field "namespace_code" Namespace.codeDecoder)
        (Decode.field "incompatibilities"
            (Decode.nullable (AssocSet.decode incompatibilityDecoder)
                |> Decode.map (Maybe.withDefault AssocSet.empty)
            )
        )
        (Nullish.decodeField "question_exceptions_skip" Decode.bool)


type alias Incompatibility =
    { locationCode : Labels.LocationCode
    , waveCodes : AssocSet.Set Labels.WaveCode
    }


incompatibilityDecoder : Decode.Decoder Incompatibility
incompatibilityDecoder =
    Decode.map2 Incompatibility
        (Decode.field "location_code" Id.decode)
        (Decode.field "wave_codes"
            (Decode.nullable
                (Decode.list Id.decode
                    |> Decode.map AssocSet.fromList
                )
                |> Decode.map (Maybe.withDefault AssocSet.empty)
            )
        )


{-| Like the /intersection API but meant to handle a bunch of rows/columns at once.
-}
postIncompatibilitiesBulk :
    { flags : XB2.Share.Config.Flags
    , trackerId : Tracked.TrackerId
    , request : GetIncompatibilitiesBulkRequest
    }
    -> GwiHttp.HttpCmd Never GetIncompatibilitiesBulkResponse
postIncompatibilitiesBulk params =
    Http.request
        { method = "POST"
        , headers = [ Auth.header params.flags.token ]
        , url = host params.flags ++ "/platform/v1/crosstabs/incompatibilities-bulk"
        , body = Http.jsonBody (encodeGetIncompatibilitiesBulkRequest params.request)
        , expect = GwiHttp.expectJson identity getIncompatibilitiesBulkResponseDecoder
        , timeout = Nothing
        , tracker = Just params.trackerId
        }
