module XB2.Share.Data.Labels exposing
    ( CategoryId
    , CategoryIdTag
    , Datapoint
    , DatapointAndSuffixCode
    , DatapointAndSuffixCodeTag
    , Location
    , LocationCode
    , LocationCodeTag
    , NamespaceAndQuestionCode
    , NamespaceAndQuestionCodeTag
    , NamespaceLineage
    , Question
    , QuestionAndDatapointCode
    , QuestionAndDatapointCodeTag
    , QuestionAveragesUnit(..)
    , Region
    , RegionCode(..)
    , ShortDatapointCode
    , ShortDatapointCodeTag
    , ShortQuestionCode
    , ShortQuestionCodeTag
    , Wave
    , WaveCode
    , WaveCodeTag
    , WaveKind(..)
    , WaveQuarter(..)
    , WaveYear
    , addNamespaceToQuestionCode
    , addQuestionToDatapointCode
    , addQuestionToShortDatapointCode
    , addSuffixToDatapointCode
    , areNamespacesIncompatibleOrUnknown
    , averagesUnitDecoder
    , comparableRegionCode
    , compatibleNamespacesWithAll
    , compatibleTopLevelNamespaces
    , encodeAveragesUnit
    , getAllLocationsV2
    , getAllWavesV2
    , getFourMostRecentWaveCodes
    , getLineage
    , getLocationsForNamespace
    , getQuestionV2
    , getWavesForNamespaceV2
    , groupToRegion
    , locationsByRegions
    , mergeLineage
    , p2Separator
    , parseNamespaceCode
    , questionCodeToNamespaceCode
    , regionName
    , splitQuestionAndDatapointCode
    , splitQuestionAndDatapointCodeCheckingWavesQuestion
    , splitQuestionCode
    , waveYear
    , wavesByYears
    )

import Dict exposing (Dict)
import Dict.Any exposing (AnyDict)
import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode
import List.Extra as List
import List.NonEmpty as NonemptyList exposing (NonEmpty)
import RemoteData exposing (RemoteData(..), WebData)
import Set.Any
import Time exposing (Month(..), Posix)
import Time.Extra as Time
import Url.Builder
import XB2.Data.Namespace as Namespace
import XB2.Data.Suffix as Suffix
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Id exposing (Id, IdDict, IdSet)
import XB2.Share.Gwi.Http exposing (HttpCmd)
import XB2.Share.Gwi.List as List



-- HELPERS


host : Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api



-- QUESTIONS


type alias NamespaceAndQuestionCode =
    Id NamespaceAndQuestionCodeTag


type NamespaceAndQuestionCodeTag
    = NamespaceAndQuestionCodeTag


type alias ShortQuestionCode =
    Id ShortQuestionCodeTag


type ShortQuestionCodeTag
    = ShortQuestionCodeTag


type QuestionAveragesUnit
    = AgreementScore
    | TimeInHours
    | OtherUnit String


averagesUnitDecoder : Decoder QuestionAveragesUnit
averagesUnitDecoder =
    let
        decoder s =
            case s of
                "agreement score" ->
                    AgreementScore

                "hours" ->
                    TimeInHours

                _ ->
                    OtherUnit s
    in
    Decode.map decoder Decode.string


encodeAveragesUnit : QuestionAveragesUnit -> Encode.Value
encodeAveragesUnit unit =
    Encode.string <|
        case unit of
            AgreementScore ->
                "agreement score"

            TimeInHours ->
                "hours"

            OtherUnit string ->
                string


type alias Question =
    { code : ShortQuestionCode
    , longCode : NamespaceAndQuestionCode
    , namespaceCode : Namespace.Code
    , name : String
    , fullName : String
    , categoryIds : List CategoryId
    , suffixes : Maybe (NonEmpty Suffix.Suffix)
    , message : Maybe String
    , accessible : Bool
    , notice : Maybe String
    , averagesUnit : Maybe QuestionAveragesUnit
    , averageSupport : Bool
    , warning : Maybe String
    , knowledgeBase : Maybe String

    {- Made last because we have two decoders that only differ in this field.
       So they can reuse one common base.
    -}
    , datapoints : NonEmpty Datapoint
    }


getQuestionV2 : NamespaceAndQuestionCode -> Flags -> HttpCmd Never Question
getQuestionV2 namespaceAndQuestionCode flags =
    Http.request
        { method = "GET"
        , headers =
            [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v2", "questions", XB2.Share.Data.Id.unwrap namespaceAndQuestionCode ]
                [ Url.Builder.string "include" "categories,datapoints" ]
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity <| questionV2Decoder namespaceAndQuestionCode
        , timeout = Nothing
        , tracker = Nothing
        }


parseNamespaceCode : NamespaceAndQuestionCode -> Namespace.Code
parseNamespaceCode code =
    case String.split "." (XB2.Share.Data.Id.unwrap code) of
        [] ->
            Namespace.coreCode

        _ :: [] ->
            Namespace.coreCode

        h :: _ ->
            Namespace.codeFromString h


questionV2Decoder : NamespaceAndQuestionCode -> Decode.Decoder Question
questionV2Decoder wantedQuestionCode =
    let
        ( _, wantedShortQuestionCode ) =
            splitQuestionCode wantedQuestionCode

        unwrappedShortQuestionCode : String
        unwrappedShortQuestionCode =
            XB2.Share.Data.Id.unwrap wantedShortQuestionCode

        {- In this V2 API the datapoints' codes
           aren't returned as "q3_1" but as "1". The problem is that the rest
           of the world expects them to be like "q3_1" (saved audiences,
           dashboards, ...).

           So we add the question code back into the datapoint code. We
           currently don't have any use for the "short" normalized code. If we
           do, we can make two separate fields in Datapoint or something.
        -}
        fixDatapointCode : String -> QuestionAndDatapointCode
        fixDatapointCode =
            {- Written in this slightly-pointfree way to not do this `if`
               inside every datapoint but just once in this `let`.
            -}
            if unwrappedShortQuestionCode == "waves" then
                \datapointCode -> XB2.Share.Data.Id.fromString datapointCode

            else
                \datapointCode ->
                    XB2.Share.Data.Id.fromString
                        (unwrappedShortQuestionCode ++ "_" ++ datapointCode)

        v2DatapointDecoder : Decoder Datapoint
        v2DatapointDecoder =
            Decode.succeed Datapoint
                |> Decode.andMap (Decode.field "code" (Decode.map fixDatapointCode Decode.string))
                |> Decode.andMap (Decode.field "name" Decode.string)
                |> Decode.andMap
                    -- TODO perhaps this will get fixed later in ATC-3037
                    (Decode.field "accessible" Decode.bool
                        |> Decode.withDefault False
                    )
                |> Decode.andMap (Decode.maybe (Decode.field "midpoint" Decode.float))
                |> Decode.andMap (Decode.field "order" Decode.float)

        v2CategoryIdDecoder : Decoder CategoryId
        v2CategoryIdDecoder =
            {- Category here actually contains all the data we get from /api/categories
               but we only care about the id.
            -}
            Decode.field "id" XB2.Share.Data.Id.decode

        averagesSupportDecoder : Decoder Bool
        averagesSupportDecoder =
            Decode.list Decode.string
                |> Decode.map (List.member "support_averages")
    in
    Decode.succeed
        (\code namespaceCode name fullName categoryIds suffixes message accessible notice averagesUnit averageSupport warning knowledgeBase datapoints ->
            { code = code
            , longCode = wantedQuestionCode
            , namespaceCode = namespaceCode
            , name = name
            , fullName = fullName
            , categoryIds = categoryIds
            , suffixes = suffixes
            , message = message
            , accessible = accessible
            , notice = notice
            , averagesUnit = averagesUnit
            , averageSupport = averageSupport
            , warning = warning
            , knowledgeBase = knowledgeBase
            , datapoints = datapoints
            }
        )
        |> Decode.andMap (Decode.at [ "question", "code" ] XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.at [ "question", "namespace_code" ] Namespace.codeDecoder)
        |> Decode.andMap (Decode.at [ "question", "name" ] Decode.string)
        |> Decode.andMap (Decode.at [ "question", "description" ] Decode.string)
        |> Decode.andMap (Decode.at [ "question", "categories" ] (Decode.list v2CategoryIdDecoder))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "suffixes" ] (NonemptyList.decodeList Suffix.decoder)))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "message" ] Decode.string))
        |> Decode.andMap
            -- TODO perhaps this will get fixed later in ATC-3037
            (Decode.at [ "question", "accessible" ] Decode.bool
                |> Decode.withDefault False
            )
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "notice" ] Decode.string))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "unit" ] averagesUnitDecoder))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "flags" ] averagesSupportDecoder) |> Decode.map (Maybe.withDefault False))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "warning" ] Decode.string))
        |> Decode.andMap (Decode.maybe (Decode.at [ "question", "knowledge_base" ] Decode.string))
        |> Decode.andMap (Decode.at [ "question", "datapoints" ] (NonemptyList.decodeList v2DatapointDecoder))



-- CATEGORIES


type CategoryIdTag
    = CategoryIdTag


type alias CategoryId =
    Id CategoryIdTag



-- DATAPOINTS


type QuestionAndDatapointCodeTag
    = QuestionAndDatapointCodeTag


type alias QuestionAndDatapointCode =
    Id QuestionAndDatapointCodeTag


type DatapointAndSuffixCodeTag
    = DatapointAndSuffixCodeTag


type alias DatapointAndSuffixCode =
    Id DatapointAndSuffixCodeTag


type ShortDatapointCodeTag
    = ShortDatapointCodeTag


type alias ShortDatapointCode =
    Id ShortDatapointCodeTag


type alias Datapoint =
    { code : QuestionAndDatapointCode
    , name : String
    , accessible : Bool
    , midpoint : Maybe Float
    , order : Float
    }



-- LOCATIONS


type LocationCodeTag
    = LocationCodeTag


{-| LocationCode == DatapointCode, but for clarity we keep it separate.
There are casting functions available below.
-}
type alias LocationCode =
    Id LocationCodeTag


type alias Location =
    { code : LocationCode
    , name : String
    , region : RegionCode
    , accessible : Bool
    }


locationsByNamespaceUrl : Flags -> String
locationsByNamespaceUrl flags =
    Url.Builder.crossOrigin (host flags)
        [ "v2", "locations", "filter" ]
        []


wavesByNamespaceUrl : Flags -> String
wavesByNamespaceUrl flags =
    Url.Builder.crossOrigin (host flags)
        [ "v2", "waves", "filter" ]
        []


encodeRequestForLocationsForNamespace : Namespace.Code -> Encode.Value
encodeRequestForLocationsForNamespace namespaceCode =
    Encode.object
        [ ( "namespaces"
          , Encode.list
                (\code ->
                    Encode.object
                        [ ( "code", Namespace.encodeCode code ) ]
                )
                [ namespaceCode ]
          )
        , ( "include", Encode.object [ ( "regions", Encode.bool True ) ] )
        ]


encodeRequestForWavesForNamespace : Namespace.Code -> Encode.Value
encodeRequestForWavesForNamespace namespaceCode =
    Encode.object
        [ ( "namespaces"
          , Encode.list
                (\code ->
                    Encode.object
                        [ ( "code", Namespace.encodeCode code ) ]
                )
                [ namespaceCode ]
          )
        ]


getLocationsForNamespace : Namespace.Code -> Flags -> HttpCmd Never (List Location)
getLocationsForNamespace namespaceCode flags =
    Http.request
        { method = "POST"
        , headers =
            [ Auth.header flags.token ]
        , url = locationsByNamespaceUrl flags
        , body = Http.jsonBody <| encodeRequestForLocationsForNamespace namespaceCode
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.field "locations" (Decode.list locationV2Decoder))
        , timeout = Nothing
        , tracker = Nothing
        }



--to get All the locations with V2 we have to send the body with an empty namespaces


getAllLocationsV2 : Flags -> HttpCmd Never (List Location)
getAllLocationsV2 flags =
    Http.request
        { method = "POST"
        , headers =
            [ Auth.header flags.token ]
        , url = locationsByNamespaceUrl flags
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "namespaces", Encode.list identity [] )
                    , ( "include"
                      , Encode.object
                            [ ( "regions", Encode.bool True ) ]
                      )
                    ]
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.field "locations" (Decode.list locationV2Decoder))
        , timeout = Nothing
        , tracker = Nothing
        }



--to get All the waves with V2 we have to send the body with an empty namespaces


getAllWavesV2 : Flags -> HttpCmd Never (List Wave)
getAllWavesV2 flags =
    Http.request
        { method = "POST"
        , headers =
            [ Auth.header flags.token ]
        , url = wavesByNamespaceUrl flags
        , body =
            Http.jsonBody <|
                Encode.object
                    [ ( "namespaces", Encode.list identity [] )
                    ]
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.field "waves" (Decode.list waveDecoder))
        , timeout = Nothing
        , tracker = Nothing
        }


locationV2Decoder : Decoder Location
locationV2Decoder =
    Decode.succeed Location
        |> Decode.andMap (Decode.field "code" XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.at [ "region", "area" ] regionCodeDecoder)
        |> Decode.andMap (Decode.field "accessible" Decode.bool)



-- REGION CODES


type RegionCode
    = Euro
    | Mea
    | Americas
    | Apac


type alias Region =
    { name : String
    , locations : IdDict LocationCodeTag Location
    }


regionCodeDecoder : Decoder RegionCode
regionCodeDecoder =
    let
        typeBuilder code =
            case code of
                "euro" ->
                    Decode.succeed Euro

                "mea" ->
                    Decode.succeed Mea

                "americas" ->
                    Decode.succeed Americas

                "apac" ->
                    Decode.succeed Apac

                _ ->
                    Decode.fail <| "Invalid area code " ++ code
    in
    Decode.andThen typeBuilder Decode.string


regionName : RegionCode -> String
regionName code =
    case code of
        Euro ->
            "Europe"

        Americas ->
            "Americas"

        Mea ->
            "Middle East & Africa"

        Apac ->
            "Asia Pacific"


comparableRegionCode : RegionCode -> Int
comparableRegionCode code =
    case code of
        Euro ->
            1

        Americas ->
            2

        Mea ->
            3

        Apac ->
            4


allRegions : Dict Int Region
allRegions =
    [ Americas, Apac, Euro, Mea ]
        |> List.map
            (\code ->
                ( comparableRegionCode code
                , { name = regionName code
                  , locations = XB2.Share.Data.Id.emptyDict
                  }
                )
            )
        |> Dict.fromList


addLocation : Location -> Dict Int Region -> Dict Int Region
addLocation location_ regions =
    let
        insertLocation region =
            { region
                | locations = Dict.Any.insert location_.code location_ region.locations
            }

        updater maybeRegion =
            case maybeRegion of
                Just region ->
                    Just <| insertLocation region

                Nothing ->
                    Dict.get (comparableRegionCode location_.region) allRegions
                        |> Maybe.map insertLocation
    in
    Dict.update (comparableRegionCode location_.region) updater regions


groupToRegion : List Location -> Dict Int Region
groupToRegion locations =
    List.foldr addLocation Dict.empty locations



-- WAVES


type WaveCodeTag
    = WaveCodeTag


type alias WaveCode =
    Id WaveCodeTag


type WaveKind
    = Quarter WaveQuarter
    | SlidingQuarter


type alias WaveYear =
    Int


type WaveQuarter
    = Q1
    | Q2
    | Q3
    | Q4


dateToQuarter : Posix -> Maybe WaveQuarter
dateToQuarter date =
    case Time.toMonth Time.utc date of
        Jan ->
            Just Q1

        Apr ->
            Just Q2

        Jul ->
            Just Q3

        Oct ->
            Just Q4

        _ ->
            Nothing


type alias Wave =
    { code : WaveCode
    , name : String -- eg. "Q1 2020"
    , accessible : Bool
    , kind : WaveKind
    , startDate : Posix
    , endDate : Posix
    }


waveYear : Wave -> WaveYear
waveYear { startDate } =
    Time.toYear Time.utc startDate


waveKindDecoder : Decoder WaveKind
waveKindDecoder =
    let
        quarterDecoder =
            Decode.field "date_start" dateDecoder
                |> Decode.andThen
                    (\date ->
                        Decode.fromMaybe
                            ("Unsuccessful quarter decoding from date " ++ Iso8601.fromTime date)
                            (dateToQuarter date)
                    )

        kindDecoder kind =
            case kind of
                "quarter" ->
                    Decode.map Quarter quarterDecoder

                "sliding_quarter" ->
                    Decode.succeed SlidingQuarter

                unknown ->
                    Decode.fail <| "Unsupported wave kind: " ++ unknown
    in
    Decode.field "kind" Decode.string
        |> Decode.andThen kindDecoder


dateDecoder : Decoder Posix
dateDecoder =
    Decode.andThen
        (\str ->
            -- Do this because new endpoint returns full ISO-8601 format (with T and Z)
            str
                |> String.split "T"
                |> List.take 1
                |> String.concat
                |> Time.fromIso8601Date Time.utc
                |> Decode.fromMaybe ("Invalid date: " ++ str)
        )
        Decode.string


waveDecoder : Decoder Wave
waveDecoder =
    Decode.succeed Wave
        |> Decode.andMap (Decode.field "code" XB2.Share.Data.Id.decode)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.field "accessible" Decode.bool)
        |> Decode.andMap waveKindDecoder
        |> Decode.andMap (Decode.field "date_start" dateDecoder)
        |> Decode.andMap (Decode.field "date_end" dateDecoder)


getWavesForNamespaceV2 : Namespace.Code -> Flags -> HttpCmd Never (List Wave)
getWavesForNamespaceV2 namespaceCode flags =
    Http.request
        { method = "POST"
        , headers =
            [ Auth.header flags.token ]
        , url = wavesByNamespaceUrl flags
        , body = Http.jsonBody <| encodeRequestForWavesForNamespace namespaceCode
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.field "waves" (Decode.list waveDecoder))
        , timeout = Nothing
        , tracker = Nothing
        }



-- Namespaces


questionCodeToNamespaceCode : NamespaceAndQuestionCode -> Namespace.Code
questionCodeToNamespaceCode =
    splitQuestionCode >> Tuple.first


{-|

  - "q20" -> ("core", "q20")
  - "gwi-ext.q418999" -> ("gwi-ext", "q418999")

-}
splitQuestionCode : NamespaceAndQuestionCode -> ( Namespace.Code, ShortQuestionCode )
splitQuestionCode namespaceAndQuestionCode =
    let
        unwrapped =
            XB2.Share.Data.Id.unwrap namespaceAndQuestionCode
    in
    case String.split "." unwrapped of
        [ namespaceCode, shortQuestionCode ] ->
            ( Namespace.codeFromString namespaceCode, XB2.Share.Data.Id.fromString shortQuestionCode )

        _ ->
            ( Namespace.coreCode, XB2.Share.Data.Id.fromString unwrapped )


{-|

  - ("core", "q20") -> "q20"
  - ("gwi-ext", "q418999") -> "gwi-ext.q418999"

-}
addNamespaceToQuestionCode : Namespace.Code -> ShortQuestionCode -> NamespaceAndQuestionCode
addNamespaceToQuestionCode namespaceCode shortQuestionCode =
    if namespaceCode == Namespace.coreCode then
        XB2.Share.Data.Id.fromString <| XB2.Share.Data.Id.unwrap shortQuestionCode

    else
        (Namespace.codeToString namespaceCode ++ "." ++ XB2.Share.Data.Id.unwrap shortQuestionCode)
            |> XB2.Share.Data.Id.fromString


getFourMostRecentWaveCodes : IdDict WaveCodeTag Wave -> IdSet WaveCodeTag
getFourMostRecentWaveCodes waves =
    waves
        |> getWavesSortedMostRecentFirst
        |> List.take 4
        |> List.map .code
        |> XB2.Share.Data.Id.setFromList


getWavesSortedMostRecentFirst : IdDict WaveCodeTag Wave -> List Wave
getWavesSortedMostRecentFirst dict =
    dict
        |> Dict.Any.values
        |> sortWavesMostRecentFirst


getWavesSortedLeastRecentFirst : IdDict WaveCodeTag Wave -> List Wave
getWavesSortedLeastRecentFirst dict =
    dict
        |> Dict.Any.values
        |> List.sortBy (.startDate >> Time.posixToMillis)


sortWavesMostRecentFirst : List Wave -> List Wave
sortWavesMostRecentFirst list =
    list
        |> List.reverseSortBy (.startDate >> Time.posixToMillis)


addQuestionToShortDatapointCode : ShortQuestionCode -> ShortDatapointCode -> QuestionAndDatapointCode
addQuestionToShortDatapointCode questionCode datapointCode =
    let
        questionCode_ : String
        questionCode_ =
            XB2.Share.Data.Id.unwrap questionCode

        datapointCode_ : String
        datapointCode_ =
            XB2.Share.Data.Id.unwrap datapointCode
    in
    case questionCode_ of
        "waves" ->
            XB2.Share.Data.Id.fromString datapointCode_

        _ ->
            questionCode_
                ++ "_"
                ++ datapointCode_
                |> XB2.Share.Data.Id.fromString


splitQuestionAndDatapointCode : QuestionAndDatapointCode -> ( ShortQuestionCode, ShortDatapointCode )
splitQuestionAndDatapointCode questionAndDatapointCode =
    let
        questionAndDatapointCode_ : String
        questionAndDatapointCode_ =
            XB2.Share.Data.Id.unwrap questionAndDatapointCode
    in
    case String.split "_" questionAndDatapointCode_ of
        [ shortQuestionCode, shortDatapointCode ] ->
            ( XB2.Share.Data.Id.fromString shortQuestionCode, XB2.Share.Data.Id.fromString shortDatapointCode )

        _ ->
            ( XB2.Share.Data.Id.fromString questionAndDatapointCode_, XB2.Share.Data.Id.fromString questionAndDatapointCode_ )


{-| We have a platform constraint related to datapoint codes for `"waves"` question
having an underscore (`_`) thus making them need to have it when doing any request with
them in the BE. This means that we can't use the `splitQuestionAndDatapointCode` normally
as it would always split by `_` so we check first if we're doing the split for a
`"waves"` question.
-}
splitQuestionAndDatapointCodeCheckingWavesQuestion :
    QuestionAndDatapointCode
    -> ShortQuestionCode
    -> ( ShortQuestionCode, ShortDatapointCode )
splitQuestionAndDatapointCodeCheckingWavesQuestion questionAndDatapointCode questionCode =
    if XB2.Share.Data.Id.unwrap questionCode == "waves" then
        ( questionCode, XB2.Share.Data.Id.fromString <| XB2.Share.Data.Id.unwrap questionAndDatapointCode )

    else
        splitQuestionAndDatapointCode questionAndDatapointCode


addQuestionToDatapointCode : ShortQuestionCode -> DatapointAndSuffixCode -> ( QuestionAndDatapointCode, Maybe Suffix.Code )
addQuestionToDatapointCode questionCode dpAndSuffixCode =
    let
        questionCode_ : String
        questionCode_ =
            XB2.Share.Data.Id.unwrap questionCode

        dpAndSuffixCode_ : String
        dpAndSuffixCode_ =
            XB2.Share.Data.Id.unwrap dpAndSuffixCode
    in
    case questionCode_ of
        "waves" ->
            ( XB2.Share.Data.Id.fromString dpAndSuffixCode_, Nothing )

        _ ->
            case String.split "_" dpAndSuffixCode_ of
                [ shortDpCode, suffixCode ] ->
                    ( XB2.Share.Data.Id.fromString <| questionCode_ ++ "_" ++ shortDpCode
                      -- TODO: Converting to String makes us lose the type safety of Suffix.Code
                    , Suffix.codeFromString suffixCode
                    )

                _ ->
                    ( XB2.Share.Data.Id.fromString <| questionCode_ ++ "_" ++ dpAndSuffixCode_
                    , Nothing
                    )


addSuffixToDatapointCode : ShortQuestionCode -> Maybe Suffix.Code -> QuestionAndDatapointCode -> DatapointAndSuffixCode
addSuffixToDatapointCode shortQuestionCode maybeSuffixCode questionAndDatapointCode =
    let
        questionAndDatapointCode_ : String
        questionAndDatapointCode_ =
            XB2.Share.Data.Id.unwrap questionAndDatapointCode
    in
    case XB2.Share.Data.Id.unwrap shortQuestionCode of
        "waves" ->
            XB2.Share.Data.Id.fromString questionAndDatapointCode_

        _ ->
            -- TODO we could check whether the argument question code == the questionCode we split?
            case String.split "_" questionAndDatapointCode_ of
                [ _, shortDatapointCode ] ->
                    case maybeSuffixCode of
                        Nothing ->
                            XB2.Share.Data.Id.fromString shortDatapointCode

                        Just suffixCode ->
                            XB2.Share.Data.Id.fromString <| shortDatapointCode ++ "_" ++ Suffix.codeToString suffixCode

                _ ->
                    -- weird
                    XB2.Share.Data.Id.fromString questionAndDatapointCode_



-- LINEAGES


type alias NamespaceLineage =
    { ancestors : List Namespace.Code
    , descendants : List Namespace.Code
    }


mergeLineage : Namespace.Code -> NamespaceLineage -> List Namespace.Code
mergeLineage currentNamespace { ancestors, descendants } =
    currentNamespace
        :: ancestors
        ++ descendants


lineageDecoder : Decoder NamespaceLineage
lineageDecoder =
    let
        idsAsObjectKeysDecoder : Decoder (List Namespace.Code)
        idsAsObjectKeysDecoder =
            Decode.keyValuePairs (Decode.succeed ())
                |> Decode.map (List.map (Tuple.first >> Namespace.codeFromString))
    in
    Decode.succeed NamespaceLineage
        |> Decode.andMap (Decode.field "ancestors" idsAsObjectKeysDecoder)
        |> Decode.andMap (Decode.field "descendants" idsAsObjectKeysDecoder)


getLineage : Namespace.Code -> Flags -> HttpCmd Never NamespaceLineage
getLineage namespaceCode flags =
    Http.request
        { method = "GET"
        , headers =
            [ Auth.header flags.token ]
        , url =
            Url.Builder.crossOrigin (host flags)
                [ "v1", "surveys", "lineage", "by_namespace", Namespace.codeToString namespaceCode ]
                []
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity lineageDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


compatibleNamespaces : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage) -> Namespace.Code -> WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
compatibleNamespaces lineages namespaceCode =
    Dict.Any.get namespaceCode lineages
        |> Maybe.withDefault NotAsked
        |> RemoteData.map (mergeLineage namespaceCode >> Set.Any.fromList Namespace.codeToString)


compatibleNamespacesWithAll : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage) -> List Namespace.Code -> WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
compatibleNamespacesWithAll lineages namespaceCodes =
    namespaceCodes
        |> List.map (compatibleNamespaces lineages)
        |> List.combineRemoteData
        |> RemoteData.map
            (\compatibles ->
                let
                    all : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
                    all =
                        List.foldl Set.Any.union (Set.Any.empty Namespace.codeToString) compatibles
                in
                List.foldl Set.Any.intersect all compatibles
            )


compatibleTopLevelNamespaces : Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage) -> List Namespace.Code -> WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
compatibleTopLevelNamespaces lineages namespaceCodes =
    let
        mergeAncestorsOnlyLineage : Namespace.Code -> NamespaceLineage -> List Namespace.Code
        mergeAncestorsOnlyLineage currentNamespace { ancestors } =
            currentNamespace :: ancestors

        compatibleAncestorsNamespaces : Namespace.Code -> WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
        compatibleAncestorsNamespaces namespaceCode =
            Dict.Any.get namespaceCode lineages
                |> Maybe.withDefault NotAsked
                |> RemoteData.map (mergeAncestorsOnlyLineage namespaceCode >> Set.Any.fromList Namespace.codeToString)
    in
    namespaceCodes
        |> List.map compatibleAncestorsNamespaces
        |> List.combineRemoteData
        |> RemoteData.map
            (\compatibles ->
                let
                    all : Set.Any.AnySet Namespace.StringifiedCode Namespace.Code
                    all =
                        List.foldl Set.Any.union (Set.Any.empty Namespace.codeToString) compatibles
                in
                List.foldl Set.Any.intersect all compatibles
            )


{-| Useful for knowing whether eg. a selection of XB rows/cols is mutually
incompatible and thus we can't affix anything to it because it will either be
incompatible with one or with the other.
-}
areNamespacesIncompatibleOrUnknown :
    Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> List Namespace.Code
    -> Bool
areNamespacesIncompatibleOrUnknown lineages usedNamespaceCodes =
    let
        compatibleNamespaces_ : WebData (Set.Any.AnySet Namespace.StringifiedCode Namespace.Code)
        compatibleNamespaces_ =
            compatibleNamespacesWithAll lineages usedNamespaceCodes
    in
    case compatibleNamespaces_ of
        Success list ->
            Set.Any.isEmpty list

        _ ->
            True


wavesByYears : IdDict WaveCodeTag Wave -> Dict WaveYear (List Wave)
wavesByYears waves =
    waves
        |> Dict.Any.filter (always .accessible)
        |> getWavesSortedLeastRecentFirst
        |> List.gatherWith (\a b -> waveYear a == waveYear b)
        |> List.map
            (\( first, restList ) ->
                let
                    wavesInsideYear =
                        (first :: restList)
                            |> List.reverseSortBy
                                (\wave ->
                                    ( Time.posixToMillis wave.startDate
                                    , Time.posixToMillis wave.endDate
                                    )
                                )
                in
                ( waveYear first, wavesInsideYear )
            )
        |> Dict.fromList


locationsByRegions : IdDict LocationCodeTag Location -> AnyDict Int RegionCode (List Location)
locationsByRegions locations =
    let
        groupLocationsByRegion : List Location -> AnyDict Int RegionCode (List Location)
        groupLocationsByRegion locations_ =
            [ Euro, Americas, Mea, Apac ]
                |> List.map
                    (\code ->
                        ( code
                        , List.filter ((==) code << .region) locations_
                            |> List.sortBy .name
                        )
                    )
                |> List.filter (Tuple.second >> List.isEmpty >> not)
                |> Dict.Any.fromList comparableRegionCode
    in
    locations
        |> Dict.Any.filter (always .accessible)
        |> Dict.Any.values
        |> groupLocationsByRegion


p2Separator : String
p2Separator =
    " » "
