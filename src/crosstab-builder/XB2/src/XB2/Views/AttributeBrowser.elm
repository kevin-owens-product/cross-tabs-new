module XB2.Views.AttributeBrowser exposing
    ( Average(..)
    , AverageDatapointInfo
    , AverageQuestion
    , Config
    , ItemType(..)
    , Warning
    , WarningNote
    , XBItem
    , getAverageDatapointCode
    , getAverageQuestion
    , getAverageQuestionCode
    , getAverageQuestionLabel
    , getXBItemFromAttribute
    , view
    )

import Dict.Any
import Html exposing (Html)
import Html.Attributes as Attrs
import Html.Events as Events
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode
import List.NonEmpty as NonEmpty exposing (NonEmpty)
import Maybe.Extra as Maybe
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.Caption as Caption exposing (Caption)
import XB2.Data.Namespace as Namespace
import XB2.Data.Zod.Optional as Optional
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main exposing (Uri)
import XB2.Share.Data.Id exposing (IdDict, IdSet)
import XB2.Share.Data.Labels
    exposing
        ( Location
        , LocationCodeTag
        , NamespaceAndQuestionCode
        , QuestionAndDatapointCode
        , QuestionAveragesUnit
        , ShortQuestionCode
        , Wave
        , WaveCodeTag
        )
import XB2.Share.Data.Platform2
    exposing
        ( Attribute
        , Dataset
        )


type alias Config msg =
    -- msgs
    { noOp : msg
    , toggleAttributes : List Attribute -> msg
    , addAttributes : List Attribute -> msg
    , loadingAttributes : Bool -> msg
    , toggleAverage : Average -> msg
    , setDecodingError : String -> msg
    , warningNoteOpened : WarningNote -> msg
    , gotStateSnapshot : Encode.Value -> msg

    -- store
    , waves : IdDict WaveCodeTag Wave
    , locations : IdDict LocationCodeTag Location
    , activeWaves : IdSet WaveCodeTag
    , activeLocations : IdSet LocationCodeTag

    -- config
    , canUseAverage : Bool
    , selectedAttributes : List Attribute
    , selectedAverages : List Average
    , selectedDatasets : List Dataset

    -- metadata modal
    , prerequestedAttribute : Maybe Attribute
    }


type alias AverageQuestion =
    { questionCode : ShortQuestionCode
    , namespaceCode : Namespace.Code
    , averagesUnit : QuestionAveragesUnit
    , questionLabel : String
    }


type alias AverageDatapointInfo =
    { datapointCode : QuestionAndDatapointCode
    , datapointLabel : String
    }


type Average
    = AvgWithoutSuffixes AverageQuestion
    | AvgWithSuffixes AverageQuestion AverageDatapointInfo


getAverageQuestion : Average -> AverageQuestion
getAverageQuestion avg =
    case avg of
        AvgWithoutSuffixes q ->
            q

        AvgWithSuffixes q _ ->
            q


getAverageQuestionCode : Average -> NamespaceAndQuestionCode
getAverageQuestionCode avg =
    case avg of
        AvgWithoutSuffixes { namespaceCode, questionCode } ->
            XB2.Share.Data.Labels.addNamespaceToQuestionCode namespaceCode questionCode

        AvgWithSuffixes { namespaceCode, questionCode } _ ->
            XB2.Share.Data.Labels.addNamespaceToQuestionCode namespaceCode questionCode


getAverageQuestionLabel : Average -> String
getAverageQuestionLabel avg =
    case avg of
        AvgWithoutSuffixes { questionLabel } ->
            questionLabel

        AvgWithSuffixes { questionLabel } { datapointLabel } ->
            questionLabel ++ XB2.Share.Data.Labels.p2Separator ++ datapointLabel


getAverageDatapointCode : Average -> Maybe QuestionAndDatapointCode
getAverageDatapointCode avg =
    case avg of
        AvgWithoutSuffixes _ ->
            Nothing

        AvgWithSuffixes _ { datapointCode } ->
            Just datapointCode


type alias XBItem =
    { caption : Caption
    , expression : Expression
    , itemType : ItemType
    }


type alias Warning =
    { locationsText : Maybe String
    , waveNames : List String
    }


type alias WarningNote =
    { title : String
    , warnings : Maybe (NonEmpty Warning)
    }


type ItemType
    = AttributeItem
    | AudienceItem
    | AverageItem


getXBItemFromAttribute :
    Attribute
    -> XBItem
getXBItemFromAttribute { codes, isExcluded, questionName, suffixName, datapointName, namespaceCode } =
    { caption =
        Caption.fromDatapoint
            { question = questionName
            , datapoint = Just datapointName
            , suffix = suffixName
            , isExcluded = isExcluded
            }
    , expression =
        Expression.FirstLevelLeaf
            { isExcluded = Optional.Present isExcluded
            , minCount = Optional.Present 1
            , namespaceAndQuestionCode =
                XB2.Share.Data.Labels.addNamespaceToQuestionCode
                    namespaceCode
                    codes.questionCode
            , questionAndDatapointCodes =
                NonEmpty.singleton
                    (XB2.Share.Data.Labels.addQuestionToShortDatapointCode
                        codes.questionCode
                        codes.datapointCode
                    )
            , suffixCodes =
                Maybe.unwrap Optional.Undefined
                    (NonEmpty.singleton >> Optional.Present)
                    codes.suffixCode
            }
    , itemType = AttributeItem
    }


view : Flags -> Config msg -> String -> Bool -> Html msg
view flags config initialState shouldPassInitialState =
    let
        appName =
            "CrosstabBuilder"

        uri : Uri
        uri =
            XB2.Share.Config.Main.get flags.env
                |> .uri

        apiEncoded =
            Encode.object
                [ ( "SERVICE_LAYER_HOST", Encode.string uri.serviceLayer )
                , ( "DEFAULT_HOST", Encode.string uri.api )
                , ( "ANALYTICS_HOST", Encode.string uri.analytics )
                , ( "COLLECTIONS_HOST", Encode.string uri.collections )
                ]

        userEncoded =
            Encode.object
                [ ( "token", Encode.string flags.token )
                , ( "email", Encode.string flags.user.email )
                ]

        encodedConfig =
            Encode.object
                [ ( "appName", Encode.string appName )
                , ( "environment", Encode.string <| XB2.Share.Config.Main.stageToString flags.env )
                , ( "api", apiEncoded )
                , ( "user", userEncoded )
                ]
                |> Encode.encode 0

        encodedWaves =
            config.waves
                |> Dict.Any.values
                |> Encode.list
                    (\wave ->
                        Encode.list identity
                            [ XB2.Share.Data.Id.encode wave.code
                            , Encode.object
                                [ ( "name", Encode.string wave.name )
                                , ( "code", XB2.Share.Data.Id.encode wave.code )
                                , ( "year", Encode.int <| XB2.Share.Data.Labels.waveYear wave )
                                ]
                            ]
                    )
                |> Encode.encode 0

        encodedLocations =
            config.locations
                |> Dict.Any.values
                |> Encode.list
                    (\location ->
                        Encode.list identity
                            [ XB2.Share.Data.Id.encode location.code
                            , Encode.object
                                [ ( "name", Encode.string location.name )
                                , ( "code", XB2.Share.Data.Id.encode location.code )
                                , ( "region"
                                  , Encode.object
                                        [ ( "code", Encode.string <| String.fromInt <| XB2.Share.Data.Labels.comparableRegionCode location.region )
                                        , ( "name", Encode.string <| XB2.Share.Data.Labels.regionName location.region )
                                        ]
                                  )
                                ]
                            ]
                    )
                |> Encode.encode 0

        addAllDecoder : Decoder (List Attribute)
        addAllDecoder =
            Decode.at [ "detail", "attributes" ] <|
                Decode.list XB2.Share.Data.Platform2.attributeDecoder

        addAllLoadingDecoder : Decoder Bool
        addAllLoadingDecoder =
            Decode.at [ "detail", "loadingData" ] Decode.bool

        warningsDecoder : Decoder (Maybe (NonEmpty Warning))
        warningsDecoder =
            Decode.list
                (Decode.succeed Warning
                    -- TODO: is there some sane way how to process `undefined`?
                    |> Decode.andMap (Decode.field "locationsText" (Decode.oneOf [ Decode.map Just Decode.string, Decode.succeed Nothing ]))
                    |> Decode.andMap (Decode.field "waveNames" (Decode.list Decode.string))
                )
                |> Decode.nullable
                |> Decode.map (Maybe.andThen NonEmpty.fromList)

        warningNoteDecoder : Decoder WarningNote
        warningNoteDecoder =
            Decode.at [ "detail", "detailedContent" ]
                (Decode.succeed WarningNote
                    |> Decode.andMap (Decode.field "title" Decode.string)
                    |> Decode.andMap (Decode.field "warnings" warningsDecoder)
                )

        toggleAveragesDecoder : Decoder Average
        toggleAveragesDecoder =
            Decode.succeed
                (\qCode unit namespace dpCode attributeLabel ->
                    { qCode = qCode
                    , unit = unit
                    , namespace = namespace
                    , dpCode = dpCode
                    , attributeLabel = attributeLabel
                    }
                )
                |> Decode.andMap (Decode.at [ "detail", "average", "question_code" ] XB2.Share.Data.Id.decode)
                |> Decode.andMap (Decode.at [ "detail", "average", "unit" ] XB2.Share.Data.Labels.averagesUnitDecoder)
                |> Decode.andMap (Decode.at [ "detail", "average", "namespace_code" ] Namespace.codeDecoder)
                |> Decode.andMap (Decode.at [ "detail", "average", "datapoint_code" ] (Decode.nullable XB2.Share.Data.Id.decode))
                |> Decode.andMap (Decode.at [ "detail", "average", "attribute_label" ] Decode.string)
                |> Decode.andThen
                    (\{ qCode, unit, namespace, dpCode, attributeLabel } ->
                        case XB2.Share.Data.Platform2.splitAttributeLabel attributeLabel of
                            Nothing ->
                                Decode.fail <|
                                    "Couldn't split attribute label '"
                                        ++ attributeLabel
                                        ++ "'to question name, datapoint name and suffix name."

                            Just labels ->
                                let
                                    averageQuestion =
                                        AverageQuestion qCode namespace unit labels.questionLabel
                                in
                                Decode.succeed <|
                                    case Maybe.map2 Tuple.pair labels.datapointLabel dpCode of
                                        Just ( datapointLabel, datapointCode ) ->
                                            let
                                                ( longDatapointCode, _ ) =
                                                    XB2.Share.Data.Labels.addQuestionToDatapointCode qCode datapointCode
                                            in
                                            AvgWithSuffixes
                                                averageQuestion
                                                { datapointCode = longDatapointCode
                                                , datapointLabel = datapointLabel
                                                }

                                        Nothing ->
                                            AvgWithoutSuffixes averageQuestion
                    )

        encodedStagedAttributes =
            config.selectedAttributes
                |> Encode.list
                    (XB2.Share.Data.Platform2.encodeAttribute
                        { isStaged = True
                        , isCalculated = True
                        }
                    )
                |> Encode.encode 0

        averageQuestionEncode : Maybe AverageDatapointInfo -> AverageQuestion -> Encode.Value
        averageQuestionEncode maybeDpInfo q =
            Encode.object
                [ ( "question_code", XB2.Share.Data.Id.encode q.questionCode )
                , ( "unit", XB2.Share.Data.Labels.encodeAveragesUnit q.averagesUnit )
                , ( "namespace_code", Namespace.encodeCode q.namespaceCode )
                , ( "datapoint_code"
                  , Maybe.unwrap
                        Encode.null
                        (.datapointCode
                            >> XB2.Share.Data.Labels.addSuffixToDatapointCode q.questionCode Nothing
                            >> XB2.Share.Data.Id.encode
                        )
                        maybeDpInfo
                  )
                ]

        encodedStagedAverages =
            config.selectedAverages
                |> Encode.list
                    (\average ->
                        case average of
                            AvgWithSuffixes question dpInfo ->
                                averageQuestionEncode (Just dpInfo) question

                            AvgWithoutSuffixes question ->
                                averageQuestionEncode Nothing question
                    )
                |> Encode.encode 0

        canUseAverageString =
            Encode.bool config.canUseAverage
                |> Encode.encode 0

        event eventName =
            appName ++ "-" ++ eventName

        encodedSelectedDatasets =
            config.selectedDatasets
                |> Encode.list
                    (\dataset ->
                        XB2.Share.Data.Platform2.encodeDatasetForWebcomponent dataset
                    )
                |> Encode.encode 0

        defaultToggleFilterValue : String
        defaultToggleFilterValue =
            Decode.decodeString (Decode.field "filtersEnabled" Decode.bool) initialState
                |> Result.withDefault False
                |> Encode.bool
                |> Encode.encode 0
    in
    Html.node "x-et-attribute-browser"
        ([ Attrs.attribute "x-env-values" encodedConfig
         , Attrs.attribute "calculated-attributes" "[]"
         , Attrs.attribute "is-modal-open" "true"
         , Attrs.attribute "default-toggle-filters-value" defaultToggleFilterValue
         , Attrs.attribute "toggle-filters-enable" "true"
         , Attrs.attribute "show-averages" canUseAverageString
         , Attrs.attribute "staged-attributes" encodedStagedAttributes
         , Attrs.attribute "staged-average-attributes" encodedStagedAverages
         , Attrs.attribute "all-waves" encodedWaves
         , Attrs.attribute "all-areas" encodedLocations
         , Attrs.attribute "selected-wave-codes" <| Encode.encode 0 <| XB2.Share.Data.Id.encodeSet config.activeWaves
         , Attrs.attribute "selected-location-ids" <| Encode.encode 0 <| XB2.Share.Data.Id.encodeSet config.activeLocations
         , Events.on (event "attributeBrowserLeftAttributesToggled")
            (Decode.value
                |> Decode.map
                    (\event_ ->
                        case Decode.decodeValue addAllDecoder event_ of
                            Ok decoded ->
                                config.toggleAttributes decoded

                            Err err ->
                                config.setDecodingError <| Decode.errorToString err
                    )
            )
         , Events.on (event "attributeBrowserLeftAttributesAdded")
            (Decode.value
                |> Decode.map
                    (Decode.decodeValue
                        (Decode.oneOf
                            [ Decode.map config.addAttributes addAllDecoder
                            , Decode.map config.loadingAttributes addAllLoadingDecoder
                            ]
                        )
                        >> Result.mapError (config.setDecodingError << Decode.errorToString)
                        >> Result.withDefault (config.setDecodingError "Error decoding {event}attributeBrowserLeftAttributesAdded")
                    )
            )
         , Events.on (event "attributeBrowserLeftAverageQuestionToggled")
            (Decode.value
                |> Decode.map
                    (\event_ ->
                        case Decode.decodeValue toggleAveragesDecoder event_ of
                            Ok decoded ->
                                config.toggleAverage decoded

                            Err err ->
                                config.setDecodingError <| Decode.errorToString err
                    )
            )
         , Events.on (event "attributeBrowserLeftWarningNoteOpened")
            (Decode.value
                |> Decode.map
                    (\event_ ->
                        case Decode.decodeValue warningNoteDecoder event_ of
                            Ok decoded ->
                                config.warningNoteOpened decoded

                            Err err ->
                                config.setDecodingError <| Decode.errorToString err
                    )
            )
         , Events.on (event "attributeBrowserLastStateSnapshotChanged")
            (Decode.at [ "detail", "lastStateSnapshot" ]
                (Decode.value
                    |> Decode.map
                        config.gotStateSnapshot
                )
            )
         ]
            ++ (if List.isEmpty config.selectedDatasets then
                    []

                else
                    [ Attrs.attribute "selected-datasets" encodedSelectedDatasets ]
               )
            ++ (if shouldPassInitialState then
                    {- We shouldn't pass it when we're affixing
                       TODO: Enforce this by type invariants.
                    -}
                    [ Attrs.attribute "initial-state" initialState ]

                else
                    []
               )
            ++ (case config.prerequestedAttribute of
                    Just attribute ->
                        [ Attrs.attribute "prerequested-attribute" (Encode.encode 0 <| XB2.Share.Data.Platform2.encodeUnwrappedAttribute attribute)
                        , Attrs.attribute "prerequested-attribute-selected-view" "notes"
                        ]

                    Nothing ->
                        []
               )
        )
        []
