module XB2.Share.Data.Platform2 exposing
    ( Attribute
    , AttributeCodes
    , AttributeTaxonomyPath
    , ChartFolder
    , ChartFolderId
    , ChartFolderIdTag
    , CompatibilitiesMetadata
    , DatasetFolder(..)
    , DatasetFolderData
    , DatasetFolderId
    , DatasetFolderIdTag
    , FullUserEmail
    , Incompatibilities
    , Incompatibility
    , OrganisationId
    , OrganisationIdTag
    , Segment
    , SegmentId
    , SegmentIdTag
    , Splitter
    , SplitterCode
    , SplitterCodeTag
    , Taxonomy
    , Timezone
    , TimezoneCode
    , TimezoneCodeTag
    , UserEmailId
    , UserEmailIdTag
    , attributeDecoder
    , attributeToString
    , createAudienceWithExpression
    , datasetCodesForNamespaceCodes
    , datasetsForNamespace
    , datasetsFromExpression
    , deepestNamespaceCode
    , encodeAttribute
    , encodeUnwrappedAttribute
    , fetchFullUserEmails
    , getAudienceFolders
    , getDatasetFolders
    , getDatasets
    , splitAttributeLabel
    )

import AssocSet
import BiDict.Assoc as BiDict exposing (BiDict)
import Dict.Any exposing (AnyDict)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra as Decode
import Json.Encode as Encode
import Json.Encode.Extra as Encode
import Maybe.Extra as Maybe
import RemoteData exposing (RemoteData(..), WebData)
import Set.Any exposing (AnySet)
import Time exposing (Posix)
import Url.Builder
import XB2.Data.Audience as Audience
import XB2.Data.Audience.Expression as Expression exposing (Expression)
import XB2.Data.Audience.Flag as AudienceFlag
import XB2.Data.Audience.Folder as AudienceFolder
import XB2.Data.Dataset as Dataset
import XB2.Data.Namespace as Namespace
import XB2.Data.Suffix as Suffix
import XB2.Share.Config exposing (Flags)
import XB2.Share.Config.Main
import XB2.Share.Data.Auth as Auth
import XB2.Share.Data.Id as Id exposing (Id)
import XB2.Share.Data.Labels
    exposing
        ( LocationCode
        , NamespaceLineage
        , ShortDatapointCode
        , ShortQuestionCode
        , WaveCode
        )
import XB2.Share.Gwi.Http exposing (HttpCmd)
import XB2.Share.Gwi.List as List


host : Flags -> String
host =
    .env >> XB2.Share.Config.Main.get >> .uri >> .api



-- AUDIENCE FOLDERS


{-| Swagger file: <https://github.com/GlobalWebIndex/core-next/blob/master/services/saved-data/swagger/audiences_folders.yaml#L18>
-}
getAudienceFolders : Flags -> HttpCmd Never (List AudienceFolder.Folder)
getAudienceFolders flags =
    Http.request
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url = host flags ++ "/v2/audiences/saved/folders"
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.field "data" (Decode.list AudienceFolder.decoder))
        , timeout = Nothing
        , tracker = Nothing
        }



-- AUDIENCES


createAudienceWithExpression : String -> Expression -> Flags -> HttpCmd Never Audience.Audience
createAudienceWithExpression audienceName expression flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2", "audiences", "saved" ] []
        , body =
            [ ( "name", Encode.string audienceName )
            , ( "flags", Encode.list (AudienceFlag.toString >> Encode.string) [ AudienceFlag.IsP2Audience ] )
            , ( "expression", Expression.encode expression )
            , ( "datasets", Encode.list identity [] ) -- autofill on BE
            ]
                |> Encode.object
                |> Http.jsonBody
        , expect = XB2.Share.Gwi.Http.expectJson identity Audience.decoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- SPLITTERS


type SegmentIdTag
    = SegmentIdTag


{-| SegmentId == QuestionAndDatapointCode, but for clarity we keep it separate.
There are casting functions available below.
-}
type alias SegmentId =
    Id SegmentIdTag


type alias Segment =
    { id : SegmentId
    , name : String
    , accessible : Bool
    }


type SplitterCodeTag
    = SplitterCodeTag


type alias SplitterCode =
    Id SplitterCodeTag


type alias Splitter =
    { code : SplitterCode
    , name : String
    , segments : List Segment
    , accessible : Bool
    , position : Int
    }



-- ATTRIBUTES


type alias AttributeTaxonomyPath =
    { taxonomyPath : List Taxonomy
    , dataset : Maybe Dataset.Dataset
    }


type alias Taxonomy =
    { id : String
    , name : String
    , order : Float
    , height : Int
    }


type alias Attribute =
    { namespaceCode : Namespace.Code
    , codes : AttributeCodes
    , questionName : String
    , datapointName : String
    , suffixName : Maybe String
    , questionDescription : Maybe String
    , order : Float
    , compatibilitiesMetadata : Maybe CompatibilitiesMetadata
    , taxonomyPaths : Maybe (List AttributeTaxonomyPath)

    -- A custom field not present in the wcs intercom that we use to handle Exclusions in Crosstabs.
    , isExcluded : Bool
    , metadata : Maybe Expression.Metadata
    }


type alias CompatibilitiesMetadata =
    { hasIncompatibilities : Bool
    , hasCompatibilities : Bool
    }


type alias AttributeCodes =
    { datapointCode : ShortDatapointCode
    , questionCode : ShortQuestionCode
    , suffixCode : Maybe Suffix.Code
    }


attributeToString : Attribute -> String
attributeToString { codes } =
    [ Id.unwrap codes.questionCode
    , Id.unwrap codes.datapointCode
    , Maybe.unwrap "" Suffix.codeToString codes.suffixCode
    ]
        |> String.join "--"


encodeAttributeTaxonomyPath : AttributeTaxonomyPath -> Encode.Value
encodeAttributeTaxonomyPath taxonomyPath =
    Encode.object
        [ ( "taxonomy_path", encodeTaxonomyList taxonomyPath.taxonomyPath )
        , ( "dataset", Encode.maybe Dataset.encodeForWebcomponent taxonomyPath.dataset )
        ]


encodeTaxonomy : Taxonomy -> Encode.Value
encodeTaxonomy taxonomy =
    Encode.object
        [ ( "height", Encode.int taxonomy.height )
        , ( "id", Encode.string taxonomy.id )
        , ( "name", Encode.string taxonomy.name )
        , ( "order", Encode.float taxonomy.order )
        ]


encodeTaxonomyList : List Taxonomy -> Encode.Value
encodeTaxonomyList taxonomies =
    Encode.list encodeTaxonomy taxonomies


encodeCompatibilitiesMetadata : CompatibilitiesMetadata -> Encode.Value
encodeCompatibilitiesMetadata metadata =
    Encode.object
        [ ( "has_compatibilities", Encode.bool metadata.hasCompatibilities )
        , ( "has_incompatibilities", Encode.bool metadata.hasIncompatibilities )
        ]


encodeAttribute : { isStaged : Bool, isCalculated : Bool } -> Attribute -> Encode.Value
encodeAttribute { isStaged, isCalculated } attr =
    Encode.object
        [ ( "compatibleAttribute"
          , [ ( "question_label", Encode.string attr.questionName )
            , ( "datapoint_label", Encode.string attr.datapointName )
            , ( "suffix_label"
              , Maybe.unwrap (Encode.string "") Encode.string attr.suffixName
              )
            , ( "namespace_code", Namespace.encodeCode attr.namespaceCode )
            , ( "question_code", Id.encode attr.codes.questionCode )
            , ( "datapoint_code", Id.encode attr.codes.datapointCode )
            , ( "suffix_code"
              , Maybe.unwrap (Encode.string "") Suffix.encodeCodeAsString attr.codes.suffixCode
              )
            , ( "question_description"
              , Maybe.unwrap Encode.null Encode.string attr.questionDescription
              )
            , ( "order", Encode.float attr.order )
            , ( "compatibilities_metadata"
              , Maybe.unwrap Encode.null
                    encodeCompatibilitiesMetadata
                    attr.compatibilitiesMetadata
              )
            , ( "taxonomy_paths"
              , Maybe.unwrap Encode.null
                    (Encode.list encodeAttributeTaxonomyPath)
                    attr.taxonomyPaths
              )
            ]
                |> Encode.object
          )
        , ( "isStaged", Encode.bool isStaged )
        , ( "isCalculated", Encode.bool isCalculated )
        ]


encodeUnwrappedAttribute : Attribute -> Encode.Value
encodeUnwrappedAttribute attr =
    Encode.object
        [ ( "question_label", Encode.string attr.questionName )
        , ( "datapoint_label", Encode.string attr.datapointName )
        , ( "suffix_label"
          , Maybe.unwrap (Encode.string "") Encode.string attr.suffixName
          )
        , ( "namespace_code", Namespace.encodeCode attr.namespaceCode )
        , ( "question_code", Id.encode attr.codes.questionCode )
        , ( "datapoint_code", Id.encode attr.codes.datapointCode )
        , ( "suffix_code"
          , Maybe.unwrap (Encode.string "") Suffix.encodeCodeAsString attr.codes.suffixCode
          )
        , ( "question_description"
          , Maybe.unwrap Encode.null Encode.string attr.questionDescription
          )
        , ( "order", Encode.float attr.order )
        , ( "compatibilities_metadata"
          , Maybe.unwrap Encode.null
                encodeCompatibilitiesMetadata
                attr.compatibilitiesMetadata
          )
        , ( "taxonomy_paths"
          , Maybe.unwrap Encode.null
                (Encode.list encodeAttributeTaxonomyPath)
                attr.taxonomyPaths
          )
        ]


attributeLabelDelimiter : String
attributeLabelDelimiter =
    "»"


splitAttributeLabel :
    String
    ->
        Maybe
            { questionLabel : String
            , datapointLabel : Maybe String
            , suffixLabel : Maybe String
            }
splitAttributeLabel attributeLabel =
    {- This whole function is a giant fragile hack as we are trying to get
       names for question/datapoints/suffix from the P2 attribute label with
       splitting it by "»" from

       "Frequency of Drinks Consumption » Rum » At least once a month"

       These data should be given to us by the P2 BE endpoint instead but they
       are not. If there will be any problem with this piece of code it should
       be solved on the P2 side first.
    -}
    String.split attributeLabelDelimiter attributeLabel
        |> List.map String.trim
        |> (\labels ->
                case labels of
                    [ question, datapoint, suffix ] ->
                        Just
                            { questionLabel = question
                            , datapointLabel = Just datapoint
                            , suffixLabel = Just suffix
                            }

                    [ question, datapoint ] ->
                        Just
                            { questionLabel = question
                            , datapointLabel = Just datapoint
                            , suffixLabel = Nothing
                            }

                    [ question ] ->
                        Just
                            { questionLabel = question
                            , datapointLabel = Nothing
                            , suffixLabel = Nothing
                            }

                    _ ->
                        Nothing
           )


attributeTaxonomyPathDecoder : Decoder AttributeTaxonomyPath
attributeTaxonomyPathDecoder =
    Decode.succeed AttributeTaxonomyPath
        |> Decode.andMap
            (Decode.field "taxonomy_path"
                (Decode.list <|
                    Decode.lazy
                        (\_ ->
                            Decode.succeed Taxonomy
                                |> Decode.andMap (Decode.field "id" Decode.string)
                                |> Decode.andMap (Decode.field "name" Decode.string)
                                |> Decode.andMap (Decode.field "order" Decode.float)
                                |> Decode.andMap (Decode.field "height" Decode.int)
                        )
                )
                |> Decode.maybe
                |> Decode.map (Maybe.withDefault [])
            )
        |> Decode.andMap (Decode.maybe (Decode.field "dataset" Dataset.decoder))


emptyStringAsNothing : (String -> a) -> String -> Maybe a
emptyStringAsNothing toExpectedType s =
    if String.isEmpty s then
        Nothing

    else
        Just <| toExpectedType s


attributeDecoder : Decoder Attribute
attributeDecoder =
    Decode.field "compatibleAttribute"
        (Decode.succeed Attribute
            |> Decode.andMap (Decode.field "namespace_code" Namespace.codeDecoder)
            |> Decode.andMap attributeCodesDecoder
            |> Decode.andMap (Decode.field "question_label" Decode.string)
            |> Decode.andMap (Decode.field "datapoint_label" Decode.string)
            |> Decode.andMap
                (Decode.optionalNullableField "suffix_label" Decode.string
                    |> Decode.map (Maybe.andThen (emptyStringAsNothing identity))
                )
            |> Decode.andMap (Decode.maybe (Decode.field "question_description" Decode.string))
            |> Decode.andMap (Decode.field "order" Decode.float)
            |> Decode.andMap (Decode.maybe (Decode.field "compatibilities_metadata" compatibilitiesMetadataDecoder))
            |> Decode.andMap (Decode.optionalField "taxonomy_paths" <| Decode.list attributeTaxonomyPathDecoder)
            -- From the start it is never excluded
            |> Decode.andMap (Decode.succeed False)
            |> Decode.andMap (Decode.maybe (Decode.field "metadata" Expression.metadataDecoder))
        )


compatibilitiesMetadataDecoder : Decoder CompatibilitiesMetadata
compatibilitiesMetadataDecoder =
    Decode.succeed CompatibilitiesMetadata
        |> Decode.andMap (Decode.field "has_incompatibilities" Decode.bool)
        |> Decode.andMap (Decode.field "has_compatibilities" Decode.bool)


attributeCodesDecoder : Decoder AttributeCodes
attributeCodesDecoder =
    Decode.succeed AttributeCodes
        |> Decode.andMap (Decode.field "datapoint_code" Id.decode)
        |> Decode.andMap (Decode.field "question_code" Id.decode)
        |> Decode.andMap
            (Decode.optionalField "suffix_code" Decode.string
                |> Decode.map (Maybe.andThen Suffix.codeFromString)
            )



-- Datasets


getDatasets : Flags -> HttpCmd Never (List Dataset.Dataset)
getDatasets flags =
    Http.request
        { method = "GET"
        , headers =
            [ Auth.header flags.token ]
        , url = host flags ++ "/platform/datasets"
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity Dataset.listDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- Datasets folders


type DatasetFolderIdTag
    = DatasetFolderIdTag


type alias DatasetFolderId =
    Id DatasetFolderIdTag


type alias DatasetFolderData =
    { id : DatasetFolderId
    , name : String
    , description : String
    , order : Float
    , datasetCodes : List Dataset.Code
    , subfolders : List DatasetFolder
    }


type DatasetFolder
    = DatasetFolder DatasetFolderData


datasetFolderDecoder : Decoder DatasetFolder
datasetFolderDecoder =
    (Decode.succeed DatasetFolderData
        |> Decode.andMap (Decode.field "id" Id.decodeFromStringOrInt)
        |> Decode.andMap (Decode.field "name" Decode.string)
        |> Decode.andMap (Decode.field "description" Decode.string)
        |> Decode.andMap (Decode.field "order" Decode.float)
        |> Decode.andMap
            (Decode.optionalField "child_datasets" (Decode.list <| Decode.field "code" Dataset.codeDecoder)
                |> Decode.map (Maybe.withDefault [])
            )
        |> Decode.andMap
            (Decode.optionalField "child_folders" (Decode.list <| Decode.lazy (\_ -> datasetFolderDecoder))
                |> Decode.map (Maybe.withDefault [])
            )
    )
        |> Decode.map DatasetFolder


getDatasetFolders : Flags -> HttpCmd Never (List DatasetFolder)
getDatasetFolders flags =
    Http.request
        { method = "GET"
        , headers = [ Auth.header flags.token ]
        , url = host flags ++ "/platform/dataset-folders"
        , body = Http.emptyBody
        , expect = XB2.Share.Gwi.Http.expectJson identity (Decode.list datasetFolderDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }



-- CHART FOLDERS


type alias ChartFolderId =
    Id ChartFolderIdTag


type ChartFolderIdTag
    = ChartFolderIdTag


type alias ChartFolder =
    { id : ChartFolderId
    , name : String
    , userId : Int
    , createdAt : Posix
    , updatedAt : Posix
    }



-- CHARTS


type alias Incompatibility =
    { locationCode : LocationCode
    , waveCodes : AnySet String WaveCode
    }


type alias Incompatibilities =
    AnyDict String LocationCode Incompatibility


findDeepestDataset :
    List Dataset.Code
    -> WebData (Dict.Any.AnyDict Dataset.StringifiedCode Dataset.Code Dataset.Dataset)
    -> Maybe Dataset.Dataset
findDeepestDataset usedDatasets allDatasets =
    (case allDatasets of
        Success datasetStore ->
            List.filterMap (\datasetCode -> Dict.Any.get datasetCode datasetStore) usedDatasets

        _ ->
            []
    )
        |> List.reverseSortBy .depth
        |> List.head


deepestDatasetNamespaceCode :
    List Dataset.Code
    -> WebData (Dict.Any.AnyDict Dataset.StringifiedCode Dataset.Code Dataset.Dataset)
    -> Maybe Namespace.Code
deepestDatasetNamespaceCode usedDatasets allDatasets =
    findDeepestDataset usedDatasets allDatasets
        |> Maybe.map .baseNamespaceCode


{-| Normally this would be just a matter of finding a dataset that has the
namespace code as `baseNamespaceCode` (hence the BiDict), but we're not
guaranteed that a namespace _will_ be used by some dataset as a base namespace.

If we don't find a dataset here, we need to move to the nearest ancestor and try
again. For that we need the namespace lineage to be fetched.

-}
datasetsForNamespace :
    BiDict Dataset.Code Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> Namespace.Code
    -> WebData (Set.Any.AnySet Dataset.StringifiedCode Dataset.Code)
datasetsForNamespace datasetsToNamespaces lineages namespaceCode =
    let
        simple : Namespace.Code -> Set.Any.AnySet Dataset.StringifiedCode Dataset.Code
        simple nsCode =
            datasetsToNamespaces
                |> BiDict.getReverse nsCode
                |> AssocSet.toList
                |> Set.Any.fromList Dataset.codeToString

        recursive :
            List Namespace.Code
            -> Namespace.Code
            -> WebData (Set.Any.AnySet Dataset.StringifiedCode Dataset.Code)
        recursive ancestors_ nsCode =
            let
                simple_ =
                    simple nsCode
            in
            if Set.Any.isEmpty simple_ then
                case ancestors_ of
                    closestAncestor :: restOfAncestors ->
                        recursive restOfAncestors closestAncestor

                    [] ->
                        Success (Set.Any.empty Dataset.codeToString)

            else
                Success simple_

        ancestors : WebData (List Namespace.Code)
        ancestors =
            Dict.Any.get namespaceCode lineages
                |> Maybe.withDefault NotAsked
                |> RemoteData.map .ancestors
    in
    ancestors
        |> RemoteData.map ((::) namespaceCode)
        |> RemoteData.andThen (\ancestors_ -> recursive ancestors_ namespaceCode)


type OrganisationIdTag
    = OrganisationIdTag


type alias OrganisationId =
    Id OrganisationIdTag


type UserEmailIdTag
    = UserEmailIdTag


type alias UserEmailId =
    Id UserEmailIdTag


type alias FullUserEmail =
    { id : UserEmailId
    , email : String
    , firstName : String
    , lastName : String
    }


fetchFullUserEmails : String -> Flags -> HttpCmd Never (List FullUserEmail)
fetchFullUserEmails term flags =
    Http.request
        { method = "POST"
        , headers = [ Auth.header flags.token ]
        , url = Url.Builder.crossOrigin (host flags) [ "v2", "users", "suggest" ] []
        , body = Http.jsonBody <| Encode.object [ ( "hint", Encode.string term ), ( "limit", Encode.int 3 ) ]
        , expect = XB2.Share.Gwi.Http.expectJson identity fullUserEmailsDecoder
        , tracker = Nothing
        , timeout = Nothing
        }


fullUserEmailsDecoder : Decoder (List FullUserEmail)
fullUserEmailsDecoder =
    Decode.optionalField "users"
        (Decode.list
            (Decode.succeed FullUserEmail
                |> Decode.andMap (Decode.field "id" Id.decodeFromInt)
                |> Decode.andMap (Decode.field "email" Decode.string)
                |> Decode.andMap (Decode.field "first_name" Decode.string)
                |> Decode.andMap (Decode.field "last_name" Decode.string)
            )
        )
        |> Decode.map (Maybe.withDefault [])



-- Timezones


type TimezoneCodeTag
    = TimezoneCodeTag


{-| TimezoneCode == QuestionAndDatapointCode, but for clarity we keep it separate.
There are casting functions available below.
-}
type alias TimezoneCode =
    Id TimezoneCodeTag


type alias Timezone =
    { code : TimezoneCode
    , name : String
    , position : Int
    }


datasetCodesForNamespaceCodes :
    BiDict Dataset.Code Namespace.Code
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> List Namespace.Code
    -> WebData (List Dataset.Code)
datasetCodesForNamespaceCodes datasetsToNamespaces lineages namespaceCodes =
    XB2.Share.Data.Labels.compatibleTopLevelNamespaces lineages namespaceCodes
        |> RemoteData.map
            (\compatibleNamespacesSet ->
                compatibleNamespacesSet
                    |> Set.Any.toList
                    |> List.map (datasetsForNamespace datasetsToNamespaces lineages)
                    {- We might later find out we need to load all the
                       NotAsked resulting from ↑ (ensure they are all
                       Successes) instead of filtering them out ↓ ... but
                       for now this seems to work.
                    -}
                    |> List.remoteDataValues
                    |> List.foldl Set.Any.union (Set.Any.empty Dataset.codeToString)
                    |> Set.Any.toList
            )


datasetsFromExpression : BiDict Dataset.Code Namespace.Code -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage) -> Expression -> WebData (List Dataset.Code)
datasetsFromExpression datasetsToNamespaces lineages expression =
    expression
        |> Expression.getNamespaceCodes
        |> datasetCodesForNamespaceCodes datasetsToNamespaces lineages


deepestNamespaceCode :
    WebData (Dict.Any.AnyDict Dataset.StringifiedCode Dataset.Code Dataset.Dataset)
    -> WebData (BiDict Dataset.Code Namespace.Code)
    -> Dict.Any.AnyDict Namespace.StringifiedCode Namespace.Code (WebData NamespaceLineage)
    -> Namespace.Code
    -> Maybe Namespace.Code
deepestNamespaceCode datasets datasetsToNamespaces lineages namespaceCode =
    let
        namespaceDatasets : WebData (List Dataset.Code)
        namespaceDatasets =
            datasetsToNamespaces
                |> RemoteData.andThen
                    (\datasetsToNamespaces_ ->
                        datasetsForNamespace
                            datasetsToNamespaces_
                            lineages
                            namespaceCode
                    )
                |> RemoteData.map Set.Any.toList
    in
    namespaceDatasets
        |> RemoteData.toMaybe
        |> Maybe.andThen
            (\usedDatasets ->
                deepestDatasetNamespaceCode
                    usedDatasets
                    datasets
            )
